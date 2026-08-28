import { computed, ref } from 'vue'

import {
  cancelDeveloperTask,
  getDeveloperTask,
  listDeveloperWorkspaces,
  rollbackDeveloperTask,
  startDeveloperTask,
  type DeveloperCommand,
  type DeveloperTask,
  type DeveloperWorkspace,
} from '../../services/developer'

import {
  editorProjectTree,
  editorRuntimeInfo,
  editorRunAction,
  editorSearchFiles,
  type EditorRuntimeInfo,
} from '../../services/vertex-editor'

export type ControlAction =
  | 'cargo_fmt'
  | 'cargo_check'
  | 'cargo_test'
  | 'git_status'
  | 'git_diff'
  | 'cargo_build'
  | 'cargo_build_release'
  | 'cargo_clippy'

export interface ChatMessage {
  id: string
  role: 'human' | 'hyperagent' | 'system'
  text: string
  at: string
}

const workspaces = ref<DeveloperWorkspace[]>([])
const workspaceId = ref('')
const runtimeInfo = ref<EditorRuntimeInfo | null>(null)

const rawTree = ref('')
const treeDepth = ref(7)
const treeFilter = ref('')
const remoteSearchResults = ref<string[]>([])

const activeFilePath = ref('')
const openFileRequest = ref({ token: 0, path: '' })
const workspaceRevision = ref(0)

const providerId = ref('ollama')
const modelId = ref('qwen3:8b')
const developerTask = ref<DeveloperTask | null>(null)

const busy = ref(false)
const actionBusy = ref('')
const lastError = ref('')

const controlOutputs = ref<Partial<Record<ControlAction, DeveloperCommand>>>({})
const chatMessages = ref<ChatMessage[]>([])

let initialized = false
let pollTimer = 0

const activities = computed(() => developerTask.value?.activities ?? [])
const commands = computed(() => developerTask.value?.commands ?? [])
const errors = computed(() => developerTask.value?.errors ?? [])
const taskDiff = computed(() => developerTask.value?.unified_diff ?? '')

const taskStateLabel = computed(() => {
  switch(developerTask.value?.state){
    case 'COMPLETED': return '完了'
    case 'FAILED': return '失敗'
    case 'CANCELLED': return '中止'
    case 'RUNNING': return '実行中'
    case 'PAUSED': return '一時停止'
    case 'BLOCKED': return '待機'
    case 'CREATED': return '作成済み'
    default: return '待機中'
  }
})

const taskTone = computed(() => {
  const state=developerTask.value?.state
  if(state==='COMPLETED') return 'green'
  if(state==='FAILED'||state==='CANCELLED') return 'red'
  if(state) return 'amber'
  return 'muted'
})

const parsedTree = computed(() =>
  rawTree.value
    .split(/\r?\n/)
    .map((line) => {
      const match=/^(\s*)\[(D|F)\]\s+(.+)$/.exec(line)
      if(!match) return null
      return {
        path: match[3],
        kind: match[2]==='D' ? 'directory' as const : 'file' as const,
        depth: Math.floor(match[1].length/2),
      }
    })
    .filter((value): value is {path:string;kind:'file'|'directory';depth:number} => Boolean(value))
)

const visibleTree = computed(() => {
  const q=treeFilter.value.trim().toLowerCase()
  return q
    ? parsedTree.value.filter((item)=>item.path.toLowerCase().includes(q))
    : parsedTree.value
})

function pushMessage(role: ChatMessage['role'], text: string){
  chatMessages.value.push({
    id:`${Date.now()}-${Math.random().toString(36).slice(2)}`,
    role,
    text,
    at:new Date().toLocaleTimeString(),
  })
  chatMessages.value=chatMessages.value.slice(-100)
}

async function ensureInitialized(){
  if(initialized) return

  lastError.value=''
  try{
    workspaces.value=await listDeveloperWorkspaces()
    if(!workspaceId.value && workspaces.value.length){
      workspaceId.value=workspaces.value[0].id
    }
    if(workspaceId.value){
      const [tree,info]=await Promise.all([
        editorProjectTree(workspaceId.value,treeDepth.value),
        editorRuntimeInfo(workspaceId.value),
      ])
      rawTree.value=tree
      runtimeInfo.value=info
    }
    initialized=true
  }catch(error){
    lastError.value=String(error)
    throw error
  }
}

async function refreshTree(){
  if(!workspaceId.value) return
  rawTree.value=await editorProjectTree(workspaceId.value,treeDepth.value)
}

async function changeWorkspace(id:string){
  workspaceId.value=id
  activeFilePath.value=''
  developerTask.value=null
  controlOutputs.value={}
  await refreshTree()
  runtimeInfo.value=await editorRuntimeInfo(workspaceId.value)
  workspaceRevision.value++
}

async function changeTreeDepth(depth:number){
  treeDepth.value=depth
  await refreshTree()
}

async function remoteSearch(query:string){
  treeFilter.value=query.trim()
  if(!workspaceId.value || !treeFilter.value){
    remoteSearchResults.value=[]
    return
  }
  const result=await editorSearchFiles(workspaceId.value,treeFilter.value)
  remoteSearchResults.value=result
    .split(/\r?\n/)
    .map((value: string) => value.trim())
    .filter(Boolean)
}

function requestOpenFile(path:string){
  if(!path) return
  openFileRequest.value={token:openFileRequest.value.token+1,path}
}

function setActiveFile(path:string){
  activeFilePath.value=path
}

function stopPolling(){
  window.clearInterval(pollTimer)
}

function beginPolling(taskId:string){
  stopPolling()
  pollTimer=window.setInterval(async()=>{
    try{
      const task=await getDeveloperTask(taskId)
      developerTask.value=task
      if(['COMPLETED','FAILED','CANCELLED'].includes(task.state)){
        stopPolling()
        await refreshTree()
        workspaceRevision.value++
      }
    }catch(error){
      lastError.value=String(error)
      stopPolling()
    }
  },700)
}

async function sendIntent(text:string, extraContext=''){
  const normalized=text.trim()
  if(!normalized || !workspaceId.value || busy.value) return

  busy.value=true
  pushMessage('human',normalized)

  try{
    const context=[
      `workspace_id=${workspaceId.value}`,
      activeFilePath.value ? `active_file=${activeFilePath.value}` : '',
      extraContext.trim(),
    ].filter(Boolean).join('\n')

    const request=context
      ? `${normalized}\n\n[VSA CONTEXT]\n${context}`
      : normalized

    const task=await startDeveloperTask({
      workspace_id:workspaceId.value,
      request,
      mode:'AUTO',
      provider_id:providerId.value,
      model_id:modelId.value,
    })

    developerTask.value=task
    pushMessage(
      'hyperagent',
      `ミッション ${task.id} を受領しました。状態: ${task.state}`
    )
    beginPolling(task.id)
  }catch(error){
    lastError.value=String(error)
    pushMessage('system',`送信失敗: ${String(error)}`)
    throw error
  }finally{
    busy.value=false
  }
}

async function cancelMission(){
  if(!developerTask.value) return
  await cancelDeveloperTask(developerTask.value.id)
  developerTask.value=await getDeveloperTask(developerTask.value.id)
}

async function rollbackMission(){
  if(!developerTask.value) return
  developerTask.value=await rollbackDeveloperTask(developerTask.value.id)
  await refreshTree()
  workspaceRevision.value++
}

async function runAction(action:ControlAction){
  if(!workspaceId.value || actionBusy.value) return null
  actionBusy.value=action
  try{
    const result=await editorRunAction(workspaceId.value,action)
    controlOutputs.value={...controlOutputs.value,[action]:result}
    return result
  }finally{
    actionBusy.value=''
  }
}

export function useVsaWorkspace(){
  return {
    workspaces,workspaceId,runtimeInfo,
    rawTree,treeDepth,treeFilter,remoteSearchResults,
    parsedTree,visibleTree,
    activeFilePath,openFileRequest,workspaceRevision,
    providerId,modelId,developerTask,
    busy,actionBusy,lastError,
    controlOutputs,chatMessages,
    activities,commands,errors,taskDiff,
    taskStateLabel,taskTone,
    ensureInitialized,refreshTree,changeWorkspace,changeTreeDepth,
    remoteSearch,requestOpenFile,setActiveFile,
    sendIntent,cancelMission,rollbackMission,runAction,
  }
}
<script setup lang="ts">
import 'monaco-editor/min/vs/editor/editor.main.css'
import * as monaco from 'monaco-editor'
import { computed,onMounted,onUnmounted,ref,watch } from 'vue'

import {
  editorReadFile,
  editorWriteFile,
} from '../../services/vertex-editor'

import { useVsaWorkspace } from './useVsaWorkspace'

const workspace=useVsaWorkspace()
const host=ref<HTMLElement|null>(null)
const docs=ref<Array<{
  path:string
  saved:string
  model:monaco.editor.ITextModel
}>>([])
const activePath=ref('')
const saving=ref(false)
const error=ref('')

let editor:monaco.editor.IStandaloneCodeEditor|null=null

const activeDoc=computed(
  ()=>docs.value.find((item)=>item.path===activePath.value) ?? null
)
const dirty=computed(
  ()=>Boolean(activeDoc.value && activeDoc.value.model.getValue()!==activeDoc.value.saved)
)

function languageFor(path:string){
  const lower=path.toLowerCase()
  if(lower.endsWith('.rs')) return 'rust'
  if(lower.endsWith('.vue')) return 'html'
  if(lower.endsWith('.ts')||lower.endsWith('.tsx')) return 'typescript'
  if(lower.endsWith('.js')) return 'javascript'
  if(lower.endsWith('.json')) return 'json'
  if(lower.endsWith('.css')||lower.endsWith('.scss')) return 'css'
  if(lower.endsWith('.md')) return 'markdown'
  return 'plaintext'
}

async function openFile(path:string){
  if(!workspace.workspaceId.value || !path) return

  const existing=docs.value.find((item)=>item.path===path)
  if(existing){
    activePath.value=path
    workspace.setActiveFile(path)
    editor?.setModel(existing.model)
    return
  }

  try{
    const snap=await editorReadFile(workspace.workspaceId.value,path)
    const uri=monaco.Uri.parse(
      `vertex-workspace:///${encodeURIComponent(snap.path)}`
    )
    let model=monaco.editor.getModel(uri)
    if(!model){
      model=monaco.editor.createModel(
        snap.content,
        languageFor(snap.path),
        uri
      )
    }else{
      model.setValue(snap.content)
    }

    docs.value.push({
      path:snap.path,
      saved:snap.content,
      model,
    })
    activePath.value=snap.path
    workspace.setActiveFile(snap.path)
    editor?.setModel(model)
  }catch(reason){
    error.value=String(reason)
  }
}

function selectDocument(path: string) {
  const document = docs.value.find((item) => item.path === path)
  if (!document) return

  activePath.value = path
  workspace.setActiveFile(path)

  const instance = editor
  if (instance) {
    instance.setModel(document.model)
  }
}
async function save(){
  const doc=activeDoc.value
  if(!doc || !workspace.workspaceId.value) return

  saving.value=true
  try{
    const value=doc.model.getValue()
    await editorWriteFile(workspace.workspaceId.value,doc.path,value)
    doc.saved=value
    await workspace.refreshTree()
  }finally{
    saving.value=false
  }
}

watch(
  ()=>workspace.openFileRequest.value.token,
  ()=>{
    const path=workspace.openFileRequest.value.path
    if(path) void openFile(path)
  }
)

onMounted(async()=>{
  if(!host.value) return

  editor=monaco.editor.create(host.value,{
    value:'',
    language:'plaintext',
    theme:'vs-dark',
    automaticLayout:true,
    fontSize:15,
    lineHeight:24,
    minimap:{enabled:true},
    smoothScrolling:true,
    stickyScroll:{enabled:true},
    bracketPairColorization:{enabled:true},
    padding:{top:12,bottom:12},
    scrollBeyondLastLine:false,
  })

  editor.addCommand(
    monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyS,
    ()=>void save()
  )

  await workspace.ensureInitialized()
})

onUnmounted(()=>{
  editor?.dispose()
  docs.value.forEach((doc)=>doc.model.dispose())
})
</script>

<template>
  <section class="vertex-main-editor">
    <header class="toolbar">
      <div>
        <strong>VSA エディター</strong>
        <small>PRIMARY EQUIPMENT / 中央作業面</small>
      </div>

      <select
        :value="workspace.workspaceId.value"
        @change="workspace.changeWorkspace(($event.target as HTMLSelectElement).value)"
      >
        <option
          v-for="item in workspace.workspaces.value"
          :key="item.id"
          :value="item.id"
        >
          {{ item.name }}
        </option>
      </select>

      <span>{{ workspace.taskStateLabel.value }}</span>

      <button
        :disabled="!dirty || saving"
        @click="save"
      >
        {{ saving ? '保存中…' : '保存' }}
      </button>
    </header>

    <div
      v-if="error || workspace.lastError.value"
      class="error"
    >
      {{ error || workspace.lastError.value }}
    </div>

    <nav class="tabs">
      <button
        v-for="doc in docs"
        :key="doc.path"
        :class="{active:doc.path===activePath}"
        @click="selectDocument(doc.path)"
      >
        {{ doc.path.split(/[\\/]/).slice(-1)[0] }}
        <b v-if="doc.model.getValue()!==doc.saved">●</b>
      </button>

      <span v-if="!docs.length">
        VVEからファイルを選択してください
      </span>
    </nav>

    <div ref="host" class="host"/>

    <footer>
      {{ activePath || 'ファイル未選択' }}
    </footer>
  </section>
</template>

<style scoped>
.vertex-main-editor{
  position:absolute;inset:0;
  display:grid;min-width:0;min-height:0;
  grid-template-rows:50px auto 36px minmax(0,1fr) 26px;
  overflow:hidden;border:0;border-radius:0;
  background:#070812;box-shadow:none
}
.toolbar{
  display:flex;align-items:center;gap:8px;padding:6px 9px;
  border-bottom:1px solid #29304d;background:#0d1020
}
.toolbar>div{min-width:180px}
.toolbar strong,.toolbar small{display:block}
.toolbar strong{color:#d8def0;font-size:13px}
.toolbar small{margin-top:3px;color:#687391;font-size:8px}
.toolbar select{
  min-width:180px;height:30px;border:1px solid #343d61;
  background:#090c19;color:#c2cbe0
}
.toolbar span{margin-left:auto;color:#9b8adb;font-size:9px}
.toolbar button{
  height:30px;border:1px solid #6a52b7;
  background:#251f4b;color:#c7baf9
}
.error{
  padding:6px 9px;border-bottom:1px solid rgba(255,116,143,.35);
  background:#28111c;color:#ffc0cd;font-size:10px
}
.tabs{
  display:flex;overflow-x:auto;
  border-bottom:1px solid #29304d;background:#0b0e1b
}
.tabs button{
  min-width:120px;height:36px;border:0;border-right:1px solid #29304d;
  background:#0e1222;color:#77829f
}
.tabs button.active{
  background:#070812;color:#d7def0;
  box-shadow:inset 0 -2px 0 #8b5cf6
}
.tabs b{color:#f2c66d}
.tabs>span{
  display:flex;align-items:center;padding:0 10px;
  color:#596581;font-size:9px
}
.host{min-width:0;min-height:0;width:100%;height:100%}
footer{
  display:flex;align-items:center;padding:0 8px;
  border-top:1px solid #29304d;background:#0a0d18;color:#65708c;
  font:9px/1 ui-monospace,Consolas,monospace
}
</style>
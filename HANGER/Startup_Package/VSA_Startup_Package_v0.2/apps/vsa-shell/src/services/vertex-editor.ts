import * as actual from '../vertex-cockpit/workspace/useVsaWorkspace'

export interface EditorRuntimeInfo {
  workspace_name: string
  workspace_root: string
  mothership_detected: boolean
  hyper_agent_runtime_detected: boolean
  git_enabled: boolean
  branch?: string
}

export interface EditorFileSnapshot {
  path: string
  content: string
  language: string
}

export interface EditorCommandResult {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

type AnyFunction = (...args: any[]) => any
const api = actual as unknown as Record<string, unknown>

function normalized(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '')
}

function functions(): Array<[string, AnyFunction]> {
  return Object.entries(api)
    .filter((entry): entry is [string, AnyFunction] => typeof entry[1] === 'function')
}

function pick(
  exact: string[],
  tokenGroups: string[][],
): AnyFunction | null {
  for (const name of exact) {
    const value = api[name]
    if (typeof value === 'function') return value as AnyFunction
  }

  const available = functions()

  for (const tokens of tokenGroups) {
    const hit = available.find(([name]) => {
      const value = normalized(name)
      return tokens.every((token) => value.includes(normalized(token)))
    })
    if (hit) return hit[1]
  }

  return null
}

async function invokeAdaptive(
  fn: AnyFunction,
  positional: unknown[],
  named: Record<string, unknown>,
): Promise<unknown> {
  if (fn.length === 0) return await fn()
  if (fn.length === 1) return await fn(named)
  return await fn(...positional)
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function textValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = '',
): string {
  if (!object) return fallback
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'string') return value
  }
  return fallback
}

function boolValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = false,
): boolean {
  if (!object) return fallback
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'boolean') return value
  }
  return fallback
}

export async function editorProjectTree(
  workspaceId: string,
  depth = 7,
): Promise<string> {
  const fn = pick(
    ['editorProjectTree','projectTree','getProjectTree','fetchProjectTree','vertexProjectTree'],
    [['project','tree'],['workspace','tree'],['tree']],
  )
  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId, depth],
    {
      workspaceId,
      workspace_id: workspaceId,
      depth,
      maxDepth: depth,
      max_depth: depth,
    },
  )

  if (typeof result === 'string') return result
  const object = objectValue(result)
  return textValue(object,['tree','text','output','value']) || JSON.stringify(result,null,2)
}

export async function editorRuntimeInfo(
  workspaceId: string,
): Promise<EditorRuntimeInfo> {
  const fn = pick(
    ['editorRuntimeInfo','runtimeInfo','getRuntimeInfo','workspaceRuntimeInfo'],
    [['runtime','info'],['workspace','info']],
  )

  if (!fn) {
    return {
      workspace_name: 'UNBOUND',
      workspace_root: '',
      mothership_detected: false,
      hyper_agent_runtime_detected: false,
      git_enabled: false,
    }
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId],
    { workspaceId, workspace_id: workspaceId },
  )

  const object = objectValue(result)

  return {
    workspace_name: textValue(object,['workspace_name','workspaceName','name'],'Workspace'),
    workspace_root: textValue(object,['workspace_root','workspaceRoot','root','path']),
    mothership_detected: boolValue(object,['mothership_detected','mothershipDetected']),
    hyper_agent_runtime_detected: boolValue(object,['hyper_agent_runtime_detected','hyperAgentRuntimeDetected']),
    git_enabled: boolValue(object,['git_enabled','gitEnabled']),
    branch: textValue(object,['branch','git_branch','gitBranch']) || undefined,
  }
}

export async function editorSearchFiles(
  workspaceId: string,
  query: string,
): Promise<string> {
  const fn = pick(
    ['editorSearchFiles','searchFiles','findFiles','workspaceSearch'],
    [['search','file'],['find','file'],['workspace','search']],
  )
  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId,query],
    { workspaceId, workspace_id: workspaceId, query, pattern: query },
  )

  if (typeof result === 'string') return result
  if (Array.isArray(result)) return result.map((item) => String(item)).join('\n')

  const object=objectValue(result)
  const nested=object?.results ?? object?.files ?? object?.items
  return Array.isArray(nested)
    ? nested.map((item) => String(item)).join('\n')
    : ''
}

export async function editorReadFile(
  workspaceId: string,
  path: string,
): Promise<EditorFileSnapshot> {
  const fn = pick(
    ['editorReadFile','readFile','readWorkspaceFile','workspaceReadFile','getFile'],
    [['read','file'],['file','read']],
  )

  if (!fn) {
    throw new Error('Editor read transport is UNBOUND.')
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId,path],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
    },
  )

  if (typeof result === 'string') {
    return { path, content: result, language: 'plaintext' }
  }

  const object=objectValue(result)

  return {
    path: textValue(object,['path','relative_path','relativePath'],path),
    content: textValue(object,['content','text','value']),
    language: textValue(object,['language','language_id','languageId'],'plaintext'),
  }
}

export async function editorWriteFile(
  workspaceId: string,
  path: string,
  content: string,
): Promise<void> {
  const fn = pick(
    ['editorWriteFile','writeFile','writeWorkspaceFile','workspaceWriteFile','saveFile'],
    [['write','file'],['save','file'],['file','write']],
  )

  if (!fn) {
    throw new Error('Editor write transport is UNBOUND.')
  }

  await invokeAdaptive(
    fn,
    [workspaceId,path,content],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
      content,
    },
  )
}

export async function editorRunAction(
  workspaceId: string,
  action: string,
): Promise<EditorCommandResult> {
  const fn = pick(
    ['editorRunAction','runAction','runEditorAction','controlledAction'],
    [['run','action'],['editor','action'],['controlled','action']],
  )

  if (!fn) {
    throw new Error('Editor action transport is UNBOUND.')
  }

  const result=await invokeAdaptive(
    fn,
    [workspaceId,action],
    { workspaceId, workspace_id: workspaceId, action },
  )

  const object=objectValue(result)

  return {
    id: textValue(object,['id','command_id','commandId'],String(Date.now())),
    executable: textValue(object,['executable','program','command'],action),
    args: Array.isArray(object?.args) ? object.args.map((item)=>String(item)) : [],
    status: textValue(object,['status','state'],'UNKNOWN'),
    stdout: textValue(object,['stdout','output']),
    stderr: textValue(object,['stderr','error']),
  }
}
export interface DeveloperWorkspace {
  id: string
  name: string
  path?: string
}

export interface DeveloperActivity {
  sequence: number
  kind: string
  message: string
  detail?: string
  risk?: string
}

export interface DeveloperCommand {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

export interface DeveloperError {
  error_type: string
  code?: string
  message: string
  file?: string
  line?: number
}

export interface DeveloperTask {
  id: string
  state: string
  activities?: DeveloperActivity[]
  commands?: DeveloperCommand[]
  errors?: DeveloperError[]
  unified_diff?: string
}

export interface StartDeveloperTaskInput {
  workspace_id: string
  request: string
  mode: string
  provider_id: string
  model_id: string
}

function unbound(): never {
  throw new Error(
    'Developer Agent transport is UNBOUND. ' +
    'V7R3 does not invent Tauri command names.'
  )
}

export async function listDeveloperWorkspaces(): Promise<DeveloperWorkspace[]> {
  return []
}

export async function startDeveloperTask(
  _input: StartDeveloperTaskInput,
): Promise<DeveloperTask> {
  return unbound()
}

export async function getDeveloperTask(
  _id: string,
): Promise<DeveloperTask> {
  return unbound()
}

export async function cancelDeveloperTask(
  _id: string,
): Promise<void> {
  return unbound()
}

export async function rollbackDeveloperTask(
  _id: string,
): Promise<DeveloperTask> {
  return unbound()
}
export interface RuntimeInfo{core_root:string;cargo_workspace:boolean;mothership:boolean;autonomous_loop:boolean;real_hyper_agent:boolean;bridge:boolean;recent_reports:string[]}
export interface FileSnapshot{path:string;content:string;language:string;bytes:number;lines:number}
export interface ActionResult{action:string;executable:string;args:string[];success:boolean;timed_out:boolean;exit_code:number|null;stdout:string;stderr:string;duration_ms:number}
export const desktop=()=>Boolean((window as unknown as{__TAURI_INTERNALS__?:unknown}).__TAURI_INTERNALS__)
async function call<T>(cmd:string,args?:Record<string,unknown>):Promise<T>{
 if(!desktop())throw new Error('Desktop bridge offline. Launch VSA through Tauri.')
 const{invoke}=await import('@tauri-apps/api/core');return invoke<T>(cmd,args)
}
export const runtimeInfo=()=>call<RuntimeInfo>('vertex_runtime_info')
export const projectTree=(depth=5)=>call<string>('vertex_project_tree',{depth})
export const readFile=(path:string)=>call<FileSnapshot>('vertex_read_file',{path})
export const writeFile=(path:string,content:string)=>call('vertex_write_file',{input:{path,content}})
export const runAction=(action:'cargo_fmt'|'cargo_check'|'cargo_test'|'git_status'|'git_diff')=>call<ActionResult>('vertex_run_action',{action})
export interface LiveSessionSnapshot {
  schema: string
  kind: 'wave_scheduled' | 'wave_completed' | string
  timestamp_ms: number
  session?: {
    session_id?: string
    status?: string
    completed_waves?: number
  }
  wave?: {
    sequence?: number
    wave_id?: string
    ready?: string[]
    blocked?: string[]
    waiting?: string[]
    missions?: string[]
    resulting_status?: string
  }
  dispatch?: {
    dispatch_id?: string
    mission_set?: string[]
    executions?: Array<{
      execution_id?: string
    }>
    confirmed_missions?: string[]
    process_result_count?: number
  }
  genesis?: {
    event_count?: number
    events_debug?: string
  }
  vsp?: {
    checkpoint_debug?: string
  } | null
}

export async function liveSessionLatest(): Promise<LiveSessionSnapshot | null> {
  const raw = await call<string>('vertex_live_session_latest')
  if (!raw.trim()) return null
  return JSON.parse(raw) as LiveSessionSnapshot
}

export async function liveSessionTail(limit = 40): Promise<LiveSessionSnapshot[]> {
  const lines = await call<string[]>('vertex_live_session_tail', { limit })
  const snapshots: LiveSessionSnapshot[] = []
  for (const line of lines) {
    try {
      snapshots.push(JSON.parse(line) as LiveSessionSnapshot)
    } catch {
      // Fail closed at the display boundary: malformed telemetry is ignored,
      // never converted into controller state.
    }
  }
  return snapshots
}
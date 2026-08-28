import { invoke } from '@tauri-apps/api/core'

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
  }
  vsp?: {
    checkpoint_debug?: string
  } | null
}

export function desktop(): boolean {
  return Boolean((window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__)
}

export async function liveSessionLatest(): Promise<LiveSessionSnapshot | null> {
  const raw = await invoke<string>('vertex_live_session_latest')
  if (!raw.trim()) return null
  return JSON.parse(raw) as LiveSessionSnapshot
}

export async function liveSessionTail(limit = 40): Promise<LiveSessionSnapshot[]> {
  const lines = await invoke<string[]>('vertex_live_session_tail', { limit })
  const snapshots: LiveSessionSnapshot[] = []

  for (const line of lines) {
    try {
      snapshots.push(JSON.parse(line) as LiveSessionSnapshot)
    } catch {
      // Malformed telemetry never becomes controller state.
    }
  }

  return snapshots
}
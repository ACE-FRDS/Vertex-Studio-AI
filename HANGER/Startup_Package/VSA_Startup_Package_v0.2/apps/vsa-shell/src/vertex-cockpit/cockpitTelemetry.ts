import { onMounted, onUnmounted, readonly, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'

const RUNTIME_INFO_COMMAND = 'vertex_runtime_info'
const HUB_STATE_COMMAND = 'vertex_hub_runtime_state'
const LIVE_SIGNAL_COMMAND: string | null = 'vertex_live_session_latest'

type JsonObject = Record<string, unknown>

export interface CockpitTelemetry {
  now: string
  runtimeOnline: boolean
  hubOnline: boolean
  liveOnline: boolean
  networkOnline: boolean
  runtimeLabel: string
  projectLabel: string
  hubPackageCount: number
  hubEnabledCount: number
  sessionId: string
  waveId: string
  dispatchId: string
  checkpointId: string
  agentCount: number | null
  hardwareThreads: number | null
  jsHeapUsedMb: number | null
  jsHeapLimitMb: number | null
  gpuRenderer: string
  lastError: string
  updatedAt: string
}

const initialState = (): CockpitTelemetry => ({
  now: new Date().toLocaleTimeString(),
  runtimeOnline: false,
  hubOnline: false,
  liveOnline: false,
  networkOnline: navigator.onLine,
  runtimeLabel: 'NO SIGNAL',
  projectLabel: 'CURRENT WORKSPACE',
  hubPackageCount: 0,
  hubEnabledCount: 0,
  sessionId: '',
  waveId: '',
  dispatchId: '',
  checkpointId: '',
  agentCount: null,
  hardwareThreads:
    typeof navigator.hardwareConcurrency === 'number'
      ? navigator.hardwareConcurrency
      : null,
  jsHeapUsedMb: null,
  jsHeapLimitMb: null,
  gpuRenderer: detectGpuRenderer(),
  lastError: '',
  updatedAt: '',
})

function parsePayload(value: unknown): unknown {
  if (typeof value !== 'string') return value
  try {
    return JSON.parse(value)
  } catch {
    return value
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function findByKey(
  value: unknown,
  keyNames: string[],
  depth = 0,
): unknown {
  if (depth > 8) return undefined

  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findByKey(item, keyNames, depth + 1)
      if (found !== undefined) return found
    }
    return undefined
  }

  if (!isObject(value)) return undefined

  const normalized = new Set(
    keyNames.map((key) => key.toLowerCase().replace(/[^a-z0-9]/g, '')),
  )

  for (const [key, child] of Object.entries(value)) {
    const current = key.toLowerCase().replace(/[^a-z0-9]/g, '')
    if (normalized.has(current)) return child
  }

  for (const child of Object.values(value)) {
    const found = findByKey(child, keyNames, depth + 1)
    if (found !== undefined) return found
  }

  return undefined
}

function asText(value: unknown): string {
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value)
  }
  return ''
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function detectGpuRenderer(): string {
  try {
    const canvas = document.createElement('canvas')
    const gl =
      canvas.getContext('webgl2')
      ?? canvas.getContext('webgl')
      ?? canvas.getContext('experimental-webgl')

    if (!gl || typeof WebGLRenderingContext === 'undefined') {
      return 'NO WEBGL SIGNAL'
    }

    const webgl = gl as WebGLRenderingContext
    const extension = webgl.getExtension('WEBGL_debug_renderer_info')
    if (extension) {
      const renderer = webgl.getParameter(extension.UNMASKED_RENDERER_WEBGL)
      if (typeof renderer === 'string' && renderer.trim()) return renderer
    }

    const fallback = webgl.getParameter(webgl.RENDERER)
    return typeof fallback === 'string' && fallback.trim()
      ? fallback
      : 'WEBGL ONLINE'
  } catch {
    return 'GPU SIGNAL UNAVAILABLE'
  }
}

function readHeap(): { used: number | null; limit: number | null } {
  const memory = (
    performance as Performance & {
      memory?: {
        usedJSHeapSize?: number
        jsHeapSizeLimit?: number
      }
    }
  ).memory

  if (!memory) return { used: null, limit: null }

  const toMb = (bytes: number | undefined) =>
    typeof bytes === 'number'
      ? Math.round((bytes / 1024 / 1024) * 10) / 10
      : null

  return {
    used: toMb(memory.usedJSHeapSize),
    limit: toMb(memory.jsHeapSizeLimit),
  }
}

function extractProjectLabel(payload: unknown): string {
  return (
    asText(
      findByKey(payload, [
        'project',
        'project_name',
        'workspace',
        'workspace_name',
        'root_name',
      ]),
    ) || 'CURRENT WORKSPACE'
  )
}

function extractRuntimeLabel(payload: unknown): string {
  return (
    asText(
      findByKey(payload, [
        'runtime',
        'runtime_name',
        'status',
        'state',
      ]),
    ) || 'ONLINE'
  )
}

function countAgents(payload: unknown): number | null {
  const direct = findByKey(payload, ['agents', 'agent_ids', 'active_agents'])
  if (Array.isArray(direct)) return direct.length

  const explicit = findByKey(payload, ['agent_count', 'active_agent_count'])
  if (typeof explicit === 'number' && Number.isFinite(explicit)) {
    return explicit
  }

  return null
}

export function useCockpitTelemetry() {
  const telemetry = ref<CockpitTelemetry>(initialState())
  let pollTimer: number | null = null
  let clockTimer: number | null = null
  let inFlight = false

  async function refresh() {
    if (inFlight) return
    inFlight = true

    const next = { ...telemetry.value }
    next.lastError = ''
    next.networkOnline = navigator.onLine
    next.now = new Date().toLocaleTimeString()

    const heap = readHeap()
    next.jsHeapUsedMb = heap.used
    next.jsHeapLimitMb = heap.limit

    try {
      const rawRuntime = await invoke<unknown>(RUNTIME_INFO_COMMAND)
      const runtime = parsePayload(rawRuntime)
      next.runtimeOnline = true
      next.runtimeLabel = extractRuntimeLabel(runtime)
      next.projectLabel = extractProjectLabel(runtime)
    } catch (error) {
      next.runtimeOnline = false
      next.runtimeLabel = 'NO SIGNAL'
      next.lastError = 'runtime: ' + String(error)
    }

    try {
      const rawHub = await invoke<unknown>(HUB_STATE_COMMAND)
      const hub = parsePayload(rawHub)
      const packages = asArray(findByKey(hub, ['packages']))
      next.hubOnline = true
      next.hubPackageCount = packages.length
      next.hubEnabledCount = packages.filter((entry) => {
        if (!isObject(entry)) return false
        return entry.enabled === true
      }).length
    } catch (error) {
      next.hubOnline = false
      if (!next.lastError) next.lastError = 'hub: ' + String(error)
    }

    if (LIVE_SIGNAL_COMMAND) {
      try {
        const rawLive = await invoke<unknown>(LIVE_SIGNAL_COMMAND)
        const live = parsePayload(rawLive)

        next.liveOnline = true
        next.sessionId = asText(findByKey(live, ['session_id', 'sessionId']))
        next.waveId = asText(findByKey(live, ['wave_id', 'waveId']))
        next.dispatchId = asText(
          findByKey(live, ['dispatch_id', 'dispatchId']),
        )
        next.checkpointId = asText(
          findByKey(live, [
            'checkpoint_id',
            'checkpointId',
            'save_point_id',
            'vsp_id',
          ]),
        )
        next.agentCount = countAgents(live)
      } catch (error) {
        next.liveOnline = false
        if (!next.lastError) next.lastError = 'live: ' + String(error)
      }
    } else {
      next.liveOnline = false
    }

    next.updatedAt = new Date().toISOString()
    telemetry.value = next
    inFlight = false
  }

  function clock() {
    telemetry.value = {
      ...telemetry.value,
      now: new Date().toLocaleTimeString(),
      networkOnline: navigator.onLine,
    }
  }

  onMounted(() => {
    void refresh()
    pollTimer = window.setInterval(() => void refresh(), 1200)
    clockTimer = window.setInterval(clock, 1000)
  })

  onUnmounted(() => {
    if (pollTimer !== null) window.clearInterval(pollTimer)
    if (clockTimer !== null) window.clearInterval(clockTimer)
  })

  return {
    telemetry: readonly(telemetry),
    refresh,
  }
}
& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC - VSA COCKPIT SHELL V1
#
# Mission:
#   Raise VSA to the first true "mothership bridge" visual level
#   without faking telemetry and without replacing the working editor.
#
# Doctrine:
#   Shell  = Bridge / layout manager
#   Panel  = independent Vue component
#   Data   = real signal only; unavailable -> NO SIGNAL / NOT WIRED
#   Hub    = equipment motherport (not inserted into live nerve path)
#   Editor = preserved and wrapped, not rewritten
#
# Component boundary:
#   src/vertex-cockpit/
#     VertexCockpitShell.vue
#     cockpitTelemetry.ts
#     panelRegistry.ts
#     panels/
#       CockpitPanelFrame.vue
#       ProjectStatusPanel.vue
#       VspStatusPanel.vue
#       VxnStatusPanel.vue
#       ArdStatusPanel.vue
#       ProjectBrainPanel.vue
#       WorkspaceHealthPanel.vue
#       SystemMonitorPanel.vue
#       HyperAgentPanel.vue
#       VspSnapshotPanel.vue
#       CockpitStatusBar.vue
#
# Safety:
#   - no eval
#   - no remote runtime import
#   - no arbitrary shell
#   - no controller mutation
#   - existing editor remains the working center surface
#   - fail closed on unknown editor/template topology
#   - backup + rollback on RED
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$editorTransport=Join-Path $ui 'src\vertex-editor\transport.ts'
$hubRuntime=Join-Path $ui 'src\vertex-hub\runtime.ts'
$liveTransport=Join-Path $ui 'src\vertex-hub\packages\vertex.live-flight-panel\1.0.0\src\hub-transport.ts'
$packageJson=Join-Path $ui 'package.json'
$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$cockpitRoot=Join-Path $ui 'src\vertex-cockpit'
$panelsRoot=Join-Path $cockpitRoot 'panels'
$tauriCheckTarget=Join-Path $startup '_build\VSA_TAURI_COCKPIT_CHECK'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_COCKPIT_SHELL_V1_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_COCKPIT_SHELL_V1_FAILED.$stamp"
$report=Join-Path $reports "VSA_COCKPIT_SHELL_V1.$stamp.json"

$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}

function RequireCommand([string]$Name){
  $cmd=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $cmd){throw "Missing command: $Name"}
  return $cmd
}

function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}

function BackupFile([string]$Path,[string]$Name){
  if(Test-Path -LiteralPath $Path){
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $Name) -Force
  }
}

function DiscoverInvokeCommand([string]$Path,[string[]]$Hints){
  if(-not(Test-Path -LiteralPath $Path)){return $null}

  $text=[IO.File]::ReadAllText($Path)
  $matches=[regex]::Matches(
    $text,
    'invoke(?:<[^>]+>)?\s*\(\s*[''"]([^''"]+)[''"]',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )

  foreach($hint in $Hints){
    foreach($match in $matches){
      $name=$match.Groups[1].Value
      if($name -like "*$hint*"){return $name}
    }
  }

  return $null
}

Write-Host @'
============================================================
 VERTEX - VSA COCKPIT SHELL V1
 MOTHERSHIP BRIDGE / COMPONENTIZED PANELS
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$editor,$editorTransport,
  $hubRuntime,$packageJson,$coreCargo,$tauriCargo
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required current-core artifact missing: $required"
  }
}

if(Test-Path -LiteralPath $cockpitRoot){
  throw "Cockpit source already exists: $cockpitRoot"
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/12] CURRENT GUI-LIVE BASELINE LOCK" -ForegroundColor Yellow

$editorText=[IO.File]::ReadAllText($editor)
$transportText=[IO.File]::ReadAllText($editorTransport)
$hubRuntimeText=[IO.File]::ReadAllText($hubRuntime)

$baseline=@(
  [pscustomobject]@{
    Name='VertexLivePreview import'
    Pass=$editorText.Contains("import VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'")
  },
  [pscustomobject]@{
    Name='VertexLivePreview render'
    Pass=$editorText.Contains('<VertexLivePreview />')
  },
  [pscustomobject]@{
    Name='VertexHubDock import'
    Pass=$editorText.Contains("import VertexHubDock from '../vertex-hub/VertexHubDock.vue'")
  },
  [pscustomobject]@{
    Name='Runtime info IPC'
    Pass=$transportText.Contains('vertex_runtime_info')
  },
  [pscustomobject]@{
    Name='Hub runtime state IPC'
    Pass=$hubRuntimeText.Contains('vertex_hub_runtime_state')
  }
)

foreach($item in $baseline){
  if(-not $item.Pass){throw "Current baseline missing: $($item.Name)"}
  Write-Host ("  {0,-34} GREEN" -f $item.Name) -ForegroundColor Green
}

$runtimeCommand=DiscoverInvokeCommand $editorTransport @('runtime_info')
if(-not $runtimeCommand){$runtimeCommand='vertex_runtime_info'}

$hubStateCommand=DiscoverInvokeCommand $hubRuntime @('runtime_state')
if(-not $hubStateCommand){$hubStateCommand='vertex_hub_runtime_state'}

$liveCommand=DiscoverInvokeCommand $liveTransport @('live','session','flight','timeline','snapshot')

Write-Host ("  Runtime command                   {0}" -f $runtimeCommand) -ForegroundColor Green
Write-Host ("  Hub state command                 {0}" -f $hubStateCommand) -ForegroundColor Green
if($liveCommand){
  Write-Host ("  Live telemetry command            {0}" -f $liveCommand) -ForegroundColor Green
}else{
  Write-Host "  Live telemetry command            NOT_DISCOVERED / FAIL-SOFT UI" -ForegroundColor Yellow
}

RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

Write-Host "`n[1/12] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
BackupFile $editor 'VertexEditorDock.vue'
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/12] CREATE COCKPIT TELEMETRY CONTRACT" -ForegroundColor Yellow
  New-Item -ItemType Directory -Path $panelsRoot -Force|Out-Null

  $liveLiteral='null'
  if($liveCommand){
    $safeLive=$liveCommand.Replace('\','\\').Replace("'","\'")
    $liveLiteral="'$safeLive'"
  }

  $runtimeLiteral=$runtimeCommand.Replace('\','\\').Replace("'","\'")
  $hubLiteral=$hubStateCommand.Replace('\','\\').Replace("'","\'")

  $telemetry=@"
import { onMounted, onUnmounted, readonly, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'

const RUNTIME_INFO_COMMAND = '$runtimeLiteral'
const HUB_STATE_COMMAND = '$hubLiteral'
const LIVE_SIGNAL_COMMAND: string | null = $liveLiteral

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
      next.lastError = `runtime: \${String(error)}`
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
      if (!next.lastError) next.lastError = `hub: \${String(error)}`
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
        if (!next.lastError) next.lastError = `live: \${String(error)}`
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
"@
  WriteUtf8 (Join-Path $cockpitRoot 'cockpitTelemetry.ts') $telemetry

  $registry=@'
export interface CockpitPanelDescriptor {
  id: string
  title: string
  region: 'TOP' | 'RIGHT' | 'BOTTOM'
  packageReady: boolean
  source: string
}

export const cockpitPanelRegistry: CockpitPanelDescriptor[] = [
  {
    id: 'vertex.project-status-panel',
    title: 'PROJECT',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectStatusPanel.vue',
  },
  {
    id: 'vertex.vsp-status-panel',
    title: 'VSP',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VspStatusPanel.vue',
  },
  {
    id: 'vertex.vxn-status-panel',
    title: 'VXN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VxnStatusPanel.vue',
  },
  {
    id: 'vertex.ard-status-panel',
    title: 'ARD',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ArdStatusPanel.vue',
  },
  {
    id: 'vertex.project-brain-panel',
    title: 'PROJECT BRAIN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectBrainPanel.vue',
  },
  {
    id: 'vertex.workspace-health-panel',
    title: 'WORKSPACE HEALTH',
    region: 'TOP',
    packageReady: true,
    source: 'panels/WorkspaceHealthPanel.vue',
  },
  {
    id: 'vertex.system-monitor-panel',
    title: 'SYSTEM MONITOR',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/SystemMonitorPanel.vue',
  },
  {
    id: 'vertex.hyper-agent-panel',
    title: 'HYPER AGENT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/HyperAgentPanel.vue',
  },
  {
    id: 'vertex.vsp-snapshot-panel',
    title: 'VSP SNAPSHOT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/VspSnapshotPanel.vue',
  },
  {
    id: 'vertex.cockpit-status-bar',
    title: 'COCKPIT STATUS BAR',
    region: 'BOTTOM',
    packageReady: true,
    source: 'panels/CockpitStatusBar.vue',
  },
]
'@
  WriteUtf8 (Join-Path $cockpitRoot 'panelRegistry.ts') $registry

  Write-Host 'Telemetry contract             : ONLINE' -ForegroundColor Green
  Write-Host 'Panel registry                 : ONLINE' -ForegroundColor Green
  Write-Host 'Fake telemetry                 : DENIED' -ForegroundColor Green

  Write-Host "`n[3/12] BUILD SHARED PANEL FRAME" -ForegroundColor Yellow

  $frame=@'
<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    status?: string
    statusTone?: 'blue' | 'green' | 'amber' | 'red' | 'muted'
    dense?: boolean
  }>(),
  {
    subtitle: '',
    status: '',
    statusTone: 'blue',
    dense: false,
  },
)
</script>

<template>
  <section
    class="panel-frame"
    :class="{ dense }"
  >
    <header class="panel-head">
      <div class="panel-title">
        <span class="panel-chevron">›</span>
        <div>
          <strong>{{ title }}</strong>
          <small v-if="subtitle">{{ subtitle }}</small>
        </div>
      </div>

      <span
        v-if="status"
        class="panel-status"
        :class="`tone-${statusTone}`"
      >
        {{ status }}
      </span>
    </header>

    <div class="panel-body">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.panel-frame {
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--vertex-line, #1c2935);
  border-radius: 4px;
  background:
    linear-gradient(180deg, rgba(17,25,35,.96), rgba(8,13,19,.98));
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.014),
    0 10px 30px rgba(0,0,0,.12);
}

.panel-head {
  display: flex;
  min-height: 30px;
  align-items: center;
  justify-content: space-between;
  padding: 0 9px;
  border-bottom: 1px solid var(--vertex-line, #1c2935);
  background:
    linear-gradient(90deg, rgba(22,140,255,.035), transparent 46%),
    rgba(10,16,23,.9);
}

.panel-title {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 6px;
}

.panel-title > div {
  min-width: 0;
}

.panel-title strong,
.panel-title small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.panel-title strong {
  color: #afbdcb;
  font-size: 8px;
  font-weight: 720;
  letter-spacing: .035em;
}

.panel-title small {
  margin-top: 2px;
  color: var(--vertex-faint, #455364);
  font: 650 6px/1 ui-monospace, "Cascadia Code", Consolas, monospace;
}

.panel-chevron {
  color: var(--vertex-blue-bright, #3ab8ff);
  font-size: 12px;
}

.panel-status {
  flex: none;
  font: 750 6px/1 ui-monospace, "Cascadia Code", Consolas, monospace;
  letter-spacing: .05em;
}

.tone-blue {
  color: var(--vertex-blue-bright, #3ab8ff);
}

.tone-green {
  color: var(--vertex-green, #55d69e);
}

.tone-amber {
  color: var(--vertex-amber, #f1b85b);
}

.tone-red {
  color: var(--vertex-red, #ff6f7c);
}

.tone-muted {
  color: var(--vertex-muted, #718195);
}

.panel-body {
  min-height: 0;
}

.dense .panel-head {
  min-height: 26px;
}
</style>
'@
  WriteUtf8 (Join-Path $panelsRoot 'CockpitPanelFrame.vue') $frame

  Write-Host 'CockpitPanelFrame             : CREATED' -ForegroundColor Green

  Write-Host "`n[4/12] BUILD TOP STATUS COMPONENTS" -ForegroundColor Yellow

  $projectPanel=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell project">
    <p>PROJECT</p>
    <strong>{{ telemetry.projectLabel }}</strong>
    <span>WORKSPACE // CURRENT</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'ProjectStatusPanel.vue') $projectPanel

  $vspPanel=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>VSP // <b :class="{ online: telemetry.liveOnline }">{{ telemetry.liveOnline ? 'LIVE' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.checkpointId || telemetry.sessionId || 'UNBOUND' }}</strong>
    <span>{{ telemetry.waveId ? `WAVE ${telemetry.waveId}` : 'CHECKPOINT STREAM' }}</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'VspStatusPanel.vue') $vspPanel

  $vxnPanel=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>VXN // <b :class="{ online: telemetry.runtimeOnline }">{{ telemetry.runtimeOnline ? 'LINKED' : 'OFFLINE' }}</b></p>
    <strong>{{ telemetry.runtimeLabel }}</strong>
    <span>RUNTIME CORE SIGNAL</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'VxnStatusPanel.vue') $vxnPanel

  $ardPanel=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>ARD // <b :class="{ online: telemetry.liveOnline }">{{ telemetry.liveOnline ? 'LINKED' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.agentCount === null ? 'UNBOUND' : `${telemetry.agentCount} AGENTS` }}</strong>
    <span>{{ telemetry.dispatchId ? `DISPATCH ${telemetry.dispatchId}` : 'LIVE LINEAGE' }}</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'ArdStatusPanel.vue') $ardPanel

  $brainPanel=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>PROJECT BRAIN // <b :class="{ online: telemetry.runtimeOnline }">{{ telemetry.runtimeOnline ? 'REACHABLE' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.runtimeOnline ? 'RUNTIME BOUND' : 'UNBOUND' }}</strong>
    <span>KNOWLEDGE / CONTINUITY EDGE</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'ProjectBrainPanel.vue') $brainPanel

  $healthPanel=@'
<script setup lang="ts">
import { computed } from 'vue'
import type { CockpitTelemetry } from '../cockpitTelemetry'

const props = defineProps<{
  telemetry: CockpitTelemetry
}>()

const signalCount = computed(
  () =>
    [
      props.telemetry.runtimeOnline,
      props.telemetry.hubOnline,
      props.telemetry.networkOnline,
    ].filter(Boolean).length,
)
</script>

<template>
  <article class="status-cell health">
    <p>WORKSPACE HEALTH</p>
    <strong>{{ signalCount }}/3 SIGNALS</strong>
    <span>RUNTIME / HUB / NETWORK</span>
  </article>
</template>
'@
  WriteUtf8 (Join-Path $panelsRoot 'WorkspaceHealthPanel.vue') $healthPanel

  Write-Host 'Top status components         : 6 CREATED' -ForegroundColor Green

  Write-Host "`n[5/12] BUILD RIGHT CIC COMPONENTS" -ForegroundColor Yellow

  $systemMonitor=@'
<script setup lang="ts">
import { computed } from 'vue'
import type { CockpitTelemetry } from '../cockpitTelemetry'
import CockpitPanelFrame from './CockpitPanelFrame.vue'

const props = defineProps<{
  telemetry: CockpitTelemetry
}>()

const heap = computed(() => {
  if (props.telemetry.jsHeapUsedMb === null) return 'NOT EXPOSED'
  if (props.telemetry.jsHeapLimitMb === null) {
    return `${props.telemetry.jsHeapUsedMb} MB`
  }
  return `${props.telemetry.jsHeapUsedMb} / ${props.telemetry.jsHeapLimitMb} MB`
})
</script>

<template>
  <CockpitPanelFrame
    title="SYSTEM MONITOR"
    subtitle="MEASURED SIGNALS ONLY"
    :status="telemetry.runtimeOnline ? 'LINKED' : 'PARTIAL'"
    :status-tone="telemetry.runtimeOnline ? 'green' : 'amber'"
  >
    <div class="monitor-grid">
      <div class="metric">
        <span>CPU THREADS</span>
        <strong>{{ telemetry.hardwareThreads ?? 'NOT EXPOSED' }}</strong>
      </div>

      <div class="metric">
        <span>JS HEAP</span>
        <strong>{{ heap }}</strong>
      </div>

      <div class="metric gpu">
        <span>GPU RENDERER</span>
        <strong>{{ telemetry.gpuRenderer }}</strong>
      </div>

      <div class="metric">
        <span>NETWORK</span>
        <strong :class="{ green: telemetry.networkOnline }">
          {{ telemetry.networkOnline ? 'ONLINE' : 'OFFLINE' }}
        </strong>
      </div>

      <div class="metric">
        <span>TAURI RUNTIME</span>
        <strong :class="{ green: telemetry.runtimeOnline }">
          {{ telemetry.runtimeOnline ? 'ONLINE' : 'NO SIGNAL' }}
        </strong>
      </div>

      <div class="metric">
        <span>VERTEXHUB</span>
        <strong :class="{ green: telemetry.hubOnline }">
          {{ telemetry.hubOnline ? 'ONLINE' : 'NO SIGNAL' }}
        </strong>
      </div>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.monitor-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1px;
  background: var(--vertex-line, #1c2935);
}

.metric {
  min-width: 0;
  padding: 10px;
  background: rgba(8,13,19,.97);
}

.metric.gpu {
  grid-column: 1 / -1;
}

.metric span,
.metric strong {
  display: block;
}

.metric span {
  color: var(--vertex-faint, #455364);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .05em;
}

.metric strong {
  margin-top: 6px;
  overflow: hidden;
  color: #9eafc0;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 8px/1.25 ui-monospace, Consolas, monospace;
}

.metric strong.green {
  color: var(--vertex-green, #55d69e);
}
</style>
'@
  WriteUtf8 (Join-Path $panelsRoot 'SystemMonitorPanel.vue') $systemMonitor

  $hyperAgent=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'
import CockpitPanelFrame from './CockpitPanelFrame.vue'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <CockpitPanelFrame
    title="HYPER AGENT"
    subtitle="LIVE LINEAGE OBSERVATION"
    :status="telemetry.liveOnline ? 'LINKED' : 'NO SIGNAL'"
    :status-tone="telemetry.liveOnline ? 'blue' : 'muted'"
  >
    <div class="agent-panel">
      <div class="agent-orb">
        <div class="orbit orbit-a" />
        <div class="orbit orbit-b" />
        <div class="orb-core" />
      </div>

      <div class="agent-data">
        <div>
          <span>AGENT COUNT</span>
          <strong>{{ telemetry.agentCount ?? 'UNBOUND' }}</strong>
        </div>
        <div>
          <span>SESSION</span>
          <strong>{{ telemetry.sessionId || 'NO LIVE SESSION' }}</strong>
        </div>
        <div>
          <span>DISPATCH</span>
          <strong>{{ telemetry.dispatchId || 'NO LIVE DISPATCH' }}</strong>
        </div>
      </div>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.agent-panel {
  display: grid;
  grid-template-columns: 90px minmax(0,1fr);
  align-items: center;
  padding: 12px 10px;
  gap: 10px;
}

.agent-orb {
  position: relative;
  width: 76px;
  height: 76px;
  margin: auto;
  border: 1px solid #17384f;
  border-radius: 50%;
  background:
    radial-gradient(circle, rgba(58,184,255,.15), rgba(4,12,18,.2) 45%, transparent 70%);
}

.orbit {
  position: absolute;
  inset: 14px;
  border: 1px solid rgba(58,184,255,.26);
  border-radius: 50%;
}

.orbit-a {
  transform: rotate(32deg) scaleY(.45);
}

.orbit-b {
  transform: rotate(-38deg) scaleX(.45);
}

.orb-core {
  position: absolute;
  top: 50%;
  left: 50%;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  transform: translate(-50%,-50%);
  background: var(--vertex-blue-bright, #3ab8ff);
  box-shadow:
    0 0 8px rgba(58,184,255,.85),
    0 0 24px rgba(22,140,255,.34);
}

.agent-data {
  min-width: 0;
}

.agent-data > div {
  padding: 7px 0;
  border-bottom: 1px solid var(--vertex-line, #1c2935);
}

.agent-data > div:last-child {
  border-bottom: 0;
}

.agent-data span,
.agent-data strong {
  display: block;
}

.agent-data span {
  color: var(--vertex-faint, #455364);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.agent-data strong {
  margin-top: 4px;
  overflow: hidden;
  color: #94a6b7;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 7px/1.2 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $panelsRoot 'HyperAgentPanel.vue') $hyperAgent

  $vspSnapshot=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'
import CockpitPanelFrame from './CockpitPanelFrame.vue'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <CockpitPanelFrame
    title="VSP SNAPSHOT"
    subtitle="CURRENT OBSERVED BOUNDARY"
    :status="telemetry.liveOnline ? 'LIVE' : 'NO SIGNAL'"
    :status-tone="telemetry.liveOnline ? 'green' : 'muted'"
  >
    <div class="snapshot">
      <div class="save-point">
        <span>CHECKPOINT</span>
        <strong>{{ telemetry.checkpointId || 'UNBOUND' }}</strong>
      </div>

      <dl>
        <div>
          <dt>SESSION</dt>
          <dd>{{ telemetry.sessionId || '—' }}</dd>
        </div>
        <div>
          <dt>WAVE</dt>
          <dd>{{ telemetry.waveId || '—' }}</dd>
        </div>
        <div>
          <dt>DISPATCH</dt>
          <dd>{{ telemetry.dispatchId || '—' }}</dd>
        </div>
      </dl>

      <div class="snapshot-note">
        No synthetic save-point data is generated.
      </div>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.snapshot {
  padding: 12px;
}

.save-point span,
.save-point strong {
  display: block;
}

.save-point span {
  color: var(--vertex-faint, #455364);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.save-point strong {
  margin-top: 5px;
  overflow: hidden;
  color: #b8c8d8;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 12px/1 ui-monospace, Consolas, monospace;
}

dl {
  margin: 12px 0 0;
}

dl > div {
  display: grid;
  grid-template-columns: 58px minmax(0,1fr);
  padding: 6px 0;
  border-top: 1px solid var(--vertex-line, #1c2935);
}

dt {
  color: var(--vertex-faint, #455364);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

dd {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  color: #8396a8;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.snapshot-note {
  margin-top: 10px;
  padding: 7px;
  border: 1px solid #172633;
  background: #081018;
  color: #4e6274;
  font: 650 6px/1.4 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $panelsRoot 'VspSnapshotPanel.vue') $vspSnapshot

  Write-Host 'Right CIC components          : 3 CREATED' -ForegroundColor Green

  Write-Host "`n[6/12] BUILD BOTTOM STATUS COMPONENT" -ForegroundColor Yellow

  $statusBar=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <footer class="status-bar">
    <div class="status-left">
      <span class="ready-dot" />
      <strong>{{ telemetry.runtimeOnline ? 'READY' : 'PARTIAL' }}</strong>
    </div>

    <div class="status-field">
      <span>HUB</span>
      <strong>{{ telemetry.hubEnabledCount }}/{{ telemetry.hubPackageCount }} ENABLED</strong>
    </div>

    <div class="status-field">
      <span>VSP</span>
      <strong>{{ telemetry.checkpointId || telemetry.sessionId || 'NO SIGNAL' }}</strong>
    </div>

    <div class="status-field">
      <span>NETWORK</span>
      <strong>{{ telemetry.networkOnline ? 'ONLINE' : 'OFFLINE' }}</strong>
    </div>

    <div class="status-field grow">
      <span>LAST TELEMETRY</span>
      <strong>{{ telemetry.updatedAt || 'WAITING' }}</strong>
    </div>

    <div class="status-right">
      <span>VERTEX COCKPIT</span>
      <strong>V1</strong>
    </div>
  </footer>
</template>

<style scoped>
.status-bar {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 18px;
  padding: 0 10px;
  border-top: 1px solid var(--vertex-line-bright, #26394b);
  background: #070c12;
  color: #607284;
  font: 700 6px/1 ui-monospace, "Cascadia Code", Consolas, monospace;
}

.status-left {
  display: flex;
  align-items: center;
  gap: 6px;
}

.ready-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--vertex-green, #55d69e);
  box-shadow: 0 0 6px rgba(85,214,158,.6);
}

.status-left strong {
  color: #8aa49c;
}

.status-field {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 5px;
}

.status-field span {
  color: #3f5060;
}

.status-field strong {
  overflow: hidden;
  color: #718598;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.status-field.grow {
  flex: 1;
}

.status-right {
  display: flex;
  align-items: center;
  gap: 5px;
  color: #466177;
}

.status-right strong {
  color: var(--vertex-blue-bright, #3ab8ff);
}
</style>
'@
  WriteUtf8 (Join-Path $panelsRoot 'CockpitStatusBar.vue') $statusBar

  Write-Host 'Cockpit Status Bar             : CREATED' -ForegroundColor Green

  Write-Host "`n[7/12] BUILD MOTHERSHIP COCKPIT SHELL" -ForegroundColor Yellow

  $shell=@'
<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useCockpitTelemetry } from './cockpitTelemetry'
import ArdStatusPanel from './panels/ArdStatusPanel.vue'
import CockpitStatusBar from './panels/CockpitStatusBar.vue'
import HyperAgentPanel from './panels/HyperAgentPanel.vue'
import ProjectBrainPanel from './panels/ProjectBrainPanel.vue'
import ProjectStatusPanel from './panels/ProjectStatusPanel.vue'
import SystemMonitorPanel from './panels/SystemMonitorPanel.vue'
import VspSnapshotPanel from './panels/VspSnapshotPanel.vue'
import VspStatusPanel from './panels/VspStatusPanel.vue'
import VxnStatusPanel from './panels/VxnStatusPanel.vue'
import WorkspaceHealthPanel from './panels/WorkspaceHealthPanel.vue'

const RIGHT_WIDTH_KEY = 'vertex.cockpit.right-width'
const RIGHT_OPEN_KEY = 'vertex.cockpit.right-open'
const TOP_OPEN_KEY = 'vertex.cockpit.top-open'

const rightWidth = ref(320)
const rightOpen = ref(true)
const topOpen = ref(true)
const resizingRight = ref(false)

const { telemetry } = useCockpitTelemetry()

const shellStyle = computed(() => ({
  '--cockpit-right-width': rightOpen.value ? `${rightWidth.value}px` : '0px',
  '--cockpit-top-height': topOpen.value ? '68px' : '0px',
}))

function beginRightResize(event: MouseEvent) {
  if (!rightOpen.value) return

  event.preventDefault()
  resizingRight.value = true

  const onMove = (moveEvent: MouseEvent) => {
    const next = window.innerWidth - moveEvent.clientX
    rightWidth.value = Math.max(260, Math.min(520, next))
  }

  const onUp = () => {
    resizingRight.value = false
    window.removeEventListener('mousemove', onMove)
    window.removeEventListener('mouseup', onUp)
  }

  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', onUp)
}

function onKey(event: KeyboardEvent) {
  if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'c') {
    event.preventDefault()
    rightOpen.value = !rightOpen.value
  }

  if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 't') {
    event.preventDefault()
    topOpen.value = !topOpen.value
  }
}

watch(rightWidth, (value) => {
  localStorage.setItem(RIGHT_WIDTH_KEY, String(Math.round(value)))
})

watch(rightOpen, (value) => {
  localStorage.setItem(RIGHT_OPEN_KEY, value ? '1' : '0')
})

watch(topOpen, (value) => {
  localStorage.setItem(TOP_OPEN_KEY, value ? '1' : '0')
})

onMounted(() => {
  const savedWidth = Number(localStorage.getItem(RIGHT_WIDTH_KEY))
  const savedRight = localStorage.getItem(RIGHT_OPEN_KEY)
  const savedTop = localStorage.getItem(TOP_OPEN_KEY)

  if (Number.isFinite(savedWidth) && savedWidth >= 260) {
    rightWidth.value = Math.min(520, savedWidth)
  }

  if (savedRight !== null) rightOpen.value = savedRight === '1'
  if (savedTop !== null) topOpen.value = savedTop === '1'

  window.addEventListener('keydown', onKey)
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKey)
})
</script>

<template>
  <div
    class="vertex-cockpit"
    :style="shellStyle"
  >
    <header
      v-if="topOpen"
      class="cockpit-top-deck"
    >
      <div class="cockpit-brand">
        <div class="brand-mark">
          <span>V</span>
        </div>

        <div>
          <strong>VERTEX STUDIO AI</strong>
          <small>DEVELOPMENT // MOTHERSHIP BRIDGE</small>
        </div>
      </div>

      <ProjectStatusPanel :telemetry="telemetry" />
      <VspStatusPanel :telemetry="telemetry" />
      <VxnStatusPanel :telemetry="telemetry" />
      <ArdStatusPanel :telemetry="telemetry" />
      <ProjectBrainPanel :telemetry="telemetry" />
      <WorkspaceHealthPanel :telemetry="telemetry" />

      <div class="cockpit-clock">
        <span>MODE : CREATION</span>
        <strong>{{ telemetry.now }}</strong>
      </div>
    </header>

    <section class="cockpit-workspace">
      <main class="cockpit-editor-surface">
        <slot />
      </main>

      <aside
        v-if="rightOpen"
        class="cockpit-right-cic"
      >
        <button
          class="right-resizer"
          :class="{ active: resizingRight }"
          title="Resize CIC"
          @mousedown="beginRightResize"
        />

        <SystemMonitorPanel :telemetry="telemetry" />
        <HyperAgentPanel :telemetry="telemetry" />
        <VspSnapshotPanel :telemetry="telemetry" />
      </aside>
    </section>

    <CockpitStatusBar :telemetry="telemetry" />

    <nav class="cockpit-command-rail">
      <button
        :class="{ active: topOpen }"
        title="Ctrl+Shift+T"
        @click="topOpen = !topOpen"
      >
        TOP
      </button>

      <button
        :class="{ active: rightOpen }"
        title="Ctrl+Shift+C"
        @click="rightOpen = !rightOpen"
      >
        CIC
      </button>

      <span class="rail-separator" />

      <span class="rail-state">
        <i :class="{ online: telemetry.runtimeOnline }" />
        RUNTIME
      </span>

      <span class="rail-state">
        <i :class="{ online: telemetry.hubOnline }" />
        HUB
      </span>

      <span class="rail-state">
        <i :class="{ online: telemetry.liveOnline }" />
        LIVE
      </span>
    </nav>
  </div>
</template>

<style scoped>
.vertex-cockpit {
  --vertex-bg-deep: #070b10;
  --vertex-bg-panel: #0c121a;
  --vertex-bg-panel-raised: #111923;
  --vertex-bg-hover: #14202c;
  --vertex-line: #1c2935;
  --vertex-line-bright: #26394b;
  --vertex-text: #cbd5df;
  --vertex-muted: #718195;
  --vertex-faint: #455364;
  --vertex-blue: #168cff;
  --vertex-blue-bright: #3ab8ff;
  --vertex-blue-soft: #102c44;
  --vertex-green: #55d69e;
  --vertex-amber: #f1b85b;
  --vertex-red: #ff6f7c;

  position: relative;
  display: grid;
  width: 100%;
  height: 100vh;
  min-width: 0;
  min-height: 0;
  grid-template-rows:
    var(--cockpit-top-height, 68px)
    minmax(0, 1fr)
    24px;
  overflow: hidden;
  background:
    radial-gradient(circle at 62% -30%, rgba(20,113,180,.12), transparent 42%),
    var(--vertex-bg-deep);
  color: var(--vertex-text);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.cockpit-top-deck {
  position: relative;
  z-index: 20;
  display: grid;
  min-width: 0;
  grid-template-columns:
    232px
    minmax(125px, .8fr)
    minmax(125px, .8fr)
    minmax(125px, .8fr)
    minmax(125px, .8fr)
    minmax(150px, 1fr)
    minmax(145px, .9fr)
    138px;
  gap: 4px;
  padding: 6px 7px;
  border-bottom: 1px solid var(--vertex-line-bright);
  background:
    linear-gradient(90deg, rgba(25,135,224,.08), transparent 28%),
    linear-gradient(180deg, #101821, #080d13);
  box-shadow: 0 5px 20px rgba(0,0,0,.22);
}

.cockpit-top-deck::after {
  position: absolute;
  right: 0;
  bottom: -1px;
  left: 0;
  height: 1px;
  background:
    linear-gradient(90deg, transparent, rgba(33,150,243,.65), transparent 72%);
  content: "";
}

.cockpit-brand {
  display: flex;
  min-width: 0;
  align-items: center;
  padding: 0 9px;
  gap: 10px;
  border: 1px solid var(--vertex-line);
  background:
    linear-gradient(180deg, rgba(13,21,30,.9), rgba(7,12,18,.95));
}

.brand-mark {
  display: grid;
  width: 31px;
  height: 31px;
  flex: none;
  place-items: center;
  border: 1px solid #285b82;
  transform: rotate(45deg);
  background: #0b2638;
  box-shadow: 0 0 14px rgba(22,140,255,.12);
}

.brand-mark span {
  transform: rotate(-45deg);
  color: var(--vertex-blue-bright);
  font-size: 11px;
  font-weight: 820;
}

.cockpit-brand strong,
.cockpit-brand small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cockpit-brand strong {
  color: #dbe7f1;
  font-size: 12px;
  font-weight: 630;
  letter-spacing: .045em;
}

.cockpit-brand small {
  margin-top: 4px;
  color: #42586b;
  font: 700 6px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

:deep(.status-cell) {
  position: relative;
  min-width: 0;
  padding: 10px 12px;
  overflow: hidden;
  border: 1px solid var(--vertex-line);
  background:
    linear-gradient(160deg, rgba(17,25,35,.94), rgba(8,13,19,.96));
}

:deep(.status-cell)::after {
  position: absolute;
  top: 8px;
  right: 0;
  bottom: 8px;
  width: 2px;
  background:
    linear-gradient(
      180deg,
      transparent,
      rgba(22,140,255,.8),
      transparent
    );
  content: "";
}

:deep(.status-cell p),
:deep(.status-cell strong),
:deep(.status-cell span) {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:deep(.status-cell p) {
  margin: 0;
  color: #8999aa;
  font-size: 8px;
  font-weight: 700;
  letter-spacing: .025em;
}

:deep(.status-cell p b) {
  color: var(--vertex-muted);
  font: inherit;
}

:deep(.status-cell p b.online) {
  color: #9ece61;
}

:deep(.status-cell > strong) {
  margin-top: 4px;
  color: #aebdcb;
  font: 720 8px/1 ui-monospace, Consolas, monospace;
}

:deep(.status-cell > span) {
  margin-top: 4px;
  color: var(--vertex-faint);
  font: 650 6px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .05em;
}

.cockpit-clock {
  display: grid;
  align-content: center;
  justify-items: end;
  padding: 0 10px;
  border: 1px solid var(--vertex-line);
  background: rgba(7,12,18,.9);
}

.cockpit-clock span {
  color: #8c9cab;
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.cockpit-clock strong {
  margin-top: 6px;
  color: #d9e4ee;
  font: 500 14px/1 ui-monospace, Consolas, monospace;
}

.cockpit-workspace {
  position: relative;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns: minmax(0, 1fr) var(--cockpit-right-width, 320px);
  overflow: hidden;
}

.cockpit-editor-surface {
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  background: var(--vertex-bg-deep);
}

.cockpit-editor-surface > :deep(*) {
  max-height: 100%;
}

.cockpit-right-cic {
  position: relative;
  z-index: 16;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-rows: auto auto minmax(0, 1fr);
  gap: 6px;
  padding: 6px;
  overflow: auto;
  border-left: 1px solid var(--vertex-line-bright);
  background:
    linear-gradient(180deg, rgba(9,15,22,.98), rgba(6,10,15,.99));
  box-shadow: -8px 0 28px rgba(0,0,0,.2);
}

.cockpit-right-cic::-webkit-scrollbar {
  width: 7px;
}

.cockpit-right-cic::-webkit-scrollbar-track {
  background: #080d13;
}

.cockpit-right-cic::-webkit-scrollbar-thumb {
  border: 2px solid #080d13;
  border-radius: 8px;
  background: #253747;
}

.right-resizer {
  position: fixed;
  z-index: 21;
  top: var(--cockpit-top-height, 68px);
  bottom: 24px;
  width: 8px;
  margin-left: -10px;
  border: 0;
  background: transparent;
  cursor: ew-resize;
}

.right-resizer::after {
  position: absolute;
  top: 0;
  bottom: 0;
  left: 3px;
  width: 2px;
  background: transparent;
  content: "";
}

.right-resizer:hover::after,
.right-resizer.active::after {
  background: var(--vertex-blue);
  box-shadow: 0 0 9px rgba(22,140,255,.75);
}

.cockpit-command-rail {
  position: fixed;
  z-index: 9000;
  right: 8px;
  bottom: 31px;
  display: flex;
  height: 28px;
  align-items: center;
  padding: 0 6px;
  gap: 5px;
  border: 1px solid #1c3040;
  border-radius: 5px;
  background: rgba(7,12,18,.94);
  box-shadow: 0 8px 24px rgba(0,0,0,.28);
  backdrop-filter: blur(8px);
}

.cockpit-command-rail button {
  height: 20px;
  padding: 0 7px;
  border: 1px solid #1c2935;
  border-radius: 3px;
  background: #0a1118;
  color: #566879;
  font: 750 6px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.cockpit-command-rail button.active {
  border-color: #28516c;
  background: #102033;
  color: #65c5ff;
}

.rail-separator {
  width: 1px;
  height: 14px;
  background: #20303d;
}

.rail-state {
  display: flex;
  align-items: center;
  gap: 4px;
  color: #536677;
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.rail-state i {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #51333a;
}

.rail-state i.online {
  background: var(--vertex-green);
  box-shadow: 0 0 6px rgba(85,214,158,.55);
}

@media (max-width: 1280px) {
  .cockpit-top-deck {
    grid-template-columns:
      210px
      repeat(4, minmax(110px, 1fr))
      125px;
  }

  .cockpit-top-deck > :deep(.status-cell:nth-of-type(5)),
  .cockpit-top-deck > :deep(.status-cell:nth-of-type(6)) {
    display: none;
  }

  .cockpit-right-cic {
    padding: 4px;
  }
}

@media (max-width: 960px) {
  .cockpit-top-deck {
    grid-template-columns: 190px 1fr 1fr 110px;
  }

  .cockpit-top-deck > :deep(.status-cell:nth-of-type(n+3)) {
    display: none;
  }

  .cockpit-workspace {
    grid-template-columns: minmax(0, 1fr);
  }

  .cockpit-right-cic {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(88vw, var(--cockpit-right-width, 320px));
  }
}
</style>
'@
  WriteUtf8 (Join-Path $cockpitRoot 'VertexCockpitShell.vue') $shell

  Write-Host 'VertexCockpitShell            : CREATED' -ForegroundColor Green
  Write-Host 'Top Status Deck               : COMPONENTIZED' -ForegroundColor Green
  Write-Host 'Right CIC                     : COMPONENTIZED' -ForegroundColor Green
  Write-Host 'Bottom Status Bar             : COMPONENTIZED' -ForegroundColor Green
  Write-Host 'Layout persistence            : ONLINE' -ForegroundColor Green
  Write-Host 'CIC resize                    : ONLINE' -ForegroundColor Green

  Write-Host "`n[8/12] WRAP EXISTING EDITOR WITH COCKPIT SHELL" -ForegroundColor Yellow

  $editorText=[IO.File]::ReadAllText($editor)

  if($editorText.Contains('VertexCockpitShell')){
    throw 'VertexCockpitShell already referenced; refusing duplicate docking.'
  }

  $previewImport="import VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'"
  if(-not $editorText.Contains($previewImport)){
    throw 'VertexLivePreview import anchor missing.'
  }

  $editorText=$editorText.Replace(
    $previewImport,
    $previewImport+"`r`nimport VertexCockpitShell from '../vertex-cockpit/VertexCockpitShell.vue'"
  )

  $templateStart=[regex]::Match(
    $editorText,
    '<template(?:\s[^>]*)?>',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )

  if(-not $templateStart.Success){
    throw 'VertexEditorDock root template open tag missing.'
  }

  $styleIndex=$editorText.IndexOf('<style',$templateStart.Index,[StringComparison]::OrdinalIgnoreCase)
  $searchEnd=if($styleIndex -ge 0){$styleIndex}else{$editorText.Length}

  $templateEnd=$editorText.LastIndexOf(
    '</template>',
    $searchEnd,
    [StringComparison]::OrdinalIgnoreCase
  )

  if($templateEnd -lt 0 -or $templateEnd -le $templateStart.Index){
    throw 'VertexEditorDock root template close tag missing.'
  }

  $innerStart=$templateStart.Index+$templateStart.Length
  $innerLength=$templateEnd-$innerStart
  $inner=$editorText.Substring($innerStart,$innerLength)

  if($inner.Contains('VertexCockpitShell')){
    throw 'Cockpit wrapper already present inside template.'
  }

  $wrappedInner="`r`n  <VertexCockpitShell>"+$inner+"`r`n  </VertexCockpitShell>`r`n"

  $editorText=
    $editorText.Substring(0,$innerStart)+
    $wrappedInner+
    $editorText.Substring($templateEnd)

  WriteUtf8 $editor $editorText

  Write-Host 'Existing editor               : PRESERVED AS SLOT' -ForegroundColor Green
  Write-Host 'Cockpit wrapper                : DOCKED' -ForegroundColor Green

  Write-Host "`n[9/12] FRONTEND TYPECHECK / VISUAL BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[cockpit] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }

    RunChecked '[cockpit] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[10/12] STATIC COMPONENT / SAFETY AUDIT" -ForegroundColor Yellow

  $requiredComponents=@(
    'VertexCockpitShell.vue',
    'cockpitTelemetry.ts',
    'panelRegistry.ts',
    'panels\CockpitPanelFrame.vue',
    'panels\ProjectStatusPanel.vue',
    'panels\VspStatusPanel.vue',
    'panels\VxnStatusPanel.vue',
    'panels\ArdStatusPanel.vue',
    'panels\ProjectBrainPanel.vue',
    'panels\WorkspaceHealthPanel.vue',
    'panels\SystemMonitorPanel.vue',
    'panels\HyperAgentPanel.vue',
    'panels\VspSnapshotPanel.vue',
    'panels\CockpitStatusBar.vue'
  )

  foreach($relative in $requiredComponents){
    $path=Join-Path $cockpitRoot $relative
    if(-not(Test-Path -LiteralPath $path)){
      throw "Cockpit component missing: $relative"
    }
    Write-Host ("  {0,-38} GREEN" -f $relative) -ForegroundColor Green
  }

  $cockpitText=(
    Get-ChildItem -LiteralPath $cockpitRoot -Recurse -File |
    ForEach-Object {[IO.File]::ReadAllText($_.FullName)}
  ) -join "`n"

  $editorNow=[IO.File]::ReadAllText($editor)

  $audits=@(
    [pscustomobject]@{
      Name='FME Deep'
      Pass=$cockpitText.Contains('#070b10')
    },
    [pscustomobject]@{
      Name='Vertex Blue'
      Pass=$cockpitText.Contains('#168cff')
    },
    [pscustomobject]@{
      Name='Bright Blue'
      Pass=$cockpitText.Contains('#3ab8ff')
    },
    [pscustomobject]@{
      Name='Success Green'
      Pass=$cockpitText.Contains('#55d69e')
    },
    [pscustomobject]@{
      Name='No eval'
      Pass=(-not $cockpitText.Contains('eval('))
    },
    [pscustomobject]@{
      Name='No remote URL import'
      Pass=(-not $cockpitText.Contains('import("http://') -and -not $cockpitText.Contains("import('http://") -and -not $cockpitText.Contains('import("https://') -and -not $cockpitText.Contains("import('https://"))
    },
    [pscustomobject]@{
      Name='No arbitrary shell'
      Pass=(-not $cockpitText.Contains('Command::new') -and -not $cockpitText.Contains('powershell.exe') -and -not $cockpitText.Contains('cmd.exe'))
    },
    [pscustomobject]@{
      Name='Editor cockpit import'
      Pass=$editorNow.Contains("import VertexCockpitShell from '../vertex-cockpit/VertexCockpitShell.vue'")
    },
    [pscustomobject]@{
      Name='Editor cockpit wrapper'
      Pass=$editorNow.Contains('<VertexCockpitShell>')
    },
    [pscustomobject]@{
      Name='Live Preview preserved'
      Pass=$editorNow.Contains('<VertexLivePreview />')
    },
    [pscustomobject]@{
      Name='VertexHub preserved'
      Pass=$editorNow.Contains('<VertexHubDock />')
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "Cockpit safety audit RED: $($audit.Name)"}
    Write-Host ("  {0,-38} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[11/12] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  $previousCargoTarget=$env:CARGO_TARGET_DIR
  try{
    New-Item -ItemType Directory -Path $tauriCheckTarget -Force|Out-Null
    $env:CARGO_TARGET_DIR=$tauriCheckTarget

    RunChecked '[release] isolated Tauri cargo check' {
      & $cargo.Source check --manifest-path $tauriCargo --all-targets
    }
  }finally{
    $env:CARGO_TARGET_DIR=$previousCargoTarget
  }

  Push-Location $ui
  try{
    RunChecked '[release] final frontend build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[12/12] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.vsa-cockpit-shell.v1'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA COCKPIT SHELL V1'
    architecture=[ordered]@{
      shell='VertexCockpitShell'
      editor_preservation='SLOT_WRAPPED'
      panel_boundary='INDEPENDENT_VUE_COMPONENTS'
      panel_count=10
      panel_registry='ONLINE'
      package_ready='YES'
      runtime_bus='UNCHANGED'
      mothership='UNCHANGED'
      vertexhub='PRESERVED'
      gui_live_preview='PRESERVED'
    }
    telemetry=[ordered]@{
      runtime_command=$runtimeCommand
      hub_state_command=$hubStateCommand
      live_signal_command=if($liveCommand){$liveCommand}else{'NOT_DISCOVERED'}
      fake_metrics='DENIED'
      missing_data_behavior='NO_SIGNAL_OR_NOT_WIRED'
      browser_hardware_threads='MEASURED_WHEN_EXPOSED'
      browser_js_heap='MEASURED_WHEN_EXPOSED'
      webgl_gpu_renderer='MEASURED_WHEN_EXPOSED'
    }
    layout=[ordered]@{
      top_status_deck='ONLINE'
      right_cic='ONLINE'
      bottom_status_bar='ONLINE'
      right_cic_resize='ONLINE'
      panel_toggle='ONLINE'
      persistence='LOCALSTORAGE'
    }
    design=[ordered]@{
      source='FME_DERIVED_VERTEX'
      bg_deep='#070b10'
      panel='#0c121a'
      raised='#111923'
      vertex_blue='#168cff'
      bright_blue='#3ab8ff'
      success='#55d69e'
      warning='#f1b85b'
      error='#ff6f7c'
    }
    validation=[ordered]@{
      vue_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    next_target='COCKPIT PANEL HUB PACKAGING / DRAGGABLE LAYOUT'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - VSA COCKPIT SHELL V1 GREEN
============================================================
 Mothership Cockpit Shell                 ONLINE
 Existing Editor Surface                  PRESERVED
 Top Status Deck                          ONLINE
 Right CIC                                ONLINE
 Bottom Status Bar                        ONLINE
 Independent Panel Components             10
 Panel Registry                           ONLINE
 Package-Ready Boundaries                 ONLINE
 Runtime Telemetry                        REAL SIGNAL ONLY
 Missing Metrics                          NO SIGNAL / NOT WIRED
 System Monitor                           ONLINE
 Hyper Agent Panel                        ONLINE
 VSP Snapshot Panel                       ONLINE
 CIC Resize                               ONLINE
 Layout Persistence                       ONLINE
 FME Vertex Design                        LOCKED
 Vertex Blue #168cff                      LOCKED
 Bright Blue #3ab8ff                      LOCKED
 Arbitrary Eval                           DENIED
 Remote Runtime Import                    DENIED
 Arbitrary Shell                          DENIED
 Controller Mutation                      DENIED
 GUI Live Preview                         PRESERVED
 VertexHub                                PRESERVED
 Frontend Typecheck                       GREEN
 Frontend Build                           GREEN
 Tauri Check                              GREEN
 Workspace Release Gate                   GREEN
------------------------------------------------------------
 NEXT TARGET:
 COCKPIT PANEL HUB PACKAGING / DRAGGABLE LAYOUT
============================================================
 VSA BRIDGE: ONLINE
 WE ARE VERTEX.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VSA COCKPIT SHELL V1 RED - DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  if(Test-Path -LiteralPath $cockpitRoot){
    Copy-Item -LiteralPath $cockpitRoot -Destination (Join-Path $failed 'vertex-cockpit') -Recurse -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $editor){
    Copy-Item -LiteralPath $editor -Destination (Join-Path $failed 'VertexEditorDock.failed.vue') -Force -ErrorAction SilentlyContinue
  }

  $editorBackup=Join-Path $backup 'VertexEditorDock.vue'
  if(Test-Path -LiteralPath $editorBackup){
    Copy-Item -LiteralPath $editorBackup -Destination $editor -Force
  }

  if(Test-Path -LiteralPath $cockpitRoot){
    Remove-Item -LiteralPath $cockpitRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Host 'Editor rollback                    : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Cockpit source rollback            : COMPLETE' -ForegroundColor Yellow
  Write-Host 'VertexHub                          : UNTOUCHED' -ForegroundColor Yellow
  Write-Host 'Mothership / Runtime Bus           : UNTOUCHED' -ForegroundColor Yellow
  Write-Host 'GUI Live Preview                   : RESTORED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}
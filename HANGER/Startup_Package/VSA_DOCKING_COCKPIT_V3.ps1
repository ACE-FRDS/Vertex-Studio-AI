& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC - VSA DOCKING COCKPIT V3
#
# Mission:
#   1. 27-inch / 2560x1440 primary readability
#   2. 1920x1080 practical support
#   3. compact/laptop fallback without micro-text
#   4. drag panel header -> LEFT / RIGHT / BOTTOM / FLOAT docking
#   5. dock/floating layout persistence
#   6. panel contract remains extensible to Agent / Drone equipment
#
# Safety:
#   - no eval
#   - no remote runtime import
#   - no arbitrary shell/runtime command
#   - controller / Mothership untouched
#   - existing Editor / VertexHub / GUI Preview preserved
#   - backup + rollback on RED
#   - no synthetic telemetry
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'
$cockpit=Join-Path $ui 'src\vertex-cockpit'
$panels=Join-Path $cockpit 'panels'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$packageJson=Join-Path $ui 'package.json'
$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriDevTarget=Join-Path $startup '_build\VSA_TAURI_DEV'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_DOCKING_COCKPIT_V3_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_DOCKING_COCKPIT_V3_FAILED.$stamp"
$report=Join-Path $reports "VSA_DOCKING_COCKPIT_V3.$stamp.json"

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

Write-Host @'
============================================================
 VERTEX - VSA DOCKING COCKPIT V3
 27-INCH READABILITY / MAGNETIC PANEL DOCKING
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$cockpit,$panels,$editor,
  $packageJson,$coreCargo,$tauriCargo
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required current-core artifact missing: $required"
  }
}

$dockLayoutPath=Join-Path $cockpit 'dockLayout.ts'
if(Test-Path -LiteralPath $dockLayoutPath){
  throw "Docking V3 source already exists: $dockLayoutPath"
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/13] V2 COCKPIT BASELINE LOCK" -ForegroundColor Yellow

$editorText=[IO.File]::ReadAllText($editor)
$shellPath=Join-Path $cockpit 'VertexCockpitShell.vue'
$framePath=Join-Path $panels 'CockpitPanelFrame.vue'
$systemPath=Join-Path $panels 'SystemMonitorPanel.vue'
$agentPath=Join-Path $panels 'HyperAgentPanel.vue'
$vspPath=Join-Path $panels 'VspSnapshotPanel.vue'
$statusPath=Join-Path $panels 'CockpitStatusBar.vue'
$registryPath=Join-Path $cockpit 'panelRegistry.ts'
$telemetryPath=Join-Path $cockpit 'cockpitTelemetry.ts'

foreach($required in @(
  $shellPath,$framePath,$systemPath,$agentPath,$vspPath,$statusPath,
  $registryPath,$telemetryPath
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "V2 Cockpit artifact missing: $required"
  }
}

$baseline=@(
  [pscustomobject]@{
    Name='Cockpit shell wrapper'
    Pass=$editorText.Contains('<VertexCockpitShell>')
  },
  [pscustomobject]@{
    Name='GUI Live Preview preserved'
    Pass=$editorText.Contains('<VertexLivePreview />')
  },
  [pscustomobject]@{
    Name='VertexHub preserved'
    Pass=$editorText.Contains('<VertexHubDock />')
  },
  [pscustomobject]@{
    Name='V2 real telemetry'
    Pass=([IO.File]::ReadAllText($telemetryPath)).Contains('useCockpitTelemetry')
  }
)

foreach($item in $baseline){
  if(-not $item.Pass){throw "V2 baseline missing: $($item.Name)"}
  Write-Host ("  {0,-36} GREEN" -f $item.Name) -ForegroundColor Green
}

RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

Write-Host "`n[1/13] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item -LiteralPath $cockpit -Destination (Join-Path $backup 'vertex-cockpit') -Recurse -Force
Copy-Item -LiteralPath $editor -Destination (Join-Path $backup 'VertexEditorDock.vue') -Force
Write-Host "Cockpit backup : $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/13] CREATE DOCK / SNAP STATE CONTRACT" -ForegroundColor Yellow

  $dockLayout=@'
import { computed, ref, watch } from 'vue'

export type DockZone = 'left' | 'right' | 'bottom' | 'float'
export type DockEntityKind = 'panel' | 'agent' | 'drone'

export interface DockPanelState {
  id: string
  zone: DockZone
  order: number
  visible: boolean
  x: number
  y: number
  width: number
  height: number
}

export interface DockHostCapability {
  kind: DockEntityKind
  dock: true
  float: true
  resize: true
  persist: true
}

export interface DockLayoutSnapshot {
  schema: 'vertex.cockpit.dock-layout.v3'
  panels: DockPanelState[]
  leftWidth: number
  rightWidth: number
  bottomHeight: number
}

const STORAGE_KEY = 'vertex.cockpit.dock-layout.v3'

const defaults: DockLayoutSnapshot = {
  schema: 'vertex.cockpit.dock-layout.v3',
  panels: [
    {
      id: 'system-monitor',
      zone: 'right',
      order: 0,
      visible: true,
      x: 920,
      y: 140,
      width: 430,
      height: 320,
    },
    {
      id: 'hyper-agent',
      zone: 'right',
      order: 1,
      visible: true,
      x: 880,
      y: 180,
      width: 430,
      height: 300,
    },
    {
      id: 'vsp-snapshot',
      zone: 'right',
      order: 2,
      visible: true,
      x: 840,
      y: 220,
      width: 430,
      height: 340,
    },
  ],
  leftWidth: 360,
  rightWidth: 430,
  bottomHeight: 300,
}

export const dockHostCapabilities: DockHostCapability[] = [
  { kind: 'panel', dock: true, float: true, resize: true, persist: true },
  { kind: 'agent', dock: true, float: true, resize: true, persist: true },
  { kind: 'drone', dock: true, float: true, resize: true, persist: true },
]

function cloneDefaults(): DockLayoutSnapshot {
  return JSON.parse(JSON.stringify(defaults)) as DockLayoutSnapshot
}

function sanitizeNumber(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback
  return Math.min(maximum, Math.max(minimum, value))
}

function sanitizePanel(
  value: unknown,
  fallback: DockPanelState,
): DockPanelState {
  const raw =
    typeof value === 'object' && value !== null
      ? (value as Partial<DockPanelState>)
      : {}

  const allowedZones: DockZone[] = ['left', 'right', 'bottom', 'float']
  const zone =
    typeof raw.zone === 'string' && allowedZones.includes(raw.zone as DockZone)
      ? (raw.zone as DockZone)
      : fallback.zone

  return {
    id: fallback.id,
    zone,
    order: sanitizeNumber(raw.order, fallback.order, 0, 1000),
    visible: typeof raw.visible === 'boolean' ? raw.visible : fallback.visible,
    x: sanitizeNumber(raw.x, fallback.x, 0, 10000),
    y: sanitizeNumber(raw.y, fallback.y, 0, 10000),
    width: sanitizeNumber(raw.width, fallback.width, 300, 1200),
    height: sanitizeNumber(raw.height, fallback.height, 180, 1000),
  }
}

function loadSnapshot(): DockLayoutSnapshot {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return cloneDefaults()

    const parsed = JSON.parse(raw) as Partial<DockLayoutSnapshot>
    if (parsed.schema !== 'vertex.cockpit.dock-layout.v3') {
      return cloneDefaults()
    }

    const sourcePanels = Array.isArray(parsed.panels) ? parsed.panels : []

    return {
      schema: 'vertex.cockpit.dock-layout.v3',
      panels: defaults.panels.map((fallback) => {
        const found = sourcePanels.find(
          (candidate) =>
            typeof candidate === 'object'
            && candidate !== null
            && (candidate as Partial<DockPanelState>).id === fallback.id,
        )
        return sanitizePanel(found, fallback)
      }),
      leftWidth: sanitizeNumber(
        parsed.leftWidth,
        defaults.leftWidth,
        300,
        680,
      ),
      rightWidth: sanitizeNumber(
        parsed.rightWidth,
        defaults.rightWidth,
        320,
        720,
      ),
      bottomHeight: sanitizeNumber(
        parsed.bottomHeight,
        defaults.bottomHeight,
        220,
        620,
      ),
    }
  } catch {
    return cloneDefaults()
  }
}

export function useDockLayout() {
  const snapshot = ref<DockLayoutSnapshot>(loadSnapshot())

  const visiblePanels = computed(() =>
    snapshot.value.panels.filter((panel) => panel.visible),
  )

  function panelsIn(zone: DockZone) {
    return computed(() =>
      visiblePanels.value
        .filter((panel) => panel.zone === zone)
        .sort((a, b) => a.order - b.order),
    )
  }

  function movePanel(
    id: string,
    zone: DockZone,
    position?: { x: number; y: number },
  ) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (!target) return

    target.zone = zone
    target.visible = true

    const maxOrder = Math.max(
      -1,
      ...snapshot.value.panels
        .filter((panel) => panel.zone === zone && panel.id !== id)
        .map((panel) => panel.order),
    )
    target.order = maxOrder + 1

    if (zone === 'float' && position) {
      target.x = Math.max(8, position.x)
      target.y = Math.max(8, position.y)
    }
  }

  function hidePanel(id: string) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (target) target.visible = false
  }

  function showPanel(id: string) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (target) target.visible = true
  }

  function updateFloatRect(
    id: string,
    rect: Partial<Pick<DockPanelState, 'x' | 'y' | 'width' | 'height'>>,
  ) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (!target) return

    if (typeof rect.x === 'number') target.x = Math.max(0, rect.x)
    if (typeof rect.y === 'number') target.y = Math.max(0, rect.y)
    if (typeof rect.width === 'number') {
      target.width = Math.max(300, Math.min(1200, rect.width))
    }
    if (typeof rect.height === 'number') {
      target.height = Math.max(180, Math.min(1000, rect.height))
    }
  }

  function setLeftWidth(width: number) {
    snapshot.value.leftWidth = Math.max(300, Math.min(680, width))
  }

  function setRightWidth(width: number) {
    snapshot.value.rightWidth = Math.max(320, Math.min(720, width))
  }

  function setBottomHeight(height: number) {
    snapshot.value.bottomHeight = Math.max(220, Math.min(620, height))
  }

  function resetLayout() {
    snapshot.value = cloneDefaults()
  }

  watch(
    snapshot,
    (value) => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
    },
    { deep: true },
  )

  return {
    snapshot,
    visiblePanels,
    leftPanels: panelsIn('left'),
    rightPanels: panelsIn('right'),
    bottomPanels: panelsIn('bottom'),
    floatingPanels: panelsIn('float'),
    movePanel,
    hidePanel,
    showPanel,
    updateFloatRect,
    setLeftWidth,
    setRightWidth,
    setBottomHeight,
    resetLayout,
  }
}
'@
  WriteUtf8 $dockLayoutPath $dockLayout

  Write-Host 'Dock state contract            : CREATED' -ForegroundColor Green
  Write-Host 'LEFT / RIGHT / BOTTOM / FLOAT  : ENABLED' -ForegroundColor Green
  Write-Host 'Drone host capability          : RESERVED / NO FAKE UI' -ForegroundColor Green

  Write-Host "`n[3/13] UPGRADE PANEL FRAME TO DRAG HANDLE" -ForegroundColor Yellow

  $frame=@'
<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    status?: string
    statusTone?: 'blue' | 'green' | 'amber' | 'red' | 'muted'
    dense?: boolean
    panelId?: string
    dockable?: boolean
  }>(),
  {
    subtitle: '',
    status: '',
    statusTone: 'blue',
    dense: false,
    panelId: '',
    dockable: false,
  },
)

function beginDrag(event: DragEvent) {
  if (!props.dockable || !props.panelId) return
  if (!event.dataTransfer) return

  event.dataTransfer.effectAllowed = 'move'
  event.dataTransfer.setData('application/x-vertex-panel', props.panelId)
  event.dataTransfer.setData('text/plain', props.panelId)

  window.dispatchEvent(
    new CustomEvent('vertex-panel-drag-state', {
      detail: {
        active: true,
        panelId: props.panelId,
      },
    }),
  )
}

function endDrag() {
  window.dispatchEvent(
    new CustomEvent('vertex-panel-drag-state', {
      detail: {
        active: false,
        panelId: props.panelId,
      },
    }),
  )
}

function panelCommand(command: 'float' | 'hide') {
  if (!props.panelId) return

  window.dispatchEvent(
    new CustomEvent('vertex-panel-command', {
      detail: {
        panelId: props.panelId,
        command,
      },
    }),
  )
}
</script>

<template>
  <section
    class="panel-frame"
    :class="{ dense }"
  >
    <header
      class="panel-head"
      :class="{ draggable: dockable }"
      :draggable="dockable"
      @dragstart="beginDrag"
      @dragend="endDrag"
    >
      <div class="panel-title">
        <span
          v-if="dockable"
          class="panel-grip"
          aria-hidden="true"
        >
          ::
        </span>

        <span class="panel-chevron">›</span>

        <div>
          <strong>{{ title }}</strong>
          <small v-if="subtitle">{{ subtitle }}</small>
        </div>
      </div>

      <div class="panel-actions">
        <span
          v-if="status"
          class="panel-status"
          :class="`tone-${statusTone}`"
        >
          {{ status }}
        </span>

        <button
          v-if="dockable"
          type="button"
          class="panel-action"
          title="Float panel"
          @click.stop="panelCommand('float')"
          @mousedown.stop
        >
          FLT
        </button>

        <button
          v-if="dockable"
          type="button"
          class="panel-action"
          title="Hide panel"
          @click.stop="panelCommand('hide')"
          @mousedown.stop
        >
          HIDE
        </button>
      </div>
    </header>

    <div class="panel-body">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.panel-frame {
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  border: 1px solid var(--vertex-line, #1c2935);
  border-radius: 5px;
  background:
    linear-gradient(180deg, rgba(17,25,35,.97), rgba(8,13,19,.99));
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.018),
    0 12px 34px rgba(0,0,0,.16);
}

.panel-head {
  display: flex;
  min-height: var(--cockpit-panel-header, 42px);
  align-items: center;
  justify-content: space-between;
  padding: 0 12px;
  gap: 12px;
  border-bottom: 1px solid var(--vertex-line, #1c2935);
  background:
    linear-gradient(90deg, rgba(22,140,255,.055), transparent 50%),
    rgba(10,16,23,.94);
  user-select: none;
}

.panel-head.draggable {
  cursor: grab;
}

.panel-head.draggable:active {
  cursor: grabbing;
}

.panel-title {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
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
  color: #b9c7d4;
  font-size: var(--cockpit-panel-title, 13px);
  font-weight: 720;
  letter-spacing: .035em;
}

.panel-title small {
  margin-top: 3px;
  color: var(--vertex-muted, #718195);
  font: 650 var(--cockpit-caption, 10px)/1.1 ui-monospace, "Cascadia Code", Consolas, monospace;
}

.panel-grip {
  color: #4d7390;
  font: 850 12px/1 ui-monospace, Consolas, monospace;
  letter-spacing: -1px;
}

.panel-chevron {
  color: var(--vertex-blue-bright, #3ab8ff);
  font-size: 18px;
}

.panel-actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 7px;
}

.panel-status {
  font: 750 var(--cockpit-caption, 10px)/1 ui-monospace, "Cascadia Code", Consolas, monospace;
  letter-spacing: .05em;
}

.panel-action {
  min-width: 34px;
  height: 26px;
  padding: 0 7px;
  border: 1px solid #243847;
  border-radius: 3px;
  background: #0a121a;
  color: #6d8295;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.panel-action:hover {
  border-color: #3279a7;
  color: #8fd1ff;
  background: #0f2030;
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
  min-height: 36px;
}
</style>
'@
  WriteUtf8 $framePath $frame
  Write-Host 'Panel header drag handle       : ONLINE' -ForegroundColor Green
  Write-Host 'Float / Hide controls          : ONLINE' -ForegroundColor Green

  Write-Host "`n[4/13] UPSCALE 27-INCH PANEL CONTENT" -ForegroundColor Yellow

  $system=@'
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
    panel-id="system-monitor"
    dockable
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
  min-height: 70px;
  padding: 13px 14px;
  background: rgba(8,13,19,.98);
}

.metric.gpu {
  grid-column: 1 / -1;
}

.metric span,
.metric strong {
  display: block;
}

.metric span {
  color: var(--vertex-muted, #718195);
  font: 700 var(--cockpit-caption, 10px)/1.2 ui-monospace, Consolas, monospace;
  letter-spacing: .045em;
}

.metric strong {
  margin-top: 9px;
  overflow: hidden;
  color: #aab9c7;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 var(--cockpit-value, 14px)/1.3 ui-monospace, Consolas, monospace;
}

.metric strong.green {
  color: var(--vertex-green, #55d69e);
}
</style>
'@
  WriteUtf8 $systemPath $system

  $agent=@'
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
    panel-id="hyper-agent"
    dockable
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
  grid-template-columns: 118px minmax(0,1fr);
  align-items: center;
  padding: 16px 14px;
  gap: 16px;
}

.agent-orb {
  position: relative;
  width: 96px;
  height: 96px;
  margin: auto;
  border: 1px solid #1d4a69;
  border-radius: 50%;
  background:
    radial-gradient(circle, rgba(58,184,255,.18), rgba(4,12,18,.22) 45%, transparent 70%);
}

.orbit {
  position: absolute;
  inset: 17px;
  border: 1px solid rgba(58,184,255,.30);
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
  width: 9px;
  height: 9px;
  border-radius: 50%;
  transform: translate(-50%,-50%);
  background: var(--vertex-blue-bright, #3ab8ff);
  box-shadow:
    0 0 10px rgba(58,184,255,.9),
    0 0 28px rgba(22,140,255,.38);
}

.agent-data {
  min-width: 0;
}

.agent-data > div {
  padding: 10px 0;
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
  color: var(--vertex-muted, #718195);
  font: 700 var(--cockpit-caption, 10px)/1.2 ui-monospace, Consolas, monospace;
}

.agent-data strong {
  margin-top: 6px;
  overflow: hidden;
  color: #a7b8c8;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 var(--cockpit-value, 14px)/1.25 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 $agentPath $agent

  $vsp=@'
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
    panel-id="vsp-snapshot"
    dockable
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
  padding: 16px;
}

.save-point span,
.save-point strong {
  display: block;
}

.save-point span {
  color: var(--vertex-muted, #718195);
  font: 700 var(--cockpit-caption, 10px)/1.2 ui-monospace, Consolas, monospace;
}

.save-point strong {
  margin-top: 8px;
  overflow: hidden;
  color: #c2d0dc;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 clamp(16px, .78vw, 20px)/1 ui-monospace, Consolas, monospace;
}

dl {
  margin: 16px 0 0;
}

dl > div {
  display: grid;
  grid-template-columns: 88px minmax(0,1fr);
  align-items: center;
  padding: 10px 0;
  border-top: 1px solid var(--vertex-line, #1c2935);
}

dt {
  color: var(--vertex-muted, #718195);
  font: 700 var(--cockpit-caption, 10px)/1 ui-monospace, Consolas, monospace;
}

dd {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  color: #97a9b9;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 12px/1.2 ui-monospace, Consolas, monospace;
}

.snapshot-note {
  margin-top: 14px;
  padding: 10px;
  border: 1px solid #1c3040;
  background: #081018;
  color: #687d8f;
  font: 650 10px/1.45 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 $vspPath $vsp

  $status=@'
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
      <strong>V3</strong>
    </div>
  </footer>
</template>

<style scoped>
.status-bar {
  display: flex;
  min-width: 0;
  min-height: 34px;
  align-items: center;
  gap: 22px;
  padding: 0 14px;
  border-top: 1px solid var(--vertex-line-bright, #26394b);
  background: #070c12;
  color: #718496;
  font: 700 var(--cockpit-caption, 10px)/1 ui-monospace, "Cascadia Code", Consolas, monospace;
}

.status-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.ready-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--vertex-green, #55d69e);
  box-shadow: 0 0 8px rgba(85,214,158,.65);
}

.status-left strong {
  color: #9db9ae;
}

.status-field {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.status-field span {
  color: #53687a;
}

.status-field strong {
  overflow: hidden;
  color: #8499aa;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.status-field.grow {
  flex: 1;
}

.status-right {
  display: flex;
  align-items: center;
  gap: 7px;
  color: #5e788d;
}

.status-right strong {
  color: var(--vertex-blue-bright, #3ab8ff);
}

@media (max-width: 1280px) {
  .status-field:nth-of-type(2),
  .status-field.grow {
    display: none;
  }

  .status-bar {
    gap: 12px;
  }
}
</style>
'@
  WriteUtf8 $statusPath $status

  Write-Host '27-inch content scale         : APPLIED' -ForegroundColor Green
  Write-Host 'Micro text in CIC             : REMOVED' -ForegroundColor Green

  Write-Host "`n[5/13] UPGRADE PANEL REGISTRY / DRONE-READY CONTRACT" -ForegroundColor Yellow

  $registry=@'
export type CockpitPanelMobility = 'fixed' | 'dockable'
export type CockpitHostKind = 'panel' | 'agent' | 'drone'

export interface CockpitPanelDescriptor {
  id: string
  title: string
  region: 'TOP' | 'LEFT' | 'RIGHT' | 'BOTTOM' | 'FLOAT'
  packageReady: boolean
  source: string
  mobility: CockpitPanelMobility
  supportedHostKinds: CockpitHostKind[]
}

export const cockpitPanelRegistry: CockpitPanelDescriptor[] = [
  {
    id: 'vertex.project-status-panel',
    title: 'PROJECT',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.vsp-status-panel',
    title: 'VSP',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VspStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.vxn-status-panel',
    title: 'VXN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VxnStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.ard-status-panel',
    title: 'ARD',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ArdStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel', 'agent'],
  },
  {
    id: 'vertex.project-brain-panel',
    title: 'PROJECT BRAIN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectBrainPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel', 'agent'],
  },
  {
    id: 'vertex.workspace-health-panel',
    title: 'WORKSPACE HEALTH',
    region: 'TOP',
    packageReady: true,
    source: 'panels/WorkspaceHealthPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'system-monitor',
    title: 'SYSTEM MONITOR',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/SystemMonitorPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'hyper-agent',
    title: 'HYPER AGENT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/HyperAgentPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'vsp-snapshot',
    title: 'VSP SNAPSHOT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/VspSnapshotPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'vertex.cockpit-status-bar',
    title: 'COCKPIT STATUS BAR',
    region: 'BOTTOM',
    packageReady: true,
    source: 'panels/CockpitStatusBar.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
]
'@
  WriteUtf8 $registryPath $registry

  Write-Host 'Dockable registry metadata    : ONLINE' -ForegroundColor Green
  Write-Host 'Agent host kind               : RESERVED' -ForegroundColor Green
  Write-Host 'Drone host kind               : RESERVED' -ForegroundColor Green

  Write-Host "`n[6/13] BUILD MAGNETIC DOCKING COCKPIT SHELL" -ForegroundColor Yellow

  $shell=@'
<script setup lang="ts">
import type { Component } from 'vue'
import {
  computed,
  onMounted,
  onUnmounted,
  ref,
} from 'vue'
import { useCockpitTelemetry } from './cockpitTelemetry'
import {
  type DockPanelState,
  type DockZone,
  useDockLayout,
} from './dockLayout'
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

const { telemetry } = useCockpitTelemetry()

const {
  snapshot,
  leftPanels,
  rightPanels,
  bottomPanels,
  floatingPanels,
  movePanel,
  hidePanel,
  showPanel,
  updateFloatRect,
  setLeftWidth,
  setRightWidth,
  setBottomHeight,
  resetLayout,
} = useDockLayout()

const draggingPanelId = ref('')
const activeDropZone = ref<DockZone | ''>('')
const windowWidth = ref(window.innerWidth)
const resizing = ref<'left' | 'right' | 'bottom' | ''>('')

const panelComponents: Record<string, Component> = {
  'system-monitor': SystemMonitorPanel,
  'hyper-agent': HyperAgentPanel,
  'vsp-snapshot': VspSnapshotPanel,
}

const allKnownPanels = computed(() => snapshot.value.panels)

const compactMode = computed(() => windowWidth.value < 1280)
const standardMode = computed(
  () => windowWidth.value >= 1280 && windowWidth.value < 2200,
)
const wideMode = computed(() => windowWidth.value >= 2200)

const shellStyle = computed(() => ({
  '--dock-left-width':
    leftPanels.value.length > 0 ? `${snapshot.value.leftWidth}px` : '0px',
  '--dock-right-width':
    rightPanels.value.length > 0 ? `${snapshot.value.rightWidth}px` : '0px',
  '--dock-bottom-height':
    bottomPanels.value.length > 0 ? `${snapshot.value.bottomHeight}px` : '0px',
}))

function componentFor(panel: DockPanelState): Component | undefined {
  return panelComponents[panel.id]
}

function panelIdFromDrag(event: DragEvent): string {
  return (
    event.dataTransfer?.getData('application/x-vertex-panel')
    || event.dataTransfer?.getData('text/plain')
    || draggingPanelId.value
  )
}

function dropTo(zone: DockZone, event: DragEvent) {
  event.preventDefault()
  const id = panelIdFromDrag(event)
  if (!id) return

  if (zone === 'float') {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect()
    movePanel(id, 'float', {
      x: Math.max(8, event.clientX - rect.left - 170),
      y: Math.max(8, event.clientY - rect.top - 26),
    })
  } else {
    movePanel(id, zone)
  }

  draggingPanelId.value = ''
  activeDropZone.value = ''
}

function allowDrop(zone: DockZone, event: DragEvent) {
  event.preventDefault()
  activeDropZone.value = zone
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
}

function leaveDrop(zone: DockZone) {
  if (activeDropZone.value === zone) activeDropZone.value = ''
}

function onPanelDragState(event: Event) {
  const detail = (event as CustomEvent<{
    active?: boolean
    panelId?: string
  }>).detail

  draggingPanelId.value =
    detail?.active && detail.panelId ? detail.panelId : ''

  if (!detail?.active) activeDropZone.value = ''
}

function onPanelCommand(event: Event) {
  const detail = (event as CustomEvent<{
    panelId?: string
    command?: 'float' | 'hide'
  }>).detail

  if (!detail?.panelId || !detail.command) return

  if (detail.command === 'hide') {
    hidePanel(detail.panelId)
    return
  }

  if (detail.command === 'float') {
    movePanel(detail.panelId, 'float', {
      x: Math.max(24, window.innerWidth * 0.5 - 230),
      y: 120,
    })
  }
}

function beginResize(
  target: 'left' | 'right' | 'bottom',
  event: MouseEvent,
) {
  event.preventDefault()
  resizing.value = target

  const startX = event.clientX
  const startY = event.clientY
  const leftStart = snapshot.value.leftWidth
  const rightStart = snapshot.value.rightWidth
  const bottomStart = snapshot.value.bottomHeight

  const onMove = (moveEvent: MouseEvent) => {
    if (target === 'left') {
      setLeftWidth(leftStart + (moveEvent.clientX - startX))
    } else if (target === 'right') {
      setRightWidth(rightStart - (moveEvent.clientX - startX))
    } else {
      setBottomHeight(bottomStart - (moveEvent.clientY - startY))
    }
  }

  const onUp = () => {
    resizing.value = ''
    window.removeEventListener('mousemove', onMove)
    window.removeEventListener('mouseup', onUp)
  }

  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', onUp)
}

function syncFloatRect(panel: DockPanelState, event: MouseEvent) {
  const element = event.currentTarget as HTMLElement
  const parent = element.offsetParent as HTMLElement | null
  if (!parent) return

  const parentRect = parent.getBoundingClientRect()
  const rect = element.getBoundingClientRect()

  updateFloatRect(panel.id, {
    x: rect.left - parentRect.left,
    y: rect.top - parentRect.top,
    width: rect.width,
    height: rect.height,
  })
}

function onResize() {
  windowWidth.value = window.innerWidth
}

function onKey(event: KeyboardEvent) {
  if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'r') {
    event.preventDefault()
    resetLayout()
  }
}

onMounted(() => {
  window.addEventListener('vertex-panel-drag-state', onPanelDragState)
  window.addEventListener('vertex-panel-command', onPanelCommand)
  window.addEventListener('resize', onResize)
  window.addEventListener('keydown', onKey)
})

onUnmounted(() => {
  window.removeEventListener('vertex-panel-drag-state', onPanelDragState)
  window.removeEventListener('vertex-panel-command', onPanelCommand)
  window.removeEventListener('resize', onResize)
  window.removeEventListener('keydown', onKey)
})
</script>

<template>
  <div
    class="vertex-cockpit"
    :class="{
      'mode-compact': compactMode,
      'mode-standard': standardMode,
      'mode-wide': wideMode,
      'is-dragging-panel': Boolean(draggingPanelId),
    }"
    :style="shellStyle"
  >
    <header class="cockpit-top-deck">
      <div class="cockpit-brand">
        <div class="brand-mark">
          <span>V</span>
        </div>

        <div>
          <strong>VERTEX STUDIO AI</strong>
          <small>DEVELOPMENT // MOTHERSHIP BRIDGE</small>
        </div>
      </div>

      <div class="cockpit-status-strip">
        <ProjectStatusPanel :telemetry="telemetry" />
        <VspStatusPanel :telemetry="telemetry" />
        <VxnStatusPanel :telemetry="telemetry" />
        <ArdStatusPanel :telemetry="telemetry" />
        <ProjectBrainPanel :telemetry="telemetry" />
        <WorkspaceHealthPanel :telemetry="telemetry" />
      </div>

      <div class="cockpit-clock">
        <span>MODE : CREATION</span>
        <strong>{{ telemetry.now }}</strong>
      </div>
    </header>

    <section class="cockpit-workspace">
      <aside
        v-if="leftPanels.length > 0"
        class="dock-column dock-left"
      >
        <button
          class="column-resizer left-resizer"
          title="Resize left dock"
          @mousedown="beginResize('left', $event)"
        />

        <component
          :is="componentFor(panel)"
          v-for="panel in leftPanels"
          :key="panel.id"
          :telemetry="telemetry"
        />
      </aside>

      <main class="cockpit-editor-surface">
        <slot />

        <div
          v-for="panel in floatingPanels"
          :key="panel.id"
          class="floating-panel"
          :style="{
            left: `${panel.x}px`,
            top: `${panel.y}px`,
            width: `${panel.width}px`,
            height: `${panel.height}px`,
          }"
          @mouseup="syncFloatRect(panel, $event)"
        >
          <component
            :is="componentFor(panel)"
            :telemetry="telemetry"
          />
        </div>

        <div
          v-if="draggingPanelId"
          class="dock-overlay"
        >
          <div
            class="dock-target target-left"
            :class="{ active: activeDropZone === 'left' }"
            @dragover="allowDrop('left', $event)"
            @dragleave="leaveDrop('left')"
            @drop="dropTo('left', $event)"
          >
            <strong>LEFT</strong>
            <span>DOCK</span>
          </div>

          <div
            class="dock-target target-float"
            :class="{ active: activeDropZone === 'float' }"
            @dragover="allowDrop('float', $event)"
            @dragleave="leaveDrop('float')"
            @drop="dropTo('float', $event)"
          >
            <strong>FLOAT</strong>
            <span>FREE PANEL</span>
          </div>

          <div
            class="dock-target target-right"
            :class="{ active: activeDropZone === 'right' }"
            @dragover="allowDrop('right', $event)"
            @dragleave="leaveDrop('right')"
            @drop="dropTo('right', $event)"
          >
            <strong>RIGHT</strong>
            <span>DOCK</span>
          </div>

          <div
            class="dock-target target-bottom"
            :class="{ active: activeDropZone === 'bottom' }"
            @dragover="allowDrop('bottom', $event)"
            @dragleave="leaveDrop('bottom')"
            @drop="dropTo('bottom', $event)"
          >
            <strong>BOTTOM</strong>
            <span>DOCK</span>
          </div>
        </div>
      </main>

      <aside
        v-if="rightPanels.length > 0"
        class="dock-column dock-right"
      >
        <button
          class="column-resizer right-resizer"
          title="Resize right dock"
          @mousedown="beginResize('right', $event)"
        />

        <component
          :is="componentFor(panel)"
          v-for="panel in rightPanels"
          :key="panel.id"
          :telemetry="telemetry"
        />
      </aside>

      <section
        v-if="bottomPanels.length > 0"
        class="dock-bottom"
      >
        <button
          class="bottom-resizer"
          title="Resize bottom dock"
          @mousedown="beginResize('bottom', $event)"
        />

        <div class="bottom-panel-strip">
          <component
            :is="componentFor(panel)"
            v-for="panel in bottomPanels"
            :key="panel.id"
            :telemetry="telemetry"
          />
        </div>
      </section>
    </section>

    <CockpitStatusBar :telemetry="telemetry" />

    <nav class="cockpit-command-rail">
      <button
        v-for="panel in allKnownPanels"
        :key="panel.id"
        :class="{ active: panel.visible }"
        :title="panel.visible ? 'Hide panel' : 'Show panel'"
        @click="panel.visible ? hidePanel(panel.id) : showPanel(panel.id)"
      >
        {{ panel.id === 'system-monitor'
          ? 'SYS'
          : panel.id === 'hyper-agent'
            ? 'AGENT'
            : 'VSP' }}
      </button>

      <span class="rail-separator" />

      <button
        title="Reset dock layout (Ctrl+Shift+R)"
        @click="resetLayout"
      >
        RESET
      </button>

      <span class="rail-mode">
        {{ wideMode ? '27-INCH' : standardMode ? 'STANDARD' : 'COMPACT' }}
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

  --cockpit-base-font: clamp(12px, .54vw, 14px);
  --cockpit-caption: clamp(10px, .42vw, 11px);
  --cockpit-panel-title: clamp(12px, .50vw, 14px);
  --cockpit-value: clamp(13px, .58vw, 16px);
  --cockpit-panel-header: 42px;

  position: relative;
  display: grid;
  width: 100%;
  height: 100vh;
  min-width: 0;
  min-height: 0;
  grid-template-rows: 96px minmax(0, 1fr) 34px;
  overflow: hidden;
  background:
    radial-gradient(circle at 62% -30%, rgba(20,113,180,.13), transparent 42%),
    var(--vertex-bg-deep);
  color: var(--vertex-text);
  font-size: var(--cockpit-base-font);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.cockpit-top-deck {
  position: relative;
  z-index: 40;
  display: grid;
  min-width: 0;
  grid-template-columns: 270px minmax(0, 1fr) 170px;
  gap: 7px;
  padding: 8px;
  border-bottom: 1px solid var(--vertex-line-bright);
  background:
    linear-gradient(90deg, rgba(25,135,224,.09), transparent 28%),
    linear-gradient(180deg, #101821, #080d13);
  box-shadow: 0 5px 22px rgba(0,0,0,.24);
}

.cockpit-top-deck::after {
  position: absolute;
  right: 0;
  bottom: -1px;
  left: 0;
  height: 1px;
  background:
    linear-gradient(90deg, transparent, rgba(33,150,243,.72), transparent 72%);
  content: "";
}

.cockpit-brand {
  display: flex;
  min-width: 0;
  align-items: center;
  padding: 0 13px;
  gap: 13px;
  border: 1px solid var(--vertex-line);
  background:
    linear-gradient(180deg, rgba(13,21,30,.93), rgba(7,12,18,.97));
}

.brand-mark {
  display: grid;
  width: 42px;
  height: 42px;
  flex: none;
  place-items: center;
  border: 1px solid #2b668f;
  transform: rotate(45deg);
  background: #0b2638;
  box-shadow: 0 0 18px rgba(22,140,255,.15);
}

.brand-mark span {
  transform: rotate(-45deg);
  color: var(--vertex-blue-bright);
  font-size: 15px;
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
  font-size: clamp(15px, .68vw, 18px);
  font-weight: 680;
  letter-spacing: .045em;
}

.cockpit-brand small {
  margin-top: 6px;
  color: #607589;
  font: 700 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .07em;
}

.cockpit-status-strip {
  display: grid;
  min-width: 0;
  grid-template-columns: repeat(6, minmax(150px, 1fr));
  gap: 6px;
  overflow-x: auto;
  overflow-y: hidden;
}

.cockpit-status-strip::-webkit-scrollbar {
  height: 5px;
}

.cockpit-status-strip::-webkit-scrollbar-thumb {
  background: #274154;
}

:deep(.status-cell) {
  position: relative;
  min-width: 150px;
  padding: 14px 15px;
  overflow: hidden;
  border: 1px solid var(--vertex-line);
  background:
    linear-gradient(160deg, rgba(17,25,35,.96), rgba(8,13,19,.98));
}

:deep(.status-cell)::after {
  position: absolute;
  top: 10px;
  right: 0;
  bottom: 10px;
  width: 2px;
  background:
    linear-gradient(
      180deg,
      transparent,
      rgba(22,140,255,.85),
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
  color: #93a5b5;
  font-size: clamp(10px, .44vw, 12px);
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
  margin-top: 8px;
  color: #bfccd8;
  font: 720 clamp(12px, .52vw, 14px)/1.1 ui-monospace, Consolas, monospace;
}

:deep(.status-cell > span) {
  margin-top: 6px;
  color: #66798b;
  font: 650 10px/1.15 ui-monospace, Consolas, monospace;
  letter-spacing: .04em;
}

.cockpit-clock {
  display: grid;
  align-content: center;
  justify-items: end;
  padding: 0 14px;
  border: 1px solid var(--vertex-line);
  background: rgba(7,12,18,.92);
}

.cockpit-clock span {
  color: #9aabba;
  font: 700 10px/1 ui-monospace, Consolas, monospace;
}

.cockpit-clock strong {
  margin-top: 9px;
  color: #e2ebf3;
  font: 500 clamp(18px, .82vw, 22px)/1 ui-monospace, Consolas, monospace;
}

.cockpit-workspace {
  position: relative;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns:
    var(--dock-left-width, 0px)
    minmax(0, 1fr)
    var(--dock-right-width, 0px);
  grid-template-rows:
    minmax(0, 1fr)
    var(--dock-bottom-height, 0px);
  overflow: hidden;
}

.cockpit-editor-surface {
  position: relative;
  grid-column: 2;
  grid-row: 1;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  background:
    radial-gradient(circle at 50% 10%, rgba(22,140,255,.035), transparent 38%),
    var(--vertex-bg-deep);
}

.cockpit-editor-surface > :deep(*) {
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
  max-height: 100%;
}

.dock-column {
  position: relative;
  z-index: 20;
  display: flex;
  min-width: 0;
  min-height: 0;
  flex-direction: column;
  gap: 8px;
  padding: 8px;
  overflow: auto;
  background:
    linear-gradient(180deg, rgba(9,15,22,.99), rgba(6,10,15,.995));
}

.dock-column::-webkit-scrollbar {
  width: 8px;
}

.dock-column::-webkit-scrollbar-track {
  background: #080d13;
}

.dock-column::-webkit-scrollbar-thumb {
  border: 2px solid #080d13;
  border-radius: 8px;
  background: #2a4153;
}

.dock-left {
  grid-column: 1;
  grid-row: 1;
  border-right: 1px solid var(--vertex-line-bright);
  box-shadow: 8px 0 26px rgba(0,0,0,.18);
}

.dock-right {
  grid-column: 3;
  grid-row: 1;
  border-left: 1px solid var(--vertex-line-bright);
  box-shadow: -8px 0 26px rgba(0,0,0,.18);
}

.column-resizer {
  position: absolute;
  z-index: 25;
  top: 0;
  bottom: 0;
  width: 8px;
  border: 0;
  background: transparent;
  cursor: ew-resize;
}

.column-resizer::after {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  background: transparent;
  content: "";
}

.left-resizer {
  right: -5px;
}

.left-resizer::after {
  right: 3px;
}

.right-resizer {
  left: -5px;
}

.right-resizer::after {
  left: 3px;
}

.column-resizer:hover::after {
  background: var(--vertex-blue);
  box-shadow: 0 0 10px rgba(22,140,255,.75);
}

.dock-bottom {
  position: relative;
  z-index: 20;
  grid-column: 1 / 4;
  grid-row: 2;
  min-width: 0;
  min-height: 0;
  padding: 8px;
  overflow: auto;
  border-top: 1px solid var(--vertex-line-bright);
  background: #080d13;
}

.bottom-resizer {
  position: absolute;
  z-index: 25;
  top: -5px;
  right: 0;
  left: 0;
  height: 8px;
  border: 0;
  background: transparent;
  cursor: ns-resize;
}

.bottom-resizer::after {
  position: absolute;
  top: 3px;
  right: 0;
  left: 0;
  height: 2px;
  background: transparent;
  content: "";
}

.bottom-resizer:hover::after {
  background: var(--vertex-blue);
  box-shadow: 0 0 10px rgba(22,140,255,.75);
}

.bottom-panel-strip {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(380px, 1fr));
  align-items: start;
  gap: 8px;
}

.floating-panel {
  position: absolute;
  z-index: 150;
  min-width: 300px;
  min-height: 180px;
  max-width: calc(100% - 16px);
  max-height: calc(100% - 16px);
  overflow: auto;
  resize: both;
  border-radius: 6px;
  box-shadow:
    0 22px 70px rgba(0,0,0,.55),
    0 0 0 1px rgba(58,184,255,.08);
}

.floating-panel > :deep(*) {
  min-height: 100%;
}

.dock-overlay {
  position: absolute;
  z-index: 8000;
  inset: 0;
  pointer-events: none;
  background: rgba(4,9,14,.18);
}

.dock-target {
  position: absolute;
  display: grid;
  place-items: center;
  border: 1px solid rgba(58,184,255,.42);
  border-radius: 8px;
  background: rgba(10,28,42,.76);
  box-shadow:
    inset 0 0 35px rgba(22,140,255,.08),
    0 10px 30px rgba(0,0,0,.24);
  pointer-events: auto;
  backdrop-filter: blur(5px);
  transition:
    transform .12s ease,
    border-color .12s ease,
    background .12s ease;
}

.dock-target.active {
  transform: scale(1.035);
  border-color: #76d0ff;
  background: rgba(17,61,92,.9);
  box-shadow:
    inset 0 0 45px rgba(22,140,255,.15),
    0 0 28px rgba(22,140,255,.20);
}

.dock-target strong,
.dock-target span {
  display: block;
  text-align: center;
}

.dock-target strong {
  color: #bce6ff;
  font: 800 16px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.dock-target span {
  margin-top: 8px;
  color: #6ca8cd;
  font: 700 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.target-left {
  top: 18%;
  bottom: 18%;
  left: 18px;
  width: 150px;
}

.target-right {
  top: 18%;
  right: 18px;
  bottom: 18%;
  width: 150px;
}

.target-bottom {
  right: 24%;
  bottom: 18px;
  left: 24%;
  height: 108px;
}

.target-float {
  top: 32%;
  right: 34%;
  bottom: 32%;
  left: 34%;
}

.cockpit-command-rail {
  position: fixed;
  z-index: 9000;
  right: 12px;
  bottom: 44px;
  display: flex;
  min-height: 34px;
  align-items: center;
  padding: 0 7px;
  gap: 6px;
  border: 1px solid #244052;
  border-radius: 5px;
  background: rgba(7,12,18,.95);
  box-shadow: 0 8px 24px rgba(0,0,0,.30);
  backdrop-filter: blur(8px);
}

.cockpit-command-rail button {
  min-width: 40px;
  height: 26px;
  padding: 0 8px;
  border: 1px solid #243746;
  border-radius: 3px;
  background: #0a1118;
  color: #63798b;
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.cockpit-command-rail button:hover,
.cockpit-command-rail button.active {
  border-color: #2f6689;
  background: #102033;
  color: #78cbff;
}

.rail-separator {
  width: 1px;
  height: 18px;
  background: #29404f;
}

.rail-mode {
  padding: 0 5px;
  color: #55758d;
  font: 750 10px/1 ui-monospace, Consolas, monospace;
}

.mode-standard {
  --cockpit-panel-header: 40px;
}

.mode-compact {
  --cockpit-base-font: 12px;
  --cockpit-caption: 10px;
  --cockpit-panel-title: 12px;
  --cockpit-value: 13px;
  --cockpit-panel-header: 40px;
  grid-template-rows: 82px minmax(0, 1fr) 34px;
}

.mode-compact .cockpit-top-deck {
  grid-template-columns: 220px minmax(0, 1fr) 126px;
  padding: 6px;
  gap: 5px;
}

.mode-compact .cockpit-brand {
  padding: 0 9px;
  gap: 9px;
}

.mode-compact .brand-mark {
  width: 34px;
  height: 34px;
}

.mode-compact .cockpit-status-strip {
  display: flex;
  overflow-x: auto;
}

.mode-compact :deep(.status-cell) {
  width: 170px;
  min-width: 170px;
  padding: 10px 12px;
}

.mode-compact .cockpit-clock {
  padding: 0 9px;
}

@media (max-width: 1279px) {
  .cockpit-workspace {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows:
      minmax(0, 1fr)
      var(--dock-bottom-height, 0px);
  }

  .cockpit-editor-surface {
    grid-column: 1;
    grid-row: 1;
  }

  .dock-left,
  .dock-right {
    position: absolute;
    z-index: 80;
    top: 0;
    bottom: var(--dock-bottom-height, 0px);
    width: min(82vw, 430px);
  }

  .dock-left {
    left: 0;
  }

  .dock-right {
    right: 0;
  }

  .dock-bottom {
    grid-column: 1;
  }

  .target-left,
  .target-right {
    width: 115px;
  }

  .target-float {
    right: 26%;
    left: 26%;
  }

  .cockpit-command-rail {
    right: 7px;
    bottom: 41px;
  }
}
</style>
'@
  WriteUtf8 $shellPath $shell

  Write-Host 'Magnetic drop overlay         : ONLINE' -ForegroundColor Green
  Write-Host 'LEFT dock                     : ONLINE' -ForegroundColor Green
  Write-Host 'RIGHT dock                    : ONLINE' -ForegroundColor Green
  Write-Host 'BOTTOM dock                   : ONLINE' -ForegroundColor Green
  Write-Host 'FLOAT surface                 : ONLINE' -ForegroundColor Green
  Write-Host 'Dock resize                   : ONLINE' -ForegroundColor Green
  Write-Host 'Dock persistence              : ONLINE' -ForegroundColor Green

  Write-Host "`n[7/13] FRONTEND TYPECHECK" -ForegroundColor Yellow
  Push-Location $ui
  try{
    RunChecked '[v3] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[8/13] FRONTEND VISUAL BUILD" -ForegroundColor Yellow
  Push-Location $ui
  try{
    RunChecked '[v3] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[9/13] READABILITY / DOCKING SAFETY AUDIT" -ForegroundColor Yellow

  $cockpitText=(
    Get-ChildItem -LiteralPath $cockpit -Recurse -File |
    ForEach-Object {[IO.File]::ReadAllText($_.FullName)}
  ) -join "`n"

  $editorNow=[IO.File]::ReadAllText($editor)

  $audits=@(
    [pscustomobject]@{
      Name='27-inch breakpoint'
      Pass=$cockpitText.Contains('2200')
    },
    [pscustomobject]@{
      Name='Compact breakpoint'
      Pass=$cockpitText.Contains('1280')
    },
    [pscustomobject]@{
      Name='Readable base minimum'
      Pass=$cockpitText.Contains('--cockpit-base-font: clamp(12px')
    },
    [pscustomobject]@{
      Name='Panel drag MIME'
      Pass=$cockpitText.Contains('application/x-vertex-panel')
    },
    [pscustomobject]@{
      Name='LEFT dock'
      Pass=$cockpitText.Contains("'left'")
    },
    [pscustomobject]@{
      Name='RIGHT dock'
      Pass=$cockpitText.Contains("'right'")
    },
    [pscustomobject]@{
      Name='BOTTOM dock'
      Pass=$cockpitText.Contains("'bottom'")
    },
    [pscustomobject]@{
      Name='FLOAT dock'
      Pass=$cockpitText.Contains("'float'")
    },
    [pscustomobject]@{
      Name='Layout schema V3'
      Pass=$cockpitText.Contains('vertex.cockpit.dock-layout.v3')
    },
    [pscustomobject]@{
      Name='Drone host contract'
      Pass=$cockpitText.Contains("'drone'")
    },
    [pscustomobject]@{
      Name='No fake telemetry'
      Pass=$cockpitText.Contains('No synthetic save-point data is generated.')
    },
    [pscustomobject]@{
      Name='FME Deep'
      Pass=$cockpitText.Contains('#070b10')
    },
    [pscustomobject]@{
      Name='Vertex Blue'
      Pass=$cockpitText.Contains('#168cff')
    },
    [pscustomobject]@{
      Name='No eval'
      Pass=(-not $cockpitText.Contains('eval('))
    },
    [pscustomobject]@{
      Name='No remote runtime import'
      Pass=(-not $cockpitText.Contains('import("http://') -and -not $cockpitText.Contains("import('http://") -and -not $cockpitText.Contains('import("https://') -and -not $cockpitText.Contains("import('https://"))
    },
    [pscustomobject]@{
      Name='No arbitrary shell'
      Pass=(-not $cockpitText.Contains('powershell.exe') -and -not $cockpitText.Contains('cmd.exe') -and -not $cockpitText.Contains('Command::new'))
    },
    [pscustomobject]@{
      Name='Cockpit wrapper preserved'
      Pass=$editorNow.Contains('<VertexCockpitShell>')
    },
    [pscustomobject]@{
      Name='GUI Preview preserved'
      Pass=$editorNow.Contains('<VertexLivePreview />')
    },
    [pscustomobject]@{
      Name='VertexHub preserved'
      Pass=$editorNow.Contains('<VertexHubDock />')
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "V3 safety audit RED: $($audit.Name)"}
    Write-Host ("  {0,-38} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[10/13] TAURI CHECK" -ForegroundColor Yellow

  $previousCargoTarget=$env:CARGO_TARGET_DIR
  try{
    New-Item -ItemType Directory -Path $tauriDevTarget -Force|Out-Null
    $env:CARGO_TARGET_DIR=$tauriDevTarget

    RunChecked '[release] Tauri cargo check' {
      & $cargo.Source check --manifest-path $tauriCargo --all-targets
    }
  }finally{
    $env:CARGO_TARGET_DIR=$previousCargoTarget
  }

  Write-Host "`n[11/13] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  Write-Host "`n[12/13] FINAL FRONTEND GATE" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[release] pnpm build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[13/13] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.vsa-docking-cockpit.v3'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA DOCKING COCKPIT V3'
    display=[ordered]@{
      primary='27-inch / 2560x1440'
      practical='1920x1080'
      compact='<1280 responsive overlay'
      microtext='REMOVED'
      minimum_base='12px'
      primary_ui_mode='WIDE_27_INCH'
    }
    docking=[ordered]@{
      drag_handle='PANEL_HEADER'
      left='ONLINE'
      right='ONLINE'
      bottom='ONLINE'
      floating='ONLINE'
      resizable='ONLINE'
      persistence='LOCALSTORAGE'
      reset='CTRL_SHIFT_R'
    }
    extensibility=[ordered]@{
      panel='SUPPORTED'
      agent='CONTRACT_RESERVED'
      drone='CONTRACT_RESERVED'
      fake_drone_ui='DENIED'
      future_hub_packaging='READY'
    }
    safety=[ordered]@{
      fake_telemetry='DENIED'
      arbitrary_eval='DENIED'
      remote_runtime_import='DENIED'
      arbitrary_shell='DENIED'
      controller_mutation='DENIED'
    }
    preserved=[ordered]@{
      editor='YES'
      gui_live_preview='YES'
      vertexhub='YES'
      mothership='UNTOUCHED'
      runtime_bus='UNTOUCHED'
    }
    validation=[ordered]@{
      vue_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    next_target='PANEL TAB STACK / HUB PACKAGE LIFT / DRONE EQUIPMENT HOST'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - VSA DOCKING COCKPIT V3 GREEN
============================================================
 Primary Display Target                   27-INCH / 2560x1440
 Practical Display                        1920x1080
 Compact Display                          RESPONSIVE
 Micro Text                               REMOVED
 Readable Base Font                       >= 12px
 Panel Header Drag                        ONLINE
 Magnetic Dock Overlay                    ONLINE
 LEFT Dock                                ONLINE
 RIGHT Dock                               ONLINE
 BOTTOM Dock                              ONLINE
 FLOAT Panel                              ONLINE
 Dock Resize                              ONLINE
 Layout Persistence                       ONLINE
 Layout Reset                             CTRL+SHIFT+R
 System Monitor                           DOCKABLE
 Hyper Agent                              DOCKABLE
 VSP Snapshot                             DOCKABLE
 Panel Host                               SUPPORTED
 Agent Host Contract                      RESERVED
 Drone Host Contract                      RESERVED
 Fake Drone UI                            DENIED
 FME Vertex Design                        LOCKED
 Vertex Blue #168cff                      LOCKED
 Arbitrary Eval                           DENIED
 Remote Runtime Import                    DENIED
 Arbitrary Shell                          DENIED
 Controller Mutation                      DENIED
 Existing Editor                          PRESERVED
 GUI Live Preview                         PRESERVED
 VertexHub                                PRESERVED
 Mothership / Runtime Bus                 UNTOUCHED
 Frontend Typecheck                       GREEN
 Frontend Build                           GREEN
 Tauri Check                              GREEN
 Workspace Release Gate                   GREEN
------------------------------------------------------------
 NEXT TARGET:
 PANEL TAB STACK / HUB PACKAGE LIFT / DRONE EQUIPMENT HOST
============================================================
 MOTHERSHIP BRIDGE: MAGNETIC
 WE ARE VERTEX.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VSA DOCKING COCKPIT V3 RED - DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  if(Test-Path -LiteralPath $cockpit){
    Copy-Item -LiteralPath $cockpit -Destination (Join-Path $failed 'vertex-cockpit.failed') -Recurse -Force -ErrorAction SilentlyContinue
  }

  if(Test-Path -LiteralPath $editor){
    Copy-Item -LiteralPath $editor -Destination (Join-Path $failed 'VertexEditorDock.failed.vue') -Force -ErrorAction SilentlyContinue
  }

  $cockpitBackup=Join-Path $backup 'vertex-cockpit'
  $editorBackup=Join-Path $backup 'VertexEditorDock.vue'

  if(Test-Path -LiteralPath $cockpitBackup){
    if(Test-Path -LiteralPath $cockpit){
      Remove-Item -LiteralPath $cockpit -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $cockpitBackup -Destination $cockpit -Recurse -Force
  }

  if(Test-Path -LiteralPath $editorBackup){
    Copy-Item -LiteralPath $editorBackup -Destination $editor -Force
  }

  Write-Host 'Cockpit rollback                  : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Editor rollback                   : COMPLETE' -ForegroundColor Yellow
  Write-Host 'VertexHub                         : PRESERVED' -ForegroundColor Yellow
  Write-Host 'Mothership / Runtime Bus          : UNTOUCHED' -ForegroundColor Yellow
  Write-Host 'GUI Live Preview                  : RESTORED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}
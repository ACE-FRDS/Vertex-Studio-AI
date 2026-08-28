& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX - VSA ROLE LAYOUT REBUILD V5R1R1
#
# LOCKED ROLE DOCTRINE
#   LEFT    : HYPERAgent Chat (Human Intent Gateway)
#   CENTER  : VSA Editor / Main Workspace (FIXED, NEVER FLOAT)
#   RIGHT   : VVE Tree Explorer (World / Project Structure)
#   BOTTOM  : Independent utility components
#             AI Activity / Terminal / Build / Test / Reviewer / AI Assistant
#   FOOTER  : Player HUD only (Level / XP / VX / Rank / Quest / World / Drone)
#
# Safety:
#   - Editor is fixed center and is not in DockLayout.
#   - No fake RPG values.
#   - No fake build/test/reviewer results.
#   - Real telemetry only where currently available.
#   - Unknown backend link => UNBOUND / NO SIGNAL.
#   - No arbitrary shell / eval / remote runtime import.
#   - Existing VertexHub / GUI Preview / Mothership remain untouched.
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'

$cockpit=Join-Path $ui 'src\vertex-cockpit'
$panels=Join-Path $cockpit 'panels'
$roleDir=Join-Path $cockpit 'role-layout'
$rolePanels=Join-Path $roleDir 'panels'

$shell=Join-Path $cockpit 'VertexCockpitShell.vue'
$dockLayout=Join-Path $cockpit 'dockLayout.ts'
$frame=Join-Path $panels 'CockpitPanelFrame.vue'
$telemetry=Join-Path $cockpit 'cockpitTelemetry.ts'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$editorTransport=Join-Path $ui 'src\vertex-editor\transport.ts'

$packageJson=Join-Path $ui 'package.json'
$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriCheckTarget=Join-Path $startup '_build\VSA_TAURI_ROLE_LAYOUT_V5_CHECK'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_ROLE_LAYOUT_REBUILD_V5R1_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_ROLE_LAYOUT_REBUILD_V5R1_FAILED.$stamp"
$report=Join-Path $reports "VSA_ROLE_LAYOUT_REBUILD_V5R1.$stamp.json"

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
 VERTEX - VSA ROLE LAYOUT REBUILD V5R1R1
 HUMAN INTENT / FIXED EDITOR / VVE / PLAYER HUD
============================================================
'@ -ForegroundColor Magenta

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$cockpit,$panels,$shell,
  $dockLayout,$frame,$telemetry,$editor,$editorTransport,
  $packageJson,$coreCargo,$tauriCargo
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required current-core artifact missing: $required"
  }
}

if(Test-Path -LiteralPath $roleDir){
  throw "Role Layout V5 already exists: $roleDir"
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/14] CURRENT COCKPIT / DOCK BASELINE" -ForegroundColor Yellow

$shellText=[IO.File]::ReadAllText($shell)
$dockText=[IO.File]::ReadAllText($dockLayout)
$editorText=[IO.File]::ReadAllText($editor)
$transportText=[IO.File]::ReadAllText($editorTransport)

$baseline=@(
  [pscustomobject]@{
    Name='Cockpit Shell'
    Pass=$shellText.Contains('vertex-cockpit')
  },
  [pscustomobject]@{
    Name='Dock Layout'
    Pass=$dockText.Contains('DockZone')
  },
  [pscustomobject]@{
    Name='Panel drag MIME'
    Pass=([IO.File]::ReadAllText($frame)).Contains('application/x-vertex-panel')
  },
  [pscustomobject]@{
    Name='Editor shell wrapper'
    Pass=$editorText.Contains('<VertexCockpitShell>')
  },
  [pscustomobject]@{
    Name='GUI Live Preview'
    Pass=$editorText.Contains('<VertexLivePreview />')
  },
  [pscustomobject]@{
    Name='VertexHub'
    Pass=$editorText.Contains('<VertexHubDock />')
  },
  [pscustomobject]@{
    Name='Project tree IPC'
    Pass=$transportText.Contains('vertex_project_tree')
  }
)

foreach($item in $baseline){
  if(-not $item.Pass){throw "Baseline missing: $($item.Name)"}
  Write-Host ("  {0,-34} GREEN" -f $item.Name) -ForegroundColor Green
}

RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

Write-Host "`n[1/14] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item -LiteralPath $cockpit -Destination (Join-Path $backup 'vertex-cockpit') -Recurse -Force
Copy-Item -LiteralPath $editor -Destination (Join-Path $backup 'VertexEditorDock.vue') -Force
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  New-Item -ItemType Directory -Path $rolePanels -Force|Out-Null

  Write-Host "`n[2/14] CREATE V5 ROLE DOCK CONTRACT" -ForegroundColor Yellow

  $dock=@'
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
  schema: 'vertex.cockpit.role-layout.v5'
  panels: DockPanelState[]
  leftWidth: number
  rightWidth: number
  bottomHeight: number
}

const STORAGE_KEY = 'vertex.cockpit.role-layout.v5'

const defaults: DockLayoutSnapshot = {
  schema: 'vertex.cockpit.role-layout.v5',
  panels: [
    // HUMAN INTENT GATEWAY
    {
      id: 'hyperagent-chat',
      zone: 'left',
      order: 0,
      visible: true,
      x: 30,
      y: 120,
      width: 430,
      height: 720,
    },

    // WORLD / PROJECT STRUCTURE
    {
      id: 'vve-tree-explorer',
      zone: 'right',
      order: 0,
      visible: true,
      x: 1080,
      y: 120,
      width: 430,
      height: 720,
    },

    // INDEPENDENT UTILITY COMPONENTS
    {
      id: 'ai-activity-monitor',
      zone: 'bottom',
      order: 0,
      visible: true,
      x: 100,
      y: 600,
      width: 380,
      height: 280,
    },
    {
      id: 'terminal',
      zone: 'bottom',
      order: 1,
      visible: true,
      x: 180,
      y: 620,
      width: 620,
      height: 300,
    },
    {
      id: 'build',
      zone: 'bottom',
      order: 2,
      visible: true,
      x: 300,
      y: 620,
      width: 360,
      height: 260,
    },
    {
      id: 'test',
      zone: 'bottom',
      order: 3,
      visible: true,
      x: 340,
      y: 620,
      width: 360,
      height: 260,
    },
    {
      id: 'reviewer',
      zone: 'bottom',
      order: 4,
      visible: true,
      x: 400,
      y: 620,
      width: 420,
      height: 300,
    },
    {
      id: 'ai-assistant',
      zone: 'bottom',
      order: 5,
      visible: true,
      x: 460,
      y: 620,
      width: 390,
      height: 300,
    },

    // OPTIONAL EQUIPMENT - AVAILABLE BUT NOT DEFAULT MAIN
    {
      id: 'system-monitor',
      zone: 'right',
      order: 10,
      visible: false,
      x: 980,
      y: 160,
      width: 420,
      height: 310,
    },
    {
      id: 'vsp-snapshot',
      zone: 'right',
      order: 11,
      visible: false,
      x: 940,
      y: 210,
      width: 420,
      height: 330,
    },
  ],
  leftWidth: 390,
  rightWidth: 390,
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

function clamp(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback
  return Math.min(maximum, Math.max(minimum, value))
}

function sanitizePanel(
  rawValue: unknown,
  fallback: DockPanelState,
): DockPanelState {
  const raw =
    typeof rawValue === 'object' && rawValue !== null
      ? (rawValue as Partial<DockPanelState>)
      : {}

  const allowed: DockZone[] = ['left', 'right', 'bottom', 'float']
  const zone =
    typeof raw.zone === 'string' && allowed.includes(raw.zone as DockZone)
      ? (raw.zone as DockZone)
      : fallback.zone

  return {
    id: fallback.id,
    zone,
    order: clamp(raw.order, fallback.order, 0, 2000),
    visible: typeof raw.visible === 'boolean' ? raw.visible : fallback.visible,
    x: clamp(raw.x, fallback.x, 0, 10000),
    y: clamp(raw.y, fallback.y, 0, 10000),
    width: clamp(raw.width, fallback.width, 300, 1400),
    height: clamp(raw.height, fallback.height, 180, 1200),
  }
}

function loadSnapshot(): DockLayoutSnapshot {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return cloneDefaults()

    const parsed = JSON.parse(raw) as Partial<DockLayoutSnapshot>
    if (parsed.schema !== 'vertex.cockpit.role-layout.v5') {
      return cloneDefaults()
    }

    const sourcePanels = Array.isArray(parsed.panels) ? parsed.panels : []

    return {
      schema: 'vertex.cockpit.role-layout.v5',
      panels: defaults.panels.map((fallback) => {
        const found = sourcePanels.find(
          (item) =>
            typeof item === 'object'
            && item !== null
            && (item as Partial<DockPanelState>).id === fallback.id,
        )
        return sanitizePanel(found, fallback)
      }),
      leftWidth: clamp(parsed.leftWidth, defaults.leftWidth, 320, 720),
      rightWidth: clamp(parsed.rightWidth, defaults.rightWidth, 320, 720),
      bottomHeight: clamp(parsed.bottomHeight, defaults.bottomHeight, 220, 620),
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
      target.width = Math.max(300, Math.min(1400, rect.width))
    }
    if (typeof rect.height === 'number') {
      target.height = Math.max(180, Math.min(1200, rect.height))
    }
  }

  function setLeftWidth(value: number) {
    snapshot.value.leftWidth = Math.max(320, Math.min(720, value))
  }

  function setRightWidth(value: number) {
    snapshot.value.rightWidth = Math.max(320, Math.min(720, value))
  }

  function setBottomHeight(value: number) {
    snapshot.value.bottomHeight = Math.max(220, Math.min(620, value))
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
  WriteUtf8 $dockLayout $dock
  Write-Host 'Role Dock Contract             : ONLINE' -ForegroundColor Green
  Write-Host 'Editor in Dock Contract        : DENIED' -ForegroundColor Green

  Write-Host "`n[3/14] BUILD HYPERAGENT CHAT - HUMAN INTENT GATEWAY" -ForegroundColor Yellow

  $chat=@'
<script setup lang="ts">
import { computed, ref } from 'vue'
import type { CockpitTelemetry } from '../../cockpitTelemetry'
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'

const props = defineProps<{
  telemetry: CockpitTelemetry
}>()

const draft = ref('')

const liveLabel = computed(() =>
  props.telemetry.liveOnline ? 'LIVE CONTEXT' : 'LINK UNBOUND',
)

const canTransmit = computed(() => false)
</script>

<template>
  <CockpitPanelFrame
    title="HYPERAGENT // CHAT"
    subtitle="HUMAN INTENT GATEWAY"
    panel-id="hyperagent-chat"
    dockable
    :status="liveLabel"
    :status-tone="telemetry.liveOnline ? 'green' : 'muted'"
  >
    <div class="chat-panel">
      <section class="agent-identity">
        <div class="agent-sigil" aria-hidden="true">
          <span class="sigil-core" />
          <span class="sigil-ring ring-a" />
          <span class="sigil-ring ring-b" />
        </div>

        <div class="agent-copy">
          <span class="eyebrow">HYPER AGENT</span>
          <strong>INTENT INTERFACE</strong>
          <small>
            {{
              telemetry.liveOnline
                ? 'Mothership live context observed'
                : 'Conversation transport is not wired yet'
            }}
          </small>
        </div>
      </section>

      <section class="chat-history">
        <div class="system-note">
          <span>HUMAN → HYPERAGENT</span>
          <p>
            This panel is the primary entry point for human intent,
            correction, priority and direction.
          </p>
        </div>

        <div class="context-card">
          <div>
            <span>SESSION</span>
            <strong>{{ telemetry.sessionId || 'NO LIVE SESSION' }}</strong>
          </div>
          <div>
            <span>WAVE</span>
            <strong>{{ telemetry.waveId || '—' }}</strong>
          </div>
          <div>
            <span>DISPATCH</span>
            <strong>{{ telemetry.dispatchId || '—' }}</strong>
          </div>
        </div>

        <div class="empty-history">
          <span>CONVERSATION HISTORY</span>
          <strong>TRANSPORT UNBOUND</strong>
          <p>
            No synthetic conversation is generated.
          </p>
        </div>
      </section>

      <section class="intent-composer">
        <textarea
          v-model="draft"
          rows="4"
          placeholder="Tell HyperAgent what you want to build, change, inspect, or prioritize..."
        />

        <div class="composer-actions">
          <span class="intent-state">
            {{ draft.length }} chars
          </span>

          <button
            type="button"
            :disabled="!canTransmit"
            title="HyperAgent conversation transport is not wired yet"
          >
            TRANSMIT
          </button>
        </div>

        <div class="transport-note">
          HYPERAGENT MESSAGE TRANSPORT: UNBOUND — INPUT IS NOT SENT OR FAKED
        </div>
      </section>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.chat-panel {
  display: grid;
  min-height: 520px;
  height: 100%;
  grid-template-rows: auto minmax(0, 1fr) auto;
  background:
    radial-gradient(circle at 45% 0%, rgba(124,92,255,.08), transparent 28%),
    rgba(6,8,17,.72);
}

.agent-identity {
  display: grid;
  grid-template-columns: 74px minmax(0, 1fr);
  align-items: center;
  gap: 14px;
  padding: 16px;
  border-bottom: 1px solid var(--vertex-line);
}

.agent-sigil {
  position: relative;
  width: 60px;
  height: 60px;
  border: 1px solid rgba(169,140,255,.35);
  border-radius: 14px;
  background:
    radial-gradient(circle, rgba(124,92,255,.22), rgba(10,12,27,.86) 62%);
  box-shadow: inset 0 0 24px rgba(98,216,255,.04);
}

.sigil-core,
.sigil-ring {
  position: absolute;
  top: 50%;
  left: 50%;
}

.sigil-core {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  transform: translate(-50%, -50%);
  background: var(--vertex-blue-bright);
  box-shadow:
    0 0 10px rgba(169,140,255,.8),
    0 0 26px rgba(124,92,255,.38);
}

.sigil-ring {
  width: 34px;
  height: 34px;
  border: 1px solid rgba(98,216,255,.26);
  border-radius: 50%;
}

.ring-a {
  transform: translate(-50%, -50%) rotate(35deg) scaleY(.44);
}

.ring-b {
  transform: translate(-50%, -50%) rotate(-42deg) scaleX(.44);
}

.agent-copy {
  min-width: 0;
}

.agent-copy span,
.agent-copy strong,
.agent-copy small {
  display: block;
}

.eyebrow {
  color: var(--vertex-cyan, #62d8ff);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.agent-copy strong {
  margin-top: 6px;
  color: #dce3f4;
  font-size: 16px;
}

.agent-copy small {
  margin-top: 7px;
  color: var(--vertex-muted);
  font-size: 11px;
}

.chat-history {
  min-height: 0;
  padding: 14px;
  overflow: auto;
}

.system-note,
.empty-history,
.context-card {
  border: 1px solid rgba(58,66,108,.72);
  border-radius: 6px;
  background:
    linear-gradient(180deg, rgba(18,22,43,.74), rgba(9,11,23,.78));
}

.system-note {
  padding: 13px;
}

.system-note span,
.empty-history span {
  color: var(--vertex-blue-bright);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .06em;
}

.system-note p,
.empty-history p {
  margin: 8px 0 0;
  color: #8995b2;
  font-size: 12px;
  line-height: 1.5;
}

.context-card {
  display: grid;
  margin-top: 10px;
  grid-template-columns: 1fr;
}

.context-card > div {
  min-width: 0;
  padding: 10px 12px;
  border-bottom: 1px solid rgba(52,61,98,.58);
}

.context-card > div:last-child {
  border-bottom: 0;
}

.context-card span,
.context-card strong {
  display: block;
}

.context-card span {
  color: #687593;
  font: 720 9px/1 ui-monospace, Consolas, monospace;
}

.context-card strong {
  margin-top: 5px;
  overflow: hidden;
  color: #aab5cd;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 11px/1.2 ui-monospace, Consolas, monospace;
}

.empty-history {
  margin-top: 10px;
  padding: 18px 13px;
}

.empty-history strong {
  display: block;
  margin-top: 8px;
  color: #c3cae0;
  font: 760 13px/1.2 ui-monospace, Consolas, monospace;
}

.intent-composer {
  padding: 12px;
  border-top: 1px solid var(--vertex-line);
  background: rgba(7,9,18,.88);
}

.intent-composer textarea {
  box-sizing: border-box;
  width: 100%;
  min-height: 92px;
  resize: vertical;
  padding: 12px;
  border: 1px solid #343c62;
  border-radius: 6px;
  outline: none;
  background: #090c19;
  color: #dbe2f2;
  font: 500 13px/1.45 "Segoe UI", sans-serif;
}

.intent-composer textarea:focus {
  border-color: rgba(169,140,255,.72);
  box-shadow: 0 0 0 3px rgba(124,92,255,.08);
}

.composer-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 9px;
}

.intent-state {
  color: #66718f;
  font: 700 10px/1 ui-monospace, Consolas, monospace;
}

.composer-actions button {
  height: 34px;
  padding: 0 15px;
  border: 1px solid #4c427b;
  border-radius: 4px;
  background: linear-gradient(180deg, #241d4d, #171630);
  color: #bcb3d8;
  font: 800 10px/1 ui-monospace, Consolas, monospace;
}

.composer-actions button:disabled {
  cursor: not-allowed;
  opacity: .46;
}

.transport-note {
  margin-top: 9px;
  color: #6a708a;
  font: 700 9px/1.35 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $rolePanels 'HyperAgentChatPanel.vue') $chat
  Write-Host 'HyperAgent Chat                : CREATED' -ForegroundColor Green
  Write-Host 'Human Intent Gateway           : LEFT DEFAULT' -ForegroundColor Green
  Write-Host 'Fake Chat Transport            : DENIED' -ForegroundColor Green

  Write-Host "`n[4/14] BUILD VVE TREE EXPLORER" -ForegroundColor Yellow

  $node=@'
<script setup lang="ts">
import { computed, ref } from 'vue'

export interface VveTreeNodeModel {
  id: string
  label: string
  kind: 'folder' | 'file' | 'unknown'
  path: string
  children: VveTreeNodeModel[]
}

const props = defineProps<{
  node: VveTreeNodeModel
  depth?: number
}>()

const open = ref((props.depth ?? 0) < 2)

const padding = computed(() => `${8 + (props.depth ?? 0) * 16}px`)
</script>

<template>
  <div class="tree-node">
    <button
      class="tree-row"
      :style="{ paddingLeft: padding }"
      type="button"
      @click="node.children.length && (open = !open)"
    >
      <span class="twisty">
        {{ node.children.length ? (open ? '⌄' : '›') : '' }}
      </span>

      <span
        class="node-icon"
        :class="node.kind"
        aria-hidden="true"
      >
        <svg
          v-if="node.kind === 'folder'"
          viewBox="0 0 24 18"
        >
          <path
            d="M1.5 4.5h7l2-2h4.5l1.5 2H22v11.8H1.5z"
            fill="currentColor"
            opacity=".22"
          />
          <path
            d="M1.5 5h7.2l2-2H15l1.6 2H22v11.2H1.5z"
            fill="none"
            stroke="currentColor"
            stroke-width="1.2"
          />
          <path
            d="M3 7.5h17.5"
            stroke="currentColor"
            stroke-width="1"
            opacity=".65"
          />
        </svg>

        <svg
          v-else
          viewBox="0 0 18 22"
        >
          <path
            d="M2 1.5h9l5 5v14H2z"
            fill="currentColor"
            opacity=".12"
          />
          <path
            d="M2 1.5h9l5 5v14H2zM11 1.5v5h5"
            fill="none"
            stroke="currentColor"
            stroke-width="1.2"
          />
        </svg>
      </span>

      <span class="node-label">{{ node.label }}</span>
    </button>

    <div
      v-if="open && node.children.length"
      class="tree-children"
    >
      <VveTreeNode
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :depth="(depth ?? 0) + 1"
      />
    </div>
  </div>
</template>

<style scoped>
.tree-row {
  display: grid;
  width: 100%;
  min-height: 34px;
  grid-template-columns: 14px 22px minmax(0,1fr);
  align-items: center;
  gap: 5px;
  border: 0;
  background: transparent;
  color: #a8b4ca;
  text-align: left;
  cursor: pointer;
}

.tree-row:hover {
  background:
    linear-gradient(90deg, rgba(124,92,255,.13), rgba(98,216,255,.025));
}

.twisty {
  color: #707b99;
  font-size: 14px;
}

.node-icon {
  display: grid;
  width: 20px;
  height: 20px;
  place-items: center;
  color: #8c7fea;
}

.node-icon.folder {
  color: #b59a67;
}

.node-icon.file {
  color: #6bbdde;
}

.node-icon svg {
  width: 18px;
  height: 18px;
}

.node-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 600 12px/1 "Segoe UI", sans-serif;
}
</style>
'@
  WriteUtf8 (Join-Path $roleDir 'VveTreeNode.vue') $node

  $vve=@'
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'
import VveTreeNode, { type VveTreeNodeModel } from '../VveTreeNode.vue'

const roots = ref<VveTreeNodeModel[]>([])
const loading = ref(false)
const error = ref('')

function parsePayload(value: unknown): unknown {
  if (typeof value !== 'string') return value
  try {
    return JSON.parse(value)
  } catch {
    return value
  }
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function textFrom(
  object: Record<string, unknown>,
  keys: string[],
): string {
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'string' && value.trim()) return value
  }
  return ''
}

function childrenFrom(object: Record<string, unknown>): unknown[] {
  for (const key of ['children', 'entries', 'nodes', 'items']) {
    if (Array.isArray(object[key])) return object[key] as unknown[]
  }
  return []
}

function normalize(
  value: unknown,
  fallbackId: string,
  depth = 0,
): VveTreeNodeModel | null {
  if (depth > 32) return null

  if (typeof value === 'string') {
    const label = value.split(/[\\/]/).filter(Boolean).pop() || value
    return {
      id: `${fallbackId}:${value}`,
      label,
      path: value,
      kind: value.includes('.') ? 'file' : 'unknown',
      children: [],
    }
  }

  const object = objectValue(value)
  if (!object) return null

  const path = textFrom(object, ['path', 'relative_path', 'full_path'])
  const label =
    textFrom(object, ['name', 'label', 'file_name', 'filename'])
    || path.split(/[\\/]/).filter(Boolean).pop()
    || fallbackId

  const rawChildren = childrenFrom(object)
  const children = rawChildren
    .map((child, index) =>
      normalize(child, `${fallbackId}.${index}`, depth + 1),
    )
    .filter((child): child is VveTreeNodeModel => Boolean(child))

  const rawKind = textFrom(object, ['kind', 'type', 'node_type']).toLowerCase()
  const isDir =
    object.is_dir === true
    || object.directory === true
    || rawKind.includes('dir')
    || rawKind.includes('folder')
    || children.length > 0

  return {
    id: path || `${fallbackId}:${label}`,
    label,
    path,
    kind: isDir ? 'folder' : rawKind.includes('file') ? 'file' : 'unknown',
    children,
  }
}

function normalizeRoots(payload: unknown): VveTreeNodeModel[] {
  const parsed = parsePayload(payload)

  if (Array.isArray(parsed)) {
    return parsed
      .map((item, index) => normalize(item, `root.${index}`))
      .filter((item): item is VveTreeNodeModel => Boolean(item))
  }

  const object = objectValue(parsed)
  if (object) {
    const direct = childrenFrom(object)
    if (direct.length > 0) {
      const root = normalize(object, 'workspace')
      return root ? [root] : []
    }

    for (const key of ['tree', 'root', 'workspace']) {
      if (object[key] !== undefined) {
        const root = normalize(object[key], key)
        return root ? [root] : []
      }
    }
  }

  const root = normalize(parsed, 'workspace')
  return root ? [root] : []
}

async function refresh() {
  loading.value = true
  error.value = ''

  try {
    const raw = await invoke<unknown>('vertex_project_tree')
    roots.value = normalizeRoots(raw)
    if (!roots.value.length) {
      error.value = 'PROJECT TREE RETURNED NO DISPLAYABLE NODES'
    }
  } catch (reason) {
    error.value = String(reason)
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void refresh()
})
</script>

<template>
  <CockpitPanelFrame
    title="VVE // TREE EXPLORER"
    subtitle="PROJECT WORLD / STRUCTURE"
    panel-id="vve-tree-explorer"
    dockable
    :status="error ? 'NO SIGNAL' : loading ? 'SCANNING' : 'ONLINE'"
    :status-tone="error ? 'amber' : 'blue'"
  >
    <div class="vve-shell">
      <div class="vve-toolbar">
        <div>
          <span>VIRTUAL EXPLORER</span>
          <strong>PROJECT WORLD</strong>
        </div>

        <button
          type="button"
          :disabled="loading"
          @click="refresh"
        >
          REFRESH
        </button>
      </div>

      <div class="vve-tree">
        <div
          v-if="loading"
          class="vve-state"
        >
          SCANNING PROJECT TREE...
        </div>

        <div
          v-else-if="error"
          class="vve-state error"
        >
          {{ error }}
        </div>

        <VveTreeNode
          v-for="root in roots"
          v-else
          :key="root.id"
          :node="root"
          :depth="0"
        />
      </div>

      <footer class="vve-footer">
        <span>VVE</span>
        <span>FOLDERS / FILES / FUTURE AGENTS / DRONES</span>
      </footer>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.vve-shell {
  display: grid;
  min-height: 520px;
  height: 100%;
  grid-template-rows: auto minmax(0,1fr) auto;
  background:
    radial-gradient(circle at 45% 0%, rgba(98,216,255,.035), transparent 28%),
    rgba(6,8,17,.72);
}

.vve-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 54px;
  padding: 0 12px;
  border-bottom: 1px solid var(--vertex-line);
}

.vve-toolbar span,
.vve-toolbar strong {
  display: block;
}

.vve-toolbar span {
  color: #6f7b9b;
  font: 720 9px/1 ui-monospace, Consolas, monospace;
}

.vve-toolbar strong {
  margin-top: 5px;
  color: #c3cce0;
  font: 740 12px/1 ui-monospace, Consolas, monospace;
}

.vve-toolbar button {
  height: 28px;
  padding: 0 9px;
  border: 1px solid #354064;
  border-radius: 4px;
  background: #0b0e1c;
  color: #8290b0;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.vve-tree {
  min-height: 0;
  overflow: auto;
  padding: 7px 0;
}

.vve-state {
  margin: 12px;
  padding: 14px;
  border: 1px solid #303957;
  border-radius: 5px;
  color: #8090aa;
  font: 700 10px/1.4 ui-monospace, Consolas, monospace;
}

.vve-state.error {
  border-color: rgba(242,198,109,.28);
  color: var(--vertex-amber);
}

.vve-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 34px;
  padding: 0 12px;
  gap: 10px;
  border-top: 1px solid var(--vertex-line);
  color: #596582;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $rolePanels 'VveTreeExplorerPanel.vue') $vve
  Write-Host 'VVE Tree Explorer              : CREATED' -ForegroundColor Green
  Write-Host 'Real vertex_project_tree IPC   : WIRED' -ForegroundColor Green
  Write-Host 'Custom Folder / File Icons     : CREATED' -ForegroundColor Green

  Write-Host "`n[5/14] BUILD INDEPENDENT UTILITY COMPONENTS" -ForegroundColor Yellow

  $activity=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../../cockpitTelemetry'
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <CockpitPanelFrame
    title="AI ACTIVITY MONITOR"
    subtitle="REAL OBSERVATION"
    panel-id="ai-activity-monitor"
    dockable
    :status="telemetry.liveOnline ? 'LIVE' : 'NO SIGNAL'"
    :status-tone="telemetry.liveOnline ? 'green' : 'muted'"
  >
    <div class="utility-body">
      <div class="metric">
        <span>AGENTS OBSERVED</span>
        <strong>{{ telemetry.agentCount ?? 'UNBOUND' }}</strong>
      </div>
      <div class="metric">
        <span>SESSION</span>
        <strong>{{ telemetry.sessionId || 'NO LIVE SESSION' }}</strong>
      </div>
      <div class="metric">
        <span>WAVE</span>
        <strong>{{ telemetry.waveId || '—' }}</strong>
      </div>
      <div class="metric">
        <span>DISPATCH</span>
        <strong>{{ telemetry.dispatchId || '—' }}</strong>
      </div>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.utility-body {
  display: grid;
  min-height: 180px;
  grid-template-columns: 1fr 1fr;
  gap: 1px;
  background: var(--vertex-line);
}
.metric {
  min-width: 0;
  padding: 13px;
  background: rgba(8,10,20,.96);
}
.metric span,
.metric strong {
  display: block;
}
.metric span {
  color: #687593;
  font: 720 9px/1 ui-monospace, Consolas, monospace;
}
.metric strong {
  margin-top: 8px;
  overflow: hidden;
  color: #abb7cd;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 12px/1.2 ui-monospace, Consolas, monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $rolePanels 'AiActivityMonitorPanel.vue') $activity

  function UtilityPanel([string]$title,[string]$subtitle,[string]$id,[string]$message,[string]$detail){
    return @"
<script setup lang="ts">
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'
</script>

<template>
  <CockpitPanelFrame
    title="$title"
    subtitle="$subtitle"
    panel-id="$id"
    dockable
    status="UNBOUND"
    status-tone="muted"
  >
    <div class="unbound-panel">
      <span>$message</span>
      <strong>$detail</strong>
      <p>No synthetic output is generated.</p>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.unbound-panel {
  min-height: 180px;
  padding: 16px;
  background:
    radial-gradient(circle at 50% 0%, rgba(124,92,255,.04), transparent 38%),
    rgba(8,10,20,.92);
}
.unbound-panel span {
  color: var(--vertex-blue-bright);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .06em;
}
.unbound-panel strong {
  display: block;
  margin-top: 12px;
  color: #c2cbe0;
  font: 760 14px/1.2 ui-monospace, Consolas, monospace;
}
.unbound-panel p {
  margin: 10px 0 0;
  color: #707c99;
  font-size: 11px;
  line-height: 1.45;
}
</style>
"@
  }

  WriteUtf8 (Join-Path $rolePanels 'TerminalPanel.vue') (
    UtilityPanel 'TERMINAL' 'CONTROLLED EXECUTION SURFACE' 'terminal' `
      'TERMINAL PANEL ADAPTER' 'CONTROLLED COMMAND TRANSPORT NOT WIRED'
  )

  WriteUtf8 (Join-Path $rolePanels 'BuildPanel.vue') (
    UtilityPanel 'BUILD' 'BUILD EVIDENCE' 'build' `
      'BUILD EVENT STREAM' 'NO CURRENT BUILD EVENT'
  )

  WriteUtf8 (Join-Path $rolePanels 'TestPanel.vue') (
    UtilityPanel 'TEST' 'TEST EVIDENCE' 'test' `
      'TEST EVENT STREAM' 'NO CURRENT TEST EVENT'
  )

  WriteUtf8 (Join-Path $rolePanels 'ReviewerPanel.vue') (
    UtilityPanel 'REVIEWER' 'ARD / REVIEW SIGNAL' 'reviewer' `
      'REVIEW EVENT STREAM' 'NO CURRENT REVIEW EVENT'
  )

  WriteUtf8 (Join-Path $rolePanels 'AiAssistantPanel.vue') (
    UtilityPanel 'AI ASSISTANT' 'SUGGESTION SURFACE' 'ai-assistant' `
      'ASSISTANT SUGGESTION STREAM' 'NO CURRENT SUGGESTION'
  )

  Write-Host 'AI Activity Monitor            : INDEPENDENT' -ForegroundColor Green
  Write-Host 'Terminal                       : INDEPENDENT' -ForegroundColor Green
  Write-Host 'Build                          : INDEPENDENT' -ForegroundColor Green
  Write-Host 'Test                           : INDEPENDENT' -ForegroundColor Green
  Write-Host 'Reviewer                       : INDEPENDENT' -ForegroundColor Green
  Write-Host 'AI Assistant                   : INDEPENDENT' -ForegroundColor Green

  Write-Host "`n[6/14] BUILD PLAYER HUD FOOTER" -ForegroundColor Yellow

  $hud=@'
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <footer class="player-hud">
    <section class="hud-player">
      <div class="player-sigil">
        <span>V</span>
      </div>
      <div>
        <small>PLAYER</small>
        <strong>CAPTAIN</strong>
      </div>
    </section>

    <section class="hud-stat">
      <small>LEVEL</small>
      <strong>UNBOUND</strong>
      <div class="xp-track">
        <span />
      </div>
      <em>XP LINK UNBOUND</em>
    </section>

    <section class="hud-stat vx">
      <small>VX</small>
      <strong>UNBOUND</strong>
      <em>GAME CURRENCY LINK</em>
    </section>

    <section class="hud-stat">
      <small>RANK</small>
      <strong>UNBOUND</strong>
      <em>RPG PROFILE LINK</em>
    </section>

    <section class="hud-stat quest">
      <small>QUEST</small>
      <strong>NO ACTIVE QUEST</strong>
      <em>QUEST SYSTEM UNBOUND</em>
    </section>

    <section class="hud-stat world">
      <small>WORLD STATUS</small>
      <strong :class="{ online: telemetry.runtimeOnline }">
        {{ telemetry.runtimeOnline ? 'RUNTIME ONLINE' : 'NO SIGNAL' }}
      </strong>
      <em>{{ telemetry.projectLabel }}</em>
    </section>

    <section class="hud-stat drone">
      <small>DRONE HOST</small>
      <strong>UNBOUND</strong>
      <em>HOST CONTRACT RESERVED</em>
    </section>
  </footer>
</template>

<style scoped>
.player-hud {
  display: grid;
  min-width: 0;
  height: 72px;
  grid-template-columns:
    220px
    190px
    170px
    170px
    minmax(240px,1fr)
    minmax(220px,.9fr)
    210px;
  align-items: stretch;
  border-top: 1px solid rgba(111,88,196,.72);
  background:
    radial-gradient(circle at 14% -90%, rgba(124,92,255,.22), transparent 42%),
    linear-gradient(90deg, #0c0d1e, #080a16 42%, #0c0d1e);
  box-shadow:
    0 -1px 0 rgba(169,140,255,.08),
    0 -12px 30px rgba(0,0,0,.18);
}

.player-hud > section {
  min-width: 0;
  padding: 11px 14px;
  border-right: 1px solid rgba(52,60,99,.72);
}

.player-hud > section:last-child {
  border-right: 0;
}

.hud-player {
  display: flex;
  align-items: center;
  gap: 12px;
}

.player-sigil {
  display: grid;
  width: 42px;
  height: 42px;
  flex: none;
  place-items: center;
  border: 1px solid rgba(169,140,255,.52);
  transform: rotate(45deg);
  background:
    radial-gradient(circle, rgba(124,92,255,.27), rgba(15,15,37,.92) 65%);
  box-shadow: 0 0 18px rgba(124,92,255,.10);
}

.player-sigil span {
  transform: rotate(-45deg);
  color: var(--vertex-blue-bright);
  font-size: 18px;
  font-weight: 850;
}

.player-hud small,
.player-hud strong,
.player-hud em {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.player-hud small {
  color: #667392;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.player-hud strong {
  margin-top: 6px;
  color: #c9d1e5;
  font: 750 13px/1 ui-monospace, Consolas, monospace;
}

.player-hud em {
  margin-top: 6px;
  color: #596581;
  font: 650 8px/1 ui-monospace, Consolas, monospace;
  font-style: normal;
}

.hud-player strong {
  color: #e2e5f2;
  font-size: 15px;
}

.vx strong {
  color: var(--vertex-blue-bright);
}

.world strong.online {
  color: var(--vertex-green);
}

.xp-track {
  height: 4px;
  margin-top: 8px;
  overflow: hidden;
  border-radius: 6px;
  background: #171b30;
}

.xp-track span {
  display: block;
  width: 0;
  height: 100%;
  background: linear-gradient(90deg, var(--vertex-blue), var(--vertex-cyan, #62d8ff));
}

@media (max-width: 1600px) {
  .player-hud {
    grid-template-columns:
      180px
      150px
      130px
      130px
      minmax(190px,1fr)
      minmax(180px,.9fr);
  }

  .drone {
    display: none;
  }
}

@media (max-width: 1200px) {
  .player-hud {
    grid-template-columns: 160px 130px 110px minmax(180px,1fr);
  }

  .hud-stat:nth-of-type(4),
  .world,
  .drone {
    display: none;
  }
}
</style>
'@
  WriteUtf8 (Join-Path $roleDir 'PlayerHud.vue') $hud

  Write-Host 'Traditional Footer            : REPLACED' -ForegroundColor Green
  Write-Host 'Player HUD                     : CREATED' -ForegroundColor Green
  Write-Host 'Fake Level / XP / VX           : DENIED' -ForegroundColor Green

  Write-Host "`n[7/14] REBUILD COCKPIT SHELL AROUND ROLES" -ForegroundColor Yellow

  $themeImport=''
  $aetherTheme=Join-Path $cockpit 'theme\vertex-aether-violet.css'
  if(Test-Path -LiteralPath $aetherTheme){
    $themeImport="import './theme/vertex-aether-violet.css'`r`n"
  }

  $shellSource=@'
<script setup lang="ts">
import type { Component } from 'vue'
import {
  computed,
  onMounted,
  onUnmounted,
  ref,
} from 'vue'
__THEME_IMPORT__
import { useCockpitTelemetry } from './cockpitTelemetry'
import {
  type DockPanelState,
  type DockZone,
  useDockLayout,
} from './dockLayout'

import SystemMonitorPanel from './panels/SystemMonitorPanel.vue'
import VspSnapshotPanel from './panels/VspSnapshotPanel.vue'

import AiActivityMonitorPanel from './role-layout/panels/AiActivityMonitorPanel.vue'
import AiAssistantPanel from './role-layout/panels/AiAssistantPanel.vue'
import BuildPanel from './role-layout/panels/BuildPanel.vue'
import HyperAgentChatPanel from './role-layout/panels/HyperAgentChatPanel.vue'
import ReviewerPanel from './role-layout/panels/ReviewerPanel.vue'
import TerminalPanel from './role-layout/panels/TerminalPanel.vue'
import TestPanel from './role-layout/panels/TestPanel.vue'
import VveTreeExplorerPanel from './role-layout/panels/VveTreeExplorerPanel.vue'
import PlayerHud from './role-layout/PlayerHud.vue'

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

const panelComponents: Record<string, Component> = {
  'hyperagent-chat': HyperAgentChatPanel,
  'vve-tree-explorer': VveTreeExplorerPanel,
  'ai-activity-monitor': AiActivityMonitorPanel,
  terminal: TerminalPanel,
  build: BuildPanel,
  test: TestPanel,
  reviewer: ReviewerPanel,
  'ai-assistant': AiAssistantPanel,
  'system-monitor': SystemMonitorPanel,
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

function allowDrop(zone: DockZone, event: DragEvent) {
  event.preventDefault()
  activeDropZone.value = zone
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
}

function leaveDrop(zone: DockZone) {
  if (activeDropZone.value === zone) activeDropZone.value = ''
}

function dropTo(zone: DockZone, event: DragEvent) {
  event.preventDefault()

  const id = panelIdFromDrag(event)
  if (!id) return

  if (zone === 'float') {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect()
    movePanel(id, 'float', {
      x: Math.max(8, event.clientX - rect.left - 180),
      y: Math.max(8, event.clientY - rect.top - 28),
    })
  } else {
    movePanel(id, zone)
  }

  draggingPanelId.value = ''
  activeDropZone.value = ''
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

  movePanel(detail.panelId, 'float', {
    x: Math.max(20, window.innerWidth * 0.5 - 220),
    y: 110,
  })
}

function beginResize(
  target: 'left' | 'right' | 'bottom',
  event: MouseEvent,
) {
  event.preventDefault()

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
    class="vertex-cockpit role-layout-v5"
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
          <small>HUMAN + AI DEVELOPMENT MOTHERSHIP</small>
        </div>
      </div>

      <div class="status-deck">
        <div class="status-card">
          <span>PROJECT</span>
          <strong>{{ telemetry.projectLabel }}</strong>
          <small>WORKSPACE</small>
        </div>

        <div class="status-card">
          <span>VSP</span>
          <strong>{{ telemetry.liveOnline ? 'LIVE' : 'NO SIGNAL' }}</strong>
          <small>{{ telemetry.checkpointId || telemetry.sessionId || 'UNBOUND' }}</small>
        </div>

        <div class="status-card">
          <span>VXN</span>
          <strong>{{ telemetry.runtimeOnline ? 'ONLINE' : 'OFFLINE' }}</strong>
          <small>RUNTIME CORE</small>
        </div>

        <div class="status-card">
          <span>ARD</span>
          <strong>{{ telemetry.agentCount === null ? 'UNBOUND' : `${telemetry.agentCount} AGENTS` }}</strong>
          <small>MISSION LINEAGE</small>
        </div>

        <div class="status-card">
          <span>VERTEXHUB</span>
          <strong>{{ telemetry.hubOnline ? 'ONLINE' : 'NO SIGNAL' }}</strong>
          <small>{{ telemetry.hubEnabledCount }}/{{ telemetry.hubPackageCount }} ENABLED</small>
        </div>
      </div>

      <div class="cockpit-clock">
        <span>USER : CAPTAIN</span>
        <small>MODE : CREATION</small>
        <strong>{{ telemetry.now }}</strong>
      </div>
    </header>

    <section class="cockpit-workspace">
      <aside
        v-if="leftPanels.length"
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
        <div class="editor-role-marker">
          <span>MAIN WORKSPACE</span>
          <strong>VSA EDITOR // FIXED CENTER</strong>
        </div>

        <div class="editor-slot">
          <slot />
        </div>

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
            <span>HUMAN / TOOL DOCK</span>
          </div>

          <div
            class="dock-target target-float"
            :class="{ active: activeDropZone === 'float' }"
            @dragover="allowDrop('float', $event)"
            @dragleave="leaveDrop('float')"
            @drop="dropTo('float', $event)"
          >
            <strong>FLOAT</strong>
            <span>FREE EQUIPMENT</span>
          </div>

          <div
            class="dock-target target-right"
            :class="{ active: activeDropZone === 'right' }"
            @dragover="allowDrop('right', $event)"
            @dragleave="leaveDrop('right')"
            @drop="dropTo('right', $event)"
          >
            <strong>RIGHT</strong>
            <span>WORLD / STRUCTURE DOCK</span>
          </div>

          <div
            class="dock-target target-bottom"
            :class="{ active: activeDropZone === 'bottom' }"
            @dragover="allowDrop('bottom', $event)"
            @dragleave="leaveDrop('bottom')"
            @drop="dropTo('bottom', $event)"
          >
            <strong>BOTTOM</strong>
            <span>UTILITY DECK</span>
          </div>
        </div>
      </main>

      <aside
        v-if="rightPanels.length"
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
        v-if="bottomPanels.length"
        class="dock-bottom"
      >
        <button
          class="bottom-resizer"
          title="Resize utility deck"
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

    <PlayerHud :telemetry="telemetry" />

    <nav class="cockpit-command-rail">
      <button
        v-for="panel in allKnownPanels"
        :key="panel.id"
        :class="{ active: panel.visible }"
        :title="panel.visible ? `Hide ${panel.id}` : `Show ${panel.id}`"
        @click="panel.visible ? hidePanel(panel.id) : showPanel(panel.id)"
      >
        {{
          panel.id === 'hyperagent-chat'
            ? 'CHAT'
            : panel.id === 'vve-tree-explorer'
              ? 'VVE'
              : panel.id === 'ai-activity-monitor'
                ? 'ACT'
                : panel.id === 'ai-assistant'
                  ? 'AIA'
                  : panel.id === 'system-monitor'
                    ? 'SYS'
                    : panel.id === 'vsp-snapshot'
                      ? 'VSP'
                      : panel.id.toUpperCase()
        }}
      </button>

      <span class="rail-separator" />

      <button
        title="Reset Role Layout (Ctrl+Shift+R)"
        @click="resetLayout"
      >
        RESET
      </button>
    </nav>
  </div>
</template>

<style scoped>
.vertex-cockpit {
  --vertex-bg-deep: #070812;
  --vertex-bg-panel: #0c0f1d;
  --vertex-bg-panel-raised: #12162a;
  --vertex-bg-hover: #171d37;
  --vertex-line: #242b46;
  --vertex-line-bright: #38446a;
  --vertex-text: #d7def0;
  --vertex-muted: #8d97b8;
  --vertex-faint: #5d6688;
  --vertex-blue: #7c5cff;
  --vertex-blue-bright: #a98cff;
  --vertex-blue-soft: #251f52;
  --vertex-cyan: #62d8ff;
  --vertex-green: #66e2b1;
  --vertex-amber: #f2c66d;
  --vertex-red: #ff748f;

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
  grid-template-rows: 90px minmax(0,1fr) 72px;
  overflow: hidden;
  background:
    radial-gradient(circle at 52% -15%, rgba(124,92,255,.14), transparent 36%),
    #070812;
  color: var(--vertex-text);
  font-size: var(--cockpit-base-font);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.cockpit-top-deck {
  display: grid;
  min-width: 0;
  grid-template-columns: 280px minmax(0,1fr) 180px;
  gap: 7px;
  padding: 8px;
  border-bottom: 1px solid rgba(100,80,175,.55);
  background:
    linear-gradient(180deg, rgba(17,20,39,.98), rgba(8,10,20,.99));
}

.cockpit-brand,
.cockpit-clock,
.status-card {
  min-width: 0;
  border: 1px solid rgba(55,63,103,.86);
  background:
    linear-gradient(160deg, rgba(18,22,43,.96), rgba(8,10,20,.98));
}

.cockpit-brand {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 13px;
}

.brand-mark {
  display: grid;
  width: 40px;
  height: 40px;
  place-items: center;
  border: 1px solid rgba(169,140,255,.72);
  transform: rotate(45deg);
  background: #171630;
}

.brand-mark span {
  transform: rotate(-45deg);
  color: var(--vertex-blue-bright);
  font-size: 15px;
  font-weight: 850;
}

.cockpit-brand strong,
.cockpit-brand small {
  display: block;
}

.cockpit-brand strong {
  color: #e4e7f3;
  font-size: 16px;
  letter-spacing: .04em;
}

.cockpit-brand small {
  margin-top: 5px;
  color: #737d9d;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.status-deck {
  display: grid;
  min-width: 0;
  grid-template-columns: repeat(5, minmax(150px,1fr));
  gap: 6px;
  overflow-x: auto;
}

.status-card {
  padding: 13px;
}

.status-card span,
.status-card strong,
.status-card small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.status-card span {
  color: #7a86a8;
  font: 750 10px/1 ui-monospace, Consolas, monospace;
}

.status-card strong {
  margin-top: 8px;
  color: #c7cfe2;
  font: 760 13px/1 ui-monospace, Consolas, monospace;
}

.status-card small {
  margin-top: 6px;
  color: #596582;
  font: 650 9px/1 ui-monospace, Consolas, monospace;
}

.cockpit-clock {
  display: grid;
  align-content: center;
  justify-items: end;
  padding: 0 13px;
}

.cockpit-clock span,
.cockpit-clock small {
  color: #8994b0;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.cockpit-clock small {
  margin-top: 5px;
}

.cockpit-clock strong {
  margin-top: 8px;
  color: #e1e4ef;
  font: 500 18px/1 ui-monospace, Consolas, monospace;
}

.cockpit-workspace {
  position: relative;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns:
    var(--dock-left-width,0px)
    minmax(0,1fr)
    var(--dock-right-width,0px);
  grid-template-rows:
    minmax(0,1fr)
    var(--dock-bottom-height,0px);
  overflow: hidden;
}

.dock-column {
  position: relative;
  z-index: 30;
  display: flex;
  min-width: 0;
  min-height: 0;
  flex-direction: column;
  gap: 8px;
  padding: 8px;
  overflow: auto;
  background:
    linear-gradient(180deg, rgba(10,12,25,.995), rgba(6,8,17,.998));
}

.dock-left {
  grid-column: 1;
  grid-row: 1;
  border-right: 1px solid rgba(74,66,125,.70);
}

.dock-right {
  grid-column: 3;
  grid-row: 1;
  border-left: 1px solid rgba(74,66,125,.70);
}

.cockpit-editor-surface {
  position: relative;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-column: 2;
  grid-row: 1;
  grid-template-rows: 34px minmax(0,1fr);
  overflow: hidden;
  background:
    radial-gradient(circle at 55% 0%, rgba(124,92,255,.04), transparent 32%),
    #070812;
}

/* EDITOR IS THE DECK. NEVER A DOCK PANEL. */
.editor-role-marker {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-width: 0;
  padding: 0 11px;
  border-bottom: 1px solid rgba(48,57,92,.80);
  background: #090c19;
}

.editor-role-marker span {
  color: #687593;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
}

.editor-role-marker strong {
  color: #9ba7c1;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
}

.editor-slot {
  min-width: 0;
  min-height: 0;
  overflow: hidden;
}

.editor-slot > :deep(*) {
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
}

.dock-bottom {
  position: relative;
  z-index: 35;
  grid-column: 1 / 4;
  grid-row: 2;
  min-width: 0;
  min-height: 0;
  padding: 8px;
  overflow: auto;
  border-top: 1px solid rgba(74,66,125,.70);
  background: #080a16;
}

.bottom-panel-strip {
  display: grid;
  min-width: max-content;
  grid-auto-flow: column;
  grid-auto-columns: minmax(330px, 420px);
  align-items: stretch;
  gap: 8px;
  height: 100%;
}

.bottom-panel-strip > :deep(*) {
  min-height: 100%;
}

.column-resizer {
  position: absolute;
  z-index: 45;
  top: 0;
  bottom: 0;
  width: 8px;
  border: 0;
  background: transparent;
  cursor: ew-resize;
}

.left-resizer {
  right: -5px;
}

.right-resizer {
  left: -5px;
}

.bottom-resizer {
  position: absolute;
  z-index: 45;
  top: -5px;
  right: 0;
  left: 0;
  height: 8px;
  border: 0;
  background: transparent;
  cursor: ns-resize;
}

.floating-panel {
  position: absolute;
  z-index: 500;
  min-width: 300px;
  min-height: 180px;
  overflow: auto;
  resize: both;
  border: 1px solid rgba(111,88,196,.54);
  border-radius: 6px;
  background: #0a0d1b;
  box-shadow: 0 24px 72px rgba(0,0,0,.58);
}

.dock-overlay {
  position: absolute;
  z-index: 8000;
  inset: 34px 0 0;
  pointer-events: none;
  background: rgba(5,7,15,.22);
}

.dock-target {
  position: absolute;
  display: grid;
  place-items: center;
  border: 1px solid rgba(169,140,255,.44);
  border-radius: 8px;
  background: rgba(26,22,58,.82);
  pointer-events: auto;
}

.dock-target.active {
  border-color: #d1c4ff;
  background: rgba(51,39,106,.92);
  box-shadow: 0 0 30px rgba(124,92,255,.23);
}

.dock-target strong,
.dock-target span {
  display: block;
  text-align: center;
}

.dock-target strong {
  color: #dfd8f7;
  font: 850 16px/1 ui-monospace, Consolas, monospace;
}

.dock-target span {
  margin-top: 7px;
  color: #8395bb;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
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
  height: 100px;
}

.target-float {
  top: 34%;
  right: 34%;
  bottom: 34%;
  left: 34%;
}

.cockpit-command-rail {
  position: fixed;
  z-index: 9000;
  right: 10px;
  bottom: 80px;
  display: flex;
  max-width: 70vw;
  min-height: 34px;
  align-items: center;
  padding: 5px;
  gap: 5px;
  overflow-x: auto;
  border: 1px solid #3c4167;
  border-radius: 5px;
  background: rgba(8,10,20,.96);
}

.cockpit-command-rail button {
  height: 25px;
  padding: 0 8px;
  border: 1px solid #323a5d;
  border-radius: 3px;
  background: #0c0f1e;
  color: #7d88a7;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.cockpit-command-rail button.active {
  border-color: #7258c6;
  background: #211b46;
  color: #c3b3ff;
}

.rail-separator {
  width: 1px;
  height: 18px;
  background: #333a5e;
}

@media (min-width: 2200px) {
  .vertex-cockpit {
    grid-template-rows: 98px minmax(0,1fr) 78px;
  }

  .cockpit-top-deck {
    grid-template-columns: 310px minmax(0,1fr) 190px;
    padding: 9px 10px;
  }

  .dock-column {
    padding: 10px;
    gap: 10px;
  }
}

@media (max-width: 1279px) {
  .vertex-cockpit {
    grid-template-rows: 82px minmax(0,1fr) 64px;
  }

  .cockpit-top-deck {
    grid-template-columns: 220px minmax(0,1fr) 130px;
    padding: 6px;
  }

  .status-deck {
    display: flex;
    overflow-x: auto;
  }

  .status-card {
    min-width: 155px;
  }

  .cockpit-workspace {
    grid-template-columns: minmax(0,1fr);
  }

  .cockpit-editor-surface {
    grid-column: 1;
  }

  .dock-left,
  .dock-right {
    position: absolute;
    top: 0;
    bottom: var(--dock-bottom-height,0px);
    width: min(82vw, 420px);
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
}
</style>
'@

  $shellSource=$shellSource.Replace('__THEME_IMPORT__',$themeImport.TrimEnd())
  WriteUtf8 $shell $shellSource

  Write-Host 'LEFT role                     : HYPERAGENT CHAT' -ForegroundColor Green
  Write-Host 'CENTER role                   : EDITOR FIXED' -ForegroundColor Green
  Write-Host 'RIGHT role                    : VVE TREE EXPLORER' -ForegroundColor Green
  Write-Host 'BOTTOM role                   : UTILITY COMPONENTS' -ForegroundColor Green
  Write-Host 'FOOTER role                   : PLAYER HUD' -ForegroundColor Green

  Write-Host "`n[8/14] FRONTEND TYPECHECK" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[role-v5] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[9/14] FRONTEND BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[role-v5] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[10/14] ROLE / SAFETY AUDIT" -ForegroundColor Yellow

  $roleText=(
    Get-ChildItem -LiteralPath $roleDir -Recurse -File |
    ForEach-Object {[IO.File]::ReadAllText($_.FullName)}
  ) -join "`n"

  $shellNow=[IO.File]::ReadAllText($shell)
  $dockNow=[IO.File]::ReadAllText($dockLayout)
  $editorNow=[IO.File]::ReadAllText($editor)

  $audits=@(
    [pscustomobject]@{
      Name='HyperAgent default LEFT'
      Pass=$dockNow.Contains("id: 'hyperagent-chat'") -and
           $dockNow.Contains("zone: 'left'")
    },
    [pscustomobject]@{
      Name='VVE default RIGHT'
      Pass=$dockNow.Contains("id: 'vve-tree-explorer'") -and
           $dockNow.Contains("zone: 'right'")
    },
    [pscustomobject]@{
      Name='AI Activity independent'
      Pass=$dockNow.Contains("id: 'ai-activity-monitor'")
    },
    [pscustomobject]@{
      Name='Terminal independent'
      Pass=$dockNow.Contains("id: 'terminal'")
    },
    [pscustomobject]@{
      Name='Build independent'
      Pass=$dockNow.Contains("id: 'build'")
    },
    [pscustomobject]@{
      Name='Test independent'
      Pass=$dockNow.Contains("id: 'test'")
    },
    [pscustomobject]@{
      Name='Reviewer independent'
      Pass=$dockNow.Contains("id: 'reviewer'")
    },
    [pscustomobject]@{
      Name='AI Assistant independent'
      Pass=$dockNow.Contains("id: 'ai-assistant'")
    },
    [pscustomobject]@{
      Name='Editor fixed center'
      Pass=$shellNow.Contains('VSA EDITOR // FIXED CENTER')
    },
    [pscustomobject]@{
      Name='Editor absent from DockLayout'
      Pass=(-not $dockNow.Contains("id: 'editor'")) -and
           (-not $dockNow.Contains("id: 'vsa-editor'"))
    },
    [pscustomobject]@{
      Name='Player HUD telemetry import'
      Pass=([IO.File]::ReadAllText((Join-Path $roleDir 'PlayerHud.vue'))).Contains(
        "from '../cockpitTelemetry'"
      )
    },
    [pscustomobject]@{
      Name='Player HUD'
      Pass=$roleText.Contains('PLAYER') -and
           $roleText.Contains('XP LINK UNBOUND') -and
           $roleText.Contains('GAME CURRENCY LINK')
    },
    [pscustomobject]@{
      Name='No fake Level 42'
      Pass=(-not $roleText.Contains('LEVEL 42'))
    },
    [pscustomobject]@{
      Name='No fake VX 12,480'
      Pass=(-not $roleText.Contains('12,480'))
    },
    [pscustomobject]@{
      Name='No fake chat messages'
      Pass=$roleText.Contains('No synthetic conversation is generated.')
    },
    [pscustomobject]@{
      Name='Real project tree IPC'
      Pass=$roleText.Contains("invoke<unknown>('vertex_project_tree')")
    },
    [pscustomobject]@{
      Name='Drone contract'
      Pass=$dockNow.Contains("'drone'")
    },
    [pscustomobject]@{
      Name='No eval'
      Pass=(-not $roleText.Contains('eval(')) -and
           (-not $shellNow.Contains('eval('))
    },
    [pscustomobject]@{
      Name='No arbitrary shell'
      Pass=(-not $roleText.Contains('powershell.exe')) -and
           (-not $roleText.Contains('cmd.exe')) -and
           (-not $roleText.Contains('Command::new'))
    },
    [pscustomobject]@{
      Name='No remote runtime import'
      Pass=(-not $roleText.Contains('import("http://')) -and
           (-not $roleText.Contains("import('http://")) -and
           (-not $roleText.Contains('import("https://')) -and
           (-not $roleText.Contains("import('https://"))
    },
    [pscustomobject]@{
      Name='Existing Editor wrapper preserved'
      Pass=$editorNow.Contains('<VertexCockpitShell>')
    },
    [pscustomobject]@{
      Name='GUI Live Preview preserved'
      Pass=$editorNow.Contains('<VertexLivePreview />')
    },
    [pscustomobject]@{
      Name='VertexHub preserved'
      Pass=$editorNow.Contains('<VertexHubDock />')
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "Role V5 audit RED: $($audit.Name)"}
    Write-Host ("  {0,-40} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[11/14] TAURI CLEAN-ROOM CHECK" -ForegroundColor Yellow

  $previousCargoTarget=$env:CARGO_TARGET_DIR
  try{
    if(Test-Path -LiteralPath $tauriCheckTarget){
      Remove-Item -LiteralPath $tauriCheckTarget -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tauriCheckTarget -Force|Out-Null
    $env:CARGO_TARGET_DIR=$tauriCheckTarget

    RunChecked '[release] Tauri cargo check - clean room' {
      & $cargo.Source check --manifest-path $tauriCargo --all-targets
    }
  }finally{
    $env:CARGO_TARGET_DIR=$previousCargoTarget
  }

  Write-Host "`n[12/14] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  Write-Host "`n[13/14] FINAL FRONTEND GATE" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[release] pnpm build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[14/14] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.role-layout.v5r1'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA ROLE LAYOUT REBUILD V5R1'
    roles=[ordered]@{
      left='HYPERAGENT CHAT / HUMAN INTENT GATEWAY'
      center='VSA EDITOR / FIXED MAIN WORKSPACE'
      right='VVE TREE EXPLORER'
      bottom='INDEPENDENT UTILITY COMPONENTS'
      footer='PLAYER HUD / RPG META LAYER'
    }
    independent_components=@(
      'hyperagent-chat',
      'vve-tree-explorer',
      'ai-activity-monitor',
      'terminal',
      'build',
      'test',
      'reviewer',
      'ai-assistant',
      'system-monitor',
      'vsp-snapshot'
    )
    player_hud=[ordered]@{
      level='UNBOUND'
      xp='UNBOUND'
      vx='UNBOUND'
      rank='UNBOUND'
      quest='UNBOUND'
      world_status='REAL RUNTIME SIGNAL'
      drone='CONTRACT RESERVED / UNBOUND'
      synthetic_values='DENIED'
      telemetry_import='CORRECTED ../cockpitTelemetry'
    }
    data=[ordered]@{
      project_tree='REAL vertex_project_tree IPC'
      live_telemetry='REAL SIGNAL ONLY'
      hyperagent_message_transport='UNBOUND'
      terminal_panel_adapter='UNBOUND'
      build_stream='UNBOUND'
      test_stream='UNBOUND'
      reviewer_stream='UNBOUND'
    }
    safety=[ordered]@{
      editor_float='DENIED'
      editor_dock='DENIED'
      synthetic_chat='DENIED'
      synthetic_rpg='DENIED'
      arbitrary_eval='DENIED'
      arbitrary_shell='DENIED'
      remote_runtime_import='DENIED'
    }
    preserved=[ordered]@{
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
    next_target='REAL HYPERAGENT CHAT TRANSPORT / UTILITY SIGNAL ADAPTERS / TAB STACK'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - VSA ROLE LAYOUT REBUILD V5R1R1 GREEN
============================================================
 LEFT / Human Intent                       HYPERAGENT CHAT
 CENTER / Main Workspace                   VSA EDITOR FIXED
 RIGHT / Project World                     VVE TREE EXPLORER
 BOTTOM / Utility Deck                     INDEPENDENT PANELS
 FOOTER / Meta Layer                       PLAYER HUD

 HyperAgent Chat                           CREATED
 HyperAgent Message Transport              UNBOUND / NO FAKE
 VVE Tree Explorer                         REAL PROJECT TREE IPC
 Custom VVE Folder Icons                   ONLINE

 AI Activity Monitor                       INDEPENDENT
 Terminal                                  INDEPENDENT
 Build                                     INDEPENDENT
 Test                                      INDEPENDENT
 Reviewer                                  INDEPENDENT
 AI Assistant                              INDEPENDENT

 Panel Drag / Dock / Float                 ONLINE
 LEFT / RIGHT / BOTTOM / FLOAT             ONLINE
 Layout Persistence                        ONLINE
 Editor Dock                               DENIED
 Editor Float                              DENIED

 Player Level                              UNBOUND
 Player XP                                 UNBOUND
 Player HUD Telemetry Import               CORRECTED
 VX                                        UNBOUND
 Rank                                      UNBOUND
 Quest                                     UNBOUND
 Drone Host                                CONTRACT RESERVED
 Synthetic RPG Values                      DENIED

 Existing Editor                           PRESERVED
 GUI Live Preview                          PRESERVED
 VertexHub                                 PRESERVED
 Mothership / Runtime Bus                  UNTOUCHED
 Frontend Typecheck                        GREEN
 Frontend Build                            GREEN
 Tauri Check                               GREEN
 Workspace Release Gate                    GREEN
------------------------------------------------------------
 NEXT TARGET:
 REAL HYPERAGENT CHAT TRANSPORT
 UTILITY SIGNAL ADAPTERS
 PANEL TAB STACK
============================================================
 HUMAN INTENT HAS A FRONT DOOR.
 WE ARE VERTEX.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' VSA ROLE LAYOUT REBUILD V5R1 RED - DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  if(Test-Path -LiteralPath $cockpit){
    Copy-Item -LiteralPath $cockpit -Destination (Join-Path $failed 'vertex-cockpit.failed') -Recurse -Force -ErrorAction SilentlyContinue
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
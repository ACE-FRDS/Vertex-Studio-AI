& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC — GUI LIVE DEVELOPMENT MODE V1
#
# Mission:
#   Remove the "blindfold".
#   Give VSA a real GUI preview surface beside the editor while
#   preserving current Hub / Mothership / Runtime safety boundaries.
#
# Live Development contract:
#   - F10 opens/closes preview
#   - resizable right-side GUI dock
#   - static, trusted preview registry only
#   - VertexHub catalog components become preview targets
#   - Vite/Tauri dev HMR updates preview after save
#   - no eval / arbitrary filesystem import / remote URL import
#   - dedicated START_VERTEX_GUI_DEV.ps1 launcher
#
# Current topology:
#   v0.2 UI + ProgramSource only
#   LEGACY untouched
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'

$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$packageJson=Join-Path $ui 'package.json'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$hubCatalog=Join-Path $ui 'src\vertex-hub\catalog.ts'
$hubDock=Join-Path $ui 'src\vertex-hub\VertexHubDock.vue'

$previewRoot=Join-Path $ui 'src\vertex-preview'
$previewRegistry=Join-Path $previewRoot 'previewRegistry.ts'
$previewSurface=Join-Path $previewRoot 'VertexSystemPreview.vue'
$previewDock=Join-Path $previewRoot 'VertexLivePreview.vue'
$launcher=Join-Path $startup 'START_VERTEX_GUI_DEV.ps1'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "GUI_LIVE_DEVELOPMENT_MODE_V1_BACKUP.$stamp"
$failed=Join-Path $reports "GUI_LIVE_DEVELOPMENT_MODE_V1_FAILED.$stamp"
$report=Join-Path $reports "GUI_LIVE_DEVELOPMENT_MODE_V1.$stamp.json"

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

Write-Host @'
============================================================
 VERTEX — GUI LIVE DEVELOPMENT MODE V1
 REMOVE THE BLINDFOLD
============================================================
'@ -ForegroundColor Cyan

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$coreCargo,$tauriCargo,
  $packageJson,$editor,$hubCatalog,$hubDock
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required current-core artifact missing: $required"
  }
}

if(Test-Path -LiteralPath $previewRoot){
  throw "GUI preview source already exists: $previewRoot"
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/10] CURRENT VERTEX BASELINE LOCK" -ForegroundColor Yellow

$editorText=[IO.File]::ReadAllText($editor)
$hubCatalogText=[IO.File]::ReadAllText($hubCatalog)
$hubDockText=[IO.File]::ReadAllText($hubDock)

$baseline=@(
  [pscustomobject]@{
    Name='VertexHubDock import'
    Pass=$editorText.Contains("import VertexHubDock from '../vertex-hub/VertexHubDock.vue'")
  },
  [pscustomobject]@{
    Name='VertexHubDock render'
    Pass=$editorText.Contains('<VertexHubDock />')
  },
  [pscustomobject]@{
    Name='Hub static component catalog'
    Pass=$hubCatalogText.Contains('vertexHubUiPackages')
  },
  [pscustomobject]@{
    Name='FME Vertex Blue'
    Pass=$hubDockText.Contains('--vertex-blue: #168cff')
  },
  [pscustomobject]@{
    Name='FME Bright Blue'
    Pass=$hubDockText.Contains('--vertex-blue-bright: #3ab8ff')
  }
)

foreach($item in $baseline){
  if(-not $item.Pass){throw "Current baseline missing: $($item.Name)"}
  Write-Host ("  {0,-34} GREEN" -f $item.Name) -ForegroundColor Green
}

RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

RunChecked '[baseline] Tauri cargo check' {
  & $cargo.Source check --manifest-path $tauriCargo --all-targets
}

Write-Host "`n[1/10] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
BackupFile $editor 'VertexEditorDock.vue'
if(Test-Path -LiteralPath $launcher){BackupFile $launcher 'START_VERTEX_GUI_DEV.ps1'}
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/10] BUILD TRUSTED PREVIEW REGISTRY" -ForegroundColor Yellow

  $registry=@'
import { markRaw, type Component } from 'vue'
import { vertexHubUiPackages } from '../vertex-hub/catalog'
import VertexSystemPreview from './VertexSystemPreview.vue'

export interface VertexPreviewTarget {
  id: string
  label: string
  group: 'SYSTEM' | 'VERTEXHUB'
  description: string
  component: Component
  source: string
}

const hubTargets: VertexPreviewTarget[] = vertexHubUiPackages.map((pkg) => ({
  id: `hub:${pkg.packageId}@${pkg.version}`,
  label: pkg.displayName,
  group: 'VERTEXHUB',
  description: pkg.summary,
  component: markRaw(pkg.component),
  source: `${pkg.packageId}@${pkg.version}`,
}))

export const vertexPreviewTargets: VertexPreviewTarget[] = [
  {
    id: 'system:vertex-surface',
    label: 'Vertex System Surface',
    group: 'SYSTEM',
    description: 'FME-derived Vertex visual language and live-development reference surface.',
    component: markRaw(VertexSystemPreview),
    source: 'src/vertex-preview/VertexSystemPreview.vue',
  },
  ...hubTargets,
]
'@
  WriteUtf8 $previewRegistry $registry

  $surface=@'
<template>
  <main class="surface">
    <header class="surface-header">
      <div class="brand">
        <div class="vertex-mark">
          <span>V</span>
        </div>
        <div>
          <p class="eyebrow">VERTEX // LIVE DEVELOPMENT SURFACE</p>
          <h1>Visual systems online.</h1>
          <p class="subtitle">
            Edit. Save. Observe. Correct. No more blind development.
          </p>
        </div>
      </div>

      <div class="status-cluster">
        <article>
          <span>PREVIEW</span>
          <strong>ONLINE</strong>
        </article>
        <article>
          <span>HMR</span>
          <strong>LINKED</strong>
        </article>
        <article>
          <span>TRUST</span>
          <strong>STATIC</strong>
        </article>
      </div>
    </header>

    <section class="command-strip">
      <span class="command-active">LIVE SURFACE</span>
      <span>COMPONENT REGISTRY</span>
      <span>VERTEXHUB</span>
      <span>VSP</span>
      <span>INSPECTOR</span>
    </section>

    <section class="surface-grid">
      <article class="primary-card">
        <div class="card-heading">
          <div>
            <p class="eyebrow">CURRENT MISSION</p>
            <h2>Remove the blindfold.</h2>
          </div>
          <span class="badge">GUI LIVE DEV</span>
        </div>

        <div class="flight-line">
          <div class="node completed">
            <span>01</span>
            <strong>EDIT</strong>
            <small>MONACO</small>
          </div>
          <i />
          <div class="node active">
            <span>02</span>
            <strong>SAVE</strong>
            <small>CTRL + S</small>
          </div>
          <i />
          <div class="node">
            <span>03</span>
            <strong>HMR</strong>
            <small>VITE</small>
          </div>
          <i />
          <div class="node">
            <span>04</span>
            <strong>SEE</strong>
            <small>PREVIEW</small>
          </div>
        </div>

        <div class="telemetry">
          <div>
            <span>VERTEX BLUE</span>
            <strong>#168CFF</strong>
          </div>
          <div>
            <span>BRIGHT BLUE</span>
            <strong>#3AB8FF</strong>
          </div>
          <div>
            <span>BACKGROUND</span>
            <strong>#070B10</strong>
          </div>
          <div>
            <span>STATUS</span>
            <strong class="green">GREEN</strong>
          </div>
        </div>
      </article>

      <article class="side-card">
        <p class="eyebrow">DOCK TELEMETRY</p>
        <h3>Development Vision</h3>

        <div class="metric">
          <span>Source visibility</span>
          <strong>ONLINE</strong>
        </div>
        <div class="metric">
          <span>GUI visibility</span>
          <strong>ONLINE</strong>
        </div>
        <div class="metric">
          <span>Hot reload</span>
          <strong>READY</strong>
        </div>
        <div class="metric">
          <span>Arbitrary eval</span>
          <strong class="red">DENIED</strong>
        </div>

        <div class="signal">
          <i />
          <span>VERTEX DEVELOPMENT NETWORK</span>
        </div>
      </article>

      <article class="lower-card">
        <div>
          <p class="eyebrow">VISUAL DOCTRINE</p>
          <h3>FME-derived. Vertex-native.</h3>
        </div>

        <div class="palette">
          <span style="--swatch:#070b10">DEEP</span>
          <span style="--swatch:#0c121a">PANEL</span>
          <span style="--swatch:#111923">RAISED</span>
          <span style="--swatch:#168cff">BLUE</span>
          <span style="--swatch:#3ab8ff">BRIGHT</span>
          <span style="--swatch:#55d69e">GREEN</span>
        </div>
      </article>
    </section>
  </main>
</template>

<style scoped>
.surface {
  --bg-deep: #070b10;
  --bg-panel: #0c121a;
  --bg-panel-raised: #111923;
  --bg-hover: #14202c;
  --line: #1c2935;
  --line-bright: #26394b;
  --text: #cbd5df;
  --muted: #718195;
  --faint: #455364;
  --blue: #168cff;
  --blue-bright: #3ab8ff;
  --green: #55d69e;
  --amber: #f1b85b;
  --red: #ff6f7c;

  min-height: 100%;
  padding: 24px;
  background:
    radial-gradient(circle at 65% -20%, rgba(20, 113, 180, .13), transparent 42%),
    linear-gradient(rgba(255,255,255,.012) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,.012) 1px, transparent 1px),
    var(--bg-deep);
  background-size: auto, 34px 34px, 34px 34px, auto;
  color: var(--text);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.surface-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: 78px;
  padding: 0 18px;
  border: 1px solid var(--line-bright);
  background:
    linear-gradient(90deg, rgba(25, 135, 224, .08), transparent 28%),
    linear-gradient(180deg, #111923, #0b1118);
  box-shadow: 0 8px 26px rgba(0,0,0,.26);
}

.brand {
  display: flex;
  align-items: center;
  gap: 14px;
}

.vertex-mark {
  display: grid;
  width: 44px;
  height: 44px;
  place-items: center;
  border: 1px solid #24527a;
  transform: rotate(45deg);
  background: #0c2132;
  box-shadow: 0 0 18px rgba(22,140,255,.17);
}

.vertex-mark span {
  transform: rotate(-45deg);
  color: var(--blue-bright);
  font-size: 16px;
  font-weight: 800;
}

.eyebrow {
  margin: 0;
  color: #506275;
  font: 750 8px/1 ui-monospace, "Cascadia Code", Consolas, monospace;
  letter-spacing: .14em;
}

h1, h2, h3, p {
  margin-top: 0;
}

h1 {
  margin-bottom: 4px;
  color: #dbe7f1;
  font-size: 22px;
  font-weight: 650;
  letter-spacing: -.025em;
}

.subtitle {
  margin-bottom: 0;
  color: var(--muted);
  font-size: 10px;
}

.status-cluster {
  display: flex;
  gap: 8px;
}

.status-cluster article {
  min-width: 86px;
  padding: 9px 10px;
  border-left: 1px solid var(--line);
}

.status-cluster span,
.status-cluster strong {
  display: block;
}

.status-cluster span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.status-cluster strong {
  margin-top: 6px;
  color: var(--green);
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.command-strip {
  display: flex;
  height: 36px;
  align-items: center;
  margin-top: 8px;
  padding: 0 14px;
  gap: 20px;
  border: 1px solid var(--line);
  background: rgba(8, 13, 19, .94);
  color: var(--faint);
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.command-active {
  position: relative;
  color: #65c5ff;
}

.command-active::after {
  position: absolute;
  right: 0;
  bottom: -12px;
  left: 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--blue), transparent);
  box-shadow: 0 -2px 8px rgba(22,140,255,.75);
  content: "";
}

.surface-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) minmax(240px, .6fr);
  gap: 12px;
  margin-top: 12px;
}

.primary-card,
.side-card,
.lower-card {
  border: 1px solid var(--line);
  border-radius: 6px;
  background:
    linear-gradient(155deg, rgba(17,25,35,.95), rgba(8,13,19,.97));
  box-shadow: inset 0 1px 0 rgba(255,255,255,.018);
}

.primary-card {
  padding: 18px;
}

.card-heading {
  display: flex;
  justify-content: space-between;
  align-items: start;
}

.card-heading h2 {
  margin: 5px 0 0;
  color: #dbe7f1;
  font-size: 20px;
  font-weight: 650;
}

.badge {
  padding: 5px 7px;
  border: 1px solid #28516c;
  border-radius: 4px;
  background: #0a1a25;
  color: #6fc9fb;
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.flight-line {
  display: grid;
  grid-template-columns: auto 1fr auto 1fr auto 1fr auto;
  align-items: center;
  margin: 28px 0;
}

.flight-line > i {
  height: 1px;
  background: linear-gradient(90deg, var(--blue), var(--line-bright));
}

.node {
  display: grid;
  width: 66px;
  height: 66px;
  place-items: center;
  align-content: center;
  border: 1px solid var(--line-bright);
  border-radius: 50%;
  background: #09121a;
  text-align: center;
}

.node span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.node strong {
  margin-top: 5px;
  color: #9eb0c0;
  font-size: 9px;
}

.node small {
  margin-top: 3px;
  color: var(--faint);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.node.completed,
.node.active {
  border-color: #24658f;
}

.node.completed strong,
.node.active strong {
  color: var(--blue-bright);
}

.node.active {
  box-shadow:
    0 0 0 4px rgba(22,140,255,.05),
    0 0 18px rgba(22,140,255,.14);
}

.telemetry {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  border-top: 1px solid var(--line);
}

.telemetry > div {
  padding: 13px 10px 0;
  border-right: 1px solid var(--line);
}

.telemetry > div:last-child {
  border-right: 0;
}

.telemetry span,
.telemetry strong {
  display: block;
}

.telemetry span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.telemetry strong {
  margin-top: 6px;
  color: #9bacc0;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.green {
  color: var(--green) !important;
}

.side-card {
  padding: 18px;
}

.side-card h3 {
  margin: 6px 0 18px;
  color: #dbe7f1;
  font-size: 14px;
  font-weight: 650;
}

.metric {
  display: flex;
  justify-content: space-between;
  padding: 10px 0;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: 9px;
}

.metric strong {
  color: var(--green);
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.metric strong.red {
  color: var(--red);
}

.signal {
  display: flex;
  align-items: center;
  margin-top: 18px;
  padding-top: 14px;
  gap: 8px;
  border-top: 1px solid var(--line);
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.signal i {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 7px rgba(85,214,158,.6);
}

.lower-card {
  grid-column: 1 / -1;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 18px;
}

.lower-card h3 {
  margin: 5px 0 0;
  color: #b8c8d8;
  font-size: 12px;
}

.palette {
  display: flex;
  gap: 6px;
}

.palette span {
  position: relative;
  min-width: 60px;
  padding: 20px 8px 7px;
  border: 1px solid var(--line);
  background: #091018;
  color: var(--muted);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
  text-align: center;
}

.palette span::before {
  position: absolute;
  top: 0;
  right: 0;
  left: 0;
  height: 14px;
  background: var(--swatch);
  content: "";
}

@media (max-width: 900px) {
  .surface-grid {
    grid-template-columns: 1fr;
  }

  .side-card,
  .lower-card {
    grid-column: 1;
  }

  .status-cluster {
    display: none;
  }

  .telemetry {
    grid-template-columns: 1fr 1fr;
  }
}
</style>
'@
  WriteUtf8 $previewSurface $surface

  Write-Host 'Trusted Preview Registry     : ONLINE' -ForegroundColor Green
  Write-Host 'Vertex System Preview        : CREATED' -ForegroundColor Green

  Write-Host "`n[3/10] BUILD RESIZABLE GUI LIVE PREVIEW DOCK" -ForegroundColor Yellow

  $dock=@'
<script setup lang="ts">
import {
  computed,
  onErrorCaptured,
  onMounted,
  onUnmounted,
  ref,
  watch,
} from 'vue'
import {
  vertexPreviewTargets,
  type VertexPreviewTarget,
} from './previewRegistry'

const STORAGE_OPEN = 'vertex.live-preview.open'
const STORAGE_TARGET = 'vertex.live-preview.target'
const STORAGE_WIDTH = 'vertex.live-preview.width'
const STORAGE_VIEWPORT = 'vertex.live-preview.viewport'

const open = ref(true)
const selectedId = ref(vertexPreviewTargets[0]?.id ?? '')
const width = ref(720)
const viewport = ref<'FIT' | '1440' | '1024' | '768'>('FIT')
const reloadKey = ref(0)
const error = ref('')
const resizing = ref(false)

const selected = computed<VertexPreviewTarget | undefined>(
  () => vertexPreviewTargets.find((target) => target.id === selectedId.value),
)

const frameWidth = computed(() => {
  if (viewport.value === 'FIT') return '100%'
  return `${Number(viewport.value)}px`
})

function toggle() {
  open.value = !open.value
}

function reload() {
  error.value = ''
  reloadKey.value += 1
}

function beginResize(event: MouseEvent) {
  event.preventDefault()
  resizing.value = true

  const onMove = (moveEvent: MouseEvent) => {
    const next = window.innerWidth - moveEvent.clientX
    width.value = Math.max(420, Math.min(window.innerWidth * .78, next))
  }

  const onUp = () => {
    resizing.value = false
    window.removeEventListener('mousemove', onMove)
    window.removeEventListener('mouseup', onUp)
  }

  window.addEventListener('mousemove', onMove)
  window.addEventListener('mouseup', onUp)
}

function keyHandler(event: KeyboardEvent) {
  if (event.key === 'F10') {
    event.preventDefault()
    toggle()
  }
}

onErrorCaptured((reason) => {
  error.value = String(reason)
  return false
})

watch(open, (value) => {
  window.localStorage.setItem(STORAGE_OPEN, value ? '1' : '0')
})

watch(selectedId, (value) => {
  window.localStorage.setItem(STORAGE_TARGET, value)
  reload()
})

watch(width, (value) => {
  window.localStorage.setItem(STORAGE_WIDTH, String(Math.round(value)))
})

watch(viewport, (value) => {
  window.localStorage.setItem(STORAGE_VIEWPORT, value)
})

onMounted(() => {
  const savedOpen = window.localStorage.getItem(STORAGE_OPEN)
  const savedTarget = window.localStorage.getItem(STORAGE_TARGET)
  const savedWidth = Number(window.localStorage.getItem(STORAGE_WIDTH))
  const savedViewport = window.localStorage.getItem(STORAGE_VIEWPORT)

  if (savedOpen !== null) open.value = savedOpen === '1'

  if (
    savedTarget
    && vertexPreviewTargets.some((target) => target.id === savedTarget)
  ) {
    selectedId.value = savedTarget
  }

  if (Number.isFinite(savedWidth) && savedWidth >= 420) {
    width.value = Math.min(window.innerWidth * .78, savedWidth)
  }

  if (['FIT', '1440', '1024', '768'].includes(savedViewport ?? '')) {
    viewport.value = savedViewport as typeof viewport.value
  }

  window.addEventListener('keydown', keyHandler)
})

onUnmounted(() => {
  window.removeEventListener('keydown', keyHandler)
})
</script>

<template>
  <Teleport to="body">
    <button
      v-if="!open"
      class="preview-launcher"
      title="GUI Live Preview — F10"
      @click="open = true"
    >
      <span class="eye">◉</span>
      <span>
        <strong>LIVE PREVIEW</strong>
        <small>F10 · GUI VISION</small>
      </span>
      <i />
    </button>

    <Transition name="preview-slide">
      <aside
        v-if="open"
        class="preview-dock"
        :style="{ width: `${width}px` }"
      >
        <button
          class="resize-handle"
          title="Resize preview"
          :class="{ active: resizing }"
          @mousedown="beginResize"
        />

        <header class="preview-header">
          <div class="preview-brand">
            <div class="preview-mark">
              <span>V</span>
            </div>

            <div>
              <p>VERTEX // GUI LIVE DEVELOPMENT</p>
              <strong>Visual Preview</strong>
            </div>
          </div>

          <div class="preview-status">
            <span>
              <i />
              HMR LINKED
            </span>
            <span>STATIC TRUST</span>
          </div>

          <button
            class="close-button"
            title="Close — F10"
            @click="open = false"
          >
            ×
          </button>
        </header>

        <section class="preview-toolbar">
          <label class="target-control">
            <span>TARGET</span>
            <select v-model="selectedId">
              <optgroup
                v-for="group in ['SYSTEM', 'VERTEXHUB']"
                :key="group"
                :label="group"
              >
                <option
                  v-for="target in vertexPreviewTargets.filter(
                    (item) => item.group === group
                  )"
                  :key="target.id"
                  :value="target.id"
                >
                  {{ target.label }}
                </option>
              </optgroup>
            </select>
          </label>

          <div class="viewport-control">
            <span>VIEWPORT</span>
            <button
              v-for="preset in (['FIT', '1440', '1024', '768'] as const)"
              :key="preset"
              :class="{ active: viewport === preset }"
              @click="viewport = preset"
            >
              {{ preset }}
            </button>
          </div>

          <button
            class="reload-button"
            title="Reload Preview"
            @click="reload"
          >
            ↻
            <span>RELOAD</span>
          </button>
        </section>

        <section class="target-strip">
          <div>
            <span>PREVIEW TARGET</span>
            <strong>{{ selected?.label ?? 'NONE' }}</strong>
          </div>

          <code>{{ selected?.source ?? 'NO SOURCE' }}</code>

          <div class="vision-status">
            <span class="vision-dot" />
            VISION ONLINE
          </div>
        </section>

        <section class="canvas-shell">
          <div class="canvas-scroll">
            <div
              class="preview-frame"
              :style="{ width: frameWidth }"
            >
              <div class="frame-ruler">
                <span>0</span>
                <span>GUI LIVE SURFACE</span>
                <span>{{ viewport === 'FIT' ? 'FIT' : `${viewport}px` }}</span>
              </div>

              <div class="frame-content">
                <component
                  :is="selected.component"
                  v-if="selected"
                  :key="`${selected.id}:${reloadKey}`"
                />

                <div v-else class="empty-preview">
                  NO PREVIEW TARGET
                </div>
              </div>
            </div>
          </div>
        </section>

        <footer class="preview-footer">
          <div>
            <span class="footer-led" />
            <strong>GUI VISION ONLINE</strong>
          </div>

          <span>EDIT → SAVE → HMR → SEE</span>

          <span>F10 TOGGLE</span>
        </footer>

        <section
          v-if="error"
          class="preview-error"
        >
          <strong>PREVIEW RED</strong>
          <pre>{{ error }}</pre>
        </section>
      </aside>
    </Transition>
  </Teleport>
</template>

<style scoped>
.preview-launcher,
.preview-dock {
  --bg-deep: #070b10;
  --bg-panel: #0c121a;
  --bg-panel-raised: #111923;
  --bg-hover: #14202c;
  --line: #1c2935;
  --line-bright: #26394b;
  --text: #cbd5df;
  --muted: #718195;
  --faint: #455364;
  --blue: #168cff;
  --blue-bright: #3ab8ff;
  --green: #55d69e;
  --amber: #f1b85b;
  --red: #ff6f7c;
}

.preview-launcher {
  position: fixed;
  z-index: 9400;
  right: 12px;
  bottom: 36px;
  display: flex;
  align-items: center;
  gap: 9px;
  height: 42px;
  padding: 0 12px 0 10px;
  border: 1px solid #23415a;
  border-radius: 7px;
  background:
    linear-gradient(180deg, #111923, #0b1118);
  box-shadow:
    0 12px 32px rgba(0,0,0,.38),
    0 0 16px rgba(22,140,255,.08);
  color: var(--text);
  cursor: pointer;
}

.preview-launcher:hover {
  border-color: #2f82b6;
  box-shadow:
    0 12px 32px rgba(0,0,0,.38),
    0 0 22px rgba(22,140,255,.16);
}

.preview-launcher .eye {
  color: var(--blue-bright);
  font-size: 17px;
}

.preview-launcher strong,
.preview-launcher small {
  display: block;
  text-align: left;
}

.preview-launcher strong {
  color: #dbe7f1;
  font-size: 9px;
  letter-spacing: .08em;
}

.preview-launcher small {
  margin-top: 3px;
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.preview-launcher i {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 7px rgba(85,214,158,.65);
}

.preview-dock {
  position: fixed;
  z-index: 9300;
  top: 0;
  right: 0;
  bottom: 0;
  display: grid;
  grid-template-rows: 62px 48px 38px minmax(0,1fr) 28px;
  min-width: 420px;
  max-width: 78vw;
  border-left: 1px solid var(--line-bright);
  background:
    radial-gradient(circle at 60% -20%, rgba(20,113,180,.11), transparent 34%),
    var(--bg-deep);
  box-shadow:
    -18px 0 48px rgba(0,0,0,.42),
    -1px 0 0 rgba(22,140,255,.08);
  color: var(--text);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.resize-handle {
  position: absolute;
  z-index: 4;
  top: 0;
  bottom: 0;
  left: -4px;
  width: 8px;
  padding: 0;
  border: 0;
  background: transparent;
  cursor: ew-resize;
}

.resize-handle::after {
  position: absolute;
  top: 0;
  bottom: 0;
  left: 3px;
  width: 2px;
  background: transparent;
  content: "";
  transition: background .15s, box-shadow .15s;
}

.resize-handle:hover::after,
.resize-handle.active::after {
  background: var(--blue);
  box-shadow: 0 0 9px rgba(22,140,255,.75);
}

.preview-header {
  display: flex;
  align-items: center;
  padding: 0 12px 0 14px;
  border-bottom: 1px solid var(--line-bright);
  background:
    linear-gradient(90deg, rgba(25,135,224,.08), transparent 28%),
    linear-gradient(180deg, #111923, #0b1118);
}

.preview-header::after {
  position: absolute;
  top: 61px;
  right: 0;
  left: 0;
  height: 1px;
  background:
    linear-gradient(90deg, transparent, rgba(33,150,243,.65), transparent 70%);
  content: "";
}

.preview-brand {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.preview-mark {
  display: grid;
  width: 32px;
  height: 32px;
  flex: none;
  place-items: center;
  border: 1px solid #24658f;
  transform: rotate(45deg);
  background: #0e3047;
  box-shadow: 0 0 12px rgba(22,140,255,.12);
}

.preview-mark span {
  transform: rotate(-45deg);
  color: var(--blue-bright);
  font-size: 12px;
  font-weight: 800;
}

.preview-brand p,
.preview-brand strong {
  display: block;
}

.preview-brand p {
  margin: 0 0 4px;
  color: #506275;
  font: 700 7px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .12em;
}

.preview-brand strong {
  color: #dbe7f1;
  font-size: 13px;
  font-weight: 650;
}

.preview-status {
  display: flex;
  margin-left: auto;
  gap: 8px;
}

.preview-status span {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 5px 7px;
  border: 1px solid var(--line);
  border-radius: 4px;
  color: var(--muted);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.preview-status i {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 6px rgba(85,214,158,.65);
}

.close-button {
  display: grid;
  width: 30px;
  height: 30px;
  margin-left: 8px;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: 5px;
  background: #0a1118;
  color: var(--muted);
  font-size: 18px;
  cursor: pointer;
}

.close-button:hover {
  border-color: #2f82b6;
  color: #dbe7f1;
}

.preview-toolbar {
  display: flex;
  align-items: center;
  padding: 0 10px;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  background: var(--bg-panel);
}

.target-control {
  display: flex;
  min-width: 0;
  flex: 1;
  align-items: center;
  gap: 7px;
}

.target-control > span,
.viewport-control > span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.target-control select {
  min-width: 0;
  height: 28px;
  flex: 1;
  border: 1px solid var(--line-bright);
  border-radius: 4px;
  outline: 0;
  background: #09121a;
  color: #b8c8d8;
  font-size: 9px;
}

.target-control select:focus {
  border-color: var(--blue);
}

.viewport-control {
  display: flex;
  align-items: center;
  gap: 4px;
}

.viewport-control button,
.reload-button {
  height: 28px;
  border: 1px solid var(--line);
  border-radius: 4px;
  background: #091018;
  color: var(--muted);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.viewport-control button {
  min-width: 36px;
  padding: 0 6px;
}

.viewport-control button:hover,
.viewport-control button.active,
.reload-button:hover {
  border-color: #28516c;
  color: #65c5ff;
  background: #102033;
}

.viewport-control button.active {
  box-shadow: inset 0 -2px 0 var(--blue);
}

.reload-button {
  display: flex;
  align-items: center;
  padding: 0 8px;
  gap: 5px;
}

.target-strip {
  display: grid;
  grid-template-columns: auto minmax(0,1fr) auto;
  align-items: center;
  padding: 0 11px;
  gap: 10px;
  border-bottom: 1px solid var(--line);
  background: #080d13;
}

.target-strip span,
.target-strip strong {
  display: block;
}

.target-strip span {
  color: var(--faint);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.target-strip strong {
  margin-top: 3px;
  color: #9eb0c0;
  font-size: 8px;
}

.target-strip code {
  min-width: 0;
  overflow: hidden;
  color: #506275;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.vision-status {
  display: flex;
  align-items: center;
  gap: 5px;
  color: var(--green);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.vision-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 7px rgba(85,214,158,.65);
}

.canvas-shell {
  min-height: 0;
  padding: 10px;
  overflow: hidden;
  background:
    linear-gradient(rgba(255,255,255,.012) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,.012) 1px, transparent 1px),
    #060a0f;
  background-size: 24px 24px;
}

.canvas-scroll {
  width: 100%;
  height: 100%;
  overflow: auto;
}

.canvas-scroll::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

.canvas-scroll::-webkit-scrollbar-track {
  background: #090e14;
}

.canvas-scroll::-webkit-scrollbar-thumb {
  border: 2px solid #090e14;
  border-radius: 8px;
  background: #263747;
}

.preview-frame {
  min-width: 100%;
  min-height: 100%;
  border: 1px solid var(--line-bright);
  background: var(--bg-deep);
  box-shadow:
    0 10px 30px rgba(0,0,0,.3),
    0 0 0 1px rgba(255,255,255,.012) inset;
}

.frame-ruler {
  display: flex;
  justify-content: space-between;
  align-items: center;
  height: 24px;
  padding: 0 8px;
  border-bottom: 1px solid var(--line);
  background: #091018;
  color: var(--faint);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.frame-content {
  min-height: calc(100% - 24px);
  overflow: auto;
  background: var(--bg-deep);
}

.empty-preview {
  display: grid;
  min-height: 400px;
  place-items: center;
  color: var(--faint);
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.preview-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 10px;
  border-top: 1px solid var(--line-bright);
  background: #080d13;
  color: var(--faint);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.preview-footer > div {
  display: flex;
  align-items: center;
  gap: 6px;
}

.preview-footer strong {
  color: #6e8295;
}

.footer-led {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 6px rgba(85,214,158,.65);
}

.preview-error {
  position: absolute;
  right: 12px;
  bottom: 38px;
  left: 12px;
  max-height: 150px;
  overflow: auto;
  padding: 10px;
  border: 1px solid rgba(255,111,124,.34);
  border-radius: 5px;
  background: rgba(51,14,20,.94);
  box-shadow: 0 12px 24px rgba(0,0,0,.32);
}

.preview-error strong {
  color: var(--red);
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.preview-error pre {
  margin: 7px 0 0;
  color: #d89da3;
  white-space: pre-wrap;
  font: 7px/1.45 ui-monospace, Consolas, monospace;
}

.preview-slide-enter-active,
.preview-slide-leave-active {
  transition: transform .18s ease, opacity .18s ease;
}

.preview-slide-enter-from,
.preview-slide-leave-to {
  transform: translateX(20px);
  opacity: 0;
}

@media (max-width: 760px) {
  .preview-dock {
    width: 100vw !important;
    max-width: 100vw;
    min-width: 0;
  }

  .preview-status,
  .viewport-control > span,
  .reload-button span {
    display: none;
  }
}
</style>
'@
  WriteUtf8 $previewDock $dock

  Write-Host 'GUI Live Preview Dock        : CREATED' -ForegroundColor Green
  Write-Host 'F10 Toggle                   : ONLINE' -ForegroundColor Green
  Write-Host 'Resizable Preview            : ONLINE' -ForegroundColor Green

  Write-Host "`n[4/10] DOCK PREVIEW INTO VERTEX EDITOR" -ForegroundColor Yellow

  $editorText=[IO.File]::ReadAllText($editor)

  $hubImport="import VertexHubDock from '../vertex-hub/VertexHubDock.vue'"
  if(-not $editorText.Contains($hubImport)){
    throw 'VertexHubDock import anchor missing; refusing ambiguous editor patch.'
  }

  if($editorText.Contains("import VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'")){
    throw 'VertexLivePreview import already present.'
  }

  $editorText=$editorText.Replace(
    $hubImport,
    $hubImport+"`r`nimport VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'"
  )

  if(-not $editorText.Contains('<VertexHubDock />')){
    throw 'VertexHubDock template anchor missing.'
  }

  $editorText=$editorText.Replace(
    '<VertexHubDock />',
    "<VertexHubDock />`r`n    <VertexLivePreview />"
  )

  WriteUtf8 $editor $editorText

  Write-Host 'Vertex Editor -> Live Preview: DOCKED' -ForegroundColor Green

  Write-Host "`n[5/10] CREATE GUI DEV LAUNCHER" -ForegroundColor Yellow

  $launcherText=@'
& {
$ErrorActionPreference='Stop'

$ui='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\apps\vsa-shell'

if(-not(Test-Path -LiteralPath $ui)){
  throw "VSA UI root missing: $ui"
}

$pnpm=Get-Command pnpm -ErrorAction SilentlyContinue
if(-not $pnpm){
  throw 'pnpm is not available.'
}

Write-Host @"
============================================================
 VERTEX — GUI LIVE DEVELOPMENT
============================================================
 Editor + GUI Preview                  ONLINE TARGET
 F10                                   TOGGLE PREVIEW
 Save                                  VITE HMR
 Preview Registry                      STATIC / TRUSTED
 VertexHub Components                  PREVIEWABLE
 Arbitrary Runtime Code                DENIED
------------------------------------------------------------
 Close this process to stop Dev Mode.
============================================================
"@ -ForegroundColor Cyan

Push-Location $ui
try{
  & $pnpm.Source exec tauri dev
  if($LASTEXITCODE -ne 0){
    throw "Tauri dev exited RED ($LASTEXITCODE)"
  }
}finally{
  Pop-Location
}
}
'@
  WriteUtf8 $launcher $launcherText

  Write-Host "Launcher: $launcher" -ForegroundColor Green

  Write-Host "`n[6/10] FRONTEND TYPECHECK / BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[preview] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }

    RunChecked '[preview] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[7/10] STATIC GUI-VISION SAFETY AUDIT" -ForegroundColor Yellow

  $dockNow=[IO.File]::ReadAllText($previewDock)
  $registryNow=[IO.File]::ReadAllText($previewRegistry)
  $editorNow=[IO.File]::ReadAllText($editor)
  $launcherNow=[IO.File]::ReadAllText($launcher)

  $audits=@(
    [pscustomobject]@{Name='F10 preview toggle';Pass=$dockNow.Contains("event.key === 'F10'")},
    [pscustomobject]@{Name='Resizable right dock';Pass=$dockNow.Contains('beginResize')},
    [pscustomobject]@{Name='FME deep token';Pass=$dockNow.Contains('--bg-deep: #070b10')},
    [pscustomobject]@{Name='FME Vertex Blue';Pass=$dockNow.Contains('--blue: #168cff')},
    [pscustomobject]@{Name='FME Bright Blue';Pass=$dockNow.Contains('--blue-bright: #3ab8ff')},
    [pscustomobject]@{Name='Trusted static registry';Pass=$registryNow.Contains('vertexHubUiPackages.map')},
    [pscustomobject]@{Name='No eval';Pass=(-not $dockNow.Contains('eval(') -and -not $registryNow.Contains('eval('))},
    [pscustomobject]@{Name='No remote import';Pass=(-not $dockNow.Contains('http://') -and -not $dockNow.Contains('https://') -and -not $registryNow.Contains('http://') -and -not $registryNow.Contains('https://'))},
    [pscustomobject]@{Name='Editor preview import';Pass=$editorNow.Contains("import VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'")},
    [pscustomobject]@{Name='Editor preview render';Pass=$editorNow.Contains('<VertexLivePreview />')},
    [pscustomobject]@{Name='Tauri dev launcher';Pass=$launcherNow.Contains('exec tauri dev')}
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){
      throw "GUI Live Development audit RED: $($audit.Name)"
    }

    Write-Host ("  {0,-32} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[8/10] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  RunChecked '[release] Tauri cargo check' {
    & $cargo.Source check --manifest-path $tauriCargo --all-targets
  }

  Push-Location $ui
  try{
    RunChecked '[release] final frontend build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[9/10] GUI DEVELOPMENT CONTRACT" -ForegroundColor Yellow

  $package=Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
  if(-not $package.devDependencies.'@tauri-apps/cli' -and -not $package.dependencies.'@tauri-apps/cli'){
    Write-Host '  Tauri CLI package metadata          NOT_DECLARED / pnpm exec still available' -ForegroundColor Yellow
  }else{
    Write-Host '  Tauri CLI package metadata          PRESENT' -ForegroundColor Green
  }

  Write-Host '  Editor                              ONLINE' -ForegroundColor Green
  Write-Host '  GUI Live Preview                    ONLINE' -ForegroundColor Green
  Write-Host '  Hub Component Preview               ONLINE' -ForegroundColor Green
  Write-Host '  Vite HMR path                       READY VIA TAURI DEV' -ForegroundColor Green
  Write-Host '  F10                                 TOGGLE' -ForegroundColor Green
  Write-Host '  Arbitrary GUI eval                  DENIED' -ForegroundColor Green

  Write-Host "`n[10/10] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.gui-live-development-mode.v1'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA GUI LIVE DEVELOPMENT MODE'
    editor=[ordered]@{
      source_editor='MONACO'
      gui_preview='ONLINE'
      preview_toggle='F10'
      preview_dock='RIGHT_RESIZABLE'
      target_selector='ONLINE'
      viewport_presets=@('FIT','1440','1024','768')
      manual_reload='ONLINE'
    }
    preview=[ordered]@{
      system_surface='ONLINE'
      vertexhub_catalog_targets='ONLINE'
      static_registry='ENFORCED'
      arbitrary_eval='DENIED'
      remote_import='DENIED'
      hmr='VITE_TAURI_DEV'
    }
    design=[ordered]@{
      source='Vertex FM Engine'
      bg_deep='#070b10'
      panel='#0c121a'
      raised='#111923'
      vertex_blue='#168cff'
      bright_blue='#3ab8ff'
      success='#55d69e'
      warning='#f1b85b'
      error='#ff6f7c'
    }
    launcher=$launcher
    validation=[ordered]@{
      frontend_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    next_target='GUI SOURCE-TO-PREVIEW SYNC / COMPONENT SELECTION'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX — GUI LIVE DEVELOPMENT MODE GREEN
============================================================
 Monaco Editor                          ONLINE
 GUI Live Preview                       ONLINE
 Right Preview Dock                     RESIZABLE
 F10 Toggle                             ONLINE
 Target Selector                        ONLINE
 VertexHub Preview Targets              ONLINE
 System Preview Surface                 ONLINE
 Vite / Tauri HMR Path                  READY
 FME Vertex Design                      LOCKED
 Vertex Blue #168cff                    LOCKED
 Bright Blue #3ab8ff                    LOCKED
 Arbitrary Eval                         DENIED
 Remote Runtime Import                  DENIED
 Frontend Typecheck                     GREEN
 Frontend Build                         GREEN
 Tauri Check                            GREEN
 Workspace Release Gate                 GREEN
------------------------------------------------------------
 DEV LAUNCHER:
 $launcher
------------------------------------------------------------
 NEXT TARGET:
 GUI SOURCE-TO-PREVIEW SYNC / COMPONENT SELECTION
============================================================
 THE BLINDFOLD IS OFF.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' GUI LIVE DEVELOPMENT MODE RED — DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  foreach($path in @(
    $editor,$previewRegistry,$previewSurface,$previewDock,$launcher
  )){
    if(Test-Path -LiteralPath $path){
      Copy-Item -LiteralPath $path -Destination (Join-Path $failed ([IO.Path]::GetFileName($path))) -Force -ErrorAction SilentlyContinue
    }
  }

  $editorBackup=Join-Path $backup 'VertexEditorDock.vue'
  if(Test-Path -LiteralPath $editorBackup){
    Copy-Item -LiteralPath $editorBackup -Destination $editor -Force
  }

  if(Test-Path -LiteralPath $previewRoot){
    Remove-Item -LiteralPath $previewRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  $launcherBackup=Join-Path $backup 'START_VERTEX_GUI_DEV.ps1'
  if(Test-Path -LiteralPath $launcherBackup){
    Copy-Item -LiteralPath $launcherBackup -Destination $launcher -Force
  }elseif(Test-Path -LiteralPath $launcher){
    Remove-Item -LiteralPath $launcher -Force -ErrorAction SilentlyContinue
  }

  Write-Host 'Editor rollback                    : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Preview source rollback            : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Dev launcher rollback              : COMPLETE' -ForegroundColor Yellow
  Write-Host 'VertexHub / Runtime / Mothership   : UNTOUCHED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}
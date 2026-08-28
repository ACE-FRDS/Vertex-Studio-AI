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
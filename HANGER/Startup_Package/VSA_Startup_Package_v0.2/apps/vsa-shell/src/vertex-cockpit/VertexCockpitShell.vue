<script setup lang="ts">
import { computed,onMounted,onUnmounted } from 'vue'

import './theme/vertex-aether-violet.css'

import AdaptiveGridHost from './equipment/AdaptiveGridHost.vue'
import { useAdaptiveGrid } from './equipment/useAdaptiveGrid'
import { useCockpitTelemetry } from './cockpitTelemetry'

const { telemetry } = useCockpitTelemetry()
const grid = useAdaptiveGrid()

const mode = computed(
  () => grid.snapshot.value.editMode ? 'LAYOUT EDIT' : 'CREATION',
)

function onKey(event: KeyboardEvent) {
  if (
    event.ctrlKey
    && event.shiftKey
    && event.key.toLowerCase() === 'l'
  ) {
    event.preventDefault()
    grid.toggleEditMode()
  }

  if (
    event.ctrlKey
    && event.shiftKey
    && event.key.toLowerCase() === 'r'
  ) {
    event.preventDefault()
    grid.reset()
  }
}

onMounted(() => window.addEventListener('keydown',onKey))
onUnmounted(() => window.removeEventListener('keydown',onKey))
</script>

<template>
  <div class="vertex-cockpit adaptive-v7">
    <header class="top-deck">
      <section class="brand">
        <div class="gem"><span>V</span></div>
        <div>
          <strong>VERTEX STUDIO AI</strong>
          <small>Adaptive Grid Equipment Workspace</small>
        </div>
      </section>

      <section class="status-strip">
        <div>
          <span>プロジェクト</span>
          <strong>{{ telemetry.projectLabel }}</strong>
          <small>Workspace</small>
        </div>

        <div>
          <span>VSP</span>
          <strong>{{ telemetry.checkpointId || '信号なし' }}</strong>
          <small>{{ telemetry.liveOnline ? 'Live Session' : '未接続' }}</small>
        </div>

        <div>
          <span>VXN</span>
          <strong>{{ telemetry.runtimeOnline ? 'オンライン' : 'オフライン' }}</strong>
          <small>{{ telemetry.runtimeLabel }}</small>
        </div>

        <div>
          <span>Agent</span>
          <strong>{{ telemetry.agentCount ?? '未公開' }}</strong>
          <small>実Live信号</small>
        </div>

        <div>
          <span>VertexHub</span>
          <strong>
            {{
              telemetry.hubOnline
                ? `${telemetry.hubEnabledCount}/${telemetry.hubPackageCount}`
                : '信号なし'
            }}
          </strong>
          <small>有効 / 導入</small>
        </div>
      </section>

      <section class="captain">
        <span>USER : CAPTAIN</span>
        <small>MODE : {{ mode }}</small>
        <strong>{{ telemetry.now }}</strong>
      </section>

      <button
        class="layout-toggle"
        type="button"
        :class="{ active: grid.snapshot.value.editMode }"
        @click="grid.toggleEditMode"
      >
        {{
          grid.snapshot.value.editMode
            ? '配置編集を終了'
            : '配置編集'
        }}
      </button>
    </header>

    <main class="desktop-grid-zone">
      <AdaptiveGridHost :telemetry="telemetry">
        <template #primary>
          <slot />
        </template>
      </AdaptiveGridHost>
    </main>

    <footer class="system-ribbon">
      <span>24×16 GRID</span>
      <span>Gap {{ grid.snapshot.value.gap }}px</span>
      <span>Layout {{ grid.snapshot.value.editMode ? 'EDIT' : 'LOCKED' }}</span>
      <span>Editor PRIMARY / NO FLOAT</span>
      <span>Drone CONTRACT READY / RUNTIME未実装</span>
      <strong>Ctrl+Shift+L 配置編集</strong>
    </footer>
  </div>
</template>

<style scoped>
.vertex-cockpit {
  position: fixed;
  inset: 0;
  display: grid;
  width: 100vw;
  height: 100vh;
  min-width: 0;
  min-height: 0;
  grid-template-rows: 92px minmax(0,1fr) 28px;
  overflow: hidden;
  background:
    radial-gradient(circle at 52% -15%,rgba(124,92,255,.17),transparent 35%),
    #070812;
  color: #d7def0;
  font-family: Inter,"Segoe UI","Yu Gothic UI",system-ui,sans-serif;
}

.top-deck {
  display: grid;
  min-width: 0;
  grid-template-columns: 290px minmax(0,1fr) 175px 94px;
  gap: 6px;
  padding: 7px;
  border-bottom: 1px solid rgba(105,82,182,.58);
  background:
    radial-gradient(circle at 38% -90%,rgba(124,92,255,.18),transparent 55%),
    linear-gradient(180deg,#111427,#080a15);
}

.brand,
.captain,
.status-strip > div {
  min-width: 0;
  border: 1px solid #303858;
  background:
    linear-gradient(155deg,rgba(17,21,41,.97),rgba(8,10,20,.99));
}

.brand {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 13px;
}

.gem {
  display: grid;
  width: 42px;
  height: 42px;
  place-items: center;
  border: 1px solid rgba(169,140,255,.62);
  transform: rotate(45deg);
  background:
    radial-gradient(circle,rgba(124,92,255,.28),#16152f 68%);
}

.gem span {
  transform: rotate(-45deg);
  color: #b89cff;
  font-size: 17px;
  font-weight: 850;
}

.brand strong,
.brand small {
  display: block;
}

.brand strong {
  color: #e5e7f2;
  font-size: 16px;
}

.brand small {
  margin-top: 5px;
  color: #727d9a;
  font-size: 9px;
}

.status-strip {
  display: grid;
  min-width: 0;
  grid-template-columns: repeat(5,minmax(135px,1fr));
  gap: 5px;
  overflow-x: auto;
}

.status-strip > div {
  padding: 10px;
}

.status-strip span,
.status-strip strong,
.status-strip small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.status-strip span {
  color: #6c7897;
  font-size: 8px;
}

.status-strip strong {
  margin-top: 6px;
  color: #c6cee1;
  font-size: 11px;
}

.status-strip small {
  margin-top: 4px;
  color: #56617d;
  font-size: 8px;
}

.captain {
  display: grid;
  align-content: center;
  justify-items: end;
  padding: 0 11px;
}

.captain span,
.captain small {
  color: #7884a0;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.captain small {
  margin-top: 4px;
}

.captain strong {
  margin-top: 7px;
  color: #e1e4ef;
  font: 500 17px/1 ui-monospace,Consolas,monospace;
}

.layout-toggle {
  border: 1px solid #3d4366;
  border-radius: 3px;
  background: #0d1020;
  color: #7e89a6;
  font-size: 9px;
  font-weight: 750;
}

.layout-toggle.active {
  border-color: #755bc9;
  background: #241e49;
  color: #cabdff;
}

.desktop-grid-zone {
  position: relative;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  background: #070812;
}

.desktop-grid-zone > :deep(*) {
  width: 100%;
  height: 100%;
}

.system-ribbon {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 18px;
  padding: 0 9px;
  overflow: hidden;
  border-top: 1px solid #2a314e;
  background: #090c18;
  color: #5e6986;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.system-ribbon span,
.system-ribbon strong {
  white-space: nowrap;
}

.system-ribbon strong {
  margin-left: auto;
  color: #7867b4;
}

@media (min-width:2200px) {
  .vertex-cockpit {
    grid-template-rows: 100px minmax(0,1fr) 30px;
  }

  .top-deck {
    grid-template-columns: 320px minmax(0,1fr) 185px 105px;
    padding: 9px;
  }
}

@media (max-width:1279px) {
  .vertex-cockpit {
    grid-template-rows: 82px minmax(0,1fr) 26px;
  }

  .top-deck {
    grid-template-columns: 210px minmax(0,1fr) 120px 78px;
    padding: 5px;
  }

  .status-strip {
    display: flex;
    overflow-x: auto;
  }

  .status-strip > div {
    min-width: 140px;
  }

  .system-ribbon span:nth-of-type(2),
  .system-ribbon span:nth-of-type(4) {
    display: none;
  }
}
</style>
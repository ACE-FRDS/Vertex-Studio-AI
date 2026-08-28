<script setup lang="ts">
import type { Component } from 'vue'

import AiActivityPanel from '../role-layout/panels/AiActivityPanel.vue'
import AiAssistantPanel from '../role-layout/panels/AiAssistantPanel.vue'
import BuildPanel from '../role-layout/panels/BuildPanel.vue'
import GitPanel from '../role-layout/panels/GitPanel.vue'
import HyperAgentChatPanel from '../role-layout/panels/HyperAgentChatPanel.vue'
import ReviewerPanel from '../role-layout/panels/ReviewerPanel.vue'
import SystemMonitorPanelJa from '../role-layout/panels/SystemMonitorPanelJa.vue'
import TerminalPanel from '../role-layout/panels/TerminalPanel.vue'
import TestPanel from '../role-layout/panels/TestPanel.vue'
import VspStatusPanelJa from '../role-layout/panels/VspStatusPanelJa.vue'
import VveExplorerPanel from '../role-layout/panels/VveExplorerPanel.vue'

import EquipmentUnitFrame from './EquipmentUnitFrame.vue'
import { equipmentRegistry } from './equipmentRegistry'
import { useAdaptiveGrid } from './useAdaptiveGrid'

defineProps<{ telemetry: any }>()

const grid = useAdaptiveGrid()

const componentMap: Record<string, Component | 'slot'> = {
  'hyperagent-chat': HyperAgentChatPanel,
  'vsa-editor': 'slot',
  'vve-explorer': VveExplorerPanel,
  'ai-activity': AiActivityPanel,
  terminal: TerminalPanel,
  build: BuildPanel,
  test: TestPanel,
  reviewer: ReviewerPanel,
  'ai-assistant': AiAssistantPanel,
  git: GitPanel,
  'system-monitor': SystemMonitorPanelJa,
  'vsp-status': VspStatusPanelJa,
}
</script>

<template>
  <div class="grid-shell">
    <div
      class="adaptive-grid-surface"
      :class="{ editing: grid.snapshot.value.editMode }"
      :style="{ '--gap': `${grid.snapshot.value.gap}px` }"
    >
      <EquipmentUnitFrame
        v-for="placement in grid.visiblePlacements.value"
        :key="placement.id"
        :equipment-id="placement.id"
      >
        <slot
          v-if="componentMap[placement.id] === 'slot'"
          name="primary"
        />

        <component
          :is="componentMap[placement.id]"
          v-else
          :telemetry="telemetry"
        />
      </EquipmentUnitFrame>
    </div>

    <aside
      v-if="grid.snapshot.value.editMode"
      class="palette"
    >
      <header>
        <strong>レイアウト編集</strong>
        <span>24 × 16 GRID</span>
      </header>

      <div class="list">
        <button
          v-for="item in equipmentRegistry"
          :key="item.id"
          type="button"
          :class="{
            active:
              grid.snapshot.value.placements.find(
                (placement) => placement.id === item.id,
              )?.visible,
          }"
          @click="
            grid.snapshot.value.placements.find(
              (placement) => placement.id === item.id,
            )?.visible
              ? grid.hide(item.id)
              : grid.show(item.id)
          "
        >
          <span>{{ item.title }}</span>
          <small>
            {{
              item.primary
                ? 'PRIMARY'
                : item.droneEligible
                  ? 'DRONE READY'
                  : item.runtimeMode.toUpperCase()
            }}
          </small>
        </button>
      </div>

      <label>
        <span>グリッド間隔</span>
        <input
          type="range"
          min="0"
          max="18"
          :value="grid.snapshot.value.gap"
          @input="
            grid.setGap(
              Number(($event.target as HTMLInputElement).value),
            )
          "
        >
      </label>

      <button
        type="button"
        class="reset"
        @click="grid.reset"
      >
        Default配置へ戻す
      </button>
    </aside>
  </div>
</template>

<style scoped>
.grid-shell {
  position: absolute;
  inset: 0;
  overflow: hidden;
  background: #070812;
}

.adaptive-grid-surface {
  position: absolute;
  inset: 0;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns: repeat(24,minmax(0,1fr));
  grid-template-rows: repeat(16,minmax(0,1fr));
  gap: var(--gap,6px);
  padding: var(--gap,6px);
  overflow: hidden;
  background:
    radial-gradient(circle at 50% -10%, rgba(124,92,255,.07), transparent 34%),
    #070812;
}

.adaptive-grid-surface.editing {
  background-image:
    linear-gradient(rgba(124,92,255,.055) 1px,transparent 1px),
    linear-gradient(90deg,rgba(124,92,255,.055) 1px,transparent 1px),
    radial-gradient(circle at 50% -10%,rgba(124,92,255,.08),transparent 34%);
  background-size:
    calc((100% - 23 * var(--gap,6px)) / 24 + var(--gap,6px))
    calc((100% - 15 * var(--gap,6px)) / 16 + var(--gap,6px)),
    calc((100% - 23 * var(--gap,6px)) / 24 + var(--gap,6px))
    calc((100% - 15 * var(--gap,6px)) / 16 + var(--gap,6px)),
    auto;
}

.palette {
  position: absolute;
  z-index: 12000;
  top: 12px;
  right: 12px;
  width: 250px;
  max-height: calc(100% - 24px);
  overflow: auto;
  border: 1px solid #4b407b;
  border-radius: 6px;
  background: rgba(10,12,25,.96);
  box-shadow: 0 20px 60px rgba(0,0,0,.48);
}

.palette header {
  padding: 11px;
  border-bottom: 1px solid #303858;
}

.palette header strong,
.palette header span {
  display: block;
}

.palette header strong {
  color: #d0d7e9;
  font-size: 12px;
}

.palette header span {
  margin-top: 4px;
  color: #665b89;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.list {
  padding: 7px;
}

.list button {
  display: flex;
  width: 100%;
  min-height: 34px;
  align-items: center;
  justify-content: space-between;
  gap: 7px;
  margin-bottom: 4px;
  padding: 0 8px;
  border: 1px solid #2e3655;
  border-radius: 3px;
  background: #0b0e1c;
  color: #7783a0;
}

.list button.active {
  border-color: #6550ae;
  background: #1b1838;
  color: #c1b5ed;
}

.list button span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 9px;
}

.list button small {
  flex: none;
  color: #5f6985;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}

.palette label {
  display: block;
  margin: 0 8px 8px;
  padding: 9px;
  border-top: 1px solid #303858;
}

.palette label span {
  display: block;
  color: #6b7694;
  font-size: 8px;
}

.palette input {
  width: 100%;
  margin-top: 7px;
}

.reset {
  width: calc(100% - 16px);
  min-height: 32px;
  margin: 0 8px 9px;
  border: 1px solid #6b52b8;
  border-radius: 3px;
  background: #241e49;
  color: #c7bbf9;
}
</style>
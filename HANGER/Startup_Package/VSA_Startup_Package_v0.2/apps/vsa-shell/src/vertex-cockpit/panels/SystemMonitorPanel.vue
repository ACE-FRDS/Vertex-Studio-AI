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
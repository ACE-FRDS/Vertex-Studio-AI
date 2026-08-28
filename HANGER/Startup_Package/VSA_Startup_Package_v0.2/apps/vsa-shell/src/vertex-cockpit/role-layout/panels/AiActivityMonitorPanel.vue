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
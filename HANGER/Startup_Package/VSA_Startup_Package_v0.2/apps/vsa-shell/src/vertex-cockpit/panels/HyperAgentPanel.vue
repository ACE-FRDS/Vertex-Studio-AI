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
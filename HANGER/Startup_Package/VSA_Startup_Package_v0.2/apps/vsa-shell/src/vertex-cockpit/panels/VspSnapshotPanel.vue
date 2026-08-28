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
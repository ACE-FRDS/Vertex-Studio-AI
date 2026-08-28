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
<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>VSP // <b :class="{ online: telemetry.liveOnline }">{{ telemetry.liveOnline ? 'LIVE' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.checkpointId || telemetry.sessionId || 'UNBOUND' }}</strong>
    <span>{{ telemetry.waveId ? `WAVE ${telemetry.waveId}` : 'CHECKPOINT STREAM' }}</span>
  </article>
</template>
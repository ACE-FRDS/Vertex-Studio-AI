<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>ARD // <b :class="{ online: telemetry.liveOnline }">{{ telemetry.liveOnline ? 'LINKED' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.agentCount === null ? 'UNBOUND' : `${telemetry.agentCount} AGENTS` }}</strong>
    <span>{{ telemetry.dispatchId ? `DISPATCH ${telemetry.dispatchId}` : 'LIVE LINEAGE' }}</span>
  </article>
</template>
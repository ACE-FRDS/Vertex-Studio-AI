<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>PROJECT BRAIN // <b :class="{ online: telemetry.runtimeOnline }">{{ telemetry.runtimeOnline ? 'REACHABLE' : 'NO SIGNAL' }}</b></p>
    <strong>{{ telemetry.runtimeOnline ? 'RUNTIME BOUND' : 'UNBOUND' }}</strong>
    <span>KNOWLEDGE / CONTINUITY EDGE</span>
  </article>
</template>
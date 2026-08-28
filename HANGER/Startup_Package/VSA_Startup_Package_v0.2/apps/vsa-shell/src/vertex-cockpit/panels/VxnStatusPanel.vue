<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell">
    <p>VXN // <b :class="{ online: telemetry.runtimeOnline }">{{ telemetry.runtimeOnline ? 'LINKED' : 'OFFLINE' }}</b></p>
    <strong>{{ telemetry.runtimeLabel }}</strong>
    <span>RUNTIME CORE SIGNAL</span>
  </article>
</template>
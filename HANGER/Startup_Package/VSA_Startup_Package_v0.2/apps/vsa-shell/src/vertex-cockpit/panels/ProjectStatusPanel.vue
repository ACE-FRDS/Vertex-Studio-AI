<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <article class="status-cell project">
    <p>PROJECT</p>
    <strong>{{ telemetry.projectLabel }}</strong>
    <span>WORKSPACE // CURRENT</span>
  </article>
</template>
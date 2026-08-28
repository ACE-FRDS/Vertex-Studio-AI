<script setup lang="ts">
import { computed } from 'vue'
import type { CockpitTelemetry } from '../cockpitTelemetry'

const props = defineProps<{
  telemetry: CockpitTelemetry
}>()

const signalCount = computed(
  () =>
    [
      props.telemetry.runtimeOnline,
      props.telemetry.hubOnline,
      props.telemetry.networkOnline,
    ].filter(Boolean).length,
)
</script>

<template>
  <article class="status-cell health">
    <p>WORKSPACE HEALTH</p>
    <strong>{{ signalCount }}/3 SIGNALS</strong>
    <span>RUNTIME / HUB / NETWORK</span>
  </article>
</template>
<script setup lang="ts">
import type { ValidationResult } from '../../types/clipboard'

defineProps<{ results: ValidationResult[] }>()

const icon = {
  success: 'check_circle',
  warning: 'warning',
  error: 'cancel',
} as const
</script>

<template>
  <div class="validation-list">
    <div v-for="result in results" :key="result.message" class="validation-row" :class="result.level">
      <span class="material-icons">{{ icon[result.level] }}</span>
      <span>{{ result.message }}</span>
    </div>
  </div>
</template>

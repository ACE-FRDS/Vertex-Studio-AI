<script setup lang="ts">
import { computed } from 'vue'
import { useClipboardStore } from '../../stores/clipboard'
import { useLocaleStore } from '../../stores/locale'

const clipboard = useClipboardStore()
const locale = useLocaleStore()
const countLabel = computed(() => `${clipboard.items.length} ${locale.t('items')}`)
</script>

<template>
  <footer class="status-bar">
    <div class="status-primary"><span class="status-check">✓</span> {{ locale.t('ready') }}</div>
    <div class="status-separator" />
    <div><span class="pulse-dot" /> {{ locale.t('autoSave') }}</div>
    <div class="status-separator" />
    <div class="status-muted">{{ locale.t('history') }} <strong>{{ countLabel }}</strong></div>
    <div class="status-spacer" />
    <div class="status-muted"><span class="db-icon">◉</span> vertex-fm-engine.db</div>
    <div class="status-separator" />
    <div class="status-muted">UTF-8</div>
    <div class="status-separator" />
    <div class="status-muted">Ln 2, Col 1</div>
    <div class="status-separator" />
    <div class="vertex-version">VERTEX 0.1.0</div>
  </footer>
</template>

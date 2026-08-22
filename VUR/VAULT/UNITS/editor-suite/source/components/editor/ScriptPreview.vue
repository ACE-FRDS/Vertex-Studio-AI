<script setup lang="ts">
import { onMounted } from 'vue'
import { useEditorStore } from '../../stores/editor'

const editor = useEditorStore()
onMounted(() => void editor.buildPreview())
</script>

<template>
  <div class="script-preview">
    <div class="preview-title-block">
      <span class="script-icon material-icons">terminal</span>
      <div><span>SCRIPT</span><h3>{{ editor.preview.name }}</h3></div>
      <q-badge outline color="primary" :label="`${editor.preview.steps.length} STEPS`" />
    </div>
    <div class="step-list">
      <div v-for="step in editor.preview.steps" :key="step.index" class="script-step" :class="{ disabled: !step.enabled }">
        <span class="step-number">{{ step.index }}</span>
        <span class="step-rail" />
        <strong>{{ step.name }}</strong>
      </div>
      <div v-if="editor.preview.steps.length === 0" class="empty-state">プレビューできるスクリプトステップがありません。</div>
    </div>
  </div>
</template>

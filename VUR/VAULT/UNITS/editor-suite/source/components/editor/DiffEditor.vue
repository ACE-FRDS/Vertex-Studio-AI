<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import * as monaco from 'monaco-editor'
import EditorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'

const props = defineProps<{ original: string; modified: string }>()
const container = ref<HTMLElement | null>(null)
let editor: monaco.editor.IStandaloneDiffEditor | undefined
let originalModel: monaco.editor.ITextModel | undefined
let modifiedModel: monaco.editor.ITextModel | undefined

const monacoGlobal = self as typeof globalThis & {
  MonacoEnvironment?: { getWorker: () => Worker }
}
monacoGlobal.MonacoEnvironment = { getWorker: () => new EditorWorker() }

onMounted(() => {
  if (!container.value) return
  originalModel = monaco.editor.createModel(props.original, 'xml')
  modifiedModel = monaco.editor.createModel(props.modified, 'xml')
  editor = monaco.editor.createDiffEditor(container.value, {
    theme: 'vertex-dark',
    automaticLayout: true,
    fontSize: 12,
    renderSideBySide: true,
    scrollBeyondLastLine: false,
    originalEditable: false,
  })
  editor.setModel({ original: originalModel, modified: modifiedModel })
})

onBeforeUnmount(() => {
  editor?.dispose()
  originalModel?.dispose()
  modifiedModel?.dispose()
})
</script>

<template>
  <div ref="container" class="monaco-host" />
</template>

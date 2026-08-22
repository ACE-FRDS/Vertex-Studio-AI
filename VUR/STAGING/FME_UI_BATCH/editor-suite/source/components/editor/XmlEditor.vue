<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as monaco from 'monaco-editor'
import EditorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import { useSettingsStore, type AppThemeId } from '../../stores/settings'

const model = defineModel<string>({ required: true })
const settings = useSettingsStore()
const container = ref<HTMLElement | null>(null)
let editor: monaco.editor.IStandaloneCodeEditor | undefined
let subscription: monaco.IDisposable | undefined

const monacoGlobal = self as typeof globalThis & {
  MonacoEnvironment?: { getWorker: () => Worker }
}
monacoGlobal.MonacoEnvironment = { getWorker: () => new EditorWorker() }

type EditorPalette = {
  light: boolean
  background: string
  foreground: string
  lineNumber: string
  activeLineNumber: string
  lineHighlight: string
  selection: string
  cursor: string
  indent: string
  activeIndent: string
  tag: string
  attribute: string
  value: string
  delimiter: string
}

const editorPalettes: Record<AppThemeId, EditorPalette> = {
  vertex: { light: false, background: '#0A1018', foreground: '#C8D4DF', lineNumber: '#34475A', activeLineNumber: '#8FB9DA', lineHighlight: '#101D29', selection: '#168CFF44', cursor: '#3AB8FF', indent: '#1A2A38', activeIndent: '#3B5E79', tag: '#55B7FF', attribute: '#8CD5FF', value: '#C8E68B', delimiter: '#66849F' },
  midnight: { light: false, background: '#0D0C1A', foreground: '#D2D0E7', lineNumber: '#45425F', activeLineNumber: '#B3ACEE', lineHighlight: '#17152A', selection: '#7467F044', cursor: '#9A8CFF', indent: '#26233B', activeIndent: '#565078', tag: '#A99CFF', attribute: '#83BAF3', value: '#C6E29A', delimiter: '#7D789D' },
  emerald: { light: false, background: '#07130F', foreground: '#C7DCD5', lineNumber: '#35554A', activeLineNumber: '#88C8B2', lineHighlight: '#0D201A', selection: '#16A87944', cursor: '#42D6A1', indent: '#173129', activeIndent: '#386E5E', tag: '#58D9AD', attribute: '#83C8BC', value: '#C3E58A', delimiter: '#5C8077' },
  amber: { light: false, background: '#140E08', foreground: '#E0D3C4', lineNumber: '#5F4832', activeLineNumber: '#D9B17D', lineHighlight: '#22170C', selection: '#D88A2D44', cursor: '#FFB454', indent: '#352415', activeIndent: '#78532C', tag: '#FFB454', attribute: '#E7C07E', value: '#B9DC85', delimiter: '#90765A' },
  crimson: { light: false, background: '#14090E', foreground: '#E0CDD4', lineNumber: '#60404C', activeLineNumber: '#DFA2B5', lineHighlight: '#251019', selection: '#D84B7244', cursor: '#FF7398', indent: '#391923', activeIndent: '#7B384D', tag: '#FF7398', attribute: '#D8A6D3', value: '#C9E189', delimiter: '#8D6674' },
  graphite: { light: false, background: '#0E1113', foreground: '#CCD2D7', lineNumber: '#454D54', activeLineNumber: '#B8C4CF', lineHighlight: '#181C20', selection: '#7D899544', cursor: '#B8C4CF', indent: '#252B30', activeIndent: '#59636C', tag: '#B8C4CF', attribute: '#8FB0C4', value: '#B7CF8F', delimiter: '#6F7A83' },
  'pastel-sky': { light: true, background: '#F4FAFF', foreground: '#294454', lineNumber: '#9BB3C3', activeLineNumber: '#3E789B', lineHighlight: '#E8F4FC', selection: '#4B9ED833', cursor: '#398EC8', indent: '#D5E8F3', activeIndent: '#9EC6DC', tag: '#2879A8', attribute: '#6D58A5', value: '#3F7A5A', delimiter: '#718A9B' },
  'pastel-mint': { light: true, background: '#F2FBF7', foreground: '#29483F', lineNumber: '#9BB9AE', activeLineNumber: '#377D69', lineHighlight: '#E5F6EF', selection: '#3FA88A33', cursor: '#329576', indent: '#D1EADF', activeIndent: '#98C9B7', tag: '#247E68', attribute: '#5D699F', value: '#47753D', delimiter: '#6E8D83' },
  'pastel-lavender': { light: true, background: '#F8F5FF', foreground: '#413858', lineNumber: '#B0A7C5', activeLineNumber: '#6E5BAD', lineHighlight: '#EEE9FA', selection: '#8974C933', cursor: '#7863B9', indent: '#E2DAF2', activeIndent: '#B9ACD7', tag: '#735EB5', attribute: '#4E78A7', value: '#587B43', delimiter: '#817797' },
  'pastel-peach': { light: true, background: '#FFF8F2', foreground: '#5A4033', lineNumber: '#C0A99C', activeLineNumber: '#A96849', lineHighlight: '#FBEDE3', selection: '#D78A6233', cursor: '#C77751', indent: '#F0DDD1', activeIndent: '#D9B39F', tag: '#B76540', attribute: '#7C679E', value: '#5F7C42', delimiter: '#9A7E70' },
  'pastel-rose': { light: true, background: '#FFF7FA', foreground: '#563845', lineNumber: '#BEA5AF', activeLineNumber: '#A45F7C', lineHighlight: '#FAEAF0', selection: '#C8799933', cursor: '#B86C8A', indent: '#EED9E1', activeIndent: '#D5ABB9', tag: '#A95175', attribute: '#6B6BA3', value: '#5D7B44', delimiter: '#94747F' },
  'pastel-lemon': { light: true, background: '#FFFDF3', foreground: '#504630', lineNumber: '#BDB39B', activeLineNumber: '#917029', lineHighlight: '#FAF5DE', selection: '#C99C3C33', cursor: '#B4892F', indent: '#EDE5C9', activeIndent: '#D5C58E', tag: '#9B7423', attribute: '#6C6A9D', value: '#58783D', delimiter: '#8D846C' },
}

for (const [themeId, palette] of Object.entries(editorPalettes) as [AppThemeId, EditorPalette][]) {
  monaco.editor.defineTheme(`vertex-${themeId}`, {
    base: palette.light ? 'vs' : 'vs-dark',
    inherit: true,
    rules: [
      { token: 'tag', foreground: palette.tag.slice(1) },
      { token: 'attribute.name', foreground: palette.attribute.slice(1) },
      { token: 'attribute.value', foreground: palette.value.slice(1) },
      { token: 'delimiter', foreground: palette.delimiter.slice(1) },
    ],
    colors: {
      'editor.background': palette.background,
      'editor.foreground': palette.foreground,
      'editorLineNumber.foreground': palette.lineNumber,
      'editorLineNumber.activeForeground': palette.activeLineNumber,
      'editor.lineHighlightBackground': palette.lineHighlight,
      'editor.selectionBackground': palette.selection,
      'editor.inactiveSelectionBackground': `${palette.selection.slice(0, 7)}22`,
      'editorCursor.foreground': palette.cursor,
      'editorIndentGuide.background1': palette.indent,
      'editorIndentGuide.activeBackground1': palette.activeIndent,
      'editorGutter.background': palette.background,
      'minimap.background': palette.background,
      'editorWhitespace.foreground': palette.indent,
      'editor.findMatchBackground': palette.selection,
    },
  })
}

const editorTheme = () => `vertex-${settings.theme}`

onMounted(() => {
  if (!container.value) return
  editor = monaco.editor.create(container.value, {
    value: model.value,
    language: 'xml',
    theme: editorTheme(),
    automaticLayout: true,
    fontFamily: "'JetBrains Mono', 'Cascadia Code', Consolas, monospace",
    fontSize: settings.fontSize,
    lineHeight: 21,
    minimap: { enabled: settings.minimap, scale: 0.8 },
    padding: { top: 14, bottom: 14 },
    renderLineHighlight: 'all',
    smoothScrolling: true,
    scrollBeyondLastLine: false,
    bracketPairColorization: { enabled: true },
    guides: { bracketPairs: true, indentation: true },
    folding: true,
    wordWrap: 'off',
  })
  subscription = editor.onDidChangeModelContent(() => {
    const value = editor?.getValue() ?? ''
    if (value !== model.value) model.value = value
  })
})

watch(model, (value) => {
  if (editor && value !== editor.getValue()) editor.setValue(value)
})

watch(
  () => [settings.fontSize, settings.minimap, settings.theme] as const,
  ([fontSize, minimap]) => {
    editor?.updateOptions({ fontSize, minimap: { enabled: minimap } })
    monaco.editor.setTheme(editorTheme())
  },
)

onBeforeUnmount(() => {
  subscription?.dispose()
  editor?.dispose()
})
</script>

<template>
  <div ref="container" class="monaco-host" />
</template>

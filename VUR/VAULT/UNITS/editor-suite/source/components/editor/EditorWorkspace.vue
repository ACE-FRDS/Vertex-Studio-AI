<script setup lang="ts">
import { computed, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useClipboardStore } from '../../stores/clipboard'
import { useEditorStore, type EditorTab } from '../../stores/editor'
import { useLocaleStore } from '../../stores/locale'
import { useCollectionWorkspaceStore } from '../../stores/collectionWorkspace'
import { formatXmlForDisplay } from '../../utils/xmlFormat'
import XmlEditor from './XmlEditor.vue'
import ScriptPreview from './ScriptPreview.vue'
import StructureView from './StructureView.vue'
import DiffEditor from './DiffEditor.vue'

const $q = useQuasar()
const clipboard = useClipboardStore()
const editor = useEditorStore()
const locale = useLocaleStore()
const collectionWorkspace = useCollectionWorkspaceStore()

const tabs = computed<{ id: EditorTab; label: string; icon: string }[]>(() => [
  { id: 'xml', label: 'XML', icon: 'code' },
  { id: 'preview', label: locale.t('preview'), icon: 'article' },
  { id: 'structure', label: locale.t('structure'), icon: 'account_tree' },
  { id: 'diff', label: locale.t('diff'), icon: 'difference' },
  { id: 'notes', label: locale.t('notes'), icon: 'notes' },
])

const item = computed(() => clipboard.selectedItem)

watch(
  () => clipboard.selectedId,
  () => {
    if (!clipboard.selectedItem) return
    const displayXml = formatXmlForDisplay(clipboard.selectedItem.xml)
    editor.content = displayXml
    editor.savedContent = displayXml
  },
)

function formatDocument() {
  const parser = new DOMParser()
  const parsed = parser.parseFromString(editor.content, 'application/xml')
  if (parsed.querySelector('parsererror')) {
    $q.notify({ type: 'negative', message: locale.t('xmlFormatError') })
    return
  }
  editor.content = formatXmlForDisplay(editor.content)
  $q.notify({ type: 'positive', message: locale.t('xmlFormatted') })
}
</script>

<template>
  <main class="editor-workspace">
    <div class="document-bar">
      <div class="document-identity">
        <span class="document-format">{{ item?.format ?? 'XML' }}</span>
        <div>
          <strong>{{ item?.name ?? locale.t('untitled') }}</strong>
          <span>{{ editor.modified ? locale.t('modified') : locale.t('saved') }}</span>
        </div>
      </div>
      <div v-if="collectionWorkspace.selectedProject" class="active-collection-project" :title="collectionWorkspace.selectedProject.name">
        <span class="material-icons">folder_open</span>
        <span>
          <small>{{ locale.language === 'ja' ? '選択中のProject' : 'Selected Project' }}</small>
          <strong>{{ collectionWorkspace.selectedProject.name }}</strong>
        </span>
      </div>
      <div class="document-actions">
        <q-btn flat dense icon="search" :aria-label="locale.t('search')"><q-tooltip>{{ locale.t('search') }}</q-tooltip></q-btn>
        <q-btn flat dense icon="undo" :aria-label="locale.t('undo')"><q-tooltip>{{ locale.t('undo') }}</q-tooltip></q-btn>
        <q-btn flat dense icon="redo" :aria-label="locale.t('redo')"><q-tooltip>{{ locale.t('redo') }}</q-tooltip></q-btn>
        <span />
        <q-btn flat dense icon="format_align_left" :aria-label="locale.t('formatDocument')" @click="formatDocument">
          <q-tooltip>{{ locale.t('formatDocument') }}</q-tooltip>
        </q-btn>
      </div>
    </div>

    <div class="editor-tabs" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        :class="{ active: editor.activeTab === tab.id }"
        @click="editor.activeTab = tab.id"
      >
        <span class="material-icons">{{ tab.icon }}</span>{{ tab.label }}
      </button>
      <div class="tab-spacer" />
      <span class="language-chip">XML</span>
    </div>

    <section class="editor-canvas">
      <XmlEditor v-if="editor.activeTab === 'xml'" v-model="editor.content" />
      <ScriptPreview v-else-if="editor.activeTab === 'preview'" />
      <StructureView v-else-if="editor.activeTab === 'structure'" :xml="editor.content" />
      <DiffEditor
        v-else-if="editor.activeTab === 'diff'"
        :original="editor.savedContent"
        :modified="editor.content"
      />
      <div v-else class="editor-notes">
        <label>{{ locale.t('developerNotes') }}</label>
        <textarea
          :value="item?.notes"
          :placeholder="locale.t('notesPlaceholder')"
          @input="clipboard.updateNotes(($event.target as HTMLTextAreaElement).value)"
        />
      </div>
    </section>
  </main>
</template>

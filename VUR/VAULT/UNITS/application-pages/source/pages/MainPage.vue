<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, type CSSProperties } from 'vue'
import { useNavigationStore } from '../stores/navigation'
import { useLocaleStore } from '../stores/locale'
import { useClipboardStore } from '../stores/clipboard'
import { useEditorStore } from '../stores/editor'
import { useLibraryStore } from '../stores/library'
import { useCollectionWorkspaceStore } from '../stores/collectionWorkspace'
import VertexHeader from '../components/layout/VertexHeader.vue'
import ClipboardSidebar from '../components/clipboard/ClipboardSidebar.vue'
import EditorWorkspace from '../components/editor/EditorWorkspace.vue'
import InspectorPanel from '../components/inspector/InspectorPanel.vue'
import BottomPanel from '../components/clipboard/BottomPanel.vue'
import StatusBar from '../components/layout/StatusBar.vue'
import ModuleWorkspace from '../components/workspace/ModuleWorkspace.vue'
import CodexWorkspace from '../components/codex/CodexWorkspace.vue'
import DocumentationWorkspace from '../components/docs/DocumentationWorkspace.vue'
import CollectionBrowserWorkspace from '../components/collections/CollectionBrowserWorkspace.vue'
import RelationshipDesignerWorkspace from '../components/relationship/RelationshipDesignerWorkspace.vue'
import KnowledgeWorkspace from '../components/knowledge/KnowledgeWorkspace.vue'
import { useClipboardMonitor } from '../composables/useClipboardMonitor'
import { formatXmlForDisplay } from '../utils/xmlFormat'
import { featureAccess } from '../services/featureAccess'
import { licenseGateway } from '../services/licenseGateway'

const navigation = useNavigationStore()
const locale = useLocaleStore()
const clipboard = useClipboardStore()
const editor = useEditorStore()
const library = useLibraryStore()
const collectionWorkspace = useCollectionWorkspaceStore()
useClipboardMonitor()

const SIDEBAR_MIN = 260
const SIDEBAR_MAX = 520
const SIDEBAR_STORAGE_KEY = 'vertex.sidebarWidth'
const defaultSidebarWidth = () => window.innerWidth <= 1420 ? 292 : 324
const storedSidebarWidthValue = localStorage.getItem(SIDEBAR_STORAGE_KEY)
const storedSidebarWidth = storedSidebarWidthValue === null ? Number.NaN : Number(storedSidebarWidthValue)
const sidebarWidth = ref(
  Number.isFinite(storedSidebarWidth)
    ? Math.min(maximumSidebarWidth(), Math.max(SIDEBAR_MIN, storedSidebarWidth))
    : defaultSidebarWidth(),
)
const resizingSidebar = ref(false)
let resizeStartX = 0
let resizeStartWidth = 0

const shellStyle = computed(() => ({
  '--sidebar-width': `${sidebarWidth.value}px`,
}) as CSSProperties)

function maximumSidebarWidth() {
  return Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, window.innerWidth - 820))
}

function setSidebarWidth(width: number) {
  sidebarWidth.value = Math.round(Math.min(maximumSidebarWidth(), Math.max(SIDEBAR_MIN, width)))
}

function stopSidebarResize() {
  if (!resizingSidebar.value) return
  resizingSidebar.value = false
  document.body.classList.remove('is-resizing-sidebar')
  localStorage.setItem(SIDEBAR_STORAGE_KEY, String(sidebarWidth.value))
  window.removeEventListener('pointermove', resizeSidebar)
  window.removeEventListener('pointerup', stopSidebarResize)
  window.removeEventListener('pointercancel', stopSidebarResize)
}

function resizeSidebar(event: PointerEvent) {
  setSidebarWidth(resizeStartWidth + event.clientX - resizeStartX)
}

function startSidebarResize(event: PointerEvent) {
  if (event.button !== 0) return
  resizeStartX = event.clientX
  resizeStartWidth = sidebarWidth.value
  resizingSidebar.value = true
  document.body.classList.add('is-resizing-sidebar')
  window.addEventListener('pointermove', resizeSidebar)
  window.addEventListener('pointerup', stopSidebarResize)
  window.addEventListener('pointercancel', stopSidebarResize)
}

function resizeSidebarWithKeyboard(event: KeyboardEvent) {
  if (event.key === 'ArrowLeft') setSidebarWidth(sidebarWidth.value - 12)
  else if (event.key === 'ArrowRight') setSidebarWidth(sidebarWidth.value + 12)
  else if (event.key === 'Home') setSidebarWidth(SIDEBAR_MIN)
  else if (event.key === 'End') setSidebarWidth(maximumSidebarWidth())
  else return
  event.preventDefault()
  localStorage.setItem(SIDEBAR_STORAGE_KEY, String(sidebarWidth.value))
}

function resetSidebarWidth() {
  setSidebarWidth(defaultSidebarWidth())
  localStorage.setItem(SIDEBAR_STORAGE_KEY, String(sidebarWidth.value))
}

function handleWindowResize() {
  setSidebarWidth(sidebarWidth.value)
}

async function refreshLicenseState() {
  try {
    featureAccess.applyVerifiedLicense(await licenseGateway.refresh())
  } catch (error) {
    console.error('Failed to refresh license state', error)
  }
}

window.addEventListener('resize', handleWindowResize)
window.addEventListener('focus', refreshLicenseState)
window.addEventListener('vertex:license-changed', refreshLicenseState)
onMounted(async () => {
  try {
    featureAccess.applyVerifiedLicense(await licenseGateway.get())
    await clipboard.initialize()
    await library.initialize()
    await collectionWorkspace.initialize()
    if (clipboard.selectedItem) {
      const displayXml = formatXmlForDisplay(clipboard.selectedItem.xml)
      editor.content = displayXml
      editor.savedContent = displayXml
      await Promise.all([
        editor.validate(clipboard.selectedItem.format),
        editor.buildPreview(),
      ])
    }
  } catch (error) {
    console.error('Failed to initialize clipboard history', error)
  }
})
onBeforeUnmount(() => {
  stopSidebarResize()
  window.removeEventListener('resize', handleWindowResize)
  window.removeEventListener('focus', refreshLicenseState)
  window.removeEventListener('vertex:license-changed', refreshLicenseState)
})
</script>

<template>
  <!-- Clipboard, collection browser, and editor share one SPA shell. -->
  <div class="vertex-shell" :style="shellStyle">
    <VertexHeader class="app-header" />
    <template v-if="navigation.active === 'clipboard' || navigation.active === 'collections'">
      <ClipboardSidebar class="app-sidebar" />
      <CollectionBrowserWorkspace v-if="navigation.active === 'collections'" class="app-editor" />
      <EditorWorkspace v-else class="app-editor" />
      <InspectorPanel class="app-inspector" />
      <BottomPanel class="app-bottom" />
      <div
        class="sidebar-resizer"
        :class="{ active: resizingSidebar }"
        role="separator"
        tabindex="0"
        aria-orientation="vertical"
        :aria-label="locale.t('resizeSidebar')"
        :aria-valuemin="SIDEBAR_MIN"
        :aria-valuemax="maximumSidebarWidth()"
        :aria-valuenow="sidebarWidth"
        @pointerdown="startSidebarResize"
        @keydown="resizeSidebarWithKeyboard"
        @dblclick="resetSidebarWidth"
      />
    </template>
    <CodexWorkspace v-else-if="navigation.active === 'codex'" class="app-module" />
    <KnowledgeWorkspace v-else-if="navigation.active === 'knowledge'" class="app-module" />
    <RelationshipDesignerWorkspace v-else-if="navigation.active === 'relationship'" class="app-module" />
    <DocumentationWorkspace v-else-if="navigation.active === 'docs'" class="app-module" />
    <ModuleWorkspace v-else class="app-module" :mode="navigation.active" />
    <StatusBar class="app-status" />
  </div>
</template>

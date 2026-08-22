<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQuasar } from 'quasar'
import { sampleInspector } from '../../data/sample'
import { clipboardGateway } from '../../services/clipboardGateway'
import { isTauriRuntime, nativeGateway } from '../../services/nativeGateway'
import { formatXmlForDisplay } from '../../utils/xmlFormat'
import { clipboardItemName } from '../../utils/clipboardItemNaming'
import { useClipboardStore } from '../../stores/clipboard'
import { useEditorStore } from '../../stores/editor'
import { useLocaleStore } from '../../stores/locale'
import { createDefaultCollection, useLibraryStore } from '../../stores/library'
import { collectionCategories, useCollectionWorkspaceStore, type CollectionCategoryId } from '../../stores/collectionWorkspace'
import { useSettingsStore, type AppThemeId } from '../../stores/settings'
import { useAiAssistantStore } from '../../stores/aiAssistant'
import { useNavigationStore, type WorkspaceMode } from '../../stores/navigation'
import { aiGateway } from '../../services/aiGateway'
import type { ClipboardItem } from '../../types/clipboard'
import type { CollectionNode } from '../../types/library'
import type { AiMessage, AiMode, AiSession, AiWorkspaceData, RagDocument, RiskLevel } from '../../types/ai'
import ValidationPanel from './ValidationPanel.vue'

const $q = useQuasar()
const clipboard = useClipboardStore()
const editor = useEditorStore()
const locale = useLocaleStore()
const library = useLibraryStore()
const collectionWorkspace = useCollectionWorkspaceStore()
const settings = useSettingsStore()
const ai = useAiAssistantStore()
const navigation = useNavigationStore()
const sending = ref(false)
const receiving = ref(false)
const workspaceSaving = ref(false)
const workspaceLoading = ref(false)
let dismissTransferNotification: (() => void) | undefined

interface WorkspaceSnapshot {
  schema: 'vrtex-fm-engine/workspace'
  schemaVersion: 1
  navigation?: { activeWorkspace?: WorkspaceMode }
  editor?: {
    content?: string
    savedContent?: string
    activeTab?: typeof editor.activeTab
  }
  clipboard?: {
    items?: ClipboardItem[]
    libraryItems?: ClipboardItem[]
    selectedId?: string
    autoSave?: boolean
  }
  collections?: {
    items?: CollectionNode[]
    selectedId?: string | null
    selectedCategoryId?: CollectionCategoryId
    itemProjectIds?: Record<string, string>
  }
  aiAssistant?: {
    sessions?: AiSession[]
    activeSession?: AiSession | null
    messages?: AiMessage[]
    ragDocuments?: RagDocument[]
    mode?: AiMode
    provider?: string
    model?: string
    dryRun?: boolean
    originalXml?: string
    generatedXml?: string
    validationStatus?: 'pending' | 'pass' | 'fail'
    riskLevel?: RiskLevel
    stages?: string[]
  }
  settings?: {
    fontSize?: number
    minimap?: boolean
    fileMakerVersion?: string
    polling?: boolean
    theme?: AppThemeId
    codexIntegration?: 'openai' | 'codex'
    codexModel?: string
    codexAuthMethod?: 'chatgpt' | 'api-key'
    codexCredentialStore?: 'environment' | 'keyring' | 'auto'
    codexRagEnabled?: boolean
    codexRequireDiffReview?: boolean
  }
}

const byteSize = computed(() => new TextEncoder().encode(editor.content).byteLength)
const validationErrorCount = computed(() =>
  editor.validation.filter((result) => result.level === 'error').length,
)
const canSendToFileMaker = computed(() =>
  Boolean(clipboard.selectedItem)
  && !sending.value
  && !editor.validationPending
  && validationErrorCount.value === 0,
)
const objectSummary = computed(() => {
  const document = new DOMParser().parseFromString(editor.content, 'application/xml')
  if (document.querySelector('parsererror')) return '—'
  const scripts = document.querySelectorAll('Script').length
  const steps = document.querySelectorAll('Step').length
  const countLabel = (count: number, label: string) => `${count} ${label}${count === 1 ? '' : 's'}`
  if (scripts) return `${countLabel(scripts, 'Script')} / ${countLabel(steps, 'Step')}`
  if (steps) return countLabel(steps, 'Step')
  const objectType = clipboard.selectedItem?.objectType ?? sampleInspector.objectType
  const selectors: Record<string, string> = {
    Table: 'BaseTable, Table',
    Field: 'Field',
    Layout: 'Layout, Object',
  }
  const count = document.querySelectorAll(selectors[objectType] ?? '*').length
  return countLabel(count, objectType)
})
const details = computed(() => [
  [locale.t('formatWindows'), clipboard.selectedItem?.windowsFormat ?? sampleInspector.windowsFormat],
  [locale.t('formatInternal'), clipboard.selectedItem?.format ?? sampleInspector.internalFormat],
  [locale.t('type'), clipboard.selectedItem?.objectType ?? sampleInspector.objectType],
  [locale.t('objects'), objectSummary.value],
  [locale.t('fileMakerVersion'), sampleInspector.fileMakerVersion],
  [locale.t('size'), `${byteSize.value.toLocaleString()} bytes`],
  [locale.t('encoding'), sampleInspector.encoding],
  [locale.t('header'), `${sampleInspector.headerBytes} bytes · Little Endian`],
])

function transferCaption(name: string, format: string, bytes: number) {
  return `${name} · ${format} · ${bytes.toLocaleString()} bytes`
}

function errorCaption(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  return message.replace(/^FileMaker Clipboard is not available:\s*/i, '')
}

function notifyTransfer(
  kind: 'get-success' | 'set-success' | 'get-error' | 'set-error',
  caption: string,
) {
  dismissTransferNotification?.()
  const success = kind.endsWith('success')
  const getting = kind.startsWith('get')
  dismissTransferNotification = $q.notify({
    position: 'bottom',
    timeout: success ? 3200 : 5600,
    progress: true,
    multiLine: true,
    icon: success ? (getting ? 'content_paste_go' : 'outbox') : 'error_outline',
    iconColor: success ? 'light-blue-4' : 'red-4',
    textColor: 'white',
    message: locale.t(
      success
        ? getting ? 'clipboardGetComplete' : 'clipboardSetComplete'
        : getting ? 'clipboardGetFailed' : 'clipboardSetFailed',
    ),
    caption,
    classes: `vertex-transfer-notification ${success ? 'transfer-success' : 'transfer-error'}`,
  })
}

async function sendToFileMaker() {
  if (!clipboard.selectedItem) {
    notifyTransfer('set-error', locale.t('clipboardNoSelection'))
    return
  }
  if (!isTauriRuntime()) {
    notifyTransfer('set-error', locale.t('desktopRequired'))
    return
  }
  sending.value = true
  try {
    const report = await nativeGateway.validateXml(editor.content, clipboard.selectedItem.format)
    editor.validation = report.issues.map(({ level, message }) => ({ level, message }))
    if (!report.valid) {
      notifyTransfer(
        'set-error',
        `${validationErrorCount.value}${locale.t('validationErrorsSuffix')}`,
      )
      return
    }
    await clipboardGateway.set(clipboard.selectedItem.format, editor.content)
    notifyTransfer(
      'set-success',
      transferCaption(clipboard.selectedItem.name, clipboard.selectedItem.format, byteSize.value),
    )
  } catch (error) {
    notifyTransfer('set-error', errorCaption(error))
  } finally {
    sending.value = false
  }
}

async function getFromFileMaker() {
  if (!isTauriRuntime()) {
    notifyTransfer('get-error', locale.t('desktopRequired'))
    return
  }
  receiving.value = true
  try {
    const payload = await clipboardGateway.get()
    const detected = await nativeGateway.detectFormat(payload.xml)
    const format = detected.format === 'UNKNOWN' ? payload.format : detected.format
    const saved = await clipboard.upsert({
      name: clipboardItemName(
        payload.xml,
        detected.objectType,
        [...clipboard.items, ...clipboard.libraryItems],
      ),
      format,
      windowsFormat: payload.windowsFormat,
      objectType: detected.objectType,
      xml: payload.xml,
      notes: '',
      favorite: false,
      inLibrary: false,
    })
    await collectionWorkspace.assignItemToProject(saved.id)
    const displayXml = formatXmlForDisplay(saved.xml)
    editor.content = displayXml
    editor.savedContent = displayXml
    await Promise.all([editor.validate(saved.format), editor.buildPreview()])
    notifyTransfer(
      'get-success',
      transferCaption(saved.name, saved.format, payload.rawSize),
    )
  } catch (error) {
    notifyTransfer('get-error', errorCaption(error))
  } finally {
    receiving.value = false
  }
}

async function validate() {
  await editor.validate(clipboard.selectedItem?.format)
  const errorCount = editor.validation.filter((result) => result.level === 'error').length
  $q.notify({
    type: errorCount ? 'negative' : 'positive',
    message: errorCount ? `${errorCount}${locale.t('validationErrorsSuffix')}` : locale.t('validationPassedNotice'),
  })
}

async function save() {
  const item = clipboard.selectedItem
  if (!item) return
  try {
    const saved = await clipboard.upsert({
      id: item.id,
      name: item.name,
      format: item.format,
      windowsFormat: item.windowsFormat,
      objectType: item.objectType,
      xml: editor.content,
      notes: item.notes,
      favorite: item.favorite,
      inLibrary: true,
    })
    await collectionWorkspace.assignItemToProject(saved.id)
    editor.save()
    $q.notify({
      type: 'positive',
      message: locale.t('savedToLibrary') || (locale.language === 'ja' ? 'ライブラリに保存しました' : 'Saved to the library'),
    })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  }
}

function workspaceFileName() {
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '')
  return `Vertex-FM-Engine-${stamp}.vfe-workspace`
}

function workspaceContents(aiWorkspace: AiWorkspaceData) {
  return JSON.stringify({
    schema: 'vrtex-fm-engine/workspace',
    schemaVersion: 1,
    appVersion: '0.1.0',
    exportedAt: new Date().toISOString(),
    navigation: { activeWorkspace: navigation.active },
    editor: {
      content: editor.content,
      savedContent: editor.savedContent,
      activeTab: editor.activeTab,
      validation: editor.validation,
      preview: editor.preview,
    },
    clipboard: {
      items: clipboard.items,
      libraryItems: clipboard.libraryItems,
      selectedId: clipboard.selectedId,
      autoSave: clipboard.autoSave,
    },
    collections: {
      items: library.collections,
      selectedId: collectionWorkspace.selectedProjectId,
      selectedCategoryId: collectionWorkspace.selectedCategoryId,
      itemProjectIds: collectionWorkspace.itemProjectIds,
    },
    aiAssistant: {
      sessions: aiWorkspace.sessions,
      activeSession: ai.activeSession,
      messages: aiWorkspace.messages,
      ragDocuments: aiWorkspace.ragDocuments,
      mode: ai.mode,
      provider: ai.provider,
      model: ai.model,
      dryRun: ai.dryRun,
      originalXml: ai.originalXml,
      generatedXml: ai.generatedXml,
      validationStatus: ai.validationStatus,
      riskLevel: ai.riskLevel,
      stages: ai.stages,
    },
    settings: {
      fontSize: settings.fontSize,
      minimap: settings.minimap,
      fileMakerVersion: settings.fileMakerVersion,
      polling: settings.polling,
      theme: settings.theme,
      codexIntegration: settings.codexIntegration,
      codexModel: settings.codexModel,
      codexAuthMethod: settings.codexAuthMethod,
      codexCredentialStore: settings.codexCredentialStore,
      codexRagEnabled: settings.codexRagEnabled,
      codexRequireDiffReview: settings.codexRequireDiffReview,
    },
  }, null, 2)
}

async function saveWorkspace() {
  if (workspaceSaving.value) return
  workspaceSaving.value = true
  try {
    const fileName = workspaceFileName()
    const contents = workspaceContents(await aiGateway.exportWorkspace())
    if (isTauriRuntime()) {
      const { save: showSaveDialog } = await import('@tauri-apps/plugin-dialog')
      const selectedPath = await showSaveDialog({
        title: locale.t('saveWorkspace') || (locale.language === 'ja' ? 'ワークスペースに保存' : 'Save Workspace'),
        defaultPath: fileName,
        filters: [{ name: 'Vertex FM Engine Workspace', extensions: ['vfe-workspace'] }],
      })
      if (!selectedPath) return
      const destination = selectedPath.toLocaleLowerCase().endsWith('.vfe-workspace')
        ? selectedPath
        : `${selectedPath}.vfe-workspace`
      await nativeGateway.saveWorkspaceFile(destination, contents)
    } else {
      const blobUrl = URL.createObjectURL(new Blob([contents], { type: 'application/vnd.vrtex-fm-engine.workspace+json' }))
      const anchor = document.createElement('a')
      anchor.href = blobUrl
      anchor.download = fileName
      anchor.click()
      window.setTimeout(() => URL.revokeObjectURL(blobUrl), 0)
    }
    $q.notify({
      type: 'positive',
      message: locale.t('workspaceFileSaved') || (locale.language === 'ja' ? 'ワークスペースファイルを保存しました' : 'Workspace file saved'),
    })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    workspaceSaving.value = false
  }
}

function parseWorkspace(contents: string): WorkspaceSnapshot {
  const parsed = JSON.parse(contents) as Partial<WorkspaceSnapshot>
  if (parsed.schema !== 'vrtex-fm-engine/workspace' || parsed.schemaVersion !== 1) {
    throw new Error(locale.language === 'ja'
      ? '対応していないワークスペース形式です。'
      : 'Unsupported workspace format.')
  }
  return parsed as WorkspaceSnapshot
}

async function restoreWorkspace(snapshot: WorkspaceSnapshot) {
  const snapshotCollections = snapshot.collections?.items?.length
    ? snapshot.collections.items
    : [createDefaultCollection()]
  const projectIds = new Set(snapshotCollections.map((collection) => collection.id))
  const historyItems = snapshot.clipboard?.items ?? []
  const libraryItems = snapshot.clipboard?.libraryItems ?? []
  const historyIds = new Set(historyItems.map((item) => item.id))
  const libraryIds = new Set(libraryItems.map((item) => item.id))
  const mergedItems = new Map<string, ClipboardItem>()
  for (const item of [...historyItems, ...libraryItems]) {
    const previous = mergedItems.get(item.id)
    mergedItems.set(item.id, {
      ...(previous ?? item),
      ...item,
      tags: [...new Set([...(previous?.tags ?? []), ...(item.tags ?? [])])],
      inHistory: historyIds.has(item.id),
      inLibrary: libraryIds.has(item.id),
    })
  }

  await clipboard.clearAll()
  library.collections = []
  collectionWorkspace.clear()
  for (const collection of snapshotCollections) {
    await library.saveCollection({ ...collection, children: collection.children ?? [] })
  }

  for (const item of mergedItems.values()) {
    const saved = await clipboard.upsert({
      id: item.id,
      name: item.name,
      format: item.format,
      windowsFormat: item.windowsFormat,
      objectType: item.objectType,
      xml: item.xml,
      notes: item.notes,
      favorite: item.favorite,
      inLibrary: item.inLibrary,
      inHistory: item.inHistory,
    }, { select: false })
    if (item.tags?.length) await clipboard.updateTags(saved.id, item.tags)
  }

  const assignments = snapshot.collections?.itemProjectIds ?? {}
  for (const [itemId, projectId] of Object.entries(assignments)) {
    if (!mergedItems.has(itemId) || !projectIds.has(projectId)) continue
    await collectionWorkspace.assignItemToProject(itemId, projectId)
  }

  const selectedProjectId = snapshot.collections?.selectedId
  collectionWorkspace.selectProject(
    selectedProjectId && projectIds.has(selectedProjectId)
      ? selectedProjectId
      : snapshotCollections[0]!.id,
  )
  library.selectedCollectionId = collectionWorkspace.selectedProjectId
  const selectedCategoryId = snapshot.collections?.selectedCategoryId
  if (selectedCategoryId && collectionCategories.some((category) => category.id === selectedCategoryId)) {
    collectionWorkspace.selectCategory(selectedCategoryId)
  }

  clipboard.autoSave = snapshot.clipboard?.autoSave ?? clipboard.autoSave
  const selectedItemId = snapshot.clipboard?.selectedId
  clipboard.selectedId = selectedItemId && mergedItems.has(selectedItemId)
    ? selectedItemId
    : historyItems[0]?.id ?? libraryItems[0]?.id ?? ''

  const editorState = snapshot.editor
  if (editorState?.content !== undefined) editor.content = editorState.content
  if (editorState?.savedContent !== undefined) editor.savedContent = editorState.savedContent
  if (editorState?.activeTab !== undefined) editor.activeTab = editorState.activeTab
  await Promise.all([
    editor.validate(clipboard.selectedItem?.format),
    editor.buildPreview(),
  ])

  const savedSettings = snapshot.settings
  if (savedSettings) {
    if (savedSettings.fontSize !== undefined) settings.fontSize = savedSettings.fontSize
    if (savedSettings.minimap !== undefined) settings.minimap = savedSettings.minimap
    if (savedSettings.fileMakerVersion !== undefined) settings.fileMakerVersion = savedSettings.fileMakerVersion
    if (savedSettings.polling !== undefined) settings.polling = savedSettings.polling
    if (savedSettings.theme !== undefined) settings.theme = savedSettings.theme
    if (savedSettings.codexIntegration !== undefined) settings.codexIntegration = savedSettings.codexIntegration
    if (savedSettings.codexModel !== undefined) settings.codexModel = savedSettings.codexModel
    if (savedSettings.codexAuthMethod !== undefined) settings.codexAuthMethod = savedSettings.codexAuthMethod
    if (savedSettings.codexCredentialStore !== undefined) settings.codexCredentialStore = savedSettings.codexCredentialStore
    if (savedSettings.codexRagEnabled !== undefined) settings.codexRagEnabled = savedSettings.codexRagEnabled
    if (savedSettings.codexRequireDiffReview !== undefined) settings.codexRequireDiffReview = savedSettings.codexRequireDiffReview
  }

  const aiState = snapshot.aiAssistant
  if (aiState) {
    await aiGateway.importWorkspace({
      sessions: aiState.sessions ?? [],
      messages: aiState.messages ?? [],
      ragDocuments: aiState.ragDocuments ?? [],
    })
    if (aiState.sessions) ai.sessions = aiState.sessions
    if (aiState.activeSession !== undefined) ai.activeSession = aiState.activeSession
    if (aiState.messages) {
      ai.messages = aiState.activeSession
        ? aiState.messages.filter((message) => message.sessionId === aiState.activeSession?.id)
        : []
    }
    if (aiState.ragDocuments) ai.ragDocuments = aiState.ragDocuments
    if (aiState.mode) ai.mode = aiState.mode
    if (aiState.provider) ai.provider = aiState.provider
    if (aiState.model) ai.model = aiState.model
    if (aiState.dryRun !== undefined) ai.dryRun = aiState.dryRun
    if (aiState.originalXml !== undefined) ai.originalXml = aiState.originalXml
    if (aiState.generatedXml !== undefined) ai.generatedXml = aiState.generatedXml
    if (aiState.validationStatus) ai.validationStatus = aiState.validationStatus
    if (aiState.riskLevel) ai.riskLevel = aiState.riskLevel
    if (aiState.stages) ai.stages = aiState.stages
  }

  if (snapshot.navigation?.activeWorkspace) {
    navigation.setActive(snapshot.navigation.activeWorkspace)
  }
}

async function openWorkspace() {
  if (workspaceLoading.value) return
  if (!isTauriRuntime()) {
    $q.notify({ type: 'negative', message: locale.t('desktopRequired') })
    return
  }
  workspaceLoading.value = true
  try {
    const { open: showOpenDialog } = await import('@tauri-apps/plugin-dialog')
    const selectedPath = await showOpenDialog({
      title: locale.language === 'ja' ? 'ワークスペースを開く' : 'Open Workspace',
      multiple: false,
      directory: false,
      filters: [{ name: 'Vertex FM Engine Workspace', extensions: ['vfe-workspace'] }],
    })
    if (typeof selectedPath !== 'string') return
    const snapshot = parseWorkspace(await nativeGateway.readWorkspaceFile(selectedPath))
    $q.dialog({
      title: locale.language === 'ja' ? 'ワークスペースを開く' : 'Open Workspace',
      message: locale.language === 'ja'
        ? '現在の履歴・ライブラリ・コレクション・編集内容を、選択したワークスペースで置き換えます。続行しますか？'
        : 'Replace the current history, library, collections, and editor state with this workspace?',
      cancel: { label: locale.language === 'ja' ? 'キャンセル' : 'Cancel', flat: true },
      persistent: true,
      class: 'vertex-dialog',
      ok: { label: locale.language === 'ja' ? '開く' : 'Open', color: 'primary' },
    }).onOk(async () => {
      workspaceLoading.value = true
      try {
        await restoreWorkspace(snapshot)
        $q.notify({
          type: 'positive',
          message: locale.language === 'ja' ? 'ワークスペースを復元しました' : 'Workspace restored',
        })
      } catch (error) {
        $q.notify({ type: 'negative', message: String(error) })
      } finally {
        workspaceLoading.value = false
      }
    }).onCancel(() => { workspaceLoading.value = false })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    workspaceLoading.value = false
  }
}

async function toggleFavorite() {
  try {
    await clipboard.toggleFavorite()
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  }
}

async function copyAsText() {
  await navigator.clipboard.writeText(editor.content)
  $q.notify({ type: 'positive', message: locale.t('copiedXmlText') })
}
</script>

<template>
  <aside class="inspector-panel">
    <div class="inspector-title">
      <div><span class="eyebrow">{{ locale.t('analyze') }}</span><h2>{{ locale.t('inspector') }}</h2></div>
      <q-btn flat dense round size="sm" icon="tune" />
    </div>

    <section class="inspector-section details-section">
      <div class="section-heading"><span>{{ locale.t('objectDetails') }}</span><i /></div>
      <dl>
        <template v-for="[label, value] in details" :key="label">
          <dt>{{ label }}</dt>
          <dd :class="{ accent: label === locale.t('formatInternal') || label === locale.t('type') }">{{ value }}</dd>
        </template>
      </dl>
    </section>

    <section class="inspector-section validation-section">
      <div class="section-heading">
        <span>{{ locale.t('validation') }}</span>
        <q-badge
          :color="validationErrorCount ? 'negative' : 'positive'"
          text-color="white"
          :label="validationErrorCount ? `${validationErrorCount}${locale.t('validationErrorsSuffix')}` : locale.t('pass')"
        />
      </div>
      <ValidationPanel :results="editor.validation" />
      <button class="secondary-action" type="button" @click="validate">
        <span class="material-icons">fact_check</span> {{ locale.t('validateAgain') }}
      </button>
    </section>

    <section class="inspector-section action-section">
      <div class="section-heading"><span>{{ locale.t('actions') }}</span><i /></div>
      <button class="get-button" type="button" :disabled="receiving" @click="getFromFileMaker">
        <span class="material-icons">content_paste_go</span>
        <strong>{{ receiving ? locale.t('receiving') : locale.t('getFromFileMaker') }}</strong>
      </button>
      <button class="send-button" type="button" :disabled="!canSendToFileMaker" @click="sendToFileMaker">
        <span class="send-icon material-icons">send</span>
        <span><strong>{{ sending ? locale.t('sending') : locale.t('sendToFileMaker') }}</strong><small>{{ locale.t('writeXmlClipboard') }}</small></span>
        <span class="material-icons arrow">arrow_forward</span>
      </button>
      <div class="action-grid">
        <button type="button" @click="save">
          <span class="material-icons">save</span>{{ locale.t('saveToLibrary') || (locale.language === 'ja' ? 'ライブラリに保存' : 'Save to Library') }}
        </button>
        <button type="button" @click="toggleFavorite">
          <span class="material-icons">{{ clipboard.selectedItem?.favorite ? 'star' : 'star_border' }}</span>{{ locale.t('favorite') }}
        </button>
        <button type="button" :disabled="workspaceSaving" @click="saveWorkspace">
          <span class="material-icons">{{ workspaceSaving ? 'hourglass_top' : 'download' }}</span>{{ locale.t('saveWorkspace') || (locale.language === 'ja' ? 'ワークスペースに保存' : 'Save Workspace') }}
        </button>
        <button type="button" :disabled="workspaceLoading" @click="openWorkspace">
          <span class="material-icons">{{ workspaceLoading ? 'hourglass_top' : 'folder_open' }}</span>{{ locale.language === 'ja' ? 'ワークスペースを開く' : 'Open Workspace' }}
        </button>
        <button type="button" @click="copyAsText"><span class="material-icons">content_copy</span>{{ locale.t('copyText') }}</button>
      </div>
    </section>
  </aside>
</template>

<style scoped>
.inspector-title .eyebrow {
  color: var(--blue-bright);
}
</style>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQuasar } from 'quasar'
import { useClipboardStore } from '../../stores/clipboard'
import { useEditorStore } from '../../stores/editor'
import { useLibraryStore } from '../../stores/library'
import { useCollectionWorkspaceStore } from '../../stores/collectionWorkspace'
import { appThemes, useSettingsStore } from '../../stores/settings'
import { useLocaleStore } from '../../stores/locale'
import { useAiAssistantStore } from '../../stores/aiAssistant'
import { useNavigationStore } from '../../stores/navigation'
import { aiGateway } from '../../services/aiGateway'
import { isTauriRuntime, nativeGateway } from '../../services/nativeGateway'
import { formatXmlForDisplay } from '../../utils/xmlFormat'
import type { AiConnectionTest, RagDocument } from '../../types/ai'
import type { WorkspaceMode } from '../../stores/navigation'

const props = defineProps<{ mode: Exclude<WorkspaceMode, 'clipboard' | 'codex' | 'knowledge' | 'relationship' | 'docs'> }>()
const $q = useQuasar()
const clipboard = useClipboardStore()
const editor = useEditorStore()
const library = useLibraryStore()
const collectionWorkspace = useCollectionWorkspaceStore()
const settings = useSettingsStore()
const locale = useLocaleStore()
const ai = useAiAssistantStore()
const navigation = useNavigationStore()
const settingsSection = ref<'general' | 'codex' | 'data'>('general')
const openingLibraryItemId = ref('')
const openAiApiKey = ref('')
const credentialBusy = ref(false)
const connectionTest = ref<AiConnectionTest | null>(null)
const libraryQuery = ref('')
const librarySort = ref<'recent' | 'name'>('recent')
const ragDocuments = ref<RagDocument[]>([])
const ragLoading = ref(false)
const ragTitle = ref('')
const ragContent = ref('')
const ragTags = ref('')
const ragSourceType = ref('filemaker-spec')

const visibleLibraryItems = computed(() => {
  const query = libraryQuery.value.trim().toLocaleLowerCase()
  const filtered = query
    ? clipboard.libraryItems.filter((item) =>
        [item.name, item.format, item.objectType, item.windowsFormat, ...item.tags]
          .some((value) => value.toLocaleLowerCase().includes(query)),
      )
    : [...clipboard.libraryItems]
  return filtered.sort((left, right) => librarySort.value === 'name'
    ? left.name.localeCompare(right.name, locale.language)
    : Date.parse(right.lastUsedAt || right.updatedAt) - Date.parse(left.lastUsedAt || left.updatedAt))
})

const selectedProviderStatus = computed(() =>
  ai.providers.find((provider) => provider.id === settings.codexIntegration) ?? null,
)

const providerStatusLabel = computed(() => {
  if (connectionTest.value?.provider === settings.codexIntegration) {
    return connectionTest.value.success ? '接続確認済み' : '接続失敗'
  }
  return selectedProviderStatus.value?.authenticated ? '認証情報あり' : '未接続'
})

const headings = computed(() => ({
  library: {
    eyebrow: locale.t('libraryEyebrow'),
    title: locale.t('navLibrary'),
    description: locale.t('libraryDescription'),
    icon: 'library_books',
  },
  collections: {
    eyebrow: locale.t('collectionsEyebrow'),
    title: locale.t('navCollections'),
    description: locale.t('collectionsDescription'),
    icon: 'account_tree',
  },
  tools: {
    eyebrow: locale.t('toolsEyebrow'),
    title: locale.t('navTools'),
    description: locale.t('toolsDescription'),
    icon: 'construction',
  },
  settings: {
    eyebrow: locale.t('settingsEyebrow'),
    title: locale.t('navSettings'),
    description: locale.t('settingsDescription'),
    icon: 'settings',
  },
} as const))

const heading = computed(() => headings.value[props.mode])

const tools = computed(() => [
  { icon: 'fact_check', name: 'XML Validation', detail: locale.t('toolXmlValidationDescription'), state: locale.t('available'), planned: false },
  { icon: 'radar', name: 'Format Detection', detail: locale.t('toolFormatDetectionDescription'), state: locale.t('available'), planned: false },
  { icon: 'difference', name: 'XML Diff', detail: locale.t('toolDiffDescription'), state: locale.t('available'), planned: false },
  { icon: 'account_tree', name: 'Structure Viewer', detail: locale.t('toolStructureDescription'), state: locale.t('available'), planned: false },
  { icon: 'build_circle', name: 'XML Repair', detail: locale.t('toolRepairDescription'), state: locale.t('planned'), planned: true },
  { icon: 'psychology', name: 'AI Assistant', detail: locale.t('toolAiDescription'), state: locale.t('available'), planned: false },
])

async function openTool(name: string) {
  if (name === 'XML Repair') return
  if (name === 'AI Assistant') {
    navigation.setActive('codex')
    return
  }
  if (!clipboard.selectedItem) {
    $q.notify({ type: 'warning', message: locale.language === 'ja' ? '先にクリップボード項目を選択してください' : 'Select a Clipboard item first' })
    navigation.setActive('clipboard')
    return
  }
  if (name === 'XML Diff') editor.activeTab = 'diff'
  else if (name === 'Structure Viewer') editor.activeTab = 'structure'
  else {
    editor.activeTab = 'xml'
    if (name === 'XML Validation') {
      await editor.validate(clipboard.selectedItem.format)
      const errors = editor.validation.filter((result) => result.level === 'error').length
      $q.notify({
        type: errors ? 'negative' : 'positive',
        message: errors
          ? `${errors}${locale.t('validationErrorsSuffix')}`
          : locale.t('validationPassedNotice'),
      })
    } else if (name === 'Format Detection') {
      const detected = isTauriRuntime()
        ? await nativeGateway.detectFormat(editor.content)
        : { format: clipboard.selectedItem.format, objectType: clipboard.selectedItem.objectType }
      $q.notify({
        type: 'info',
        icon: 'radar',
        message: `${detected.format} · ${detected.objectType}`,
      })
    }
  }
  navigation.setActive('clipboard')
}

function collectionItemCount(projectId: string) {
  return clipboard.items.filter((item) =>
    item.inHistory && collectionWorkspace.projectIdForItem(item.id) === projectId,
  ).length
}

function openCollection(projectId: string) {
  collectionWorkspace.selectProject(projectId)
  collectionWorkspace.selectCategory('all')
  library.selectedCollectionId = projectId
  navigation.setActive('clipboard')
}

function createCollection() {
  $q.dialog({
    title: locale.language === 'ja' ? 'コレクションProjectを追加' : 'Add Collection Project',
    message: locale.language === 'ja'
      ? 'FileMaker開発資産を整理するProject名を入力してください。'
      : 'Enter a Project name for organizing FileMaker assets.',
    prompt: {
      model: '',
      type: 'text',
      placeholder: locale.language === 'ja' ? '例：顧客管理システム' : 'Example: Customer System',
      isValid: (value) => value.trim().length > 0,
    },
    cancel: { label: locale.t('cancel'), flat: true },
    ok: { label: locale.language === 'ja' ? '追加する' : 'Add', color: 'primary' },
    persistent: true,
    class: 'vertex-dialog collection-create-dialog',
  }).onOk(async (name: string) => {
    const collection = { id: crypto.randomUUID(), name: name.trim(), count: 0, children: [] }
    try {
      await library.saveCollection(collection)
      openCollection(collection.id)
      $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'コレクションを追加しました' : 'Collection added' })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

async function loadRagDocuments() {
  ragLoading.value = true
  try {
    ragDocuments.value = await aiGateway.listRagDocuments()
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    ragLoading.value = false
  }
}

async function addRagDocument() {
  if (!ragTitle.value.trim() || !ragContent.value.trim() || ragLoading.value) return
  ragLoading.value = true
  try {
    const saved = await aiGateway.saveRagDocument({
      title: ragTitle.value.trim(),
      content: ragContent.value.trim(),
      sourceType: ragSourceType.value,
      tags: ragTags.value.trim(),
    })
    ragDocuments.value = [saved, ...ragDocuments.value.filter((document) => document.id !== saved.id)]
    ragTitle.value = ''
    ragContent.value = ''
    ragTags.value = ''
    $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'RAGドキュメントを追加しました' : 'RAG document added' })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    ragLoading.value = false
  }
}

function deleteRagDocument(document: RagDocument) {
  $q.dialog({
    title: locale.language === 'ja' ? 'RAGドキュメントを削除' : 'Delete RAG Document',
    message: `「${document.title}」${locale.language === 'ja' ? 'を削除しますか？' : ' will be deleted.'}`,
    cancel: { label: locale.t('cancel'), flat: true },
    ok: { label: locale.t('deleteAction'), color: 'negative' },
    persistent: true,
    class: 'vertex-dialog',
  }).onOk(async () => {
    try {
      await aiGateway.deleteRagDocument(document.id)
      ragDocuments.value = ragDocuments.value.filter((candidate) => candidate.id !== document.id)
      $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'RAGドキュメントを削除しました' : 'RAG document deleted' })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

async function openLibraryItem(id: string) {
  if (openingLibraryItemId.value) return
  openingLibraryItemId.value = id

  try {
    const source = clipboard.libraryItems.find((item) => item.id === id)
    if (!source) throw new Error(`Library item not found: ${id}`)

    const tags = [...source.tags]
    const item = await clipboard.upsert({
      id: source.id,
      name: source.name,
      format: source.format,
      windowsFormat: source.windowsFormat,
      objectType: source.objectType,
      xml: source.xml,
      notes: source.notes,
      favorite: source.favorite,
      inLibrary: true,
      inHistory: true,
    })

    item.tags = tags
    const historyIndex = clipboard.items.findIndex((candidate) => candidate.id === item.id)
    if (historyIndex >= 0) clipboard.items.splice(historyIndex, 1)
    clipboard.items.unshift(item)

    const libraryIndex = clipboard.libraryItems.findIndex((candidate) => candidate.id === item.id)
    if (libraryIndex >= 0) clipboard.libraryItems[libraryIndex] = { ...item, tags }

    const displayXml = formatXmlForDisplay(item.xml)
    editor.content = displayXml
    editor.savedContent = displayXml
    editor.activeTab = 'xml'
    navigation.setActive('clipboard')

    await Promise.all([
      editor.validate(item.format),
      editor.buildPreview(),
    ])
    $q.notify({ type: 'positive', message: locale.t('libraryItemOpened') })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    openingLibraryItemId.value = ''
  }
}

type DeleteScope = 'library' | 'clipboard' | 'all'

function confirmDeletion(scope: DeleteScope) {
  const labels = {
    library: locale.t('deleteLibrary'),
    clipboard: locale.t('deleteClipboard'),
    all: locale.t('deleteAll'),
  }
  const count = scope === 'library'
    ? clipboard.libraryItems.length
    : scope === 'clipboard'
      ? clipboard.items.filter((item) => item.inHistory).length
      : clipboard.libraryItems.length + clipboard.items.length
  const preserveNotice = scope === 'clipboard'
    ? locale.language === 'ja' ? ' お気に入りは残ります。' : ' Favorites will remain.'
    : ''
  const message = locale.language === 'ja'
    ? `${labels[scope]}を実行します。対象は${count}件です。この操作は取り消せません。${preserveNotice}`
    : `${labels[scope]} will remove ${count} item(s). This action cannot be undone.${preserveNotice}`

  $q.dialog({
    title: locale.t('deleteConfirmTitle'),
    message,
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: { label: locale.t('deleteAction'), color: 'negative', unelevated: true },
  }).onOk(async () => {
    try {
      if (scope === 'all') {
        await clipboard.clearAll()
        await library.clearCollections()
        collectionWorkspace.clear()
      } else if (scope === 'library') {
        await clipboard.clearLibrary()
        await library.clearCollections()
        collectionWorkspace.clear()
      } else {
        await clipboard.clearClipboard()
      }
      if (scope === 'clipboard' || scope === 'all') {
        editor.content = ''
        editor.savedContent = ''
        editor.activeTab = 'xml'
      }
      $q.notify({ type: 'positive', message: locale.t('deleteCompleted') })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

async function checkCodexConnection() {
  if (!isTauriRuntime()) {
    $q.notify({ type: 'warning', icon: 'smart_toy', message: '接続確認はデスクトップアプリで実行してください' })
    return
  }
  credentialBusy.value = true
  try {
    connectionTest.value = await aiGateway.testProviderConnection(settings.codexIntegration)
    await ai.refreshProviders()
    $q.notify({
      type: connectionTest.value.success ? 'positive' : 'negative',
      icon: connectionTest.value.success ? 'cloud_done' : 'cloud_off',
      message: connectionTest.value.detail,
      caption: connectionTest.value.requestId ? `Request ID: ${connectionTest.value.requestId}` : undefined,
    })
  } catch (error) {
    connectionTest.value = {
      provider: settings.codexIntegration,
      success: false,
      detail: String(error),
      requestId: null,
    }
    $q.notify({ type: 'negative', icon: 'cloud_off', message: String(error) })
  } finally {
    credentialBusy.value = false
  }
}

async function saveOpenAiApiKey() {
  if (!openAiApiKey.value.trim() || credentialBusy.value) return
  credentialBusy.value = true
  try {
    await aiGateway.saveOpenAiApiKey(openAiApiKey.value)
    openAiApiKey.value = ''
    settings.codexAuthMethod = 'api-key'
    settings.codexCredentialStore = 'keyring'
    connectionTest.value = null
    await ai.refreshProviders()
    $q.notify({ type: 'positive', icon: 'verified_user', message: 'APIキーをWindows保護ストレージへ保存しました' })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    credentialBusy.value = false
  }
}

function confirmOpenAiApiKeyDeletion() {
  $q.dialog({
    title: '保存済みAPIキーを削除しますか？',
    message: 'Windows保護ストレージに保存したOpenAI APIキーを削除します。環境変数は変更しません。',
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: { label: 'APIキーを削除', color: 'negative', unelevated: true },
  }).onOk(async () => {
    credentialBusy.value = true
    try {
      const deleted = await aiGateway.deleteOpenAiApiKey()
      connectionTest.value = null
      await ai.refreshProviders()
      $q.notify({
        type: deleted ? 'positive' : 'info',
        message: deleted ? '保存済みAPIキーを削除しました' : '保存済みAPIキーはありません',
      })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    } finally {
      credentialBusy.value = false
    }
  })
}
</script>

<template>
  <main class="module-workspace">
    <header class="module-header">
      <div class="module-icon"><span class="material-icons">{{ heading.icon }}</span></div>
      <div class="module-header-copy">
        <span class="module-header-eyebrow">{{ heading.eyebrow }}</span>
        <h1>{{ heading.title }}</h1>
        <p>{{ heading.description }}</p>
      </div>
    </header>

    <section v-if="mode === 'library'" class="module-body library-workspace">
      <div class="module-toolbar">
        <label><span class="material-icons">search</span><input v-model="libraryQuery" type="search" :placeholder="locale.t('searchLibrary')" /></label>
        <button type="button" @click="librarySort = librarySort === 'recent' ? 'name' : 'recent'"><span class="material-icons">sort</span>{{ librarySort === 'recent' ? locale.t('sortRecent') : (locale.language === 'ja' ? '名前順' : 'Name') }}</button>
      </div>
      <div class="library-grid">
        <div v-if="visibleLibraryItems.length === 0" class="library-empty">
          <span class="material-icons">inventory_2</span>
          <p>{{ libraryQuery ? (locale.language === 'ja' ? '一致する項目がありません' : 'No matching items') : locale.t('noItems') }}</p>
        </div>
        <article
          v-for="item in visibleLibraryItems"
          :key="item.id"
          class="library-card"
          :class="{ opening: openingLibraryItemId === item.id }"
          role="button"
          tabindex="0"
          :aria-busy="openingLibraryItemId === item.id"
          @click="openLibraryItem(item.id)"
          @keydown.enter.prevent="openLibraryItem(item.id)"
          @keydown.space.prevent="openLibraryItem(item.id)"
        >
          <div class="library-format">{{ item.format }}</div>
          <button
            class="library-star"
            :class="{ active: item.favorite }"
            type="button"
            :aria-label="item.favorite ? locale.t('removeFavorite') : locale.t('addFavorite')"
            @click.stop="clipboard.toggleFavorite(item.id)"
          >
            <span class="material-icons">{{ item.favorite ? 'star' : 'star_border' }}</span>
          </button>
          <strong>{{ item.name }}</strong>
          <small>{{ item.objectType }} · {{ item.windowsFormat }}</small>
          <div><span v-for="tag in item.tags" :key="tag">{{ tag }}</span></div>
        </article>
      </div>
    </section>

    <section v-else-if="mode === 'collections'" class="module-body collections-workspace">
      <div class="module-toolbar">
        <strong>{{ library.collections.length }} {{ locale.t('projectCollections') }}</strong>
        <button type="button" @click="createCollection"><span class="material-icons">create_new_folder</span>{{ locale.t('newCollection') }}</button>
      </div>
      <div class="collection-board">
        <article v-for="collection in library.collections" :key="collection.id" class="collection-board-card" role="button" tabindex="0" @click="openCollection(collection.id)" @keydown.enter.prevent="openCollection(collection.id)">
          <header><span class="material-icons">folder_open</span><strong>{{ collection.name }}</strong><em>{{ collectionItemCount(collection.id) }}</em></header>
          <div v-for="child in collection.children" :key="child.id">
            <span class="material-icons">folder</span><span>{{ child.name }}</span><em>{{ child.count }}</em>
          </div>
        </article>
      </div>
    </section>

    <section v-else-if="mode === 'tools'" class="module-body tools-grid">
      <article v-for="tool in tools" :key="tool.name" class="tool-card" :class="{ planned: tool.planned }" :role="tool.planned ? undefined : 'button'" :tabindex="tool.planned ? -1 : 0" @click="openTool(tool.name)" @keydown.enter.prevent="openTool(tool.name)">
        <span class="material-icons">{{ tool.icon }}</span>
        <div class="tool-card-copy">
          <strong>{{ tool.name }}</strong>
          <div class="tool-description">
            <span>{{ locale.t('descriptionLabel') }}</span>
            <p>{{ tool.detail }}</p>
          </div>
        </div>
        <small>{{ tool.state }}</small>
      </article>
    </section>

    <section v-else class="module-body settings-workspace">
      <nav class="settings-subnav" :aria-label="locale.t('navSettings')">
        <button type="button" :class="{ active: settingsSection === 'general' }" @click="settingsSection = 'general'"><span class="settings-tab-content"><span class="material-icons">tune</span><span>{{ locale.t('settingsGeneralTab') }}</span></span></button>
        <button type="button" :class="{ active: settingsSection === 'codex' }" @click="settingsSection = 'codex'; loadRagDocuments()"><span class="settings-tab-content"><span class="material-icons">smart_toy</span><span>{{ locale.t('settingsCodexTab') }}</span></span></button>
        <button type="button" :class="{ active: settingsSection === 'data' }" @click="settingsSection = 'data'"><span class="settings-tab-content"><span class="material-icons">database</span><span>{{ locale.t('settingsDataTab') }}</span></span></button>
      </nav>

      <Transition name="settings-slide" mode="out-in">
        <div v-if="settingsSection === 'general'" key="general" class="settings-page general-settings-page">
          <div class="settings-group appearance-settings">
            <span>{{ locale.t('appearanceSettings') }}</span>
            <div class="theme-picker-heading">
              <div><strong>{{ locale.t('colorTheme') }}</strong><small>{{ locale.t('colorThemeHelp') }}</small></div>
              <div class="theme-picker-actions">
                <label class="cursor-theme-toggle">
                  <span class="material-icons" aria-hidden="true">mouse</span>
                  <span class="cursor-theme-toggle-copy">
                    <strong>{{ locale.language === 'ja' ? 'テーマ連動カーソル' : 'Theme cursor' }}</strong>
                    <small>{{ settings.customCursor ? (locale.language === 'ja' ? 'テーマ色を使用' : 'Uses theme color') : (locale.language === 'ja' ? 'Windows標準' : 'System default') }}</small>
                  </span>
                  <input
                    v-model="settings.customCursor"
                    type="checkbox"
                    role="switch"
                    :aria-label="locale.language === 'ja' ? 'テーマ連動カーソル' : 'Theme cursor'"
                  />
                </label>
                <em>{{ appThemes.length }} THEMES</em>
              </div>
            </div>
            <div class="theme-grid" role="radiogroup" :aria-label="locale.t('colorTheme')">
              <button
                v-for="themeOption in appThemes"
                :key="themeOption.id"
                type="button"
                class="theme-card"
                :class="{ active: settings.theme === themeOption.id }"
                role="radio"
                :aria-checked="settings.theme === themeOption.id"
                @click="settings.theme = themeOption.id"
              >
                <span class="theme-swatch" aria-hidden="true">
                  <i v-for="color in themeOption.colors" :key="color" :style="{ backgroundColor: color }" />
                </span>
                <span class="theme-card-copy">
                  <strong>{{ locale.language === 'ja' ? themeOption.nameJa : themeOption.nameEn }}</strong>
                  <small>{{ locale.language === 'ja' ? themeOption.descriptionJa : themeOption.descriptionEn }}</small>
                </span>
                <span v-if="settings.theme === themeOption.id" class="material-icons theme-selected">check_circle</span>
              </button>
            </div>
          </div>
          <div class="settings-group">
            <span>{{ locale.t('editorSettings') }}</span>
            <label><div><strong>{{ locale.t('monacoFontSize') }}</strong><small>{{ locale.t('monacoFontSizeHelp') }}</small></div><input v-model.number="settings.fontSize" type="number" min="10" max="24" /></label>
            <label><div><strong>{{ locale.t('minimap') }}</strong><small>{{ locale.t('minimapHelp') }}</small></div><input v-model="settings.minimap" type="checkbox" role="switch" :aria-label="locale.t('minimap')" /></label>
          </div>
          <div class="settings-group">
            <span>{{ locale.t('fileMakerSettings') }}</span>
            <label><div><strong>{{ locale.t('defaultVersion') }}</strong><small>{{ locale.t('defaultVersionHelp') }}</small></div><select v-model="settings.fileMakerVersion"><option>26.0</option><option>25.0</option><option>24.0</option></select></label>
            <label><div><strong>{{ locale.t('clipboardPolling') }}</strong><small>{{ locale.t('clipboardPollingHelp') }}</small></div><input v-model="settings.polling" type="checkbox" role="switch" :aria-label="locale.t('clipboardPolling')" /></label>
          </div>
          <div class="settings-group">
            <span>{{ locale.t('languageSettings') }}</span>
            <label>
              <div><strong>{{ locale.t('language') }}</strong><small>{{ locale.t('languageHelp') }}</small></div>
              <select v-model="locale.language" :aria-label="locale.t('language')">
                <option value="ja">{{ locale.t('japanese') }}</option>
                <option value="en">{{ locale.t('english') }}</option>
              </select>
            </label>
          </div>
        </div>

        <div v-else-if="settingsSection === 'codex'" key="codex" class="settings-page codex-settings-page">
          <div class="settings-group codex-settings-group">
            <span>{{ locale.t('codexSettings') }}</span>
            <div class="codex-settings-intro">
              <div class="codex-settings-icon"><span class="material-icons">smart_toy</span></div>
              <div>
                <strong>{{ locale.t('codexConnectionTitle') }}</strong>
                <small>{{ locale.t('codexConnectionHelp') }}</small>
              </div>
              <em :class="{ online: selectedProviderStatus?.authenticated, failed: connectionTest && !connectionTest.success }"><i />{{ providerStatusLabel }}</em>
            </div>
            <div class="codex-settings-grid">
              <label>
                <div><strong>{{ locale.t('codexIntegrationMethod') }}</strong><small>{{ locale.t('codexIntegrationMethodHelp') }}</small></div>
                <select v-model="settings.codexIntegration" :aria-label="locale.t('codexIntegrationMethod')"><option value="openai">OpenAI Responses API</option><option value="codex">Codex App Server（Phase 2）</option></select>
              </label>
              <label>
                <div><strong>AI Model</strong><small>AI Assistantで使用するモデル</small></div>
                <select v-model="settings.codexModel" aria-label="AI Model"><option value="gpt-5.6-terra">gpt-5.6-terra</option><option value="gpt-5.6-sol">gpt-5.6-sol</option></select>
              </label>
              <label>
                <div><strong>{{ locale.t('codexAuthMethod') }}</strong><small>{{ locale.t('codexAuthMethodHelp') }}</small></div>
                <select v-model="settings.codexAuthMethod" :aria-label="locale.t('codexAuthMethod')"><option value="api-key">{{ locale.t('signInWithApiKey') }}</option><option value="chatgpt" disabled>{{ locale.t('signInWithChatGpt') }}（Phase 2）</option></select>
              </label>
              <label>
                <div><strong>{{ locale.t('codexCredentialStore') }}</strong><small>{{ locale.t('codexCredentialStoreHelp') }}</small></div>
                <select v-model="settings.codexCredentialStore" :aria-label="locale.t('codexCredentialStore')"><option value="keyring">Windows保護ストレージ（推奨）</option><option value="environment">起動環境（OPENAI_API_KEY）</option><option value="auto">{{ locale.t('credentialStoreAuto') }}</option></select>
              </label>
              <label>
                <div><strong>{{ locale.t('codexRagSetting') }}</strong><small>{{ locale.t('codexRagSettingHelp') }}</small></div>
                <input v-model="settings.codexRagEnabled" type="checkbox" role="switch" :aria-label="locale.t('codexRagSetting')" />
              </label>
              <label>
                <div><strong>{{ locale.t('codexDiffReview') }}</strong><small>{{ locale.t('codexDiffReviewHelp') }}</small></div>
                <input v-model="settings.codexRequireDiffReview" type="checkbox" role="switch" :aria-label="locale.t('codexDiffReview')" />
              </label>
            </div>
            <div v-if="settings.codexIntegration === 'openai'" class="api-key-settings">
              <div class="api-key-copy">
                <strong>OpenAI APIキー</strong>
                <small>APIキーは現在のWindowsユーザーだけが復号できます。画面・SQLite・localStorageには保存しません。</small>
              </div>
              <label class="api-key-entry">
                <span class="material-icons">key</span>
                <input v-model="openAiApiKey" type="password" autocomplete="new-password" spellcheck="false" placeholder="sk-…" aria-label="OpenAI APIキー" @keyup.enter="saveOpenAiApiKey" />
              </label>
              <button type="button" :disabled="!openAiApiKey.trim() || credentialBusy || !isTauriRuntime()" @click="saveOpenAiApiKey"><span class="material-icons">security</span>安全に保存</button>
              <button class="delete-credential" type="button" :disabled="credentialBusy || !selectedProviderStatus?.authenticated || !isTauriRuntime()" @click="confirmOpenAiApiKeyDeletion"><span class="material-icons">delete_outline</span>保存キーを削除</button>
            </div>
            <div class="codex-setup-guide">
              <strong>{{ locale.t('codexSetupProcedure') }}</strong>
              <ol>
                <li><span>1</span><div><strong>{{ locale.t('codexSetupRuntime') }}</strong><small>{{ locale.t('codexSetupRuntimeHelp') }}</small></div></li>
                <li><span>2</span><div><strong>{{ locale.t('codexSetupLogin') }}</strong><small>{{ locale.t('codexSetupLoginHelp') }}</small></div></li>
                <li><span>3</span><div><strong>{{ locale.t('codexSetupConnect') }}</strong><small>{{ locale.t('codexSetupConnectHelp') }}</small></div></li>
              </ol>
              <p><span class="material-icons">shield</span>{{ locale.t('codexSecretNotice') }}</p>
            </div>
            <div class="codex-settings-actions">
              <span :class="{ online: connectionTest?.success, failed: connectionTest && !connectionTest.success }"><i />{{ connectionTest?.detail ?? selectedProviderStatus?.detail ?? locale.t('codexConnectionPending') }}</span>
              <button type="button" :disabled="credentialBusy" @click="checkCodexConnection"><span class="material-icons">{{ credentialBusy ? 'hourglass_top' : 'sync' }}</span>{{ credentialBusy ? '確認中…' : locale.t('checkConnection') }}</button>
            </div>
            <div class="rag-management">
              <div class="rag-management-heading">
                <div><strong>SQLite RAG</strong><small>{{ locale.language === 'ja' ? 'FileMaker仕様・専門ルールをAIの参照情報として管理します。' : 'Manage FileMaker specifications and rules used by AI.' }}</small></div>
                <span>{{ ragDocuments.length }} {{ locale.language === 'ja' ? '件' : 'documents' }}</span>
              </div>
              <div class="rag-entry-grid">
                <input v-model="ragTitle" type="text" :placeholder="locale.language === 'ja' ? 'タイトル' : 'Title'" />
                <select v-model="ragSourceType" aria-label="RAG source type"><option value="filemaker-spec">FileMaker Spec</option><option value="vertex-rule">Vertex Rule</option><option value="project-rule">Project Rule</option></select>
                <input v-model="ragTags" type="text" :placeholder="locale.language === 'ja' ? 'タグ（空白区切り）' : 'Tags'" />
                <textarea v-model="ragContent" rows="3" :placeholder="locale.language === 'ja' ? 'FileMaker仕様やルールの本文' : 'Specification or rule content'" />
                <button type="button" :disabled="ragLoading || !ragTitle.trim() || !ragContent.trim()" @click="addRagDocument"><span class="material-icons">add</span>{{ locale.language === 'ja' ? 'RAGへ追加' : 'Add to RAG' }}</button>
              </div>
              <div class="rag-document-list">
                <div v-for="document in ragDocuments" :key="document.id" class="rag-document-row">
                  <span class="material-icons">description</span>
                  <div><strong>{{ document.title }}</strong><small>{{ document.sourceType }} · {{ document.tags || '—' }}</small></div>
                  <button type="button" :aria-label="`${document.title}を削除`" @click="deleteRagDocument(document)"><span class="material-icons">delete_outline</span></button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div v-else key="data" class="settings-page data-settings-page">
          <div class="settings-group danger-settings">
            <span>{{ locale.t('dataManagement') }}</span>
            <div class="danger-settings-intro"><strong>{{ locale.t('deleteStoredData') }}</strong><small>{{ locale.t('deleteStoredDataHelp') }}</small></div>
            <div class="delete-setting-row"><div><strong>{{ locale.t('deleteLibrary') }}</strong><small>{{ locale.t('deleteLibraryHelp') }}</small></div><button type="button" @click="confirmDeletion('library')">{{ locale.t('deleteLibrary') }}</button></div>
            <div class="delete-setting-row"><div><strong>{{ locale.t('deleteClipboard') }}</strong><small>{{ locale.t('deleteClipboardHelp') }}</small></div><button type="button" @click="confirmDeletion('clipboard')">{{ locale.t('deleteClipboard') }}</button></div>
            <div class="delete-setting-row critical"><div><strong>{{ locale.t('deleteAll') }}</strong><small>{{ locale.t('deleteAllHelp') }}</small></div><button type="button" @click="confirmDeletion('all')">{{ locale.t('deleteAll') }}</button></div>
          </div>
        </div>
      </Transition>
    </section>
  </main>
</template>

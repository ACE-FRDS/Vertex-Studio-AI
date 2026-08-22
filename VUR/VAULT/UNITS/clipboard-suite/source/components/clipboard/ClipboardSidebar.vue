<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { useQuasar } from 'quasar'
import { useClipboardStore } from '../../stores/clipboard'
import { createDefaultCollection, useLibraryStore } from '../../stores/library'
import { useLocaleStore } from '../../stores/locale'
import { useEditorStore } from '../../stores/editor'
import { useNavigationStore } from '../../stores/navigation'
import {
  collectionCategories,
  collectionCategoryForItem,
  type CollectionCategoryId,
  useCollectionWorkspaceStore,
} from '../../stores/collectionWorkspace'
import { formatXmlForDisplay } from '../../utils/xmlFormat'
import { clipboardObjectMultiplicity } from '../../utils/clipboardItemNaming'
import type { ClipboardItem } from '../../types/clipboard'

const clipboard = useClipboardStore()
const library = useLibraryStore()
const locale = useLocaleStore()
const editor = useEditorStore()
const navigation = useNavigationStore()
const collectionWorkspace = useCollectionWorkspaceStore()
const $q = useQuasar()
type SidebarView = 'history' | 'collections' | 'favorites'
const clipboardSubview = ref<Exclude<SidebarView, 'collections'>>('history')
const activeView = computed({
  get: (): SidebarView => navigation.active === 'collections' ? 'collections' : clipboardSubview.value,
  set: (view: SidebarView) => {
    if (view === 'collections') navigation.setActive('collections')
    else {
      clipboardSubview.value = view
      navigation.setActive('clipboard')
    }
  },
})
const editingTitleId = ref('')
const titleDraft = ref('')
const historyDeleteBusy = ref(false)
const cardDeleteBusyId = ref('')
const librarySavingId = ref('')
const draggingHistoryId = ref('')
const dragTargetId = ref('')
const dragPlacement = ref<'before' | 'after'>('before')
const suppressHistoryClick = ref(false)
const expandedCollectionIds = ref(new Set(library.collections.map((collection) => collection.id)))
let pendingHistoryDragId = ''
let historyDragPointerId: number | null = null
let historyDragStartX = 0
let historyDragStartY = 0

function itemsInSelectedProject(items: ClipboardItem[]) {
  const projectId = collectionWorkspace.selectedProject?.id
  if (!projectId) return items
  return items.filter((item) => collectionWorkspace.projectIdForItem(item.id) === projectId)
}

const displayedItems = computed(() => itemsInSelectedProject(
  activeView.value === 'favorites' ? clipboard.favorites : clipboard.filteredItems,
))
const historyCount = computed(() => itemsInSelectedProject(
  clipboard.items.filter((item) => item.inHistory),
).length)
const canReorderHistory = computed(() => activeView.value === 'history' && !clipboard.filter.trim())
const selectedProjectId = computed(() => collectionWorkspace.selectedProject?.id ?? '')

function projectItems(projectId: string) {
  return clipboard.items.filter(
    (item) => item.inHistory && collectionWorkspace.projectIdForItem(item.id) === projectId,
  )
}

function categoryCount(projectId: string, categoryId: CollectionCategoryId) {
  const items = projectItems(projectId)
  if (categoryId === 'all') return items.length
  return items.filter((item) => collectionCategoryForItem(item) === categoryId).length
}

function categoryLabel(category: (typeof collectionCategories)[number]) {
  return locale.language === 'ja' ? category.labelJa : category.labelEn
}

function selectCollectionProject(projectId: string) {
  collectionWorkspace.selectProject(projectId)
  collectionWorkspace.selectCategory('all')
  if (expandedCollectionIds.value.has(projectId)) expandedCollectionIds.value.delete(projectId)
  else expandedCollectionIds.value.add(projectId)
}

function isCollectionExpanded(projectId: string) {
  return expandedCollectionIds.value.has(projectId)
}

function selectCollectionCategory(projectId: string, categoryId: CollectionCategoryId) {
  collectionWorkspace.selectProject(projectId)
  collectionWorkspace.selectCategory(categoryId)
}

function selectClipboardProject(event: Event) {
  const projectId = (event.target as HTMLSelectElement).value
  collectionWorkspace.selectProject(projectId)
}

function createCollectionProject() {
  $q.dialog({
    dark: true,
    title: locale.language === 'ja' ? 'コレクションProjectを追加' : 'Add Collection Project',
    message: locale.language === 'ja'
      ? 'FileMaker開発資産を整理するProject名を入力してください。'
      : 'Enter a project name for organizing FileMaker assets.',
    prompt: {
      model: '',
      type: 'text',
      maxlength: 80,
      isValid: (value) => Boolean(value.trim()),
      autocomplete: 'off',
      placeholder: locale.language === 'ja' ? '例：顧客管理システム' : 'Example: CRM System',
    },
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: {
      label: locale.language === 'ja' ? '追加する' : 'Add',
      color: 'primary',
      unelevated: true,
    },
  }).onOk(async (value: string) => {
    const name = value.trim()
    if (!name) return
    const duplicate = library.collections.some(
      (collection) => collection.name.toLocaleLowerCase() === name.toLocaleLowerCase(),
    )
    if (duplicate) {
      $q.notify({
        type: 'warning',
        message: locale.language === 'ja'
          ? '同じ名前のコレクションProjectが既にあります'
          : 'A collection project with this name already exists',
      })
      return
    }

    const project = {
      id: `collection-${crypto.randomUUID()}`,
      name,
      count: 0,
      children: [],
    }
    try {
      await library.saveCollection(project)
      expandedCollectionIds.value.add(project.id)
      collectionWorkspace.selectProject(project.id)
      collectionWorkspace.selectCategory('all')
      $q.notify({
        type: 'positive',
        message: locale.language === 'ja'
          ? `「${name}」を追加しました`
          : `Added “${name}”`,
      })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

function confirmSelectedCollectionDeletion() {
  const project = collectionWorkspace.selectedProject
  if (!project) return
  const itemCount = projectItems(project.id).length
  const remainingProject = library.collections.find((collection) => collection.id !== project.id)
  const destinationName = remainingProject?.name ?? 'Default'

  $q.dialog({
    dark: true,
    title: locale.language === 'ja' ? 'コレクションProjectを削除' : 'Delete Collection Project',
    message: locale.language === 'ja'
      ? `「${project.name}」を削除します。${itemCount > 0 ? `履歴${itemCount}件は「${destinationName}」へ移動し、削除されません。` : '履歴アイテムは削除されません。'}`
      : `Delete “${project.name}”. ${itemCount > 0 ? `${itemCount} history item(s) will be moved to “${destinationName}” and will not be deleted.` : 'History items will not be deleted.'}`,
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: {
      label: locale.language === 'ja' ? '削除する' : 'Delete',
      color: 'negative',
      unelevated: true,
    },
  }).onOk(async () => {
    try {
      let fallback = remainingProject
      if (!fallback && project.id === 'default') {
        fallback = { ...project, name: 'Default', count: 0, children: [] }
        await library.saveCollection(fallback)
      } else {
        if (!fallback) {
          fallback = createDefaultCollection()
          await library.saveCollection(fallback)
          expandedCollectionIds.value.add(fallback.id)
        }
        await library.deleteCollection(project.id, fallback.id)
        expandedCollectionIds.value.delete(project.id)
      }

      for (const [itemId, projectId] of Object.entries(collectionWorkspace.itemProjectIds)) {
        if (projectId === project.id) collectionWorkspace.itemProjectIds[itemId] = fallback.id
      }
      collectionWorkspace.selectProject(fallback.id)
      collectionWorkspace.selectCategory('all')
      $q.notify({
        type: 'positive',
        message: locale.language === 'ja'
          ? `「${project.name}」を削除しました`
          : `Deleted “${project.name}”`,
      })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

const groups = computed(() => {
  const grouped = new Map<string, ClipboardItem[]>()
  for (const item of displayedItems.value) {
    const created = new Date(item.createdAt)
    const today = new Date()
    const dayDiff = Math.floor(
      (new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() -
        new Date(created.getFullYear(), created.getMonth(), created.getDate()).getTime()) /
        86_400_000,
    )
    const label = dayDiff === 0 ? locale.t('today') : dayDiff === 1 ? locale.t('yesterday') : locale.t('earlier')
    if (!grouped.has(label)) grouped.set(label, [])
    grouped.get(label)?.push(item)
  }
  return [...grouped.entries()]
})

function timeLabel(iso: string) {
  return new Intl.DateTimeFormat(locale.language === 'ja' ? 'ja-JP' : 'en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(new Date(iso))
}

function objectTypeLabel(item: ClipboardItem) {
  const multiplicity = clipboardObjectMultiplicity(item.xml)
  if (item.format === 'XMTB' && multiplicity.tableCount > 1) return locale.t('multipleTables')
  if (item.format === 'XMSC' && multiplicity.scriptCount > 1) return locale.t('multipleScripts')
  return item.objectType
}

async function openHistoryItem(item: ClipboardItem) {
  if (editingTitleId.value === item.id || draggingHistoryId.value || suppressHistoryClick.value) return
  await activateHistoryItem(item)
}

async function activateHistoryItem(item: ClipboardItem) {
  clipboard.select(item.id)
  const displayXml = formatXmlForDisplay(item.xml)
  editor.content = displayXml
  editor.savedContent = displayXml
  editor.activeTab = 'xml'
  try {
    await Promise.all([
      editor.validate(item.format),
      editor.buildPreview(),
    ])
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  }
}

function startHistoryPointer(item: ClipboardItem, event: PointerEvent) {
  const origin = event.target as HTMLElement | null
  if (event.button !== 0 || !canReorderHistory.value || origin?.closest('button, input, textarea, [contenteditable="true"]')) return
  pendingHistoryDragId = item.id
  historyDragPointerId = event.pointerId
  historyDragStartX = event.clientX
  historyDragStartY = event.clientY
  dragTargetId.value = ''
  ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
}

function moveHistoryPointer(event: PointerEvent) {
  if (!pendingHistoryDragId || historyDragPointerId !== event.pointerId) return
  if (!draggingHistoryId.value) {
    const distance = Math.hypot(event.clientX - historyDragStartX, event.clientY - historyDragStartY)
    if (distance < 6) return
    draggingHistoryId.value = pendingHistoryDragId
    document.body.classList.add('is-dragging-history')
  }

  event.preventDefault()
  const pointed = document.elementFromPoint(event.clientX, event.clientY) as HTMLElement | null
  const card = pointed?.closest<HTMLElement>('.history-card[data-item-id]')
  const targetId = card?.dataset.itemId ?? ''
  if (!card || !targetId || targetId === draggingHistoryId.value) {
    dragTargetId.value = ''
    return
  }
  const bounds = card.getBoundingClientRect()
  updateHistoryDropIndicator(
    targetId,
    event.clientY < bounds.top + bounds.height / 2 ? 'before' : 'after',
  )
}

function updateHistoryDropIndicator(targetId: string, placement: 'before' | 'after') {
  const order = displayedItems.value.filter((item) => item.inHistory)
  const sourceIndex = order.findIndex((item) => item.id === draggingHistoryId.value)
  if (sourceIndex < 0) {
    dragTargetId.value = ''
    return
  }

  const orderWithoutSource = order.filter((item) => item.id !== draggingHistoryId.value)
  const targetIndex = orderWithoutSource.findIndex((item) => item.id === targetId)
  if (targetIndex < 0) {
    dragTargetId.value = ''
    return
  }

  const insertionIndex = targetIndex + (placement === 'after' ? 1 : 0)
  if (insertionIndex === sourceIndex) {
    dragTargetId.value = ''
    return
  }

  if (insertionIndex >= orderWithoutSource.length) {
    dragTargetId.value = orderWithoutSource.at(-1)?.id ?? ''
    dragPlacement.value = 'after'
    return
  }

  dragTargetId.value = orderWithoutSource[insertionIndex]?.id ?? ''
  dragPlacement.value = 'before'
}

function reorderHistoryItems(sourceId: string, targetId: string, placement: 'before' | 'after') {
  if (sourceId && targetId && sourceId !== targetId) {
    const sourceIndex = clipboard.items.findIndex(
      (candidate) => candidate.id === sourceId && candidate.inHistory,
    )
    if (sourceIndex >= 0) {
      const [moved] = clipboard.items.splice(sourceIndex, 1)
      const targetIndex = clipboard.items.findIndex((candidate) => candidate.id === targetId)
      if (moved && targetIndex >= 0) {
        clipboard.items.splice(targetIndex + (placement === 'after' ? 1 : 0), 0, moved)
        localStorage.setItem(
          'vertex.historyOrder',
          JSON.stringify(clipboard.items.filter((candidate) => candidate.inHistory).map((candidate) => candidate.id)),
        )
      }
    }
  }
}

async function finishHistoryPointer(event: PointerEvent) {
  if (historyDragPointerId !== event.pointerId) return
  const card = event.currentTarget as HTMLElement
  if (card.hasPointerCapture(event.pointerId)) card.releasePointerCapture(event.pointerId)
  const moved = Boolean(draggingHistoryId.value)
  const movedItem = moved
    ? clipboard.items.find((item) => item.id === draggingHistoryId.value)
    : undefined
  if (moved) {
    reorderHistoryItems(draggingHistoryId.value, dragTargetId.value, dragPlacement.value)
    suppressHistoryClick.value = true
    window.setTimeout(() => { suppressHistoryClick.value = false }, 0)
  }
  finishHistoryDrag()
  if (movedItem) await activateHistoryItem(movedItem)
}

function cancelHistoryPointer(event: PointerEvent) {
  if (historyDragPointerId !== event.pointerId) return
  const card = event.currentTarget as HTMLElement
  if (card.hasPointerCapture(event.pointerId)) card.releasePointerCapture(event.pointerId)
  finishHistoryDrag()
}

function finishHistoryDrag() {
  document.body.classList.remove('is-dragging-history')
  draggingHistoryId.value = ''
  dragTargetId.value = ''
  dragPlacement.value = 'before'
  pendingHistoryDragId = ''
  historyDragPointerId = null
}

async function saveToLibrary(item: ClipboardItem) {
  if (librarySavingId.value) return
  librarySavingId.value = item.id
  try {
    const tags = [...item.tags]
    const saved = await clipboard.upsert({
      id: item.id,
      name: item.name,
      format: item.format,
      windowsFormat: item.windowsFormat,
      objectType: item.objectType,
      xml: item.xml,
      notes: item.notes,
      favorite: item.favorite,
      inLibrary: true,
      inHistory: item.inHistory ?? true,
    }, { select: false })
    await collectionWorkspace.assignItemToProject(saved.id)
    saved.tags = tags
    const libraryIndex = clipboard.libraryItems.findIndex((candidate) => candidate.id === saved.id)
    if (libraryIndex >= 0) clipboard.libraryItems[libraryIndex] = { ...saved, tags }
    $q.notify({
      type: 'positive',
      message: locale.t('savedToLibrary') || (locale.language === 'ja' ? 'ライブラリに保存しました' : 'Saved to the library'),
    })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    librarySavingId.value = ''
  }
}

function confirmCardDeletion(item: ClipboardItem) {
  if (cardDeleteBusyId.value) return
  const preservedLocations = [
    item.inLibrary ? (locale.language === 'ja' ? 'ライブラリ' : 'Library') : '',
    item.favorite ? (locale.language === 'ja' ? 'お気に入り' : 'Favorites') : '',
  ].filter(Boolean)
  const preserveMessage = preservedLocations.length > 0
    ? (locale.language === 'ja'
        ? `${preservedLocations.join('・')}に保存されている項目は残ります。`
        : `The item saved in ${preservedLocations.join(' and ')} will remain.`)
    : ''

  $q.dialog({
    dark: true,
    title: locale.language === 'ja' ? 'カードを削除' : 'Delete Card',
    message: locale.language === 'ja'
      ? `「${item.name}」をクリップボード履歴から削除します。この操作は取り消せません。${preserveMessage}`
      : `Delete “${item.name}” from Clipboard history? This action cannot be undone. ${preserveMessage}`,
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: {
      label: locale.language === 'ja' ? '削除する' : 'Delete',
      color: 'negative',
      unelevated: true,
    },
  }).onOk(async () => {
    cardDeleteBusyId.value = item.id
    const wasSelected = clipboard.selectedId === item.id
    try {
      cancelTitleEdit()
      await clipboard.removeFromHistory(item.id)
      if (!item.inLibrary && !item.favorite) delete collectionWorkspace.itemProjectIds[item.id]
      if (wasSelected && clipboard.selectedItem) await activateHistoryItem(clipboard.selectedItem)
      $q.notify({
        type: 'positive',
        message: locale.language === 'ja' ? 'カードを削除しました' : 'Card deleted',
      })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    } finally {
      cardDeleteBusyId.value = ''
    }
  })
}

async function startTitleEdit(item: ClipboardItem) {
  editingTitleId.value = item.id
  titleDraft.value = item.name
  await nextTick()
  const input = document.querySelector<HTMLInputElement>(
    `.card-title-editor[data-item-id="${CSS.escape(item.id)}"]`,
  )
  input?.focus()
  input?.select()
}

function cancelTitleEdit() {
  editingTitleId.value = ''
  titleDraft.value = ''
}

async function saveTitle(item: ClipboardItem) {
  if (editingTitleId.value !== item.id) return
  const name = titleDraft.value.trim()
  cancelTitleEdit()
  if (!name) {
    $q.notify({ type: 'warning', message: locale.t('cardTitleRequired') })
    return
  }
  if (name === item.name) return
  try {
    await clipboard.upsert({
      id: item.id,
      name,
      format: item.format,
      windowsFormat: item.windowsFormat,
      objectType: item.objectType,
      xml: item.xml,
      notes: item.notes,
      favorite: item.favorite,
      inLibrary: item.inLibrary,
      inHistory: item.inHistory,
    }, { select: false })
    $q.notify({ type: 'positive', message: locale.t('cardTitleUpdated') })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  }
}

function confirmHistoryDeletion() {
  const count = historyCount.value
  if (count === 0 || historyDeleteBusy.value) {
    $q.notify({ type: 'info', message: locale.t('historyEmpty') })
    return
  }

  const message = locale.language === 'ja'
    ? `クリップボード履歴${count}件を削除します。この操作は取り消せません。お気に入りとライブラリに保存済みの項目は残ります。`
    : `Delete ${count} Clipboard history item(s)? This action cannot be undone. Favorites and items saved to the library will remain.`

  $q.dialog({
    title: locale.t('deleteHistory'),
    message,
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: { label: locale.t('deleteAction'), color: 'negative', unelevated: true },
  }).onOk(async () => {
    historyDeleteBusy.value = true
    try {
      cancelTitleEdit()
      await clipboard.clearClipboard()
      $q.notify({ type: 'positive', message: locale.t('historyDeleteCompleted') })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    } finally {
      historyDeleteBusy.value = false
    }
  })
}
</script>

<template>
  <aside class="sidebar-panel">
    <div class="side-tabs">
      <button
        v-for="tab in ([
          ['history', 'history', locale.t('history')],
          ['collections', 'account_tree', locale.t('navCollections')],
          ['favorites', 'star_border', locale.t('favorites')],
        ] as const)"
        :key="tab[0]"
        :class="{ active: activeView === tab[0] }"
        :title="tab[2]"
        type="button"
        @click="activeView = tab[0]"
      >
        <span class="material-icons">{{ tab[1] }}</span>
        <small>{{ tab[2] }}</small>
      </button>
    </div>

    <section class="side-content">
      <div class="panel-heading">
        <div>
          <span class="eyebrow">{{ locale.t('navClipboard') }}</span>
          <h2>{{ activeView === 'collections' ? locale.t('navCollections') : activeView === 'favorites' ? locale.t('favorites') : locale.t('history') }}</h2>
        </div>
        <q-btn
          v-if="activeView === 'history'"
          flat
          dense
          round
          size="sm"
          icon="more_horiz"
          :aria-label="locale.t('historyMenu')"
        >
          <q-tooltip>{{ locale.t('historyMenu') }}</q-tooltip>
          <q-menu class="history-options-menu" anchor="bottom right" self="top right">
            <q-list>
              <q-item
                v-close-popup
                clickable
                class="history-delete-item"
                :disable="historyCount === 0 || historyDeleteBusy"
                @click="confirmHistoryDeletion"
              >
                <q-item-section avatar><q-icon name="delete_outline" /></q-item-section>
                <q-item-section>
                  <q-item-label>{{ locale.t('deleteHistory') }}</q-item-label>
                  <q-item-label caption>{{ locale.t('deleteHistoryHelp') }}</q-item-label>
                </q-item-section>
                <q-item-section side>{{ historyCount }}</q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-btn>
        <q-btn
          v-else-if="activeView === 'collections'"
          class="collection-add-button"
          flat
          dense
          round
          icon="add"
          :aria-label="locale.language === 'ja' ? 'コレクションProjectを追加' : 'Add collection project'"
          @click="createCollectionProject"
        >
          <q-tooltip>{{ locale.language === 'ja' ? 'コレクションProjectを追加' : 'Add collection project' }}</q-tooltip>
        </q-btn>
      </div>

      <div v-if="activeView !== 'collections'" class="clipboard-project-selector">
        <span class="clipboard-project-selector-icon material-icons">folder_open</span>
        <span class="clipboard-project-selector-copy">
          <small>{{ locale.language === 'ja' ? '選択中のコレクションProject' : 'Selected Collection Project' }}</small>
          <select
            :value="collectionWorkspace.selectedProjectId ?? ''"
            :aria-label="locale.language === 'ja' ? 'コレクションProjectを切り替え' : 'Switch collection project'"
            @change="selectClipboardProject"
          >
            <option
              v-for="collection in library.collections"
              :key="collection.id"
              :value="collection.id"
            >
              {{ collection.name }}
            </option>
          </select>
        </span>
        <span class="material-icons clipboard-project-selector-arrow">unfold_more</span>
        <q-btn
          class="clipboard-project-delete-button"
          flat
          dense
          round
          size="sm"
          icon="delete_outline"
          :aria-label="locale.language === 'ja' ? '選択中のコレクションProjectを削除' : 'Delete selected collection project'"
          @click.stop="confirmSelectedCollectionDeletion"
        >
          <q-tooltip>{{ locale.language === 'ja' ? '選択中のコレクションProjectを削除' : 'Delete selected collection project' }}</q-tooltip>
        </q-btn>
      </div>

      <label v-if="activeView !== 'collections'" class="search-box">
        <span class="material-icons">search</span>
        <input v-model="clipboard.filter" type="search" :placeholder="locale.t('filterItems')" />
        <kbd>⌘K</kbd>
      </label>

      <div v-if="activeView === 'collections'" class="collection-list collection-project-tree">
        <div v-for="collection in library.collections" :key="collection.id" class="collection-group">
          <button
            type="button"
            class="collection-row root"
            :class="{ active: selectedProjectId === collection.id && collectionWorkspace.selectedCategoryId === 'all' }"
            :aria-expanded="isCollectionExpanded(collection.id)"
            @click="selectCollectionProject(collection.id)"
          >
            <span class="material-icons collection-expand-icon">
              {{ isCollectionExpanded(collection.id) ? 'keyboard_arrow_down' : 'keyboard_arrow_right' }}
            </span>
            <span class="material-icons folder">folder_open</span>
            <span>{{ collection.name }}</span>
            <em>{{ categoryCount(collection.id, 'all') }}</em>
          </button>
          <button
            v-for="category in collectionCategories.filter((candidate) => candidate.id !== 'all')"
            :key="`${collection.id}-${category.id}`"
            type="button"
            class="collection-row child"
            v-show="isCollectionExpanded(collection.id)"
            :class="{ active: selectedProjectId === collection.id && collectionWorkspace.selectedCategoryId === category.id }"
            @click="selectCollectionCategory(collection.id, category.id)"
          >
            <span class="tree-line" />
            <span class="material-icons folder">{{ category.icon }}</span>
            <span>{{ categoryLabel(category) }}</span>
            <em>{{ categoryCount(collection.id, category.id) }}</em>
          </button>
        </div>
        <div v-if="library.collections.length === 0" class="empty-state collection-empty-state">
          <span class="material-icons">create_new_folder</span>
          <p>{{ locale.language === 'ja' ? 'コレクションProjectがありません' : 'No collection projects' }}</p>
        </div>
      </div>

      <div v-else class="history-scroll">
        <section v-for="[label, items] in groups" :key="label" class="history-group">
          <div class="group-label"><span>{{ label }}</span><i /></div>
          <div
            v-for="item in items"
            :key="item.id"
            class="history-card"
            :class="{
              selected: clipboard.selectedId === item.id,
              draggable: canReorderHistory,
              dragging: draggingHistoryId === item.id,
              'drag-before': dragTargetId === item.id && dragPlacement === 'before',
              'drag-after': dragTargetId === item.id && dragPlacement === 'after',
            }"
            role="button"
            tabindex="0"
            :data-item-id="item.id"
            :aria-grabbed="draggingHistoryId === item.id"
            @click="openHistoryItem(item)"
            @keydown.enter.prevent="openHistoryItem(item)"
            @keydown.space.prevent="openHistoryItem(item)"
            @pointerdown="startHistoryPointer(item, $event)"
            @pointermove="moveHistoryPointer"
            @pointerup="finishHistoryPointer"
            @pointercancel="cancelHistoryPointer"
          >
            <div class="card-accent" />
            <div class="history-main">
              <div class="history-title-row">
                <input
                  v-if="editingTitleId === item.id"
                  v-model="titleDraft"
                  class="card-title-editor"
                  :data-item-id="item.id"
                  :aria-label="locale.t('editCardTitle')"
                  maxlength="120"
                  @click.stop
                  @blur="saveTitle(item)"
                  @keydown.enter.stop.prevent="saveTitle(item)"
                  @keydown.escape.stop.prevent="cancelTitleEdit"
                />
                <strong v-else>{{ item.name }}</strong>
                <div class="history-title-actions">
                  <button
                    v-if="editingTitleId !== item.id"
                    class="title-edit-toggle"
                    type="button"
                    :aria-label="locale.t('editCardTitle')"
                    :title="locale.t('editCardTitle')"
                    @click.stop="startTitleEdit(item)"
                  >
                    <span class="material-icons">edit</span>
                  </button>
                  <button
                    class="favorite-toggle"
                    :class="{ active: item.favorite }"
                    type="button"
                    :aria-label="item.favorite ? locale.t('removeFavorite') : locale.t('addFavorite')"
                    :title="item.favorite ? locale.t('removeFavorite') : locale.t('addFavorite')"
                    @click.stop="clipboard.toggleFavorite(item.id)"
                  >
                    <span class="material-icons">{{ item.favorite ? 'star' : 'star_border' }}</span>
                  </button>
                </div>
              </div>
              <div class="history-meta">
                <span class="format-pill">{{ item.format }}</span>
                <span class="object-type">{{ objectTypeLabel(item) }}</span>
                <time>{{ timeLabel(item.createdAt) }}</time>
              </div>
              <div v-if="item.tags.length" class="mini-tags">
                <span v-for="tag in item.tags.slice(0, 3)" :key="tag">{{ tag }}</span>
              </div>
            </div>
            <q-menu context-menu class="history-options-menu history-context-menu">
              <q-list>
                <q-item
                  v-close-popup
                  clickable
                  class="history-library-item"
                  :disable="Boolean(librarySavingId)"
                  @click.stop="saveToLibrary(item)"
                >
                  <q-item-section avatar><q-icon name="library_add" /></q-item-section>
                  <q-item-section>
                    <q-item-label>{{ locale.t('saveToLibrary') || (locale.language === 'ja' ? 'ライブラリに保存' : 'Save to Library') }}</q-item-label>
                    <q-item-label caption>{{ locale.t('saveToLibraryHelp') || (locale.language === 'ja' ? 'このXMLをライブラリへ追加・更新します' : 'Add or update this XML in the library') }}</q-item-label>
                  </q-item-section>
                  <q-item-section v-if="item.inLibrary" side><q-icon name="check_circle" /></q-item-section>
                </q-item>
                <q-separator />
                <q-item
                  v-close-popup
                  clickable
                  class="history-card-delete-item"
                  :disable="Boolean(cardDeleteBusyId)"
                  @click.stop="confirmCardDeletion(item)"
                >
                  <q-item-section avatar><q-icon name="delete_outline" /></q-item-section>
                  <q-item-section>
                    <q-item-label>{{ locale.language === 'ja' ? 'カードを削除' : 'Delete Card' }}</q-item-label>
                    <q-item-label caption>{{ locale.language === 'ja' ? 'クリップボード履歴から削除します' : 'Remove from Clipboard history' }}</q-item-label>
                  </q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </div>
        </section>
        <div v-if="groups.length === 0" class="empty-state">
          <span class="material-icons">inbox</span>
          <p>{{ locale.t('noItems') }}</p>
        </div>
      </div>
    </section>
  </aside>
</template>

<style scoped>
.panel-heading .eyebrow {
  color: var(--blue-bright);
}

.collection-row {
  color: var(--muted);
}

.collection-row:hover {
  background: var(--bg-hover);
  color: var(--text);
}

.collection-row.active {
  background: linear-gradient(90deg, rgba(var(--accent-rgb), .2), var(--bg-panel-raised));
  color: var(--text);
  box-shadow: inset 2px 0 var(--blue-bright);
}

.collection-row .folder,
.collection-row.active .folder,
.collection-row.active em {
  color: var(--blue-bright);
}

.collection-row em {
  color: var(--faint);
}

.tree-line {
  border-color: var(--line-bright);
}

.collection-project-tree .collection-group {
  border-color: var(--line);
}
</style>

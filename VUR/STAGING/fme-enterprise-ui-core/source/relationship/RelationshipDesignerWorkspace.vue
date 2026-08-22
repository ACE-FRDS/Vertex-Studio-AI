<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch, type CSSProperties } from 'vue'
import { useQuasar } from 'quasar'
import RelationshipEditorDialog from './RelationshipEditorDialog.vue'
import { relationshipDesignSample } from '../../data/relationshipDesignSample'
import { relationshipOperator } from '../../domain/design/relationshipOperators'
import { clipboardGateway } from '../../services/clipboardGateway'
import { dependencyState } from '../../services/componentCardEngine'
import { featureAccess } from '../../services/featureAccess'
import { licenseGateway } from '../../services/licenseGateway'
import { isTauriRuntime, nativeGateway } from '../../services/nativeGateway'
import { useRelationshipDesignerStore } from '../../stores/relationshipDesigner'
import { useAiAssistantStore } from '../../stores/aiAssistant'
import { useLocaleStore } from '../../stores/locale'
import type { ComponentCard, ComponentCardStatus, DesignRelationship, TableOccurrence } from '../../types/design'

const $q = useQuasar()
const designer = useRelationshipDesignerStore()
const aiAssistant = useAiAssistantStore()
const locale = useLocaleStore()
const license = computed(() => featureAccess.snapshot())
const designerUnlocked = computed(() => featureAccess.can('relationshipDesigner'))
const refreshingLicense = ref(false)
const viewport = ref<HTMLElement | null>(null)
const draggingIds = ref<string[]>([])
const resizingId = ref('')
const panning = ref(false)
const selecting = ref(false)
const selectionBox = ref<{ start: CanvasPosition; current: CanvasPosition } | null>(null)
const fieldScrollOffsets = ref<Record<string, number>>({})
const relationshipDraft = ref<{ from: FieldEndpoint; pointer: CanvasPosition } | null>(null)
const relationshipHoverTarget = ref<FieldEndpoint | null>(null)
const relationshipDialogOpen = ref(false)
const relationshipDialogIsNew = ref(false)
const relationshipForm = ref<DesignRelationship | null>(null)
const pendingSelfJoinOccurrenceId = ref('')
const renameDialogOpen = ref(false)
const renameOccurrenceId = ref('')
const renameValue = ref('')
const renameInput = ref<HTMLInputElement | null>(null)
const sendingToFileMaker = ref(false)
const cardDetailOpen = ref(false)
const cardEditTitle = ref('')
const cardEditDescription = ref('')
const repairingCard = ref(false)
let componentCardScrollAnimationFrame = 0
let componentCardScrollTarget = 0
let componentCardScrollElement: HTMLElement | null = null

interface FieldEndpoint {
  occurrenceId: string
  fieldId: string
  side: 'left' | 'right'
}

interface CanvasPosition { x: number; y: number }

type PointerInteraction =
  | { kind: 'card'; ids: string[]; startX: number; startY: number; origins: Record<string, CanvasPosition> }
  | { kind: 'resize'; id: string; edge: 'left' | 'right' | 'top' | 'bottom'; startX: number; startY: number; originX: number; originY: number; originWidth: number; originHeight: number }
  | { kind: 'pan'; startX: number; startY: number; originX: number; originY: number }
  | { kind: 'select'; start: CanvasPosition; baseIds: string[]; additive: boolean }
  | { kind: 'relationship'; from: FieldEndpoint }
  | null

let interaction: PointerInteraction = null

const project = computed(() => designer.project)
const selectedOccurrence = computed(() => designer.selectedOccurrence)
const selectedOccurrenceIds = computed(() => new Set(project.value?.canvasState.selectedOccurrenceIds ?? []))
const selectedOccurrences = computed(() => (project.value?.tableOccurrences ?? []).filter((occurrence) => selectedOccurrenceIds.value.has(occurrence.id)))
const renameError = computed(() => {
  const name = renameValue.value.trim()
  if (!name) return 'オカレンス名を入力してください。'
  if ((project.value?.tableOccurrences ?? []).some((occurrence) => occurrence.id !== renameOccurrenceId.value && occurrence.name === name)) return '同じオカレンス名が既に使用されています。'
  return ''
})
const selectedTable = computed(() => selectedOccurrence.value ? tableFor(selectedOccurrence.value) : null)
const focusedComponentCard = computed(() => {
  if (designer.selectedComponentCard) return designer.selectedComponentCard
  const occurrence = selectedOccurrence.value
  if (!occurrence) return null
  return project.value?.componentCards.find((card) =>
    card.sourceIds.includes(occurrence.id) || card.sourceIds.includes(occurrence.baseTableId),
  ) ?? null
})
const selectedValidationErrors = computed(() => {
  const occurrence = selectedOccurrence.value
  const table = selectedTable.value
  const card = focusedComponentCard.value
  if (!occurrence || !table) return []
  const entityIds = new Set([occurrence.id, table.id, card?.id ?? '', ...table.fields.map((field) => field.id)])
  return designer.validation.errors.filter((error) => error.entityId && entityIds.has(error.entityId))
})
const fileMakerSendState = computed(() => {
  const card = focusedComponentCard.value
  if (designer.selectedRelationship && !designer.selectedComponentCard) return { available: false, reason: text.value.relationshipSendUnavailable }
  if (!card) return { available: false, reason: text.value.selectSendTarget }
  if (selectedValidationErrors.value.length) return { available: false, reason: text.value.resolveValidationErrors }
  if (card.status === 'validationError' || card.status === 'failed') return { available: false, reason: text.value.generatedXmlInvalid }
  if (card.executionMode !== 'clipboard') return { available: false, reason: text.value.manualStep }
  if (!['ready', 'copied', 'applied', 'verified'].includes(card.status) || !card.generatedXml?.trim() || !card.clipboardFormat?.trim()) {
    return { available: false, reason: text.value.generatedXmlPending }
  }
  if (!isTauriRuntime()) return { available: false, reason: text.value.desktopSendRequired }
  return {
    available: true,
    reason: `${card.title} · ${card.clipboardFormat}`,
  }
})
const worldStyle = computed(() => ({
  transform: `translate3d(${project.value?.canvasState.pan.x ?? 0}px, ${project.value?.canvasState.pan.y ?? 0}px, 0) scale(${project.value?.canvasState.zoom ?? 1})`,
}) as CSSProperties)
const viewportGridStyle = computed(() => {
  const canvas = project.value?.canvasState
  const zoom = canvas?.zoom ?? 1
  const pan = canvas?.pan ?? { x: 0, y: 0 }
  const majorGrid = 96 * zoom
  const minorGrid = 16 * zoom
  const position = `${pan.x}px ${pan.y}px`
  return {
    backgroundSize: `${majorGrid}px ${majorGrid}px, ${majorGrid}px ${majorGrid}px, ${minorGrid}px ${minorGrid}px`,
    backgroundPosition: `${position}, ${position}, ${position}`,
  } as CSSProperties
})
const zoomLabel = computed(() => `${Math.round((project.value?.canvasState.zoom ?? 1) * 100)}%`)
const selectionBoxStyle = computed(() => {
  const box = selectionBox.value
  if (!box) return null
  const left = Math.min(box.start.x, box.current.x)
  const top = Math.min(box.start.y, box.current.y)
  return {
    transform: `translate3d(${left}px, ${top}px, 0)`,
    width: `${Math.abs(box.current.x - box.start.x)}px`,
    height: `${Math.abs(box.current.y - box.start.y)}px`,
  } as CSSProperties
})
const relationshipPaths = computed(() => (project.value?.relationships ?? []).flatMap((relationship) => {
  const left = project.value?.tableOccurrences.find((item) => item.id === relationship.leftOccurrenceId)
  const right = project.value?.tableOccurrences.find((item) => item.id === relationship.rightOccurrenceId)
  if (!left || !right) return []
  const leftSide = left.x + left.width / 2 <= right.x + right.width / 2 ? 'right' : 'left'
  const rightSide = leftSide === 'right' ? 'left' : 'right'
  const start = fieldPoint(relationship.leftOccurrenceId, relationship.leftFieldId, leftSide)
  const end = fieldPoint(relationship.rightOccurrenceId, relationship.rightFieldId, rightSide)
  if (!start || !end) return []
  return [{ relationship, path: connectionPath(start, end, leftSide), start, end, midpoint: { x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 }, symbol: relationshipOperator(relationship.operator)?.symbol ?? relationship.operator }]
}))
const draftPath = computed(() => {
  const draft = relationshipDraft.value
  if (!draft) return ''
  const start = fieldPoint(draft.from.occurrenceId, draft.from.fieldId, draft.from.side)
  return start ? connectionPath(start, draft.pointer, draft.from.side) : ''
})
const relatedFieldSides = computed(() => {
  const sides = new Map<string, Set<'left' | 'right'>>()
  const add = (occurrenceId: string, fieldId: string, side: 'left' | 'right') => {
    const key = fieldKey(occurrenceId, fieldId)
    const values = sides.get(key) ?? new Set<'left' | 'right'>()
    values.add(side)
    sides.set(key, values)
  }
  for (const relationship of project.value?.relationships ?? []) {
    const left = project.value?.tableOccurrences.find((item) => item.id === relationship.leftOccurrenceId)
    const right = project.value?.tableOccurrences.find((item) => item.id === relationship.rightOccurrenceId)
    if (!left || !right) continue
    const leftSide = left.x + left.width / 2 <= right.x + right.width / 2 ? 'right' : 'left'
    add(relationship.leftOccurrenceId, relationship.leftFieldId, leftSide)
    add(relationship.rightOccurrenceId, relationship.rightFieldId, leftSide === 'right' ? 'left' : 'right')
  }
  return sides
})

const text = computed(() => locale.language === 'ja' ? {
  title: 'AIリレーションシップデザイナー', project: 'AI設計プロジェクト', tables: 'テーブル', occurrences: 'テーブルオカレンス', relationships: 'リレーション',
  canvas: 'RELATIONSHIP CANVAS', fit: '全体表示', reset: '表示をリセット', inspector: 'インスペクター', noSelection: 'TOカードを選択すると詳細を確認できます。',
  baseTable: '元テーブル', position: 'キャンバス座標', fields: 'フィールド', primaryKey: '主キー', foreignKey: '外部キー', required: '必須',
  cards: 'COMPONENT CARDS', phase: 'PHASE 2', validation: '設計検証', valid: '正常', errors: 'エラー', warnings: '警告', collapse: '折りたたみ', expand: '展開',
  fileMakerSend: 'FILEMAKER送信', sendAvailable: '送信可能', sendUnavailable: '送信不可', sendToFileMaker: 'FileMakerに送信', sending: '送信中…',
  selectSendTarget: '送信するTOカードを選択してください。', relationshipSendUnavailable: 'リレーションシップはFileMaker送信に対応していません。',
  resolveValidationErrors: 'このオブジェクトの設計検証エラーを解消してください。', componentCardMissing: '送信対象のコンポーネントカードがありません。',
  generatedXmlPending: '送信用XMLがまだ生成されていません。', generatedXmlInvalid: '送信用XMLが無効です。', desktopSendRequired: 'FileMaker送信はデスクトップ版で利用できます。',
  sendComplete: 'FileMakerクリップボードへのセットが完了しました。', sendFailed: 'FileMakerへの送信に失敗しました。',
  cardDetail: 'カード詳細', validateCard: '検証', applied: '貼り付け済み', verified: '動作確認済み', nextCard: '次のカード', saveChanges: '変更を保存',
  dependencyPending: '依存カード未完了', manualStep: '手動作業', xmlSource: 'XML SOURCE', validationResult: 'VALIDATION', history: 'HISTORY',
} : {
  title: 'AI Relationship Designer', project: 'AI Design Project', tables: 'Tables', occurrences: 'Table Occurrences', relationships: 'Relationships',
  canvas: 'RELATIONSHIP CANVAS', fit: 'Fit to Screen', reset: 'Reset View', inspector: 'Inspector', noSelection: 'Select a TO card to inspect it.',
  baseTable: 'Base Table', position: 'Canvas Position', fields: 'Fields', primaryKey: 'Primary Key', foreignKey: 'Foreign Key', required: 'Required',
  cards: 'COMPONENT CARDS', phase: 'PHASE 2', validation: 'Design Validation', valid: 'Valid', errors: 'Errors', warnings: 'Warnings', collapse: 'Collapse', expand: 'Expand',
  fileMakerSend: 'FILEMAKER TRANSFER', sendAvailable: 'READY', sendUnavailable: 'UNAVAILABLE', sendToFileMaker: 'Send to FileMaker', sending: 'Sending…',
  selectSendTarget: 'Select a TO card to send.', relationshipSendUnavailable: 'Relationships cannot be sent through the FileMaker clipboard.',
  resolveValidationErrors: 'Resolve the validation errors for this object.', componentCardMissing: 'No component card is available for this object.',
  generatedXmlPending: 'FileMaker XML has not been generated yet.', generatedXmlInvalid: 'The generated FileMaker XML is invalid.', desktopSendRequired: 'FileMaker transfer is available in the desktop app.',
  sendComplete: 'FileMaker clipboard data is ready.', sendFailed: 'Failed to send data to FileMaker.',
  cardDetail: 'Card Details', validateCard: 'Validate', applied: 'Mark Applied', verified: 'Mark Verified', nextCard: 'Next Card', saveChanges: 'Save Changes',
  dependencyPending: 'Dependencies pending', manualStep: 'Manual Step', xmlSource: 'XML SOURCE', validationResult: 'VALIDATION', history: 'HISTORY',
})

function tableFor(occurrence: TableOccurrence) {
  return project.value?.tables.find((table) => table.id === occurrence.baseTableId) ?? null
}

async function sendFocusedObjectToFileMaker() {
  const card = focusedComponentCard.value
  if (!fileMakerSendState.value.available || !card?.generatedXml || !card.clipboardFormat) return
  sendingToFileMaker.value = true
  try {
    const report = await nativeGateway.validateXml(card.generatedXml, card.clipboardFormat)
    if (!report.valid) {
      const detail = report.issues.find((issue) => issue.level === 'error')?.message ?? text.value.generatedXmlInvalid
      $q.notify({ type: 'negative', position: 'bottom', icon: 'error_outline', message: text.value.sendFailed, caption: detail })
      return
    }
    await clipboardGateway.set(card.clipboardFormat, card.generatedXml)
    designer.setComponentCardStatus(card.id, 'copied', 'FileMakerクリップボードへ送信')
    $q.notify({ type: 'positive', position: 'bottom', icon: 'outbox', message: text.value.sendComplete, caption: `${card.title} · ${card.clipboardFormat}` })
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error)
    designer.setComponentCardStatus(card.id, 'failed', detail)
    $q.notify({ type: 'negative', position: 'bottom', icon: 'error_outline', message: text.value.sendFailed, caption: detail })
  } finally {
    sendingToFileMaker.value = false
  }
}

function cardDependencyState(card: ComponentCard) {
  return dependencyState(card, project.value?.componentCards ?? [])
}

function statusLabel(status: ComponentCardStatus) {
  const labels: Record<ComponentCardStatus, string> = locale.language === 'ja'
    ? { draft: '下書き', aiGenerated: 'AI生成', validating: '検証中', validationError: 'エラー', warning: '警告', ready: '準備完了', copied: 'コピー済み', applied: '貼付済み', verified: '確認済み', skipped: 'スキップ', failed: '失敗' }
    : { draft: 'Draft', aiGenerated: 'AI Generated', validating: 'Validating', validationError: 'Error', warning: 'Warning', ready: 'Ready', copied: 'Copied', applied: 'Applied', verified: 'Verified', skipped: 'Skipped', failed: 'Failed' }
  return labels[status]
}

function cardTypeLabel(card: ComponentCard) {
  if (card.executionMode === 'manual') return card.kind === 'relationship' ? 'RELATIONSHIP · MANUAL' : `${card.kind.toLocaleUpperCase()} · MANUAL`
  return card.kind.toLocaleUpperCase()
}

function openCardDetails(card: ComponentCard) {
  designer.selectComponentCard(card.id)
  cardEditTitle.value = card.title
  cardEditDescription.value = card.description
  cardDetailOpen.value = true
}

function cardCanCopy(card: ComponentCard) {
  return card.executionMode === 'clipboard'
    && ['ready', 'copied', 'applied', 'verified'].includes(card.status)
    && Boolean(card.generatedXml?.trim() && card.clipboardFormat?.trim())
    && isTauriRuntime()
}

async function sendCardToFileMaker(card: ComponentCard) {
  designer.selectComponentCard(card.id)
  await nextTick()
  await sendFocusedObjectToFileMaker()
}

function closeCardDetails() {
  cardDetailOpen.value = false
}

function saveCardDetails() {
  const card = designer.selectedComponentCard
  if (!card) return
  designer.updateComponentCard(card.id, { title: cardEditTitle.value, description: cardEditDescription.value })
  cardEditTitle.value = designer.selectedComponentCard?.title ?? cardEditTitle.value
  cardEditDescription.value = designer.selectedComponentCard?.description ?? cardEditDescription.value
}

async function validateFocusedCard() {
  const card = designer.selectedComponentCard ?? focusedComponentCard.value
  if (!card) return
  designer.setComponentCardStatus(card.id, 'validating')
  const structural = designer.validateCard(card.id)
  if (!structural?.validationResult.valid || structural.executionMode !== 'clipboard' || !structural.generatedXml || !isTauriRuntime()) return
  try {
    const report = await nativeGateway.validateXml(structural.generatedXml, structural.clipboardFormat)
    const errors = report.issues.filter((issue) => issue.level === 'error').map((issue) => ({ level: 'error' as const, code: issue.code, message: issue.message }))
    const warnings = report.issues.filter((issue) => issue.level === 'warning').map((issue) => ({ level: 'warning' as const, code: issue.code, message: issue.message }))
    designer.applyComponentCardValidation(card.id, { valid: report.valid && errors.length === 0, errors, warnings, validatedAt: new Date().toISOString() })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    designer.applyComponentCardValidation(card.id, { valid: false, errors: [{ level: 'error', code: 'NATIVE_VALIDATION_FAILED', message }], warnings: [], validatedAt: new Date().toISOString() })
  }
}

async function repairFocusedCard() {
  const card = designer.selectedComponentCard ?? focusedComponentCard.value
  if (!card || repairingCard.value) return
  repairingCard.value = true
  try {
    await aiAssistant.initialize(card.generatedXml ?? '')
    const issues = [...card.validationResult.errors, ...card.validationResult.warnings].map((issue) => `- ${issue.message}`).join('\n')
    const prompt = [
      '次のComponent Cardだけを再生成してください。プロジェクト全体は変更しないでください。',
      `Component: ${card.title} (${card.kind})`,
      card.description,
      issues ? `Validation issues:\n${issues}` : '現在の設計意図を維持し、FileMakerへ貼り付け可能なXMLを返してください。',
      `Source:\n${card.sourceContent}`,
    ].join('\n\n')
    await aiAssistant.sendPrompt(prompt, card.generatedXml ?? '', card.clipboardFormat)
    if (aiAssistant.generatedXml) {
      designer.replaceComponentCardXml(card.id, aiAssistant.generatedXml, 'AIによるカード単位再生成')
      await validateFocusedCard()
    } else if (aiAssistant.lastError) {
      $q.notify({ type: 'negative', position: 'bottom', icon: 'error_outline', message: 'AIによる修正に失敗しました。', caption: aiAssistant.lastError })
    }
  } finally {
    repairingCard.value = false
  }
}

function updateFocusedCardStatus(status: ComponentCardStatus) {
  const card = designer.selectedComponentCard ?? focusedComponentCard.value
  if (card) designer.setComponentCardStatus(card.id, status)
}

function openNextCard() {
  const cards = project.value?.componentCards ?? []
  const current = designer.selectedComponentCard ?? focusedComponentCard.value
  if (!current || !cards.length) return
  const currentIndex = cards.findIndex((card) => card.id === current.id)
  const next = [...cards.slice(currentIndex + 1), ...cards.slice(0, currentIndex)]
    .find((card) => !['verified', 'skipped'].includes(card.status))
  if (next) openCardDetails(next)
}

function startCardDrag(event: PointerEvent, occurrence: TableOccurrence) {
  if (event.button !== 0) return
  event.preventDefault()
  event.stopPropagation()
  const additive = event.shiftKey || event.ctrlKey || event.metaKey
  if (additive) designer.selectOccurrence(occurrence.id, true)
  else if (!selectedOccurrenceIds.value.has(occurrence.id)) designer.selectOccurrence(occurrence.id)
  if (!selectedOccurrenceIds.value.has(occurrence.id)) return
  const ids = [...selectedOccurrenceIds.value]
  const origins = Object.fromEntries((project.value?.tableOccurrences ?? [])
    .filter((candidate) => ids.includes(candidate.id))
    .map((candidate) => [candidate.id, { x: candidate.x, y: candidate.y }]))
  draggingIds.value = ids
  interaction = { kind: 'card', ids, startX: event.clientX, startY: event.clientY, origins }
  bindPointerEvents()
}

function startOccurrenceResize(event: PointerEvent, occurrence: TableOccurrence, edge: 'left' | 'right' | 'top' | 'bottom') {
  if (event.button !== 0 || (occurrence.collapsed && (edge === 'top' || edge === 'bottom'))) return
  event.preventDefault()
  event.stopPropagation()
  if (!selectedOccurrenceIds.value.has(occurrence.id)) designer.selectOccurrence(occurrence.id)
  resizingId.value = occurrence.id
  interaction = {
    kind: 'resize',
    id: occurrence.id,
    edge,
    startX: event.clientX,
    startY: event.clientY,
    originX: occurrence.x,
    originY: occurrence.y,
    originWidth: occurrence.width,
    originHeight: occurrenceHeight(occurrence),
  }
  bindPointerEvents()
}

function startCanvasInteraction(event: PointerEvent) {
  const target = event.target as HTMLElement
  if (target.closest('.to-card') || target.closest('.canvas-toolbar') || target.closest('.relationship-link') || target.closest('.relationship-badge')) return
  if (event.button === 0) {
    const start = clientToWorld(event.clientX, event.clientY)
    if (!start) return
    event.preventDefault()
    const additive = event.shiftKey || event.ctrlKey || event.metaKey
    const baseIds = additive ? [...selectedOccurrenceIds.value] : []
    if (!additive) designer.selectOccurrences([])
    selectionBox.value = { start, current: start }
    selecting.value = true
    interaction = { kind: 'select', start, baseIds, additive }
    bindPointerEvents()
    return
  }
  if (event.button !== 1 && event.button !== 2) return
  event.preventDefault()
  const pan = project.value?.canvasState.pan ?? { x: 0, y: 0 }
  interaction = { kind: 'pan', startX: event.clientX, startY: event.clientY, originX: pan.x, originY: pan.y }
  panning.value = true
  bindPointerEvents()
}

function bindPointerEvents() {
  window.addEventListener('pointermove', handlePointerMove)
  window.addEventListener('pointerup', stopInteraction)
  window.addEventListener('pointercancel', stopInteraction)
}

function handlePointerMove(event: PointerEvent) {
  if (!interaction) return
  if (interaction.kind === 'card') {
    const zoom = project.value?.canvasState.zoom ?? 1
    const deltaX = (event.clientX - interaction.startX) / zoom
    const deltaY = (event.clientY - interaction.startY) / zoom
    designer.moveOccurrences(interaction.ids.flatMap((id) => {
      const origin = interaction?.kind === 'card' ? interaction.origins[id] : null
      return origin ? [{ id, x: origin.x + deltaX, y: origin.y + deltaY }] : []
    }))
  } else if (interaction.kind === 'resize') {
    const zoom = project.value?.canvasState.zoom ?? 1
    const deltaX = (event.clientX - interaction.startX) / zoom
    const deltaY = (event.clientY - interaction.startY) / zoom
    if (interaction.edge === 'right') {
      designer.resizeOccurrence(interaction.id, { width: interaction.originWidth + deltaX })
    } else if (interaction.edge === 'left') {
      const width = Math.max(180, interaction.originWidth - deltaX)
      designer.resizeOccurrence(interaction.id, { x: interaction.originX + interaction.originWidth - width, width })
    } else if (interaction.edge === 'bottom') {
      designer.resizeOccurrence(interaction.id, { height: interaction.originHeight + deltaY })
    } else {
      const height = Math.max(120, interaction.originHeight - deltaY)
      designer.resizeOccurrence(interaction.id, { y: interaction.originY + interaction.originHeight - height, height })
    }
  } else if (interaction.kind === 'pan') {
    const zoom = project.value?.canvasState.zoom ?? 1
    designer.setViewport(zoom, interaction.originX + event.clientX - interaction.startX, interaction.originY + event.clientY - interaction.startY)
  } else if (interaction.kind === 'select') {
    const current = clientToWorld(event.clientX, event.clientY)
    if (!current) return
    selectionBox.value = { start: interaction.start, current }
    const left = Math.min(interaction.start.x, current.x)
    const top = Math.min(interaction.start.y, current.y)
    const right = Math.max(interaction.start.x, current.x)
    const bottom = Math.max(interaction.start.y, current.y)
    const enclosed = (project.value?.tableOccurrences ?? []).filter((occurrence) => {
      const occurrenceRight = occurrence.x + occurrence.width
      const occurrenceBottom = occurrence.y + occurrenceHeight(occurrence)
      return occurrence.x < right && occurrenceRight > left && occurrence.y < bottom && occurrenceBottom > top
    }).map((occurrence) => occurrence.id)
    designer.selectOccurrences(interaction.additive ? [...interaction.baseIds, ...enclosed] : enclosed)
  } else {
    const position = clientToWorld(event.clientX, event.clientY)
    if (position && relationshipDraft.value) relationshipDraft.value = { ...relationshipDraft.value, pointer: position }
    relationshipHoverTarget.value = dropEndpointAt(event.clientX, event.clientY, interaction.from)
  }
}

function stopInteraction(event?: PointerEvent) {
  if (interaction?.kind === 'relationship' && event) {
    const target = dropEndpointAt(event.clientX, event.clientY, interaction.from)
    if (target) {
      if (target.occurrenceId === interaction.from.occurrenceId && target.fieldId === interaction.from.fieldId) {
        openSelfJoinRelationship(interaction.from)
      } else {
        openNewRelationship(interaction.from, target)
      }
    }
  }
  interaction = null
  draggingIds.value = []
  resizingId.value = ''
  panning.value = false
  selecting.value = false
  selectionBox.value = null
  relationshipDraft.value = null
  relationshipHoverTarget.value = null
  window.removeEventListener('pointermove', handlePointerMove)
  window.removeEventListener('pointerup', stopInteraction)
  window.removeEventListener('pointercancel', stopInteraction)
}

function handleWheel(event: WheelEvent) {
  const element = viewport.value
  const canvas = project.value?.canvasState
  if (!element || !canvas) return
  const rect = element.getBoundingClientRect()
  const pointerX = event.clientX - rect.left
  const pointerY = event.clientY - rect.top
  const worldX = (pointerX - canvas.pan.x) / canvas.zoom
  const worldY = (pointerY - canvas.pan.y) / canvas.zoom
  const nextZoom = clamp(canvas.zoom * Math.exp(-event.deltaY * 0.0012), 0.3, 2)
  designer.setViewport(nextZoom, pointerX - worldX * nextZoom, pointerY - worldY * nextZoom)
}

function handleOccurrenceWheel(occurrenceId: string, event: WheelEvent) {
  const card = event.currentTarget as HTMLElement
  const fieldList = card.querySelector<HTMLElement>('.to-field-list')
  if (!fieldList || fieldList.scrollHeight <= fieldList.clientHeight + 1) return
  event.preventDefault()
  event.stopPropagation()
  const distance = event.deltaMode === WheelEvent.DOM_DELTA_LINE
    ? event.deltaY * 32
    : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
      ? event.deltaY * fieldList.clientHeight
      : event.deltaY
  fieldList.scrollTop += distance
  fieldScrollOffsets.value = { ...fieldScrollOffsets.value, [occurrenceId]: fieldList.scrollTop }
}

function handleComponentCardWheel(event: WheelEvent) {
  const scroller = event.currentTarget as HTMLElement
  const maximumScroll = scroller.scrollWidth - scroller.clientWidth
  if (maximumScroll <= 1) return

  const primaryDelta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY
  const rawDistance = event.deltaMode === WheelEvent.DOM_DELTA_LINE
    ? primaryDelta * 34
    : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
      ? primaryDelta * scroller.clientWidth * 0.85
      : primaryDelta
  if (rawDistance === 0) return
  const distance = Math.sign(rawDistance) * Math.max(Math.abs(rawDistance), 72)
  if (componentCardScrollElement !== scroller) {
    componentCardScrollElement = scroller
    componentCardScrollTarget = scroller.scrollLeft
  }

  const targetBase = componentCardScrollAnimationFrame ? componentCardScrollTarget : scroller.scrollLeft
  componentCardScrollTarget = clamp(targetBase + distance, 0, maximumScroll)
  if (componentCardScrollAnimationFrame) {
    cancelAnimationFrame(componentCardScrollAnimationFrame)
    componentCardScrollAnimationFrame = 0
  }
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    scroller.scrollLeft = componentCardScrollTarget
    return
  }

  const startScroll = scroller.scrollLeft
  const travel = componentCardScrollTarget - startScroll
  const startedAt = performance.now()
  const duration = clamp(210 + Math.abs(travel) * 0.18, 230, 420)
  const animate = (timestamp: number) => {
    const progress = clamp((timestamp - startedAt) / duration, 0, 1)
    const eased = 1 - Math.pow(1 - progress, 3)
    scroller.scrollLeft = startScroll + travel * eased
    if (progress < 1) componentCardScrollAnimationFrame = requestAnimationFrame(animate)
    else componentCardScrollAnimationFrame = 0
  }
  componentCardScrollAnimationFrame = requestAnimationFrame(animate)
}

function zoomBy(factor: number) {
  const element = viewport.value
  const canvas = project.value?.canvasState
  if (!element || !canvas) return
  const centerX = element.clientWidth / 2
  const centerY = element.clientHeight / 2
  const worldX = (centerX - canvas.pan.x) / canvas.zoom
  const worldY = (centerY - canvas.pan.y) / canvas.zoom
  const nextZoom = clamp(canvas.zoom * factor, 0.3, 2)
  designer.setViewport(nextZoom, centerX - worldX * nextZoom, centerY - worldY * nextZoom)
}

async function fitToScreen() {
  await nextTick()
  const element = viewport.value
  const occurrences = project.value?.tableOccurrences ?? []
  if (!element || !occurrences.length) return
  const minX = Math.min(...occurrences.map((item) => item.x))
  const minY = Math.min(...occurrences.map((item) => item.y))
  const maxX = Math.max(...occurrences.map((item) => item.x + item.width))
  const maxY = Math.max(...occurrences.map((item) => item.y + occurrenceHeight(item)))
  const padding = 72
  const graphWidth = Math.max(1, maxX - minX)
  const graphHeight = Math.max(1, maxY - minY)
  const zoom = clamp(Math.min((element.clientWidth - padding * 2) / graphWidth, (element.clientHeight - padding * 2) / graphHeight), 0.3, 1.2)
  const panX = (element.clientWidth - graphWidth * zoom) / 2 - minX * zoom
  const panY = (element.clientHeight - graphHeight * zoom) / 2 - minY * zoom
  designer.setViewport(zoom, panX, panY)
}

function resetView() { designer.setViewport(1, 52, 52) }

function occurrenceHeight(occurrence: TableOccurrence) {
  if (occurrence.collapsed) return 53
  if (occurrence.height) return occurrence.height
  const fieldCount = tableFor(occurrence)?.fields.length ?? 0
  return 77 + Math.min(fieldCount * 32, 192)
}

async function openOccurrenceRename(occurrence: TableOccurrence) {
  renameOccurrenceId.value = occurrence.id
  renameValue.value = occurrence.name
  renameDialogOpen.value = true
  await nextTick()
  renameInput.value?.focus()
  renameInput.value?.select()
}

function closeOccurrenceRename() {
  renameDialogOpen.value = false
  renameOccurrenceId.value = ''
  renameValue.value = ''
}

function saveOccurrenceRename() {
  if (renameError.value || !designer.renameOccurrence(renameOccurrenceId.value, renameValue.value)) return
  closeOccurrenceRename()
}

function alignSelectedOccurrences(alignment: 'left' | 'center' | 'right' | 'top' | 'middle' | 'bottom') {
  const occurrences = selectedOccurrences.value
  if (occurrences.length < 2) return
  const left = Math.min(...occurrences.map((occurrence) => occurrence.x))
  const right = Math.max(...occurrences.map((occurrence) => occurrence.x + occurrence.width))
  const center = (left + right) / 2
  const top = Math.min(...occurrences.map((occurrence) => occurrence.y))
  const bottom = Math.max(...occurrences.map((occurrence) => occurrence.y + occurrenceHeight(occurrence)))
  const middle = (top + bottom) / 2
  designer.moveOccurrences(occurrences.map((occurrence) => ({
    id: occurrence.id,
    x: alignment === 'left'
      ? left
      : alignment === 'right'
        ? right - occurrence.width
        : alignment === 'center'
          ? center - occurrence.width / 2
          : occurrence.x,
    y: alignment === 'top'
      ? top
      : alignment === 'bottom'
        ? bottom - occurrenceHeight(occurrence)
        : alignment === 'middle'
          ? middle - occurrenceHeight(occurrence) / 2
          : occurrence.y,
  })))
}

function distributeSelectedOccurrences(axis: 'horizontal' | 'vertical') {
  const occurrences = [...selectedOccurrences.value]
  if (occurrences.length < 3) return

  const sorted = occurrences.sort(axis === 'horizontal'
    ? (a, b) => a.x - b.x || a.y - b.y
    : (a, b) => a.y - b.y || a.x - b.x)
  const first = sorted[0]
  const last = sorted[sorted.length - 1]
  if (!first || !last) return

  if (axis === 'horizontal') {
    const minimumGap = 48
    const totalWidth = sorted.reduce((total, occurrence) => total + occurrence.width, 0)
    const right = Math.max(last.x + last.width, first.x + totalWidth + minimumGap * (sorted.length - 1))
    const gap = (right - first.x - totalWidth) / (sorted.length - 1)
    let x = first.x
    designer.moveOccurrences(sorted.map((occurrence) => {
      const position = { id: occurrence.id, x, y: occurrence.y }
      x += occurrence.width + gap
      return position
    }))
    return
  }

  const minimumGap = 72
  const totalHeight = sorted.reduce((total, occurrence) => total + occurrenceHeight(occurrence), 0)
  const bottom = Math.max(
    last.y + occurrenceHeight(last),
    first.y + totalHeight + minimumGap * (sorted.length - 1),
  )
  const gap = (bottom - first.y - totalHeight) / (sorted.length - 1)
  let y = first.y
  designer.moveOccurrences(sorted.map((occurrence) => {
    const position = { id: occurrence.id, x: occurrence.x, y }
    y += occurrenceHeight(occurrence) + gap
    return position
  }))
}

async function arrangeSelectedAnchorBuoy() {
  const occurrences = selectedOccurrences.value
  if (occurrences.length < 2 || !project.value) return
  const selectedOrder = project.value.canvasState.selectedOccurrenceIds.filter((id) => selectedOccurrenceIds.value.has(id))
  const byId = new Map(occurrences.map((occurrence) => [occurrence.id, occurrence]))
  const adjacency = new Map(occurrences.map((occurrence) => [occurrence.id, new Set<string>()]))
  for (const relationship of project.value.relationships) {
    if (!byId.has(relationship.leftOccurrenceId) || !byId.has(relationship.rightOccurrenceId)) continue
    adjacency.get(relationship.leftOccurrenceId)?.add(relationship.rightOccurrenceId)
    adjacency.get(relationship.rightOccurrenceId)?.add(relationship.leftOccurrenceId)
  }

  const minimumX = Math.max(40, Math.min(...occurrences.map((occurrence) => occurrence.x)))
  const minimumY = Math.max(40, Math.min(...occurrences.map((occurrence) => occurrence.y)))
  const horizontalGap = 330
  const verticalGap = 72
  const componentGap = 120
  const visited = new Set<string>()
  const positions: Array<{ id: string; x: number; y: number }> = []
  let componentTop = minimumY

  for (const anchorId of selectedOrder) {
    if (visited.has(anchorId) || !byId.has(anchorId)) continue
    const levels: string[][] = []
    const queue: Array<{ id: string; level: number }> = [{ id: anchorId, level: 0 }]
    visited.add(anchorId)
    while (queue.length) {
      const current = queue.shift()
      if (!current) break
      ;(levels[current.level] ??= []).push(current.id)
      const neighbors = [...(adjacency.get(current.id) ?? [])]
        .filter((id) => !visited.has(id))
        .sort((a, b) => (byId.get(a)?.y ?? 0) - (byId.get(b)?.y ?? 0))
      for (const neighborId of neighbors) {
        visited.add(neighborId)
        queue.push({ id: neighborId, level: current.level + 1 })
      }
    }

    let componentHeight = 0
    for (const [levelIndex, ids] of levels.entries()) {
      let nextY = componentTop
      for (const id of ids) {
        const occurrence = byId.get(id)
        if (!occurrence) continue
        positions.push({ id, x: minimumX + levelIndex * horizontalGap, y: nextY })
        nextY += occurrenceHeight(occurrence) + verticalGap
      }
      componentHeight = Math.max(componentHeight, nextY - componentTop - verticalGap)
    }
    componentTop += Math.max(componentHeight, 120) + componentGap
  }

  designer.moveOccurrences(positions)
  await nextTick()
  await fitToScreen()
}

function selectCardFromClick(event: MouseEvent, occurrenceId: string) {
  if (event.shiftKey || event.ctrlKey || event.metaKey) return
  if (!selectedOccurrenceIds.value.has(occurrenceId)) designer.selectOccurrence(occurrenceId)
}

function toggleCollapsed(occurrence: TableOccurrence) {
  designer.toggleOccurrenceCollapsed(occurrence.id)
}

function startFieldLink(event: PointerEvent, endpoint: FieldEndpoint) {
  if (event.button !== 0) return
  event.preventDefault()
  event.stopPropagation()
  const pointer = clientToWorld(event.clientX, event.clientY)
  if (!pointer) return
  designer.selectOccurrence(endpoint.occurrenceId)
  relationshipDraft.value = { from: endpoint, pointer }
  interaction = { kind: 'relationship', from: endpoint }
  bindPointerEvents()
}

function startFieldRowLink(event: PointerEvent, occurrence: TableOccurrence, fieldId: string) {
  if (event.button !== 0) return
  const row = event.currentTarget as HTMLElement
  const rect = row.getBoundingClientRect()
  const side: FieldEndpoint['side'] = event.clientX < rect.left + rect.width / 2 ? 'left' : 'right'
  startFieldLink(event, { occurrenceId: occurrence.id, fieldId, side })
}

function dropEndpointAt(clientX: number, clientY: number, from: FieldEndpoint): FieldEndpoint | null {
  const target = document.elementFromPoint(clientX, clientY)?.closest<HTMLElement>('[data-field-port], [data-field-drop]')
  const occurrenceId = target?.dataset.occurrenceId
  const fieldId = target?.dataset.fieldId
  if (!occurrenceId || !fieldId) return null
  const side = target.dataset.side === 'left' || target.dataset.side === 'right'
    ? target.dataset.side
    : from.side === 'right' ? 'left' : 'right'
  return { occurrenceId, fieldId, side }
}

function fieldKey(occurrenceId: string, fieldId: string) {
  return `${occurrenceId}:${fieldId}`
}

function isFieldRelated(occurrenceId: string, fieldId: string) {
  return relatedFieldSides.value.has(fieldKey(occurrenceId, fieldId))
}

function isFieldSideRelated(occurrenceId: string, fieldId: string, side: 'left' | 'right') {
  return relatedFieldSides.value.get(fieldKey(occurrenceId, fieldId))?.has(side) ?? false
}

function isConnectionTarget(occurrenceId: string, fieldId: string) {
  return relationshipHoverTarget.value?.occurrenceId === occurrenceId && relationshipHoverTarget.value.fieldId === fieldId
}

function isConnectionSource(occurrenceId: string, fieldId: string) {
  return relationshipDraft.value?.from.occurrenceId === occurrenceId && relationshipDraft.value.from.fieldId === fieldId
}

function clientToWorld(clientX: number, clientY: number): CanvasPosition | null {
  const element = viewport.value
  const canvas = project.value?.canvasState
  if (!element || !canvas) return null
  const rect = element.getBoundingClientRect()
  return {
    x: (clientX - rect.left - canvas.pan.x) / canvas.zoom,
    y: (clientY - rect.top - canvas.pan.y) / canvas.zoom,
  }
}

function fieldPoint(occurrenceId: string, fieldId: string, side: 'left' | 'right'): CanvasPosition | null {
  const occurrence = project.value?.tableOccurrences.find((item) => item.id === occurrenceId)
  if (!occurrence) return null
  if (occurrence.collapsed) return { x: occurrence.x + (side === 'right' ? occurrence.width : 0), y: occurrence.y + 26 }
  const fields = tableFor(occurrence)?.fields ?? []
  const index = fields.findIndex((field) => field.id === fieldId)
  if (index < 0) return null
  const scroll = fieldScrollOffsets.value[occurrenceId] ?? 0
  const unclampedY = occurrence.y + 52 + index * 32 + 16 - scroll
  return {
    x: occurrence.x + (side === 'right' ? occurrence.width : 0),
    y: clamp(unclampedY, occurrence.y + 58, occurrence.y + occurrenceHeight(occurrence) - 31),
  }
}

function connectionPath(start: CanvasPosition, end: CanvasPosition, startSide: 'left' | 'right') {
  const direction = startSide === 'right' ? 1 : -1
  const distance = Math.max(70, Math.abs(end.x - start.x) * .45)
  return `M ${start.x} ${start.y} C ${start.x + distance * direction} ${start.y}, ${end.x - distance * direction} ${end.y}, ${end.x} ${end.y}`
}

function onFieldScroll(occurrenceId: string, event: Event) {
  fieldScrollOffsets.value = { ...fieldScrollOffsets.value, [occurrenceId]: (event.target as HTMLElement).scrollTop }
}

function openNewRelationship(from: FieldEndpoint, to: FieldEndpoint) {
  relationshipForm.value = {
    id: `rel_${crypto.randomUUID()}`,
    leftOccurrenceId: from.occurrenceId,
    leftFieldId: from.fieldId,
    operator: 'equal',
    rightOccurrenceId: to.occurrenceId,
    rightFieldId: to.fieldId,
    allowCreateLeft: false,
    allowCreateRight: false,
    deleteRelatedLeft: false,
    deleteRelatedRight: false,
    sortRelatedLeft: false,
    sortRelatedRight: false,
  }
  relationshipDialogIsNew.value = true
  relationshipDialogOpen.value = true
}

function openSelfJoinRelationship(from: FieldEndpoint) {
  const source = project.value?.tableOccurrences.find((occurrence) => occurrence.id === from.occurrenceId)
  if (!source || !project.value) return
  const cloneId = `to_${crypto.randomUUID()}`
  const position = nextSelfJoinPosition(source)
  const clone: TableOccurrence = {
    id: cloneId,
    name: nextSelfJoinName(source.name),
    baseTableId: source.baseTableId,
    x: position.x,
    y: position.y,
    width: source.width,
    height: source.height,
    collapsed: false,
    ...(source.extensions ? { extensions: { ...source.extensions } } : {}),
  }
  if (!designer.createOccurrence(clone)) return
  pendingSelfJoinOccurrenceId.value = cloneId
  openNewRelationship(from, { occurrenceId: cloneId, fieldId: from.fieldId, side: 'left' })
}

function nextSelfJoinName(sourceName: string) {
  const baseName = `${sourceName}_自己参照`
  const names = new Set((project.value?.tableOccurrences ?? []).map((occurrence) => occurrence.name))
  if (!names.has(baseName)) return baseName
  let suffix = 2
  while (names.has(`${baseName}_${suffix}`)) suffix += 1
  return `${baseName}_${suffix}`
}

function nextSelfJoinPosition(source: TableOccurrence): CanvasPosition {
  const horizontalStep = 330
  const verticalStep = occurrenceHeight(source) + 72
  const width = source.width
  const height = occurrenceHeight(source)
  const occurrences = project.value?.tableOccurrences ?? []
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const column = Math.floor(attempt / 6) + 1
    const row = attempt % 6
    const x = Math.min(4800 - width - 40, Math.max(40, source.x + horizontalStep * column))
    const y = Math.min(3200 - height - 40, Math.max(40, source.y + verticalStep * row))
    const available = occurrences.every((occurrence) => {
      const gap = 36
      return x + width + gap <= occurrence.x
        || x >= occurrence.x + occurrence.width + gap
        || y + height + gap <= occurrence.y
        || y >= occurrence.y + occurrenceHeight(occurrence) + gap
    })
    if (available) return { x, y }
  }
  return { x: Math.min(4800 - width - 40, source.x + horizontalStep), y: Math.min(3200 - height - 40, source.y + verticalStep) }
}

function editRelationship(relationship: DesignRelationship) {
  designer.selectRelationship(relationship.id)
  relationshipForm.value = cloneRelationship(relationship)
  relationshipDialogIsNew.value = false
  relationshipDialogOpen.value = true
}

function cloneRelationship(relationship: DesignRelationship): DesignRelationship {
  return {
    ...relationship,
    extensions: relationship.extensions ? { ...relationship.extensions } : undefined,
  }
}

function closeRelationshipDialog() {
  if (pendingSelfJoinOccurrenceId.value) designer.deleteOccurrence(pendingSelfJoinOccurrenceId.value)
  pendingSelfJoinOccurrenceId.value = ''
  relationshipDialogOpen.value = false
  relationshipForm.value = null
}

function saveRelationship(relationship: DesignRelationship) {
  if (relationshipDialogIsNew.value) {
    const pendingId = pendingSelfJoinOccurrenceId.value
    if (pendingId && relationship.leftOccurrenceId !== pendingId && relationship.rightOccurrenceId !== pendingId) {
      designer.deleteOccurrence(pendingId)
    }
    if (!designer.createRelationship(relationship)) return
    pendingSelfJoinOccurrenceId.value = ''
  } else designer.updateRelationship(relationship.id, relationship)
  closeRelationshipDialog()
}

function deleteRelationship(id: string) {
  designer.deleteRelationship(id)
  closeRelationshipDialog()
}

function clamp(value: number, minimum: number, maximum: number) { return Math.min(maximum, Math.max(minimum, value)) }

async function initializeDesigner() {
  if (!designerUnlocked.value) return
  if (!designer.project) designer.loadAiDesign(relationshipDesignSample)
  await nextTick()
  await fitToScreen()
}

async function refreshLicense() {
  refreshingLicense.value = true
  try {
    featureAccess.applyVerifiedLicense(await licenseGateway.refresh())
  } finally {
    refreshingLicense.value = false
  }
}

watch(designerUnlocked, (unlocked, wasUnlocked) => {
  if (unlocked && !wasUnlocked) void initializeDesigner()
})

onMounted(async () => {
  await refreshLicense()
  await initializeDesigner()
})
onBeforeUnmount(() => {
  if (componentCardScrollAnimationFrame) cancelAnimationFrame(componentCardScrollAnimationFrame)
  stopInteraction()
  if (pendingSelfJoinOccurrenceId.value) designer.deleteOccurrence(pendingSelfJoinOccurrenceId.value)
})
</script>

<template>
  <section v-if="!designerUnlocked" class="relationship-pro-gate">
    <div class="relationship-pro-card">
      <div class="relationship-pro-icon material-icons">hub</div>
      <div class="relationship-pro-copy">
        <div class="relationship-pro-eyebrow">VRTEX FM ENGINE PRO</div>
        <h1>AIリレーションシップデザイナー</h1>
        <p>AIリレーションシップデザイナーはVRTEX FM Engine Proで利用できます。</p>
        <p class="relationship-pro-note">
          テーブルオカレンス、リレーション、検証結果などのProjectデータは保持されます。Proライセンスを有効化すると、そのまま編集を再開できます。
        </p>
        <div class="relationship-pro-features">
          <span><i class="material-icons">check_circle</i>テーブルオカレンス設計</span>
          <span><i class="material-icons">check_circle</i>フィールド間リレーション</span>
          <span><i class="material-icons">check_circle</i>自動整列・設計検証</span>
          <span><i class="material-icons">check_circle</i>FileMaker連携</span>
        </div>
        <div class="relationship-pro-actions">
          <button type="button" class="relationship-license-button" :disabled="refreshingLicense" @click="refreshLicense">
            <span class="material-icons">refresh</span>
            {{ refreshingLicense ? 'ライセンスを確認中…' : 'ライセンスを再確認' }}
          </button>
          <span class="relationship-license-state">{{ license.tier.toUpperCase() }} · {{ license.status }}</span>
        </div>
      </div>
    </div>
  </section>

  <section v-else class="relationship-workspace">
    <aside class="design-project-pane">
      <header class="relationship-pane-title">
        <span class="material-icons">schema</span>
        <div><small>VRTEX PRO · {{ text.phase }}</small><strong>{{ text.project }}</strong></div>
      </header>
      <section class="project-summary">
        <span class="project-kicker">AI DESIGN MODEL</span>
        <h2>{{ project?.name }}</h2>
        <p>{{ project?.description }}</p>
        <div class="project-metrics">
          <span><b>{{ project?.tables.length ?? 0 }}</b><small class="metric-label">{{ text.tables }}</small></span>
          <span><b>{{ project?.tableOccurrences.length ?? 0 }}</b><small class="metric-label">{{ locale.language === 'ja' ? 'テーブル\nオカレンス' : 'Table\nOccurrences' }}</small></span>
          <span><b>{{ project?.relationships.length ?? 0 }}</b><small class="metric-label">{{ text.relationships }}</small></span>
        </div>
      </section>
      <div class="occurrence-tree-heading"><strong>{{ text.occurrences }}</strong><span>{{ project?.tableOccurrences.length ?? 0 }}</span></div>
      <div class="occurrence-tree">
        <button v-for="occurrence in project?.tableOccurrences" :key="occurrence.id" type="button" :class="{ active: selectedOccurrenceIds.has(occurrence.id) }" @click="designer.selectOccurrence(occurrence.id, $event.shiftKey || $event.ctrlKey || $event.metaKey)">
          <span class="material-icons">table_view</span>
          <span><strong>{{ occurrence.name }}</strong><small>{{ tableFor(occurrence)?.name }}</small></span>
          <em>{{ tableFor(occurrence)?.fields.length ?? 0 }}</em>
        </button>
      </div>
      <footer class="design-validation-summary" :class="{ invalid: !designer.validation.valid }">
        <span class="material-icons">{{ designer.validation.valid ? 'verified' : 'warning' }}</span>
        <div><strong>{{ text.validation }} · {{ designer.validation.valid ? text.valid : text.errors }}</strong><small>{{ designer.validation.errors.length }} {{ text.errors }} / {{ designer.validation.warnings.length }} {{ text.warnings }}</small></div>
      </footer>
    </aside>

    <main class="relationship-canvas-pane">
      <header class="canvas-toolbar">
        <div><span class="material-icons">hub</span><div><small>{{ text.canvas }}</small><strong>{{ text.title }}</strong></div></div>
        <div class="canvas-actions">
          <button type="button" aria-label="Zoom out" @click="zoomBy(.85)"><span class="material-icons">remove</span></button>
          <span class="zoom-value">{{ zoomLabel }}</span>
          <button type="button" aria-label="Zoom in" @click="zoomBy(1.18)"><span class="material-icons">add</span></button>
          <i />
          <button type="button" :title="text.fit" @click="fitToScreen"><span class="material-icons">fit_screen</span>{{ text.fit }}</button>
          <button type="button" :title="text.reset" @click="resetView"><span class="material-icons">center_focus_strong</span></button>
        </div>
      </header>
      <div ref="viewport" class="relationship-canvas-viewport" :class="{ panning, selecting }" :style="viewportGridStyle" @pointerdown="startCanvasInteraction" @contextmenu.prevent @wheel.prevent="handleWheel">
        <div class="canvas-world" :style="worldStyle">
          <svg class="relationship-layer" viewBox="0 0 4800 3200" aria-label="リレーションシップ">
            <g
              v-for="item in relationshipPaths"
              :key="item.relationship.id"
              class="relationship-link"
              :class="{ selected: designer.selectedRelationship?.id === item.relationship.id }"
              @click.stop="designer.selectRelationship(item.relationship.id)"
              @dblclick.stop.prevent="editRelationship(item.relationship)"
            >
              <path
                class="relationship-link-hit"
                :d="item.path"
                @click.stop="designer.selectRelationship(item.relationship.id)"
                @dblclick.stop.prevent="editRelationship(item.relationship)"
              />
              <path class="relationship-link-line" :d="item.path" />
              <circle class="relationship-endpoint" :cx="item.start.x" :cy="item.start.y" r="4" />
              <circle class="relationship-endpoint" :cx="item.end.x" :cy="item.end.y" r="4" />
            </g>
            <path v-if="draftPath" class="relationship-draft-line" :d="draftPath" />
          </svg>
          <button
            v-for="item in relationshipPaths"
            :key="`badge-${item.relationship.id}`"
            type="button"
            class="relationship-badge"
            :class="{ selected: designer.selectedRelationship?.id === item.relationship.id }"
            :style="{ transform: `translate3d(${item.midpoint.x - 14}px, ${item.midpoint.y - 11}px, 0)` }"
            title="ダブルクリックしてリレーションシップを編集"
            @click.stop="editRelationship(item.relationship)"
            @dblclick.stop.prevent="editRelationship(item.relationship)"
          >{{ item.symbol }}</button>
          <article
            v-for="occurrence in project?.tableOccurrences"
            :key="occurrence.id"
            class="to-card"
            :class="{ selected: selectedOccurrenceIds.has(occurrence.id), dragging: draggingIds.includes(occurrence.id), resizing: resizingId === occurrence.id, collapsed: occurrence.collapsed }"
            :style="{ width: `${occurrence.width}px`, height: `${occurrenceHeight(occurrence)}px`, transform: `translate3d(${occurrence.x}px, ${occurrence.y}px, 0)` }"
            tabindex="0"
            @click.stop="selectCardFromClick($event, occurrence.id)"
            @keydown.enter="designer.selectOccurrence(occurrence.id)"
            @wheel="handleOccurrenceWheel(occurrence.id, $event)"
          >
            <header @pointerdown="startCardDrag($event, occurrence)" @dblclick.stop.prevent="openOccurrenceRename(occurrence)">
              <span class="to-table-icon material-icons">table_rows</span>
              <div><strong>{{ occurrence.name }}</strong><small>{{ tableFor(occurrence)?.name }}</small></div>
              <button type="button" :title="occurrence.collapsed ? text.expand : text.collapse" @pointerdown.stop @click.stop="toggleCollapsed(occurrence)"><span class="material-icons">{{ occurrence.collapsed ? 'expand_more' : 'expand_less' }}</span></button>
            </header>
            <div v-if="!occurrence.collapsed" class="to-field-list" @scroll="onFieldScroll(occurrence.id, $event)">
              <div
                v-for="field in tableFor(occurrence)?.fields"
                :key="field.id"
                data-field-drop
                :data-occurrence-id="occurrence.id"
                :data-field-id="field.id"
                title="ドラッグして別のフィールドへ接続"
                :class="{
                  key: field.isPrimaryKey || field.isForeignKey,
                  related: isFieldRelated(occurrence.id, field.id),
                  'connection-target': isConnectionTarget(occurrence.id, field.id),
                  'connection-source': isConnectionSource(occurrence.id, field.id),
                }"
                @pointerdown="startFieldRowLink($event, occurrence, field.id)"
              >
                <span class="field-dot-slot"><i class="field-connection-dot" :class="{ visible: isFieldSideRelated(occurrence.id, field.id, 'left') }" /></span>
                <span class="field-key">{{ field.isPrimaryKey ? 'PK' : field.isForeignKey ? 'FK' : '' }}</span>
                <span class="field-name">{{ field.name }}</span>
                <small>{{ field.type }}</small>
                <span class="field-dot-slot"><i class="field-connection-dot" :class="{ visible: isFieldSideRelated(occurrence.id, field.id, 'right') }" /></span>
              </div>
            </div>
            <footer v-if="!occurrence.collapsed"><span>{{ tableFor(occurrence)?.fields.length ?? 0 }} FIELDS</span><span>{{ Math.round(occurrence.x) }}, {{ Math.round(occurrence.y) }}</span></footer>
            <i class="to-resize-handle resize-left" @pointerdown="startOccurrenceResize($event, occurrence, 'left')" />
            <i class="to-resize-handle resize-right" @pointerdown="startOccurrenceResize($event, occurrence, 'right')" />
            <i v-if="!occurrence.collapsed" class="to-resize-handle resize-top" @pointerdown="startOccurrenceResize($event, occurrence, 'top')" />
            <i v-if="!occurrence.collapsed" class="to-resize-handle resize-bottom" @pointerdown="startOccurrenceResize($event, occurrence, 'bottom')" />
          </article>
          <div v-if="selectionBoxStyle" class="occurrence-selection-box" :style="selectionBoxStyle" />
        </div>
        <div class="canvas-help"><span class="material-icons">select_all</span>フィールド行：接続 · 空白左ドラッグ：領域選択 · TOヘッダー：複数移動 · 右ドラッグ：画面移動</div>
      </div>
    </main>

    <aside class="design-inspector-pane">
      <header class="relationship-pane-title"><span class="material-icons">tune</span><div><small>DESIGN OBJECT</small><strong>{{ text.inspector }}</strong></div></header>
      <div class="design-inspector-content">
        <template v-if="selectedOccurrence && selectedTable">
          <section class="inspector-identity">
            <span class="material-icons">table_view</span>
            <div><small>TABLE OCCURRENCE</small><strong>{{ selectedOccurrence.name }}</strong><p>{{ selectedTable.description }}</p></div>
          </section>
          <dl class="design-property-list">
            <div><dt>{{ text.baseTable }}</dt><dd>{{ selectedTable.name }}</dd></div>
            <div><dt>{{ text.position }}</dt><dd>X {{ Math.round(selectedOccurrence.x) }} · Y {{ Math.round(selectedOccurrence.y) }}</dd></div>
            <div><dt>WIDTH</dt><dd>{{ selectedOccurrence.width }} px</dd></div>
            <div><dt>HEIGHT</dt><dd>{{ Math.round(occurrenceHeight(selectedOccurrence)) }} px</dd></div>
            <div><dt>{{ text.fields }}</dt><dd>{{ selectedTable.fields.length }}</dd></div>
          </dl>
          <section class="inspector-field-list">
            <header><strong>{{ text.fields }}</strong><span>{{ selectedTable.fields.length }}</span></header>
            <div v-for="field in selectedTable.fields" :key="field.id">
              <span class="material-icons">{{ field.isPrimaryKey ? 'key' : field.isForeignKey ? 'link' : 'short_text' }}</span>
              <div><strong>{{ field.name }}</strong><small>{{ field.type }}<template v-if="field.isRequired"> · {{ text.required }}</template></small></div>
              <em v-if="field.isPrimaryKey">PK</em><em v-else-if="field.isForeignKey">FK</em>
            </div>
          </section>
        </template>
        <div v-else class="inspector-empty"><span class="material-icons">ads_click</span><p>{{ text.noSelection }}</p></div>
      </div>
      <section class="filemaker-send-panel" :class="{ available: fileMakerSendState.available }">
        <header><span>{{ text.fileMakerSend }}</span><em>{{ fileMakerSendState.available ? text.sendAvailable : text.sendUnavailable }}</em></header>
        <button type="button" :disabled="!fileMakerSendState.available || sendingToFileMaker" @click="sendFocusedObjectToFileMaker">
          <span class="material-icons">{{ fileMakerSendState.available ? 'outbox' : 'block' }}</span>
          <span><strong>{{ sendingToFileMaker ? text.sending : fileMakerSendState.available ? text.sendToFileMaker : text.sendUnavailable }}</strong><small>{{ fileMakerSendState.reason }}</small></span>
          <span class="material-icons arrow">arrow_forward</span>
        </button>
      </section>
    </aside>

    <section class="component-card-tray">
      <header>
        <div class="component-card-title"><span class="material-icons">view_carousel</span><strong>{{ text.cards }}</strong><button type="button" title="設計からカードを再生成" @click="designer.regenerateComponentCards"><span class="material-icons">refresh</span></button></div>
        <div v-if="selectedOccurrences.length > 1" class="occurrence-layout-tools" aria-label="選択中のテーブルオカレンスを整列">
          <span class="selected-to-count">{{ selectedOccurrences.length }} TO SELECTED</span>
          <button type="button" title="選択TOを左揃え" aria-label="左揃え" @click="alignSelectedOccurrences('left')"><span class="material-icons">align_horizontal_left</span></button>
          <button type="button" title="選択TOを左右中央揃え" aria-label="左右中央揃え" @click="alignSelectedOccurrences('center')"><span class="material-icons">align_horizontal_center</span></button>
          <button type="button" title="選択TOを右揃え" aria-label="右揃え" @click="alignSelectedOccurrences('right')"><span class="material-icons">align_horizontal_right</span></button>
          <i />
          <button type="button" title="選択TOを上揃え" aria-label="上揃え" @click="alignSelectedOccurrences('top')"><span class="material-icons">align_vertical_top</span></button>
          <button type="button" title="選択TOを上下中央揃え" aria-label="上下中央揃え" @click="alignSelectedOccurrences('middle')"><span class="material-icons">align_vertical_center</span></button>
          <button type="button" title="選択TOを下揃え" aria-label="下揃え" @click="alignSelectedOccurrences('bottom')"><span class="material-icons">align_vertical_bottom</span></button>
          <i />
          <button type="button" title="選択TOを横方向に等間隔配置" aria-label="横方向に等間隔" :disabled="selectedOccurrences.length < 3" @click="distributeSelectedOccurrences('horizontal')"><span class="material-icons">horizontal_distribute</span></button>
          <button type="button" title="選択TOを縦方向に等間隔配置" aria-label="縦方向に等間隔" :disabled="selectedOccurrences.length < 3" @click="distributeSelectedOccurrences('vertical')"><span class="material-icons">vertical_distribute</span></button>
          <i />
          <button type="button" class="auto-layout-button" title="アンカー・ブイ方式で自動整列" aria-label="アンカー・ブイ自動整列" @click="arrangeSelectedAnchorBuoy"><span class="material-icons">account_tree</span><strong>自動整列</strong></button>
        </div>
        <span>{{ project?.componentCards.length ?? 0 }} CARDS</span>
      </header>
      <div class="component-card-scroll" tabindex="0" aria-label="コンポーネントカード一覧。マウスホイールで左右にスクロールできます" @wheel.prevent.stop="handleComponentCardWheel">
        <article v-for="card in project?.componentCards" :key="card.id" class="component-engine-card" :class="[`status-${card.status}`, { active: designer.selectedComponentCardId === card.id }]" tabindex="0" role="button" @click="openCardDetails(card)" @keydown.enter="openCardDetails(card)">
          <span class="card-step">STEP {{ String(card.sequence).padStart(2, '0') }}</span>
          <span class="material-icons">{{ card.executionMode === 'manual' ? 'construction' : card.kind === 'table' ? 'table_chart' : card.kind === 'script' ? 'code' : 'inventory_2' }}</span>
          <div><small>{{ cardTypeLabel(card) }}</small><strong>{{ card.title }}</strong><p>{{ card.description }}</p></div>
          <span class="card-state"><em>{{ statusLabel(card.status) }}</em><small v-if="!cardDependencyState(card).ready"><span class="material-icons">warning</span>{{ text.dependencyPending }}</small><small v-else><span class="material-icons">{{ card.validationResult.valid ? 'check_circle' : 'error' }}</span>{{ card.validationResult.errors.length }}E / {{ card.validationResult.warnings.length }}W</small><button type="button" :disabled="!cardCanCopy(card)" :title="cardCanCopy(card) ? text.sendToFileMaker : fileMakerSendState.reason" @click.stop="sendCardToFileMaker(card)"><span class="material-icons">outbox</span>Copy</button></span>
        </article>
      </div>
    </section>

    <RelationshipEditorDialog
      :open="relationshipDialogOpen"
      :project="project"
      :relationship="relationshipForm"
      :is-new="relationshipDialogIsNew"
      @close="closeRelationshipDialog"
      @save="saveRelationship"
      @delete="deleteRelationship"
    />

    <div v-if="cardDetailOpen && designer.selectedComponentCard" class="component-card-backdrop" @pointerdown.self="closeCardDetails" @keydown.esc="closeCardDetails">
      <section class="component-card-dialog" role="dialog" aria-modal="true" aria-labelledby="component-card-title">
        <header>
          <span class="material-icons">{{ designer.selectedComponentCard.executionMode === 'manual' ? 'construction' : 'inventory_2' }}</span>
          <div><small>STEP {{ String(designer.selectedComponentCard.sequence).padStart(2, '0') }} / {{ String(project?.componentCards.length ?? 0).padStart(2, '0') }} · {{ cardTypeLabel(designer.selectedComponentCard) }}</small><h2 id="component-card-title">{{ text.cardDetail }}</h2></div>
          <span class="dialog-status" :class="`status-${designer.selectedComponentCard.status}`">{{ statusLabel(designer.selectedComponentCard.status) }}</span>
          <button type="button" aria-label="閉じる" @click="closeCardDetails"><span class="material-icons">close</span></button>
        </header>
        <div class="component-card-detail-scroll">
          <section class="card-detail-summary">
            <label>Title<input v-model="cardEditTitle" maxlength="160" /></label>
            <label>Description<textarea v-model="cardEditDescription" rows="2" /></label>
            <p v-if="designer.selectedComponentCard.aiExplanation"><span class="material-icons">auto_awesome</span>{{ designer.selectedComponentCard.aiExplanation }}</p>
            <button type="button" @click="saveCardDetails"><span class="material-icons">save</span>{{ text.saveChanges }}</button>
          </section>
          <section class="card-detail-grid">
            <article><header>ELEMENTS <span>{{ designer.selectedComponentCard.elements.length }}</span></header><ul><li v-for="element in designer.selectedComponentCard.elements" :key="element">{{ element }}</li></ul></article>
            <article><header>DEPENDENCIES <span>{{ designer.selectedComponentCard.dependencies.length }}</span></header><ul><li v-if="!designer.selectedComponentCard.dependencies.length">なし</li><li v-for="dependencyId in designer.selectedComponentCard.dependencies" :key="dependencyId"><span class="material-icons">{{ project?.componentCards.find((card) => card.id === dependencyId)?.status === 'verified' ? 'check_circle' : 'schedule' }}</span>{{ project?.componentCards.find((card) => card.id === dependencyId)?.title ?? dependencyId }}</li></ul></article>
          </section>
          <section class="card-validation-detail"><header><span>{{ text.validationResult }}</span><span class="validation-actions"><button type="button" :disabled="repairingCard" @click="repairFocusedCard"><span class="material-icons">auto_fix_high</span>{{ repairingCard ? 'AI修正中…' : 'AIで修正' }}</button><button type="button" @click="validateFocusedCard"><span class="material-icons">fact_check</span>{{ text.validateCard }}</button></span></header><p v-if="designer.selectedComponentCard.validationResult.valid"><span class="material-icons">check_circle</span>Ready · {{ designer.selectedComponentCard.validationResult.warnings.length }} Warning</p><p v-for="issue in [...designer.selectedComponentCard.validationResult.errors, ...designer.selectedComponentCard.validationResult.warnings]" :key="issue.code + issue.message" :class="issue.level"><span class="material-icons">{{ issue.level === 'error' ? 'error' : 'warning' }}</span>{{ issue.message }}</p></section>
          <details v-if="designer.selectedComponentCard.generatedXml" class="card-xml-detail"><summary>{{ text.xmlSource }} · {{ designer.selectedComponentCard.clipboardFormat }}</summary><pre>{{ designer.selectedComponentCard.generatedXml }}</pre></details>
          <section class="card-history-detail"><header>{{ text.history }} <span>{{ designer.selectedComponentCard.history.length }}</span></header><ol><li v-for="entry in [...designer.selectedComponentCard.history].reverse().slice(0, 8)" :key="entry.id"><time>{{ new Date(entry.timestamp).toLocaleString(locale.language === 'ja' ? 'ja-JP' : 'en-US') }}</time><strong>{{ entry.action }}</strong><span>{{ entry.detail }}</span></li></ol></section>
        </div>
        <footer>
          <div><button type="button" :disabled="!fileMakerSendState.available" @click="sendFocusedObjectToFileMaker"><span class="material-icons">outbox</span>{{ text.sendToFileMaker }}</button><button type="button" @click="updateFocusedCardStatus('skipped')">Skip</button><button type="button" :disabled="designer.selectedComponentCard.executionMode === 'clipboard' ? designer.selectedComponentCard.status !== 'copied' : !['ready', 'warning'].includes(designer.selectedComponentCard.status)" @click="updateFocusedCardStatus('applied')">{{ text.applied }}</button><button type="button" :disabled="designer.selectedComponentCard.status !== 'applied'" @click="updateFocusedCardStatus('verified')">{{ text.verified }}</button></div>
          <button type="button" class="next-card-button" @click="openNextCard">{{ text.nextCard }}<span class="material-icons">arrow_forward</span></button>
        </footer>
      </section>
    </div>

    <div v-if="renameDialogOpen" class="occurrence-name-backdrop" @pointerdown.self="closeOccurrenceRename" @keydown.esc="closeOccurrenceRename">
      <form class="occurrence-name-dialog" role="dialog" aria-modal="true" aria-labelledby="occurrence-name-title" @submit.prevent="saveOccurrenceRename">
        <header>
          <span class="material-icons">edit</span>
          <div><small>TABLE OCCURRENCE</small><h2 id="occurrence-name-title">オカレンス名を変更</h2></div>
          <button type="button" aria-label="閉じる" @click="closeOccurrenceRename"><span class="material-icons">close</span></button>
        </header>
        <label for="occurrence-name-input">オカレンス名</label>
        <input id="occurrence-name-input" ref="renameInput" v-model="renameValue" maxlength="120" autocomplete="off" @keydown.esc.prevent="closeOccurrenceRename" />
        <p :class="{ error: renameError }">{{ renameError || 'リレーションシップグラフで識別しやすい一意の名前を入力してください。' }}</p>
        <footer><button type="button" @click="closeOccurrenceRename">キャンセル</button><button type="submit" class="primary" :disabled="!!renameError">変更する</button></footer>
      </form>
    </div>
  </section>
</template>

<style scoped>
.relationship-workspace{display:grid;min-width:0;min-height:0;grid-template-columns:210px minmax(720px,1fr) 270px;grid-template-rows:minmax(0,1fr) 118px;overflow:hidden;background:var(--bg-deep);color:var(--text)}
.design-project-pane,.design-inspector-pane,.relationship-canvas-pane{min-width:0;min-height:0}.design-project-pane{display:flex;grid-column:1;grid-row:1/3;flex-direction:column;border-right:1px solid var(--line-bright);background:var(--bg-inset)}.relationship-canvas-pane{grid-column:2;grid-row:1}.design-inspector-pane{display:flex;grid-column:3;grid-row:1/3;overflow:hidden;flex-direction:column;border-left:1px solid var(--line-bright);background:var(--bg-panel)}.design-inspector-content{min-height:0;flex:1;overflow-y:auto}
.relationship-pane-title{display:flex;height:62px;flex:none;align-items:center;padding:0 14px;gap:10px;border-bottom:1px solid var(--line-bright);background:var(--bg-panel-raised)}.relationship-pane-title>.material-icons{display:grid;width:34px;height:34px;place-items:center;border:1px solid rgba(var(--accent-rgb),.45);border-radius:5px;background:var(--blue-soft);color:var(--blue-bright);font-size:19px}.relationship-pane-title>div{display:flex;min-width:0;flex-direction:column}.relationship-pane-title small{color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.1em}.relationship-pane-title strong{margin-top:3px;color:var(--text);font-size:13px}
.project-summary{padding:15px;border-bottom:1px solid var(--line)}.project-kicker{color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.12em}.project-summary h2{margin:7px 0 4px;color:var(--text);font-size:16px}.project-summary p{height:34px;overflow:hidden;margin:0;color:var(--muted);font-size:9.5px;line-height:1.7}.project-metrics{display:grid;margin-top:13px;grid-template-columns:repeat(3,minmax(0,1fr));gap:5px}.project-metrics>span{display:grid;min-width:0;min-height:68px;align-content:center;justify-items:center;padding:6px 2px;grid-template-rows:18px 28px;border:1px solid var(--line);border-radius:3px;background:var(--bg-panel);color:var(--muted);text-align:center}.project-metrics b{margin:0;color:var(--blue-bright);font:14px/18px "Cascadia Code",monospace;text-align:center}.metric-label{display:grid;min-width:0;max-width:100%;align-content:center;justify-items:center;color:var(--muted);font-size:7.5px;line-height:1.25;overflow-wrap:normal;white-space:pre-line;word-break:keep-all;text-align:center}
.occurrence-tree-heading{display:flex;height:40px;flex:none;align-items:center;justify-content:space-between;padding:0 13px;color:var(--muted);font-size:9px;letter-spacing:.08em}.occurrence-tree-heading span{font:9px "Cascadia Code",monospace}.occurrence-tree{min-height:0;flex:1;overflow:auto;padding:0 8px 10px}.occurrence-tree button{display:grid;width:100%;min-height:50px;align-items:center;margin-bottom:4px;padding:6px 8px;grid-template-columns:23px minmax(0,1fr) auto;gap:6px;border:1px solid transparent;border-radius:4px;background:transparent;color:var(--muted);cursor:pointer;text-align:left}.occurrence-tree button:hover{border-color:var(--line-bright);background:var(--bg-hover)}.occurrence-tree button.active{border-color:var(--blue);background:linear-gradient(90deg,rgba(var(--accent-rgb),.2),var(--bg-panel));box-shadow:inset 2px 0 var(--blue-bright)}.occurrence-tree .material-icons{color:var(--blue-bright);font-size:16px}.occurrence-tree button>span:nth-child(2){display:flex;min-width:0;flex-direction:column}.occurrence-tree strong{overflow:hidden;color:var(--text);font-size:10.5px;text-overflow:ellipsis;white-space:nowrap}.occurrence-tree small{margin-top:2px;color:var(--muted);font-size:8px}.occurrence-tree em{color:var(--blue-bright);font:8px "Cascadia Code",monospace;font-style:normal}.design-validation-summary{display:flex;min-height:56px;flex:none;align-items:center;padding:9px 12px;gap:8px;border-top:1px solid var(--line-bright);background:rgba(29,111,81,.1)}.design-validation-summary>.material-icons{color:var(--green);font-size:18px}.design-validation-summary>div{display:flex;flex-direction:column}.design-validation-summary strong{color:var(--text);font-size:9px}.design-validation-summary small{margin-top:3px;color:var(--muted);font-size:8px}.design-validation-summary.invalid>.material-icons{color:var(--red)}
.relationship-canvas-pane{display:grid;grid-template-rows:62px minmax(0,1fr);overflow:hidden;background:var(--bg-deep)}.canvas-toolbar{display:flex;align-items:center;justify-content:space-between;padding:0 14px;border-bottom:1px solid var(--line-bright);background:linear-gradient(90deg,rgba(var(--accent-rgb),.12),var(--bg-panel))}.canvas-toolbar>div:first-child{display:flex;align-items:center;gap:9px}.canvas-toolbar>div:first-child>.material-icons{color:var(--blue-bright);font-size:24px}.canvas-toolbar>div:first-child>div{display:flex;flex-direction:column}.canvas-toolbar small{color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.13em}.canvas-toolbar strong{margin-top:3px;color:var(--text);font-size:13px}.canvas-actions{display:flex;align-items:center;gap:4px}.canvas-actions button{display:flex;height:30px;align-items:center;padding:0 8px;gap:4px;border:1px solid var(--line-bright);border-radius:3px;background:var(--bg-panel-raised);color:var(--muted);cursor:pointer;font-size:9px}.canvas-actions button:hover{border-color:var(--blue);color:var(--text)}.canvas-actions .material-icons{font-size:15px}.canvas-actions>i{width:1px;height:22px;margin:0 4px;background:var(--line-bright)}.zoom-value{min-width:44px;color:var(--blue-bright);font:9px "Cascadia Code",monospace;text-align:center}
.relationship-canvas-viewport{position:relative;min-height:0;overflow:hidden;background-color:var(--bg-deep);background-image:linear-gradient(rgba(var(--accent-rgb),.04) 1px,transparent 1px),linear-gradient(90deg,rgba(var(--accent-rgb),.04) 1px,transparent 1px),radial-gradient(circle,rgba(var(--accent-rgb),.24) 1px,transparent 1px);background-repeat:repeat;cursor:default;touch-action:none;user-select:none}.relationship-canvas-viewport.selecting{cursor:crosshair}.relationship-canvas-viewport.panning{cursor:grabbing}.canvas-world{position:absolute;top:0;left:0;width:4800px;height:3200px;transform-origin:0 0;will-change:transform}.occurrence-selection-box{position:absolute;z-index:20;top:0;left:0;border:1px solid var(--blue-bright);background:rgba(var(--accent-rgb),.12);box-shadow:inset 0 0 0 1px rgba(var(--accent-rgb),.12),0 0 12px rgba(var(--accent-rgb),.18);pointer-events:none}.canvas-help{position:absolute;right:12px;bottom:10px;display:flex;align-items:center;padding:6px 9px;gap:5px;border:1px solid var(--line-bright);border-radius:3px;background:color-mix(in srgb,var(--bg-panel) 91%,transparent);color:var(--muted);font:8px "Cascadia Code",monospace;pointer-events:none}.canvas-help .material-icons{color:var(--blue-bright);font-size:14px}
.relationship-layer{position:absolute;z-index:1;inset:0;width:4800px;height:3200px;overflow:visible;pointer-events:none}.relationship-link{pointer-events:none}.relationship-link-hit{fill:none;stroke:transparent;stroke-width:18;pointer-events:stroke;cursor:pointer}.relationship-link-line{fill:none;stroke:color-mix(in srgb,var(--blue-bright) 72%,var(--muted));stroke-width:2;pointer-events:none;filter:drop-shadow(0 0 2px rgba(var(--accent-rgb),.28))}.relationship-link:hover .relationship-link-line,.relationship-link.selected .relationship-link-line{stroke:var(--blue-bright);stroke-width:3;filter:drop-shadow(0 0 5px rgba(var(--accent-rgb),.72))}.relationship-endpoint{fill:var(--bg-deep);stroke:var(--blue-bright);stroke-width:2;pointer-events:none}.relationship-operator{pointer-events:all;cursor:pointer}.relationship-operator rect{fill:var(--bg-panel-raised);stroke:var(--blue);stroke-width:1.5}.relationship-operator text{fill:var(--text);font:11px "Cascadia Code",monospace;font-weight:800;user-select:none}.relationship-link.selected .relationship-operator rect{fill:var(--blue-soft);stroke:var(--blue-bright)}.relationship-draft-line{fill:none;stroke:var(--blue-bright);stroke-width:2.5;stroke-dasharray:7 5;pointer-events:none;filter:drop-shadow(0 0 5px rgba(var(--accent-rgb),.8))}
.relationship-badge{position:absolute;z-index:3;top:0;left:0;display:grid;width:28px;height:22px;place-items:center;padding:0;border:1px solid var(--blue);border-radius:4px;background:var(--bg-panel-raised);color:var(--text);font:11px "Cascadia Code",monospace;font-weight:800;cursor:pointer}.relationship-badge:hover,.relationship-badge.selected{border-color:var(--blue-bright);background:var(--blue-soft);box-shadow:0 0 7px rgba(var(--accent-rgb),.55)}
.to-card{position:absolute;z-index:2;top:0;left:0;display:flex;overflow:hidden;flex-direction:column;border:1px solid var(--line-bright);border-radius:5px;outline:0;background:var(--bg-panel);box-shadow:0 8px 24px rgba(0,0,0,.28);cursor:default;will-change:transform}.to-card.selected{border-color:var(--blue-bright);box-shadow:0 0 0 1px rgba(var(--accent-rgb),.2),0 8px 26px rgba(var(--accent-rgb),.18)}.to-card.dragging,.to-card.resizing{z-index:10;opacity:.94;box-shadow:0 15px 40px rgba(0,0,0,.42),0 0 0 2px rgba(var(--accent-rgb),.32)}.to-card>header{display:flex;height:52px;flex:none;align-items:center;padding:0 8px;gap:7px;border-bottom:1px solid var(--line-bright);background:linear-gradient(135deg,rgba(var(--accent-rgb),.18),var(--bg-panel-raised));cursor:move}.to-table-icon{display:grid;width:28px;height:28px;flex:none;place-items:center;border-radius:4px;background:var(--blue-soft);color:var(--blue-bright);font-size:16px}.to-card>header>div{display:flex;min-width:0;flex:1;flex-direction:column}.to-card>header strong{overflow:hidden;color:var(--text);font-size:13px;text-overflow:ellipsis;white-space:nowrap}.to-card>header small{margin-top:2px;color:var(--muted);font-size:10px}.to-card>header button{display:grid;width:24px;height:24px;place-items:center;padding:0;border:0;background:transparent;color:var(--muted);cursor:pointer}.to-card>header button .material-icons{font-size:17px}.to-card.collapsed{height:53px}.to-card.collapsed>header{border-bottom:0}.to-field-list{min-height:0;flex:1;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;scrollbar-width:thin;scrollbar-color:color-mix(in srgb,var(--muted) 28%,transparent) transparent}.to-card:hover .to-field-list,.to-card:focus-within .to-field-list,.to-card.selected .to-field-list{scrollbar-color:var(--blue) var(--bg-inset)}.to-field-list::-webkit-scrollbar{width:8px}.to-field-list::-webkit-scrollbar-track{background:transparent}.to-field-list::-webkit-scrollbar-thumb{border:2px solid transparent;border-radius:8px;background:color-mix(in srgb,var(--muted) 28%,transparent);background-clip:padding-box}.to-card:hover .to-field-list::-webkit-scrollbar-track,.to-card:focus-within .to-field-list::-webkit-scrollbar-track,.to-card.selected .to-field-list::-webkit-scrollbar-track{background:var(--bg-inset)}.to-card:hover .to-field-list::-webkit-scrollbar-thumb,.to-card:focus-within .to-field-list::-webkit-scrollbar-thumb,.to-card.selected .to-field-list::-webkit-scrollbar-thumb{border-color:var(--bg-inset);background:var(--blue);background-clip:padding-box}.to-field-list>div{display:grid;height:32px;align-items:center;padding:0 3px;grid-template-columns:14px 25px minmax(0,1fr) auto 14px;gap:3px;border-bottom:1px solid var(--line);color:var(--muted);font-size:11px}.to-field-list>div.key{color:var(--text)}.field-key{color:var(--amber);font:9px "Cascadia Code",monospace;font-weight:800}.field-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.to-field-list small{color:var(--faint);font:9.5px "Cascadia Code",monospace}.field-port{display:block!important;width:10px!important;height:10px!important;min-width:10px;padding:0!important;border:2px solid var(--blue-bright)!important;border-radius:50%!important;background:var(--bg-deep)!important;cursor:crosshair!important;box-shadow:0 0 0 2px rgba(var(--accent-rgb),.08)}.field-port:hover{background:var(--blue-bright)!important;box-shadow:0 0 7px rgba(var(--accent-rgb),.9)}.to-card>footer{display:flex;height:25px;flex:none;align-items:center;justify-content:space-between;padding:0 7px;background:var(--bg-inset);color:var(--faint);font:9px "Cascadia Code",monospace}
.to-resize-handle{position:absolute;z-index:12;display:block}.resize-left,.resize-right{top:8px;bottom:8px;width:7px;cursor:ew-resize}.resize-left{left:-2px}.resize-right{right:-2px}.resize-top,.resize-bottom{right:8px;left:8px;height:7px;cursor:ns-resize}.resize-top{top:-2px}.resize-bottom{bottom:-2px}.to-card.selected .to-resize-handle::after,.to-card:hover .to-resize-handle::after{position:absolute;border-radius:3px;background:rgba(var(--accent-rgb),.38);content:""}.to-card.selected .resize-left::after,.to-card.selected .resize-right::after,.to-card:hover .resize-left::after,.to-card:hover .resize-right::after{top:34%;bottom:34%;width:1px}.resize-left::after{left:2px}.resize-right::after{right:2px}.to-card.selected .resize-top::after,.to-card.selected .resize-bottom::after,.to-card:hover .resize-top::after,.to-card:hover .resize-bottom::after{right:34%;left:34%;height:1px}.resize-top::after{top:2px}.resize-bottom::after{bottom:2px}
.to-field-list>div{font-size:13px;transition:background .14s,border-color .14s,box-shadow .14s}.to-field-list .field-name{font-size:13px;font-weight:600;letter-spacing:.01em}.to-field-list>div.related .field-name{color:var(--amber);font-weight:700;text-shadow:0 0 7px color-mix(in srgb,var(--amber) 38%,transparent)}.field-port.related{border-color:var(--amber)!important;background:color-mix(in srgb,var(--amber) 32%,var(--bg-deep))!important;box-shadow:0 0 6px color-mix(in srgb,var(--amber) 68%,transparent)}.field-port.related:hover{background:var(--amber)!important;box-shadow:0 0 9px color-mix(in srgb,var(--amber) 88%,transparent)}.to-field-list>div.connection-source{background:linear-gradient(90deg,rgba(var(--accent-rgb),.18),rgba(var(--accent-rgb),.05));box-shadow:inset 3px 0 var(--blue-bright)}.to-field-list>div.connection-target{background:linear-gradient(90deg,color-mix(in srgb,var(--amber) 24%,var(--bg-panel)),rgba(var(--accent-rgb),.12));box-shadow:inset 0 0 0 1px var(--amber),inset 4px 0 var(--amber),0 0 10px color-mix(in srgb,var(--amber) 22%,transparent)}.to-field-list>div.connection-target .field-name{color:var(--text);text-shadow:0 0 8px rgba(var(--accent-rgb),.65)}.to-field-list>div.connection-target .field-port{border-color:var(--amber)!important;background:var(--amber)!important;box-shadow:0 0 10px color-mix(in srgb,var(--amber) 90%,transparent);transform:scale(1.22)}
.to-field-list>div{cursor:crosshair}.to-field-list>div:hover:not(.connection-source):not(.connection-target){background:linear-gradient(90deg,rgba(var(--accent-rgb),.1),rgba(var(--accent-rgb),.025))}.to-field-list>div.related .field-name{color:color-mix(in srgb,var(--text) 78%,var(--muted));font-weight:700;text-shadow:none}.field-dot-slot{display:grid;width:14px;height:100%;place-items:center;pointer-events:none}.field-connection-dot{display:block;width:8px;height:8px;border-radius:50%;background:var(--blue-bright);box-shadow:0 0 7px rgba(var(--accent-rgb),.8);opacity:0;transform:scale(.65);transition:opacity .14s,transform .14s}.field-connection-dot.visible{opacity:1;transform:scale(1)}.to-field-list>div.connection-source{background:linear-gradient(90deg,rgba(var(--accent-rgb),.24),rgba(var(--accent-rgb),.07));box-shadow:inset 3px 0 var(--blue-bright),inset 0 0 0 1px rgba(var(--accent-rgb),.28)}.to-field-list>div.connection-target{background:linear-gradient(90deg,rgba(var(--accent-rgb),.3),rgba(var(--accent-rgb),.1));box-shadow:inset 0 0 0 1px var(--blue-bright),inset 4px 0 var(--blue-bright),0 0 11px rgba(var(--accent-rgb),.24)}.to-field-list>div.connection-target .field-name{color:var(--text);text-shadow:0 0 8px rgba(var(--accent-rgb),.65)}.to-field-list>div.connection-target .field-connection-dot{background:var(--blue-bright);box-shadow:0 0 10px rgba(var(--accent-rgb),.95)}
.inspector-identity{display:flex;padding:15px;gap:10px;border-bottom:1px solid var(--line)}.inspector-identity>.material-icons{display:grid;width:38px;height:38px;flex:none;place-items:center;border:1px solid var(--blue);border-radius:5px;background:var(--blue-soft);color:var(--blue-bright);font-size:20px}.inspector-identity>div{display:flex;min-width:0;flex-direction:column}.inspector-identity small{color:var(--blue-bright);font:7.5px "Cascadia Code",monospace;letter-spacing:.08em}.inspector-identity strong{margin-top:3px;color:var(--text);font-size:13px}.inspector-identity p{margin:3px 0 0;color:var(--muted);font-size:8.5px;line-height:1.45}.design-property-list{margin:0;padding:8px 14px;border-bottom:1px solid var(--line)}.design-property-list>div{display:flex;min-height:31px;align-items:center;justify-content:space-between}.design-property-list dt{color:var(--muted);font-size:8.5px}.design-property-list dd{margin:0;color:var(--text);font:8.5px "Cascadia Code",monospace}.inspector-field-list>header{display:flex;height:37px;align-items:center;justify-content:space-between;padding:0 13px;color:var(--muted);font-size:9px;letter-spacing:.08em}.inspector-field-list>header span{font-family:"Cascadia Code",monospace}.inspector-field-list>div{display:grid;min-height:44px;align-items:center;padding:5px 12px;grid-template-columns:20px minmax(0,1fr) auto;gap:6px;border-top:1px solid var(--line)}.inspector-field-list>.material-icons,.inspector-field-list>div>.material-icons{color:var(--blue-bright);font-size:14px}.inspector-field-list>div>div{display:flex;min-width:0;flex-direction:column}.inspector-field-list strong{color:var(--text);font-size:9.5px}.inspector-field-list small{margin-top:2px;color:var(--muted);font-size:7.5px}.inspector-field-list em{padding:2px 4px;border:1px solid color-mix(in srgb,var(--amber) 55%,transparent);border-radius:2px;color:var(--amber);font:7px "Cascadia Code",monospace;font-style:normal}.inspector-empty{display:grid;height:260px;place-content:center;justify-items:center;padding:20px;color:var(--muted);text-align:center}.inspector-empty .material-icons{font-size:32px}.inspector-empty p{max-width:190px;font-size:10px;line-height:1.6}
.filemaker-send-panel{flex:none;padding:11px 12px 13px;border-top:1px solid var(--line-bright);background:linear-gradient(180deg,var(--bg-panel-raised),var(--bg-inset))}.filemaker-send-panel>header{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;color:var(--muted);font:8px "Cascadia Code",monospace;letter-spacing:.09em}.filemaker-send-panel>header em{padding:3px 6px;border:1px solid color-mix(in srgb,var(--red) 55%,transparent);border-radius:10px;color:var(--red);font-size:7px;font-style:normal;letter-spacing:.04em}.filemaker-send-panel.available>header em{border-color:color-mix(in srgb,var(--green) 60%,transparent);color:var(--green)}.filemaker-send-panel>button{display:grid;width:100%;min-height:57px;align-items:center;padding:8px 9px;grid-template-columns:30px minmax(0,1fr) 18px;gap:7px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel);color:var(--muted);text-align:left}.filemaker-send-panel>button:disabled{cursor:not-allowed;opacity:.72}.filemaker-send-panel.available>button{border-color:var(--blue);background:linear-gradient(120deg,rgba(var(--accent-rgb),.28),rgba(var(--accent-rgb),.09));color:var(--text);cursor:pointer;box-shadow:inset 2px 0 var(--blue-bright)}.filemaker-send-panel>button>.material-icons:first-child{display:grid;width:30px;height:30px;place-items:center;border-radius:50%;background:var(--bg-inset);color:var(--red);font-size:17px}.filemaker-send-panel.available>button>.material-icons:first-child{background:var(--blue-soft);color:var(--blue-bright)}.filemaker-send-panel>button>span:nth-child(2){display:flex;min-width:0;flex-direction:column}.filemaker-send-panel>button strong{font-size:10.5px}.filemaker-send-panel>button small{overflow:hidden;margin-top:3px;color:var(--muted);font-size:7.5px;line-height:1.35;text-overflow:ellipsis}.filemaker-send-panel .arrow{color:var(--blue-bright);font-size:16px}.filemaker-send-panel>button:disabled .arrow{color:var(--faint)}
.occurrence-name-backdrop{position:fixed;z-index:9000;display:grid;inset:0;place-items:center;background:rgba(1,8,14,.76);backdrop-filter:blur(5px)}.occurrence-name-dialog{width:min(460px,calc(100vw - 40px));overflow:hidden;border:1px solid var(--blue-bright);border-radius:7px;background:var(--bg-panel-raised);box-shadow:0 24px 80px rgba(0,0,0,.58),0 0 24px rgba(var(--accent-rgb),.13)}.occurrence-name-dialog>header{display:grid;height:72px;align-items:center;padding:0 18px;grid-template-columns:38px minmax(0,1fr) 32px;gap:10px;border-bottom:1px solid var(--line-bright);background:linear-gradient(110deg,rgba(var(--accent-rgb),.18),var(--bg-panel-raised))}.occurrence-name-dialog>header>.material-icons{display:grid;width:36px;height:36px;place-items:center;border-radius:5px;background:var(--blue-soft);color:var(--blue-bright);font-size:20px}.occurrence-name-dialog>header>div{display:flex;flex-direction:column}.occurrence-name-dialog>header small{color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.12em}.occurrence-name-dialog h2{margin:4px 0 0;color:var(--text);font-size:17px}.occurrence-name-dialog>header button{display:grid;width:30px;height:30px;place-items:center;padding:0;border:0;background:transparent;color:var(--muted);cursor:pointer}.occurrence-name-dialog>header button:hover{color:var(--text)}.occurrence-name-dialog>header button .material-icons{font-size:19px}.occurrence-name-dialog>label{display:block;margin:20px 20px 8px;color:var(--muted);font-size:11px}.occurrence-name-dialog>input{display:block;width:calc(100% - 40px);height:44px;margin:0 20px;padding:0 12px;border:1px solid var(--line-bright);border-radius:4px;outline:0;background:var(--bg-inset);color:var(--text);font-size:15px}.occurrence-name-dialog>input:focus{border-color:var(--blue-bright);box-shadow:0 0 0 2px rgba(var(--accent-rgb),.15)}.occurrence-name-dialog>p{min-height:35px;margin:8px 20px 0;color:var(--muted);font-size:10px;line-height:1.5}.occurrence-name-dialog>p.error{color:var(--red)}.occurrence-name-dialog>footer{display:flex;height:62px;align-items:center;justify-content:flex-end;padding:0 20px;gap:8px;border-top:1px solid var(--line)}.occurrence-name-dialog>footer button{height:34px;padding:0 16px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel);color:var(--muted);cursor:pointer;font-size:11px}.occurrence-name-dialog>footer button:hover{border-color:var(--blue);color:var(--text)}.occurrence-name-dialog>footer button.primary{border-color:var(--blue);background:var(--blue);color:#fff;font-weight:700}.occurrence-name-dialog>footer button:disabled{cursor:not-allowed;opacity:.42}
.component-card-tray{display:grid;min-width:0;min-height:0;grid-template-rows:34px minmax(0,1fr);border-top:1px solid var(--line-bright);background:var(--bg-inset)}.component-card-tray>header{display:grid;align-items:center;padding:0 11px;grid-template-columns:minmax(145px,1fr) auto minmax(70px,1fr);gap:10px;border-bottom:1px solid var(--line);color:var(--muted);font:8px "Cascadia Code",monospace}.component-card-tray>header>.component-card-title{display:flex;align-items:center;gap:6px}.component-card-tray>header>span:last-child{justify-self:end}.component-card-tray>header .material-icons{color:var(--blue-bright);font-size:14px}.occurrence-layout-tools{display:flex;max-width:100%;height:28px;align-items:center;padding:2px 4px;gap:3px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel)}.selected-to-count{padding:0 6px;color:var(--blue-bright);font-size:7px;letter-spacing:.08em;white-space:nowrap}.occurrence-layout-tools button{display:grid;width:25px;height:23px;place-items:center;padding:0;border:1px solid transparent;border-radius:3px;background:transparent;color:var(--muted);cursor:pointer}.occurrence-layout-tools button:not(:disabled):hover{border-color:var(--blue);background:var(--blue-soft);color:var(--text)}.occurrence-layout-tools button:disabled{cursor:not-allowed;opacity:.32}.occurrence-layout-tools button .material-icons{font-size:15px}.occurrence-layout-tools>i{width:1px;height:17px;margin:0 2px;background:var(--line-bright)}.occurrence-layout-tools .auto-layout-button{display:flex;width:auto;padding:0 8px;gap:4px;border-color:rgba(var(--accent-rgb),.32);background:rgba(var(--accent-rgb),.1)}.occurrence-layout-tools .auto-layout-button strong{color:var(--text);font-size:8px;white-space:nowrap}.component-card-scroll{display:flex;min-width:0;align-items:stretch;overflow-x:auto;overflow-y:hidden;padding:8px 8px 10px;gap:8px;flex-wrap:nowrap;overscroll-behavior-x:contain;scrollbar-color:var(--blue) var(--bg-inset);scrollbar-width:thin}.component-card-scroll:focus-visible{outline:1px solid var(--blue-bright);outline-offset:-2px}.component-card-scroll::-webkit-scrollbar{height:7px}.component-card-scroll::-webkit-scrollbar-track{background:var(--bg-inset)}.component-card-scroll::-webkit-scrollbar-thumb{border:2px solid var(--bg-inset);border-radius:8px;background:var(--blue);background-clip:padding-box}.component-card-scroll article{display:grid;min-width:220px;align-items:center;padding:8px;grid-template-columns:30px minmax(0,1fr) auto;gap:7px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel)}.component-card-scroll article>.material-icons{display:grid;width:30px;height:30px;place-items:center;border-radius:4px;background:var(--blue-soft);color:var(--blue-bright);font-size:16px}.component-card-scroll article>div{display:flex;min-width:0;flex-direction:column}.component-card-scroll small{color:var(--blue-bright);font:7px "Cascadia Code",monospace}.component-card-scroll strong{margin-top:2px;color:var(--text);font-size:9.5px}.component-card-scroll p{overflow:hidden;margin:2px 0 0;color:var(--muted);font-size:7.5px;text-overflow:ellipsis;white-space:nowrap}.component-card-scroll em{color:var(--muted);font:7px "Cascadia Code",monospace;font-style:normal}.component-card-placeholder{border-style:dashed!important;opacity:.65}
.component-card-tray{grid-column:2;grid-row:2}
.component-card-title>button{display:grid;width:21px;height:21px;place-items:center;padding:0;border:1px solid transparent;border-radius:3px;background:transparent;color:var(--muted);cursor:pointer}.component-card-title>button:hover{border-color:var(--blue);background:var(--blue-soft)}.component-card-title>button .material-icons{font-size:13px!important}.component-engine-card{position:relative;min-width:292px!important;flex:0 0 292px;padding:17px 8px 7px!important;grid-template-columns:30px minmax(0,1fr) 88px!important;cursor:pointer;transition:border-color .14s,background .14s,transform .14s}.component-engine-card:hover,.component-engine-card.active{border-color:var(--blue-bright)!important;background:linear-gradient(120deg,rgba(var(--accent-rgb),.16),var(--bg-panel))!important;transform:translateY(-1px)}.card-step{position:absolute;top:4px;left:8px;color:var(--blue-bright);font:6.5px "Cascadia Code",monospace;letter-spacing:.1em}.card-state{display:flex;min-width:0;align-items:flex-end;flex-direction:column;gap:4px}.card-state em{padding:3px 5px;border:1px solid var(--line-bright);border-radius:8px;white-space:nowrap}.card-state small{display:flex;max-width:88px;align-items:center;gap:2px;color:var(--muted)!important;text-align:right}.card-state small .material-icons{color:var(--blue-bright);font-size:10px}.card-state>button{display:flex;height:18px;align-items:center;padding:0 5px;gap:2px;border:1px solid var(--blue);border-radius:3px;background:var(--blue-soft);color:var(--text);cursor:pointer;font:6.5px "Cascadia Code",monospace}.card-state>button:disabled{border-color:var(--line);background:transparent;color:var(--faint);cursor:not-allowed;opacity:.55}.card-state>button .material-icons{font-size:10px!important}.status-ready .card-state em,.status-copied .card-state em,.status-applied .card-state em,.status-verified .card-state em{border-color:color-mix(in srgb,var(--green) 58%,transparent);color:var(--green)}.status-warning .card-state em{border-color:color-mix(in srgb,var(--amber) 60%,transparent);color:var(--amber)}.status-validationError .card-state em,.status-failed .card-state em{border-color:color-mix(in srgb,var(--red) 62%,transparent);color:var(--red)}
.component-card-backdrop{position:fixed;z-index:9100;display:grid;inset:0;place-items:center;background:color-mix(in srgb,var(--bg-deep) 82%,transparent);backdrop-filter:blur(6px)}.component-card-dialog{display:grid;width:min(920px,calc(100vw - 52px));height:min(760px,calc(100vh - 52px));overflow:hidden;grid-template-rows:72px minmax(0,1fr) 64px;border:1px solid var(--blue-bright);border-radius:7px;background:var(--bg-panel-raised);box-shadow:0 28px 90px color-mix(in srgb,var(--bg-deep) 76%,transparent),0 0 30px rgba(var(--accent-rgb),.14)}.component-card-dialog>header{display:grid;align-items:center;padding:0 18px;grid-template-columns:40px minmax(0,1fr) auto 32px;gap:11px;border-bottom:1px solid var(--line-bright);background:linear-gradient(110deg,rgba(var(--accent-rgb),.19),var(--bg-panel-raised))}.component-card-dialog>header>.material-icons{display:grid;width:38px;height:38px;place-items:center;border-radius:5px;background:var(--blue-soft);color:var(--blue-bright);font-size:21px}.component-card-dialog>header>div{display:flex;min-width:0;flex-direction:column}.component-card-dialog>header small{color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.1em}.component-card-dialog h2{margin:4px 0 0;color:var(--text);font-size:18px}.component-card-dialog>header>button{display:grid;width:30px;height:30px;place-items:center;padding:0;border:0;background:transparent;color:var(--muted);cursor:pointer}.component-card-dialog>header>button:hover{color:var(--text)}.dialog-status{padding:4px 8px;border:1px solid var(--line-bright);border-radius:12px;color:var(--muted);font:8px "Cascadia Code",monospace}.dialog-status.status-ready,.dialog-status.status-copied,.dialog-status.status-applied,.dialog-status.status-verified{border-color:var(--green);color:var(--green)}.dialog-status.status-validationError,.dialog-status.status-failed{border-color:var(--red);color:var(--red)}.component-card-detail-scroll{overflow-y:auto;padding:18px}.card-detail-summary{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px 12px}.card-detail-summary label{display:flex;min-width:0;flex-direction:column;color:var(--muted);font:8px "Cascadia Code",monospace;letter-spacing:.08em}.card-detail-summary label:first-child{grid-column:1}.card-detail-summary label:nth-child(2){grid-column:1}.card-detail-summary input,.card-detail-summary textarea{width:100%;margin-top:6px;padding:9px 10px;border:1px solid var(--line-bright);border-radius:4px;outline:0;background:var(--bg-inset);color:var(--text);font:12px "Segoe UI",sans-serif;resize:vertical}.card-detail-summary input:focus,.card-detail-summary textarea:focus{border-color:var(--blue-bright);box-shadow:0 0 0 2px rgba(var(--accent-rgb),.13)}.card-detail-summary>p{display:flex;margin:0;padding:10px 12px;grid-column:1/3;gap:7px;border-left:2px solid var(--blue-bright);background:rgba(var(--accent-rgb),.08);color:var(--muted);font-size:10px;line-height:1.55}.card-detail-summary>p .material-icons{color:var(--blue-bright);font-size:16px}.card-detail-summary>button{display:flex;height:35px;align-items:center;align-self:end;padding:0 12px;grid-column:2;grid-row:1/3;gap:5px;border:1px solid var(--blue);border-radius:4px;background:var(--blue-soft);color:var(--text);cursor:pointer;font-size:10px}.card-detail-summary>button .material-icons{font-size:15px}.card-detail-grid{display:grid;margin-top:14px;grid-template-columns:1fr 1fr;gap:10px}.card-detail-grid>article,.card-validation-detail,.card-history-detail{border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel)}.card-detail-grid header,.card-validation-detail>header,.card-history-detail>header{display:flex;height:34px;align-items:center;justify-content:space-between;padding:0 10px;border-bottom:1px solid var(--line);color:var(--blue-bright);font:8px "Cascadia Code",monospace;letter-spacing:.09em}.card-detail-grid ul{max-height:138px;overflow-y:auto;margin:0;padding:8px 11px 8px 27px;color:var(--muted);font-size:9.5px;line-height:1.75}.card-detail-grid li .material-icons{margin-right:4px;color:var(--blue-bright);font-size:11px;vertical-align:-2px}.card-validation-detail{margin-top:10px;padding-bottom:7px}.card-validation-detail>header button{display:flex;height:24px;align-items:center;padding:0 7px;gap:3px;border:1px solid var(--blue);border-radius:3px;background:var(--blue-soft);color:var(--text);cursor:pointer;font-size:8px}.card-validation-detail>header button .material-icons{font-size:12px}.card-validation-detail>p{display:flex;margin:7px 10px 0;align-items:center;gap:5px;color:var(--muted);font-size:9.5px}.card-validation-detail>p .material-icons{color:var(--green);font-size:14px}.card-validation-detail>p.error,.card-validation-detail>p.error .material-icons{color:var(--red)}.card-validation-detail>p.warning,.card-validation-detail>p.warning .material-icons{color:var(--amber)}.card-xml-detail{margin-top:10px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-inset)}.card-xml-detail summary{padding:10px;color:var(--blue-bright);font:8px "Cascadia Code",monospace;cursor:pointer}.card-xml-detail pre{max-height:220px;overflow:auto;margin:0;padding:12px;border-top:1px solid var(--line);color:var(--text);font:9px/1.55 "Cascadia Code",monospace;white-space:pre-wrap}.card-history-detail{margin-top:10px}.card-history-detail ol{max-height:150px;overflow:auto;margin:0;padding:8px 12px;list-style:none}.card-history-detail li{display:grid;min-height:27px;align-items:center;grid-template-columns:145px 90px minmax(0,1fr);gap:8px;border-bottom:1px solid var(--line);color:var(--muted);font-size:8.5px}.card-history-detail time{font-family:"Cascadia Code",monospace}.card-history-detail strong{color:var(--blue-bright)}.component-card-dialog>footer{display:flex;align-items:center;justify-content:space-between;padding:0 18px;border-top:1px solid var(--line-bright);background:var(--bg-inset)}.component-card-dialog>footer>div{display:flex;gap:7px}.component-card-dialog>footer button{display:flex;height:34px;align-items:center;padding:0 12px;gap:4px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel);color:var(--muted);cursor:pointer;font-size:9.5px}.component-card-dialog>footer button:hover:not(:disabled){border-color:var(--blue);color:var(--text)}.component-card-dialog>footer button:disabled{cursor:not-allowed;opacity:.38}.component-card-dialog>footer .next-card-button{border-color:var(--blue);background:var(--blue-soft);color:var(--text)}.component-card-dialog>footer .material-icons{font-size:14px}

/* Theme-linked relationship workspace states. */
.design-validation-summary:not(.invalid){background:rgba(var(--accent-rgb),.1)}
.design-validation-summary:not(.invalid)>.material-icons{color:var(--blue-bright)}
.field-port.related{border-color:var(--blue-bright)!important;background:color-mix(in srgb,var(--blue-soft) 72%,var(--bg-deep))!important;box-shadow:0 0 6px rgba(var(--accent-rgb),.55)}
.field-port.related:hover{background:var(--blue-bright)!important;box-shadow:0 0 9px rgba(var(--accent-rgb),.82)}
.occurrence-name-backdrop{background:color-mix(in srgb,var(--bg-deep) 80%,transparent)}
@media(max-width:1420px){.relationship-workspace{grid-template-columns:185px minmax(640px,1fr) 235px}.canvas-actions button{font-size:0}.canvas-actions button .material-icons{font-size:15px}}
.validation-actions{display:flex;align-items:center;gap:5px}.card-validation-detail>header button:disabled{cursor:not-allowed;opacity:.45}
</style>

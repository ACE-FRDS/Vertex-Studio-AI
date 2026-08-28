import { computed, ref, watch } from 'vue'

import {
  equipmentRegistry,
  type EquipmentLayout,
} from './equipmentRegistry'

export interface EquipmentPlacement extends EquipmentLayout {
  id: string
  visible: boolean
  z: number
}

export interface AdaptiveGridSnapshot {
  schema: 'vertex.adaptive-grid.v7'
  columns: 24
  rows: 16
  gap: number
  editMode: boolean
  placements: EquipmentPlacement[]
}

const STORAGE_KEY = 'vertex.adaptive-grid.v7'

function defaultSnapshot(): AdaptiveGridSnapshot {
  return {
    schema: 'vertex.adaptive-grid.v7',
    columns: 24,
    rows: 16,
    gap: 6,
    editMode: false,
    placements: equipmentRegistry.map((item, index) => ({
      id: item.id,
      visible: true,
      z: item.primary ? 10 : index + 20,
      ...item.layout,
    })),
  }
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function load(): AdaptiveGridSnapshot {
  const fallback = defaultSnapshot()

  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return fallback

    const parsed = JSON.parse(raw) as Partial<AdaptiveGridSnapshot>
    if (parsed.schema !== 'vertex.adaptive-grid.v7') return fallback

    const incoming = Array.isArray(parsed.placements)
      ? parsed.placements
      : []

    return {
      schema: 'vertex.adaptive-grid.v7',
      columns: 24,
      rows: 16,
      gap: clamp(Number(parsed.gap ?? fallback.gap), 0, 18),
      editMode: Boolean(parsed.editMode),
      placements: fallback.placements.map((base) => {
        const rawPlacement = incoming.find(
          (item) =>
            item
            && typeof item === 'object'
            && (item as Partial<EquipmentPlacement>).id === base.id,
        ) as Partial<EquipmentPlacement> | undefined

        const colSpan = clamp(
          Number(rawPlacement?.colSpan ?? base.colSpan),
          base.minColSpan,
          24,
        )
        const rowSpan = clamp(
          Number(rawPlacement?.rowSpan ?? base.rowSpan),
          base.minRowSpan,
          16,
        )

        return {
          ...base,
          visible:
            typeof rawPlacement?.visible === 'boolean'
              ? rawPlacement.visible
              : base.visible,
          z: clamp(Number(rawPlacement?.z ?? base.z), 1, 9999),
          colSpan,
          rowSpan,
          col: clamp(
            Number(rawPlacement?.col ?? base.col),
            1,
            Math.max(1, 25 - colSpan),
          ),
          row: clamp(
            Number(rawPlacement?.row ?? base.row),
            1,
            Math.max(1, 17 - rowSpan),
          ),
        }
      }),
    }
  } catch {
    return fallback
  }
}

const snapshot = ref(load())
const activeDragId = ref('')
const activeResizeId = ref('')

const visiblePlacements = computed(() =>
  snapshot.value.placements.filter((item) => item.visible),
)

function bringToFront(id: string) {
  const target = snapshot.value.placements.find((item) => item.id === id)
  if (!target) return

  target.z = Math.max(
    1,
    ...snapshot.value.placements.map((item) => item.z),
  ) + 1
}

function show(id: string) {
  const item = snapshot.value.placements.find((value) => value.id === id)
  if (!item) return
  item.visible = true
  bringToFront(id)
}

function hide(id: string) {
  const item = snapshot.value.placements.find((value) => value.id === id)
  if (item) item.visible = false
}

function toggleEditMode() {
  snapshot.value.editMode = !snapshot.value.editMode
}

function setGap(value: number) {
  snapshot.value.gap = clamp(value, 0, 18)
}

function updatePlacement(
  id: string,
  patch: Partial<Pick<EquipmentPlacement,'col'|'row'|'colSpan'|'rowSpan'>>,
) {
  const target = snapshot.value.placements.find((item) => item.id === id)
  const descriptor = equipmentRegistry.find((item) => item.id === id)
  if (!target || !descriptor) return

  const colSpan = clamp(
    patch.colSpan ?? target.colSpan,
    descriptor.layout.minColSpan,
    24,
  )
  const rowSpan = clamp(
    patch.rowSpan ?? target.rowSpan,
    descriptor.layout.minRowSpan,
    16,
  )

  target.colSpan = colSpan
  target.rowSpan = rowSpan
  target.col = clamp(
    patch.col ?? target.col,
    1,
    Math.max(1, 25 - colSpan),
  )
  target.row = clamp(
    patch.row ?? target.row,
    1,
    Math.max(1, 17 - rowSpan),
  )

  bringToFront(id)
}

function reset() {
  snapshot.value = defaultSnapshot()
}

function exportLayout() {
  return JSON.stringify(snapshot.value, null, 2)
}

function importLayout(raw: string) {
  const parsed = JSON.parse(raw)
  if (parsed?.schema !== 'vertex.adaptive-grid.v7') {
    throw new Error('Unsupported layout schema')
  }

  localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed))
  snapshot.value = load()
}

watch(
  snapshot,
  (value) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
  },
  { deep: true },
)

export function useAdaptiveGrid() {
  return {
    snapshot,
    visiblePlacements,
    activeDragId,
    activeResizeId,
    bringToFront,
    show,
    hide,
    toggleEditMode,
    setGap,
    updatePlacement,
    reset,
    exportLayout,
    importLayout,
  }
}
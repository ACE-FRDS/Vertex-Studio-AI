<script setup lang="ts">
import { computed, ref } from 'vue'

import { equipmentById } from './equipmentRegistry'
import { useAdaptiveGrid } from './useAdaptiveGrid'

const props = defineProps<{ equipmentId: string }>()
const grid = useAdaptiveGrid()

const descriptor = computed(() => equipmentById[props.equipmentId])
const placement = computed(
  () =>
    grid.snapshot.value.placements.find(
      (item) => item.id === props.equipmentId,
    ) ?? null,
)

const moveStart = ref({ x:0,y:0,col:1,row:1 })
const resizeStart = ref({ x:0,y:0,colSpan:1,rowSpan:1 })

function metrics() {
  const host = document.querySelector('.adaptive-grid-surface') as HTMLElement | null
  if (!host) return null

  const rect = host.getBoundingClientRect()
  const gap = grid.snapshot.value.gap

  return {
    cellWidth: (rect.width - gap * 23) / 24,
    cellHeight: (rect.height - gap * 15) / 16,
    gap,
  }
}

function startMove(event: PointerEvent) {
  if (
    !grid.snapshot.value.editMode
    || !descriptor.value?.movable
    || !placement.value
  ) return

  event.preventDefault()
  event.stopPropagation()

  grid.activeDragId.value = props.equipmentId

  moveStart.value = {
    x: event.clientX,
    y: event.clientY,
    col: placement.value.col,
    row: placement.value.row,
  }

  const onMove = (e: PointerEvent) => {
    const m = metrics()
    if (!m) return

    const dx = Math.round(
      (e.clientX - moveStart.value.x) / (m.cellWidth + m.gap),
    )
    const dy = Math.round(
      (e.clientY - moveStart.value.y) / (m.cellHeight + m.gap),
    )

    grid.updatePlacement(props.equipmentId, {
      col: moveStart.value.col + dx,
      row: moveStart.value.row + dy,
    })
  }

  const onUp = () => {
    grid.activeDragId.value = ''
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
  }

  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
}

function startResize(event: PointerEvent) {
  if (
    !grid.snapshot.value.editMode
    || !descriptor.value?.resizable
    || !placement.value
  ) return

  event.preventDefault()
  event.stopPropagation()

  grid.activeResizeId.value = props.equipmentId

  resizeStart.value = {
    x: event.clientX,
    y: event.clientY,
    colSpan: placement.value.colSpan,
    rowSpan: placement.value.rowSpan,
  }

  const onMove = (e: PointerEvent) => {
    const m = metrics()
    if (!m) return

    const dx = Math.round(
      (e.clientX - resizeStart.value.x) / (m.cellWidth + m.gap),
    )
    const dy = Math.round(
      (e.clientY - resizeStart.value.y) / (m.cellHeight + m.gap),
    )

    grid.updatePlacement(props.equipmentId, {
      colSpan: resizeStart.value.colSpan + dx,
      rowSpan: resizeStart.value.rowSpan + dy,
    })
  }

  const onUp = () => {
    grid.activeResizeId.value = ''
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
  }

  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
}
</script>

<template>
  <section
    v-if="placement && descriptor"
    class="equipment-unit"
    :class="{
      primary: descriptor.primary,
      editable: grid.snapshot.value.editMode,
    }"
    :style="{
      gridColumn: `${placement.col} / span ${placement.colSpan}`,
      gridRow: `${placement.row} / span ${placement.rowSpan}`,
      zIndex: placement.z,
    }"
    @pointerdown="grid.bringToFront(equipmentId)"
  >
    <header
      v-if="!descriptor.primary || grid.snapshot.value.editMode"
      class="equipment-head"
      @pointerdown="startMove"
    >
      <div class="title">
        <span>◆</span>
        <div>
          <strong>{{ descriptor.title }}</strong>
          <small>{{ descriptor.subtitle }}</small>
        </div>
      </div>

      <div class="badges">
        <b v-if="descriptor.primary">PRIMARY</b>
        <b v-if="descriptor.droneEligible">DRONE READY</b>
        <b>{{ descriptor.runtimeMode.toUpperCase() }}</b>

        <button
          v-if="!descriptor.primary"
          type="button"
          @pointerdown.stop
          @click.stop="grid.hide(equipmentId)"
        >
          ×
        </button>
      </div>
    </header>

    <div class="body">
      <slot />
    </div>

    <button
      v-if="grid.snapshot.value.editMode && descriptor.resizable"
      class="resize"
      type="button"
      @pointerdown="startResize"
    >
      ◢
    </button>

    <div
      v-if="grid.snapshot.value.editMode"
      class="readout"
    >
      C{{ placement.col }} R{{ placement.row }}
      · {{ placement.colSpan }}×{{ placement.rowSpan }}
    </div>
  </section>
</template>

<style scoped>
.equipment-unit {
  position: relative;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  border: 1px solid rgba(48,56,88,.88);
  border-radius: 5px;
  background:
    radial-gradient(circle at 75% -45%, rgba(124,92,255,.07), transparent 48%),
    #090c19;
  box-shadow: 0 10px 28px rgba(0,0,0,.18);
}

.equipment-unit.primary {
  border: 0;
  border-radius: 0;
  background: #070812;
  box-shadow: none;
}

.equipment-unit.editable {
  outline: 1px dashed rgba(169,140,255,.35);
  outline-offset: -3px;
}

.equipment-head {
  display: flex;
  min-height: 40px;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 0 9px;
  border-bottom: 1px solid #2a314e;
  background:
    linear-gradient(90deg, rgba(124,92,255,.10), transparent 52%),
    #0d1020;
  cursor: grab;
  user-select: none;
}

.title {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.title > span {
  color: #a98cff;
  font-size: 8px;
}

.title strong,
.title small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.title strong {
  color: #cbd3e6;
  font-size: 11px;
}

.title small {
  margin-top: 3px;
  color: #606b87;
  font-size: 8px;
}

.badges {
  display: flex;
  align-items: center;
  gap: 4px;
}

.badges b {
  height: 20px;
  display: inline-flex;
  align-items: center;
  padding: 0 5px;
  border: 1px solid #313959;
  border-radius: 3px;
  background: #0a0d19;
  color: #68738f;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}

.badges b:nth-child(2) {
  border-color: rgba(98,216,255,.25);
  color: #7ab7cf;
}

.badges button {
  width: 22px;
  height: 22px;
  border: 1px solid #303858;
  border-radius: 3px;
  background: #0a0d19;
  color: #65718d;
}

.body {
  position: relative;
  min-width: 0;
  min-height: 0;
  height: 100%;
  overflow: hidden;
}

.equipment-unit:not(.primary) .body {
  height: calc(100% - 40px);
}

.body > :deep(*) {
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
}

.resize {
  position: absolute;
  z-index: 50;
  right: 3px;
  bottom: 3px;
  width: 24px;
  height: 24px;
  border: 1px solid #55458f;
  border-radius: 3px;
  background: rgba(29,23,62,.92);
  color: #a98cff;
  cursor: nwse-resize;
}

.readout {
  position: absolute;
  z-index: 45;
  right: 31px;
  bottom: 5px;
  padding: 3px 5px;
  background: rgba(7,8,18,.82);
  color: #6e628e;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}
</style>
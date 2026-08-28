<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    status?: string
    statusTone?: 'blue' | 'green' | 'amber' | 'red' | 'muted'
    dense?: boolean
    panelId?: string
    dockable?: boolean
  }>(),
  {
    subtitle: '',
    status: '',
    statusTone: 'blue',
    dense: false,
    panelId: '',
    dockable: false,
  },
)

function beginDrag(event: DragEvent) {
  if (!props.dockable || !props.panelId) return
  if (!event.dataTransfer) return

  event.dataTransfer.effectAllowed = 'move'
  event.dataTransfer.setData('application/x-vertex-panel', props.panelId)
  event.dataTransfer.setData('text/plain', props.panelId)

  window.dispatchEvent(
    new CustomEvent('vertex-panel-drag-state', {
      detail: {
        active: true,
        panelId: props.panelId,
      },
    }),
  )
}

function endDrag() {
  window.dispatchEvent(
    new CustomEvent('vertex-panel-drag-state', {
      detail: {
        active: false,
        panelId: props.panelId,
      },
    }),
  )
}

function panelCommand(command: 'float' | 'hide') {
  if (!props.panelId) return

  window.dispatchEvent(
    new CustomEvent('vertex-panel-command', {
      detail: {
        panelId: props.panelId,
        command,
      },
    }),
  )
}
</script>

<template>
  <section
    class="panel-frame"
    :class="{ dense }"
  >
    <header
      class="panel-head"
      :class="{ draggable: dockable }"
      :draggable="dockable"
      @dragstart="beginDrag"
      @dragend="endDrag"
    >
      <div class="panel-title">
        <span
          v-if="dockable"
          class="panel-grip"
          aria-hidden="true"
        >
          ::
        </span>

        <span class="panel-chevron">›</span>

        <div>
          <strong>{{ title }}</strong>
          <small v-if="subtitle">{{ subtitle }}</small>
        </div>
      </div>

      <div class="panel-actions">
        <span
          v-if="status"
          class="panel-status"
          :class="`tone-${statusTone}`"
        >
          {{ status }}
        </span>

        <button
          v-if="dockable"
          type="button"
          class="panel-action"
          title="Float panel"
          @click.stop="panelCommand('float')"
          @mousedown.stop
        >
          FLT
        </button>

        <button
          v-if="dockable"
          type="button"
          class="panel-action"
          title="Hide panel"
          @click.stop="panelCommand('hide')"
          @mousedown.stop
        >
          HIDE
        </button>
      </div>
    </header>

    <div class="panel-body">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.panel-frame {
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  border: 1px solid var(--vertex-line, #1c2935);
  border-radius: 5px;
  background:
    linear-gradient(180deg, rgba(17,25,35,.97), rgba(8,13,19,.99));
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.018),
    0 12px 34px rgba(0,0,0,.16);
}

.panel-head {
  display: flex;
  min-height: var(--cockpit-panel-header, 42px);
  align-items: center;
  justify-content: space-between;
  padding: 0 12px;
  gap: 12px;
  border-bottom: 1px solid var(--vertex-line, #1c2935);
  background:
    linear-gradient(90deg, rgba(22,140,255,.055), transparent 50%),
    rgba(10,16,23,.94);
  user-select: none;
}

.panel-head.draggable {
  cursor: grab;
}

.panel-head.draggable:active {
  cursor: grabbing;
}

.panel-title {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
}

.panel-title > div {
  min-width: 0;
}

.panel-title strong,
.panel-title small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.panel-title strong {
  color: #b9c7d4;
  font-size: var(--cockpit-panel-title, 13px);
  font-weight: 720;
  letter-spacing: .035em;
}

.panel-title small {
  margin-top: 3px;
  color: var(--vertex-muted, #718195);
  font: 650 var(--cockpit-caption, 10px)/1.1 ui-monospace, "Cascadia Code", Consolas, monospace;
}

.panel-grip {
  color: #4d7390;
  font: 850 12px/1 ui-monospace, Consolas, monospace;
  letter-spacing: -1px;
}

.panel-chevron {
  color: var(--vertex-blue-bright, #3ab8ff);
  font-size: 18px;
}

.panel-actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 7px;
}

.panel-status {
  font: 750 var(--cockpit-caption, 10px)/1 ui-monospace, "Cascadia Code", Consolas, monospace;
  letter-spacing: .05em;
}

.panel-action {
  min-width: 34px;
  height: 26px;
  padding: 0 7px;
  border: 1px solid #243847;
  border-radius: 3px;
  background: #0a121a;
  color: #6d8295;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.panel-action:hover {
  border-color: #3279a7;
  color: #8fd1ff;
  background: #0f2030;
}

.tone-blue {
  color: var(--vertex-blue-bright, #3ab8ff);
}

.tone-green {
  color: var(--vertex-green, #55d69e);
}

.tone-amber {
  color: var(--vertex-amber, #f1b85b);
}

.tone-red {
  color: var(--vertex-red, #ff6f7c);
}

.tone-muted {
  color: var(--vertex-muted, #718195);
}

.panel-body {
  min-height: 0;
}

.dense .panel-head {
  min-height: 36px;
}
</style>
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'
import VveTreeNode, { type VveTreeNodeModel } from '../VveTreeNode.vue'

const roots = ref<VveTreeNodeModel[]>([])
const loading = ref(false)
const error = ref('')

function parsePayload(value: unknown): unknown {
  if (typeof value !== 'string') return value
  try {
    return JSON.parse(value)
  } catch {
    return value
  }
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function textFrom(
  object: Record<string, unknown>,
  keys: string[],
): string {
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'string' && value.trim()) return value
  }
  return ''
}

function childrenFrom(object: Record<string, unknown>): unknown[] {
  for (const key of ['children', 'entries', 'nodes', 'items']) {
    if (Array.isArray(object[key])) return object[key] as unknown[]
  }
  return []
}

function normalize(
  value: unknown,
  fallbackId: string,
  depth = 0,
): VveTreeNodeModel | null {
  if (depth > 32) return null

  if (typeof value === 'string') {
    const label = value.split(/[\\/]/).filter(Boolean).pop() || value
    return {
      id: `${fallbackId}:${value}`,
      label,
      path: value,
      kind: value.includes('.') ? 'file' : 'unknown',
      children: [],
    }
  }

  const object = objectValue(value)
  if (!object) return null

  const path = textFrom(object, ['path', 'relative_path', 'full_path'])
  const label =
    textFrom(object, ['name', 'label', 'file_name', 'filename'])
    || path.split(/[\\/]/).filter(Boolean).pop()
    || fallbackId

  const rawChildren = childrenFrom(object)
  const children = rawChildren
    .map((child, index) =>
      normalize(child, `${fallbackId}.${index}`, depth + 1),
    )
    .filter((child): child is VveTreeNodeModel => Boolean(child))

  const rawKind = textFrom(object, ['kind', 'type', 'node_type']).toLowerCase()
  const isDir =
    object.is_dir === true
    || object.directory === true
    || rawKind.includes('dir')
    || rawKind.includes('folder')
    || children.length > 0

  return {
    id: path || `${fallbackId}:${label}`,
    label,
    path,
    kind: isDir ? 'folder' : rawKind.includes('file') ? 'file' : 'unknown',
    children,
  }
}

function normalizeRoots(payload: unknown): VveTreeNodeModel[] {
  const parsed = parsePayload(payload)

  if (Array.isArray(parsed)) {
    return parsed
      .map((item, index) => normalize(item, `root.${index}`))
      .filter((item): item is VveTreeNodeModel => Boolean(item))
  }

  const object = objectValue(parsed)
  if (object) {
    const direct = childrenFrom(object)
    if (direct.length > 0) {
      const root = normalize(object, 'workspace')
      return root ? [root] : []
    }

    for (const key of ['tree', 'root', 'workspace']) {
      if (object[key] !== undefined) {
        const root = normalize(object[key], key)
        return root ? [root] : []
      }
    }
  }

  const root = normalize(parsed, 'workspace')
  return root ? [root] : []
}

async function refresh() {
  loading.value = true
  error.value = ''

  try {
    const raw = await invoke<unknown>('vertex_project_tree')
    roots.value = normalizeRoots(raw)
    if (!roots.value.length) {
      error.value = 'PROJECT TREE RETURNED NO DISPLAYABLE NODES'
    }
  } catch (reason) {
    error.value = String(reason)
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void refresh()
})
</script>

<template>
  <CockpitPanelFrame
    title="VVE // TREE EXPLORER"
    subtitle="PROJECT WORLD / STRUCTURE"
    panel-id="vve-tree-explorer"
    dockable
    :status="error ? 'NO SIGNAL' : loading ? 'SCANNING' : 'ONLINE'"
    :status-tone="error ? 'amber' : 'blue'"
  >
    <div class="vve-shell">
      <div class="vve-toolbar">
        <div>
          <span>VIRTUAL EXPLORER</span>
          <strong>PROJECT WORLD</strong>
        </div>

        <button
          type="button"
          :disabled="loading"
          @click="refresh"
        >
          REFRESH
        </button>
      </div>

      <div class="vve-tree">
        <div
          v-if="loading"
          class="vve-state"
        >
          SCANNING PROJECT TREE...
        </div>

        <div
          v-else-if="error"
          class="vve-state error"
        >
          {{ error }}
        </div>

        <VveTreeNode
          v-for="root in roots"
          v-else
          :key="root.id"
          :node="root"
          :depth="0"
        />
      </div>

      <footer class="vve-footer">
        <span>VVE</span>
        <span>FOLDERS / FILES / FUTURE AGENTS / DRONES</span>
      </footer>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.vve-shell {
  display: grid;
  min-height: 520px;
  height: 100%;
  grid-template-rows: auto minmax(0,1fr) auto;
  background:
    radial-gradient(circle at 45% 0%, rgba(98,216,255,.035), transparent 28%),
    rgba(6,8,17,.72);
}

.vve-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 54px;
  padding: 0 12px;
  border-bottom: 1px solid var(--vertex-line);
}

.vve-toolbar span,
.vve-toolbar strong {
  display: block;
}

.vve-toolbar span {
  color: #6f7b9b;
  font: 720 9px/1 ui-monospace, Consolas, monospace;
}

.vve-toolbar strong {
  margin-top: 5px;
  color: #c3cce0;
  font: 740 12px/1 ui-monospace, Consolas, monospace;
}

.vve-toolbar button {
  height: 28px;
  padding: 0 9px;
  border: 1px solid #354064;
  border-radius: 4px;
  background: #0b0e1c;
  color: #8290b0;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  cursor: pointer;
}

.vve-tree {
  min-height: 0;
  overflow: auto;
  padding: 7px 0;
}

.vve-state {
  margin: 12px;
  padding: 14px;
  border: 1px solid #303957;
  border-radius: 5px;
  color: #8090aa;
  font: 700 10px/1.4 ui-monospace, Consolas, monospace;
}

.vve-state.error {
  border-color: rgba(242,198,109,.28);
  color: var(--vertex-amber);
}

.vve-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 34px;
  padding: 0 12px;
  gap: 10px;
  border-top: 1px solid var(--vertex-line);
  color: #596582;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}
</style>
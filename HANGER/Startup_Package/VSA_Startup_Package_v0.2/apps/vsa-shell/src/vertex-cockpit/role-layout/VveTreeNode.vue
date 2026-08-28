<script setup lang="ts">
import { computed, ref } from 'vue'

export interface VveTreeNodeModel {
  id: string
  label: string
  kind: 'folder' | 'file' | 'unknown'
  path: string
  children: VveTreeNodeModel[]
}

const props = defineProps<{
  node: VveTreeNodeModel
  depth?: number
}>()

const open = ref((props.depth ?? 0) < 2)

const padding = computed(() => `${8 + (props.depth ?? 0) * 16}px`)
</script>

<template>
  <div class="tree-node">
    <button
      class="tree-row"
      :style="{ paddingLeft: padding }"
      type="button"
      @click="node.children.length && (open = !open)"
    >
      <span class="twisty">
        {{ node.children.length ? (open ? '⌄' : '›') : '' }}
      </span>

      <span
        class="node-icon"
        :class="node.kind"
        aria-hidden="true"
      >
        <svg
          v-if="node.kind === 'folder'"
          viewBox="0 0 24 18"
        >
          <path
            d="M1.5 4.5h7l2-2h4.5l1.5 2H22v11.8H1.5z"
            fill="currentColor"
            opacity=".22"
          />
          <path
            d="M1.5 5h7.2l2-2H15l1.6 2H22v11.2H1.5z"
            fill="none"
            stroke="currentColor"
            stroke-width="1.2"
          />
          <path
            d="M3 7.5h17.5"
            stroke="currentColor"
            stroke-width="1"
            opacity=".65"
          />
        </svg>

        <svg
          v-else
          viewBox="0 0 18 22"
        >
          <path
            d="M2 1.5h9l5 5v14H2z"
            fill="currentColor"
            opacity=".12"
          />
          <path
            d="M2 1.5h9l5 5v14H2zM11 1.5v5h5"
            fill="none"
            stroke="currentColor"
            stroke-width="1.2"
          />
        </svg>
      </span>

      <span class="node-label">{{ node.label }}</span>
    </button>

    <div
      v-if="open && node.children.length"
      class="tree-children"
    >
      <VveTreeNode
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :depth="(depth ?? 0) + 1"
      />
    </div>
  </div>
</template>

<style scoped>
.tree-row {
  display: grid;
  width: 100%;
  min-height: 34px;
  grid-template-columns: 14px 22px minmax(0,1fr);
  align-items: center;
  gap: 5px;
  border: 0;
  background: transparent;
  color: #a8b4ca;
  text-align: left;
  cursor: pointer;
}

.tree-row:hover {
  background:
    linear-gradient(90deg, rgba(124,92,255,.13), rgba(98,216,255,.025));
}

.twisty {
  color: #707b99;
  font-size: 14px;
}

.node-icon {
  display: grid;
  width: 20px;
  height: 20px;
  place-items: center;
  color: #8c7fea;
}

.node-icon.folder {
  color: #b59a67;
}

.node-icon.file {
  color: #6bbdde;
}

.node-icon svg {
  width: 18px;
  height: 18px;
}

.node-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 600 12px/1 "Segoe UI", sans-serif;
}
</style>
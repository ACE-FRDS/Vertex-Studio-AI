<script setup lang="ts">
import { ref } from 'vue'

export interface XmlTreeItem {
  name: string
  detail?: string
  children: XmlTreeItem[]
}

defineProps<{ node: XmlTreeItem; depth?: number }>()
const open = ref(true)
</script>

<template>
  <div class="xml-tree-node">
    <button
      class="tree-node-row"
      type="button"
      :style="{ paddingLeft: `${(depth ?? 0) * 18 + 12}px` }"
      @click="open = !open"
    >
      <span class="material-icons arrow" :class="{ hidden: !node.children.length }">
        {{ open ? 'keyboard_arrow_down' : 'keyboard_arrow_right' }}
      </span>
      <span class="node-bracket">&lt;</span><strong>{{ node.name }}</strong><span class="node-bracket">&gt;</span>
      <small v-if="node.detail">{{ node.detail }}</small>
    </button>
    <template v-if="open">
      <XmlTreeNode
        v-for="(child, index) in node.children"
        :key="`${child.name}-${index}`"
        :node="child"
        :depth="(depth ?? 0) + 1"
      />
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import XmlTreeNode, { type XmlTreeItem } from './XmlTreeNode.vue'

const props = defineProps<{ xml: string }>()

function toTree(element: Element): XmlTreeItem {
  const name = element.tagName
  const detail = ['name', 'type', 'id']
    .map((attribute) => element.getAttribute(attribute))
    .filter(Boolean)
    .join(' · ')
  return {
    name,
    detail,
    children: [...element.children].map(toTree),
  }
}

const tree = computed<XmlTreeItem | null>(() => {
  const document = new DOMParser().parseFromString(props.xml, 'application/xml')
  if (document.querySelector('parsererror')) return null
  return document.documentElement ? toTree(document.documentElement) : null
})
</script>

<template>
  <div class="structure-view">
    <div class="structure-toolbar">
      <span><i /> XML DOM STRUCTURE</span>
      <span>{{ tree ? 'Parsed successfully' : 'Parse error' }}</span>
    </div>
    <XmlTreeNode v-if="tree" :node="tree" />
    <div v-else class="empty-state"><span class="material-icons">error_outline</span><p>Unable to build XML tree</p></div>
  </div>
</template>

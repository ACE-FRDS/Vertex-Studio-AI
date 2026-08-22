<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQuasar } from 'quasar'
import { sampleInspector } from '../../data/sample'
import { useClipboardStore } from '../../stores/clipboard'
import { useEditorStore } from '../../stores/editor'
import { useLocaleStore } from '../../stores/locale'

type BottomTab = 'info' | 'preview' | 'tags' | 'notes'

const clipboard = useClipboardStore()
const editor = useEditorStore()
const locale = useLocaleStore()
const $q = useQuasar()
const active = ref<BottomTab>('info')
const tagBusy = ref(false)
const byteSize = computed(() => new TextEncoder().encode(editor.content).byteLength)
const kilobytes = computed(() => `${(byteSize.value / 1024).toFixed(2)} KB`)

const info = computed(() => [
  [locale.t('format'), clipboard.selectedItem?.windowsFormat ?? '—'],
  [locale.t('internal'), clipboard.selectedItem?.format ?? '—'],
  [locale.t('type'), clipboard.selectedItem?.objectType ?? '—'],
  [locale.t('dataSize'), kilobytes.value],
  [locale.t('encoding'), sampleInspector.encoding],
  [locale.t('header'), `${sampleInspector.headerBytes} bytes`],
])

function addTag() {
  const item = clipboard.selectedItem
  if (!item || tagBusy.value) return
  $q.dialog({
    dark: true,
    title: locale.language === 'ja' ? 'タグを追加' : 'Add Tag',
    prompt: {
      model: '',
      type: 'text',
      maxlength: 60,
      isValid: (value) => Boolean(value.trim()),
      autocomplete: 'off',
      placeholder: locale.language === 'ja' ? '例：JSON、インポート' : 'Example: JSON, Import',
    },
    persistent: true,
    cancel: { label: locale.t('cancel'), flat: true, color: 'grey-5' },
    ok: { label: locale.language === 'ja' ? '追加する' : 'Add', color: 'primary', unelevated: true },
  }).onOk(async (value: string) => {
    const tag = value.trim()
    if (!tag) return
    if (item.tags.some((candidate) => candidate.toLocaleLowerCase() === tag.toLocaleLowerCase())) {
      $q.notify({ type: 'warning', message: locale.language === 'ja' ? '同じタグが既にあります' : 'This tag already exists' })
      return
    }
    tagBusy.value = true
    try {
      await clipboard.updateTags(item.id, [...item.tags, tag])
      $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'タグを追加しました' : 'Tag added' })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    } finally {
      tagBusy.value = false
    }
  })
}

async function removeTag(tag: string) {
  const item = clipboard.selectedItem
  if (!item || tagBusy.value) return
  tagBusy.value = true
  try {
    await clipboard.updateTags(item.id, item.tags.filter((candidate) => candidate !== tag))
    $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'タグを削除しました' : 'Tag removed' })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    tagBusy.value = false
  }
}
</script>

<template>
  <section class="bottom-panel">
    <div class="bottom-tabs">
      <button type="button" :class="{ active: active === 'info' }" @click="active = 'info'">{{ locale.t('clipboardInfo') }}</button>
      <button type="button" :class="{ active: active === 'preview' }" @click="active = 'preview'">{{ locale.t('quickPreview') }}</button>
      <button type="button" :class="{ active: active === 'tags' }" @click="active = 'tags'">
        {{ locale.t('tags') }} <span>{{ clipboard.selectedItem?.tags.length ?? 0 }}</span>
      </button>
      <button type="button" :class="{ active: active === 'notes' }" @click="active = 'notes'">{{ locale.t('notes') }}</button>
      <div />
      <button class="collapse-button" type="button" title="Collapse"><span class="material-icons">expand_more</span></button>
    </div>

    <div v-if="active === 'info'" class="info-grid">
      <div v-for="[label, value] in info" :key="label" class="info-cell">
        <span>{{ label }}</span><strong>{{ value }}</strong>
      </div>
      <div class="checksum-cell"><span>{{ locale.t('checksum') }}</span><code>sha256: 7f83b1657ff1…a0bb</code></div>
    </div>

    <div v-else-if="active === 'preview'" class="quick-preview">
      <span class="material-icons">terminal</span>
      <div><strong>地方競馬現役馬JSON取込</strong><small>Set Variable → Insert from URL → Loop → Commit Records</small></div>
    </div>

    <div v-else-if="active === 'tags'" class="tag-editor">
      <span v-for="tag in clipboard.selectedItem?.tags" :key="tag">{{ tag }} <button type="button" :disabled="tagBusy" :aria-label="`${tag}を削除`" @click="removeTag(tag)">×</button></span>
      <button class="add-tag" type="button" :disabled="!clipboard.selectedItem || tagBusy" @click="addTag">＋ {{ locale.t('addTag') }}</button>
    </div>

    <div v-else class="bottom-notes">
      <textarea
        :value="clipboard.selectedItem?.notes"
        :placeholder="locale.t('notesForItem')"
        @input="clipboard.updateNotes(($event.target as HTMLTextAreaElement).value)"
      />
    </div>
  </section>
</template>

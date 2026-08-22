<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { RELATIONSHIP_OPERATORS } from '../../domain/design/relationshipOperators'
import type { DesignProject, DesignRelationship, TableOccurrence } from '../../types/design'

const props = defineProps<{
  open: boolean
  project: DesignProject | null
  relationship: DesignRelationship | null
  isNew: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [relationship: DesignRelationship]
  delete: [id: string]
}>()

const form = ref<DesignRelationship | null>(null)

watch(
  () => [props.open, props.relationship] as const,
  () => { form.value = props.relationship ? cloneRelationship(props.relationship) : null },
  { immediate: true, deep: true },
)

const leftOccurrence = computed(() => occurrence(form.value?.leftOccurrenceId))
const rightOccurrence = computed(() => occurrence(form.value?.rightOccurrenceId))
const leftFields = computed(() => fieldsFor(leftOccurrence.value))
const rightFields = computed(() => fieldsFor(rightOccurrence.value))
const leftField = computed(() => leftFields.value.find((field) => field.id === form.value?.leftFieldId))
const rightField = computed(() => rightFields.value.find((field) => field.id === form.value?.rightFieldId))
const operatorSymbol = computed(() => RELATIONSHIP_OPERATORS.find((item) => item.id === form.value?.operator)?.symbol ?? form.value?.operator ?? '=')
const canSave = computed(() => Boolean(
  form.value?.leftOccurrenceId
  && form.value.leftFieldId
  && form.value.operator
  && form.value.rightOccurrenceId
  && form.value.rightFieldId
  && !(form.value.leftOccurrenceId === form.value.rightOccurrenceId && form.value.leftFieldId === form.value.rightFieldId),
))

function occurrence(id?: string) {
  return props.project?.tableOccurrences.find((candidate) => candidate.id === id) ?? null
}

function fieldsFor(value: TableOccurrence | null) {
  if (!value) return []
  return props.project?.tables.find((table) => table.id === value.baseTableId)?.fields ?? []
}

function changeOccurrence(side: 'left' | 'right', id: string) {
  if (!form.value) return
  const target = occurrence(id)
  const fields = fieldsFor(target)
  if (side === 'left') {
    form.value.leftOccurrenceId = id
    form.value.leftFieldId = fields[0]?.id ?? ''
  } else {
    form.value.rightOccurrenceId = id
    form.value.rightFieldId = fields[0]?.id ?? ''
  }
}

function save() {
  if (form.value && canSave.value) emit('save', cloneRelationship(form.value))
}

function cloneRelationship(relationship: DesignRelationship): DesignRelationship {
  return {
    ...relationship,
    extensions: relationship.extensions ? { ...relationship.extensions } : undefined,
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open && form" class="relationship-dialog-backdrop" role="presentation" @keydown.esc="emit('close')">
      <section class="relationship-dialog" role="dialog" aria-modal="true" aria-labelledby="relationship-dialog-title">
        <header>
          <div>
            <span class="material-icons">account_tree</span>
            <div>
              <small>RELATIONSHIP DESIGNER</small>
              <h2 id="relationship-dialog-title">{{ isNew ? 'リレーションシップを作成' : 'リレーションシップを編集' }}</h2>
            </div>
          </div>
          <button type="button" aria-label="閉じる" @click="emit('close')"><span class="material-icons">close</span></button>
        </header>

        <p class="relationship-dialog-intro">
          関連レコードの検索に使用するテーブルオカレンスとフィールドの組み合わせを指定します。
          フィールド、演算子、作成・削除・ソートの各設定はVRTEXの設計検証対象になります。
        </p>

        <div class="relationship-pair-editor">
          <section>
            <label>テーブルオカレンス A</label>
            <select :value="form.leftOccurrenceId" @change="changeOccurrence('left', ($event.target as HTMLSelectElement).value)">
              <option v-for="item in project?.tableOccurrences" :key="item.id" :value="item.id">{{ item.name }}</option>
            </select>
            <div class="relation-field-picker" role="listbox" aria-label="左側フィールド">
              <button
                v-for="field in leftFields"
                :key="field.id"
                type="button"
                :class="{ active: form.leftFieldId === field.id }"
                @click="form.leftFieldId = field.id"
              >
                <span>{{ field.isPrimaryKey ? 'PK' : field.isForeignKey ? 'FK' : '' }}</span>
                <strong>{{ field.name }}</strong><small>{{ field.type }}</small>
              </button>
            </div>
          </section>

          <div class="relationship-operator-column">
            <label>演算子</label>
            <select v-model="form.operator" aria-label="リレーション演算子">
              <option v-for="operator in RELATIONSHIP_OPERATORS" :key="operator.id" :value="operator.id">
                {{ operator.symbol }}　{{ operator.nameJa }}
              </option>
            </select>
            <span class="material-icons">compare_arrows</span>
          </div>

          <section>
            <label>テーブルオカレンス B</label>
            <select :value="form.rightOccurrenceId" @change="changeOccurrence('right', ($event.target as HTMLSelectElement).value)">
              <option v-for="item in project?.tableOccurrences" :key="item.id" :value="item.id">{{ item.name }}</option>
            </select>
            <div class="relation-field-picker" role="listbox" aria-label="右側フィールド">
              <button
                v-for="field in rightFields"
                :key="field.id"
                type="button"
                :class="{ active: form.rightFieldId === field.id }"
                @click="form.rightFieldId = field.id"
              >
                <span>{{ field.isPrimaryKey ? 'PK' : field.isForeignKey ? 'FK' : '' }}</span>
                <strong>{{ field.name }}</strong><small>{{ field.type }}</small>
              </button>
            </div>
          </section>
        </div>

        <div class="relationship-pair-summary">
          <strong>{{ leftOccurrence?.name }}::{{ leftField?.name }}</strong>
          <em>{{ operatorSymbol }}</em>
          <strong>{{ rightOccurrence?.name }}::{{ rightField?.name }}</strong>
        </div>

        <div class="relationship-options">
          <fieldset>
            <legend>{{ leftOccurrence?.name }}</legend>
            <label><input v-model="form.allowCreateLeft" type="checkbox">このリレーションシップを使用してレコード作成を許可</label>
            <label><input v-model="form.deleteRelatedLeft" type="checkbox">他方のレコード削除時に関連レコードを削除</label>
            <label><input v-model="form.sortRelatedLeft" type="checkbox">関連レコードをソート</label>
          </fieldset>
          <fieldset>
            <legend>{{ rightOccurrence?.name }}</legend>
            <label><input v-model="form.allowCreateRight" type="checkbox">このリレーションシップを使用してレコード作成を許可</label>
            <label><input v-model="form.deleteRelatedRight" type="checkbox">他方のレコード削除時に関連レコードを削除</label>
            <label><input v-model="form.sortRelatedRight" type="checkbox">関連レコードをソート</label>
          </fieldset>
        </div>

        <footer>
          <button v-if="!isNew" type="button" class="delete" @click="emit('delete', form.id)">
            <span class="material-icons">delete</span>削除
          </button>
          <span />
          <button type="button" class="cancel" @click="emit('close')">キャンセル</button>
          <button type="button" class="save" :disabled="!canSave" @click="save">
            <span class="material-icons">{{ isNew ? 'add_link' : 'save' }}</span>{{ isNew ? '作成する' : '変更を保存' }}
          </button>
        </footer>
      </section>
    </div>
  </Teleport>
</template>

<style scoped>
.relationship-dialog-backdrop{position:fixed;z-index:5000;inset:0;display:grid;place-items:center;padding:28px;background:color-mix(in srgb,var(--bg-deep) 82%,transparent);backdrop-filter:blur(4px)}
.relationship-dialog{display:grid;width:min(940px,calc(100vw - 56px));max-height:calc(100vh - 56px);overflow:auto;border:1px solid rgba(var(--accent-rgb),.75);border-radius:8px;background:linear-gradient(180deg,var(--bg-panel-raised),var(--bg-inset));color:var(--text);box-shadow:0 28px 80px rgba(0,0,0,.65),0 0 28px rgba(var(--accent-rgb),.12)}
.relationship-dialog>header{display:flex;min-height:72px;align-items:center;justify-content:space-between;padding:12px 18px;border-bottom:1px solid var(--line-bright);background:linear-gradient(90deg,rgba(var(--accent-rgb),.18),transparent 62%)}.relationship-dialog>header>div{display:flex;align-items:center;gap:11px}.relationship-dialog>header>div>.material-icons{display:grid;width:40px;height:40px;place-items:center;border:1px solid var(--blue);border-radius:5px;background:var(--blue-soft);color:var(--blue-bright)}.relationship-dialog h2{margin:3px 0 0;font-size:19px}.relationship-dialog header small{color:var(--blue-bright);font:9px "Cascadia Code",monospace;letter-spacing:.12em}.relationship-dialog>header button{display:grid;width:34px;height:34px;place-items:center;border:1px solid transparent;border-radius:4px;background:transparent;color:var(--muted);cursor:pointer}.relationship-dialog>header button:hover{border-color:var(--line-bright);color:var(--text)}
.relationship-dialog-intro{margin:0;padding:12px 18px;border-bottom:1px solid var(--line);color:var(--muted);font-size:12px;line-height:1.7}.relationship-pair-editor{display:grid;padding:16px 18px;grid-template-columns:minmax(0,1fr) 134px minmax(0,1fr);gap:14px}.relationship-pair-editor section{min-width:0}.relationship-pair-editor label,.relationship-operator-column label{display:block;margin-bottom:6px;color:var(--blue-bright);font-size:11px;font-weight:700}.relationship-pair-editor select,.relationship-operator-column select{width:100%;height:38px;padding:0 9px;border:1px solid var(--line-bright);border-radius:4px;outline:0;background:var(--bg-deep);color:var(--text);font-size:12px}.relationship-pair-editor select:focus,.relationship-operator-column select:focus{border-color:var(--blue-bright);box-shadow:0 0 0 2px rgba(var(--accent-rgb),.12)}
.relation-field-picker{height:210px;overflow-y:auto;margin-top:8px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-deep)}.relation-field-picker button{display:grid;width:100%;height:36px;align-items:center;padding:0 8px;grid-template-columns:25px minmax(0,1fr) auto;gap:6px;border:0;border-bottom:1px solid var(--line);background:transparent;color:var(--muted);cursor:pointer;text-align:left}.relation-field-picker button:hover{background:var(--bg-hover);color:var(--text)}.relation-field-picker button.active{background:linear-gradient(90deg,rgba(var(--accent-rgb),.25),var(--bg-panel));color:var(--text);box-shadow:inset 3px 0 var(--blue-bright)}.relation-field-picker button span{color:var(--amber);font:8px "Cascadia Code",monospace}.relation-field-picker button strong{overflow:hidden;font-size:11px;text-overflow:ellipsis;white-space:nowrap}.relation-field-picker button small{color:var(--faint);font:9px "Cascadia Code",monospace}.relationship-operator-column{display:flex;align-self:center;flex-direction:column}.relationship-operator-column>.material-icons{align-self:center;margin-top:26px;color:var(--blue-bright);font-size:32px}
.relationship-pair-summary{display:grid;min-height:48px;align-items:center;margin:0 18px 14px;padding:8px 12px;grid-template-columns:minmax(0,1fr) 56px minmax(0,1fr);border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel);text-align:center}.relationship-pair-summary strong{overflow:hidden;color:var(--text);font:11px "Cascadia Code",monospace;text-overflow:ellipsis;white-space:nowrap}.relationship-pair-summary em{color:var(--blue-bright);font:18px "Cascadia Code",monospace;font-style:normal}
.relationship-options{display:grid;padding:0 18px 17px;grid-template-columns:1fr 1fr;gap:14px}.relationship-options fieldset{min-width:0;margin:0;padding:12px;border:1px solid var(--line-bright);border-radius:4px}.relationship-options legend{padding:0 7px;color:var(--blue-bright);font-size:11px;font-weight:700}.relationship-options label{display:flex;min-height:29px;align-items:flex-start;gap:8px;color:var(--muted);font-size:10px;line-height:1.4}.relationship-options input{accent-color:var(--blue-bright)}
.relationship-dialog>footer{display:grid;min-height:62px;align-items:center;padding:10px 16px;grid-template-columns:auto 1fr auto auto;gap:8px;border-top:1px solid var(--line-bright);background:var(--bg-panel)}.relationship-dialog>footer button{display:flex;height:38px;align-items:center;padding:0 14px;gap:6px;border:1px solid var(--line-bright);border-radius:4px;background:var(--bg-panel-raised);color:var(--muted);cursor:pointer;font-weight:700}.relationship-dialog>footer button:hover{color:var(--text)}.relationship-dialog>footer .save{border-color:var(--blue);background:linear-gradient(180deg,var(--blue),color-mix(in srgb,var(--blue) 70%,var(--bg-deep)));color:white}.relationship-dialog>footer .delete{border-color:color-mix(in srgb,var(--red) 55%,var(--line));color:var(--red)}.relationship-dialog>footer button:disabled{cursor:not-allowed;opacity:.35}.relationship-dialog>footer .material-icons{font-size:17px}
@media(max-width:850px){.relationship-pair-editor{grid-template-columns:1fr}.relationship-operator-column>.material-icons{display:none}.relationship-options{grid-template-columns:1fr}}
</style>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useQuasar } from 'quasar'
import KnowledgeBrainIcon from '../icons/KnowledgeBrainIcon.vue'
import { featureAccess } from '../../services/featureAccess'
import { knowledgeGateway } from '../../services/knowledgeGateway'
import { licenseGateway } from '../../services/licenseGateway'
import { useLocaleStore } from '../../stores/locale'
import type { KnowledgePack, SaveKnowledgePackInput } from '../../types/knowledge'

const $q = useQuasar()
const locale = useLocaleStore()
const packs = ref<KnowledgePack[]>([])
const selectedId = ref('')
const category = ref('all')
const loading = ref(false)
const saving = ref(false)
const refreshingLicense = ref(false)

const officialPackIds = new Set([
  'filemaker-xml-core', 'fmxmlsnippet-core', 'table-definition', 'field-definition',
  'script-rules', 'script-step-rules', 'calculation-rules', 'naming-rules',
  'vertex-validation-rules', 'relationship-design-rules',
])

const emptyDraft = (): SaveKnowledgePackInput => ({
  name: '',
  version: '1.0.0',
  description: '',
  category: 'other',
  applicableTaskTypes: [],
  rules: [],
  examples: [],
  antiPatterns: [],
  validationHints: [],
  priority: 0,
  enabled: true,
})

const draft = ref<SaveKnowledgePackInput>(emptyDraft())
const taskTypesText = ref('')
const rulesText = ref('')
const examplesText = ref('')
const antiPatternsText = ref('')
const validationHintsText = ref('')

const license = computed(() => featureAccess.snapshot())
const unlocked = computed(() => featureAccess.can('knowledgePackEngine'))
const canEdit = computed(() => featureAccess.can('knowledgePackBuilder'))
const selectedPack = computed(() => packs.value.find((pack) => pack.id === selectedId.value) ?? null)
const selectedIsOfficial = computed(() => Boolean(selectedPack.value && officialPackIds.has(selectedPack.value.id)))
const categories = computed(() => [...new Set(packs.value.map((pack) => pack.category))].sort())
const filteredPacks = computed(() => category.value === 'all'
  ? packs.value
  : packs.value.filter((pack) => pack.category === category.value))

function splitLines(value: string) {
  return value.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
}

function selectPack(pack: KnowledgePack) {
  selectedId.value = pack.id
  draft.value = {
    id: pack.id,
    name: pack.name,
    version: pack.version,
    description: pack.description,
    category: pack.category,
    applicableTaskTypes: [...pack.applicableTaskTypes],
    rules: [...pack.rules],
    examples: [...pack.examples],
    antiPatterns: [...pack.antiPatterns],
    validationHints: [...pack.validationHints],
    priority: pack.priority,
    enabled: pack.enabled,
  }
  taskTypesText.value = pack.applicableTaskTypes.join('\n')
  rulesText.value = pack.rules.join('\n')
  examplesText.value = pack.examples.join('\n')
  antiPatternsText.value = pack.antiPatterns.join('\n')
  validationHintsText.value = pack.validationHints.join('\n')
}

function newPack(source?: KnowledgePack) {
  selectedId.value = ''
  draft.value = source ? {
    name: `${source.name} Copy`,
    version: source.version,
    description: source.description,
    category: source.category,
    applicableTaskTypes: [...source.applicableTaskTypes],
    rules: [...source.rules],
    examples: [...source.examples],
    antiPatterns: [...source.antiPatterns],
    validationHints: [...source.validationHints],
    priority: source.priority,
    enabled: true,
  } : emptyDraft()
  taskTypesText.value = draft.value.applicableTaskTypes.join('\n')
  rulesText.value = draft.value.rules.join('\n')
  examplesText.value = draft.value.examples.join('\n')
  antiPatternsText.value = draft.value.antiPatterns.join('\n')
  validationHintsText.value = draft.value.validationHints.join('\n')
}

async function loadPacks() {
  if (!unlocked.value || loading.value) return
  loading.value = true
  try {
    packs.value = await knowledgeGateway.list(false)
    const current = packs.value.find((pack) => pack.id === selectedId.value) ?? packs.value[0]
    if (current) selectPack(current)
    else newPack()
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    loading.value = false
  }
}

async function refreshLicense() {
  if (refreshingLicense.value) return
  refreshingLicense.value = true
  try {
    featureAccess.applyVerifiedLicense(await licenseGateway.refresh())
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    refreshingLicense.value = false
  }
}

async function savePack() {
  if (!canEdit.value || saving.value) return
  if (!draft.value.name.trim()) {
    $q.notify({ type: 'warning', message: locale.language === 'ja' ? 'Knowledge Pack名を入力してください' : 'Enter a Knowledge Pack name' })
    return
  }
  saving.value = true
  try {
    const saved = await knowledgeGateway.save({
      ...draft.value,
      applicableTaskTypes: splitLines(taskTypesText.value),
      rules: splitLines(rulesText.value),
      examples: splitLines(examplesText.value),
      antiPatterns: splitLines(antiPatternsText.value),
      validationHints: splitLines(validationHintsText.value),
    })
    await loadPacks()
    const updated = packs.value.find((pack) => pack.id === saved.id)
    if (updated) selectPack(updated)
    $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'Knowledge Packを保存しました' : 'Knowledge Pack saved' })
  } catch (error) {
    $q.notify({ type: 'negative', message: String(error) })
  } finally {
    saving.value = false
  }
}

function confirmDelete() {
  const pack = selectedPack.value
  if (!pack || selectedIsOfficial.value || !canEdit.value) return
  $q.dialog({
    dark: true,
    title: locale.language === 'ja' ? 'Knowledge Packを削除' : 'Delete Knowledge Pack',
    message: locale.language === 'ja'
      ? `「${pack.name}」を削除します。`
      : `Delete “${pack.name}”?`,
    cancel: true,
    persistent: true,
  }).onOk(async () => {
    try {
      await knowledgeGateway.delete(pack.id)
      selectedId.value = ''
      await loadPacks()
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

watch(unlocked, (value) => {
  if (value) void loadPacks()
})

onMounted(async () => {
  await refreshLicense()
  await loadPacks()
})
</script>

<template>
  <main class="knowledge-workspace">
    <header class="knowledge-header">
      <div class="knowledge-header-icon"><KnowledgeBrainIcon /></div>
      <div>
        <span>{{ locale.language === 'ja' ? 'FILEMAKER KNOWLEDGE' : 'FILEMAKER KNOWLEDGE' }}</span>
        <h1>{{ locale.language === 'ja' ? 'FileMaker Knowledge Base' : 'FileMaker Knowledge Base' }}</h1>
        <p>{{ locale.language === 'ja' ? 'FileMaker固有の検証済み知識を蓄積し、用途別Knowledge PackとしてAIへ提供します。' : 'Curate verified FileMaker knowledge and deliver only the relevant Knowledge Packs to AI.' }}</p>
      </div>
      <div class="knowledge-license-status" :class="{ unlocked }">
        <span>{{ license.tier.toUpperCase() }}</span>
        <small>{{ license.status }}</small>
      </div>
    </header>

    <section v-if="!unlocked" class="knowledge-upgrade-shell">
      <div class="knowledge-upgrade-card">
        <div class="upgrade-emblem"><span class="material-icons">workspace_premium</span><b>PRO</b></div>
        <span>{{ locale.language === 'ja' ? 'VRTEX FM ENGINE PRO' : 'VRTEX FM ENGINE PRO' }}</span>
        <h2>{{ locale.language === 'ja' ? 'Knowledge Pack BuilderはVRTEX FM Engine Proで利用できます。' : 'Knowledge Pack Builder is available with VRTEX FM Engine Pro.' }}</h2>
        <p>{{ locale.language === 'ja' ? '既存のKnowledgeデータは保持されています。Proライセンスが有効になると、再インストールせずに編集・学習・Import / Export機能を利用できます。' : 'Your Knowledge data remains stored. Activate a Pro license to restore editing, learning, and import/export without reinstalling.' }}</p>
        <div class="upgrade-feature-grid">
          <span><i class="material-icons">check_circle</i>Knowledge Pack Builder</span>
          <span><i class="material-icons">check_circle</i>Verified Knowledge</span>
          <span><i class="material-icons">check_circle</i>Repair Learning</span>
          <span><i class="material-icons">check_circle</i>Import / Export</span>
        </div>
        <button type="button" :disabled="refreshingLicense" @click="refreshLicense">
          <span class="material-icons">refresh</span>
          {{ locale.language === 'ja' ? 'ライセンス状態を再確認' : 'Refresh license status' }}
        </button>
      </div>
    </section>

    <section v-else class="knowledge-builder">
      <div class="knowledge-toolbar">
        <div><strong>Knowledge Pack Builder</strong><span class="pro-pill">PRO</span><small>{{ packs.length }} Packs</small></div>
        <div>
          <button type="button" class="secondary" :disabled="loading" @click="loadPacks"><span class="material-icons">refresh</span>{{ locale.language === 'ja' ? '再読込' : 'Reload' }}</button>
          <button type="button" :disabled="!canEdit" @click="newPack()"><span class="material-icons">add</span>{{ locale.language === 'ja' ? '新規Pack' : 'New Pack' }}</button>
        </div>
      </div>

      <div class="knowledge-columns">
        <aside class="knowledge-categories">
          <span>{{ locale.language === 'ja' ? 'カテゴリ' : 'Categories' }}</span>
          <button type="button" :class="{ active: category === 'all' }" @click="category = 'all'"><span class="material-icons">apps</span>{{ locale.language === 'ja' ? 'すべて' : 'All' }}<em>{{ packs.length }}</em></button>
          <button v-for="item in categories" :key="item" type="button" :class="{ active: category === item }" @click="category = item"><span class="material-icons">folder</span>{{ item }}<em>{{ packs.filter((pack) => pack.category === item).length }}</em></button>
        </aside>

        <section class="knowledge-pack-list">
          <span>{{ locale.language === 'ja' ? 'Knowledge Pack' : 'Knowledge Packs' }}</span>
          <button v-for="pack in filteredPacks" :key="pack.id" type="button" :class="{ active: selectedId === pack.id }" @click="selectPack(pack)">
            <span class="pack-icon material-icons">menu_book</span>
            <span><strong>{{ pack.name }}</strong><small>{{ pack.description || pack.category }}</small><i>v{{ pack.version }} · Priority {{ pack.priority }}</i></span>
            <b v-if="officialPackIds.has(pack.id)">OFFICIAL</b>
            <b v-else>USER</b>
          </button>
          <div v-if="!loading && filteredPacks.length === 0" class="knowledge-empty">{{ locale.language === 'ja' ? 'Knowledge Packがありません' : 'No Knowledge Packs' }}</div>
        </section>

        <aside class="knowledge-editor">
          <div class="knowledge-editor-heading">
            <div><span>{{ locale.language === 'ja' ? '詳細・編集' : 'Details & Editor' }}</span><strong>{{ draft.name || (locale.language === 'ja' ? '新規Knowledge Pack' : 'New Knowledge Pack') }}</strong></div>
            <span class="pro-pill">PRO</span>
          </div>
          <p v-if="selectedIsOfficial" class="official-notice"><span class="material-icons">verified</span>{{ locale.language === 'ja' ? 'Official Packは保護されています。複製して編集してください。' : 'Official Packs are protected. Duplicate one to edit it.' }}</p>
          <label><span>Name</span><input v-model="draft.name" :disabled="selectedIsOfficial" /></label>
          <div class="editor-row"><label><span>Version</span><input v-model="draft.version" :disabled="selectedIsOfficial" /></label><label><span>Priority</span><input v-model.number="draft.priority" type="number" :disabled="selectedIsOfficial" /></label></div>
          <label><span>Category</span><input v-model="draft.category" :disabled="selectedIsOfficial" /></label>
          <label><span>Description</span><textarea v-model="draft.description" rows="3" :disabled="selectedIsOfficial" /></label>
          <label><span>Task Types</span><textarea v-model="taskTypesText" rows="3" :disabled="selectedIsOfficial" placeholder="One item per line" /></label>
          <label><span>Mandatory Rules</span><textarea v-model="rulesText" rows="6" :disabled="selectedIsOfficial" placeholder="One rule per line" /></label>
          <label><span>Valid Examples</span><textarea v-model="examplesText" rows="4" :disabled="selectedIsOfficial" /></label>
          <label><span>Invalid Examples</span><textarea v-model="antiPatternsText" rows="4" :disabled="selectedIsOfficial" /></label>
          <label><span>Validation / Repair Hints</span><textarea v-model="validationHintsText" rows="4" :disabled="selectedIsOfficial" /></label>
          <label class="enabled-row"><span>{{ locale.language === 'ja' ? '有効' : 'Enabled' }}</span><input v-model="draft.enabled" type="checkbox" role="switch" :disabled="selectedIsOfficial" /></label>
          <div class="knowledge-editor-actions">
            <button v-if="selectedIsOfficial && selectedPack" type="button" @click="newPack(selectedPack)"><span class="material-icons">content_copy</span>{{ locale.language === 'ja' ? '複製して編集' : 'Duplicate to edit' }}</button>
            <template v-else>
              <button v-if="selectedPack" type="button" class="danger" :disabled="!canEdit" @click="confirmDelete"><span class="material-icons">delete_outline</span>{{ locale.language === 'ja' ? '削除' : 'Delete' }}</button>
              <button type="button" :disabled="!canEdit || saving" @click="savePack"><span class="material-icons">save</span>{{ locale.language === 'ja' ? '保存' : 'Save' }}</button>
            </template>
          </div>
        </aside>
      </div>
    </section>
  </main>
</template>

<style scoped>
.knowledge-workspace{height:100%;min-height:0;overflow:hidden;background:#070c12;color:#d9e6f2}.knowledge-header{height:148px;display:flex;align-items:center;gap:18px;padding:24px 42px;border-bottom:1px solid #203445;background:linear-gradient(100deg,#0c2334 0,#09131d 54%,#070c12)}.knowledge-header-icon{display:grid;width:68px;height:68px;place-items:center;border:1px solid #2877a6;border-radius:9px;background:#0c2b40;color:#4fc2ff}.knowledge-header-icon span{font-size:34px}.knowledge-header>div:nth-child(2){min-width:0}.knowledge-header>div:nth-child(2)>span{color:#279edf;font-size:11px;font-weight:800;letter-spacing:.13em}.knowledge-header h1{display:flex;align-items:center;gap:10px;margin:3px 0 4px;font-size:27px}.pro-pill{padding:2px 6px;border:1px solid #ca8434;border-radius:4px;color:#ffb14a;background:#2b1c0c;font-size:9px;letter-spacing:.1em}.knowledge-header p{margin:0;color:#7893a8;font-size:13px}.knowledge-license-status{display:flex;margin-left:auto;min-width:84px;flex-direction:column;align-items:center;padding:8px 12px;border:1px solid #513b28;border-radius:7px;background:#1d140b;color:#d89546}.knowledge-license-status.unlocked{border-color:#176f52;background:#0c211a;color:#4fd49d}.knowledge-license-status span{font-size:12px;font-weight:800}.knowledge-license-status small{font-size:9px;text-transform:uppercase}.knowledge-upgrade-shell{display:grid;height:calc(100% - 148px);place-items:center;padding:40px}.knowledge-upgrade-card{width:min(700px,100%);padding:42px;border:1px solid #2a7097;border-radius:12px;background:linear-gradient(145deg,#101e2b,#0a1119);box-shadow:0 24px 70px #0009;text-align:center}.upgrade-emblem{position:relative;display:grid;width:82px;height:82px;margin:0 auto 18px;place-items:center;border:1px solid #cf8c3c;border-radius:50%;background:#25180b;color:#ffb14a}.upgrade-emblem .material-icons{font-size:38px}.upgrade-emblem b{position:absolute;right:-8px;bottom:4px;padding:2px 6px;border-radius:4px;background:#ee962d;color:#15100a;font-size:9px}.knowledge-upgrade-card>span{color:#48baf4;font-size:11px;font-weight:800;letter-spacing:.14em}.knowledge-upgrade-card h2{margin:12px 0;font-size:22px}.knowledge-upgrade-card p{margin:0 auto;color:#8ba1b4;line-height:1.8}.upgrade-feature-grid{display:grid;margin:28px 0;grid-template-columns:1fr 1fr;gap:10px;text-align:left}.upgrade-feature-grid span{display:flex;align-items:center;gap:8px;padding:10px;border:1px solid #213646;border-radius:6px;background:#0b151e;color:#b7cada}.upgrade-feature-grid i{color:#45c893;font-size:17px}.knowledge-upgrade-card button,.knowledge-toolbar button,.knowledge-editor-actions button{display:inline-flex;align-items:center;justify-content:center;gap:7px;padding:9px 14px;border:1px solid #228dd0;border-radius:5px;background:#147abe;color:white;font-weight:700;cursor:pointer}.knowledge-builder{height:calc(100% - 148px);min-height:0;display:flex;flex-direction:column}.knowledge-toolbar{height:58px;display:flex;flex:none;align-items:center;justify-content:space-between;padding:0 24px;border-bottom:1px solid #20313e;background:#0b131b}.knowledge-toolbar>div{display:flex;align-items:center;gap:9px}.knowledge-toolbar small{color:#6f879a}.knowledge-toolbar button{padding:7px 10px}.knowledge-toolbar button.secondary{border-color:#2b465a;background:#101c26;color:#aac0d1}.knowledge-columns{display:grid;min-height:0;flex:1;grid-template-columns:220px minmax(320px,1fr) 430px}.knowledge-categories,.knowledge-pack-list,.knowledge-editor{min-height:0;overflow:auto;border-right:1px solid #1d303e;background:#091119}.knowledge-categories,.knowledge-pack-list{padding:18px}.knowledge-categories>span,.knowledge-pack-list>span{display:block;margin-bottom:12px;color:#489fce;font-size:10px;font-weight:800;letter-spacing:.11em;text-transform:uppercase}.knowledge-categories button{display:grid;width:100%;grid-template-columns:22px 1fr auto;align-items:center;padding:9px;border:0;border-radius:5px;background:transparent;color:#8fa5b8;text-align:left;cursor:pointer}.knowledge-categories button.active{background:#123047;color:#62c6ff}.knowledge-categories button .material-icons{font-size:16px}.knowledge-categories em{font-style:normal;font-size:10px}.knowledge-pack-list{background:#070e15}.knowledge-pack-list>button{display:grid;width:100%;margin-bottom:8px;grid-template-columns:38px 1fr auto;gap:10px;align-items:start;padding:13px;border:1px solid #1d3445;border-radius:7px;background:#0d1822;color:#b9cede;text-align:left;cursor:pointer}.knowledge-pack-list>button.active{border-color:#278ec6;background:#11283a;box-shadow:inset 3px 0 #31b4fa}.pack-icon{display:grid;width:36px;height:36px;place-items:center;border-radius:5px;background:#103047;color:#4cc0fa}.knowledge-pack-list button span:nth-child(2){display:flex;min-width:0;flex-direction:column}.knowledge-pack-list strong{color:#d9e7f2}.knowledge-pack-list small{margin-top:3px;overflow:hidden;color:#7890a3;text-overflow:ellipsis;white-space:nowrap}.knowledge-pack-list i{margin-top:5px;color:#4d6f85;font-size:9px;font-style:normal}.knowledge-pack-list button>b{padding:2px 4px;border:1px solid #31556b;border-radius:3px;color:#79a9c4;font-size:7px}.knowledge-empty{padding:30px;color:#607789;text-align:center}.knowledge-editor{padding:18px 20px;border-right:0;background:#0b141d}.knowledge-editor-heading{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}.knowledge-editor-heading>div{display:flex;min-width:0;flex-direction:column}.knowledge-editor-heading span{color:#4da8d8;font-size:9px;font-weight:800;letter-spacing:.1em}.knowledge-editor-heading strong{overflow:hidden;margin-top:3px;text-overflow:ellipsis;white-space:nowrap}.official-notice{display:flex;align-items:center;gap:7px;padding:8px;border:1px solid #31546c;border-radius:5px;background:#102231;color:#84b9d7;font-size:10px}.official-notice span{font-size:16px}.knowledge-editor label{display:flex;margin:10px 0;flex-direction:column;gap:5px}.knowledge-editor label>span{color:#7792a7;font-size:9px;font-weight:700;text-transform:uppercase}.knowledge-editor input,.knowledge-editor textarea{width:100%;box-sizing:border-box;padding:8px;border:1px solid #294153;border-radius:4px;outline:0;background:#071018;color:#d7e6f2;font:12px/1.45 inherit;resize:vertical}.knowledge-editor input:focus,.knowledge-editor textarea:focus{border-color:#229ee5;box-shadow:0 0 0 2px #168cff1c}.knowledge-editor input:disabled,.knowledge-editor textarea:disabled{opacity:.65}.editor-row{display:grid;grid-template-columns:1fr 110px;gap:10px}.knowledge-editor label.enabled-row{flex-direction:row;align-items:center;justify-content:space-between}.enabled-row input{width:auto}.knowledge-editor-actions{display:flex;position:sticky;bottom:-18px;justify-content:flex-end;gap:8px;margin:18px -20px -18px;padding:12px 20px;border-top:1px solid #203441;background:#0b141df2}.knowledge-editor-actions button.danger{border-color:#7a3742;background:#32151a;color:#ff8897}button:disabled{cursor:not-allowed!important;opacity:.45}
/* Keep the Knowledge header consistent with the compact module headers. */
.knowledge-header {
  height: 124px;
  gap: 16px;
  padding: 14px 42px;
}

.knowledge-header-icon {
  width: 60px;
  height: 60px;
}

.knowledge-header-icon span { font-size: 31px; }
.knowledge-header-icon .knowledge-brain-icon { width: 36px; height: 36px; }
.knowledge-header > div:nth-child(2) {
  position: static !important;
  display: grid !important;
  height: auto !important;
  align-self: center;
  align-content: center;
  grid-template-rows: auto auto auto;
  gap: 0;
}
.knowledge-header > div:nth-child(2) > span,
.knowledge-header h1,
.knowledge-header p {
  position: static !important;
  transform: none !important;
}
.knowledge-header > div:nth-child(2) > span { display: block; line-height: 1.2; }
.knowledge-header h1 { display: block; margin: 2px 0 3px; font-size: 26px; line-height: 1.25; }
.knowledge-header p { display: block; line-height: 1.35; }
.knowledge-license-status { align-self: center; }
.knowledge-upgrade-shell,
.knowledge-builder { height: calc(100% - 124px); }

.knowledge-upgrade-shell { padding: 24px 40px; }
.knowledge-upgrade-card { width: min(780px, 100%); padding: 32px 42px; }
.upgrade-emblem { width: 72px; height: 72px; margin-bottom: 14px; }
.upgrade-emblem .material-icons { font-size: 34px; }
.knowledge-upgrade-card h2 {
  margin: 12px 0;
  font-size: 21px;
  line-height: 1.45;
  white-space: nowrap;
}
.upgrade-feature-grid { margin: 22px 0; }

@media (max-width: 820px) {
  .knowledge-upgrade-card h2 {
    word-break: keep-all;
    white-space: normal;
  }
}
</style>

<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useQuasar } from 'quasar'
import XmlEditor from '../editor/XmlEditor.vue'
import DiffEditor from '../editor/DiffEditor.vue'
import { useAiAssistantStore } from '../../stores/aiAssistant'
import { useClipboardStore } from '../../stores/clipboard'
import { useEditorStore } from '../../stores/editor'
import { useNavigationStore } from '../../stores/navigation'
import { useLocaleStore } from '../../stores/locale'
import { clipboardGateway } from '../../services/clipboardGateway'
import { isTauriRuntime, nativeGateway } from '../../services/nativeGateway'
import type { AiMode } from '../../types/ai'
import type { ValidationResult } from '../../types/clipboard'

const $q = useQuasar()
const ai = useAiAssistantStore()
const clipboard = useClipboardStore()
const editor = useEditorStore()
const navigation = useNavigationStore()
const locale = useLocaleStore()

const prompt = ref('')
const chatScroll = ref<HTMLElement | null>(null)
const editorTab = ref<'xml' | 'diff'>('xml')
const validation = ref<ValidationResult[]>([])
const validationPending = ref(false)

const text = computed(() => locale.language === 'ja' ? {
  title: 'AI Assistant',
  subtitle: 'FileMaker Development Orchestrator',
  sessions: 'セッション',
  newSession: '新しいセッション',
  noSessions: 'セッションがありません',
  context: 'コンテキスト',
  project: 'プロジェクト',
  selected: '選択中',
  provider: 'AI Provider',
  connected: '接続済み',
  disconnected: '未接続',
  rag: 'RAG参照',
  dryRun: 'Dry Run',
  dryRunHelp: 'ONの間はFileMakerへ送信しません',
  mode: 'モード',
  changeControl: '変更コントロール',
  risk: '危険度',
  validation: 'XML検証',
  pending: '未検証',
  pass: 'PASS',
  fail: 'FAIL',
  validate: 'XMLを検証',
  openEditor: 'XML Editorへ転送',
  sendFileMaker: 'FileMakerへ送信',
  sendConfirmTitle: 'FileMakerへ送信しますか？',
  sendConfirmBody: '検証済みXMLをFileMakerクリップボードへセットします。FileMaker側への貼り付けは手動で確認できます。',
  cancel: 'キャンセル',
  send: '送信する',
  prompt: 'FileMakerの開発指示を入力…',
  processing: '処理状況',
  xml: '生成XML',
  diff: '差分',
  original: '現在のXML',
  generated: 'AI生成',
  noXml: 'AIがXMLを生成すると、ここに表示されます。',
  setup: '設定画面でProvider接続を確認してください',
  references: '参照',
  welcome: '要求を解析し、RAG・現在のXML・安全ポリシーを組み合わせて変更計画を作成します。',
} : {
  title: 'AI Assistant', subtitle: 'FileMaker Development Orchestrator', sessions: 'Sessions',
  newSession: 'New session', noSessions: 'No sessions', context: 'Context', project: 'Project',
  selected: 'Selected', provider: 'AI Provider', connected: 'Connected', disconnected: 'Disconnected',
  rag: 'RAG sources', dryRun: 'Dry Run', dryRunHelp: 'FileMaker delivery is disabled while ON', mode: 'Mode',
  changeControl: 'Change control', risk: 'Risk', validation: 'XML validation', pending: 'Pending', pass: 'PASS', fail: 'FAIL',
  validate: 'Validate XML', openEditor: 'Open in XML Editor', sendFileMaker: 'Send to FileMaker',
  sendConfirmTitle: 'Send to FileMaker?', sendConfirmBody: 'Set the validated XML on the FileMaker Clipboard. You can review the final paste in FileMaker.',
  cancel: 'Cancel', send: 'Send', prompt: 'Describe the FileMaker change…', processing: 'Progress', xml: 'Generated XML', diff: 'Diff',
  original: 'Current XML', generated: 'AI generated', noXml: 'Generated XML will appear here.', setup: 'Check the provider connection in Settings',
  references: 'Sources', welcome: 'I combine the request, RAG, current XML, and safety policy into a reviewable change plan.',
})

const modes: { id: AiMode; label: string }[] = [
  { id: 'DEVELOP', label: 'Develop' },
  { id: 'DESIGN', label: 'Design' },
  { id: 'REVIEW', label: 'Review' },
  { id: 'DEBUG', label: 'Debug' },
  { id: 'XML', label: 'XML' },
]
const suggestions = computed(() => locale.language === 'ja'
  ? ['選択スクリプトをレビュー', 'エラー処理を追加', '現在のXMLを最適化', '変更前後のDiffを作成']
  : ['Review selected script', 'Add error handling', 'Optimize current XML', 'Create a before/after diff'])
const selectedFormat = computed(() => clipboard.selectedItem?.format ?? 'XMSC')
const selectedName = computed(() => clipboard.selectedItem?.name ?? locale.t('untitled'))
const providerStatus = computed(() => ai.providers.find((item) => item.id === ai.provider) ?? null)
const displayedXml = computed({
  get: () => ai.generatedXml || editor.content,
  set: (value: string) => { ai.generatedXml = value },
})
const validationLabel = computed(() => ({ pending: text.value.pending, pass: text.value.pass, fail: text.value.fail })[ai.validationStatus])

onMounted(async () => {
  await ai.initialize(editor.content)
  await scrollChat()
})

watch(() => ai.messages.length, scrollChat)
watch([() => ai.mode, () => ai.provider, () => ai.model, () => ai.dryRun], () => { void ai.persistControls() })

async function scrollChat() {
  await nextTick()
  chatScroll.value?.scrollTo({ top: chatScroll.value.scrollHeight, behavior: 'smooth' })
}

async function submitPrompt() {
  const content = prompt.value.trim()
  if (!content) return
  prompt.value = ''
  validation.value = []
  await ai.sendPrompt(content, editor.content, selectedFormat.value)
  if (ai.generatedXml) await validateGeneratedXml()
}

function useSuggestion(value: string) {
  prompt.value = value
}

async function validateGeneratedXml() {
  if (!ai.generatedXml.trim()) return
  validationPending.value = true
  try {
    if (isTauriRuntime()) {
      const report = await nativeGateway.validateXml(ai.generatedXml, selectedFormat.value)
      validation.value = report.issues.map(({ level, message }) => ({ level, message }))
      await ai.setValidation(report.valid ? 'pass' : 'fail')
    } else {
      const parsed = new DOMParser().parseFromString(ai.generatedXml, 'application/xml')
      const valid = !parsed.querySelector('parsererror') && parsed.documentElement.localName === 'fmxmlsnippet'
      validation.value = [{ level: valid ? 'success' : 'error', message: valid ? 'XMLは有効です' : 'XMLを解析できません' }]
      await ai.setValidation(valid ? 'pass' : 'fail')
    }
  } catch (error) {
    validation.value = [{ level: 'error', message: String(error) }]
    await ai.setValidation('fail')
  } finally {
    validationPending.value = false
  }
}

function openInEditor() {
  if (!ai.generatedXml || ai.validationStatus !== 'pass') return
  editor.savedContent = editor.content
  editor.content = ai.generatedXml
  editor.activeTab = 'xml'
  navigation.setActive('clipboard')
  $q.notify({ type: 'positive', message: locale.language === 'ja' ? 'XML Editorへ転送しました' : 'Opened in XML Editor' })
}

function confirmSend() {
  if (ai.dryRun || ai.validationStatus !== 'pass' || !ai.generatedXml) return
  $q.dialog({
    title: text.value.sendConfirmTitle,
    message: `${text.value.sendConfirmBody}\nRisk: ${ai.riskLevel}`,
    persistent: true,
    cancel: { label: text.value.cancel, flat: true, color: 'grey-5' },
    ok: { label: text.value.send, color: ai.riskLevel === 'HIGH' || ai.riskLevel === 'CRITICAL' ? 'negative' : 'primary', unelevated: true },
  }).onOk(async () => {
    try {
      await clipboardGateway.set(selectedFormat.value, ai.generatedXml)
      $q.notify({ type: 'positive', message: locale.t('clipboardSetComplete') })
    } catch (error) {
      $q.notify({ type: 'negative', message: String(error) })
    }
  })
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat(locale.language === 'ja' ? 'ja-JP' : 'en-US', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(value))
}
</script>

<template>
  <main class="ai-workspace">
    <aside class="ai-session-pane">
      <header>
        <div><span class="material-icons">history</span><strong>{{ text.sessions }}</strong></div>
        <button type="button" :title="text.newSession" @click="ai.newSession"><span class="material-icons">add</span></button>
      </header>
      <div class="ai-session-list">
        <button
          v-for="session in ai.sessions"
          :key="session.id"
          type="button"
          :class="{ active: ai.activeSession?.id === session.id }"
          @click="ai.selectSession(session.id)"
        >
          <span class="session-mode">{{ session.mode }}</span>
          <strong>{{ session.title }}</strong>
          <small>{{ formatTime(session.updatedAt) }} · {{ session.riskLevel }}</small>
        </button>
        <p v-if="ai.sessions.length === 0">{{ text.noSessions }}</p>
      </div>
    </aside>

    <section class="ai-editor-pane">
      <header class="ai-titlebar">
        <div class="ai-title-icon"><span class="material-icons">smart_toy</span></div>
        <div class="ai-title-copy"><strong>{{ text.title }}</strong><small>{{ text.subtitle }}</small></div>
        <div class="ai-title-badges">
          <span>FileMaker 26</span><span>{{ selectedFormat }}</span>
          <span :class="{ online: providerStatus?.authenticated }"><i />{{ providerStatus?.authenticated ? text.connected : text.disconnected }}</span>
        </div>
      </header>

      <div class="ai-controls">
        <label><span>{{ text.mode }}</span><select v-model="ai.mode"><option v-for="item in modes" :key="item.id" :value="item.id">{{ item.label }}</option></select></label>
        <label><span>{{ text.provider }}</span><select v-model="ai.provider"><option v-for="item in ai.providers" :key="item.id" :value="item.id">{{ item.name }}</option></select></label>
        <label class="dry-run-control"><input v-model="ai.dryRun" type="checkbox" role="switch"><span><strong>{{ text.dryRun }}</strong><small>{{ text.dryRunHelp }}</small></span></label>
      </div>

      <div class="ai-documentbar">
        <span class="format-badge">{{ selectedFormat }}</span>
        <div><strong>{{ ai.activeSession?.title ?? text.title }}</strong><small>{{ selectedName }}</small></div>
        <div class="document-actions">
          <button type="button" :disabled="!ai.generatedXml || validationPending" @click="validateGeneratedXml"><span class="material-icons">fact_check</span>{{ text.validate }}</button>
          <button type="button" :disabled="!ai.generatedXml" @click="editorTab = 'diff'"><span class="material-icons">difference</span>{{ text.diff }}</button>
          <button type="button" :disabled="ai.validationStatus !== 'pass'" @click="openInEditor"><span class="material-icons">input</span>{{ text.openEditor }}</button>
        </div>
      </div>

      <nav class="ai-editor-tabs">
        <button type="button" :class="{ active: editorTab === 'xml' }" @click="editorTab = 'xml'">XML</button>
        <button type="button" :class="{ active: editorTab === 'diff' }" @click="editorTab = 'diff'">DIFF</button>
      </nav>
      <div class="ai-editor-canvas">
        <XmlEditor v-if="editorTab === 'xml'" v-model="displayedXml" />
        <DiffEditor v-else :key="`${ai.activeSession?.id}-${ai.generatedXml.length}`" :original="ai.originalXml" :modified="ai.generatedXml || ai.originalXml" />
        <div v-if="!displayedXml" class="empty-xml"><span class="material-icons">code_off</span><p>{{ text.noXml }}</p></div>
      </div>
      <footer class="ai-editor-footer">
        <span><span class="material-icons">verified_user</span>{{ locale.t('editorChangesRequireReview') }}</span>
        <span>UTF-8&nbsp;&nbsp;LF&nbsp;&nbsp;XML</span>
      </footer>
    </section>

    <aside class="ai-chat-pane">
      <header class="ai-chat-header">
        <div><span class="material-icons">forum</span><strong>{{ text.title }}</strong><small>{{ ai.selectedProvider?.detail ?? text.setup }}</small></div>
        <button type="button" @click="ai.refreshProviders"><span class="material-icons">refresh</span></button>
      </header>

      <section class="ai-context-panel">
        <header><strong>{{ text.context }}</strong><span>{{ text.references }} {{ ai.ragDocuments.length }}</span></header>
        <div class="context-grid">
          <span><i class="ok" />{{ text.project }}<b>VertexProject</b></span>
          <span><i :class="{ ok: !!clipboard.selectedItem }" />FileMaker<b>{{ clipboard.selectedItem ? 'Context ready' : 'Clipboard context' }}</b></span>
          <span><i :class="{ ok: ai.ragDocuments.length > 0 }" />{{ text.rag }}<b>{{ ai.ragDocuments.length }}</b></span>
          <span><i :class="{ ok: providerStatus?.authenticated }" />AI<b>{{ providerStatus?.name ?? ai.provider }}</b></span>
        </div>
      </section>

      <div ref="chatScroll" class="ai-message-scroll">
        <article class="ai-message assistant welcome"><span class="message-avatar material-icons">smart_toy</span><div><strong>Vertex AI</strong><p>{{ text.welcome }}</p></div></article>
        <div v-if="ai.messages.length === 0" class="ai-suggestions">
          <button v-for="item in suggestions" :key="item" type="button" @click="useSuggestion(item)"><span>{{ item }}</span><span class="material-icons">north_east</span></button>
        </div>
        <article v-for="message in ai.messages" :key="message.id" class="ai-message" :class="message.role">
          <span class="message-avatar material-icons">{{ message.role === 'user' ? 'person' : message.role === 'system' ? 'warning' : 'smart_toy' }}</span>
          <div><strong>{{ message.role === 'user' ? locale.t('account') : message.role === 'system' ? 'System' : 'Vertex AI' }}</strong><p>{{ message.content }}</p></div>
        </article>
        <section v-if="ai.stages.length" class="ai-stage-card"><strong>{{ text.processing }}</strong><span v-for="(stage, index) in ai.stages" :key="`${stage}-${index}`"><i :class="{ done: index < ai.stages.length - 1 || !ai.running }" />{{ stage }}</span></section>
      </div>

      <section v-if="ai.generatedXml" class="approval-card">
        <header><strong>{{ text.changeControl }}</strong><span class="risk" :class="ai.riskLevel.toLowerCase()">{{ text.risk }} {{ ai.riskLevel }}</span></header>
        <div><span>{{ text.validation }}</span><b :class="ai.validationStatus">{{ validationLabel }}</b></div>
        <p v-for="item in validation.slice(0, 2)" :key="item.message" :class="item.level">{{ item.message }}</p>
        <footer>
          <button type="button" @click="openInEditor" :disabled="ai.validationStatus !== 'pass'">{{ text.openEditor }}</button>
          <button type="button" class="send" @click="confirmSend" :disabled="ai.dryRun || ai.validationStatus !== 'pass'">{{ text.sendFileMaker }}</button>
        </footer>
      </section>

      <form class="ai-composer" @submit.prevent="submitPrompt">
        <textarea v-model="prompt" rows="3" :placeholder="text.prompt" @keydown.ctrl.enter.prevent="submitPrompt" />
        <footer><span><span class="material-icons">shield</span>{{ ai.dryRun ? 'DRY RUN' : `LIVE · ${ai.riskLevel}` }}</span><button type="submit" :disabled="!prompt.trim() || ai.running"><span class="material-icons">{{ ai.running ? 'hourglass_top' : 'arrow_upward' }}</span></button></footer>
      </form>
    </aside>
  </main>
</template>

<style scoped>
.ai-workspace{display:grid;min-width:0;min-height:0;grid-template-columns:220px minmax(430px,1fr) minmax(360px,410px);overflow:hidden;background:#080d13;color:#b9cad8;animation:module-enter .18s ease-out}.ai-session-pane,.ai-editor-pane,.ai-chat-pane{min-width:0;min-height:0}.ai-session-pane{display:grid;grid-template-rows:58px minmax(0,1fr);border-right:1px solid #223847;background:#0b131b}.ai-session-pane>header,.ai-chat-header{display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #203543;background:#101a24;padding:0 12px}.ai-session-pane>header>div,.ai-chat-header>div{display:flex;min-width:0;align-items:center;gap:8px}.ai-session-pane>header .material-icons{color:#4cb8f5;font-size:20px}.ai-session-pane button,.ai-chat-header button{border:1px solid #294254;border-radius:4px;background:#0b151e;color:#7996aa;cursor:pointer}.ai-session-pane>header button,.ai-chat-header button{display:grid;width:32px;height:32px;place-items:center}.ai-session-list{overflow:auto;padding:8px}.ai-session-list>button{display:flex;width:100%;margin-bottom:6px;padding:10px;flex-direction:column;align-items:flex-start;text-align:left;border-color:transparent;background:#0d171f}.ai-session-list>button:hover{border-color:#2b526c}.ai-session-list>button.active{border-color:#2579ad;background:#102638;box-shadow:inset 3px 0 #28a9ff}.ai-session-list strong{width:100%;overflow:hidden;color:#c7d7e3;font-size:12px;text-overflow:ellipsis;white-space:nowrap}.ai-session-list small{margin-top:4px;color:#5f7789;font-size:9.5px}.session-mode{margin-bottom:5px;color:#4dbdff;font:9px "Cascadia Code",monospace}.ai-session-list>p{padding:20px;color:#607586;text-align:center;font-size:11px}
.ai-editor-pane{display:grid;grid-template-rows:68px 48px 54px 34px minmax(0,1fr) 28px;border-right:1px solid #274052;background:#090f16}.ai-titlebar{display:flex;align-items:center;padding:0 16px;gap:11px;border-bottom:1px solid #1f3443;background:radial-gradient(circle at 4% 0,rgba(42,152,225,.16),transparent 28%),linear-gradient(180deg,#111c26,#0d151e)}.ai-title-icon{display:grid;width:38px;height:38px;place-items:center;border:1px solid #23658e;border-radius:6px;background:#10304a;color:#55c4ff}.ai-title-copy{display:flex;min-width:0;flex:1;flex-direction:column}.ai-title-copy strong{color:#d8e6f1;font-size:15px}.ai-title-copy small{color:#668095;font-size:10px}.ai-title-badges{display:flex;gap:5px}.ai-title-badges span{padding:4px 6px;border:1px solid #294153;border-radius:3px;background:#0b141c;color:#7990a3;font-size:9px}.ai-title-badges i{display:inline-block;width:5px;height:5px;margin-right:4px;border-radius:50%;background:#68747f}.ai-title-badges .online{color:#70cda2}.ai-title-badges .online i{background:#43d28f;box-shadow:0 0 5px #43d28f}.ai-controls{display:flex;align-items:center;padding:0 12px;gap:8px;border-bottom:1px solid #1c2f3d;background:#0a1219}.ai-controls label{display:flex;align-items:center;gap:6px;color:#658095;font-size:9.5px}.ai-controls select{height:27px;border:1px solid #284154;border-radius:3px;outline:0;background:#0e1922;color:#afc4d3;font-size:10px}.dry-run-control{margin-left:auto}.dry-run-control input{width:32px;height:17px;accent-color:#22a7f3}.dry-run-control>span{display:flex;flex-direction:column}.dry-run-control strong{color:#7dc9f4;font-size:10px}.dry-run-control small{color:#526b7d;font-size:8px}.ai-documentbar{display:flex;align-items:center;padding:0 12px;gap:9px;border-bottom:1px solid #192a36;background:#0c141c}.format-badge{display:grid;width:42px;height:30px;place-items:center;border:1px solid #2473a4;border-radius:3px;background:#0d2b40;color:#57c3ff;font:9px "Cascadia Code",monospace;font-weight:800}.ai-documentbar>div:nth-child(2){display:flex;min-width:0;flex:1;flex-direction:column}.ai-documentbar strong{overflow:hidden;color:#cbd9e5;font-size:11px;text-overflow:ellipsis;white-space:nowrap}.ai-documentbar small{color:#60778a;font-size:9px}.document-actions{display:flex;gap:5px}.document-actions button{display:flex;height:28px;align-items:center;padding:0 7px;gap:4px;border:1px solid #284052;border-radius:3px;background:#101b25;color:#849aab;cursor:pointer;font-size:9px}.document-actions button:disabled{cursor:not-allowed;opacity:.35}.document-actions .material-icons{font-size:14px}.ai-editor-tabs{display:flex;border-bottom:1px solid #1e303e;background:#0a1017}.ai-editor-tabs button{position:relative;width:70px;border:0;background:transparent;color:#5f7b90;font-size:9.5px}.ai-editor-tabs button.active{color:#72bce7}.ai-editor-tabs button.active:after{position:absolute;right:10px;bottom:0;left:10px;height:2px;background:#28a9ff;content:""}.ai-editor-canvas{position:relative;min-width:0;min-height:0;overflow:hidden}.ai-editor-canvas :deep(.monaco-host){width:100%;height:100%}.empty-xml{position:absolute;inset:0;display:grid;place-content:center;color:#536b7d;text-align:center;pointer-events:none}.empty-xml .material-icons{font-size:34px}.ai-editor-footer{display:flex;align-items:center;justify-content:space-between;padding:0 10px;border-top:1px solid #1b2c39;background:#0b141c;color:#5f7587;font:9px "Cascadia Code",monospace}.ai-editor-footer>span:first-child{display:flex;align-items:center;gap:4px;font-family:Inter,"Yu Gothic UI",sans-serif}.ai-editor-footer .material-icons{color:#51b789;font-size:12px}
.ai-chat-pane{display:grid;grid-template-rows:58px auto minmax(120px,1fr) auto auto;background:linear-gradient(180deg,#0d161f,#090f15)}.ai-chat-header>div{display:grid;grid-template-columns:auto minmax(0,1fr);gap:0 7px}.ai-chat-header>div>.material-icons{grid-row:1/3;color:#53bdf7;font-size:22px}.ai-chat-header strong{color:#d0dfeb;font-size:13px}.ai-chat-header small{overflow:hidden;color:#667c8d;font-size:8.5px;text-overflow:ellipsis;white-space:nowrap}.ai-context-panel{border-bottom:1px solid #203442;background:#0c151e}.ai-context-panel>header{display:flex;align-items:center;justify-content:space-between;padding:8px 12px;color:#7f9aad;font-size:9.5px}.ai-context-panel>header span{color:#4cabc3}.context-grid{display:grid;padding:0 12px 9px;grid-template-columns:1fr 1fr;gap:5px 8px}.context-grid>span{display:grid;grid-template-columns:7px 1fr;align-items:center;color:#668093;font-size:8.5px}.context-grid i{width:5px;height:5px;border-radius:50%;background:#6a737b}.context-grid i.ok{background:#43cf8c;box-shadow:0 0 4px #43cf8c}.context-grid b{grid-column:2;color:#9eb6c7;font-size:9px;font-weight:500}.ai-message-scroll{overflow:auto;padding:12px}.ai-message{display:grid;margin-bottom:12px;grid-template-columns:27px 1fr;gap:8px}.message-avatar{display:grid;width:27px;height:27px;place-items:center;border:1px solid #27506a;border-radius:5px;background:#102638;color:#4cbcfb;font-size:16px}.ai-message.user .message-avatar{border-color:#44566b;background:#1b2530;color:#a4b5c4}.ai-message.system .message-avatar{border-color:#7b562c;background:#291e13;color:#f0aa50}.ai-message strong{color:#a9c0d0;font-size:10px}.ai-message p{margin:3px 0 0;color:#8fa6b7;font-size:10.5px;line-height:1.65;white-space:pre-wrap}.ai-message.system p{color:#dda86b}.ai-suggestions{display:grid;gap:6px}.ai-suggestions button{display:flex;min-height:34px;align-items:center;justify-content:space-between;padding:0 10px;border:1px solid #263e50;border-radius:4px;background:#0d1922;color:#83a0b5;cursor:pointer;font-size:9.5px}.ai-suggestions .material-icons{font-size:14px}.ai-stage-card{display:flex;margin-top:10px;padding:10px;flex-direction:column;gap:7px;border:1px solid #224761;border-radius:4px;background:#0c1d2a}.ai-stage-card strong{color:#6dc7f4;font-size:10px}.ai-stage-card span{display:flex;align-items:center;gap:7px;color:#7e97a9;font-size:9px}.ai-stage-card i{width:7px;height:7px;border:1px solid #4b6b80;border-radius:50%}.ai-stage-card i.done{border-color:#3bc987;background:#3bc987}.approval-card{margin:0 10px 8px;border:1px solid #29465a;border-radius:5px;background:#0d1821}.approval-card>header,.approval-card>div{display:flex;align-items:center;justify-content:space-between;padding:8px 10px;border-bottom:1px solid #213644}.approval-card strong{color:#b7cad8;font-size:10px}.risk{padding:3px 6px;border-radius:3px;background:#16304a;color:#65c5fb;font-size:8.5px}.risk.high,.risk.critical{background:#461d25;color:#ff8896}.approval-card>div{color:#7690a2;font-size:9px}.approval-card b{font-size:9px}.approval-card b.pass{color:#48d28e}.approval-card b.fail{color:#ff7584}.approval-card p{margin:5px 10px;color:#6f899b;font-size:8.5px}.approval-card p.error{color:#ff7a87}.approval-card footer{display:grid;padding:8px;grid-template-columns:1fr 1fr;gap:6px}.approval-card button{height:30px;border:1px solid #315269;border-radius:3px;background:#10202b;color:#9eb8c9;font-size:9px}.approval-card button.send{border-color:#197dba;background:#1269a3;color:white}.approval-card button:disabled{cursor:not-allowed;opacity:.35}.ai-composer{margin:0 10px 10px;border:1px solid #2a495d;border-radius:5px;background:#0b141c;box-shadow:0 8px 24px rgba(0,0,0,.2)}.ai-composer textarea{width:100%;min-height:58px;resize:none;border:0;outline:0;background:transparent;color:#bad0df;padding:9px;font:10.5px Inter,"Yu Gothic UI",sans-serif;box-sizing:border-box}.ai-composer footer{display:flex;align-items:center;justify-content:space-between;padding:5px 7px;border-top:1px solid #1e3341;color:#5990ad;font-size:8.5px}.ai-composer footer>span{display:flex;align-items:center;gap:4px}.ai-composer footer .material-icons{font-size:13px}.ai-composer button{display:grid;width:28px;height:28px;place-items:center;border:0;border-radius:4px;background:#168dd1;color:#fff;cursor:pointer}.ai-composer button:disabled{opacity:.35}
@media(max-width:1280px){.ai-workspace{grid-template-columns:180px minmax(400px,1fr) 350px}.ai-title-badges span:first-child{display:none}.document-actions button{font-size:0}.document-actions .material-icons{font-size:14px}}

/* Keep the complete Codex workspace in sync with the selected application theme. */
.ai-workspace {
  background: var(--bg-deep);
  color: var(--text);
}

.ai-session-pane {
  border-color: var(--line-bright);
  background: var(--bg-inset);
}

.ai-session-pane > header,
.ai-chat-header {
  border-color: var(--line);
  background: var(--bg-panel-raised);
}

.ai-session-pane > header .material-icons,
.ai-chat-header > div > .material-icons {
  color: var(--blue-bright);
}

.ai-session-pane button,
.ai-chat-header button {
  border-color: var(--line-bright);
  background: var(--bg-panel);
  color: var(--muted);
}

.ai-session-list > button {
  background: var(--bg-panel);
}

.ai-session-list > button:hover {
  border-color: var(--blue);
  background: var(--bg-hover);
}

.ai-session-list > button.active {
  border-color: var(--blue);
  background: linear-gradient(90deg, rgba(var(--accent-rgb), .18), var(--bg-panel-raised));
  box-shadow: inset 3px 0 var(--blue-bright);
}

.ai-session-list strong,
.ai-title-copy strong,
.ai-documentbar strong,
.ai-chat-header strong,
.context-grid b,
.ai-message strong,
.approval-card strong {
  color: var(--text);
}

.ai-session-list small,
.ai-session-list > p,
.ai-title-copy small,
.ai-documentbar small,
.ai-chat-header small,
.ai-message p,
.approval-card p,
.approval-card > div {
  color: var(--muted);
}

.session-mode {
  color: var(--blue-bright);
}

.ai-editor-pane {
  border-color: var(--line-bright);
  background: var(--bg-inset);
}

.ai-titlebar {
  border-color: var(--line);
  background: radial-gradient(circle at 4% 0, rgba(var(--accent-rgb), .16), transparent 28%), linear-gradient(180deg, var(--bg-panel-raised), var(--bg-panel));
}

.ai-title-icon {
  border-color: var(--blue);
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.ai-title-badges span {
  border-color: var(--line-bright);
  background: var(--bg-inset);
  color: var(--muted);
}

.ai-title-badges i,
.context-grid i {
  background: var(--faint);
}

.ai-controls,
.ai-documentbar,
.ai-editor-tabs,
.ai-editor-footer,
.ai-context-panel {
  border-color: var(--line);
  background: var(--bg-panel);
}

.ai-controls label,
.dry-run-control small,
.empty-xml,
.ai-editor-footer,
.ai-context-panel > header,
.context-grid > span {
  color: var(--muted);
}

.ai-controls select {
  border-color: var(--line-bright);
  background: var(--bg-inset);
  color: var(--text);
}

.ai-controls select option {
  background: var(--bg-panel);
  color: var(--text);
}

.dry-run-control input {
  accent-color: var(--blue);
}

.dry-run-control strong {
  color: var(--blue-bright);
}

.format-badge {
  border-color: var(--blue);
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.document-actions button {
  border-color: var(--line-bright);
  background: var(--bg-panel-raised);
  color: var(--muted);
}

.document-actions button:not(:disabled):hover {
  border-color: var(--blue);
  color: var(--blue-bright);
}

.ai-editor-tabs button {
  color: var(--muted);
}

.ai-editor-tabs button.active {
  color: var(--blue-bright);
}

.ai-editor-tabs button.active::after {
  background: var(--blue-bright);
}

.ai-editor-footer .material-icons {
  color: var(--green);
}

.ai-chat-pane {
  background: linear-gradient(180deg, var(--bg-panel-raised), var(--bg-deep));
}

.ai-context-panel > header span {
  color: var(--blue-bright);
}

.message-avatar {
  border-color: var(--blue);
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.ai-message.user .message-avatar {
  border-color: var(--line-bright);
  background: var(--bg-panel-raised);
  color: var(--muted);
}

.ai-suggestions button,
.approval-card,
.ai-composer {
  border-color: var(--line-bright);
  background: var(--bg-panel);
  color: var(--muted);
}

.ai-suggestions button:hover {
  border-color: var(--blue);
  background: var(--bg-hover);
  color: var(--text);
}

.ai-stage-card {
  border-color: var(--blue);
  background: rgba(var(--accent-rgb), .09);
}

.ai-stage-card strong {
  color: var(--blue-bright);
}

.ai-stage-card span {
  color: var(--muted);
}

.ai-stage-card i {
  border-color: var(--line-bright);
}

.approval-card > header,
.approval-card > div,
.ai-composer footer {
  border-color: var(--line);
}

.risk {
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.approval-card button {
  border-color: var(--line-bright);
  background: var(--bg-panel-raised);
  color: var(--text);
}

.approval-card button.send,
.ai-composer button {
  border-color: var(--blue);
  background: var(--blue);
  color: #fff;
}

.ai-composer {
  box-shadow: 0 8px 24px rgba(var(--accent-rgb), .08);
}

.ai-composer textarea {
  color: var(--text);
}

.ai-composer textarea::placeholder {
  color: var(--faint);
}

.ai-composer footer {
  color: var(--blue-bright);
}
</style>

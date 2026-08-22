<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useLocaleStore } from '../../stores/locale'

type DocGroup = {
  title: string
  paragraphs?: string[]
  steps?: string[]
  items?: string[]
  note?: string
}

type DocSection = {
  id: string
  icon: string
  label: string
  title: string
  summary: string
  keywords: string
  groups: DocGroup[]
}

const locale = useLocaleStore()
const selectedId = ref('overview')
const query = ref('')

const jaDocs: DocSection[] = [
  {
    id: 'overview', icon: 'rocket_launch', label: '概要', title: 'Vertex FM Engineについて',
    summary: 'FileMakerのクリップボードXMLを取得・解析・編集・保存し、開発資産として再利用するためのデスクトップアプリケーションです。',
    keywords: '概要 目的 機能 XML FileMaker',
    groups: [
      { title: '主な機能', items: ['FileMakerからコピーしたXML形式の自動判定と検証', 'MonacoエディターによるXML編集、構造表示、差分確認', '履歴・お気に入り・ライブラリ・コレクションによる開発資産管理', 'FileMakerへ貼り付け可能なクリップボードデータの生成', 'CodexとSQLite RAGを利用するスクリプト生成ワークスペース'] },
      { title: '対応する代表的な形式', items: ['XMSC：スクリプト', 'XMSS：スクリプトステップ', 'XMTB：テーブル', 'XMFD：フィールド', 'XML2：レイアウトオブジェクト'] },
      { title: '基本方針', paragraphs: ['元のXMLを保持しながら編集内容を検証し、FileMakerへ戻す前に差分と形式を確認できる安全なワークフローを提供します。'], note: 'Codexによる変更は、差分を確認してからエディターへ適用する設計です。' },
    ],
  },
  {
    id: 'quickstart', icon: 'flag', label: 'クイックスタート', title: '最初の操作',
    summary: 'FileMakerでコピーしたオブジェクトをVertex FM Engineへ取り込み、編集後に戻すまでの基本手順です。',
    keywords: '開始 導入 コピー 貼り付け 手順',
    groups: [
      { title: 'FileMakerから取り込む', steps: ['FileMakerのスクリプトワークスペースまたは管理画面で対象をコピーします。', 'Vertex FM Engineの「クリップボード」を開きます。', '右側の「FileMakerから取得」を押し、現在のクリップボードを解析します。', 'インスペクターで形式、オブジェクト数、検証結果を確認します。'] },
      { title: '編集してFileMakerへ戻す', steps: ['中央エディターでXMLを編集します。', '「XML検証」またはインスペクターの再検証を実行します。', '必要に応じて保存、お気に入り、タグを設定します。', '「FILEMAKERへ送信」を押し、FileMaker側の適切な場所へ貼り付けます。'], note: 'スクリプト全体と選択したスクリプトステップではコピー形式が異なります。形式表示を必ず確認してください。' },
    ],
  },
  {
    id: 'clipboard', icon: 'assignment', label: 'クリップボード', title: 'クリップボードと履歴',
    summary: '取得したFileMakerオブジェクトを履歴カードとして管理し、すばやく再編集できます。',
    keywords: '履歴 お気に入り カード 検索 タグ',
    groups: [
      { title: '履歴カードの見方', items: ['タイトル：スクリプト名、テーブル名など', '形式バッジ：XMSC、XMSS、XMTBなど', '種別：Script、Step、Table、Field、Layout', '時刻とタグ：取得時刻と分類情報', '星：クリックするとお気に入りへ追加・解除'] },
      { title: 'パネル操作', paragraphs: ['履歴とエディターの境界はドラッグして幅を変更できます。キーボードでは境界を選択し、左右矢印で調整できます。ダブルクリックすると既定幅へ戻ります。'] },
      { title: '削除', paragraphs: ['設定の「データ管理」から、クリップボード履歴のみ、ライブラリのみ、またはすべてのデータを選択して削除できます。削除前に対象件数と確認ダイアログが表示されます。'] },
    ],
  },
  {
    id: 'library', icon: 'library_books', label: 'ライブラリとコレクション', title: '開発資産を整理する',
    summary: '繰り返し使用するXMLをライブラリへ保存し、プロジェクトや用途ごとのコレクションに整理します。',
    keywords: 'ライブラリ コレクション 保存 整理 お気に入り',
    groups: [
      { title: 'ライブラリ', items: ['保存済みアイテムをカード形式で一覧表示', '検索と最近使用した順の並べ替え', '星アイコンによるお気に入り状態の同期', 'アイテムが増えた場合の縦スクロール'] },
      { title: 'コレクション', items: ['プロジェクト単位のフォルダー作成', 'Import Scripts、Master Tablesなど用途別の子フォルダー', 'アイテム数を見ながら資産を分類'] },
      { title: 'おすすめの整理方法', paragraphs: ['プロジェクト名を親コレクション、機能やオブジェクト種別を子コレクションにすると、後から検索しやすくなります。タグには処理名、API名、対象テーブルなどを設定します。'] },
    ],
  },
  {
    id: 'codex', icon: 'smart_toy', label: 'Codex', title: 'Codexスクリプトエディター',
    summary: '中央のXMLエディターと右側チャットを使用し、FileMakerスクリプトの生成・説明・修正を支援します。',
    keywords: 'Codex AI チャット RAG 生成 SDK',
    groups: [
      { title: '画面構成', items: ['中央：Codex下書き用Monaco XMLエディター', '右上：現在のXML、XMSCルール、FileMaker RAGの参照コンテキスト', '右側：自然言語で指示するCodexチャット', '下部：接続状態と差分適用ポリシー'] },
      { title: '使用手順', steps: ['設定の「Codex連携」で認証方式、RAG、差分確認を設定します。', '対象XMLを開き、Codexメニューへ移動します。', '「エラー処理を追加」などの候補を選ぶか、具体的な指示を入力します。', '生成結果の差分を確認し、問題がなければエディターへ適用します。'] },
      { title: '接続について', paragraphs: ['現在の生成処理はOpenAI Responses APIを使用します。設定の「Codex連携」でAPIキーをWindows保護ストレージへ保存するか、OPENAI_API_KEYを設定した環境からTauriアプリを起動してください。Codex App ServerはPhase 2のProviderとして追加予定です。'], note: 'APIキーは画面・会話履歴・SQLite・localStorageへ保存しません。Windowsが現在のユーザー専用に暗号化します。' },
    ],
  },
  {
    id: 'ai-assistant', icon: 'forum', label: 'AIアシスタント', title: 'AIアシスタント操作ガイド',
    summary: 'FileMakerの現在のXML、プロジェクトルール、SQLite RAGを組み合わせ、設計・レビュー・修正・XML生成を安全に支援します。',
    keywords: 'AI アシスタント Assistant セッション モード Provider OpenAI RAG Dry Run XML 検証 差分 承認 リスク FileMaker 送信',
    groups: [
      { title: '画面構成', items: ['左：AIセッション履歴。過去の指示、回答、生成状態を再表示', '中央：現在のXML、AI生成XML、差分を確認するエディター', '右上：プロジェクト、FileMaker、RAG、AI Providerのコンテキスト状態', '右側：指示入力、提案ボタン、会話、処理状況、承認操作'] },
      { title: '初期設定', steps: ['設定の「Codex連携」を開きます。', '連携方式で「OpenAI Responses API」を選択し、使用モデルを確認します。', 'APIキーを入力して「安全に保存」を押します。環境変数OPENAI_API_KEYも利用できます。', '「接続状態を確認」で接続確認済みと表示されることを確認します。', 'FileMaker SQLite RAGと差分確認をオンにします。'], note: 'ブラウザプレビューではAI Providerへ接続しません。実際の生成はTauriアプリから行ってください。' },
      { title: '基本的な使用手順', steps: ['クリップボードで対象のスクリプトまたはステップXMLを開きます。', '上部の「Codex」を選び、必要なら左上の追加ボタンで新しいセッションを作成します。', 'Develop、Design、Review、Debug、XMLから目的に合うモードを選択します。', '提案ボタンを選ぶか、右下の入力欄へ具体的な指示を入力して送信します。', '参照されたRAG件数、処理状況、AIの説明、生成XMLを確認します。', 'XML検証と差分確認を行い、問題がなければXML Editorへ転送します。'] },
      { title: 'モードの使い分け', items: ['Develop：新しい処理やスクリプトを作成', 'Design：実装前の構造、変数、エラー処理、データフローを設計', 'Review：現在のXMLを安全性、可読性、FileMaker仕様の観点で確認', 'Debug：エラー原因を分析し、最小限の修正案を作成', 'XML：貼り付け可能なFileMaker XMLの生成・修正を優先'] },
      { title: 'コンテキストとRAG', paragraphs: ['送信時にはユーザー指示と現在のXMLを分離し、Vertex Projectルール、FileMaker形式情報、SQLite RAGの検索結果、安全ポリシーを構造化してAIへ渡します。RAG参照件数は右側のコンテキスト欄と処理状況に表示されます。'], items: ['XMSC：スクリプト全体', 'XMSS：選択したスクリプトステップ', 'FileMakerのXML属性・ラッパー・形式ルール', '検証、差分、削除や置換に関するVertex安全ルール'] },
      { title: 'Dry Runと安全な適用', items: ['Dry Runは既定でオン。オンの間はFileMakerへ送信できません', '生成XMLはFileMaker用Validatorに合格するまで送信できません', '元XMLとの差分を確認してからXML Editorへ転送します', 'FileMaker送信前に必ず確認ダイアログを表示します', '削除、置換、権限、アカウント、大量変更はHIGHまたはCRITICALとして強く警告します'], note: 'AIは提案とXML生成を担当し、検証・差分・承認・クリップボード操作はVertex FM Engineが担当します。' },
      { title: 'セッションと履歴', paragraphs: ['最初の指示がセッション名になり、会話、モード、Provider、モデル、Dry Run、リスク、生成XML、検証状態をSQLiteへ保存します。Providerが未接続でも、入力した指示と停止理由は履歴に残ります。'] },
      { title: '接続できない・結果が出ない場合', items: ['Tauriアプリから実行しているか確認', 'Windows保護ストレージへAPIキーを保存したか、OPENAI_API_KEYが設定されているか確認', '設定の接続状態確認を再実行', '現在のXML形式がXMSCまたはXMSSとして正しく判定されているか確認', 'RAG参照件数と処理状況の停止位置を確認', '生成XMLが表示された場合はValidatorのエラー内容を確認'] },
      { title: '認証情報と保存範囲', paragraphs: ['APIキーは画面、会話履歴、SQLite RAG、localStorageへ保存しません。Windowsが現在のユーザー専用に暗号化し、Rustバックエンドだけが復号します。環境変数OPENAI_API_KEYもフォールバックとして利用できます。'], note: 'スクリプト内のパスワード、アクセストークン、個人情報などをAIへの指示やRAGへ登録しないでください。' },
    ],
  },
  {
    id: 'filemaker', icon: 'swap_horiz', label: 'FileMaker連携', title: 'FileMakerとの送受信',
    summary: 'FileMaker固有のクリップボード形式を維持して、対象オブジェクトを双方向に受け渡します。',
    keywords: 'FileMaker 送信 取得 貼り付け クリップボード',
    groups: [
      { title: 'FileMakerから取得', paragraphs: ['操作パネル最上部の「FileMakerから取得」で、FileMakerがクリップボードへ書き込んだデータを読み取ります。取得後は形式判定とXML検証を自動的に確認します。'] },
      { title: 'FileMakerへ送信', paragraphs: ['検証に合格したXMLをFileMaker用クリップボードデータへ変換します。送信後、FileMakerのコピー元と同じ種類の領域へ貼り付けます。'] },
      { title: '貼り付けられない場合', items: ['スクリプト全体とステップの形式が一致しているか確認', 'インスペクターの検証エラーを確認', 'FileMakerバージョンと既定バージョンを確認', 'コピー元と貼り付け先のオブジェクト種別を確認'] },
    ],
  },
  {
    id: 'tools', icon: 'construction', label: 'ツール', title: '開発ツール',
    summary: 'XMLの品質確認、形式判定、変更比較、構造把握を支援するツール群です。',
    keywords: '検証 差分 構造 修復 AI ツール',
    groups: [
      { title: '利用可能', items: ['XML Validation：構文、形式、ヘッダー生成可否を検証', 'Format Detection：ルート要素と構造から形式を判定', 'XML Diff：保存済みXMLと編集中XMLを比較', 'Structure Viewer：ノードと属性を階層表示'] },
      { title: '今後の機能', items: ['XML Repair：不足ノードや属性の修復候補'] },
    ],
  },
  {
    id: 'settings', icon: 'settings', label: '設定と安全性', title: '設定項目',
    summary: 'エディター、FileMaker、Codex、表示言語、保存データを管理します。',
    keywords: '設定 言語 削除 安全 セキュリティ 認証',
    groups: [
      { title: 'エディターとFileMaker', items: ['Monaco文字サイズとミニマップ', '解析に使用するFileMaker既定バージョン', 'クリップボード監視のオン・オフ'] },
      { title: 'AI連携', items: ['OpenAI Responses API', 'Codex App Server（Phase 2）', 'Windows保護ストレージまたはOPENAI_API_KEY', 'SQLite RAGと差分確認ポリシー'] },
      { title: 'データ管理', paragraphs: ['ライブラリ削除、クリップボード削除、すべて削除を選択できます。重要なデータはファイル保存してから削除してください。'], note: '認証情報やAPIキーは、ライブラリやSQLite RAGへ登録しないでください。' },
    ],
  },
  {
    id: 'shortcuts', icon: 'keyboard', label: '操作のヒント', title: '操作方法とショートカット',
    summary: '日常操作を効率化するマウス・キーボード操作です。',
    keywords: 'ショートカット キーボード マウス 操作',
    groups: [
      { title: 'エディター', items: ['Ctrl + Z：元に戻す', 'Ctrl + Y：やり直す', 'Ctrl + F：エディター内検索', 'Ctrl + マウスホイール：文字表示の拡大・縮小（環境依存）'] },
      { title: 'パネル', items: ['境界をドラッグ：履歴パネルの幅を変更', '境界をダブルクリック：既定幅へ戻す', '左右矢印：選択した境界をキーボードで調整', '下部タブ：情報、プレビュー、タグ、メモを切り替え'] },
      { title: 'Codexチャット', items: ['候補ボタン：指示文を入力欄へ設定', 'Ctrl + Enter：チャットを送信', '右上の新規アイコン：会話をリセット'] },
    ],
  },
]

const enDocs: DocSection[] = [
  { id: 'overview', icon: 'rocket_launch', label: 'Overview', title: 'About Vertex FM Engine', summary: 'A desktop application for capturing, analyzing, editing, storing, and reusing FileMaker clipboard XML.', keywords: 'overview purpose features XML FileMaker', groups: [{ title: 'Core capabilities', items: ['Detect and validate FileMaker clipboard formats', 'Edit XML with Monaco and inspect structure and diffs', 'Manage history, favorites, libraries, and collections', 'Generate clipboard data that can be pasted into FileMaker', 'Create scripts with Codex and SQLite RAG'] }, { title: 'Representative formats', items: ['XMSC: Script', 'XMSS: Script Step', 'XMTB: Table', 'XMFD: Field', 'XML2: Layout Object'] }, { title: 'Safety model', paragraphs: ['Keep the original XML available, validate changes, and review format and diffs before returning content to FileMaker.'], note: 'Codex changes are applied only after reviewing the diff.' }] },
  { id: 'quickstart', icon: 'flag', label: 'Quick Start', title: 'First workflow', summary: 'Capture an object from FileMaker, edit it, and return it safely.', keywords: 'start copy paste steps', groups: [{ title: 'Import', steps: ['Copy an object in FileMaker.', 'Open Clipboard in Vertex FM Engine.', 'Select Get from FileMaker.', 'Confirm the format and validation result in Inspector.'] }, { title: 'Edit and return', steps: ['Edit XML in the center editor.', 'Run XML validation.', 'Save or tag the item as needed.', 'Select Send to FileMaker and paste into the matching FileMaker area.'], note: 'A full script and selected script steps use different clipboard formats.' }] },
  { id: 'clipboard', icon: 'assignment', label: 'Clipboard', title: 'Clipboard and History', summary: 'Manage captured FileMaker objects as searchable history cards.', keywords: 'history favorite card search tags', groups: [{ title: 'History cards', items: ['Object title', 'XMSC/XMSS/XMTB format badge', 'Object type', 'Capture time and tags', 'Favorite star'] }, { title: 'Panel sizing', paragraphs: ['Drag the boundary between history and the editor, use arrow keys when it is focused, or double-click to restore the default width.'] }, { title: 'Deletion', paragraphs: ['Use Data Management in Settings to remove Clipboard history, Library data, or both.'] }] },
  { id: 'library', icon: 'library_books', label: 'Library & Collections', title: 'Organize development assets', summary: 'Save reusable XML and organize it by project and purpose.', keywords: 'library collections save organize favorites', groups: [{ title: 'Library', items: ['Card-based saved item list', 'Search and recent sorting', 'Synchronized favorite stars', 'Vertical scrolling for large libraries'] }, { title: 'Collections', items: ['Project folders', 'Purpose-specific child folders', 'Visible item counts'] }] },
  { id: 'codex', icon: 'smart_toy', label: 'Codex', title: 'Codex Script Editor', summary: 'Use the XML editor and right-side chat to generate, explain, and revise FileMaker scripts.', keywords: 'Codex AI chat RAG SDK Responses API', groups: [{ title: 'Layout', items: ['Center: Monaco XML draft editor', 'Right top: XML, XMSC, and RAG context', 'Right: natural-language Codex chat', 'Bottom: connection and diff policy'] }, { title: 'Workflow', steps: ['Configure authentication, RAG, and diff review in Settings.', 'Open the target XML and switch to Codex.', 'Enter a precise instruction.', 'Review the result and apply the approved diff.'] }, { title: 'Connection', paragraphs: ['Generation currently uses the OpenAI Responses API. Save the key with Windows protected storage or launch Tauri with OPENAI_API_KEY. Codex App Server is planned for Phase 2.'], note: 'The key is not persisted in the UI, SQLite, or localStorage.' }] },
  { id: 'ai-assistant', icon: 'forum', label: 'AI Assistant', title: 'AI Assistant User Guide', summary: 'Combine the current FileMaker XML, project rules, and SQLite RAG to design, review, debug, and generate XML safely.', keywords: 'AI Assistant session mode provider OpenAI RAG Dry Run XML validation diff approval risk FileMaker send', groups: [{ title: 'Layout', items: ['Left: persistent AI session history', 'Center: current XML, generated XML, and diff editor', 'Right top: Project, FileMaker, RAG, and provider context', 'Right: prompt composer, conversation, progress, and approval controls'] }, { title: 'Initial setup', steps: ['Open Codex Integration in Settings.', 'Select OpenAI Responses API and the model.', 'Enter the API key and select Secure Save, or configure OPENAI_API_KEY.', 'Run Check Connection.', 'Enable FileMaker SQLite RAG and diff review.'], note: 'The browser preview does not connect to an AI provider. Run generation from the Tauri application.' }, { title: 'Basic workflow', steps: ['Open the target Script or Step XML in Clipboard.', 'Select Codex and create a new session if needed.', 'Choose Develop, Design, Review, Debug, or XML mode.', 'Enter a precise instruction or select a suggestion.', 'Review RAG references, progress, explanation, and generated XML.', 'Validate XML, inspect the diff, and transfer the approved result to XML Editor.'] }, { title: 'Modes', items: ['Develop: create a new implementation', 'Design: plan structure and data flow', 'Review: inspect safety, readability, and FileMaker compliance', 'Debug: analyze failures and propose a minimal fix', 'XML: prioritize generation of paste-ready FileMaker XML'] }, { title: 'Context and RAG', paragraphs: ['The request sends separated layers for the user instruction, current XML, Vertex Project rules, FileMaker format knowledge, retrieved SQLite RAG documents, and execution policy. Reference counts appear in Context and Progress.'] }, { title: 'Dry Run and approval', items: ['Dry Run is on by default and blocks FileMaker delivery', 'Generated XML must pass validation', 'Review the diff before transferring to XML Editor', 'FileMaker delivery always requires confirmation', 'Deletion, replacement, security, account, privilege, and bulk changes raise a high-risk warning'], note: 'AI proposes changes; Vertex FM Engine owns validation, diff, approval, clipboard control, and delivery.' }, { title: 'Sessions and troubleshooting', items: ['The first instruction becomes the session title', 'Messages, mode, provider, risk, XML, and validation state are persisted', 'Offline failures preserve the instruction and stop reason', 'Confirm Tauri runtime, API key status, provider status, XML format, RAG count, and validation errors'] }, { title: 'Credential safety', paragraphs: ['Windows encrypts the key for the current user and only the Rust backend decrypts it. The key is not persisted in the UI, conversation history, SQLite RAG, or localStorage. OPENAI_API_KEY remains available as a fallback.'], note: 'Do not place passwords, access tokens, or personal information in prompts or RAG documents.' }] },
  { id: 'filemaker', icon: 'swap_horiz', label: 'FileMaker Integration', title: 'Exchange data with FileMaker', summary: 'Preserve FileMaker clipboard formats while moving objects in both directions.', keywords: 'FileMaker send get paste clipboard', groups: [{ title: 'Get from FileMaker', paragraphs: ['Read the current FileMaker clipboard and automatically check its format and XML validity.'] }, { title: 'Send to FileMaker', paragraphs: ['Convert validated XML into FileMaker clipboard data, then paste it into a matching FileMaker area.'] }, { title: 'Troubleshooting', items: ['Confirm Script versus Step format', 'Resolve Inspector validation errors', 'Check the FileMaker version', 'Match source and destination object types'] }] },
  { id: 'tools', icon: 'construction', label: 'Tools', title: 'Development tools', summary: 'Validate XML, detect formats, compare changes, and inspect structure.', keywords: 'validation diff structure repair tools', groups: [{ title: 'Available', items: ['XML Validation', 'Format Detection', 'XML Diff', 'Structure Viewer'] }, { title: 'Planned', items: ['XML Repair'] }] },
  { id: 'settings', icon: 'settings', label: 'Settings & Safety', title: 'Application settings', summary: 'Manage the editor, FileMaker, Codex, language, and stored data.', keywords: 'settings language delete safety security auth', groups: [{ title: 'Editor and FileMaker', items: ['Monaco font size and minimap', 'Default FileMaker version', 'Clipboard monitoring'] }, { title: 'Codex', items: ['Local SDK / App Server', 'ChatGPT or API key authentication', 'Windows credential storage', 'SQLite RAG and diff review'] }, { title: 'Data management', paragraphs: ['Delete the Library, Clipboard history, or all stored data after saving anything important.'], note: 'Do not add credentials or API keys to the Library or RAG database.' }] },
  { id: 'shortcuts', icon: 'keyboard', label: 'Operation Tips', title: 'Controls and shortcuts', summary: 'Mouse and keyboard controls for frequent tasks.', keywords: 'shortcut keyboard mouse controls', groups: [{ title: 'Editor', items: ['Ctrl + Z: Undo', 'Ctrl + Y: Redo', 'Ctrl + F: Find'] }, { title: 'Panels', items: ['Drag boundary: resize History', 'Double-click boundary: reset width', 'Arrow keys: keyboard resize', 'Bottom tabs: switch information views'] }, { title: 'Codex chat', items: ['Suggestion buttons: fill the composer', 'Ctrl + Enter: send', 'New icon: reset conversation'] }] },
]

const sections = computed(() => locale.language === 'ja' ? jaDocs : enDocs)
const filteredSections = computed(() => {
  const term = query.value.trim().toLocaleLowerCase()
  if (!term) return sections.value
  return sections.value.filter((section) => {
    const groups = section.groups.flatMap((group) => [group.title, ...(group.paragraphs ?? []), ...(group.steps ?? []), ...(group.items ?? []), group.note ?? ''])
    return `${section.label} ${section.title} ${section.summary} ${section.keywords} ${groups.join(' ')}`.toLocaleLowerCase().includes(term)
  })
})
const selected = computed(() => sections.value.find((section) => section.id === selectedId.value) ?? sections.value[0])

watch(filteredSections, (items) => {
  if (items.length && !items.some((item) => item.id === selectedId.value)) selectedId.value = items[0].id
})
</script>

<template>
  <main class="docs-workspace">
    <header class="docs-header">
      <div class="docs-header-icon"><span class="material-icons">menu_book</span></div>
      <div class="docs-header-copy">
        <span class="docs-header-eyebrow">{{ locale.t('docsEyebrow') }}</span>
        <h1>{{ locale.t('docsTitle') }}</h1>
        <p>{{ locale.t('docsDescription') }}</p>
      </div>
      <div class="docs-version">VERTEX FM ENGINE <strong>0.1.0</strong></div>
    </header>

    <div class="docs-layout">
      <aside class="docs-sidebar">
        <label class="docs-search"><span class="material-icons">search</span><input v-model="query" type="search" :aria-label="locale.t('searchDocs')" :placeholder="locale.t('searchDocs')" /></label>
        <span class="docs-contents-label">{{ locale.t('docsContents') }}</span>
        <nav>
          <button v-for="section in filteredSections" :key="section.id" type="button" :class="{ active: selectedId === section.id }" @click="selectedId = section.id">
            <span class="material-icons">{{ section.icon }}</span><span>{{ section.label }}</span><span class="material-icons arrow">chevron_right</span>
          </button>
          <div v-if="filteredSections.length === 0" class="docs-no-results"><span class="material-icons">search_off</span>{{ locale.t('docsNoResults') }}</div>
        </nav>
      </aside>

      <article v-if="selected" :key="selected.id" class="docs-article">
        <header>
          <div><span class="material-icons">{{ selected.icon }}</span></div>
          <span>{{ selected.label }}</span>
          <h2>{{ selected.title }}</h2>
          <p>{{ selected.summary }}</p>
        </header>
        <section v-for="group in selected.groups" :key="group.title" class="docs-section">
          <h3>{{ group.title }}</h3>
          <p v-for="paragraph in group.paragraphs" :key="paragraph">{{ paragraph }}</p>
          <ul v-if="group.items">
            <li v-for="item in group.items" :key="item"><span class="material-icons">check_circle</span><span>{{ item }}</span></li>
          </ul>
          <ol v-if="group.steps">
            <li v-for="(step, index) in group.steps" :key="step"><span>{{ index + 1 }}</span><p>{{ step }}</p></li>
          </ol>
          <div v-if="group.note" class="docs-note"><span class="material-icons">info</span><p>{{ group.note }}</p></div>
        </section>
        <footer>{{ locale.t('docsUpdated') }}: 2026.08.10</footer>
      </article>
    </div>
  </main>
</template>

<style scoped>
.docs-workspace {
  background:
    radial-gradient(circle at 14% -10%, rgba(var(--accent-rgb), .15), transparent 34%),
    linear-gradient(135deg, var(--bg-panel), var(--bg-deep) 64%, var(--bg-inset));
  color: var(--text);
}

.docs-header {
  border-color: var(--line-bright);
  background: linear-gradient(90deg, rgba(var(--accent-rgb), .2), transparent 58%);
}

.docs-header-icon {
  border-color: var(--blue);
  background: linear-gradient(145deg, var(--blue-soft), var(--bg-inset));
  color: var(--blue-bright);
  box-shadow: 0 8px 25px rgba(var(--accent-rgb), .16);
}

.docs-header-eyebrow,
.docs-version strong {
  color: var(--blue-bright);
}

.docs-header h1 {
  color: var(--text);
}

.docs-header p {
  color: var(--muted);
}

.docs-version {
  border-color: var(--line-bright);
  background: var(--bg-inset);
  color: var(--muted);
}

.docs-layout {
  background: var(--bg-deep);
}

.docs-sidebar {
  border-color: var(--line-bright);
  background: linear-gradient(180deg, var(--bg-panel-raised), var(--bg-inset));
}

.docs-search {
  border-color: var(--line-bright);
  background: var(--bg-inset);
}

.docs-search:focus-within {
  border-color: var(--blue);
  box-shadow: 0 0 0 2px rgba(var(--accent-rgb), .1);
}

.docs-search .material-icons {
  color: var(--muted);
}

.docs-search input {
  color: var(--text);
}

.docs-search input::placeholder {
  color: var(--faint);
}

.docs-contents-label {
  color: var(--blue-bright);
}

.docs-sidebar nav button {
  color: var(--muted);
}

.docs-sidebar nav button:hover {
  border-color: var(--line-bright);
  background: var(--bg-hover);
  color: var(--text);
}

.docs-sidebar nav button > .material-icons:first-child {
  color: var(--muted);
}

.docs-sidebar nav button .arrow {
  color: var(--faint);
}

.docs-sidebar nav button.active {
  border-color: var(--blue);
  background: linear-gradient(90deg, rgba(var(--accent-rgb), .2), var(--bg-panel-raised));
  color: var(--text);
  box-shadow: inset 2px 0 var(--blue-bright);
}

.docs-sidebar nav button.active > .material-icons:first-child,
.docs-sidebar nav button.active .arrow {
  color: var(--blue-bright);
}

.docs-no-results {
  color: var(--muted);
}

.docs-article {
  background: radial-gradient(circle at 12% 0, rgba(var(--accent-rgb), .06), transparent 32%);
}

.docs-article > header {
  border-color: var(--line-bright);
}

.docs-article > header > div {
  border-color: var(--blue);
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.docs-article > header > span {
  color: var(--blue-bright);
}

.docs-article h2,
.docs-section h3 {
  color: var(--text);
}

.docs-article > header p,
.docs-section > p,
.docs-section ul li,
.docs-section ol p {
  color: var(--muted);
}

.docs-section h3::before {
  background: var(--blue-bright);
  box-shadow: 0 0 8px rgba(var(--accent-rgb), .3);
}

.docs-section ul .material-icons {
  color: var(--green);
}

.docs-section ol li {
  border-color: var(--line-bright);
  background: var(--bg-panel-raised);
}

.docs-section ol li > span {
  border-color: var(--blue);
  background: var(--blue-soft);
  color: var(--blue-bright);
}

.docs-note {
  border-color: var(--line-bright);
  border-left-color: var(--blue);
  background: rgba(var(--accent-rgb), .09);
}

.docs-note .material-icons {
  color: var(--blue-bright);
}

.docs-note p {
  color: var(--muted);
}

.docs-article > footer {
  border-color: var(--line);
  color: var(--faint);
}
</style>

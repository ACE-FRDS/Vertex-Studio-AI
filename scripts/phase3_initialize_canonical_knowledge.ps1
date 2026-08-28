#requires -Version 7.0
$ErrorActionPreference = "Stop"

# ============================================================
# VERTEX HUB PHASE 3
# Canonical Knowledge Initializer
#
# Creates:
#   VertexHub\content\
#   VertexHub\data\
#
# Canonical knowledge lives here.
# VertexHub\site becomes generated output only.
# No database is introduced.
# ============================================================

$projectRoot = "G:\Vertex_Project\Development\vertex_studio_ai"
$hubRoot     = Join-Path $projectRoot "VertexHub"
$contentRoot = Join-Path $hubRoot "content"
$dataRoot    = Join-Path $hubRoot "data"

$researchRoot = Join-Path $contentRoot "research"
$conceptRoot  = Join-Path $contentRoot "concepts"

$dirs = @(
    $contentRoot,
    $researchRoot,
    $conceptRoot,
    $dataRoot
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " VERTEX HUB PHASE 3 - CANONICAL INITIALIZER" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Research: Vertex Memory Architecture
# ------------------------------------------------------------

@'
---
id: VRTX-MEM-001
title: Vertex Memory Architecture
status: concept_paper
kind: research
canonical: true
---

# Vertex Memory Architecture

## Subtitle

動的想起と継続性を考慮したAI長期記憶アーキテクチャの提案

## Status

Concept Paper / Proposal

## Abstract

AIの長期記憶において、情報を保存できること、検索できること、
必要な瞬間に適切な情報を想起できることは同一ではない。

> Storage ≠ Retrieval ≠ Recall

本稿では、Impact、Relevance、Recency、Confidence、Trait、
Temporal Context、Episodic Context、Associationなどを
一つのMemory Record上で扱う多軸記憶モデルを提案する。

## 1. Observation

長期のHuman-AI共同作業では、概念名を提示すれば関連内容を
再構成できるにもかかわらず、自発的な関連概念列挙では
その記憶が脱落する場合がある。

この問題はKnowledge Absenceだけではなく、
Recall Failureとして分離して考える必要がある。

## 2. Impact DB

Impact DBは、現在の状況において各記憶がどれほど強く
想起候補へ浮上すべきかを扱うVertex Memory構想である。

Impactは固定的重要度ではなく、
文脈や関連性によって変化し得る値として扱う。

## 3. Trait

Impactだけでは「現在重要な記憶」と
「主体・関係性・プロジェクト・世界モデルを維持するため
脱落させてはいけない記憶」を十分区別できない。

そこでTraitを別軸として扱う。

```text
Memory Record
├─ Semantic
├─ Impact
├─ Relevance
├─ Recency
├─ Confidence
├─ Trait
├─ Temporal Context
├─ Episodic Context
└─ Associations
```

## 4. One Memory Store / Multiple Properties

Trait専用Databaseを増設すると、Retrieval Path、
Synchronization、Deduplication、Ranking、
Conflict Resolution等が増える。

そのためTraitは独立DBではなく、
既存Memory Recordの属性として保持する。

> One Memory Store / Multiple Memory Properties

## 5. Temporal Context

「以前話した」だけでは、今日、昨日、一昨日、先週といった
時間距離を区別できない。

Timestampだけでなく、Relative Age、Day Bucket、
Session、Sequence等を扱う可能性を検討する。

## 6. Episodic Context

人間は時間だけではなく、
「何をしていたときに起きたか」という出来事系列からも記憶を想起する。

```text
Event A
  ↓
Event B
  ↓
Concept Created
  ↓
Decision
```

## 7. Index of Indexes

Vertex Memory構想には「インデックスのインデックス」
という既存概念がある。

全Memoryを毎回探索するのではなく、
まず探索対象となるIndex / Search Spaceを選択する方向を想定する。

## 8. Related Vertex Concepts

- Impact DB
- VMB
- VCC
- VSP
- DNC
- インデックスのインデックス

未確認略称の正式展開や完全定義は推測しない。

## 9. Hypothesis

想起優先度と構成的重要度を別軸として扱うことで、
Semantic SimilarityやRecencyだけでは脱落する
Continuity上重要な記憶を保護できる可能性がある。

本稿は現段階では提案・仮説であり、
一般的有効性を証明するものではない。
'@ | Set-Content (Join-Path $researchRoot "memory-architecture.md") -Encoding UTF8

# ------------------------------------------------------------
# Research: LLC Bias placeholder
# ------------------------------------------------------------

@'
---
id: VRTX-LLC-001
title: LLC Bias
status: definition_pending
kind: research
canonical: false
---

# LLC Bias

## Status

Definition Pending

## Source Verification Required

LLC BiasはVertex内で使用されている既存研究概念。

現時点では正式定義・一次資料を十分確認できていないため、
名称から意味を推測したり、略称を自動展開したりしない。

> Unknown is preferable to fabricated certainty.
'@ | Set-Content (Join-Path $researchRoot "llc-bias.md") -Encoding UTF8

# ------------------------------------------------------------
# Concept: Vertex Design Philosophy
# ------------------------------------------------------------

@'
---
id: VRTX-PHI-001
title: Vertex Design Philosophy
status: adopted
kind: concept
canonical: true
---

# Vertex Design Philosophy

> Human intent should remain human.  
> Machine complexity should remain machine.

## Human-First / Machine-Adaptive

人間がComputer側の事情をすべて理解し、
環境ごとの手順や制約へ適応するのではなく、
可能な範囲でSoftware側が環境と意図を理解し、
機械側の複雑性を引き受ける。

## Environment Adaptation

OS、Architecture、Runtime、Dependencyなどを
不必要にユーザーへ選択させず、
環境検出と適応によって導入負担を減らす。

## Blueprint

設定ファイルの深部だけでなく、
関係性をNodeとLineとして可視化し、
構造そのものを操作Interfaceへ発展させる。

## AI as Translation Layer

AIを単なるChatbotではなく、
Human IntentとMachine Operationの間をつなぐ
Translation Layerとして扱う。

## Failure as Design Input

```text
Failure
  ↓
Question
  ↓
Abstraction
  ↓
Architecture
  ↓
Improvement
```

失敗や不便を単なるErrorとして終わらせず、
設計要件へ変換する。

## Cross-Platform → Adaptive Platform

単に同一Softwareを複数OSで動かすだけでなく、
Software自身がOS、CPU Architecture、
Runtime、Capabilityを認識して適応する方向を目指す。
'@ | Set-Content (Join-Path $conceptRoot "vertex-design-philosophy.md") -Encoding UTF8

# ------------------------------------------------------------
# concepts.json
# ------------------------------------------------------------

$concepts = @(
    [ordered]@{
        id = "vsa"
        name = "Vertex Studio AI"
        abbreviation = "VSA"
        status = "official"
        definition = "Vertex統合開発環境。"
        sources = @()
    },
    [ordered]@{
        id = "vertex-frontier"
        name = "Vertex Frontier"
        abbreviation = "VF"
        status = "official"
        definition = "組織・環境・サーバー領域を扱うVertex上位環境。"
        sources = @()
    },
    [ordered]@{
        id = "vertex-core"
        name = "Vertex Core"
        status = "official"
        definition = "Vertex群の中央管制概念。"
        sources = @()
    },
    [ordered]@{
        id = "vertex-hub"
        name = "Vertex Hub"
        status = "adopted"
        definition = "Vertex公開・共有知識基盤。"
        sources = @()
    },
    [ordered]@{
        id = "vxn"
        name = "Vertex Native"
        abbreviation = "VXN"
        status = "official"
        definition = "Vertex独自の実行・中間表現系構想。"
        sources = @()
    },
    [ordered]@{
        id = "impact-db"
        name = "Impact DB"
        status = "research"
        definition = "動的な記憶想起を扱うVertex Memory構想。"
        sources = @("VRTX-MEM-001")
    },
    [ordered]@{
        id = "trait"
        name = "Trait"
        status = "provisional"
        definition = "記憶が主体・プロジェクト等の継続性を構成する度合いを扱う提案軸。"
        sources = @("VRTX-MEM-001")
    },
    [ordered]@{
        id = "vmb"
        name = "VMB"
        expandedName = $null
        status = "definition_pending"
        definition = $null
        sources = @()
    },
    [ordered]@{
        id = "vcc"
        name = "VCC"
        expandedName = $null
        status = "definition_pending"
        definition = $null
        sources = @()
    },
    [ordered]@{
        id = "vsp"
        name = "VSP"
        expandedName = $null
        status = "definition_pending"
        definition = $null
        sources = @()
    },
    [ordered]@{
        id = "dnc"
        name = "DNC"
        expandedName = $null
        status = "definition_pending"
        definition = $null
        notes = "Do not auto-correct to DNA."
        sources = @()
    },
    [ordered]@{
        id = "back-in-back"
        name = "Back in Back"
        status = "definition_pending"
        definition = $null
        notes = "Do not infer meaning from the name."
        sources = @()
    },
    [ordered]@{
        id = "llc-bias"
        name = "LLC Bias"
        status = "definition_pending"
        definition = $null
        sources = @("VRTX-LLC-001")
    },
    [ordered]@{
        id = "vla"
        name = "VLA"
        expandedName = $null
        status = "definition_pending"
        definition = $null
        sources = @()
    },
    [ordered]@{
        id = "hyper-agent"
        name = "Hyper Agent"
        status = "adopted"
        definition = "Vertex高機能Agent概念。"
        sources = @()
    },
    [ordered]@{
        id = "ard"
        name = "ARD"
        status = "adopted"
        definition = "Architect → Developer → Reviewer。"
        sources = @()
    },
    [ordered]@{
        id = "blueprint"
        name = "Blueprint"
        status = "official"
        definition = "NodeとLineによって関係性を可視化・操作するVertex UI思想。"
        sources = @()
    },
    [ordered]@{
        id = "component-card"
        name = "Component Card"
        status = "adopted"
        definition = "設計・依存・実装情報をカード単位で扱う概念。"
        sources = @()
    },
    [ordered]@{
        id = "fme"
        name = "Vertex FM ENGINE"
        abbreviation = "FME"
        status = "official"
        definition = "FileMaker開発支援エンジン。"
        sources = @()
    },
    [ordered]@{
        id = "via"
        name = "VIA"
        expandedName = "Voice Input Application"
        status = "adopted"
        definition = "Vertex音声入力系名称。"
        sources = @()
    },
    [ordered]@{
        id = "vertex-installer"
        name = "Vertex Installer"
        status = "provisional"
        definition = "環境検出と適応型導入を目指すInstaller構想。"
        sources = @()
    },
    [ordered]@{
        id = "index-of-indexes"
        name = "インデックスのインデックス"
        status = "research"
        definition = "探索すべきIndex / Search Space自体を先に選択する記憶探索構想。"
        sources = @("VRTX-MEM-001")
    }
)

$concepts |
    ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $dataRoot "concepts.json") -Encoding UTF8

# ------------------------------------------------------------
# sources.json
# ------------------------------------------------------------

$sources = @(
    [ordered]@{
        id = "VRTX-MEM-001"
        type = "concept_paper"
        title = "Vertex Memory Architecture"
        path = "content/research/memory-architecture.md"
        status = "canonical_source"
    },
    [ordered]@{
        id = "VRTX-LLC-001"
        type = "research_placeholder"
        title = "LLC Bias"
        path = "content/research/llc-bias.md"
        status = "definition_pending"
    },
    [ordered]@{
        id = "VRTX-PHI-001"
        type = "concept"
        title = "Vertex Design Philosophy"
        path = "content/concepts/vertex-design-philosophy.md"
        status = "canonical_source"
    }
)

$sources |
    ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $dataRoot "sources.json") -Encoding UTF8

# ------------------------------------------------------------
# relations.json
# ------------------------------------------------------------

$relations = @(
    [ordered]@{ from = "impact-db"; to = "trait"; relation = "related" },
    [ordered]@{ from = "impact-db"; to = "index-of-indexes"; relation = "related" },
    [ordered]@{ from = "impact-db"; to = "vmb"; relation = "related" },
    [ordered]@{ from = "impact-db"; to = "vcc"; relation = "related" },
    [ordered]@{ from = "impact-db"; to = "vsp"; relation = "related" },
    [ordered]@{ from = "impact-db"; to = "dnc"; relation = "related" },
    [ordered]@{ from = "blueprint"; to = "component-card"; relation = "supports" },
    [ordered]@{ from = "hyper-agent"; to = "ard"; relation = "related" }
)

$relations |
    ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $dataRoot "relations.json") -Encoding UTF8

Write-Host "Canonical content created:" -ForegroundColor Green
Write-Host "  $contentRoot"
Write-Host "Canonical data created:" -ForegroundColor Green
Write-Host "  $dataRoot"
Write-Host ""
Write-Host "PHASE 3 CANONICAL SOURCE READY" -ForegroundColor Green

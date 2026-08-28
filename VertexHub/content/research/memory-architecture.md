---
id: VRTX-MEM-001
title: Vertex Memory Architecture
status: concept_paper
kind: research
canonical: true
version: 0.1.0
review_status: self_published_unreviewed
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

これは現段階のConcept / Technical Paperであり、実装済みの仕様や
科学的に証明された一般理論として提示するものではない。

## 1. Observation

長期のHuman-AI共同作業では、概念名を提示すれば関連内容を
再構成できるにもかかわらず、自発的な関連概念列挙では
その記憶が脱落する場合がある。

この問題はKnowledge Absenceだけではなく、
Recall Failureとして分離して考える必要がある。

## 2. Impact DB

**What should be recalled now? / 現在の状況で、何を想起候補として浮上させるべきか。**

Impact DBは、現在の状況において各記憶がどれほど強く
想起候補へ浮上すべきかを扱うVertex Memory構想である。

Impactは固定的重要度ではなく、
文脈や関連性によって変化し得る値として扱う。

## 3. Trait

**What must not be forgotten? / 何を脱落させてはいけないか。**

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

Conceptual buckets:

- today
- yesterday
- day before yesterday
- this week
- last week
- older

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

追加仕様は現時点では定義しない。

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

## Revision History

- 0.1.0 / 2026-08-27 — Initial canonical public concept-paper record. Historical creation and publication dates remain unverified.

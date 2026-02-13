---
name: spec-workflow
description: |
  仕様書ワークフロー / Specification Workflow

  プロジェクトの要件定義書・設計書・タスクリストを生成するスキル。
  A skill for generating project requirements, design documents, and task lists.

  日本語トリガー:
  - 「要件定義を作って」「要件をまとめて」「仕様書を作成して」
  - 「設計書を作って」「技術設計をして」「アーキテクチャを設計して」
  - 「タスクリストを作って」「実装タスクに分解して」「tasks.mdを生成して」
  - 「仕様を全部まとめて」「フル仕様を作成」「3点セットを作って」
  - 会話で仕様が固まった後に「これを要件定義書にして」

  English triggers:
  - "Create requirements", "Generate requirements doc", "Summarize as requirements"
  - "Create design document", "Design the architecture", "Generate technical spec"
  - "Create task list", "Break down into tasks", "Generate tasks.md"
  - "Create full spec", "Generate all specs", "Create the complete specification"
  - After discussion: "Turn this into requirements", "Document this as spec"
---

# Spec Workflow - 仕様書ワークフロー

プロジェクトの仕様書（要件定義・設計書・タスクリスト）を生成するスキルです。

## 言語ルール

1. **入力言語を自動判定** → 同じ言語で出力
2. 日本語で指示 → 日本語で生成
3. English input → English output
4. 明示的な指定があれば優先（「英語で」「in Japanese」など）

## フェーズ

| フェーズ | 生成物 | トリガー例 |
|---------|--------|-----------|
| init | requirement.md | 「要件定義を作って」「Create requirements」 |
| design | design.md | 「設計書を作って」「Create design doc」 |
| tasks | tasks.md | 「タスクリストを作って」「Create task list」 |
| full | 上記3点すべて | 「仕様を全部」「Create full spec」 |

## 対話方針: AskUserQuestion 活用

**すべてのユーザー判断が必要な場面で `AskUserQuestion` ツールを使用する。**

テキストで自由に聞くのではなく、選択肢を提示して回答を得る。
これにより対話が直感的・効率的になる。

### AskUserQuestion を使う場面

| 場面 | 例 |
|------|-----|
| フェーズ判定が曖昧な時 | init / design / tasks / full の選択 |
| init対話モードの各質問 | プロジェクト種別、技術選択、スコープ等 |
| design の分岐点 | アーキテクチャ選択、DB選定等 |
| tasks の戦略選択 | systematic / agile / enterprise |
| 完了後のアクション | 「Issueに登録しますか？」「次のフェーズに進みますか？」 |

### 質問設計のルール

1. **1回の質問は1〜4問**（AskUserQuestionの制約）
2. **各質問は2〜4選択肢**（Otherは自動付与される）
3. **選択肢には必ず description を付ける**（判断材料を提供）
4. **質問ラウンド数は状況に応じて柔軟に**:
   - シンプルなプロジェクト → 1ラウンド（3-4問）で十分
   - 複雑なプロジェクト → 2-3ラウンド（前の回答を踏まえて次を調整）
5. **推奨選択肢がある場合は先頭に置き `(Recommended)` を付ける**
6. **前の回答で明確になった項目は次のラウンドで聞かない**

### テキスト質問を使う場面（AskUserQuestion を使わない）

- プロジェクト名やコンセプトなど、選択肢に落とせないオープンな質問
- ユーザーが自由記述で説明すべき背景情報
- 「他に要件はありますか？」のような追加確認

## 実行フロー

### 1. フェーズ判定

ユーザーのリクエストから実行フェーズを判定:

```
「要件定義」「requirements」→ init
「設計書」「design」「architecture」→ design
「タスク」「tasks」「実装計画」→ tasks
「全部」「フル」「3点セット」「full」「complete」→ full
```

フェーズが曖昧な場合は AskUserQuestion で確認:

```
question: "どの仕様書を生成しますか？"
options:
  - "要件定義書 (requirement.md)" → init
  - "設計書 (design.md)" → design
  - "タスクリスト (tasks.md)" → tasks
  - "3点セットすべて" → full
```

### 2. コンテキスト確認

- **会話履歴がある場合**: 会話で固まった内容を仕様書化
- **新規リクエストの場合**: 対話モードで要件を探索（AskUserQuestion活用）

### 3. フェーズ実行

各フェーズの詳細は以下を参照:
- **init**: [references/init.md](references/init.md) - 要件定義の生成
- **design**: [references/design.md](references/design.md) - 設計書の生成
- **tasks**: [references/tasks.md](references/tasks.md) - タスクリストの生成

### 4. 出力先

```
.specs/[project-name]/
├── requirement.md  (init)
├── design.md       (design)
└── tasks.md        (tasks)
```

プロジェクト名は英語ケバブケースに変換:
- 「TODOアプリ」→ `todo-app`
- 「株価分析ツール」→ `stock-analysis-tool`

## オプション

| オプション | 説明 | 対象フェーズ |
|-----------|------|-------------|
| `--quick` | 対話なしで素早く生成 | init |
| `--deep` | ソクラテス式深掘り対話 | init |
| `--personas` | 複数視点による分析・レビュー | init, design |
| `--analyze` | 既存コードを分析 | init, design, tasks |
| `--visual` | Mermaid図を強化 | design |
| `--estimate` | 見積もりとリスク評価 | tasks |
| `--hierarchy` | Epic/Story/Task階層 | tasks |

## 実行モード

### 対話モード（デフォルト）

パラメータなし、または会話からの続きの場合:
1. 必要な情報を質問で収集
2. ユーザーと対話しながら要件を明確化
3. 確認後に仕様書を生成

### クイックモード（--quick）

プロジェクト概要だけで素早く生成:
1. 概要から典型的な要件を推測
2. ベストプラクティスに基づいて生成
3. 対話なしで完成

### フルワークフロー（full）

3点セットを順番に生成:
1. requirement.md を生成
2. requirement.md を読み込み design.md を生成
3. design.md を読み込み tasks.md を生成

## 要件番号体系

生成する仕様書では以下の番号体系を使用:

- `[REQ-XXX]`: 機能要件
- `[NFR-XXX]`: 非機能要件
- `[CON-XXX]`: 制約事項
- `[ASM-XXX]`: 前提条件
- `[T-XXX]`: タスク

この番号でドキュメント間のトレーサビリティを確保。

## YAGNI原則

以下は**明示的な要件がない限り含めない**:

- 複雑な権限管理（基本認証で十分な場合）
- 高度な分析・レポート機能
- マルチテナント対応
- リアルタイム通知・更新
- 詳細な監査ログ
- 管理画面・ダッシュボード
- 非同期処理（明示的なパフォーマンス要件がない限り）

## MCP統合

高度な分析が必要な場合に活用:

| MCP | 用途 |
|-----|------|
| Sequential | 複雑な要件の体系的分析、アーキテクチャ決定支援 |
| Context7 | フレームワーク固有のベストプラクティス |
| Serena | 既存コードの意味解析、セッション管理 |
| Magic | UI/UXパターンの推奨 |

## 完了後アクション

各フェーズ完了時に AskUserQuestion で次のアクションを提案:

**init完了後:**
```
question: "要件定義書を生成しました。次のアクションは？"
options:
  - "設計書も生成する" → design フェーズへ
  - "内容を確認・修正したい" → 修正対話へ
  - "これで完了" → 終了
```

**full完了後:**
```
question: "仕様書3点セットが完了しました。"
options:
  - "GitHub Issueに登録する" → spec-to-issue スキルを実行
  - "内容を確認・修正したい" → 修正対話へ
  - "これで完了" → 終了
```

## 使用例

```
# 会話後に要件定義化
「この内容を要件定義書にまとめて」

# 新規プロジェクトの要件定義
「TODOアプリの要件定義を作って」

# 設計書の生成
「todo-appの設計書を作成して」

# タスクリストの生成
「todo-appのタスクリストを作って」

# 3点セット一括生成
「ECサイトの仕様を全部作って」

# English
"Create requirements for a todo app"
"Generate design document for todo-app"
"Create full specification for e-commerce platform"
```

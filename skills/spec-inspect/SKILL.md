---
name: spec-inspect
description: |
  Specification quality checker for spec-generator documents.

  Validates requirement.md, design.md, tasks.md for consistency, completeness, and quality.
  Detects requirement ID mismatches, missing sections, contradictions, and ambiguous expressions.

  English triggers: "inspect specs", "check specification quality", "validate requirements"
  日本語トリガー: 「仕様書を検査」「品質チェック」「仕様を検証」「spec-inspect実行」
license: MIT
---

# spec-inspect - 仕様書品質チェッカー

spec-generatorで生成された仕様書（requirement.md, design.md, tasks.md）の品質を自動的に検証し、問題をレポートします。

## 実行タイミング

- spec-generator完了後（自動提案）
- spec-to-issueでIssue登録する前
- 仕様書を更新した後

## 実行フロー

### ステップ1: プロジェクトパスの確認

ユーザーから提供されたプロジェクトパス、または現在のコンテキストから`.specs/{project-name}/`のパスを特定します。

**確認事項**:
- `.specs/{project-name}/requirement.md` が存在するか
- `.specs/{project-name}/design.md` が存在するか
- `.specs/{project-name}/tasks.md` が存在するか

ファイルが存在しない場合はエラーメッセージを表示して終了。

### ステップ2: 仕様書の読み込み

Readツールを使用して3つの仕様書を読み込みます。

```
requirement_content = Read(".specs/{project-name}/requirement.md")
design_content = Read(".specs/{project-name}/design.md")
tasks_content = Read(".specs/{project-name}/tasks.md")
```

### ステップ3: 品質チェックの実行

以下のチェックを順次実行します。検出した問題はissuesリストに追加します。

#### チェック1: 要件ID整合性検証 [CRITICAL]

**目的**: requirement.mdで定義されている要件IDが、design.mdとtasks.mdで正しく参照されているか検証

**手順**:
1. requirement.mdから要件IDを抽出（正規表現: `\[(REQ|NFR|CON|ASM|T)-\d{3,}\]`）
2. design.mdから参照されている要件IDを抽出
3. tasks.mdから参照されている要件IDを抽出

**検出パターン**:
- **[CRITICAL]** design.mdまたはtasks.mdで参照されているが、requirement.mdに存在しない要件ID
  ```
  ID: CRITICAL-{連番}
  Title: "要件ID {req_id} が存在しない"
  File: design.md または tasks.md
  Line: {該当行番号}
  Description: "{req_id} は {file} で参照されているが requirement.md に定義されていません"
  Suggestion: "requirement.md に {req_id} を追加するか、参照を修正してください"
  ```

- **[INFO]** requirement.mdに定義されているが、どこからも参照されていない要件ID
  ```
  ID: INFO-{連番}
  Title: "要件ID {req_id} が未参照"
  File: requirement.md
  Line: {該当行番号}
  Description: "{req_id} はどの設計・タスクにも紐づいていません"
  Suggestion: "この要件は実装不要ですか？不要な場合は削除を検討してください"
  ```

#### チェック2: 必須セクション検証 [WARNING]

**目的**: 各仕様書が標準的な構造を持っているか確認

**必須セクション定義**:
- **requirement.md**: 概要、機能要件、非機能要件、制約事項、前提条件
- **design.md**: アーキテクチャ概要、技術スタック、データモデル
- **tasks.md**: タスク一覧、優先順位

**手順**:
1. 各ファイルのMarkdown見出し（# または ##）を抽出
2. 必須セクションが存在するか確認（部分一致、大文字小文字を区別しない）

**検出パターン**:
- **[WARNING]** 必須セクションが欠けている
  ```
  ID: WARNING-{連番}
  Title: "必須セクション '{section_name}' が欠如"
  File: {filename}
  Line: 1
  Description: "{filename} には '{section_name}' セクションが必要です"
  Suggestion: "'{section_name}' セクションを追加してください"
  ```

#### チェック3: 矛盾検出 [WARNING]

**目的**: 仕様書間で矛盾する記述を検出

**検出パターン例**:
- 技術スタックの不一致（例：requirementではPostgreSQL、designではMySQL）
- 数値の不一致（例：requirementで「100ユーザー」、designで「1000ユーザー」）
- APIエンドポイントの不一致

**手順**:
1. requirement.mdから技術的な固有名詞を抽出（データベース名、ライブラリ名等）
2. design.mdで同じ概念が異なる名前で言及されていないかチェック
3. 数値データの不一致を検出

**検出パターン**:
- **[WARNING]** 矛盾する記述
  ```
  ID: WARNING-{連番}
  Title: "矛盾: {概念名}"
  File: requirement.md, design.md
  Line: {該当行番号}
  Description: "requirement.md では {value1}、design.md では {value2} と記載されています"
  Suggestion: "どちらかに統一してください"
  ```

#### チェック4: 曖昧な表現の検出 [INFO]

**目的**: 実装に必要な情報が欠けている曖昧な表現を検出

**検出キーワード**:
- "適切に"、"できる限り"、"なるべく"、"ある程度"
- "高速に"、"大量の"、"多くの"（数値基準なし）
- "検討する"、"考慮する"、"予定"（確定していない）

**手順**:
1. 3つの仕様書全体で曖昧なキーワードを検索（Grepツール使用）
2. 該当箇所をリスト化

**検出パターン**:
- **[INFO]** 曖昧な表現
  ```
  ID: INFO-{連番}
  Title: "曖昧な表現: '{keyword}'"
  File: {filename}
  Line: {該当行番号}
  Description: "'{context}' という表現は実装者によって解釈が異なります"
  Suggestion: "具体的な数値・基準を明記してください"
  ```

### ステップ4: 検査結果のサマリー生成

検出した問題を重要度別に集計:
- Critical: {count}
- Warning: {count}
- Info: {count}

### ステップ5: レポート生成

`.specs/{project-name}/inspection-report.md` にMarkdown形式のレポートを生成します。

**テンプレート**:
```markdown
# spec-inspect レポート - {project_name}

## 検査サマリー
- 検査日時: {YYYY-MM-DD HH:MM:SS}
- 検査対象: requirement.md, design.md, tasks.md
- 検出問題数: **Critical: {X}, Warning: {Y}, Info: {Z}**

## ⛔ Critical Issues (実装ブロッカー)

{Critical問題が0件の場合は「なし」と表示}

### [{issue.id}] {issue.title}
- **ファイル**: `{issue.file}:{issue.line}`
- **詳細**: {issue.description}
- **修正提案**: {issue.suggestion}

## ⚠️ Warnings (要確認事項)

{Warning問題が0件の場合は「なし」と表示}

### [{issue.id}] {issue.title}
- **ファイル**: `{issue.file}:{issue.line}`
- **詳細**: {issue.description}
- **修正提案**: {issue.suggestion}

## ℹ️ Info (改善推奨)

{Info問題が0件の場合は「なし」と表示}

### [{issue.id}] {issue.title}
- **ファイル**: `{issue.file}:{issue.line}`
- **詳細**: {issue.description}
- **修正提案**: {issue.suggestion}
```

レポート生成後、Writeツールで保存:
```
Write(".specs/{project-name}/inspection-report.md", report_content)
```

### ステップ6: コンソール出力

ユーザーに分かりやすい形式でサマリーを表示:

```
✅ spec-inspect 完了

📊 検査結果:
  ⛔ Critical: {count} 件
  ⚠️  Warning: {count} 件
  ℹ️  Info: {count} 件

{Critical問題が1件以上ある場合}
❌ Critical問題が見つかりました。実装前に修正が必要です。

{Critical問題が0件の場合}
✅ Critical問題はありません。

📄 詳細レポート: .specs/{project-name}/inspection-report.md
```

### ステップ7: 次のアクション提案（ワークフロー連携）

**spec-generatorから呼び出された場合**:

検査結果に応じてAskUserQuestionで次のアクションを質問します。

#### パターン1: Critical問題あり

```yaml
AskUserQuestion:
  questions:
    - question: "Critical問題が {count} 件見つかりました。仕様書の修正が必要です。次のアクションを選択してください。"
      header: "次のアクション"
      multiSelect: false
      options:
        - label: "修正してから再実行"
          description: "仕様書を修正後、再度spec-inspectを実行します"
        - label: "スキップしてIssue登録"
          description: "問題を承知の上でspec-to-issueでIssue登録を続行します"
        - label: "キャンセル"
          description: "ここで終了します"
```

**ユーザー選択に応じた処理**:
- "修正してから再実行" → 終了（ユーザーが修正後に再実行）
- "スキップしてIssue登録" → spec-to-issueスキルを起動
- "キャンセル" → 終了

#### パターン2: Warning/Infoのみ

```yaml
AskUserQuestion:
  questions:
    - question: "Warning が {count} 件見つかりました。このままIssue登録しますか？"
      header: "次のアクション"
      multiSelect: false
      options:
        - label: "Issue登録する"
          description: "spec-to-issueでGitHub Issueを登録します"
        - label: "修正してから再実行"
          description: "仕様書を修正後、再度spec-inspectを実行します"
        - label: "キャンセル"
          description: "ここで終了します"
```

**ユーザー選択に応じた処理**:
- "Issue登録する" → spec-to-issueスキルを起動
- "修正してから再実行" → 終了
- "キャンセル" → 終了

#### パターン3: 問題なし

```yaml
AskUserQuestion:
  questions:
    - question: "品質チェック完了。問題は見つかりませんでした。Issue登録しますか？"
      header: "次のアクション"
      multiSelect: false
      options:
        - label: "Issue登録する"
          description: "spec-to-issueでGitHub Issueを登録します"
        - label: "キャンセル"
          description: "ここで終了します"
```

**ユーザー選択に応じた処理**:
- "Issue登録する" → spec-to-issueスキルを起動
- "キャンセル" → 終了

### ステップ8: spec-to-issueへの連携データ保存

次のスキルで使用できるように、検査結果を一時ファイルに保存:

```json
{
  "project_path": ".specs/{project-name}",
  "project_name": "{project-name}",
  "critical_count": {count},
  "warning_count": {count},
  "info_count": {count},
  "report_path": ".specs/{project-name}/inspection-report.md",
  "timestamp": "{ISO 8601}"
}
```

Writeツールで保存:
```
Write(".specs/{project-name}/.inspection_result.json", json_content)
```

## エラーハンドリング

### ファイルが存在しない

```
❌ エラー: 必須ファイルが見つかりません
  見つからないファイル: {missing_files}

📍 確認してください:
  - プロジェクトパスが正しいか: .specs/{project-name}/
  - spec-generatorで仕様書を生成済みか
```

### ファイル読み取りエラー

```
❌ エラー: ファイルの読み取りに失敗しました
  ファイル: {filename}
  エラー: {error_message}
```

### 要件ID抽出エラー

正規表現マッチングでエラーが発生した場合も処理を続行し、警告を表示:

```
⚠️  警告: 要件ID抽出で一部エラーが発生しました
  続行可能な範囲で検査を実行します
```

## 実装上の注意点

### 効率的な実行

- **大きなファイル**: requirement.mdやdesign.mdが非常に長い場合、Read操作を最小限にする
- **正規表現の最適化**: Grepツールを活用して効率的に検索
- **段階的な出力**: 各チェック完了時に進捗を表示

### 精度の向上

- **部分一致の活用**: セクション名は完全一致ではなく部分一致で検索（"機能要件" と "## 機能要件" の両方にマッチ）
- **大文字小文字**: 日本語・英語ともに柔軟にマッチング
- **コンテキスト考慮**: 矛盾検出では、単語の出現だけでなく文脈を考慮

### ユーザー体験

- **明確なメッセージ**: エラーメッセージは具体的で実行可能な修正提案を含む
- **視覚的な区別**: emoji（⛔⚠️ℹ️✅❌📄📊）を使って視認性を向上
- **進捗表示**: 長時間かかる処理では進捗を表示

## 制約事項

- 日本語と英語の仕様書に対応（自然言語処理の精度には限界あり）
- Markdown形式の仕様書のみサポート
- spec-generatorの出力形式に依存

## 成功基準

- 要件ID参照エラーの検出率: 100%
- 必須セクション欠如の検出率: 100%
- 矛盾検出の精度: ベストエフォート（LLMの推論能力に依存）
- 処理時間: 3つの仕様書合計3000行以下で30秒以内

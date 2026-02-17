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

- **[WARNING]** 要件カバレッジが不十分（[NFR-XXX]含む全要件IDのdesign.md参照率を算出し、100%未満の場合に警告）
  ```
  ID: WARNING-{連番}
  Title: "要件カバレッジ: {covered}/{total} ({percentage}%)"
  Description: "以下の要件がdesign.mdで言及されていません: {未カバー要件リスト}"
  Suggestion: "design.mdに各要件への対応方針を記載してください"
  ```

#### チェック2: 必須セクション検証 [WARNING]

**目的**: 各仕様書が標準的な構造を持っているか確認

**必須セクション定義**:
- **requirement.md**: 概要、機能要件、非機能要件、制約事項、前提条件
- **design.md**: アーキテクチャ概要、技術スタック、データモデル、API設計（該当する場合）、セキュリティ設計
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
- design.mdで設計されたコンポーネントがtasks.mdの実装予定から漏れている

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

#### チェック5: 用語の一貫性チェック [WARNING] → [REQ-003]

**目的**: 仕様書全体で用語が一貫して使用されているか確認

**検出パターン**:
- 同じ概念を異なる用語で表現（例：「ユーザー」と「利用者」、「削除」と「除去」）
- 略語の不統一（例：「DB」と「データベース」が混在）
- 用語集（存在する場合）で定義された用語と異なる表現の使用

**手順**:
1. 3つの仕様書から主要な名詞・概念を抽出
2. 同義語・類義語のペアを検出
3. 用語集セクションがあれば、それと照合

**出力**: `WARNING-{連番}` 「用語の揺れ: '{term1}' と '{term2}'」+ 統一推奨

#### チェック6: 設計の実装計画検証 [WARNING] → [REQ-005]

**目的**: design.mdの設計内容がtasks.mdで実装計画されているか確認

**検出パターン**:
- 設計されたコンポーネント・モジュールに対応するタスクが存在しない
- DBスキーマ設計に対応するマイグレーションタスクがない
- API設計に対応する実装タスクがない

**手順**:
1. design.mdから主要コンポーネント名・モジュール名を抽出
2. tasks.mdで各コンポーネントに対応するタスクが存在するか確認
3. 未カバーの設計要素をリスト化

**出力**: `WARNING-{連番}` 「設計要素 '{component}' に対応するタスクが未定義」

#### チェック7: 依存関係の検証 [WARNING] → [REQ-006]

**目的**: タスク間の依存関係が論理的に正しいか検証

**検出パターン**:
- 循環依存（タスクAがBに依存、BがAに依存）
- 前提タスク未定義（存在しないタスクへの依存参照）
- 明らかに順序が逆の依存関係（例：テストタスクが実装タスクより先）

**手順**:
1. tasks.mdからタスク間の依存関係を抽出
2. 依存グラフを構築し循環を検出
3. 論理的に不自然な順序を指摘

**出力**: `WARNING-{連番}` 「循環依存: {taskA} ⇄ {taskB}」または「依存順序が不自然」

#### チェック8: 実装不可能な要件の警告 [WARNING] → [REQ-008]

**目的**: 技術的に実装が困難、または矛盾する要件を検出

**検出パターン**:
- 相反する非機能要件（例：「レスポンス1ms以内」と「全データ暗号化」の両立困難）
- 技術スタックでは実現困難な機能
- リソース制約を超える要件（例：無制限ストレージ、ゼロダウンタイム等の非現実的要件）

**出力**: `WARNING-{連番}` 「実現困難な可能性: {要件内容}」+ 代替案の提示

#### チェック9: 要件漏れの検出 [WARNING] → [REQ-010]

**目的**: 明らかに必要だが記述されていない要件を検出

**検出パターン**:
- 認証機能あり → セキュリティ要件がない
- DB使用 → バックアップ・リカバリ要件がない
- 外部API連携 → エラーハンドリング・リトライ要件がない
- ファイルアップロード → サイズ制限・形式制限要件がない
- ユーザーデータ保存 → プライバシー・データ保護要件がない

**手順**:
1. requirement.md/design.mdから機能の特徴を抽出
2. 上記パターンに照合し、対応する要件の有無を確認

**出力**: `WARNING-{連番}` 「要件漏れの可能性: {機能}に対する{要件種別}が未定義」

#### チェック10: 命名規則の一貫性チェック [INFO] → [REQ-014]

**目的**: 仕様書内の命名規則が一貫しているか確認

**検出パターン**:
- ケバブケース/キャメルケース/スネークケースの混在
- 同一文脈での命名揺れ（例：user_id vs userId vs userID）
- 定数・テーブル名・コンポーネント名の命名パターン違反

**手順**:
1. design.md/tasks.mdからコード関連の名前（変数名、テーブル名、API名等）を抽出
2. 命名パターンの統計を取り、少数派を検出

**出力**: `INFO-{連番}` 「命名規則の不統一: {pattern1}({count1}件) vs {pattern2}({count2}件)」

#### チェック11: ディレクトリ配置ルールの一貫性チェック [INFO] → [REQ-015]

**目的**: 仕様書で定義されたディレクトリ構造・配置ルールが一貫しているか確認

**検出パターン**:
- 類似コンポーネントの配置場所の不統一（例：`src/features/A/` vs `src/components/B/`）
- テストファイル配置の不統一（`tests/` vs `__tests__/` 混在）
- 設定ファイル配置の散在

**出力**: `INFO-{連番}` 「ディレクトリ配置の不統一: {パターン説明}」

#### チェック12: コンポーネント再発明の検出 [INFO] → [REQ-016]

**目的**: 既存のライブラリで実現可能な機能を再実装していないか検出

**検出パターン**:
- design.mdの技術スタックに含まれるライブラリの機能を独自実装
  - 例：date-fns導入済みなのに日付処理を自作
  - 例：Zod導入済みなのにバリデーションを独自実装
- 標準ライブラリで提供される機能の再実装

**手順**:
1. design.mdの「技術スタック」セクションからライブラリ一覧を抽出
2. tasks.mdの実装タスクと照合し、ライブラリ機能と重複する実装を検出

**出力**: `INFO-{連番}` 「再発明の可能性: {タスク内容} は {ライブラリ名} で実現可能」

#### チェック13: プロジェクトルール遵守チェック [WARNING] → [REQ-017]

**目的**: CLAUDE.md/AGENTS.md等に記載されたプロジェクト固有ルールに仕様書が違反していないか確認

**手順**:
1. プロジェクトルートの `CLAUDE.md`、`AGENTS.md`、`.claude/` を読み込み
2. コーディング規約・禁止パターン・必須パターンを抽出
3. design.md/tasks.mdの記述と照合

**検出例**:
- 「TypeScript strict mode必須」→ design.mdで言及なし
- 「JWT認証必須」→ design.mdで別方式を採用
- 「console.log禁止」→ tasks.mdでconsole.logを使用する記述

**出力**: `WARNING-{連番}` 「プロジェクトルール違反: {ルール内容} に対して {違反箇所}」

#### チェック14: API/UI命名規則の一貫性チェック [WARNING] → [REQ-021]

**目的**: API・UI命名規則の一貫性を検証（Webアプリ/API関連の仕様書の場合）

**検出パターン**:
- REST APIリソース名の単数形/複数形不統一（`/user/:id` vs `/comments`）
- 非RESTfulな動詞パス（`/getUsers` → `/users` (GET) が推奨）
- パスのケース不統一（`/user-profile` vs `/userProfile`）
- パスパラメータ形式の不統一（`:id` vs `{id}`）
- 画面コンポーネント名の接尾辞不統一（`Screen` vs `Page`）

**手順**:
1. design.mdの「API設計」セクションからエンドポイント一覧を抽出
2. tasks.mdから画面名・ルーティングを抽出
3. 多数派パターンを「推奨」として少数派を指摘

**出力**: `WARNING-{連番}` 「API命名規則の不統一: {詳細}」+ 統一提案

#### チェック15: ドキュメント更新必要性の分析 [INFO] → [REQ-024]

**目的**: 仕様書の内容に基づき、既存ドキュメントの更新が必要かどうかを分析

**対象ドキュメント**:
- README.md、CLAUDE.md、AGENTS.md
- CLAUDE.mdで指定されたドキュメントディレクトリ（例：`docs/`）内のファイル

**手順**:
1. プロジェクトルートのREADME.md、CLAUDE.md、AGENTS.mdの存在を確認
2. CLAUDE.mdを解析し、ドキュメントディレクトリの指定があれば走査
3. 仕様書の内容と照合:
   - 新機能 → README.mdの機能一覧に未記載
   - 新APIエンドポイント → API仕様書に未記載
   - 技術スタック変更 → セットアップガイド未更新
   - コーディング規約追加 → CLAUDE.md/AGENTS.md未更新
4. 更新が必要な箇所をDOC-XXXタスクとして提案

**出力**:
- `INFO-{連番}` 「ドキュメント更新が必要: {ファイル名} - {理由}」
- 検出結果を tasks.md への追加タスクとして提案:
  ```
  ### ドキュメント更新タスク（自動検出）
  - [ ] DOC-001: {ファイル名}の{セクション}を更新 ({理由})
  ```

### ステップ4: 検査結果のサマリー生成

検出した問題を重要度別に集計:
- Critical: {count}
- Warning: {count}
- Info: {count}

### ステップ5: レポート生成

`.specs/{project-name}/inspection-report.md` にMarkdown形式のレポートを生成します。

**テンプレート**: `# spec-inspect レポート - {project_name}` → 検査サマリー（日時、対象、検出数） → 重要度別セクション（⛔ Critical / ⚠️ Warnings / ℹ️ Info）。各issue: `### [{issue.id}] {issue.title}` + ファイル:行番号、詳細、修正提案。0件の場合は「なし」と表示。

Writeツールで `.specs/{project-name}/inspection-report.md` に保存。

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

検査結果に応じてAskUserQuestionで次のアクションを質問（header: "次のアクション", multiSelect: false）:

| 検査結果 | 質問文 | 選択肢 |
|---------|-------|--------|
| Critical問題あり | 「Critical問題が {count} 件。修正が必要です」 | 修正してから再実行 / スキップしてIssue登録 / キャンセル |
| Warning/Infoのみ | 「Warning が {count} 件。このままIssue登録しますか？」 | Issue登録する / 修正してから再実行 / キャンセル |
| 問題なし | 「品質チェック完了。Issue登録しますか？」 | Issue登録する / キャンセル |

**ユーザー選択に応じた処理**:
- 「Issue登録する」/「スキップしてIssue登録」 → spec-to-issueスキルを起動
- 「修正してから再実行」 → 終了（ユーザーが修正後に再実行）
- 「キャンセル」 → 終了

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

- **ファイル不在**: `❌ エラー: 必須ファイルが見つかりません` + 見つからないファイル名、パス確認指示
- **読み取りエラー**: `❌ エラー: ファイルの読み取りに失敗しました` + ファイル名、エラー内容
- **要件ID抽出エラー**: 処理を続行し `⚠️ 警告: 要件ID抽出で一部エラーが発生しました` を表示

## 実装上の注意点

- **効率**: 大きなファイルはRead操作を最小限に。Grepツールで効率的に検索。各チェック完了時に進捗表示
- **精度**: セクション名は部分一致で検索。矛盾検出では文脈を考慮。日本語・英語ともに柔軟にマッチング
- **UX**: エラーは具体的で実行可能な修正提案を含む。emoji（⛔⚠️ℹ️✅❌📄📊）で視認性向上

## 制約事項

- 日本語と英語の仕様書に対応（自然言語処理の精度には限界あり）
- Markdown形式の仕様書のみサポート
- spec-generatorの出力形式に依存

## 成功基準

- 要件ID参照エラーの検出率: 100%
- 必須セクション欠如の検出率: 100%
- 矛盾検出の精度: ベストエフォート（LLMの推論能力に依存）
- 処理時間: 3つの仕様書合計3000行以下で30秒以内

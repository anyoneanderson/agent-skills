# spec-implement ガイド

## 概要

spec-implement は、プロジェクト固有の設定ファイルを読み込み、構造化された仕様書からタスクを実行することで、実装からPR作成までのワークフローを自動化します。

実行エンジンとして以下を行います:
- ワークフローファイル（`issue-to-pr-workflow.md`）を開発プレイブックとして読み込む
- コーディングルールファイル（`coding-rules.md`）を品質ゲートとして強制適用する
- プロジェクト指示ファイル（`CLAUDE.md`, `AGENTS.md`）をルール補完として読み込む
- `.specs/{feature}/tasks.md` のチェックボックスで進捗を追跡する
- 完了後にPRを作成する

## 全体実行フロー

```
1. 初期チェック
   ├── 作業ディレクトリの確認（gitリポジトリ、gh CLI利用可能）
   ├── オプション解析（--resume, --issue, --spec, --dry-run）
   └── specディレクトリの特定（.specs/{feature}/）

2. ファイル読み込み（柔軟なパス探索）
   ├── issue-to-pr-workflow.md（プレイブック）
   │   └── 探索順: docs/development/ → docs/ → find コマンド
   ├── coding-rules.md（品質ルール）
   │   └── 探索順: docs/development/ → docs/ → find コマンド
   ├── CLAUDE.md, src/CLAUDE.md, test/CLAUDE.md, AGENTS.md（プロジェクト指示）
   ├── .specs/{feature}/requirement.md
   ├── .specs/{feature}/design.md
   └── .specs/{feature}/tasks.md

3. Issue分析
   ├── gh issue view {number} でコンテキスト取得
   └── 要件、ラベル、アサイニーの抽出

4. ブランチ作成 🚨 ブロッキングゲート
   ├── ワークフローからベースブランチを動的検出（デフォルト: main）
   ├── ワークフローの命名規則に従う（デフォルト: feature/issue-{N}-{desc}）
   └── main/master/develop上での実装を禁止（検証必須）

5. タスクループ
   ├── エージェントロール検出（ワークフローに定義がある場合）
   ├── tasks.mdから次の未完了タスクを読み取り
   ├── design.mdを参照して実装の詳細を確認
   ├── タスクを実装
   ├── 🔍 実装レビュー（design.md + coding-rules.md + CLAUDE.md照合）
   ├── テスト実装（該当する場合）
   ├── 🔍 テストレビュー（カバレッジ + パターン確認）
   ├── 品質チェック実行
   ├── tasks.mdのチェックボックスを更新（- [ ] → - [x]）
   └── 進捗をコミット（プロジェクトのコミット規則に従う）

6. 最終品質ゲート
   ├── 全テスト実行（ワークフローから）
   ├── lint/typecheck実行（ワークフローから）
   ├── 全[MUST]ルールの通過を確認
   └── CLAUDE.md 条件付きルールの通過を確認

7. PR作成
   ├── ワークフローのPRテンプレートに従う
   ├── --base {base_branch}（ワークフローから動的決定）
   ├── Issueにリンク（Closes #{N}）
   └── CI監視（ワークフローに記述がある場合）
```

## ファイル読み込み

### ワークフローファイルの探索

ワークフローファイルは以下の順序で探索します:
1. `docs/development/issue-to-pr-workflow.md`
2. `docs/issue-to-pr-workflow.md`
3. `find . -name "issue-to-pr-workflow.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" | head -1`

最初に見つかったファイルを使用します。

### コーディングルールファイルの探索

コーディングルールファイルは以下の順序で探索します:
1. `docs/development/coding-rules.md`
2. `docs/coding-rules.md`
3. `find . -name "coding-rules.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" | head -1`

最初に見つかったファイルを使用します。

### プロジェクト指示ファイルの読み込み

以下のファイルが存在すれば全て読み込みます:
- `CLAUDE.md`（プロジェクトルート）
- `src/CLAUDE.md`（ソースレベルルール）
- `test/CLAUDE.md`（テストレベルルール）
- `AGENTS.md`（エージェント定義）

これらのファイルに含まれる条件付きルール（IF-THENパターン、条件付き指示、環境固有の制約）、環境制約、コーディング規約は `[MUST]` ルールと同等の強制度で適用されます。

### ワークフローファイルの使われ方

ワークフローファイルは、spec-implement がセクションごとに読んで従うプロジェクト固有のプレイブックです。通常以下のセクションを含みます:

| セクション | spec-implement が抽出する内容 |
|-----------|-------------------------------|
| Development Environment | 環境セットアップコマンド、コンテナ起動コマンド |
| Issue Analysis and Setup | ブランチ命名規則、Issue読み取り手順 |
| Branch Strategy / PR Target | **ベースブランチ**（develop, mainなど）、PRターゲット |
| Phased Implementation | 実装の順序、コーディングガイドライン |
| Agent Roles / Sub-agents | エージェントロール定義（存在する場合） |
| Testing | テストコマンド、カバレッジ閾値 |
| PR Creation and Quality Gates | PR前チェック、PR本文テンプレート |
| CI/CD Monitoring | CI確認コマンド |
| Commit Message Rules | コミットメッセージの形式、言語要件 |

**重要な原則**: spec-implement はプロジェクト固有のコマンドやブランチ名をハードコードしません。すべてワークフローファイルから読み取ります。

### ワークフローファイルが存在しない場合

探索した全パスにワークフローファイルが存在しない場合:
1. 警告メッセージを表示
2. spec-workflow-init を実行してワークフローを生成するか確認
3. 辞退された場合、内蔵のミニマルフローを使用:
   - Issue分析 → ブランチ作成 → タスク実装 → テスト実行 → PR作成
   - ベースブランチは `main` をデフォルトとして使用

## コーディングルールの読み込み

### ルールファイルの使われ方

ルールファイルは、3段階の強制度を持つプロジェクト固有の品質基準を定義します:

| 強制度 | 違反時の動作 | 例 |
|--------|-------------|-----|
| `[MUST]` | エラー — 修正するまで続行不可 | 「すべての関数に戻り値の型を記述すること」 |
| `[SHOULD]` | 警告 — 記録して続行 | 「letよりconstを優先すること」 |
| `[MAY]` | 情報 — ログ記録のみ | 「JSDocコメントの追加を検討すること」 |

ルールは4つのタイミングでチェックされます:
1. **タスク開始前**: タスクカテゴリに関連するルールを確認
2. **コード生成時**: 生成コードを`[MUST]`ルールに照らして自己チェック
3. **タスク完了時**: 完了条件 + ルール準拠を確認
4. **最終ゲート**: 全変更に対して全`[MUST]`ルールをチェック

### ルールファイルが存在しない場合

探索した全パスにルールファイルが存在しない場合:
1. 警告メッセージを表示
2. spec-rules-init を実行してルールを生成するか確認
3. 辞退された場合、ルール強制なしで実装を続行
4. CLAUDE.md や AGENTS.md が存在すればフォールバック参照として使用

## ブランチ作成（ブロッキングゲート）

### 🚨 Feature ブランチは必須

実装は `main`、`master`、`develop` ブランチ上で直接行ってはなりません。このゲートはスキップできません。

ワークフローファイルに「保護ブランチ」や「ブランチ保護」セクションが定義されている場合は、デフォルトの代わりにそのリストを使用します。

### ベースブランチの動的決定

1. ワークフローファイルから「ブランチ戦略」「ベースブランチ」「PRターゲット」を検索
2. `develop` や `main` 等の指定があれば、それを `{base_branch}` として使用
3. 指定がなければ `main` をデフォルトとして使用

### ブランチ作成後の検証

```bash
current_branch=$(git branch --show-current)
if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ] || [ "$current_branch" = "develop" ]; then
  echo "🚨 エラー: 保護されたブランチ上では実装できません: $current_branch"
  exit 1
fi
```

この検証に失敗した場合、タスクループに進むことはできません。

## エージェントロール検出

ワークフローファイルに「Agent Roles」「Sub-agents」「エージェントロール」セクションがある場合:

1. ロール定義を解析（例: implementer, reviewer, tester）
2. ユーザーに並列実行の選択肢を提示
3. サブエージェント選択時: Task tool でロール定義に基づいてエージェントを起動
4. シングル選択時: 順次実行で続行

### ワークフローテーブル形式の解析

ワークフローファイルでは通常、2つのMarkdownテーブルでエージェントロールを定義します:

**ロール割り当てテーブル** — ロールをエージェント名と責務にマッピング:

```markdown
| Role | Agent | Responsibility |
|------|-------|---------------|
| Implementer | workflow-implementer | Write implementation code following coding-rules.md |
| Reviewer | workflow-reviewer | Code review against coding-rules.md standards |
| Tester | workflow-tester | Write and run tests, verify coverage |
```

**並列実行戦略テーブル** — 各フェーズでアクティブなロールを定義:

```markdown
| Phase | Implementer | Tester | Reviewer |
|-------|-------------|--------|----------|
| Analysis | Design review | Test plan | - |
| Implementation | Write code | Write tests | - |
| Review | - | - | Review code + tests |
| Quality Gate | - | Run all tests | Final check |
```

### テーブルからTask Toolパラメータへのマッピング

Task tool でサブエージェントを起動する際:

1. **エージェント名**: ロール割り当てテーブルの `Agent` 列の値を Task tool の `name` パラメータとして使用（例: `name: "workflow-implementer"`）
2. **エージェントの責務**: `Responsibility` 列の値をタスクプロンプトのコンテキストとして使用
3. **フェーズ実行順序**: 並列実行戦略テーブルを行ごとに上から順に実行:
   - `-` のセルはそのフェーズでロールがアイドル状態であることを示す
   - `-` 以外のセルはそのフェーズでのロールのアクションを記述
   - 同じフェーズ行でアクティブなロールは並列実行可能
   - フェーズは上から下に順次実行

### 例: Task Tool の呼び出し

「Implementation」フェーズでImplementerとTesterが両方アクティブな場合:

```
# 並列で起動:
Task(name: "workflow-implementer", prompt: "Write implementation code following coding-rules.md...")
Task(name: "workflow-tester", prompt: "Write tests following project test patterns...")

## tasks.md の状態管理

### チェックボックスの形式

tasks.md は標準的なMarkdownチェックボックスで状態を追跡します:

```markdown
### Phase 1: セットアップ
- [ ] T001: プロジェクト構造の作成     ← 未チェック = 未完了
- [x] T002: データベースの初期化       ← チェック済み = 完了

### Phase 2: 実装
- [ ] T003: ユーザーモデルの実装
  - 完了条件:
    - [x] モデルクラスの作成           ← サブ項目も追跡
    - [ ] バリデーションルールの追加
    - [ ] ユニットテストの作成
```

### チェックボックスの更新方法

1. タスク開始時: すべての完了条件を満たすまでトップレベルのチェックボックスは `- [ ]` のまま
2. サブ基準の完了時: 個別のサブチェックボックスを `- [x]` に更新
3. 全基準通過時: トップレベルのチェックボックスを `- [x]` に更新
4. 更新後: 変更をコミットして進捗を保存

### コミット戦略

各タスク完了後、プロジェクトのコミット規則に従ってコミットします:

1. coding-rules.md または CLAUDE.md からコミットメッセージ規則を抽出（形式、言語）
2. 抽出した規則に従ってコミットメッセージを生成
3. 規則が見つからない場合のデフォルト: `feat: {task-id} complete — {brief description}`

```
git add .specs/{feature}/tasks.md [+ 実装ファイル]
git commit -m "{プロジェクト規則に従ったコミットメッセージ}"
```

これにより、エージェントが予期せず停止しても進捗が保存されます。

## レビューフェーズ

### 実装レビュー（各タスク完了時）

タスクの実装完了後、PRに進む前に以下をセルフレビューします:
- design.md の仕様との整合性
- coding-rules.md の `[MUST]` ルール違反がないこと
- CLAUDE.md の条件付きルール違反がないこと
- 問題が見つかった場合は修正してから次に進む

### テストレビュー（テスト実装後）

テストの実装完了後:
- テストカバレッジが完了条件を満たしていること
- テストパターンがプロジェクト規約に合致していること
- 問題が見つかった場合は修正してから次に進む

## --resume の動作

`--resume` オプションは、最後の未完了タスクからの続行を可能にします:

```
1. tasks.md を読み込む
2. すべてのトップレベルチェックボックスをスキャン
3. 最初の未チェックタスク（- [ ]）を特定
4. サブ基準を確認:
   - すべて未チェック → タスクを最初から開始
   - 一部チェック済み → 最初の未チェック基準から続行
5. 残りのタスクを順番に実行
```

### 再開シナリオ

| シナリオ | 動作 |
|----------|------|
| 全タスクチェック済み | 「全タスク完了」と報告し、最終ゲートへ進む |
| 最初のタスクが未チェック | 最初から開始 |
| 途中のタスクが未チェック | 完了済みタスクをスキップし、未チェックから続行 |
| サブ基準が一部完了 | タスク内の未チェック基準から再開 |

## トラブルシューティング

### よくある問題

**「workflow.md が見つかりません」**
- `docs/development/` と `docs/` の両方を確認したか確認
- `spec-workflow-init` を実行してワークフローファイルを生成
- または内蔵のミニマルフローで続行

**「coding-rules.md が見つかりません」**
- `docs/development/` と `docs/` の両方を確認したか確認
- `spec-rules-init` を実行してルールファイルを生成
- またはルール強制なしで続行

**「tasks.md が見つかりません」**
- この機能に対して spec-generator を実行済みか確認
- または `--issue` を使用してミニマルモード（Issueのみ）で実行

**「gh CLIが認証されていません」**
- `gh auth login` を実行して認証
- リポジトリへの書き込み権限があることを確認

**保護ブランチ上で実装しようとしている**
- feature ブランチを作成してから再実行
- `--resume` を使用する場合も、正しいブランチ上にいることを確認

**タスクループが停滞しているように見える**
- `[MUST]` ルール違反が進行をブロックしていないか確認
- エラーメッセージを確認して違反を修正
- 修正後に `--resume` で続行

**エージェントがタスクの途中で停止した**
- `--resume` を使用して最後のチェックポイントから続行
- git log で最後にコミットされた進捗を確認
- tasks.md のチェックボックスが実行停止位置を正確に示す

### 安全機構

spec-implement には以下の安全装置が含まれています:
- 🚨 保護ブランチ（main/master/develop）上での実装をブロック
- force push を行わない
- main/master への直接 push を行わない
- テスト失敗時のPR作成をブロック
- 大規模なコード削除前にユーザー確認を求める
- 各タスク完了後に進捗をコミットして復旧可能性を確保

## `--dry-run` 出力フォーマット

`--dry-run` が指定された場合、以下を表示して変更を加えずに終了します:

```
=== spec-implement Dry Run ===

📁 検出ファイル:
  ワークフロー:    {パス or "not found"}
  コーディングルール: {パス or "not found"}
  CLAUDE.md:     {検出ファイル一覧}
  Specディレクトリ:  {.specs/{feature}/ パス}

🌿 ブランチ戦略:
  ベースブランチ:   {base_branch}
  Featureブランチ:  feature/issue-{N}-{description}
  PRターゲット:    {base_branch}

📋 タスク ({N} 合計, {M} 完了, {K} 残り):
  {各タスクのステータスを表示}

🔍 品質ゲート:
  [MUST] ルール:   {count} 件検出
  テストコマンド:   {抽出されたコマンド or "default"}
  Lintコマンド:    {抽出されたコマンド or "default"}

🤖 エージェントロール: {検出されたロール or "none (single agent)"}

📝 コミット規約: {抽出されたフォーマット or "default"}
```

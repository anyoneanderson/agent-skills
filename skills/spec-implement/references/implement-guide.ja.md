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
0. ロールガード — オーケストレーター専任、コード/レビュー/テストは自分で書かない

1. 初期チェック
   ├── 作業ディレクトリの確認（gitリポジトリ、gh CLI利用可能）
   ├── オプション解析（--resume, --issue, --spec, --dry-run）
   ├── cmux利用可否チェック（$CMUX_SOCKET_PATH）
   └── specディレクトリの特定 🚨 ブロッキング
       ├── .specs/ を必ずスキャン（Issue本文にパスがあっても省略しない）
       ├── 見つかった場合 → そのまま使用して進行
       └── 見つからない場合 → パスを手動指定するか spec-generator を提案

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

5. ランタイム対応の並列モード判定
   ├── 現在の実行環境からランタイムを判定
   ├── ワークフローの `Agent definition files` / `エージェント定義ファイル` セクションを解析（存在する場合）
   ├── ランタイムごとのサブエージェント設定を検証
   │   ├── Codex: name フィールドが一致する .codex/agents/workflow-*.toml
   │   └── Claude Code agent team: name が一致する .claude/agents/workflow-*.md
   ├── ランタイムが曖昧な場合はユーザーに選択確認
   └── 設定不備ならシングルエージェント順次実行へフォールバック

6. タスクループ（オーケストレーターがワーカースキルに委任）
   ├── ロールタグ解析: [orchestrator] フェーズ → 直接実行
   ├── [code] フェーズ → 各未完了タスクに対して:
   │   ├── spec-code --task {id} --spec {path} を呼び出し
   │   ├── spec-review --task {id} --spec {path} を呼び出し
   │   ├── review-{id}.md を読み → fix loop（最大3回）:
   │   │   └── spec-code --feedback review-{id}.md → 再レビュー
   │   ├── spec-test --task {id} --spec {path} を呼び出し
   │   ├── テスト FAIL → spec-code --feedback test-{id}.md → 再テスト
   │   ├── レビュー PASS かつ テスト PASS → tasks.md チェック更新
   │   └── 進捗をコミット
   └── 重要: オーケストレーターは実装もレビューも自分でしない — 常に委任

7. 最終品質ゲート
   ├── 全テスト実行（ワークフローから）
   ├── lint/typecheck実行（ワークフローから）
   ├── 全[MUST]ルールの通過を確認
   └── CLAUDE.md 条件付きルールの通過を確認

8. PR作成
   ├── ワークフローのPRテンプレートに従う
   ├── --base {base_branch}（ワークフローから動的決定）
   ├── Issueにリンク（Closes #{N}）
   ├── 先送りした指摘（fix_before: trial / required_check / follow_up）の
   │   後続 issue を起票して PR 本文にリンク。失敗時は指摘全文を本文に残して
   │   警告を添える
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
| Agent Definition Files (Optional) | サブエージェント定義ファイルの明示パス |
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
2. Codex custom agents、Claude Code agent team、cmux dispatch の3パターンから実行方式を解決
3. サブエージェント選択時: ランタイム別の方式でロール定義に基づいてエージェントを起動
4. シングル選択時: 順次実行で続行

### ランタイム判定ルール

ランタイムは現在の実行環境から判定します。リポジトリ内のディレクトリ（`.codex/`, `.claude/`）の有無だけで判定してはいけません。

- `.codex/` と `.claude/` は設定検証のためにのみ使用
- ワークフローの `Agent definition files` / `エージェント定義ファイル` セクションを先に解析
- ワークフローに明示された定義ファイルパスを最優先で使用
- ワークフロー未記載時のみランタイム既定パスにフォールバック
- Codex のランタイム既定パスは `.codex/agents/workflow-implementer.toml`、`.codex/agents/workflow-reviewer.toml`、`.codex/agents/workflow-tester.toml`
- Codex は `.codex/agents/*.toml` から custom agent を検出する。`[agents.<name>] config_file = ...` は要求も作成もしない
- Claude Code agent team のランタイム既定パスは `.claude/agents/workflow-implementer.md`、`.claude/agents/workflow-reviewer.md`、`.claude/agents/workflow-tester.md`
- Claude Code 実行中で `.claude/agents/workflow-*.md` が存在し、`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が設定されている場合は、Claude Code agent team を使用する
- cmux dispatch は別ペインで外部起動する方式。`--roles` なしでは、ワークフローまたはユーザーが cmux を明示選択した場合、または runtime-native agent が使えない場合に使用する。`--roles` ありでは host-aware 能力 fallback を優先し、dispatch mode を黙って切り替えず native 利用不能を caller へ報告する
- ランタイムを判定できない場合は、起動前にユーザーへ確認
- ランタイム設定が不正な場合は順次実行へフォールバック

### 並列モードの優先順位

`/spec-implement --issue {N}` が明示的な dispatch 指定なしで呼ばれた場合は、次の優先順位を使う:

1. **Codex custom agents**: Codex 実行中で `.codex/agents/workflow-*.toml` が存在する
2. **Claude Code agent team**: Claude Code 実行中で `.claude/agents/workflow-*.md` が存在し、`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が設定されている
3. **cmux dispatch**: `$CMUX_SOCKET_PATH` が設定され、ワークフローまたはユーザーが cmux dispatch を選択している
4. **シングルエージェント**: 有効な並列設定がない

有効なランタイム組み込み設定が1つだけの場合は確認で止まらない。複数の有効モードがあり、ワークフローに優先指定がない場合、ランタイム判定が曖昧な場合、または Claude Code agent team が要求されているが `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` が有効でない場合のみ確認する。

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

**マルチエージェント役割分担戦略テーブル** — 各フェーズでアクティブなロールを定義:

```markdown
| Phase | Implementer | Tester | Reviewer |
|-------|-------------|--------|----------|
| Analysis | Design review | Test plan | - |
| Implementation | Write code | Write tests | - |
| Review | - | - | Review code + tests |
| Quality Gate | - | Run all tests | Final check |
```

### テーブルからサブエージェントパラメータへのマッピング

サブエージェント起動時:

1. **サブエージェント識別子**: ロール割り当てテーブルの `Agent` 列の値を agent type として使用（例: `workflow-implementer`）
2. **定義ファイルパス**: ワークフローの `Agent definition files` / `エージェント定義ファイル` セクションに記載があればそのパスを使用。未記載時はランタイム既定パスを使用
3. **エージェントの責務**: `Responsibility` 列の値をタスクプロンプトのコンテキストとして使用
4. **フェーズ実行順序**: マルチエージェント役割分担戦略テーブルを行ごとに上から順に実行:
   - `-` のセルはそのフェーズでロールがアイドル状態であることを示す
   - `-` 以外のセルはそのフェーズでのロールのアクションを記述
   - 同じフェーズ行でアクティブなロールは同時実行可能
   - フェーズは上から下に順次実行

### 例: ランタイム別の呼び出し

「Implementation」フェーズでImplementerとTesterが両方アクティブな場合:

```text
# Codex（並列起動の例）
Task:
  agent_type: workflow-implementer
  prompt: "/spec-code --issue {N} --task {task-id} --spec {path} を実行。ワークフローに従い、変更ファイル、実行コマンド、ブロッカーを報告する。"

Task:
  agent_type: workflow-tester
  prompt: "/spec-test --task {task-id} --spec {path} を実行。追加したテスト、実行コマンド、失敗、カバレッジ不足を報告する。"
```

```text
# Claude Code agent team（ランタイム組み込みの自然言語例）
この実装フェーズ用の agent team を作成する。
workflow-implementer と workflow-tester というプロジェクト subagent 定義を使用する。
teammate 名は implementer と tester にする。
implementer に割り当て: /spec-code --issue {N} --task {task-id} --spec {path} を実行。変更ファイル、実行コマンド、ブロッカーを報告する。
tester に割り当て: /spec-test --task {task-id} --spec {path} を実行。追加したテスト、実行コマンド、失敗、カバレッジ不足を報告する。
ファイル競合を避けるため、担当ファイルを分ける。両 teammate の完了を待ってから次に進む。
```

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

**「並列モードを開始できない」**
- ランタイムごとの設定を確認:
  - Codex: `.codex/agents/workflow-implementer.toml`、`.codex/agents/workflow-reviewer.toml`、`.codex/agents/workflow-tester.toml` が存在し、各 `name` フィールドがワークフローの `Agent` 列と一致している
  - Claude Code agent team: ワークフロー記載パスが存在する（未記載時は `.claude/agents/workflow-implementer.md`, `.claude/agents/workflow-reviewer.md`, `.claude/agents/workflow-tester.md`）
  - cmux + Claude Code: `$CMUX_SOCKET_PATH` が設定され、`cmux-delegate` が利用可能で、必要に応じてロール表の `AI` 列が `claude` に対応している
- 設定が不足している場合は順次実行で続行するか、`spec-workflow-init` を再実行

**「ワークフロー記載のエージェント定義ファイルが存在しない」**
- ワークフロー内の `Agent definition files` / `エージェント定義ファイル` セクションのパスを確認
- ワークフローのパスを修正するか、不足ファイルを作成してから再実行

**「ワークフローのAgent名がランタイム設定に存在しない」**
- ワークフローの Role Assignment Table の `Agent` 名とランタイムの識別子定義を一致させる
- ワークフローまたはランタイム設定を修正して再実行

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
🤖 ランタイム:      {codex | claude-code | unknown}
🤖 並列モード:      {enabled | disabled | fallback-to-sequential}
🤖 エージェント定義: {workflow記載パス | runtime defaults}

📝 コミット規約: {抽出されたフォーマット or "default"}
📋 レビュー基準:  {パス or "未検出"}
🖥️  cmux dispatch: {有効 | 無効}
```

## cmux ディスパッチパターン

cmux dispatch モードが選択された場合、サブエージェントは組み込み Agent ツールの代わりに cmux ワークスペースで起動されます。

### ディスパッチ方式の選択

1. **cmux-delegate スキルがインストール済みの場合**（推奨）:
   - `Skill` ツールで `cmux-delegate` を呼び出す
   - スキルが cmux CLI 操作（ワークスペース作成、エージェント起動、ポーリング、結果回収）を抽象化する
   - **組み込み Agent ツールは使わない** — 必ず `cmux-delegate` スキルを使用する
   - **安全ルール**: 合成したプロンプトや diff は先に一時ファイルへ書き出し、その内容を渡す。複数行テキストを `--task` / `--diff` のクォート文字列に直接埋め込まない
   - 具体的な呼び出し例:
     ```
     # 実装者を Codex で起動
     TASK_FILE=$(mktemp)
     cat > "$TASK_FILE" <<'EOF'
     You are a workflow-implementer.
     {definition file content}

     Task: Implement T001 — create user model following design section 2.3.
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent codex --task \"$(cat \"$TASK_FILE\")\""

     # テスターを Codex で起動（実装者と並列）
     TEST_TASK_FILE=$(mktemp)
     cat > "$TEST_TASK_FILE" <<'EOF'
     You are a workflow-tester.
     {definition file content}

     Task: Write tests for T001 — verify user model CRUD operations.
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent codex --task \"$(cat \"$TEST_TASK_FILE\")\""

     # レビュアーを Claude で起動（実装・テスト完了後）
     REVIEW_TASK_FILE=$(mktemp)
     cat > "$REVIEW_TASK_FILE" <<'EOF'
     You are a workflow-reviewer.
     {definition file content}

     Review the following changes against review_rules.md:
     {git diff output}
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent claude --task \"$(cat \"$REVIEW_TASK_FILE\")\""
     ```
   - セカンドオピニオン実行:
     ```
     DIFF_FILE=$(mktemp)
     git diff HEAD > "$DIFF_FILE"
     Skill:
       skill: "cmux-second-opinion"
       args: "--diff \"$(cat \"$DIFF_FILE\")\" --rules '{path to review_rules.md}'"
     ```
2. **cmux-delegate スキルが未インストールの場合**（フォールバック）:
   - 以下の cmux CLI パターンを Bash で直接実行する

### エージェント起動パターン（低レベル・フォールバック用）

```bash
# 1. ペイン分割（new-workspace は非ターミナル surface を作る可能性があるため使用しない）
WS=$(cmux new-split right)
# 出力: OK surface:{N} workspace:{N}

# 2. エージェント起動（ロールテーブルの AI 列に基づきコマンド選択）
# Claude Code:
cmux send --surface surface:{N} "claude --dangerously-skip-permissions\n"
# Codex:
cmux send --surface surface:{N} "codex --dangerously-bypass-approvals-and-sandbox\n"
# Gemini CLI:
cmux send --surface surface:{N} "gemini\n"

# 3. プロンプト検出（3秒間隔、15秒タイムアウト）
sleep 3
cmux read-screen --surface surface:{N}

# 4. タスク送信（一時ファイル経由で改行やクォートを安全に保持）
TASK_FILE=$(mktemp)
cat > "$TASK_FILE" <<'EOF'
{task_prompt}
EOF
while IFS= read -r line; do
  cmux send --surface surface:{N} "$line"
  cmux send-key --surface surface:{N} return
done < "$TASK_FILE"

# 5. 完了検出（段階的ポーリング: 5秒 → 10秒 → 30秒）
cmux read-screen --surface surface:{N}

# 6. 結果回収
cmux read-screen --surface surface:{N} --scrollback 500

# 7. クリーンアップ
cmux close-workspace --workspace workspace:{N}
```

### ロールテーブルからのエージェント選択

ワークフローのロール割り当てテーブルに `AI` 列がある場合:

| ロール | エージェント | AI | 責務 |
|--------|-------------|-----|------|
| 実装者 | workflow-implementer | codex | コード作成 |
| テスター | workflow-tester | codex | テスト作成 |
| レビュアー | workflow-reviewer | claude | コードレビュー |

AI 列の値 → 起動コマンドのマッピング:

| AI 値 | コマンド（auto-approve） |
|-------|----------------------|
| `claude` | `claude --dangerously-skip-permissions` |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `gemini` | `gemini`（auto-approve なし） |
| *(未指定)* | デフォルト: `claude --dangerously-skip-permissions` |

### cmux でのマルチエージェント実行

戦略テーブルに従い、同一行のロールを並列起動:

1. 実装者 + テスターを別ワークスペースで同時起動
2. 両方の完了を監視
3. 両方完了後、レビュアーを起動
4. 全結果を統合

## レビューゲート詳細

### Implementation Review Gate

単純なセルフレビューを構造化されたプロセスに置き換えます:

1. **基準読み込み**: review_rules.md（検出時）+ coding-rules.md + CLAUDE.md
2. **レビュー**: 重大度別チェック（セキュリティ、型安全、パターン、品質）
3. **検出結果の分類**:
   - **重大**: セキュリティ脆弱性、バグ → 人間の優先度は最上位
   - **改善提案**: 品質、可読性 → 修正に値する
   - **軽微**: スタイル → ログのみ
   - 重大 / 改善提案の各指摘には `fix_before` タグ
     （`implementation | trial | required_check | follow_up`。定義と格上げの
     立証責任は spec-review SKILL.md Step 4.5）も付ける。ゲートで止めるのは
     `fix_before: implementation` だけ。
4. **修正ループ**（最大3回）:
   - `fix_before: implementation` の指摘を修正 → 変更箇所のみ再レビュー
   - 先送りの指摘（`trial` / `required_check` / `follow_up`）と軽微は記録して
     PR 本文へ持ち越す。このループでは修正しない
   - 3回目で未解消の `implementation` 指摘 → ユーザーに判断を委ねる
5. **セカンドオピニオン**（cmux dispatch + second-opinion 有効時）:
   - セルフレビューループ通過後
   - `Skill` ツールで `cmux-second-opinion` スキルを呼び出す（推奨）。未インストールの場合はフォールバックとしてレビュアーエージェントを cmux で手動起動
   - スキルが diff + review_rules.md を別AIに送信し、構造化レポートを回収する
   - 新たな `fix_before: implementation` 指摘 → 追加修正ループ（1回のみ）
6. **ゲート通過**: 未解消の `fix_before: implementation` 指摘がない状態

### Test Review Gate

Implementation Review Gate と同じ構造 + テスト固有の観点:

- カバレッジが完了条件を満たしているか
- エッジケース・エラーパスのテストがあるか
- テストの独立性（テスト間依存なし）
- AAA パターン（Arrange → Act → Assert）

### セカンドオピニオン設定（ワークフローから）

ワークフローの "Second Opinion" / "セカンドオピニオン" セクションから設定を読み取ります:

| 設定 | 動作 |
|------|------|
| 「毎回実施」/ "Always" | レビューゲートごとに自動実行 |
| 「ユーザー要求時のみ」/ "On request" | 実行前にユーザーに確認（AskUserQuestion） |
| 「実施しない」/ "Never" | スキップ |
| *(セクション未定義)* | デフォルト: 「ユーザー要求時のみ」 |

**実行方法**: `Skill` ツールで `cmux-second-opinion` スキルを呼び出す:
```
DIFF_FILE=$(mktemp)
git diff HEAD > "$DIFF_FILE"
Skill:
  skill: "cmux-second-opinion"
  args: "--diff \"$(cat \"$DIFF_FILE\")\" --rules '{path to review_rules.md}'"
```
スキルが未インストールの場合は、レビュアーエージェントを cmux で手動起動してフォールバックする。

## エージェント定義ファイルの注入

Codex のランタイム組み込み custom agent を起動する場合、TOML の内容をプロンプトへ注入しないでください。Codex は agent type に基づいて `.codex/agents/*.toml` から `developer_instructions` を読み込みます。

Claude Code agent team の teammate を起動する場合も、Claude Code が project subagent を選択できるなら Markdown の agent 定義をプロンプトへ注入しないでください。Claude Code が選択された `.claude/agents/*.md` の定義を読み込みます。agent team はリーダーの会話履歴を継承しないため、Issue、spec path、task id、担当ファイル、依存関係、期待する成果物などのタスク固有コンテキストは生成プロンプトに含める。

cmux や custom agent type を直接選択できない外部ランタイムを使う場合は、エージェント定義ファイルの内容をタスクプロンプトに注入します。これにより、外部エージェントもロール固有のルールと制約を認識した状態でタスクを実行します。

### 注入手順

1. Codex のランタイム組み込みサブエージェントを使う場合は、ワークフローの `Agent` 列の値を custom agent type として使用し、ファイル内容の注入はスキップする。
2. Claude Code agent team を使う場合は、ワークフローの `Agent` 列の値を project subagent 名としてチーム生成プロンプトに含め、ファイル内容の注入はスキップする。
3. cmux または外部 dispatch の場合は、ロールに対応する定義ファイルを読み込む:
   - ワークフローの `Agent definition files` / `エージェント定義ファイル` セクションに記載があればそのパスを使用
   - 未記載時はランタイム既定パス（例: `.claude/agents/workflow-implementer.md`）を使用
4. 定義ファイルの内容をタスクプロンプトの先頭に付加する
5. 定義ファイルが存在しない場合は、ロール割り当てテーブルの `Responsibility` 列をロール説明として使用

### プロンプト構成テンプレート

```
You are a {role_name}.

{content of agent definition file}

Task: {actual task description from tasks.md}

Context:
- Design reference: {design.md section}
- Coding rules: {path to coding-rules.md}
- Review rules: {path to review_rules.md} (reviewer only)
- Target files: {file list}
```

### 例: Codex ランタイム組み込み custom agent

```text
Agent:
  agent_type: workflow-implementer
  prompt: |
    /spec-code --issue 123 --task T001 --spec .specs/user-model を実行。
    Target files: src/models/user.ts
    変更ファイル、実行コマンド、ブロッカーを報告する。
```

### 例: cmux-delegate スキル経由

```text
TASK_FILE=$(mktemp)
cat > "$TASK_FILE" <<'EOF'
You are a workflow-implementer.
{content of definition file}

Task: Implement T001 — create user model.
Target files: src/models/user.ts
EOF
Skill:
  skill: "cmux-delegate"
  args: "--agent codex --task \"$(cat \"$TASK_FILE\")\""
```

### レビュアーのプロンプト構成

レビュアーは通常のタスクプロンプトに加え、レビュー対象の差分と基準を含めます:

```
You are a workflow-reviewer.

{content of agent definition file}

Review the following changes:
{git diff output or changed files summary}

Review criteria:
- review_rules.md: {path}
- coding-rules.md: {path}
- design.md: {relevant section}

Classify findings as: Critical / Improvement / Minor
```

## kind ラベルによるタスク単位ルーティング

SKILL.md の「Phase 6b」で要約した `--roles` レイヤーの詳細です。まずタスクの
`kind` を implementer AI role へ対応づけ、その後 `--host-runtime` を使って
runtime-native subagent か cross-AI agent-delegate backend を選びます。Phase 6 の
ループとレビューゲートはそのまま保ちます。

### 有効になる条件

- **`--roles` 省略時** → 従来経路。全タスクを spec-code、全レビューを spec-review で処理し、
  spec-test も従来どおり。agent-delegate は一切呼ばれません。パイプライン以前の仕様書と完全に同じ挙動です。
- **`--roles` 指定時** → オーケストレーション経路。`--host-runtime {claude|codex}`
  が必須です。各タスクの implementer / reviewer AI role を先に決め、その後で実行
  backend を解決します。

`--review-fallback` はこの経路のレビューだけに適用します。既定値は `block` で、
preferred cross-AI reviewer が利用不能な場合に単体の `spec-implement --roles` が停止する
従来の意図を維持します。`native-independent` は明示指定が必要です。spec-orchestrate は
single-AI 環境でも完走できるよう、この値を渡します。

ループの制御フローは両経路で同一です（フェーズ単位の反復、3回上限の修正ループ、
ゲート判定＝ `fix_before: implementation` は再実行・先送りの指摘と Minor は記録のみ、チェックボックス更新、コミット方針）。
タスクごとに解決されるのは各ステップの**実行主体だけ**です。

### `--roles` のパース

`--roles` は次のどちらの形式も受け付けます:

1. **インラインマップ**: `ui=claude,backend=codex,test=codex` — カンマ区切りの `kind=owner` の並び。
   owner は `claude` か `codex`。
2. **pipeline.yml のパス**: `roles:` ブロックを持つファイル。`roles.impl_ui` / `roles.impl_backend` /
   `roles.impl_test` を読み、kind `ui` / `backend` / `test` に対応づけます。

```bash
# インライン形式 → 連想配列で引く
# roles[ui]=claude roles[backend]=codex roles[test]=codex

# pipeline.yml 形式（yq や awk）。キーが無い kind は未マッピングのまま
impl_ui="$(yq -r '.roles.impl_ui // empty' "$roles_path")"      # → roles[ui]
impl_backend="$(yq -r '.roles.impl_backend // empty' "$roles_path")"
impl_test="$(yq -r '.roles.impl_test // empty' "$roles_path")"
```

タスク処理前に `--host-runtime` を検証します。値は `claude` / `codex` のどちらかです。
オーケストレーターは pipeline state に記録した値を渡します。単体呼び出しでは明示指定が
必要です。role の既定値や agent-delegate の環境変数から推測しません。

### 担当解決（タスクごと）

```
kind  = tasks.md のタスク詳細ブロックの `kind:` フィールドの値
owner = roles[kind]              kind が既知かつマップに存在する場合
owner = claude                   それ以外（kind 不明・欠落、またはマップ未登録）
```

`owner` は implementer AI role であり、backend ではありません。次の共通の
host-aware 行列で実行手段を解決します。

<!-- dispatch-matrix:start -->
| Host runtime | Owner AI role | Backend | agent-delegate target |
|---|---|---|---|
| `codex` | `codex` | `runtime-native` | `-` |
| `codex` | `claude` | `agent-delegate` | `claude` |
| `claude` | `claude` | `runtime-native` | `-` |
| `claude` | `codex` | `agent-delegate` | `codex` |
<!-- dispatch-matrix:end -->

host と owner が一致すれば runtime-native subagent を使い、agent-delegate は起動しません。
native worker では spec-code を実行します。異なれば公開契約どおりに agent-delegate を使います。

### 相手 LLM への実装委譲（`owner != host_runtime`）

`agent-delegate/references/contract.md` に従います。
コード実装はファイルを書き込むため、明示的な `--detach` と `--sandbox workspace-write` を使います。
owner AI role を `--target` で明示し、expected run id と起動時刻を保持します。
15秒を標準、30秒を上限としてポーリングし、30分ごとに状態を再確認します。
起動から2時間に達したら、公開契約の停止手順を適用します。

起動前に、phase 開始時の git snapshot、タスクの正確な対象パス、prompt に含める呼び出し側生成の相関値、機械検査できる Done criteria を記録します。
この4項目をタスク固有の成果物復旧 validator として使い、実行失敗後に validator を作りません。

```bash
OUT=".specs/{feature}/delegate/{task-id}"; mkdir -p "$OUT"
PROMPT="$(mktemp)"
cat > "$PROMPT" <<EOF
Implement {task-id} from the spec.
- Spec dir: .specs/{feature}/  (requirement.md, design.md, tasks.md)
- Task detail: {タスク詳細ブロックを貼り付け。Done criteria と Target files を含む}
- Coding rules: {coding-rules.md のパス}
Commit nothing; report changed files and any blocker.
EOF

launch="$(agent-delegate.sh --mode delegate --target "$owner" \
  --prompt-file "$PROMPT" --out-dir "$OUT" --label "{task-id}" \
  --sandbox workspace-write --detach)"
expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
# 公開契約の状態機械を適用する15秒間隔の永続監視を開始する。
# valid terminal report の通知後: status="$(jq -r .status "$report")"
```

- 各周期では expected-run report、owner、pid、heartbeat、worker/monitor の
  プロセス状態の順に確認します。
  生存中と劣化状態では待機を続け、report の不在だけで失敗にしません。
- 2時間に達したらreportとownerを読み直し、expected monitorと確認できたプロセスだけに`TERM`を送ります。
  terminal reportを最大90秒待ち、公開されなければ`--force`を実行せず、診断情報を人間へ渡して待機を終了します。
- `status == done` → 相手が完了。チェックボックスを更新してコミット（コミットは相手ではなく
  オーケストレーターが持つ。相手には「コミットするな」と指示する）。
- expected-run の `status == blocked` かつ `blocker_category == env_error` → 修正ループへ入る前に、fail-closed な成果物復旧を適用します。
  phase 開始時からの差分が宣言済み対象パス内に収まり、相関の証拠が存在し、起動前に定義した Done-criteria validator に合格した場合だけ処理を続けます。
  blocked report は実行時の診断として残します。
- ほかの `status == blocked`、または成果物復旧の不合格 → `blocker` / `blocker_category` を読み、修正ループ（下記）に回すか呼び出し元に上げます。

### Preferred reviewer と backend 解決

先に preferred reviewer AI role を決め、その後で backend を解決します。

```
reviewer = claude  if owner == codex
reviewer = codex   if owner == claude
```

`reviewer == host_runtime` なら runtime-native reviewer subagent で spec-review を
実行し、agent-delegate は起動しません。異なれば以下の peer review 経路で
`--target "$reviewer"` を使います。cross-AI review は優先経路であり、常に守るべき
不変条件はレビュー実行コンテキストの独立性です。

### Cross-AI peer review（`reviewer != host_runtime`）

契約上、review モードは常に read-only です。
5分以内に完了する具体的根拠がある場合だけ同期実行します。
それ以外は `--detach` を追加して expected run id を保持し、同じ15〜30秒の状態待機を使います。
起動前に、review file の鮮度の基準、review 文脈へ含める呼び出し側生成の相関値、review out-dir を除いたワークスペースの git snapshot を記録します。
snapshot には agent-delegate 契約の内容 fingerprint を使い、path または status の一覧だけで済ませません。

```bash
OUT=".specs/{feature}/review/{task-id}"; mkdir -p "$OUT"
git diff "{base_branch}...HEAD" > "$OUT/{task-id}-diff.txt"
PROMPT="$(mktemp)"
cat > "$PROMPT" <<EOF
Review the changes for {task-id}.
- Diff: $OUT/{task-id}-diff.txt
- Spec dir: .specs/{feature}/
- Review criteria: {review_rules.md のパス}, {coding-rules.md のパス}
EOF

report="$(agent-delegate.sh --mode review --target "$reviewer" \
  --prompt-file "$PROMPT" --out-dir "$OUT" --label "{task-id}-review" | tail -1)"
review_file="$(jq -r .artifacts.review_file "$report")"
gate="$(grep -m1 '^Gate:' "$review_file")"    # Gate: PASS | Gate: FAIL
```

レビューファイルは spec-review 出力と同じ severity セクション（`### Critical` / `### Improvement` /
`### Minor`）と `Gate: PASS|FAIL` 行を持つため、「Review Gate Details」の既存ゲートロジックが
無改修でそのまま消費できます。

expected-run の blocked report が `blocker_category: env_error` の場合は、再実行または blocked と決める前に、公開契約の fail-closed な成果物復旧を適用します。
宣言済み review file が起動後に新規作成または更新され、相関値を持ち、4点構造検査、Critical と Improvement の有効な `fix_before`、Gate 再計算に合格した場合だけ採用します。
宣言済み out-dir を除いた実行後のワークスペース snapshot が起動前と一致することも確認します。
blocked report は実行時の診断として残します。
ほかの blocked 分類と成果物復旧の不合格は通常の blocked 経路へ渡します。

### 独立 native review フォールバック

次の条件をすべて満たす場合にだけ、この経路を適用します。

1. preferred reviewer が `host_runtime` と異なる。
2. agent-delegate が不在、exit `2`、または
   `blocker_category: tool_unavailable` を返した。
3. `--review-fallback native-independent` が明示指定されている。

fallback reviewer は host AI role を使いますが、implementer そのものではありません。
各レビューラウンドで次を守ります。

- runtime の新規 subagent 起動機構で runtime-native **reviewer** subagent を毎回新規に
  起動する。オーケストレーターの文脈を再利用せず、implementer instance を resume
  せず、実装会話を継続しない。
- diff / 成果物、仕様、レビュー基準だけを渡す。再レビューではこれに過去の findings と
  修正概要だけを加える。
- 読み取り専用ツールだけを公開し、reviewer 起動直前とレビュー後の repository change
  fingerprint を突合する。fingerprint は tracked worktree / staged diff の内容と、
  gitignore 対象外の untracked path / 内容を含める。除外するのは caller が所有する
  run-record path だけで、`.specs/` 全体を除外してはいけない。対象 fingerprint に変化が
  あれば review result を破棄し、通常の workspace drift 手順へ blocked で回す。
- preferred 経路と同じ spec-review 互換の構造化内容を返す。レビューファイルを
  materialize するのは reviewer ではなくオーケストレーターとする。

option 省略時は `--review-fallback block` とします。runtime が新規 reviewer instance を
保証できない場合や runtime-native reviewer が利用不能な場合は blocker を報告し、
オーケストレーター自身でレビューしてはいけません。各 fallback 起動を構造化された
`review_fallbacks` record として呼び出し元へ返します。record は phase（`implement`）・
artifact/task id・round・レビュー時点の `host_runtime`・preferred/actual role・backend・
reason・independence を持ちます。state を書くのは spec-orchestrate だけであり、返却 record
を `state.review_fallbacks` へ追記します。単体の spec-implement は pipeline state を
書かず、completion summary に列挙します。PR には cross-AI 保証の縮退を明記します。

### 修正ループのルーティング

修正ループの構造（最大3回、その後は降格 or ユーザー確認）は不変です。修正の実行主体だけが
タスクの実装担当に従います:

| Implementer backend | 修正ステップ | 再レビュー |
|---|---|---|
| runtime-native | native spec-code subagent を `--feedback {findings}` 付きで再実行 | preferred の反対 reviewer AI を再解決し、利用不能なら明示された fallback policy を再適用 |
| agent-delegate | `--mode delegate --target <owner> --detach --resume {thread_id}`（findings を追記） | preferred の反対 reviewer AI を再解決し、利用不能なら明示された fallback policy を再適用 |

ラウンドをまたぐ agent-delegate 再レビューは `--resume {thread_id}`（thread_id は前ラウンドの
`report.json` から取得）でレビューセッションを継続し、文脈を保ってトークンを節約します。resume は
作成時のサンドボックスを維持し、レビューセッションは read-only なので契約の resume 規則を満たします。

### 能力フォールバック

- **host runtime が不正・未指定:** オーケストレーター配下では設定 blocker を報告します。
  単体では `claude` / `codex` の指定を人に求めます。
- **native subagent が利用不能:** 上位へ報告し、オーケストレーターが manual / auto の
  role fallback を適用します。単体では owner AI role を変える前に人へ確認します。
- **cross-AI peer が利用不能**（スクリプト不在、exit `2`、または
  `blocker_category: tool_unavailable`）: 実装では上位へ報告し、オーケストレーターが
  manual / auto の owner fallback を適用します。レビューでは既定の
  `--review-fallback block` なら停止します。明示された `native-independent` なら上記の
  独立 native review 契約を使います。同じ AI role でも implementer instance は
  決して再利用しません。

fallback を黙って選びません。spec-implement は worker role の変更と独立 review
fallback を呼び出し元へ返します。唯一の state writer である spec-orchestrate が
`state.role_overrides` / `state.review_fallbacks` へ記録して PR 本文へ記載します。
単体実行では pipeline state を書かず、completion summary に表示します。

agent-delegate の内部実装を取り込んではいけません。依存するのは契約に定義されたフラグと
`report.json` スキーマのみです。

# agent-skills

仕様駆動開発と自律（harness）開発のための再利用可能なAIエージェントスキル集。

[English version](README.md)

## スキル一覧

| スキル | 説明 |
|-------|------|
| [spec-generator](skills/spec-generator/) | 会話やプロンプトからプロジェクトの要件定義書・設計書・タスクリストを生成 |
| [spec-writing](skills/spec-writing/) | 具体的な処理説明と共通の抽象動詞語彙を使って仕様書を生成・修正 |
| [handover](skills/handover/) | ローカルのセッション引き継ぎを作成し、次のAIエージェントセッションを検証済み文脈から開始 |
| [mcp-convert](skills/mcp-convert/) | Claude Code の MCP 設定を Codex CLI 向けに変換 |
| [spec-inspect](skills/spec-inspect/) | 仕様書の品質を検証し、実装前に問題を検出 |
| [spec-rules-init](skills/spec-rules-init/) | プロジェクト規約を抽出し、統一的なcoding-rules.mdを生成 |
| [spec-to-issue](skills/spec-to-issue/) | 仕様書から構造化されたGitHub Issueを自動生成 |
| [spec-workflow-init](skills/spec-workflow-init/) | 対話形式でプロジェクト固有のissue-to-pr-workflow.mdを生成 |
| [spec-code](skills/spec-code/) | 仕様書から1タスクを自律的に実装 |
| [spec-review](skills/spec-review/) | ルール×ファイルのマトリックスによる構造化コードレビュー |
| [spec-test](skills/spec-test/) | タスク完了条件に基づくテスト作成・実行 |
| [spec-evaluate](skills/spec-evaluate/) | 受け入れテスト計画（test.md）をビルドに対して実行し、証跡を保存して要件別の合否を報告 |
| [spec-implement](skills/spec-implement/) | spec-code/review/testをオーケストレーションし仕様書からPRまで |
| [spec-orchestrate](skills/spec-orchestrate/) | Issue や要求を仕様→敵対的レビュー→実装→受け入れ試験→PRまで一気通貫で駆動（manual / 完全自律） |
| [cmux-fork](skills/cmux-fork/) | Claude Codeの会話を新しいcmuxペインまたはワークスペースにフォーク |
| [cmux-delegate](skills/cmux-delegate/) | 別のcmuxペインまたはワークスペースでAIエージェントにタスクを委任 |
| [cmux-second-opinion](skills/cmux-second-opinion/) | cmux経由で別AIエージェントにコードや仕様書の独立レビューを依頼 |
| [agent-delegate](skills/agent-delegate/) | もう一方のAIエージェントにタスク委譲や敵対的レビューをヘッドレスで依頼（cmux不要）。解析可能なreport.jsonを返す |
| [skill-suggest](skills/skill-suggest/) | プロジェクトの技術スタックを自動解析し、skills.shレジストリから最適なスキルを提案・インストール |
| [harness-init](skills/harness-init/) | Harness Engineering 制御ループ（Planner/Generator/Evaluator エージェント・hooks・ガードスクリプト）をプロジェクトに導入 |
| [harness-plan](skills/harness-plan/) | epic を計画: product-spec を起草し sprint roadmap を導出、sprint ごとに tracker Issue を起票 |
| [harness-loop](skills/harness-loop/) | Generator⇄Evaluator の自律 sprint 制御ループを rubric 収束まで実行し PR を作成 |

## インストール

```bash
# 全スキルをインストール
npx skills add anyoneanderson/agent-skills -g -y

# 個別にインストール
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill spec-writing -g -y
npx skills add anyoneanderson/agent-skills --skill handover -g -y
npx skills add anyoneanderson/agent-skills --skill mcp-convert -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-rules-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
npx skills add anyoneanderson/agent-skills --skill spec-workflow-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-code -g -y
npx skills add anyoneanderson/agent-skills --skill spec-review -g -y
npx skills add anyoneanderson/agent-skills --skill spec-test -g -y
npx skills add anyoneanderson/agent-skills --skill spec-evaluate -g -y
npx skills add anyoneanderson/agent-skills --skill spec-implement -g -y
npx skills add anyoneanderson/agent-skills --skill spec-orchestrate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-fork -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-second-opinion -g -y
npx skills add anyoneanderson/agent-skills --skill agent-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill skill-suggest -g -y

# Harness Engineering（自律）— 先に spec-rules-init + spec-workflow-init を入れる
npx skills add anyoneanderson/agent-skills --skill harness-init -g -y
npx skills add anyoneanderson/agent-skills --skill harness-plan -g -y
npx skills add anyoneanderson/agent-skills --skill harness-loop -g -y
```

> **Note**: cmux スキルは [cmux](https://cmux.dev/)（macOS 14.0+）が必要で、cmux セッション内で実行する必要があります。

## クイックスタート

### 仕様書を生成する

```
> 要件定義を作って
> todo-appの設計書を作成して
> todo-appのタスクリストを作って
> ECサイトの仕様を全部作って
```

### セッションをまたいで再開する

```
> handover write
> handover boot
> handover install
> handover status
```

### 仕様書の品質を検証する

```
> 仕様書を検査
> 品質チェック
> 仕様を検証
```

### Claude の MCP 設定を Codex に変換する

```
> Claude CodeのMCPをCodexに変換
> ClaudeのMCP設定をCodex CLIに同期
> mcpServersをCodexに移行
```

### コーディングルールを生成する

```
> コーディングルールを生成して
> coding-rules.mdを作成
> プロジェクトルールを抽出
```

### 開発ワークフローを生成する

```
> ワークフローを生成
> 開発フローを作成
> Issue-to-PRフローを設定
```

### 仕様書からGitHub Issueを作成する

```
> 仕様書をIssueにして
> specからIssue作成
```

### 1タスクを実装する

```
> /spec-code --issue 42 --task T-003 --spec .specs/auth-feature/
> /spec-code --task T-007 --feedback .specs/feature/review-T-007.md
```

### コードレビューする

```
> /spec-review --task T-003 --spec .specs/auth-feature/
> /spec-review （スタンドアロン — 現在の diff をレビュー）
```

### テストを実行する

```
> /spec-test --task T-003 --spec .specs/auth-feature/
```

### ビルドに対して受け入れ試験を実行する

```
> /spec-evaluate --spec .specs/auth-feature/
> /spec-evaluate --spec .specs/auth-feature/ --round 2 --backend self
```

### 仕様書から実装してPRを作成する（オーケストレーション）

```
> 仕様書から実装 --issue 42
> 実装を開始 --spec .specs/auth-feature/
> 実装を再開 --resume
```

### 仕様からPRまでパイプライン全体を1コマンドで回す

```
> /spec-orchestrate --mode manual          # 対話で仕様を固め、承認したらあとは任せる
> /spec-orchestrate --issue 42             # auto: Issue を渡して PR を待つ
> /spec-orchestrate --resume               # 中断した実行を pipeline-state.json から再開
```

### 会話をフォークする（cmux）

```
> フォークして
> 下にフォークして
> 新しいワークスペースでフォークして
```

### 別エージェントにタスクを委任する（cmux）

```
> 別ペインでテストを実行して
> Codex にこの diff をレビューしてもらって
> 新しいワークスペースに委任して
```

### セカンドオピニオンを取得する（cmux）

```
> この diff をセカンドオピニオンして
> 仕様書のセカンドオピニオンをもらって
> 自由にレビューしてもらって
```

### ヘッドレスで委譲・レビューする — cmux 不要（agent-delegate）

```
> このタスクを Codex に投げて
> Codex にこの diff をレビューさせて
> cmux なしでセカンドオピニオン
```

### ベストプラクティススキルを提案する

```
> おすすめスキルを教えて
> スキルを提案して
> ベストプラクティススキルを検索
```

### 自律 harness 開発をセットアップする

> 前提: 先に `/spec-rules-init` と `/spec-workflow-init` を実行 — harness はそれらが生成する `coding-rules.md` / `review_rules.md` / `issue-to-pr-workflow.md` を消費します。

```
> harness を初期化          # harness-init: 制御ループを導入
> epic を計画               # harness-plan: product-spec → roadmap → tracker Issue
> harness-loop を実行        # harness-loop: 自律 Generator ⇄ Evaluator sprint → PR
> harness-loop を実行 --mode autonomous-ralph
```

## 仕組み

1. **spec-generator** が `.specs/{project}/` に構造化された仕様書を生成:
   - `requirement.md` — 要件定義書
   - `design.md` — 技術設計書
   - `tasks.md` — 実装タスクリスト
   - `test.md` — 受け入れテスト計画（full ワークフローの最終ステップで生成）

2. **handover** がセッション継続を支援:
   - ローカルの `handover.md` と `.handover/` 状態ファイルを作成
   - `.gitignore` ガードによりデフォルトで handover を private に保持
   - AGENTS.md / CLAUDE.md の起動ガイダンスと optional な Claude Code / Codex session-start hook をインストール
   - 次セッションで handover metadata と現在の repository 状態を照合して boot

3. **spec-inspect** が仕様書の品質を検証:
   - 要件ID整合性の検証
   - 必須セクションや矛盾の検出
   - 曖昧な表現の識別
   - 検査結果を `inspection-report.md` に生成

4. **spec-to-issue** が `.specs/{project}/` を読み取り、チェックリスト・仕様書リンク・完了条件を含むGitHub Issueを作成。

5. **spec-workflow-init** が `docs/issue-to-pr-workflow.md` にプロジェクト固有の開発ワークフローを生成。

6. **spec-rules-init** がプロジェクト規約から品質ルールを生成:
   - `docs/coding-rules.md` — 実装品質ゲート
   - `docs/review_rules.md` — レビュー基準（重大度別出力方針: CI / レビューゲート / セカンドオピニオン）

7. **spec-code** が仕様書から1タスクを自律的に実装:
   - 全仕様書（requirement.md, design.md, tasks.md）を読んでコンテキスト把握
   - coding-rules.md とプロジェクト規約に従う
   - `--feedback` モードでレビュー/テスト結果への対応が可能

8. **spec-review** が構造化コードレビューを実行:
   - ルール × ファイルのマトリックスで漏れなく照合
   - 結果を `review-{task-id}.md` に出力（spec-code --feedback で使用）
   - スタンドアロンで手動レビューにも使える

9. **spec-test** がテストを作成・実行:
   - タスク完了条件からテスト要件を抽出
   - 既存のテストパターンとフレームワークを検出
   - 結果を `test-{task-id}.md` に出力

10. **spec-evaluate** が受け入れテスト計画（`test.md`）を実装済み機能に対して実行:
    - 各項目を検証方法別（playwright / command / file-check）に実行
    - 証跡（スクリーンショット・ログ）を `.specs/{feature}/evidence/{round}/` に保存
    - 証跡を機械検証: 裏づけファイルのない PASS 報告は FAIL に倒す
    - `evaluate-{round}.md` を出力 — spec-review 互換 findings として `spec-code --feedback` に渡せる

11. **spec-implement** がパイプライン全体をオーケストレーション（自分ではコードもレビューも書かない）:
    - 委任: spec-code → spec-review → fix loop → spec-test
    - `[code]` フェーズはワーカースキルに委任、`[orchestrator]` フェーズは直接実行
    - review + test 両方 PASS 後にのみ tasks.md を更新
    - オプション: `--roles` でタスクの `kind:` ごとに Claude / Codex の AI role を選び、`--host-runtime` との一致時は runtime-native、反対側だけを target 明示の agent-delegate で実行。preferred reviewer は反対 AI。単体の `--roles` は利用不能時に停止し、`--review-fallback native-independent` 明示時だけ独立 native reviewer を許可
    - オプション: **cmux dispatch** でサブエージェント並列実行
    - 品質ゲート通過後にPRを作成

12. **spec-orchestrate** が要求や Issue から PR までパイプライン全体を駆動:
    - フェーズ: 受付 → 仕様生成 → 機械検査 → 敵対的仕様レビュー（別 LLM）→ 人間承認（manual のみ）→ 実装 → 受け入れ試験 → PR → 振り返り
    - 2モード: `manual`（仕様承認の1箇所だけ人間ゲート）と `auto`（Issue を入れると PR が出る、人間の入力なし）
    - フェーズ別の担当割りを `.specs/pipeline.yml` で設定（claude ⇄ codex）。host と一致する role は runtime-native subagent、反対側は target 明示の agent-delegate で実行
    - single-AI fallback: preferred cross-AI reviewer が利用不能なら、新規 read-only host-native reviewer subagent を起動して保証の縮退を記録。reviewer の独立性を保証できない場合だけ停止
    - 停滞したレビューループを機械シグナル（findings 指紋）で検知し裁定: 担当を入れ替えるか draft PR で着地
    - 状態は `pipeline-state.json` に保存。中断しても最後の完了フェーズから再開
    - 振り返りでは実行記録を集計して改善提案を生成し、安全なものは自動適用（ブランチ → PR → 自動マージ。公開契約と SKILL.md は常に人間レビュー）

### エージェント間委譲（cmux 不要）

13. **agent-delegate** がもう一方のエージェント（Claude Code ⇄ Codex）へのタスク委譲・敵対的レビューをヘッドレスで実行:
    - `--mode delegate` は peer CLI でタスクを実行、`--mode review` は read-only の敵対的レビュー
    - 機械可読な `report.json` を返す（stdout の最終行は従来どおりそのパス。detach 起動では expected run id も出力）
    - 書き込みを伴う delegate は明示的な `--detach` を既定とし、同期実行は5分以内という具体的根拠がある read-only 作業に限る
    - detach 実行は15秒間隔（最大30秒）で expected-run report、owner、pid、heartbeat、プロセス状態の順に確認し、実行が生存中なら report の未生成だけで失敗にしない
    - expected-run の `env_error` をタスク失敗とする前に、起動前に宣言したパス、鮮度、相関、mode 固有の検証を使って fail-closed な `env_error` の成果物復旧を試す。monitor の消失だけでは失敗にしない
    - detach待機は30分ごとに状態を再確認し、2時間でexpected monitorへ`TERM`を送る。terminal reportを最大90秒待っても公開されなければ、自動で`--force`を使わず、診断情報を人間へ渡して待機を終了する
    - `--resume <thread_id>` でセッション継続 — 多ラウンドのレビューを1つの文脈で回せる

### cmux スキル（オプション、[cmux](https://cmux.dev/) が必要）

14. **cmux-fork** が現在の会話を新しい cmux ペインまたはワークスペースにフォーク。会話コンテキストを完全に引き継ぎ。

15. **cmux-delegate** が別の cmux ワークスペースに AI エージェントを起動し、タスクを送信・監視・結果回収。Claude Code / Codex / Gemini CLI 対応。

16. **cmux-second-opinion** が別の AI エージェントに独立したレビューを依頼。親と異なるエージェントを自動選択。コードレビュー・仕様書レビュー対応、基準モード3種。

### プロジェクトセットアップ

17. **skill-suggest** がプロジェクトのマニフェストファイル（package.json, Cargo.toml 等）を解析し、skills.sh レジストリからベストプラクティス系スキルを検索・提案・インストール。`--agent` オプションで不要ディレクトリの生成を防止。

### Harness Engineering（自律、オプション）

上記 `/spec-*` フローより一歩進んだ自律レーン。**前提:** 先に **spec-rules-init** と **spec-workflow-init** を実行 — harness は `docs/coding-rules.md` / `docs/review_rules.md` / `docs/issue-to-pr-workflow.md` を、自律エージェントが従う rulebook として消費する。`/spec-*` が人間をタスク単位でループ内に残すのに対し、harness は人間が決めた境界内で sprint まるごとを自走させる。

18. **harness-init** が制御ループを導入: 環境設定を一度ヒアリングし、Planner/Generator/Evaluator サブエージェント・hooks・ガードスクリプト・`.harness/` resilience ツリーを生成。プロジェクトごとに一度実行。

19. **harness-plan** が epic を計画: `product-spec.md` を起草し、sprint 分解/bundling 付きの `roadmap.md` を導出、sprint ごとに tracker Issue を起票。自律実行前の最後の人間介入ステップ。

20. **harness-loop** が GAN 制御ループを実行: sprint ごとに contract を交渉し、Generator ⇄ Evaluator を rubric 収束（または Principal Skinner 停止）まで反復、毎 iteration で checkpoint（`progress.md` + `_state.json` + git + `metrics.jsonl`）し PR を作成。モード: interactive / continuous / autonomous-ralph / scheduled。

## 互換性

[SKILL.md](https://skills.sh) フォーマット対応の全エージェントで動作:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode など。

## ライセンス

[MIT](LICENSE)

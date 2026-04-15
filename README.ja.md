# agent-skills

仕様駆動開発のための再利用可能なAIエージェントスキル集。

[English version](README.md)

## スキル一覧

| スキル | 説明 |
|-------|------|
| [spec-generator](skills/spec-generator/) | 会話やプロンプトからプロジェクトの要件定義書・設計書・タスクリストを生成 |
| [mcp-convert](skills/mcp-convert/) | Claude Code の MCP 設定を Codex CLI 向けに変換 |
| [spec-inspect](skills/spec-inspect/) | 仕様書の品質を検証し、実装前に問題を検出 |
| [spec-rules-init](skills/spec-rules-init/) | プロジェクト規約を抽出し、統一的なcoding-rules.mdを生成 |
| [spec-to-issue](skills/spec-to-issue/) | 仕様書から構造化されたGitHub Issueを自動生成 |
| [spec-workflow-init](skills/spec-workflow-init/) | 対話形式でプロジェクト固有のissue-to-pr-workflow.mdを生成 |
| [spec-code](skills/spec-code/) | 仕様書から1タスクを自律的に実装 |
| [spec-review](skills/spec-review/) | ルール×ファイルのマトリックスによる構造化コードレビュー |
| [spec-test](skills/spec-test/) | タスク完了条件に基づくテスト作成・実行 |
| [spec-implement](skills/spec-implement/) | spec-code/review/testをオーケストレーションし仕様書からPRまで |
| [cmux-fork](skills/cmux-fork/) | Claude Codeの会話を新しいcmuxペインまたはワークスペースにフォーク |
| [cmux-delegate](skills/cmux-delegate/) | 別のcmuxペインまたはワークスペースでAIエージェントにタスクを委任 |
| [cmux-second-opinion](skills/cmux-second-opinion/) | cmux経由で別AIエージェントにコードや仕様書の独立レビューを依頼 |
| [skill-suggest](skills/skill-suggest/) | プロジェクトの技術スタックを自動解析し、skills.shレジストリから最適なスキルを提案・インストール |
| [harness-init](skills/harness-init/) | Harness 制御ループ（Planner/Generator/Evaluator サブエージェント・hooks・ガードスクリプト・耐性ファイル）をプロジェクトに導入 |
| [harness-plan](skills/harness-plan/) | /harness の epic を計画: 対話で product-spec.md を起草、bundling 判定付き roadmap.md を導出、sprint 毎に tracker Issue を起票 |

## インストール

```bash
# 全スキルをインストール
npx skills add anyoneanderson/agent-skills -g -y

# 個別にインストール
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill mcp-convert -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-rules-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
npx skills add anyoneanderson/agent-skills --skill spec-workflow-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-code -g -y
npx skills add anyoneanderson/agent-skills --skill spec-review -g -y
npx skills add anyoneanderson/agent-skills --skill spec-test -g -y
npx skills add anyoneanderson/agent-skills --skill spec-implement -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-fork -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-second-opinion -g -y
npx skills add anyoneanderson/agent-skills --skill skill-suggest -g -y
npx skills add anyoneanderson/agent-skills --skill harness-init -g -y
npx skills add anyoneanderson/agent-skills --skill harness-plan -g -y
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

### 仕様書から実装してPRを作成する（オーケストレーション）

```
> 仕様書から実装 --issue 42
> 実装を開始 --spec .specs/auth-feature/
> 実装を再開 --resume
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

### ベストプラクティススキルを提案する

```
> おすすめスキルを教えて
> スキルを提案して
> ベストプラクティススキルを検索
```

### Harness 制御ループを導入する

```
> harness を導入
> ハーネスを初期化
> harness-init を実行
```

### harness epic を計画する

```
> epic を計画
> harness-plan を実行
> product-spec を作成
```

## 仕組み

1. **spec-generator** が `.specs/{project}/` に構造化された仕様書を生成:
   - `requirement.md` — 要件定義書
   - `design.md` — 技術設計書
   - `tasks.md` — 実装タスクリスト

2. **spec-inspect** が仕様書の品質を検証:
   - 要件ID整合性の検証
   - 必須セクションや矛盾の検出
   - 曖昧な表現の識別
   - 検査結果を `inspection-report.md` に生成

3. **spec-to-issue** が `.specs/{project}/` を読み取り、チェックリスト・仕様書リンク・完了条件を含むGitHub Issueを作成。

4. **spec-workflow-init** が `docs/issue-to-pr-workflow.md` にプロジェクト固有の開発ワークフローを生成。

5. **spec-rules-init** がプロジェクト規約から品質ルールを生成:
   - `docs/coding-rules.md` — 実装品質ゲート
   - `docs/review_rules.md` — レビュー基準（重大度別出力方針: CI / レビューゲート / セカンドオピニオン）

6. **spec-code** が仕様書から1タスクを自律的に実装:
   - 全仕様書（requirement.md, design.md, tasks.md）を読んでコンテキスト把握
   - coding-rules.md とプロジェクト規約に従う
   - `--feedback` モードでレビュー/テスト結果への対応が可能

7. **spec-review** が構造化コードレビューを実行:
   - ルール × ファイルのマトリックスで漏れなく照合
   - 結果を `review-{task-id}.md` に出力（spec-code --feedback で使用）
   - スタンドアロンで手動レビューにも使える

8. **spec-test** がテストを作成・実行:
   - タスク完了条件からテスト要件を抽出
   - 既存のテストパターンとフレームワークを検出
   - 結果を `test-{task-id}.md` に出力

9. **spec-implement** がパイプライン全体をオーケストレーション（自分ではコードもレビューも書かない）:
   - 委任: spec-code → spec-review → fix loop → spec-test
   - `[code]` フェーズはワーカースキルに委任、`[orchestrator]` フェーズは直接実行
   - review + test 両方 PASS 後にのみ tasks.md を更新
   - オプション: **cmux dispatch** でサブエージェント並列実行
   - 品質ゲート通過後にPRを作成

### cmux スキル（オプション、[cmux](https://cmux.dev/) が必要）

7. **cmux-fork** が現在の会話を新しい cmux ペインまたはワークスペースにフォーク。会話コンテキストを完全に引き継ぎ。

8. **cmux-delegate** が別の cmux ワークスペースに AI エージェントを起動し、タスクを送信・監視・結果回収。Claude Code / Codex / Gemini CLI 対応。

9. **cmux-second-opinion** が別の AI エージェントに独立したレビューを依頼。親と異なるエージェントを自動選択。コードレビュー・仕様書レビュー対応、基準モード3種。

### プロジェクトセットアップ

10. **skill-suggest** がプロジェクトのマニフェストファイル（package.json, Cargo.toml 等）を解析し、skills.sh レジストリからベストプラクティス系スキルを検索・提案・インストール。`--agent` オプションで不要ディレクトリの生成を防止。

11. **harness-init** が Harness 制御ループをプロジェクトへ導入。環境設定（プロジェクト種別・Generator バックエンド・Evaluator ツール・hook 強制レベル・Principal Skinner 閾値・MCP allow-list）を 1 度ヒアリングし、Planner/Generator/Evaluator サブエージェント、`.claude/settings.json` hooks、ガードスクリプト（`progress-append` / `restore-after-compact` / `stop-guard` / `tier-a-guard` / `mcp-allowlist` / `wrap-untrusted`）、耐性ファイル（`.harness/progress.md` / `_state.json` / `metrics.jsonl`）を生成する。`/harness-plan` → `/harness-loop` → `/harness-rules-update` 系列の事前準備。

12. **harness-plan** が epic 単位で 1 度だけ実行され、`harness-init` と `harness-loop` の間を埋める。`product-spec.md` を対話で起草（Why / What / Out of Scope / Constraints — "How" の混入を拒否）、Planner サブエージェントに `roadmap.md` を導出させ sprint 毎に 4 結合軸（スキーマ・認証・UI・契約面）で `bundling: split|bundled` を判定、人間承認ゲートを通し、sprint 毎 contract.md 雛形を事前記入、sprint 毎に tracker Issue を起票（GitHub / GitLab / なし）する。完了後、プロジェクトは `/harness-loop` で sprint ループを開始できる状態になる。

## 互換性

[SKILL.md](https://skills.sh) フォーマット対応の全エージェントで動作:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode など。

## ライセンス

[MIT](LICENSE)

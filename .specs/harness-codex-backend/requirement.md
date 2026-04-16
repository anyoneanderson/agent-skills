# 要件定義: harness-codex-backend

## 1. 背景と目的

親仕様 `.specs/harness-suite/` に対する差分仕様。Issue #46 で提起された「Codex をバックエンドとして使う場合のアーキテクチャ課題」を解決する。

### 発端

- zen-base での dogfood 中、`openai/codex-plugin-cc` の存在発覚
- Claude Code 側の `PostToolUse(Edit|Write)` hook が Codex 内部 subprocess の編集を観測できないことが判明（実機確認済み）
- 「hooks が効かないから `codex_cmux` 棄却」という過去の決定（F2）が、`codex_plugin` でも同じ問題を抱えることが判明 → 設計原則そのものを見直す必要

### 目的

1. Generator backend を `claude` / `codex_plugin` / `codex_cmux` の 3 種対称に扱う
2. backend 非依存の統一プロトコル（ファイル経由通信）を確立
3. Codex 側の hook / agent / trust gate といった新概念を設計に取り込む
4. Planner が大きい Epic で context 破綻しないよう fresh 分割を導入

### 親仕様との関係

- 親 `.specs/harness-suite/` の既存 REQ / NFR / CON / ASM は**基本維持**
- 本仕様は**差分**（追加 / 修正 / 訂正）のみ記述
- 修正対象の親 REQ は `REQ-NNN-M`（Modified）で参照、新規要件は `REQ-CB-NNN` 形式

## 2. ステークホルダー

| Role | 新たに関わる要素 |
|---|---|
| Skill 利用者 | backend 3 種を選択可能、Codex 側の trust gate は silent auto-add で意識不要 |
| Planner / Generator / Evaluator | 全員 fresh invocation + ファイル経由通信に統一。Generator は backend 問わず同じ出力契約を持つ |
| Skill 開発者 | agent templates / hook scripts / bridge scripts を書く対象ファイルが増える |

## 3. 機能要件

### 3.1 Generator backend 対称化（修正）

- **[REQ-060-M] Generator backend の 3 種並列サポート**: `_config.yml.generator_backend` の値（`claude` / `codex_plugin` / `codex_cmux`）で切り替え、すべて同一の出力契約（REQ-CB-001）に従うこと。
  - `claude`: `.claude/agents/generator.md` を介した Claude sub-agent 呼び出し
  - `codex_plugin`: `node codex-companion.mjs task --fresh --prompt-file ... --json`（non-interactive、主役）
  - `codex_cmux`: `cmux-delegate codex --prompt-file ...`（可視性 / debug 用途）
  - フォールバック挙動は `codex_cmux` → `claude`、`codex_plugin` → `claude`（cmux / plugin 不在時）。フォールバック時は `progress.md` に警告 1 行を記録すること。
- **[REQ-020-M] product-spec.md 作成フロー**: Planner との対話は **1 session に限定**（対話性のため）、ただし user 応答を逐次 `progress.md` に append し compact 耐性を担保すること。
- **[REQ-021-M] roadmap.md 生成は別 fresh Planner**: `product-spec.md` 確定後、Orchestrator が新たな Planner sub-agent を起動し roadmap を生成すること。product-spec 対話の Planner session は再利用しない。
- **[REQ-073-M] Hook 強制記録の backend 別分岐**:
  - `claude`: 親仕様 REQ-073 の通り `PostToolUse(Edit|Write)` hook + `progress-append.sh`
  - `codex_plugin` / `codex_cmux`: Claude 側 hook では観測不可なため、**Orchestrator bridge script** (`codex-progress-bridge.sh`) が Codex の `report.json` を読んで `progress.md` に代行追記する
  - 両方式とも同一の行フォーマット（`[ts] tool=X file=Y phase=Z iter=N agent=W`）を生成し、grep 時に backend 非依存とすること

### 3.2 統一出力プロトコル（新規）

- **[REQ-CB-001] Generator の 2 ファイル出力義務**: backend 問わず Generator 呼び出しの完了時に以下 2 ファイルが存在することを義務化する。
  1. `<sprint>/feedback/generator-<iter>.md` — narrative（approach / concerns / evidence pointers）
  2. `<sprint>/feedback/generator-<iter>-report.json` — 機械可読レポート
     ```json
     {
       "status": "done" | "blocked",
       "touchedFiles": ["relative/path/a.ts", ...],
       "summary": "one-line description",
       "blocker": null | "<text if status=blocked>"
     }
     ```
- **[REQ-CB-002] Report.json 書き忘れ時のフォールバック**: Codex が report.json を書かずに終了した場合、Orchestrator は `git diff --name-only HEAD` で `touchedFiles` を再構築し、report.json を自前で生成すること。この時 `progress.md` に `[WARN] codex-report missing, fell back to git diff` を 1 行記録する。
- **[REQ-CB-003] Orchestrator Bridge の backend 非依存性**: bridge script (`codex-progress-bridge.sh`) は入力として「report.json のパス」のみを受け、backend 種別を引数に取らないこと。これにより bridge ロジックが backend 増減に追従不要となる。

### 3.3 Planner の fresh 分割（新規）

- **[REQ-CB-010] contract 雛形生成の sprint 毎 fresh invocation**: `/harness-plan` の contract 雛形生成は sprint 毎に独立した fresh Planner sub-agent 呼び出しで行うこと。各呼び出しは `product-spec.md` + `roadmap.md` + 該当 sprint のメタデータだけを読む。
- **[REQ-CB-011] contract 雛形生成の並列実行許容**: 上記の sprint 毎 fresh invocation は sprint 間で独立しているため、Claude Code の Task tool が並列実行をサポートする場合は並列化してよい。並列時の順序依存は存在しないこと。
- **[REQ-CB-012] Planner session 長寿命化の禁止**: `/harness-plan` 内で 1 つの Planner sub-agent が product-spec 対話 + roadmap 生成 + contract 雛形生成を通しで行う実装を禁止する。単一 session の context 線形膨張を避けるため。

### 3.4 Codex 側 Hook の導入（新規）

- **[REQ-CB-020] Codex Hook 生成**: `harness-init` が `<project>/.codex/hooks.json` を生成し、`_config.yml.generator_backend` が `codex_plugin` または `codex_cmux` の場合のみ以下の hook を登録すること。
  - `SessionStart(startup|resume)`: `inject-harness-context.sh` — contract / progress.md tail / _state.json を stdout で吐いて Codex に注入
  - `PreToolUse(Bash)`: `tier-a-guard-codex.sh` — `rm -rf` / `git push --force` 等を Codex 側でも block（Tier-A 二重ガード）
  - `PostToolUse(Bash)`: `codex-bash-log.sh` — test / build / lint 等の Bash 実行結果を `progress.md` に追記
- **[REQ-CB-021] Codex Hook Feature Flag の有効化**: `harness-init` が `<project>/.codex/config.toml` に `[features] codex_hooks = true` を追記すること。既存の config が存在する場合は非破壊パッチで追記する。
- **[REQ-CB-022] Write Interception の Future Work 明記**: 本仕様時点で Codex 側 hook の `PreToolUse` / `PostToolUse` matcher は Bash tool のみ対象であり、Write / Edit / MCP / WebSearch の interception は未実装であること。この制約を `design.md` に明記し、Orchestrator bridge 方式を併用する理由とする。

### 3.5 Agent TOML / MD の Role Contract 化（新規）

- **[REQ-CB-030] Role Contract の TOML / MD への集約**: `.codex/agents/generator.toml` / `.claude/agents/generator.md`（および `.ja.md`）の `developer_instructions` / body に以下をすべて記述すること。
  - Boot Sequence（progress.md / _state.json / contract.md / 前 iter feedback を読む）
  - Pre-flight Gates（pending_human / aborted_reason / current_epic 等の不成立チェック）
  - 出力プロトコル（REQ-CB-001 の 2 ファイル書き込み義務）
  - 禁則事項（自己評価禁止、progress.md 直書き禁止、main force-push 禁止）
- **[REQ-CB-031] Task-specific Prompt の最小化**: Orchestrator が生成する prompt-file には role 知識を含めず、以下のみ含めること:
  - "You are the '<role>' agent defined in `<path>`. Load and follow its developer_instructions."
  - 今回の iteration / sprint 番号
  - 今回のタスク固有指示（例: "apply feedback/evaluator-<iter-1>.md"）
- **[REQ-CB-032] Codex plugin の model 非同期性への対応**: codex-plugin-cc の `task` コマンドは agent TOML の `model` フィールドを honor しないため、Orchestrator は毎回 `--model <name>` を明示的に指定すること。model 値は `_config.yml.codex_generator_model`（デフォルト `gpt-5.4`）から引く。
- **[REQ-CB-033] planner / evaluator の同構造化**: 上記 REQ-CB-030 は `planner.toml` / `evaluator.toml`（および対応 `.md` / `.ja.md`）にも適用すること。

### 3.6 Codex Backend Discovery（新規）

- **[REQ-CB-040] Codex Plugin Path の動的解決**: `harness-init` は `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` を glob で検出し、見つかったパスを `_config.yml.codex_plugin_path` に保存すること。plugin が未インストールの場合は `codex_plugin` backend 選択を禁止し、hearing でエラー表示する。
- **[REQ-CB-041] Codex CLI 存在チェック**: `harness-init` は `codex --version` で Codex CLI の存在を確認し、不在なら `codex_plugin` / `codex_cmux` 両方を選択肢から除外すること。ユーザに `npm install -g @openai/codex` を案内する。

### 3.7 F2 決定の撤回

- **[REQ-CB-050] `codex_cmux` オプションの復活**: 親仕様 `_config.yml.generator_backend` の選択肢に `codex_cmux` を復活させること（Dogfood Round 2 で削除した F2 決定を撤回）。ただし位置付けは「主役の `codex_plugin` に対する可視性 / debug 用のセカンダリ選択肢」とし、ヒアリング説明文でその旨を明示する。

## 4. 非機能要件

- **[NFR-CB-001] Backend 追加時の拡張性**: 将来 `other_mcp` や `gemini_plugin` 等の新 backend が追加されても、Orchestrator bridge / report.json schema / role contract / hearing UI は**無変更で吸収可能**であること。変更が必要なのは Generator 起動コマンド 1 行のみであること。
- **[NFR-CB-002] Token コスト監視**: `_fresh` 運用は毎 invocation で全ファイルを再読するため token が嵩む。`metrics.jsonl` の `cost_usd` で実測を取り、閾値超過時は REQ-080 の Principal Skinner が停止判定に使うこと（既存機構の継承）。
- **[NFR-CB-003] Test mode でのサイドエフェクト禁止**: bridge script / codex hook script は `HARNESS_TEST_MODE=1` 時に state / progress / metrics への書き込みを行わないこと（既存 B4 パターンの継承）。

## 5. 制約

- **[CON-CB-001] Claude Code / Codex のバージョン依存**: 本仕様は以下の最低バージョンを前提とする。
  - Claude Code: sub-agent 仕様、hooks 仕様が安定化されたバージョン（2026-04 現在）
  - Codex CLI: `0.120.0` 以上（`codex_hooks` feature flag サポート）
  - codex-plugin-cc: `1.0.3` 以上
- **[CON-CB-002] 既存ファイルの非破壊パッチ**: `<project>/.codex/config.toml` / `.claude/settings.json` への追記はすべて非破壊パッチ（既存エントリを上書きしない）で行うこと。
- **[CON-CB-003] Model 指定の統一**: 本仕様では Codex のモデル指定は `--model` フラグ経由に統一する。agent TOML の `model` フィールドは将来 plugin 側が honor するようになったら再有効化するが、現時点では**プレースホルダとして記述は残すが運用上参照しない**。

## 6. 前提

- **[ASM-CB-001] Codex hook の Bash only 制約**: 2026-04 時点で Codex 側 hook の tool matcher は Bash のみ対応。Write / MCP / WebSearch は未実装。本仕様はこの制約を前提に設計し、Write 観測は Orchestrator bridge が担う。
- **[ASM-CB-002] Codex の trust gate auto-add**: codex-plugin-cc 経由で呼ばれた場合、Codex は workspace を silent に trust list へ追加する（実機確認済み）。user への明示的な trust 承認ガイドは不要。
- **[ASM-CB-003] `--fresh` デフォルト運用**: Codex plugin backend 使用時は `--fresh` を毎 invocation 指定するのが default。`--resume-last` は token コスト対策として user が明示的に opt-in した場合のみ使用する（本仕様は opt-in 機構は未定義、将来課題）。
- **[ASM-CB-004] Codex CLI の app-server mode 前提**: codex-plugin-cc は Codex の app-server protocol を使用する。Codex CLI が "advanced runtime available" 状態であることを前提とする（`/codex:setup` で確認可能）。

## 7. スコープ外

- Codex 側の `Stop` hook 採用（将来 Ralph 風自己継続を検討する際に扱う、今回は shell ループ制御で代替）
- `--resume-last` を使った token 最適化
- Generator 以外（Planner / Evaluator）を Codex バックエンドで動かす運用（現状 Planner / Evaluator は Claude 固定）
- Codex SDK 直接統合（将来 plugin 依存を外したい場合の検討）
- `gemini_plugin` 等の別 AI backend の追加（本仕様の拡張性確認用途としてのみ言及、実装しない）

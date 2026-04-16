# タスクリスト: harness-codex-backend

## Priority

| Priority | 基準 | 該当タスク |
|---|---|---|
| P0（必須） | これ無しには Codex backend が機能しない | T-CB-001, T-CB-010, T-CB-020〜T-CB-025, T-CB-030〜T-CB-033 |
| P1（重要） | 体験 / スケール上必要 | T-CB-002, T-CB-011, T-CB-012, T-CB-040〜T-CB-043, T-CB-050 |
| P2（発展） | 品質向上 / 将来対応 | T-CB-013, T-CB-044, T-CB-060〜T-CB-062 |

## マイルストーン

| Milestone | Scope | Tasks |
|---|---|---|
| **M-CB-A: 仕様反映** | 親 spec の更新 or 本 spec を正式採用化 | T-CB-001〜T-CB-002 |
| **M-CB-B: テンプレ / スクリプト整備** | role contract 化 + 新規 hook / bridge scripts | T-CB-010〜T-CB-013 |
| **M-CB-C: harness-init 改修** | 生成物追加 + 動的 discovery | T-CB-020〜T-CB-025 |
| **M-CB-D: harness-plan 改修** | Planner fresh 分割 + 並列化 | T-CB-030〜T-CB-033 |
| **M-CB-E: harness-loop 改修** | backend 分岐 + bridge 呼び出し | T-CB-040〜T-CB-044 |
| **M-CB-F: dogfood 検証** | zen-base で実走 | T-CB-050 |
| **M-CB-G: Future-work 整理** | write interception / resume-last の準備 | T-CB-060〜T-CB-062 |

---

## M-CB-A: 仕様反映（Phase B-2）

### [T-CB-001] 親仕様 (`.specs/harness-suite/`) の差分反映判断 (P0)
- 対応要件: 本仕様全体
- 作業内容:
  - **選択 A**: 親仕様を直接書き換え（`requirement.md` / `design.md` / `tasks.md`）、本仕様はレビュー用として残す
  - **選択 B**: 親仕様に「Codex backend は別仕様参照」のポインタを追加し、本仕様をプロモート
  - レビュー合意で選択、PR 本文に記録
- 完了基準: 選択が Issue #46 / PR description に明記され、レビュアーの合意を得る
- 依存: なし

### [T-CB-002] 親 requirement.md の書き換え（選択 A 採用時） (P1)
- 対応要件: REQ-060-M, REQ-020-M, REQ-021-M, REQ-073-M + REQ-CB-001〜050
- 作業ファイル: `.specs/harness-suite/requirement.md`
- 作業内容:
  - REQ-060 を 3 backend 並列に書き換え、`codex_cmux` 復活を明記
  - REQ-020 / REQ-021 に Planner fresh 分割の補足追加
  - REQ-073 を backend 別分岐に書き換え
  - 本仕様 §3.1〜3.7 の新規 REQ を親 REQ 番号空間に編入（例: REQ-060 の下位項目として REQ-060a, 060b...）または新番号帯（REQ-110〜）を払い出す
  - 新 ASM 追加（Codex hook Bash only / trust auto-add / --fresh デフォルト）
- 完了基準: 親仕様が自己完結し、本仕様参照なしでも一貫している
- 依存: T-CB-001

### [T-CB-003] 親 design.md の書き換え（選択 A 採用時） (P1)
- 対応要件: 本仕様 §1〜§11 を親 §1〜§12 に融合
- 作業ファイル: `.specs/harness-suite/design.md`
- 作業内容:
  - §3.1〜3.3 に backend matrix / Planner fresh 分割 / bridge フローを追記
  - §9.4 を backend 別分岐実装に書き直し
  - §9.5 書き込み権限 table に report.json 行追加
  - §10 Technology Stack に codex-plugin-cc / codex-companion / codex hooks を追加
  - §11 Security に Codex 側 Tier-A 二重ガード追記
  - §12 テスト戦略に T-CB-test-1〜6 を追加
- 完了基準: design.md の Traceability Matrix が本仕様 REQ もすべてカバー
- 依存: T-CB-002

### [T-CB-004] 親 tasks.md への task 追加（選択 A 採用時） (P1)
- 作業ファイル: `.specs/harness-suite/tasks.md`
- 作業内容: M-CB-B〜M-CB-F を親マイルストーン体系に編入（M7 として追加等）
- 完了基準: 全新規タスクが親 tasks.md に反映
- 依存: T-CB-002, T-CB-003

---

## M-CB-B: テンプレ / スクリプト整備（Phase B-3 前半）

### [T-CB-010] agent role contract 化（generator / planner / evaluator）(P0)
- 対応要件: REQ-CB-030〜033
- 作業ファイル:
  - `skills/harness-init/references/agent-templates/generator.toml` / `.md` / `.ja.md`
  - `skills/harness-init/references/agent-templates/planner.toml` / `.md` / `.ja.md`
  - `skills/harness-init/references/agent-templates/evaluator.toml` / `.md` / `.ja.md`
- 作業内容: developer_instructions / body に以下を記述
  - Boot Sequence（REQ-072 参照）
  - Pre-flight Gates（pending_human / aborted_reason / current_epic 等）
  - 出力プロトコル（REQ-CB-001 の 2 ファイル書き込み義務、Codex のみ）
  - 禁則事項
- 完了基準:
  - 6 ファイル（3 role × toml/md ≒ 6, さらに .ja.md 含めて 9 相当）が更新
  - Codex plugin で actual invoke した時に developer_instructions が反映されることを T-CB-050 で確認
- 依存: なし

### [T-CB-011] `codex-progress-bridge.sh` 作成 (P0)
- 対応要件: REQ-CB-001, REQ-CB-002, REQ-CB-003, REQ-073-M
- 作業ファイル: `skills/harness-init/references/scripts/codex-progress-bridge.sh`
- 作業内容: 本仕様 §5.1 の擬似コードに従い実装
  - stdin = report.json、args = `--phase / --iter / --agent`
  - per-file 行追記 + summary 行 + `_state.json` atomic update
  - `HARNESS_TEST_MODE=1` で no-op
- 完了基準:
  - shellcheck pass
  - unit test: 既知 input → 期待 output（手動 or T-CB-044）
- 依存: なし

### [T-CB-012] Codex 側 hook scripts 3 本作成 (P0)
- 対応要件: REQ-CB-020
- 作業ファイル:
  - `skills/harness-init/references/codex-hooks/inject-harness-context.sh`
  - `skills/harness-init/references/codex-hooks/tier-a-guard-codex.sh`
  - `skills/harness-init/references/codex-hooks/codex-bash-log.sh`
- 作業内容:
  - `inject-harness-context.sh`: SessionStart(startup|resume) 入力を受け、`.harness/progress.md` tail + `_state.json` summary を stdout に出力（Codex の developer context として注入される）
  - `tier-a-guard-codex.sh`: PreToolUse(Bash) で `.harness/tier-a-patterns.txt` に match したら `{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "..."}}` を stdout
  - `codex-bash-log.sh`: PostToolUse(Bash) の入力から command と output を抽出し、`progress.md` に `[ts] codex-bash cmd="..." exit=N` を 1 行追記
- 完了基準:
  - 3 本とも実行可能、JSON stdout format が Codex hook spec に準拠
  - shellcheck pass
- 依存: なし

### [T-CB-013] `.codex/hooks.json` テンプレ作成 (P1)
- 対応要件: REQ-CB-020, REQ-CB-021
- 作業ファイル: `skills/harness-init/references/codex-hooks/hooks.json.template`
- 作業内容: 本仕様 §4.4 のスキーマ通りの template、path placeholder は `$CODEX_REPO_ROOT` で埋める
- 完了基準: jq でパース可能、3 event 全て登録
- 依存: T-CB-012

---

## M-CB-C: harness-init 改修（Phase B-3 中盤）

### [T-CB-020] `_config.yml` schema 拡張 (P0)
- 対応要件: REQ-CB-040, REQ-CB-041, REQ-CB-050
- 作業ファイル: `skills/harness-init/SKILL.md` の Step 3（config 書き出し部）
- 作業内容:
  - `codex_plugin_path` / `codex_generator_model` / `codex_resume_strategy` フィールド追加
  - `generator_backend` 選択肢に `codex_cmux` 復活
- 完了基準: 生成された `_config.yml` に新フィールドが含まれ、デフォルト値が正しい
- 依存: T-CB-001

### [T-CB-021] Codex CLI / plugin discovery ロジック (P0)
- 対応要件: REQ-CB-040, REQ-CB-041
- 作業ファイル: `skills/harness-init/SKILL.md` Step 8a-b
- 作業内容:
  - `codex --version` で CLI 存在確認、不在なら `codex_plugin` / `codex_cmux` を選択肢から排除
  - `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` を glob、見つからなければ `codex_plugin` を選択肢から排除
  - 解決したパスを `_config.yml.codex_plugin_path` に保存
- 完了基準: plugin 未インストール環境でも harness-init が失敗せず、ヒアリング選択肢が適切に絞られる
- 依存: T-CB-020

### [T-CB-022] Codex hooks 配置ロジック (P0)
- 対応要件: REQ-CB-020, REQ-CB-021
- 作業ファイル: `skills/harness-init/SKILL.md` Step 8c-e
- 作業内容:
  - `<project>/.codex/hooks.json` を生成（template から）
  - `<project>/.codex/hooks/*.sh` 3 本を配置、chmod 755
  - `<project>/.codex/config.toml` に `[features] codex_hooks=true` を非破壊 append（既存エントリ保全）
- 完了基準:
  - backend=codex_* 選択時のみ生成、backend=claude 時は配置しない
  - 既存の `.codex/config.toml` がある場合は [features] 以外を保持
- 依存: T-CB-013, T-CB-012

### [T-CB-023] bridge script 配置 (P0)
- 対応要件: REQ-CB-003
- 作業ファイル: `skills/harness-init/SKILL.md` Step 8f
- 作業内容: `.harness/scripts/codex-progress-bridge.sh` を配置、chmod 755
- 完了基準: backend=codex_* 選択時に配置される
- 依存: T-CB-011

### [T-CB-024] hearing-questions Round 2 更新 (P0)
- 対応要件: REQ-CB-050
- 作業ファイル:
  - `skills/harness-init/references/hearing-questions.md`
  - `skills/harness-init/references/hearing-questions.ja.md`
- 作業内容:
  - Round 2（generator backend 選択）の選択肢に `codex_cmux` 追加（復活）
  - 各選択肢の説明文を更新（`codex_plugin` = 推奨、`codex_cmux` = 可視性重視、`claude` = baseline）
  - F2 削除コメントの撤回記述を追加
  - Codex CLI / plugin 不在検出時の follow-up（T-CB-021 連携）を明記
- 完了基準: dogfood round 3 で選択肢が正しく機能、非実装 backend が除外される
- 依存: T-CB-021

### [T-CB-025] hooks-templates / rubric-presets 等の整合 (P1)
- 対応要件: 既存 templates の一貫性
- 作業ファイル:
  - `skills/harness-init/references/hooks-templates.md` / `.ja.md`
  - その他 templates
- 作業内容: 本仕様で追加された生成物（`.codex/hooks.json` 等）を templates 一覧に反映、重複説明の整理
- 完了基準: harness-init の生成物リストが本仕様 §2.1 と一致
- 依存: T-CB-022, T-CB-023

---

## M-CB-D: harness-plan 改修（Phase B-3 中盤）

### [T-CB-030] Planner fresh 分割の実装 (P0)
- 対応要件: REQ-020-M, REQ-021-M, REQ-CB-010, REQ-CB-012
- 作業ファイル: `skills/harness-plan/SKILL.md`
- 作業内容:
  - Step 2（product-spec 対話）: 1 Planner session、user 応答を progress.md に逐次 append
  - Step 3（roadmap 生成）: 別 fresh Planner session
  - Step 5（contract 雛形）: sprint 毎 fresh Planner（並列可）
- 完了基準:
  - 各 step が独立 Task() 呼び出しになっている
  - 中間状態が progress.md / _state.json に記録される
- 依存: T-CB-010

### [T-CB-031] contract 雛形並列生成の実装 (P1)
- 対応要件: REQ-CB-011
- 作業ファイル: `skills/harness-plan/SKILL.md`
- 作業内容:
  - Task tool を並列呼び出し（Claude Code がサポートする場合）
  - 並列不可な場合は逐次 fallback（順序依存なしなので並列が望ましい）
- 完了基準:
  - 5 sprint 以上の Epic で並列実行された場合、合計時間が逐次の 1/2 以下
  - 並列失敗時も逐次で正常完了
- 依存: T-CB-030

### [T-CB-032] Planner 用 prompt-file テンプレ整備 (P0)
- 対応要件: REQ-CB-031
- 作業ファイル: `skills/harness-plan/references/prompt-templates/`
  - `planner-interview.md` / `.ja.md`
  - `planner-roadmap.md` / `.ja.md`
  - `planner-contract.md` / `.ja.md`
- 作業内容: 各 Planner 呼び出し用の task-specific prompt template を作成。role 知識は重複させず、 `.claude/agents/planner.md` を参照する形
- 完了基準: 3 template が揃い、Orchestrator が sprint 変数を差し込んで使える
- 依存: T-CB-030

### [T-CB-033] harness-plan の Boot Sequence 整合 (P1)
- 対応要件: REQ-072 踏襲
- 作業ファイル: `skills/harness-plan/SKILL.md` 冒頭
- 作業内容: Boot Sequence を各 Planner invocation 前にも実行するロジック（既存 sub-agent が Boot Sequence 実施するので Orchestrator 側の確認のみ）
- 完了基準: compact 発動 → restart 後に /harness-plan が resume 可能
- 依存: T-CB-030

---

## M-CB-E: harness-loop 改修（Phase B-3 後半）

### [T-CB-040] Generator 呼び出しの backend 分岐実装 (P0)
- 対応要件: REQ-060-M, REQ-CB-032
- 作業ファイル: `skills/harness-loop/SKILL.md`
- 作業内容: 本仕様 §3.3 の擬似コードを実装
  - `claude` / `codex_plugin` / `codex_cmux` の 3 分岐
  - `codex_plugin` は `node {path} task --cwd {ws} --json --write --fresh --model {m} --prompt-file {pf}` を Bash で同期呼び出し
  - `codex_cmux` は cmux-delegate 利用
- 完了基準:
  - 各 backend で 1 iter 完走可能
  - report.json が所定パスに生成される
- 依存: T-CB-010, T-CB-011, T-CB-020

### [T-CB-041] report.json fallback ロジック (P0)
- 対応要件: REQ-CB-002
- 作業ファイル: `skills/harness-loop/SKILL.md`
- 作業内容:
  - Generator 呼び出し後、report.json の存在確認
  - 欠落時は `git diff --name-only HEAD` で touchedFiles を再構築し、report.json を自前生成
  - `progress.md` に `[WARN] codex-report missing, fell back to git diff` を記録
- 完了基準:
  - T-CB-test-3 のシナリオで fallback が動作
  - WARN 行が progress.md に追記される
- 依存: T-CB-040

### [T-CB-042] bridge script 呼び出しの統合 (P0)
- 対応要件: REQ-073-M, REQ-CB-003
- 作業ファイル: `skills/harness-loop/SKILL.md`
- 作業内容: Generator 呼び出し後に `cat {report} | codex-progress-bridge.sh --phase ... --iter ... --agent ...` を Bash
- 完了基準: `claude` backend でも `codex_*` backend でも progress.md 行フォーマットが統一される
- 依存: T-CB-011, T-CB-040

### [T-CB-043] Generator 用 prompt-file テンプレ整備 (P0)
- 対応要件: REQ-CB-031
- 作業ファイル: `skills/harness-loop/references/prompt-templates/`
  - `generator-negotiation.md` / `.ja.md`
  - `generator-implementation.md` / `.ja.md`
- 作業内容: Phase B（Negotiation）と Phase C（Implementation）の prompt template、task-specific 部分のみ（role contract は agent 定義参照）
- 完了基準: Orchestrator が iter 変数を差し込んで使える
- 依存: T-CB-010

### [T-CB-044] bridge / hook scripts の ユニットテスト (P2)
- 対応要件: NFR-CB-003（test mode）
- 作業ファイル: `skills/harness-loop/references/scripts/tests/`
- 作業内容:
  - fixture JSON (report.json サンプル) を用意
  - bridge script に fixture を食わせて期待の progress.md / _state.json が生成されることを確認
  - `HARNESS_TEST_MODE=1` で no-op 動作確認
- 完了基準: CI 的に実行可能な簡易テスト suite が揃う
- 依存: T-CB-011, T-CB-012

---

## M-CB-F: dogfood 検証（Phase B-4）

### [T-CB-050] zen-base で /harness-init → /harness-plan 実走 (P0)
- 対応要件: 全体 E2E
- 作業内容:
  - zen-base の既存 `.harness/` / `.claude/agents/` / `.codex/agents/` / CLAUDE.md harness 追記を退避または削除
  - 新 skill（本仕様の成果物）で `/harness-init` 再実行
  - 生成物を本仕様 §2.1 と照合
  - `codex_plugin` backend 選択、`generator_backend=codex_plugin` 状態で `/harness-plan` を実走
  - product-spec 対話 → roadmap → contract × N が生成されることを確認
  - 途中でバグ / UX issue が出たらリストアップ、別 PR 対応 or 本 PR 内 fix
- 完了基準:
  - 生成物完備
  - Planner fresh 分割が観測される（progress.md で確認可能）
  - 次工程 `/harness-loop` に進める状態
- 依存: M-CB-B / M-CB-C / M-CB-D / M-CB-E 全完了

---

## M-CB-G: Future-work 整理（Phase 以降、本 PR scope 外）

### [T-CB-060] Codex Write interception 移行準備 (P2)
- 対応要件: 本仕様 §11
- 作業内容:
  - Codex CLI / plugin の Write interception 実装状況を定期ウォッチ
  - 実装され次第、Codex 側 hook で Write を捕捉するスクリプトを追加
  - Orchestrator bridge を縮小（fallback 役のみに）
- 完了基準: Write interception が安定提供された段階で新 PR

### [T-CB-061] `--resume-last` opt-in 機構 (P2)
- 対応要件: ASM-CB-003
- 作業内容:
  - `_config.yml.codex_resume_strategy` を `"fresh"` / `"resume-last"` 切替式に
  - token コスト実測の材料を提供
- 完了基準: user が opt-in で切替可能、resume-last 時も GAN 純度が保てる運用を確立

### [T-CB-062] Multi-backend 拡張（gemini_plugin 等） (P2)
- 対応要件: NFR-CB-001
- 作業内容: 本仕様の拡張性確認用途。新 backend を追加した際に必要な変更が Generator 起動コマンド 1 行 + config schema のみであることを検証
- 完了基準: 別 backend を実験的に追加し、動作確認（本 PR scope 外）

---

## 依存関係グラフ（抜粋）

```
T-CB-001 (仕様反映判断)
  ├── T-CB-002 (requirement.md 書き換え) ── T-CB-003 (design.md) ── T-CB-004 (tasks.md)
  │
  └── 以下 Phase B-3 / B-4 へ
      ├── T-CB-010 (role contract 化) ─┬── T-CB-030 (harness-plan 改修)
      ├── T-CB-011 (bridge script)     │   ├── T-CB-031 (並列化)
      ├── T-CB-012 (codex hooks)       │   ├── T-CB-032 (prompt templates)
      ├── T-CB-013 (hooks.json)        │   └── T-CB-033 (Boot Sequence)
      │                                 │
      ├── T-CB-020 (_config schema)    ├── T-CB-040 (backend 分岐)
      ├── T-CB-021 (discovery)         │   ├── T-CB-041 (fallback)
      ├── T-CB-022 (hooks 配置)        │   ├── T-CB-042 (bridge 呼び出し)
      ├── T-CB-023 (bridge 配置)       │   ├── T-CB-043 (prompt templates)
      ├── T-CB-024 (hearing update)    │   └── T-CB-044 (unit test)
      ├── T-CB-025 (template 整合)     │
      │                                 │
      └──────────────────────┬──────────┘
                              │
                              ↓
                    T-CB-050 (zen-base dogfood)
```

# 設計書: harness-codex-backend

親仕様 `.specs/harness-suite/design.md` に対する差分設計。本仕様は親を**置換ではなく追記 / 修正**する位置付け。

## 1. アーキテクチャ概要

### 1.1 γ (file-mediated peer processes) の採用

```
┌──────────────────────────────────────────────────────┐
│ Orchestrator (/harness-loop skill, main Claude)      │
│   ・seed files を書く (contract / shared_state)     │
│   ・Generator を backend 別に起動                    │
│   ・Generator が書いた report を読む                │
│   ・progress.md / _state.json を更新                 │
│   ・Evaluator に同様の流れで渡す                    │
└─────┬────────────────────────────────────────────────┘
      │ write prompt-file
      ↓
  ┌───┴───────────────────┬──────────────────────┐
  │                        │                      │
  ↓                        ↓                      ↓
[Task tool]          [Bash to            [cmux-delegate]
                     codex-companion]    
Claude sub-agent     Codex plugin        Codex in cmux pane
(fresh context)      (fresh thread)      (fresh session)
                                          
                                          │
  ↓                        ↓               ↓
全て同じ出力契約: feedback/generator-<iter>.md
             + feedback/generator-<iter>-report.json
```

**中核原則**:
- すべての Agent は毎 invocation で fresh start（context 持ち越しなし）
- State は**すべてファイル**（git 管理下）に置く
- Agent 間の直接通信は存在しない（Orchestrator を経由）
- Backend の違いは「Generator 起動コマンド 1 行だけ」

### 1.2 親仕様との関係図

```
.specs/harness-suite/               ← 親仕様（M1〜M4 で実装済み）
  ├ requirement.md                   [REQ-001 〜 REQ-101]
  ├ design.md                        [§1〜§12]
  └ tasks.md                         [T-001 〜 T-055]

.specs/harness-codex-backend/        ← 本仕様（差分）
  ├ requirement.md                   [REQ-060-M, REQ-CB-001 〜 REQ-CB-050]
  ├ design.md (this)                 
  └ tasks.md                         [T-CB-001 〜 T-CB-NNN]
```

親仕様は基本維持、本仕様で明示的に `-M` マークした要件のみ書き換える。

## 2. ディレクトリ / ファイル構成の変化

### 2.1 harness-init 生成物の増減

```
<project>/
├── .claude/
│   ├── agents/
│   │   ├── planner.md                         [親] role contract 化で内容更新
│   │   ├── generator.md                       [親] 同上
│   │   └── evaluator.md                       [親] 同上
│   └── settings.json                          [親] hook は既存、変更なし
│
├── .codex/                                    [★] 本仕様で拡充
│   ├── config.toml                            [既存] [features] codex_hooks=true を追記
│   ├── agents/
│   │   ├── planner.toml                       [親] developer_instructions 更新
│   │   ├── generator.toml                     [親] 同上
│   │   └── evaluator.toml                     [親] 同上
│   ├── hooks.json                             [★新規]
│   └── hooks/                                 [★新規]
│       ├── inject-harness-context.sh
│       ├── tier-a-guard-codex.sh
│       └── codex-bash-log.sh
│
├── .harness/
│   ├── _config.yml                            [★] codex_plugin_path / codex_generator_model 追加
│   ├── scripts/
│   │   ├── progress-append.sh                 [親] 変更なし
│   │   ├── stop-guard.sh                      [親] 変更なし
│   │   ├── tier-a-guard.sh                    [親] 変更なし
│   │   ├── mcp-allowlist.sh                   [親] 変更なし
│   │   └── codex-progress-bridge.sh           [★新規]
│   └── (以下は harness-plan / harness-loop 実行時に生成)
│
└── CLAUDE.md                                  [親] 変更なし
```

### 2.2 Generator 出力物（ファイル規約）

```
.harness/<epic>/sprints/sprint-<n>-<feature>/feedback/
├── generator-<iter>.md                        [親仕様: 既存]
└── generator-<iter>-report.json               [★新規 本仕様 REQ-CB-001]
```

## 3. 各スキルの詳細設計差分

### 3.1 harness-init の変更

**処理フロー追加ステップ**:

```
親仕様のステップ 1-7 に加えて:

8. generator_backend が codex_* の場合:
   a. codex --version で Codex CLI 存在確認（不在ならエラー提示、選択リセット）
   b. ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs を glob
      → _config.yml.codex_plugin_path に保存
   c. <project>/.codex/hooks.json を生成
   d. <project>/.codex/hooks/*.sh を配置（chmod 755）
   e. <project>/.codex/config.toml に [features] codex_hooks=true を非破壊追記
   f. .harness/scripts/codex-progress-bridge.sh を配置

9. _config.yml に以下を追記:
   codex_plugin_path: <resolved-path> | null
   codex_generator_model: gpt-5.4
   codex_resume_strategy: fresh   # 将来 "resume-last" 切替のための placeholder
```

### 3.2 harness-plan の変更（Planner fresh 分割）

**現行のステップ（親仕様 §3.2）**:
```
1 Planner sub-agent で以下を通し実行:
  - product-spec 対話
  - roadmap 生成
  - contract 雛形 × N
```

**本仕様のステップ**:
```
Step 2: product-spec.md 対話
  - Task(planner-interview, prompt=...)
  - このセッションは対話長めだが、user 応答を progress.md に逐次 append
  - product-spec.md 完成で Planner session 終了

Step 3: roadmap.md 生成（★別 fresh Planner）
  - Task(planner-roadmap, prompt="read product-spec.md and generate roadmap.md")
  - 入力: product-spec.md のみ
  - 出力: roadmap.md
  - Planner session 終了

Step 4: user に roadmap 承認

Step 5: contract 雛形生成（★sprint 毎 fresh Planner、並列可）
  for sprint in roadmap.sprints:
    tasks.append(Task(
      subagent_type="planner-contract",
      prompt=f"read product-spec.md + roadmap.md + sprint={sprint}, "
             f"generate contract.md template"
    ))
  
  # 並列実行（Task tool 並列サポート時）
  results = parallel_await(tasks)

Step 6: tracker に応じて Issue 起票（親仕様 REQ-023 踏襲）
```

**Context 削減効果**: Planner 単一 session の線形膨張（product-spec + roadmap + N sprint contract）が **sprint 1 個分の定数**に。

### 3.3 harness-loop の変更（backend 分岐 + bridge）

**Generator 呼び出しロジック** (擬似コード):

```python
def invoke_generator(iter, phase):
    backend = config["generator_backend"]
    prompt_file = build_prompt_file(iter, phase)
    
    if backend == "claude":
        # Task tool で Claude sub-agent 起動（既存）
        result = Task(subagent_type="generator",
                      prompt=read_file(prompt_file))
        # report.json は sub-agent が書く、hook も自動発火
    
    elif backend == "codex_plugin":
        model = config["codex_generator_model"]
        plugin_path = config["codex_plugin_path"]
        workspace = get_workspace_root()
        
        # 同期 Bash で Codex task 呼び出し
        json_out = bash(
            f'node "{plugin_path}" task '
            f'--cwd "{workspace}" --json --write --fresh '
            f'--model "{model}" --prompt-file "{prompt_file}"'
        )
        # Codex が report.json を書く（契約）
    
    elif backend == "codex_cmux":
        # cmux-delegate で別 pane に Codex セッションを張る
        # 完了待ちは cmux-delegate の機構に従う
        run_cmux_delegate("codex", prompt_file)
    
    # ★ backend 非依存の後処理
    report_path = f"feedback/generator-{iter}-report.json"
    if not exists(report_path):
        # REQ-CB-002 フォールバック
        build_report_from_git_diff(report_path)
        log_warning("codex-report missing, fell back to git diff")
    
    # bridge で progress.md / _state.json 更新
    bash(f"cat {report_path} | .harness/scripts/codex-progress-bridge.sh "
         f"--phase {phase} --iter {iter} --agent generator-{backend}")
```

**Evaluator 呼び出し**: Claude 固定のため変更なし（親仕様踏襲）。

### 3.4 harness-rules-update の変更

変更なし（親仕様踏襲）。

## 4. 主要データ構造

### 4.1 `feedback/generator-<iter>-report.json` スキーマ（新規）

```json
{
  "$schema": "report-v1",
  "status": "done" | "blocked",
  "touchedFiles": ["relative/path/a.ts", "relative/path/b.ts"],
  "summary": "one-line description of what was done",
  "blocker": null | "reason if status=blocked",
  "codex_thread_id": "<thread-uuid>" | null
}
```

- `touchedFiles` は workspace root からの **相対パス**。Codex が `/private/tmp/...` 等の firmlink-resolved な絶対パスを返した場合、Orchestrator が相対化する。
- `codex_thread_id` は Codex backend 時のみ値が入る（将来の resume-last オプション用）。claude backend では常に null。
- fallback 生成時は `status: "done"`, `summary: "(fallback: git diff)"` で埋める。

### 4.2 `_config.yml` 追加フィールド

```yaml
# 親仕様の既存フィールドに加えて:
codex_plugin_path: "/Users/.../codex-companion.mjs"  # null if not installed
codex_generator_model: "gpt-5.4"
codex_resume_strategy: "fresh"                        # future: "resume-last"
```

### 4.3 `_state.json` 追加フィールド

親仕様のスキーマに加えて:

```json
{
  "codex_thread_ids": {
    "<sprint-key>": {
      "<iter>": "019d9510-ee24-..."
    }
  }
}
```

- Codex backend 時のみ populate
- Ralph / resume で再開時に `--resume-last` 的な最適化を選ぶ際の情報源（将来用）

### 4.4 `.codex/hooks.json` スキーマ

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "startup|resume",
      "hooks": [{
        "type": "command",
        "command": "$CODEX_REPO_ROOT/.codex/hooks/inject-harness-context.sh",
        "timeout": 5
      }]
    }],
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CODEX_REPO_ROOT/.codex/hooks/tier-a-guard-codex.sh",
        "timeout": 5
      }]
    }],
    "PostToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CODEX_REPO_ROOT/.codex/hooks/codex-bash-log.sh",
        "timeout": 5
      }]
    }]
  }
}
```

`$CODEX_REPO_ROOT` は Codex が期待する「repo root 解決」プレースホルダとし、hook スクリプト側で `git rev-parse --show-toplevel` で実解決する。

## 5. Orchestrator Bridge の処理フロー

### 5.1 `codex-progress-bridge.sh`

```bash
#!/usr/bin/env bash
# Input:  stdin = report.json
# Args:   --phase <p> --iter <n> --agent <name>
# Effect: append lines to .harness/progress.md, update _state.json

set -eu

[ "${HARNESS_TEST_MODE:-0}" = "1" ] && exit 0

INPUT=$(cat)
PHASE=$1; ITER=$2; AGENT=$3   # arg parsing (getopts 等で正確に)

STATUS=$(jq -r '.status // "unknown"' <<< "$INPUT")
THREAD=$(jq -r '.codex_thread_id // empty' <<< "$INPUT")
SUMMARY=$(jq -r '.summary // empty' <<< "$INPUT")
TS=$(date -u +%FT%TZ)

# per-file 追記
jq -r '.touchedFiles[]?' <<< "$INPUT" | while IFS= read -r FILE; do
  [ -z "$FILE" ] && continue
  # 相対パス化（必要なら readlink -f + basename workspace）
  echo "[$TS] tool=Codex file=$FILE phase=$PHASE iter=$ITER agent=$AGENT" \
    >> .harness/progress.md
done

# 統合 summary 行
COUNT=$(jq '.touchedFiles | length' <<< "$INPUT")
echo "[$TS] codex-done phase=$PHASE iter=$ITER agent=$AGENT thread=$THREAD files=$COUNT status=$STATUS summary=\"$SUMMARY\"" \
  >> .harness/progress.md

# _state.json atomic update
jq --arg tid "$THREAD" --argjson iter "$ITER" '
  .last_agent = "\($iter | tostring)|'"$AGENT"'"
  | if $tid != "" then .codex_thread_ids[.current_sprint|tostring][.iteration|tostring] = $tid else . end
' .harness/_state.json > .harness/_state.json.tmp
mv .harness/_state.json.tmp .harness/_state.json
```

### 5.2 backend 非依存の処理順序

```
iter 完了時:
  1. Generator 呼び出し完了（backend 別）
  2. report.json の存在確認 → なければ fallback 生成
  3. bridge でのファイル追記（progress.md + _state.json）
  4. git add -A && git commit （既存 REQ-077）
  5. Evaluator 呼び出し
  6. evaluator 評価結果で pass/fail 判定
  7. fail なら iter++ で Generator に戻る
  8. pass なら PR 作成（既存 REQ-033）
```

## 6. 既存資産との接続

### 6.1 Claude Code の既存 hook との共存

Claude 側 `PostToolUse(Edit|Write)` hook（親仕様 REQ-073）は `generator_backend=claude` の時にのみ有効な progress 記録経路として継続使用。Codex backend 時も hook 自体は登録されたままだが、Codex の編集は hook を発火させないため実質無効化される（既存機構を壊さない）。

### 6.2 cmux-delegate との連携

`codex_cmux` backend は既存 `cmux-delegate` スキルを利用。cmux セッション内で `codex` を起動し、prompt-file 経由で指示する。cmux-delegate 側で完了通知を受けた後、workspace 内に書かれた report.json を Orchestrator が読む。

### 6.3 既存 Tier-A ガードとの二重化

親仕様 REQ-082 の `.harness/scripts/tier-a-guard.sh`（Claude PreToolUse(Bash)）に加えて、本仕様 REQ-CB-020 の `tier-a-guard-codex.sh`（Codex PreToolUse(Bash)）で**二重にブロック**する。双方とも `.harness/tier-a-patterns.txt` を参照し、パターン定義は共通化。

## 7. Traceability Matrix

| 新規 / 修正 REQ | 該当設計セクション | 関連親 REQ |
|---|---|---|
| REQ-CB-001 | §2.2, §4.1 | REQ-030, REQ-074 |
| REQ-CB-002 | §3.3 フォールバック, §5.1 | REQ-077 |
| REQ-CB-003 | §5.1 | REQ-073 |
| REQ-CB-010 | §3.2 Step 5 | REQ-021 |
| REQ-CB-011 | §3.2 Step 5 (parallel_await) | REQ-022 |
| REQ-CB-012 | §3.2 Step 2-5 全体 | REQ-020 |
| REQ-CB-020 | §2.1, §4.4 | REQ-073, REQ-082 |
| REQ-CB-021 | §3.1 Step 8e | — |
| REQ-CB-022 | §1.1, §2.2, §3.3 | — |
| REQ-CB-030 | §3.3 prompt-file | REQ-060 |
| REQ-CB-031 | §3.3 prompt 構造 | — |
| REQ-CB-032 | §3.3 `--model` 明示 | REQ-060 |
| REQ-CB-033 | §2.1 | REQ-061 |
| REQ-CB-040 | §3.1 Step 8b | ASM-003 |
| REQ-CB-041 | §3.1 Step 8a | ASM-003 |
| REQ-CB-050 | §1.1 backend 一覧 | REQ-060 |
| REQ-060-M | §1.1, §3.3 | REQ-060 |
| REQ-020-M / REQ-021-M | §3.2 | REQ-020, REQ-021 |
| REQ-073-M | §3.3 bridge, §5.1 | REQ-073 |

## 8. Technology Stack（差分）

親仕様 §10 に以下を追加:

| Layer | 本仕様の追加採用技術 | 根拠 |
|---|---|---|
| Codex Plugin | `openai/codex-plugin-cc` 1.0.3+ | Codex 呼び出しの主経路 |
| Codex CLI | `codex-cli` 0.120.0+ | `codex_hooks` feature flag 前提 |
| Bridge | Bash + jq（既存） | backend 非依存の report.json → progress.md 代行 |
| cmux integration | 既存 cmux-delegate | 可視性モード |

## 9. Security Design（差分）

### 9.1 Tier-A 二重ガード

- 親仕様 REQ-082 の Claude 側 `PreToolUse(Bash)` + tier-a-guard.sh
- 本仕様 REQ-CB-020 の Codex 側 `PreToolUse(Bash)` + tier-a-guard-codex.sh
- 双方とも `.harness/tier-a-patterns.txt` を共有

### 9.2 Trust Gate の扱い

Codex plugin は workspace を silent に trust list 追加（実機確認済み）。これにより harness 運用フローが stop せずに進行するが、裏を返せば user が trust の可視性を失う。対策:

- `harness-init` 完了時の確認表示に「Codex plugin 経由の呼び出しは新規ディレクトリを自動で trust list に追加します」と注意書き
- `~/.codex/config.toml` の trust list は user が任意で編集可能であることを CLAUDE.md に記載

### 9.3 Codex 側 hook が介在しない編集の観測

本仕様時点で Codex の Write は hook で捕捉できない。悪意あるコード生成（意図しない secret 埋め込み等）の検出は Evaluator の rubric + レビュー時の検証に依存する。Codex 側 Write hook がサポートされ次第、`secret-scan-codex.sh` 的な PostToolUse(Write) hook を追加する（Future work）。

## 10. テスト戦略（差分）

親仕様 §12 に以下を追加:

| テストケース | 内容 | 合格基準 |
|---|---|---|
| T-CB-test-1 | `claude` backend で 1 sprint 完走 | feedback / report.json / progress.md 行 / commit が揃う |
| T-CB-test-2 | `codex_plugin` backend で 1 sprint 完走 | 同上 + codex_thread_id が _state.json に記録される |
| T-CB-test-3 | Codex が report.json 書き忘れるケース（意図的 prompt 省略） | fallback が動作、progress.md に WARN 行が出る |
| T-CB-test-4 | Planner fresh 分割の並列 contract 生成 | 5 sprint の contract が並列で生成される（合計時間 < 逐次時間） |
| T-CB-test-5 | Codex 側 hook の Tier-A ブロック | `rm -rf /` を Codex に試行させた時 PreToolUse が block |
| T-CB-test-6 | Compact 耐性（Orchestrator 側） | iteration 途中で compact 発動 → SessionStart hook で復元 → 継続実行 |

## 11. 既知の制約 / Future Work

| 項目 | 現状 | 将来対応 |
|---|---|---|
| Codex Write hook 未実装 | Orchestrator bridge で代行 | Write interception 実装時に hook-based に移行、bridge は廃止 / 縮小 |
| agent TOML の model 不反映 | Orchestrator が `--model` 明示 | plugin が honor するようになったら `--model` 省略可に |
| Ralph mode の Codex 対応 | headless `claude -p` で Orchestrator が毎 iter 起動。Codex は stateless で毎回 fresh thread | Codex Stop hook が安定化したら self-continuation も検討 |
| `--resume-last` の token 最適化 | 未対応（常に `--fresh`） | opt-in フラグを `_config.yml` に追加、運用実測で切替 |
| その他 MCP backend | スコープ外 | REQ-060 の `other` に属す形で将来対応 |

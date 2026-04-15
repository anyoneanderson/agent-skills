# Resilience スキーマ

コンテキストコンパクト・セッション再起動・プロセスクラッシュを跨いで生き残る 3 ファイルのスキーマ定義。Anthropic 公式の "三点セット"（progress.md + _state.json + git）に観測層（metrics.jsonl）を加えた構成。詳細は `.specs/harness-suite/design.md` §9 を参照。

Boot Sequence（REQ-072）— 全 skill / sub-agent は動作前に以下を必ず読む:

1. `git log --oneline -20`
2. `tail -100 .harness/progress.md`
3. `cat .harness/_state.json`

---

## `.harness/progress.md`（人間可読ログ）

**目的**: 意図・判断・次アクションを自由形式で記録。`/compact` を跨いで生存する（コンテキストウィンドウ外に存在するため）。

**書き手**: 全エージェント（append-only）。`PostToolUse(Edit|Write)` hook で強制。

**形式** — 1 イベント 1 行:

```
[<ISO-8601-UTC>] <event>
```

`<event>` は以下のいずれか:

```
tool=<tool_name> file=<file_path> phase=<phase> iter=<N>
   # PostToolUse hook が Edit|Write で出力

decision: <text>
   # Orchestrator / Planner が不可逆な選択を記録

negotiation: round=<N> agent=<role> summary=<text>
   # 交渉の round ごと要約（生メッセージは feedback/ 側）

evaluation: iter=<N> verdict=<pass|fail> axes="f=0.9 c=0.7 d=0.6 o=0.5"
   # iteration ごとの Evaluator 判定

stop: reason=<max_iter|wall_time|rubric_stagnation|cost_cap|tier_a> detail=<text>
   # Principal Skinner 発動（REQ-080）

restore: from=<source> preserved=<tokens>
   # SessionStart(compact) hook が再注入後に出力
```

**末尾例**:

```
[2026-04-15T09:41:03Z] tool=Write file=src/login.tsx phase=impl iter=3
[2026-04-15T09:41:05Z] tool=Edit file=src/login.test.tsx phase=impl iter=3
[2026-04-15T09:42:14Z] evaluation: iter=3 verdict=fail axes="f=0.6 c=0.8 d=0.7 o=0.6"
[2026-04-15T09:42:14Z] decision: iter=3 failed Functionality threshold; generator to retry
[2026-04-15T09:45:02Z] restore: from=SessionStart(compact) preserved=100-tail-lines
```

**読み取りルール**:
- Tail ベース。ファイル全体をパースしない — `tail -100` が契約
- 各行は情報提供であり実行可能指示ではない。progress.md のみから state を再構成してはならず、必ず `_state.json` と照合
- 未知の形式の行は無視（前方互換性）

**ローテーション**: 1 MiB 超過時は `progress.md.<N>.old` にリネームして新規開始。ヘッダに過去セグメントへのリンクチェーンを残す。

---

## `.harness/_state.json`（機械可読カーソル）

**目的**: オーケストレーション位置の single source of truth。完全に決定論的にパース可能で、`harness-loop` / hooks / Autonomous Ralph が次アクションを決定するために使う。

**書き手**: Orchestrator のみ（harness-loop）。iteration ごとに 1 回更新。

**スキーマバージョン**: 1

```json
{
  "schema_version": 1,
  "current_epic": "auth-suite",
  "current_sprint": 2,
  "phase": "impl",
  "iteration": 3,
  "max_iterations": 8,
  "max_wall_time_sec": 28800,
  "max_cost_usd": 20.0,
  "cumulative_cost_usd": 4.27,
  "start_time": "2026-04-15T22:00:00Z",
  "last_agent": "generator",
  "next_action": "evaluator:score-iter-3",
  "last_commit": "2013f7b8c9e...",
  "features_pass_fail": [
    {
      "feature": "login",
      "functionality": "fail",
      "craft": "pass",
      "design": "pass",
      "originality": "pass"
    }
  ],
  "completed": false,
  "pending_human": false,
  "aborted_reason": null,
  "mode": "autonomous-ralph",
  "rubric_stagnation_count": 0
}
```

### フィールドリファレンス

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `schema_version` | int | yes | bump 時は migrate。初期値 1 |
| `current_epic` | string | yes | `.harness/` 配下のディレクトリ名 |
| `current_sprint` | int | yes | 1-indexed sprint 番号 |
| `phase` | enum | yes | `negotiation \| impl \| evaluation \| pr \| done` |
| `iteration` | int | yes | 初回前は 0、Generator → Evaluator 1 サイクルごとに increment |
| `max_iterations` | int | yes | Principal Skinner 上限（デフォルト 8） |
| `max_wall_time_sec` | int | yes | Principal Skinner 時間上限（デフォルト 28800 = 8h） |
| `max_cost_usd` | number | yes | Principal Skinner コスト上限（デフォルト 20.0） |
| `cumulative_cost_usd` | number | yes | metrics.jsonl からの累積合計 |
| `start_time` | ISO-8601 | yes | 現 sprint が negotiation に入った時刻 |
| `last_agent` | enum | yes | `planner \| generator \| evaluator \| orchestrator` |
| `next_action` | string | yes | 次実行者へのヒント（自由記述） |
| `last_commit` | string\|null | yes | 最新 iteration の commit SHA |
| `features_pass_fail` | array | yes | 現 sprint の feature × 軸 × pass/fail |
| `completed` | bool | yes | epic 内全 sprint 完了時のみ true |
| `pending_human` | bool | yes | Tier-A guard 発動時 / 曖昧要求（v2）時に true |
| `aborted_reason` | string\|null | yes | Principal Skinner 発動時に non-null |
| `mode` | enum | yes | `interactive \| continuous \| autonomous-ralph \| scheduled` |
| `rubric_stagnation_count` | int | yes | 連続で rubric が改善しなかった iteration 数（どれかの軸が向上した時点で 0 にリセット） |

> `stop_hook_active` は `_state.json` の永続フィールドでは **ない**。Claude
> Code の hook runner が Stop hook の stdin payload に乗せて渡す再帰防止用
> フラグで、`stop-guard.sh` はそれを `jq -r '.stop_hook_active'` で読むだけ。
> 将来的に永続カウンタが必要になった場合はここに新フィールドとして追加する。

### 更新ルール

- アトミック書き込み: `_state.json.tmp` → `fsync` → `rename`。部分書き込みを観測可能にしない
- iteration 終了ごとに更新: `iteration` / `last_agent` / `next_action` / `last_commit` / `cumulative_cost_usd` / 該当 `features_pass_fail`
- 削除しない。abort 時も `aborted_reason` を設定し `completed: false` のまま残す。resume はユーザの意識的判断に委ねる
- `.stop_hook_active` は `_state.json` ではなく Stop hook の stdin payload
  から `stop-guard.sh` が読むフィールド。Claude Code が前回の
  `{"decision":"block"}` に続く再帰呼び出しで `true` をセットするので、
  次回の呼び出しは短絡して exit 0 する。こちら側での永続管理は不要

### スキーマ migration

`schema_version` が上がる時、`harness-init` は `.harness/scripts/migrate-<n>-to-<m>.sh` を配布し既存 `_state.json` を書き換える。旧ファイルは `_state.json.v<N>.bak` にバックアップ。

---

## `.harness/metrics.jsonl`（観測、REQ-090）

**目的**: iteration ごとのメトリクスをコスト管理・傾向分析に使う。JSON Lines なので tail reader / OTLP exporter でストリーム処理可能。

**書き手**: Orchestrator が iteration 終了時に 1 行 append。

**スキーマ** — 1 行 1 オブジェクト:

```json
{
  "ts": "2026-04-15T09:42:14Z",
  "iter": 3,
  "sprint": 2,
  "agent": "generator",
  "duration_ms": 18420,
  "input_tokens": 12450,
  "output_tokens": 2180,
  "cost_usd": 0.23,
  "rubric_scores": { "functionality": 0.8, "craft": 0.7, "design": 0.6, "originality": 0.5 },
  "tool_calls": 14,
  "tool_failures": 1
}
```

### フィールドリファレンス

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `ts` | ISO-8601 | yes | iteration 終了時刻 |
| `iter` | int | yes | 出力時の `_state.json.iteration` と一致 |
| `sprint` | int | yes | `_state.json.current_sprint` と一致 |
| `agent` | string | yes | この iteration の主担当エージェント |
| `duration_ms` | int | yes | iteration 壁時計時間 |
| `input_tokens` | int | no | モデルが報告しない場合は空 |
| `output_tokens` | int | no | 同上 |
| `cost_usd` | number | yes | iteration コスト。`cumulative_cost_usd` に加算される |
| `rubric_scores` | object | yes | 軸 → スコア ∈ [0, 1] |
| `tool_calls` | int | yes | この iteration での総 tool 呼び出し回数 |
| `tool_failures` | int | yes | うち non-zero / エラー返却した回数 |

**集計**: `_state.json.cumulative_cost_usd` が累積合計の正本。read 時に metrics.jsonl を再集計してはならない（カーソルを信頼する）。

**OTLP エクスポート（REQ-092、任意）**: `.harness/scripts/metrics-exporter.sh` がこのファイルを tail して `_config.yml.otlp_endpoint` へ POST。endpoint 未設定または `hook_level != strict` なら no-op。

---

## Resume / Recovery プロトコル

skill が再起動した時（新 session / `/compact` / Ralph fresh iter / クラッシュ復旧）:

```
1. Boot Sequence 実行（git log -20, progress.md tail -100, _state.json cat）
2. _state.json.completed == true なら:
     sprint / epic 完了済み。新 epic か新 sprint か、または終了を判断
3. _state.json.aborted_reason != null なら:
     Principal Skinner で停止済み。autonomous モードでは自動 resume しない
     ユーザの明示的アクションを要求
4. _state.json.pending_human == true なら:
     Tier-A 発動または曖昧要求の保留中。停止してユーザへ提示
5. 上記いずれでもなければ:
     _state.json.phase から再開、`next_action` をヒントに該当エージェントを
     再起動（Planner / Generator / Evaluator）
```

**保証**: ステップ 1〜5 はこの 3 ファイル + git のみで完結する。プロセスメモリや過去 session コンテキストは不要。この契約は T-054 で検証される。

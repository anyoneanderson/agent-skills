# Autonomous Ralph

REQ-078 と REQ-079 を扱う。`autonomous-ralph` 実行モードは `harness-loop` を
headless で回し、各 iteration を独立 Claude プロセスで実行する。
iteration 間の記憶は `progress.md` + `_state.json` + git + `metrics.jsonl`
の 4 ファイルのみ。"Ralph" は checkpoint された状態に対して fresh agent を
繰り返し起動するこのパターンの通称。

## なぜ iteration 毎に fresh context か

単一の長時間 `claude -p --continue` セッションはコンテキスト蓄積で
compaction を引き起こす。harness ループでは Generator 出力・Evaluator
採点・ツール出力が毎 iter 積層するため影響が大きい。iter 毎再起動で
drift を排除する:

- 各 iter は 3 つの永続ファイルのみを読む
- Principal Skinner 条件が唯一の生存する iter 跨ぎ状態
- 再現性: 過去 iter の入力を再実行すれば同一出力クラスが得られる
  （モデル温度の範囲で）

トレードオフ: iter 毎の Boot Sequence コスト。sprint 全体（デフォルト 8
iter）で amortise すると Boot は経過時間の約 1%。

## ラッパースクリプトテンプレート

loop 開始時にユーザが `autonomous-ralph` を選んだ時点で
`.harness/scripts/ralph-loop.sh` として配置する。harness-init がベースを
出荷し、harness-loop Step 2 はモード選択時のみ本ファイルを書き出す。

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE=".harness/_state.json"
PROGRESS=".harness/progress.md"

command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }
command -v claude >/dev/null || { echo "claude CLI required" >&2; exit 2; }
[[ -f $STATE ]] || { echo "_state.json missing; run /harness-init + /harness-plan first" >&2; exit 2; }

while :; do
  # Principal Skinner ゲート — すべて _state.json から読む
  completed=$(jq -r '.completed // false' "$STATE")
  aborted=$(jq -r '.aborted_reason // empty' "$STATE")
  pending_human=$(jq -r '.pending_human // false' "$STATE")
  iter=$(jq -r '.iteration // 0' "$STATE")
  max_iter=$(jq -r '.max_iterations // 8' "$STATE")
  start_time=$(jq -r '.start_time // empty' "$STATE")
  max_wall=$(jq -r '.max_wall_time_sec // 28800' "$STATE")
  cost=$(jq -r '.cumulative_cost_usd // 0' "$STATE")
  max_cost=$(jq -r '.max_cost_usd // 20' "$STATE")
  stag=$(jq -r '.rubric_stagnation_count // 0' "$STATE")
  max_stag=$(jq -r '.rubric_stagnation_n // 3' "$STATE")

  if [[ $completed == true ]]; then
    printf '[%s] ralph: epic complete, exiting\n' "$(date -u +%FT%TZ)" >> "$PROGRESS"
    exit 0
  fi
  if [[ -n $aborted ]]; then
    printf '[%s] ralph: aborted reason=%s; human resume required\n' "$(date -u +%FT%TZ)" "$aborted" >> "$PROGRESS"
    exit 1
  fi
  if [[ $pending_human == true ]]; then
    printf '[%s] ralph: pending_human=true; halting for approval\n' "$(date -u +%FT%TZ)" >> "$PROGRESS"
    exit 1
  fi
  if (( iter >= max_iter )); then
    jq '.aborted_reason = "max_iterations"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    printf '[%s] stop: reason=max_iter iter=%s\n' "$(date -u +%FT%TZ)" "$iter" >> "$PROGRESS"
    exit 1
  fi
  # wall_time
  if [[ -n $start_time ]]; then
    elapsed=$(( $(date -u +%s) - $(date -u -j -f %FT%TZ "$start_time" +%s 2>/dev/null || date -u -d "$start_time" +%s) ))
    if (( elapsed >= max_wall )); then
      jq '.aborted_reason = "wall_time"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      printf '[%s] stop: reason=wall_time elapsed=%ss\n' "$(date -u +%FT%TZ)" "$elapsed" >> "$PROGRESS"
      exit 1
    fi
  fi
  # cost cap
  if awk -v c="$cost" -v m="$max_cost" 'BEGIN{exit !(c>=m)}'; then
    jq '.aborted_reason = "cost_cap"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    printf '[%s] stop: reason=cost_cap cost=%s\n' "$(date -u +%FT%TZ)" "$cost" >> "$PROGRESS"
    exit 1
  fi
  # rubric stagnation
  if (( stag >= max_stag )); then
    jq '.aborted_reason = "rubric_stagnation"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    printf '[%s] stop: reason=rubric_stagnation count=%s\n' "$(date -u +%FT%TZ)" "$stag" >> "$PROGRESS"
    exit 1
  fi

  # 1 iteration、fresh context
  printf '[%s] ralph: launching iter=%s\n' "$(date -u +%FT%TZ)" "$iter" >> "$PROGRESS"
  claude -p --bare "Resume /harness-loop. Read .harness/progress.md (tail 100) and .harness/_state.json. Execute exactly one iteration (one Generator turn + one Evaluator turn + Step 7 checkpoint), then exit."
  # skill が呼び出し内で _state.json を書く; 次 tick で新値が読まれる
done
```

### 終了コード

| Code | 意味 |
|---|---|
| 0 | epic 完了、終了 |
| 1 | Principal Skinner 停止 または pending_human halt |
| 2 | Pre-flight 失敗（jq / claude / `_state.json` 不足） |

## なぜ `--bare`、`--continue`/`--resume` 不使用か

- `--bare`: インタラクティブ UI と追加フレーミングを抑制。stdout の
  shell 捕捉が決定論的
- `--continue` 不使用: 各呼び出しが fresh context。Ralph は *fresh context
  そのもの* であり、過去セッション継承はパターンを台無しにする
- `--resume` 不使用: 古いコンテキストを stitch し直すため同じ論理

harness パターンの前提: 3 つの永続ファイルが再開に必要なものを全て
持つ。持てない場合は Orchestrator の状態書込のバグであり、セッション
メモリを残す理由にはならない。

## Scheduled モード変形

`scheduled` はハイブリッド。`continuous` を N iter 回したあと `autonomous-ralph`
を 1 iter 挟んでコンテキストを流す、を繰り返す。プロジェクトが pure
continuous には大きすぎ（sprint 中 context rot）、pure Ralph では Boot
コストが支配的な場合に使う。

```bash
# ralph-loop.sh の変形:
RALPH_EVERY=${RALPH_EVERY:-5}
continuous_iters_remaining=${RALPH_EVERY}

while :; do
  # ...上記と同じ Principal Skinner ゲート...

  if (( continuous_iters_remaining > 0 )); then
    # continuous 1 step: 同一 claude セッションを維持
    claude -p --bare "..."  # orchestrator が同一プロセスで 1 iter 進める
    continuous_iters_remaining=$(( continuous_iters_remaining - 1 ))
  else
    # Ralph 1 step: fresh context
    claude -p --bare "Resume /harness-loop one iteration..."
    continuous_iters_remaining=${RALPH_EVERY}
  fi
done
```

`_config.yml.scheduled_ralph_every` で `RALPH_EVERY` を設定（デフォルト 5）。
`harness-init` が `scheduled` 選択可能時に setup 時に記録する。

## 夜間運用

数時間〜夜間実行する場合:

1. loop 開始時に `autonomous-ralph` を選択
2. `max_wall_time_sec` を予算に合わせて設定
   （例: 8h なら 28800、デフォルト）
3. `max_cost_usd` でコスト上限
   （例: $20 なら 20、デフォルト）
4. ラッパーを detach で起動:
   ```bash
   nohup .harness/scripts/ralph-loop.sh >> .harness/ralph.log 2>&1 &
   disown
   ```
5. モニタ:
   ```bash
   tail -f .harness/progress.md
   tail -f .harness/metrics.jsonl
   ```

起床後: `_state.json` の `aborted_reason` を最初に確認、次に
`progress.md` の末尾。

## Ralph 実行中の Tier-A 停止

`.harness/scripts/tier-a-guard.sh`（`harness-init` が配置）は Tier-A 操作を
deny した時 `pending_human=true` に設定する。ラッパーの次 tick でこれを
検出し、Claude プロセスを新規起動せず exit 1 する。ユーザは:

1. deny されたコマンドを `progress.md` で確認
2. 判断: approve（方針調整）または reject（aborted のまま）
3. 手動で `_state.json.pending_human=false` に戻す
4. ラッパー再起動

バイパス経路は無い。Tier-A 承認は常に human-in-the-loop（REQ-081）。

## やってはいけないこと

- `while :; do claude -p --continue ...` — Ralph を台無しにする
- Principal Skinner ブロックの抑制 — コスト暴走
- iteration の並列化 — state ファイルがボトルネック
- 同一プロジェクトで複数ラッパーを起動 — `_state.json` race
- 本番でラッパー stderr を握り潰す — 診断材料の損失

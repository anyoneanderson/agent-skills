# Autonomous Ralph

`autonomous-ralph` 実行モードは対話中 supervisor session を 1 本維持しつつ、
`harness-loop` の worker 側を iteration ごとに独立 Claude プロセスで実行する。
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

## Supervisor-first 契約

`autonomous-ralph` の公開エントリは対話中 session からの:

```text
/harness-loop --mode autonomous-ralph
```

その後の Step 2 分岐は次のとおり:

- 対話 session → supervisor attach/spawn 経路
  （`references/supervisor-dispatch.ja.md` 参照）
- wrapper からの非対話再入 → ちょうど 1 unit だけ実行する worker 経路

`ralph-loop.sh` は supervisor が扱う内部実装詳細である。

## 内部 wrapper 実装

以下が正準の内部 `ralph-loop.sh`。Step 2 が初めて supervisor mode に
入った時点で `.harness/scripts/ralph-loop.sh` に配置する。

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE=".harness/_state.json"
PROGRESS=".harness/progress.md"
CONFIG=".harness/_config.yml"

command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }
command -v claude >/dev/null || { echo "claude CLI required" >&2; exit 2; }
[[ -f $STATE ]] || { echo "_state.json missing; run /harness-init + /harness-plan first" >&2; exit 2; }

yget() {
  { grep -E "^$1:" "$CONFIG" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"' | tr -d "'"; } || true
}

first_missing_sprint_pr() {
  [ "$(yget tracker)" = "none" ] && return 1
  local current_sprint i
  current_sprint="$(jq -r '.current_sprint // 0' "$STATE")"
  [ "$current_sprint" -gt 0 ] 2>/dev/null || return 1
  for (( i = 1; i <= current_sprint; i++ )); do
    if ! jq -e --arg key "$i" '(.sprint_prs[$key] // "") | type == "string" and length > 0' "$STATE" >/dev/null; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

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
  phase=$(jq -r '.phase // "impl"' "$STATE")
  current_epic=$(jq -r '.current_epic // empty' "$STATE")

  if [[ $completed == true ]]; then
    missing_pr_sprint="$(first_missing_sprint_pr || true)"
    if [ -n "$missing_pr_sprint" ]; then
      jq --arg sprint "$missing_pr_sprint" '
        .completed = false
        | .phase = "pr"
        | .pending_worker_exit = false
        | .next_action = ("harness-loop:create-pr:sprint-" + $sprint)
      ' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      printf '[%s] guard: completed=true but sprint_prs[%s] missing; restoring phase=pr\n' \
        "$(date -u +%FT%TZ)" "$missing_pr_sprint" >> "$PROGRESS"
      continue
    fi
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
  # fresh-epic boot reset (epic あたり最大 1 回。wall-time / iteration / cost /
  # stagnation gate より前に置き、前 epic の古いカウンタが boot 直後に
  # false-positive stop を起こさないようにする)。
  # 新規 epic は新しい current_epic + phase=ready-for-loop で handoff されるが
  # wall-time / cost / stagnation / iteration カウンタは初期化されない。reset は
  # start_time_epic を基準に判定する: start_time_epic が current_epic と異なる
  # (または未設定) なら新 epic の初回 boot なので、カウンタを 1 度だけ再設定し
  # start_time_epic = current_epic を刻む。以降の tick や mid-epic resume は
  # start_time_epic == current_epic を観測して reset を skip するため、epic の
  # 残り期間も wall-time cap が有効に働く (ready-for-loop で stuck した worker が
  # start_time を進め続けることがない)。sprint ごとの start_time reset は Step 9
  # の sprint transition が別途担当する。
  if [[ -n $current_epic ]]; then
    start_time_epic=$(jq -r '.start_time_epic // empty' "$STATE")
    if [[ "$start_time_epic" != "$current_epic" ]]; then
      now_ts="$(date -u +%FT%TZ)"
      jq --arg now "$now_ts" --arg epic "$current_epic" '
        .start_time = $now
        | .start_time_epic = $epic
        | .cumulative_cost_usd = 0
        | .rubric_stagnation_count = 0
        | .iteration = 0
      ' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      start_time="$now_ts"
      cost=0
      stag=0
      iter=0
      printf '[%s] ralph: fresh-epic boot — start_time/cost/stagnation/iteration reset (epic=%s)\n' "$now_ts" "$current_epic" >> "$PROGRESS"
    fi
  fi
  if [[ "$phase" != "pr" ]] && (( iter >= max_iter )); then
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

  # Defensive: pending_worker_exit は 1 turn 単位の micro-signal。
  # 直前の turn が stop-guard.sh で reset 前に異常終了した場合に備えて
  # ここで明示的に false へ戻す。
  jq '.pending_worker_exit = false' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

  # 1 worker unit、fresh context。prompt は phase 依存で分岐して
  # 現行 state cursor に対応する Step を subprocess で実行させる
  # (negotiation / impl / pr / foundation 各 phase で subprocess に渡す
  #  instruction が違う。phase 固定 prompt だと default impl path 以外の
  #  state.phase で subprocess が mutation 無しに exit してしまう)。
  #
  # 各 phase prompt には以下 3 要素を必ず含める:
  #   1. PRE-FLIGHT Step 3 self-check (sprint_branch == null OR
  #      git branch != expected → SKILL.md Step 3 を実行し
  #      sprint_branch を更新)。
  #   2. phase 固有 work instruction。
  #   3. EXIT signal: turn を終わらせる durable write の直後に
  #      _state.json.pending_worker_exit = true を atomic に立てる。
  #      これが無いと負担管理上 iteration を進めない negotiation
  #      phase で stop-guard.sh が永遠 block する。
  PRE_FLIGHT='PRE-FLIGHT (Step 3 sprint branch self-check, see SKILL.md §Step 3): expected branch を harness/<current_epic>/sprint-<current_sprint>-<feature> として算出 (feature は roadmap から、bundle peer は primary peer の feature)。state.sprint_branch が null か、`git rev-parse --abbrev-ref HEAD` が expected と異なる場合は Step 3 を実行 (git checkout -b expected が必要なら作成、そうでなければ git checkout expected)、_state.json.sprint_branch = expected を atomic に書き込み、progress.md に branch 行を append する。phase が foundation-* の場合 foundation protocol が branch setup を所有するので skip。'
  EXIT_SIGNAL='EXIT SIGNAL: 本 invocation の最終 durable write として _state.json.pending_worker_exit = true を atomic (jq | mv) に立て、stop-guard.sh が natural exit を許可できるようにする。フラグは次の allow-stop と次の wrapper tick で自動 clear される。'

  phase=$(jq -r '.phase // "impl"' "$STATE")
  case "$phase" in
    negotiation)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute exactly one negotiation round (Generator turn + Evaluator turn per references/negotiation-protocol.md §Round), including validate-generator-report.sh and validate-evaluator-report.sh immediately after their dispatches. round summary を commit したあと ${EXIT_SIGNAL} 最後に exit。"
      ;;
    impl|evaluation)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute exactly one iteration (one Generator turn + one Evaluator turn + Step 7 checkpoint), including validate-generator-report.sh and validate-evaluator-report.sh immediately after their dispatches. Step 7 atomic commit のあと ${EXIT_SIGNAL} 最後に exit。"
      ;;
    pr)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute Step 8 per references/pr-creation-guide.md: push the sprint branch if needed, run gh pr create, record the PR URL to _state.json.sprint_prs[<n>], append shared_state.md/Decisions and progress.md, then commit. roadmap に次 sprint が残っていれば Step 9 transition: current_sprint++, iteration=0, phase=negotiation, start_time=now, rubric_stagnation_count=0, features_pass_fail=[], **sprint_branch=null, negotiation_round=0, last_agent=null** (stale carry-over 防止のため、これら 3 つも必ず reset)。残っていなければ _state.json.sprint_prs[1..current_sprint] が全て non-null であることを確認してから completed=true, phase=done。durable transition write のあと ${EXIT_SIGNAL} 最後に exit。"
      ;;
    foundation-setup|foundation-attest)
      prompt="Resume /harness-loop. Follow references/foundation-loop-protocol.md for the current foundation phase (setup or attest). turn を終わらせる durable phase write (Attest record / verification commit / pending_human flip) のあと ${EXIT_SIGNAL} 最後に exit。"
      ;;
    done)
      printf '[%s] ralph: phase=done, exiting\n' "$(date -u +%FT%TZ)" >> "$PROGRESS"
      exit 0
      ;;
    *)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute the appropriate Step for phase=${phase} according to SKILL.md. turn を終わらせる durable write のあと ${EXIT_SIGNAL} 最後に exit。"
      ;;
  esac

  printf '[%s] ralph: launching worker phase=%s iter=%s\n' "$(date -u +%FT%TZ)" "$phase" "$iter" >> "$PROGRESS"
  claude -p --permission-mode bypassPermissions "$prompt"
  # skill が呼び出し内で _state.json を書く; 次 tick で新値が読まれる
done
```

### 終了コード

| Code | 意味 |
|---|---|
| 0 | epic 完了、終了 |
| 1 | Principal Skinner 停止 または pending_human halt |
| 2 | Pre-flight 失敗（jq / claude / `_state.json` 不足） |

## Worker model / timeout / progress budget の設定

wrapper は `.harness/_config.yml` の以下の任意 key を読む:

```yaml
worker_model: sonnet
worker_model_high_risk: opus
worker_model_high_risk_phases:
  - negotiation
  - pr
worker_timeout_sec_default: 1800
worker_timeout_sec_negotiation: 600
worker_timeout_sec_pr: 300
# 任意の phase × model 別 override (下記参照)。
# worker_timeout_sec_impl_opus: 2700
worker_timeout_grace_sec: 10
progress_tail_lines: 30
progress_rotation_on_epic_complete: true
tool_log_external: true
```

通常 worker turn は `worker_model` を使い、長時間運用時の週次 token
pressure を下げる。`worker_model_high_risk_phases` に列挙された phase
では、設定されていれば `worker_model_high_risk` を使う。phase timeout
を超えた worker には SIGTERM を送り、grace 経過後も残っていれば
SIGKILL する。wrapper は非 0 exit を log して次 tick へ進み、`set -e`
で連鎖終了しない。

`worker_timeout_for_phase()` は timeout を次の順で解決する。これにより
特定 phase の遅い model だけ他 phase を変えずに余裕を持たせられる:

1. env `HARNESS_WORKER_TIMEOUT_SEC` (最優先、すべてを上書き)
2. `worker_timeout_sec_<phase>_<model>` — その phase の model
   (`worker_model_for_phase()` で解決) に対する任意の flat override
   (例 `worker_timeout_sec_pr_opus`)
3. `worker_timeout_sec_<phase>` — 既存の phase 別キー
   (`negotiation` / `pr`)
4. `worker_timeout_sec_default` (無ければ literal `1800`)

`worker_timeout_sec_<phase>_<model>` flat キーは任意。何も設定しなければ
解決は従来の phase 別挙動 (1800 / 600 / 300) に収束するので、既存の
config は影響を受けない。

`progress_rotation_on_epic_complete` が true の場合、epic 完了時に root
の `.harness/progress.md` を `.harness/<epic>/progress-completed.md` へ
移動し、新しい root progress log を開始する。`tool_log_external` が true
の場合、hook 由来の機械行は human narrative ではなく
`.harness/tool_log.jsonl` に出力する。

## なぜ `-p --permission-mode bypassPermissions` を使い、session 再利用系 flag を使わないか

- `-p`: 非対話 worker 実行用。harness に必要な hooks、CLAUDE.md 読込、
  plugins、credentials を迂回しない。ただし `-p` 単独では workspace
  trust dialog を skip するのみで、Bash / Edit / Write 等の approval
  prompt は依然として発火する
- `--permission-mode bypassPermissions`: 全 tool 呼び出しの UI approval
  prompt を skip し、無人 worker が実際に作業できるようにする。hooks
  (PreToolUse / PostToolUse / Stop) は **継続して動作** するため、
  `.harness/scripts/tier-a-guard.sh` が Tier-A パターンを denied して
  `pending_human=true` を立てる安全網は維持される。UI 抑止のみで safety
  rail はそのまま
- minimal-mode flag 不使用: hooks / CLAUDE.md discovery / plugin sync /
  keychain reads まで全て skip するような flag は harness の safety rail
  を丸ごと失うため採用しない
- `--continue` 不使用: 各呼び出しが fresh context。Ralph は *fresh
  context そのもの* であり、過去セッション継承はパターンを台無しにする
- `--resume` 不使用: 古いコンテキストを stitch し直すため同じ論理

harness パターンの前提: 3 つの永続ファイルが再開に必要なものを全て
持つ。持てない場合は Orchestrator の状態書込のバグであり、セッション
メモリを残す理由にはならない。fresh context は iteration ごとに
`claude -p --permission-mode bypassPermissions` を再起動することで
維持でき、危険操作を本当に止めるのは hook ベースの safety (tier-a-guard)
であって対話 approval prompt ではない。

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
    claude -p "..."  # orchestrator が同一プロセスで 1 iter 進める
    continuous_iters_remaining=$(( continuous_iters_remaining - 1 ))
  else
    # Ralph 1 step: fresh context
    claude -p "Resume /harness-loop one iteration..."
    continuous_iters_remaining=${RALPH_EVERY}
  fi
done
```

`RALPH_EVERY` の解決順序: `/harness-loop` 呼び出し時の
`--ralph-every <N>` CLI フラグ → `RALPH_EVERY` 環境変数 → リテラル
デフォルト `5`。v1 では `_config.yml` から読まない
（`harness-init` は本キーを把握していない）。

## 夜間運用

数時間〜夜間実行する場合:

1. 対話中 Claude Code session から
   `/harness-loop --mode autonomous-ralph` を開始
2. supervisor に `.harness/ralph.pid` ベースで wrapper を attach/spawn
   させる
3. `max_wall_time_sec` と `max_cost_usd` を予算に合わせる
4. event relay と `pending_human` 介入のため supervisor session を維持
5. 再開時も同じ `/harness-loop --mode autonomous-ralph` を叩き、
   duplicate wrapper を作らず reattach させる

`ralph-loop.sh` は worker 起動器として残るが、user 向け entrypoint ではない。

## Ralph 実行中の Tier-A 停止

`.harness/scripts/tier-a-guard.sh`（`harness-init` が配置）は Tier-A 操作を
deny した時 `pending_human=true` に設定する。ラッパーは次 tick で worker
再起動を止める。recovery を所有するのは supervisor (interactive / autonomous
いずれも) だが、recovery が発火するのは `tier_a_last.cmd` の分類が
「false positive」に達したときのみ。unattended run ではこれが効く: 相談する
人間が不在なので、supervisor 自身で分類し判断する (or halt を維持) しかない:

1. `progress.md` / `ralph.log` および `_state.json.tier_a_last.cmd` から
   deny 内容を確認
2. cmd を分類:
   - **False positive** — cmd は当 project では benign (Evaluator が
     project-internal な absolute path を rm する cleanup script、`/tmp/...`
     配下の build artifact rm 等 — system-path whitelist が対象外とする
     pattern)
   - **真の Tier-A 違反** — cmd は OS state 破壊、protected branch への
     force-push、production DB drop 等を実際に引き起こす
   - **Uncertain**
3. 判断:
   - False positive → 下記 recovery sequence を実行
   - 真の違反 → halt を維持、unattended mode で auto-clear はしない
     (silent auto-clear は guard の存在意義を毀損する)。人間が attach
     していれば `AskUserQuestion` で cmd を提示し explicit override を
     仰いでよい
   - Uncertain → halt を維持、bias は「迷ったら halt」
4. recovery-eligible に達した分類の後にのみ `.harness/ralph.pid` ベースで
   wrapper を re-attach / restart

毎 Monitor event 後に supervisor は wrapper PID の死活を直接確認する
（`ps -p $(cat .harness/ralph.pid)` あるいは
`kill -0 $(cat .harness/ralph.pid)`）。`progress.md` に
`halting for approval` event が出ているなら wrapper は exit 済みであり、
Monitor event 単独では wrapper alive の証拠にならない — respawn が必要。

Monitor pattern には `halting for approval` を含めて起動する。これで
halt 検知が「次 worker tick の失敗を待つ」遅延から即時に短縮される
（pattern が無い場合 halt 滞留が数十分単位に達する観察例あり）。
動作する regex（full filter は `references/supervisor-dispatch.md`）:

```text
negotiation|evaluation|decision|stop|pending_human|halting for approval|TIER-A
```

### Tier-A 復旧 sequence（idempotent）

分類が「false positive」に達したとき (または人間 attach 時の explicit
override 時) のみ実行する。「真の違反」「uncertain」では実行しない。
再実行しても安全だが、user に編集を委譲しないこと:

```bash
# atomic clear + wrapper respawn
jq '.pending_human=false' .harness/_state.json > /tmp/_s.json \
  && mv /tmp/_s.json .harness/_state.json
nohup .harness/scripts/ralph-loop.sh >> .harness/ralph.log 2>&1 &
echo $! > .harness/ralph.pid
disown
printf '[%s] supervisor: tier-a cleared, wrapper respawn pid=%s\n' \
  "$(date -u +%FT%TZ)" "$!" >> .harness/progress.md
```

silent auto-clear path は無い。Tier-A guard はまさに unattended mode が
silent に state を破壊できないように存在する。recovery は
supervisor-driven かつ classification-gated、halt が safety floor。

## やってはいけないこと

- `while :; do claude -p --continue ...` — Ralph を台無しにする
- Principal Skinner ブロックの抑制 — コスト暴走
- iteration の並列化 — state ファイルがボトルネック
- 同一プロジェクトで複数ラッパーを起動 — `_state.json` race
- 本番でラッパー stderr を握り潰す — 診断材料の損失

# Supervisor Dispatch

`autonomous-ralph` の公開エントリは
`/harness-loop --mode autonomous-ralph` だけにする。
ここから `harness-loop` は次の 2 分岐に入る:

- **Supervisor** — 進捗監視・wrapper lifecycle 管理・`pending_human`
  介入を担う対話中 Claude Code session
- **Worker** — wrapper から再起動される非対話 1 unit 実行

この文書は、その分岐と `.harness/ralph.pid` の契約を定義する。

## 起動条件

Step 2 の mode 解決後に次で分岐する:

```text
if flag == --stop-wrapper:
  stop-wrapper flow

elif mode != autonomous-ralph:
  通常の Step 3 へ

elif interactive session detected:
  supervisor flow

else:
  worker flow
```

対話検出は `[ -t 0 ]`、runtime flag、同等の platform signal のいずれでも
よい。重要なのは意味論で、人間が接続されている session なら supervisor、
headless 再入なら worker であること。

## Wrapper lifecycle (`.harness/ralph.pid`)

使用パス:

- PID file: `.harness/ralph.pid`
- wrapper log: `.harness/ralph.log`
- worker 実装詳細: `.harness/scripts/ralph-loop.sh`

ライフサイクル規約:

1. `.harness/ralph.pid` があり、`kill -0 "$(cat .harness/ralph.pid)"`
   が成功するなら wrapper は生存中。attach を報告し、新規 spawn しない
2. pid file があるのに `kill -0` が失敗する場合は stale。pid file を削除し、
   fresh wrapper を spawn する
3. spawn は detached lifetime で行う:
   ```bash
   nohup .harness/scripts/ralph-loop.sh >> .harness/ralph.log 2>&1 &
   pid=$!
   echo "$pid" > .harness/ralph.pid
   disown
   ```
   unattended run では staleness watchdog も起動する:
   ```bash
   nohup .harness/scripts/staleness-watchdog.sh >> .harness/staleness.log 2>&1 &
   ```
4. spawn / attach は idempotent でなければならない。同一 project で wrapper を
   2 本動かさない
5. `--stop-wrapper` は次を実行する:
   ```bash
   if [[ -f .harness/ralph.pid ]] && kill -0 "$(cat .harness/ralph.pid)" 2>/dev/null; then
     kill "$(cat .harness/ralph.pid)"
   fi
   rm -f .harness/ralph.pid
   ```

## Supervisor flow

Supervisor の責務:

1. 上記 lifecycle 規約で wrapper 生存を担保
2. `wrapper pid=<n>` を user に通知
3. `.harness/progress.md` と `.harness/ralph.log` の fresh event を監視
4. 高シグナル event だけ relay:
   - `negotiation: round=<r> ... signal=<...>`
   - `decision: sprint-... contract frozen`
   - `evaluation: iter=<n> verdict=<pass|fail>`
   - `stop: reason=...`
   - `pending_human=true`
   - `decision: epic=<name> completed ...`
5. supervisor として常駐し、worker unit を inline 実行しない

## Staleness watchdog

`autonomous-ralph` には「進捗が無い」ことを検知する signal も必要。
Principal Skinner gate は iteration が進む、budget を超える、
`pending_human` が立つ、のいずれかでしか発火しないため、sleeping
worker が `progress.md` を書かなくなった状態は捕捉できない。

`.harness/scripts/staleness-watchdog.sh` は
`.harness/progress.md` の最新 timestamp を `staleness_interval_sec`
秒ごとに読み、`staleness_threshold_sec` を超えたら
`STALE-WATCHDOG` warning を append する。復旧は opt-in で、
`staleness_auto_recover: true` の場合のみ hung worker を終了し、
`.harness/scripts/ralph-loop.sh` を respawn する。試行回数は
`max_staleness_recoveries_per_sprint` で制限する。

推奨 filter（line-based、1 行 1 keyword）:

```text
negotiation: round=
evaluation:
sprint-transition:
phase transition:
branch:
decision:
ralph: launching worker
ralph: worker timeout
stop:
pending_human
halting for approval
Tier-A
```

`decision:` は単独で一致させる（`decision: sprint-` / `decision: epic=`
に絞らない）ので、自由記述の orchestrator decision を取りこぼさない。
`sprint-transition:` / `phase transition:` / `branch:` /
`ralph: launching worker` / `ralph: worker timeout` は高シグナルへ昇格する。
これらは loop が sprint/phase 境界を跨ぐ、branch を切り替える、worker を
再起動する瞬間を示し、supervisor が liveness モデルを正確に保つために
観測すべき event だからである。

`harness-loop sprint events --monitor` や `tail | grep -E` に渡す
single-line regex 版:

```text
negotiation|evaluation|sprint-transition|phase transition|branch:|decision:|launching worker|worker timeout|stop:|pending_human|halting for approval|TIER-A
```

`halting for approval` は wrapper が `pending_human=true` 検知で
`exit 1` する直前に出力する log 行。これを explicit に監視することで
supervisor の「wrapper はまだ生きているか?」検知が「次 worker tick の
失敗を待つ」遅延（分単位）から即時（秒単位）に短縮される。

### `tail` バッファによる取りこぼしを避ける

`tail -F file | grep -E ...` は pipe 内で `grep` が出力を block-buffer する
ため停滞することがあり、高シグナル行が遅れて、あるいは纏めて届く。各
一致 event を書き込まれ次第 relay するには line-buffer を強制する:

```bash
stdbuf -oL tail -F .harness/progress.md \
  | grep --line-buffered -E 'negotiation|evaluation|sprint-transition|phase transition|branch:|decision:|launching worker|worker timeout|stop:|pending_human|halting for approval|TIER-A'
```

複数 source（例 `progress.md` と `ralph.log`）を取りこぼしなく追う場合は、
まとめて tail するか `inotifywait` で書き込みを監視する:

```bash
# 複数ファイルを tail。--line-buffered で grep が行ごとに flush する
stdbuf -oL tail -F .harness/progress.md .harness/ralph.log \
  | grep --line-buffered -E 'stop:|pending_human|halting for approval|TIER-A'

# event 駆動の代替 (Linux): 書き込みのたびに tail を再走査する
while inotifywait -q -e modify .harness/progress.md .harness/ralph.log; do
  tail -n 5 .harness/progress.md .harness/ralph.log \
    | grep -E 'stop:|pending_human|halting for approval|TIER-A'
done
```

`stdbuf` / `inotifywait` が無い macOS では、`grep --line-buffered`
単体（Homebrew の GNU grep）や `fswatch` が等価手段になる。

## Worker flow

Worker flow は従来の Ralph と同じ:

- Boot Sequence を読む
- ちょうど 1 つの bounded unit を実行
- `_state.json` / `progress.md` / git / `metrics.jsonl` を永続化
- wrapper が次を判断できるよう exit

Worker flow は `.harness/ralph.pid` を触らない。

## Evaluator post-dispatch validation

Evaluator dispatch は常に Claude `Task()` 呼び出しである。Task が戻ったら、
Orchestrator は `feedback/evaluator-<iter>.md` や
`feedback/evaluator-<iter>-report.json` を消費する前に、必ず
`.harness/scripts/claude-dispatch.sh --post-dispatch --role evaluator ...`
を実行する。この wrapper は subagent を起動せず、`_state.json` も直接
touch しない。責務はファイル正規化、fallback 出力合成、
`progress-append.sh` 経由の WARN 出力に限る。次の step で
`validate-evaluator-report.sh` を実行し、shared-state report schema と
Phase 3 evidence contract を機械検証する。

## `pending_human` / Tier-A 介入

wrapper が `_state.json.pending_human == true` で止まった場合、回復できるのは
supervisor 分岐 (interactive / autonomous いずれも) のみ。判断は
`tier_a_last.cmd` の分類が主導であり、`AskUserQuestion` は人間が attach
している場合の任意 override に留める（overnight / unattended run では
応答が得られないため依存できない）。

1. `_state.json`（`.tier_a_last.cmd` に matched cmd が入っている）と
   `progress.md` 末尾を読む
2. cmd を 3 種に分類:
   - **False positive** — cmd は当 project では benign (例: Evaluator が
     project-internal な absolute path を rm する cleanup script、wrapper
     が `/tmp/...` 配下の build artifact を `rm -rf` する等、system-path
     whitelist の対象外)
   - **真の Tier-A 違反** — cmd は OS state 破壊、protected branch への
     force-push、production DB drop 等を実際に引き起こす
   - **Uncertain** — `tier_a_last.cmd` と `progress.md` の context だけでは
     確信を持って分類できない
3. 分岐:
   - False positive → 下記 recovery sequence を実行（atomic clear + wrapper
     respawn）。`phase` は live な in-sprint 値を維持。`progress.md` に
     分類結果を append し、なぜ halt を clear したか audit trail に記録
   - 真の Tier-A 違反 → halt を維持し停止状態を報告。どの状況でも
     auto-clear しない — 真の Tier-A 違反こそ guard が存在する理由であり、
     unattended mode で silent auto-clear するとその意義を毀損する。
     人間が attach していれば `AskUserQuestion` で cmd を提示し explicit
     override を仰いでよい。explicit approve が得られた場合は人間が
     policy 判断責任を持ち、supervisor が代行で recovery sequence を実行
   - Uncertain → halt を維持。保守的 bias は「迷ったら halt」— 次に
     attach する supervisor session が `.tier_a_last` から resume し
     再分類する。今 attach 中の人間がいれば `AskUserQuestion` 適切

毎 Monitor event 後に supervisor は wrapper PID の死活を直接確認する
（`ps -p $(cat .harness/ralph.pid)` あるいは
`kill -0 $(cat .harness/ralph.pid)`）。`halting for approval` event は
wrapper が exit 済みである signal であり、Monitor event 単独は wrapper
alive の証拠にならない — respawn が必要。

### Recovery sequence (idempotent)

分類が「false positive」に達したとき (または人間 attach 時の explicit
override 時) のみ実行する。「真の違反」「uncertain」では実行しない。
再実行しても安全:

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

人間が attach している場合でも supervisor が代行で実行する — user に
`_state.json` の手編集をさせない。recovery 操作の責任は supervisor
（interactive / autonomous いずれも）が持ち、人間が居る場合は真の違反時の
policy 判断のみを担う。

## State invariants

- sprint transition は次 sprint のために `phase = "negotiation"` を書く
- supervisor の resume / reattach は `phase = "negotiation"` を live cursor
  として扱う
- state を `ready-for-loop` に巻き戻さない
- wrapper と supervisor は同じ `_state.json` を読む。書けるのは worker
  （または明示的な supervisor の Tier-A 回復）だけ

## Failure handling

- wrapper spawn 失敗 → stderr を surface、`pending_human=true` にして停止
- wrapper log はあるが pid file が無い → live wrapper なしとして扱う
- pid file はあるが process が死んでいる → stale pid を削除して respawn
- supervisor session が複数 attach → 先着を実運用側とみなし、後発は
  read-only attach に留めて respawn しない

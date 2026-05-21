# Supervisor Dispatch

`autonomous-ralph` has one public entrypoint:
`/harness-loop --mode autonomous-ralph`.
From there, `harness-loop` must branch into either:

- **Supervisor** — interactive Claude Code session that watches progress,
  manages wrapper lifecycle, and handles `pending_human`
- **Worker** — non-interactive one-unit execution re-invoked by the wrapper

This file defines that branch and the `.harness/ralph.pid` lifecycle.

## Entry conditions

Evaluate in Step 2 after mode resolution:

```text
if flag == --stop-wrapper:
  stop-wrapper flow

elif mode != autonomous-ralph:
  continue normal Step 3 flow

elif interactive session detected:
  supervisor flow

else:
  worker flow
```

Interactive detection may use `[ -t 0 ]`, a tool/runtime flag, or an
equivalent platform signal. The contract is semantic: human-attached
session ⇒ supervisor, headless re-entry ⇒ worker.

## Wrapper lifecycle (`.harness/ralph.pid`)

Paths:

- PID file: `.harness/ralph.pid`
- Wrapper log: `.harness/ralph.log`
- Worker implementation detail: `.harness/scripts/ralph-loop.sh`

Lifecycle rules:

1. If `.harness/ralph.pid` exists and `kill -0 "$(cat .harness/ralph.pid)"`
   succeeds, the wrapper is already alive. Report attach and do not spawn
   a second wrapper.
2. If the pid file exists but `kill -0` fails, delete the stale pid file
   and spawn a fresh wrapper.
3. Spawn with detached lifetime:
   ```bash
   nohup .harness/scripts/ralph-loop.sh >> .harness/ralph.log 2>&1 &
   pid=$!
   echo "$pid" > .harness/ralph.pid
   disown
   ```
   For unattended runs, also arm the staleness watchdog:
   ```bash
   nohup .harness/scripts/staleness-watchdog.sh >> .harness/staleness.log 2>&1 &
   ```
4. Spawn/attach must be idempotent. Never run two wrappers for one project.
5. `--stop-wrapper` does:
   ```bash
   if [[ -f .harness/ralph.pid ]] && kill -0 "$(cat .harness/ralph.pid)" 2>/dev/null; then
     kill "$(cat .harness/ralph.pid)"
   fi
   rm -f .harness/ralph.pid
   ```

## Supervisor flow

Supervisor responsibilities:

1. Ensure the wrapper is running via the lifecycle rules above
2. Announce `wrapper pid=<n>` to the user
3. Watch fresh events from `.harness/progress.md` and `.harness/ralph.log`
4. Relay only high-signal events, for example:
   - `negotiation: round=<r> ... signal=<...>`
   - `decision: sprint-... contract frozen`
   - `evaluation: iter=<n> verdict=<pass|fail>`
   - `stop: reason=...`
   - `pending_human=true`
   - `decision: epic=<name> completed ...`
5. Stay attached as supervisor; do not execute the worker unit inline

## Staleness watchdog

`autonomous-ralph` also needs an absence-of-progress signal. Principal
Skinner gates only fire when an iteration advances, a budget is exceeded,
or `pending_human` is set; they do not detect a sleeping worker that stops
writing progress.

`.harness/scripts/staleness-watchdog.sh` monitors the latest timestamp in
`.harness/progress.md` every `staleness_interval_sec` seconds and appends a
`STALE-WATCHDOG` warning when the age exceeds `staleness_threshold_sec`.
Recovery is opt-in: set `staleness_auto_recover: true` to terminate the
hung worker, respawn `.harness/scripts/ralph-loop.sh`, and cap attempts
with `max_staleness_recoveries_per_sprint`.

Recommended event filter (line-based, one keyword per line):

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

`decision:` is matched on its own (not narrowed to `decision: sprint-` /
`decision: epic=`) so free-form orchestrator decisions are not dropped.
`sprint-transition:` / `phase transition:` / `branch:` /
`ralph: launching worker` / `ralph: worker timeout` are promoted to
high-signal because they mark the loop crossing a sprint/phase boundary,
switching branches, or restarting a worker — exactly the moments a
supervisor must observe to keep its liveness model accurate.

Equivalent single-line regex for `harness-loop sprint events --monitor`
or any `tail | grep -E` pipeline:

```text
negotiation|evaluation|sprint-transition|phase transition|branch:|decision:|launching worker|worker timeout|stop:|pending_human|halting for approval|TIER-A
```

`halting for approval` is the wrapper's own log line emitted just
before `exit 1` on `pending_human=true`. Monitoring it explicitly
short-circuits the supervisor's "did the wrapper just exit?" check
from minutes (waiting for the next worker-tick failure) down to
seconds.

### Avoiding dropped lines from `tail` buffering

`tail -F file | grep -E ...` can stall in pipes because `grep` block-buffers
its output; high-signal lines then arrive late or in bursts. Force
line-buffering so each matching event is relayed as soon as it is written:

```bash
stdbuf -oL tail -F .harness/progress.md \
  | grep --line-buffered -E 'negotiation|evaluation|sprint-transition|phase transition|branch:|decision:|launching worker|worker timeout|stop:|pending_human|halting for approval|TIER-A'
```

To follow more than one source (e.g. `progress.md` and `ralph.log`)
without losing lines, either tail them together or watch for writes with
`inotifywait`:

```bash
# tail multiple files; --line-buffered keeps grep flushing per line
stdbuf -oL tail -F .harness/progress.md .harness/ralph.log \
  | grep --line-buffered -E 'stop:|pending_human|halting for approval|TIER-A'

# event-driven alternative (Linux): re-scan tails on every write
while inotifywait -q -e modify .harness/progress.md .harness/ralph.log; do
  tail -n 5 .harness/progress.md .harness/ralph.log \
    | grep -E 'stop:|pending_human|halting for approval|TIER-A'
done
```

On macOS where `stdbuf` / `inotifywait` may be unavailable, `grep
--line-buffered` alone (GNU grep via Homebrew) or `fswatch` are the
equivalents.

## Worker flow

Worker flow is the old Ralph behavior:

- read Boot Sequence
- execute exactly one bounded unit
- persist `_state.json` / `progress.md` / git / `metrics.jsonl`
- exit so the wrapper can decide the next spawn

Worker flow never touches `.harness/ralph.pid`.

## Evaluator post-dispatch validation

Evaluator dispatch is always a Claude `Task()` call. After the Task
returns, Orchestrator MUST run `.harness/scripts/claude-dispatch.sh
--post-dispatch --role evaluator ...` before consuming
`feedback/evaluator-<iter>.md` or `feedback/evaluator-<iter>-report.json`.
The wrapper does not invoke the subagent and does not write `_state.json`
directly; it only canonicalizes files, synthesises fallback output, and
routes WARN lines through `progress-append.sh`. The next step is the
machine validator (`validate-evaluator-report.sh`), which enforces the
shared-state report schema and Phase 3 evidence contract.

## `pending_human` / Tier-A handling

When the wrapper halts because `_state.json.pending_human == true`,
the supervisor — interactive *or* autonomous — is the only branch
allowed to recover. Classification of `tier_a_last.cmd` drives the
decision; `AskUserQuestion` is an optional human-attached override,
not a precondition (overnight / unattended runs cannot rely on it).

1. Read `_state.json` (`.tier_a_last.cmd` is the matched cmd) and the
   latest `progress.md` tail
2. Classify the cmd as one of three:
   - **False positive** — cmd is benign for this project (e.g.
     Evaluator cleanup script targeting a project-internal absolute
     path that the system-path whitelist does not match, or a
     wrapper `rm -rf /tmp/...` build artifact)
   - **True Tier-A violation** — cmd would actually destroy OS
     state, force-push to a protected branch, drop a production
     table, etc.
   - **Uncertain** — `tier_a_last.cmd` plus `progress.md` context is
     not enough to confidently classify
3. Branch:
   - False positive → run the recovery sequence below (atomic clear
     + wrapper respawn). Keep `phase` on the live in-sprint value.
     Append the classification to `progress.md` so the audit trail
     records *why* the halt was cleared
   - True Tier-A violation → leave the halt in place. Report the
     stopped state. Do not auto-clear under any circumstances —
     real Tier-A violations are exactly what the guard exists to
     stop, and a silent auto-clear in unattended mode would defeat
     that. If a human is attached, `AskUserQuestion` may surface
     the cmd for explicit override; an explicit approve from the
     human owns the policy decision and the supervisor then runs
     the recovery sequence on their behalf
   - Uncertain → leave the halt in place. The conservative bias is
     "halt rather than guess wrong"; the next attached supervisor
     session resumes from `.tier_a_last` and re-classifies. If a
     human is attached now, `AskUserQuestion` is appropriate

After every Monitor event, the supervisor verifies the wrapper is
still alive (`ps -p $(cat .harness/ralph.pid)` or
`kill -0 $(cat .harness/ralph.pid)`). A `halting for approval` event
in `progress.md` implies the wrapper has exited — Monitor events
alone are not proof of liveness; a respawn is required.

### Recovery sequence (idempotent)

Run only after classification has reached "false positive" (or, with
a human attached, an explicit override). Never run on "true
violation" or "uncertain". Safe to re-run:

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

When a human is attached the supervisor still runs the sequence on
their behalf — do not instruct the user to edit `_state.json` by
hand. The supervisor (interactive or autonomous) owns the recovery
operation; the human, if present, owns only the policy decision for
true violations.

## State invariants

- Sprint transition writes `phase = "negotiation"` for the next sprint
- Supervisor resume/reattach must treat `phase = "negotiation"` as live
- Do not bounce the state back to `ready-for-loop`
- Wrapper and supervisor both read the same `_state.json`; only the worker
  (or explicit supervisor Tier-A recovery) writes it

## Failure handling

- Wrapper spawn fails → surface stderr, set `pending_human=true`, stop
- Wrapper log exists but pid file missing → treat as no live wrapper
- pid file exists but process is gone → delete stale pid and respawn
- Multiple supervisor sessions attach → first one wins operationally;
  later sessions attach read-only and must not respawn the wrapper

# Autonomous Ralph

The `autonomous-ralph` execution mode keeps one interactive supervisor
session while the worker side of `harness-loop` runs one fresh Claude
process per iteration. Cross-iteration memory lives only in
`progress.md` + `_state.json` + git + `metrics.jsonl`. "Ralph" is the
canonical name for this pattern (repeatedly re-invoking a fresh agent on
the same checkpointed state).

## Why fresh context per iteration

A single long-running `claude -p --continue` session accumulates
context until compaction hits. Harnessed loops magnify this because
each iteration layers Generator output, Evaluator scoring, and tool
output on top. Restarting per iteration eliminates that drift:

- Each iteration reads only the three durable files
- Principal Skinner conditions are the only surviving cross-iter state
- Reproducibility: rerunning a prior iteration's input yields the same
  output class (subject to model temperature)

Tradeoff: Boot Sequence cost per iter. Amortised against a full
sprint (8 iter default), Boot is ~1% of elapsed time.

## Supervisor-first contract

The public entrypoint for `autonomous-ralph` is an interactive
supervisor session:

```text
/harness-loop --mode autonomous-ralph
```

Step 2 then branches as follows:

- interactive session → supervisor attach/spawn path (see
  `references/supervisor-dispatch.md`)
- non-interactive re-entry from the wrapper → worker path for exactly one
  bounded unit

`ralph-loop.sh` is an internal implementation detail owned by the
supervisor lifecycle.

## Internal wrapper implementation

The template below is the authoritative internal `ralph-loop.sh`.
Install it at `.harness/scripts/ralph-loop.sh` when Step 2 first enters
supervisor mode.

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
  # Principal Skinner gates — all read from _state.json
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
  # fresh-epic boot reset (runs at most once per epic, BEFORE the wall-time /
  # iteration / cost / stagnation gates so stale counters from a prior epic
  # cannot fire a false-positive stop on boot).
  # A freshly planned epic hands off a new current_epic with phase=ready-for-loop
  # but does not (re)initialise the wall-time / cost / stagnation / iteration
  # counters. We key the reset off start_time_epic: when it differs from
  # current_epic (or is absent) this is the first boot of a new epic, so we
  # re-anchor the counters once and stamp start_time_epic = current_epic.
  # Subsequent ticks and mid-epic resumes observe start_time_epic == current_epic
  # and skip the reset, so the wall-time cap stays effective for the rest of the
  # epic regardless of phase (a worker stuck in ready-for-loop no longer keeps
  # pushing start_time forward). Per-sprint start_time resets are handled
  # separately by the Step 9 sprint transition.
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

  # Defensive: pending_worker_exit is a per-turn micro-signal; ensure
  # the next worker starts with a clean slate even if a previous turn
  # crashed before stop-guard.sh could reset it.
  jq '.pending_worker_exit = false' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

  # One worker unit, fresh context. Prompt is phase-dependent so the
  # subprocess executes the correct Step for the current state cursor
  # (negotiation / impl / pr / foundation phases each need different
  # work instructions; a phase-fixed prompt caused subprocesses to
  # exit without mutation when state.phase was outside the default impl path).
  #
  # Every phase prompt MUST contain three boilerplate hints:
  #   1. PRE-FLIGHT Step 3 self-check (sprint_branch == null OR git
  #      branch != expected → run SKILL.md Step 3, update sprint_branch).
  #   2. Phase-specific work instructions.
  #   3. EXIT signal: after the durable write that ends this turn,
  #      atomically set _state.json.pending_worker_exit = true so
  #      stop-guard.sh allows the natural exit. Without this signal,
  #      negotiation phases (which never advance `iteration`) hang
  #      until a Principal Skinner cap fires.
  PRE_FLIGHT='PRE-FLIGHT (Step 3 sprint branch self-check, see SKILL.md §Step 3): compute expected branch = harness/<current_epic>/sprint-<current_sprint>-<feature> (feature from roadmap; bundle peer uses primary-peer feature). If state.sprint_branch is null OR `git rev-parse --abbrev-ref HEAD` differs from expected, execute Step 3 (git checkout -b expected if missing, else git checkout expected), atomically write _state.json.sprint_branch = expected, and append a progress.md line. Skip when phase is foundation-* and the foundation protocol owns branch setup.'
  EXIT_SIGNAL='EXIT SIGNAL: as the LAST durable write of this invocation, atomically set _state.json.pending_worker_exit = true (jq | mv) so stop-guard.sh allows the natural exit. The flag is auto-cleared on the next allow-stop and on the next wrapper tick.'

  phase=$(jq -r '.phase // "impl"' "$STATE")
  case "$phase" in
    negotiation)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute exactly one negotiation round (Generator turn + Evaluator turn per references/negotiation-protocol.md §Round), including validate-generator-report.sh and validate-evaluator-report.sh immediately after their dispatches. After the round summary commit, ${EXIT_SIGNAL} Then exit."
      ;;
    impl|evaluation)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute exactly one iteration (one Generator turn + one Evaluator turn + Step 7 checkpoint), including validate-generator-report.sh and validate-evaluator-report.sh immediately after their dispatches. After the Step 7 atomic commit, ${EXIT_SIGNAL} Then exit."
      ;;
    pr)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute Step 8 per references/pr-creation-guide.md: push the sprint branch if needed, run gh pr create, record the PR URL to _state.json.sprint_prs[<n>], append shared_state.md/Decisions and progress.md, then commit. If roadmap has more sprints, execute Step 9 transition: current_sprint++, iteration=0, phase=negotiation, start_time=now, rubric_stagnation_count=0, features_pass_fail=[], **sprint_branch=null, negotiation_round=0, last_agent=null** (these last three prevent stale carry-over into the next sprint). Otherwise assert _state.json.sprint_prs[1..current_sprint] are all non-null, then set completed=true, phase=done. After the durable transition write, ${EXIT_SIGNAL} Then exit."
      ;;
    foundation-setup|foundation-attest)
      prompt="Resume /harness-loop. Follow references/foundation-loop-protocol.md for the current foundation phase (setup or attest). After the durable phase write that ends this turn (Attest record / verification commit / pending_human flip), ${EXIT_SIGNAL} Then exit."
      ;;
    done)
      printf '[%s] ralph: phase=done, exiting\n' "$(date -u +%FT%TZ)" >> "$PROGRESS"
      exit 0
      ;;
    *)
      prompt="Resume /harness-loop. Read .harness/progress.md (tail 30) and .harness/_state.json.

${PRE_FLIGHT}

Execute the appropriate Step for phase=${phase} according to SKILL.md. After the durable write that ends this turn, ${EXIT_SIGNAL} Then exit."
      ;;
  esac

  printf '[%s] ralph: launching worker phase=%s iter=%s\n' "$(date -u +%FT%TZ)" "$phase" "$iter" >> "$PROGRESS"
  claude -p --permission-mode bypassPermissions "$prompt"
  # The skill writes _state.json inside the call; this loop reads fresh values next tick.
done
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Epic completed; nothing to do |
| 1 | Principal Skinner stop or pending_human halt |
| 2 | Pre-flight failed (missing jq / claude / `_state.json`) |

## Worker model, timeout, and progress budget knobs

The wrapper reads these optional `.harness/_config.yml` keys:

```yaml
worker_model: sonnet
worker_model_high_risk: opus
worker_model_high_risk_phases:
  - negotiation
  - pr
worker_timeout_sec_default: 1800
worker_timeout_sec_negotiation: 600
worker_timeout_sec_pr: 300
# Optional per-(phase × model) override; see below.
# worker_timeout_sec_impl_opus: 2700
worker_timeout_grace_sec: 10
progress_tail_lines: 30
progress_rotation_on_epic_complete: true
tool_log_external: true
```

`worker_model` is used for ordinary worker turns to reduce long-running
weekly token pressure. Phases listed in `worker_model_high_risk_phases`
use `worker_model_high_risk` when configured. A worker that exceeds its
phase timeout receives SIGTERM, then SIGKILL after the grace period; the
wrapper logs the non-zero exit and continues to the next tick instead of
dying with `set -e`.

`worker_timeout_for_phase()` resolves the timeout in this order, so a
slower model under a given phase can get more headroom without changing
the other phases:

1. env `HARNESS_WORKER_TIMEOUT_SEC` (highest; overrides everything)
2. `worker_timeout_sec_<phase>_<model>` — the model resolved for that
   phase via `worker_model_for_phase()` (e.g. `worker_timeout_sec_pr_opus`)
3. `worker_timeout_sec_<phase>` — the existing phase-only key
   (`negotiation` / `pr`)
4. `worker_timeout_sec_default` (else literal `1800`)

The flat `worker_timeout_sec_<phase>_<model>` keys are optional. When none
are set the resolution collapses to the legacy phase-only behaviour
(1800 / 600 / 300), so existing configs are unaffected.

When `progress_rotation_on_epic_complete` is true, the wrapper moves the
completed epic's root `.harness/progress.md` to
`.harness/<epic>/progress-completed.md` and starts a fresh root progress
log. When `tool_log_external` is true, hook-level machine rows go to
`.harness/tool_log.jsonl` instead of the human narrative.

## Why `-p --permission-mode bypassPermissions` and no session-resume flags

- `-p`: non-interactive worker execution. Keeps the subprocess contract
  shell-friendly without bypassing harness-required hooks, CLAUDE.md
  loading, plugins, or credentials. `-p` alone only skips the workspace
  trust dialog — approval prompts for Bash / Edit / Write still fire
- `--permission-mode bypassPermissions`: skip the UI approval prompt for
  every tool use so an unattended worker can actually do work. Hooks
  (PreToolUse / PostToolUse / Stop) **still run**, so
  `.harness/scripts/tier-a-guard.sh` continues to deny Tier-A patterns
  and set `pending_human=true` — the safety rail is preserved, only the
  user-facing prompt is suppressed
- No minimal-mode flag: skipping hooks / CLAUDE.md discovery / plugin
  sync / keychain reads removes the harness safety rails entirely, so
  any flag with those side-effects is a non-starter
- No `--continue`: every invocation is fresh context. Ralph *is* fresh
  context; inheriting a prior session defeats the pattern
- No `--resume`: resume stitches old context back in — same objection

The harness pattern is: the three durable files carry everything
necessary to pick up. If they can't, we have a bug in the Orchestrator's
state writing, not a reason to keep session memory. Fresh context still
comes from re-invoking `claude -p --permission-mode bypassPermissions`
per iteration; hook-based safety (tier-a-guard) is what actually gates
dangerous operations, not the interactive approval prompt.

## Scheduled mode variant

`scheduled` is the hybrid: run `continuous` for N iterations, then
one `autonomous-ralph` iteration to flush context, repeat. Use when
the project is too large for pure continuous (context rot mid-sprint)
but pure Ralph's Boot cost dominates.

```bash
# ralph-loop.sh but with:
RALPH_EVERY=${RALPH_EVERY:-5}
continuous_iters_remaining=${RALPH_EVERY}

while :; do
  # ...Principal Skinner gates as above...

  if (( continuous_iters_remaining > 0 )); then
    # one continuous step: keep the same claude session
    claude -p "..."  # orchestrator advances 1 iter in same process
    continuous_iters_remaining=$(( continuous_iters_remaining - 1 ))
  else
    # one Ralph step: fresh context
    claude -p "Resume /harness-loop one iteration..."
    continuous_iters_remaining=${RALPH_EVERY}
  fi
done
```

`RALPH_EVERY` comes from (in order): the `--ralph-every <N>` CLI flag
passed to `/harness-loop`, the `RALPH_EVERY` env var, or the literal
default `5`. v1 does not read this from `_config.yml`; `harness-init`
is not aware of the key.

## Running overnight

For overnight or multi-hour runs:

1. Start `/harness-loop --mode autonomous-ralph` from an interactive
   Claude Code session
2. Let the supervisor attach or spawn the wrapper via `.harness/ralph.pid`
3. Ensure `max_wall_time_sec` and `max_cost_usd` match your budget
4. Keep the supervisor session available for event relay and
   `pending_human` intervention
5. On resume, rerun `/harness-loop --mode autonomous-ralph`; the
   supervisor must reattach instead of spawning a duplicate wrapper

`ralph-loop.sh` remains the worker launcher, but it is not a user-facing
entrypoint.

## Tier-A halts during Ralph

`.harness/scripts/tier-a-guard.sh` (installed by `harness-init`) sets
`pending_human=true` when it denies a Tier-A operation. The wrapper's
next tick exits without launching a new worker. The supervisor —
interactive or autonomous — owns recovery, and recovery only fires
when classification of `tier_a_last.cmd` reaches "false positive".
This matters most for unattended runs: there is no human to consult,
so the supervisor must classify and decide on its own (or leave the
halt in place):

1. Inspect the denied action from `progress.md` / `ralph.log` and
   `_state.json.tier_a_last.cmd`
2. Classify the cmd:
   - **False positive** — cmd is benign for this project (Evaluator
     cleanup script on a project-internal absolute path, build-
     artifact `rm` under `/tmp/...`, etc. — the kind the system-path
     whitelist was designed to ignore)
   - **True Tier-A violation** — cmd would actually destroy OS state,
     force-push to a protected branch, drop a production table, etc.
   - **Uncertain**
3. Decide:
   - False positive → run the recovery sequence below
   - True violation → leave the halt; never auto-clear in unattended
     mode (a silent auto-clear would defeat the guard's purpose).
     If a human is attached, `AskUserQuestion` may surface the cmd
     for explicit override
   - Uncertain → leave the halt; the bias is "halt rather than guess
     wrong"
4. Re-attach or restart the wrapper via `.harness/ralph.pid` only
   after a recovery-eligible classification

After every Monitor event, the supervisor verifies the wrapper is
still alive (`ps -p $(cat .harness/ralph.pid)` or
`kill -0 $(cat .harness/ralph.pid)`). A `halting for approval` event
in `progress.md` implies the wrapper has exited — Monitor events
alone are not proof of liveness; a respawn is required.

The Monitor pattern must include `halting for approval` so the halt is
detected immediately rather than at the next worker-tick failure
(observed deferrals reach tens of minutes when the pattern is
missing). A working regex (see `references/supervisor-dispatch.md`
for the full filter):

```text
negotiation|evaluation|decision|stop|pending_human|halting for approval|TIER-A
```

### Tier-A recovery sequence (idempotent)

Run only after classification reaches "false positive" (or, with a
human attached, an explicit override). Never run on "true violation"
or "uncertain". Safe to re-run; never delegate the edit to the user:

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

No silent auto-clear path. Tier-A guards exist precisely so unattended
mode cannot quietly destroy state. Recovery is supervisor-driven and
classification-gated; the halt is the safety floor.

## Don't do

- Don't `while :; do claude -p --continue ...` — defeats Ralph
- Don't suppress the Principal Skinner block — runaway cost
- Don't parallelise iterations — the state file is the bottleneck
- Don't run two wrappers on the same project — race on `_state.json`
- Don't swallow the wrapper's stderr in production — missed diagnostics

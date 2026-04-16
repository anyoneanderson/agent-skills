# Autonomous Ralph

The `autonomous-ralph` execution mode runs `harness-loop` headlessly,
one iteration per Claude process, with no cross-iteration memory except
`progress.md` + `_state.json` + git + `metrics.jsonl`. "Ralph" is the
canonical name for this pattern (repeatedly re-invoking a fresh agent
on the same checkpointed state).

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

## Wrapper script template

The template below is the authoritative `ralph-loop.sh`. Install it at
`.harness/scripts/ralph-loop.sh` the first time `autonomous-ralph` is
selected (`harness-loop` Step 2 writes it on mode selection; it is not
shipped by `harness-init` in v1). Keep one copy per project — a
project-local edit survives re-installs only if you version it in git.

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE=".harness/_state.json"
PROGRESS=".harness/progress.md"

command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }
command -v claude >/dev/null || { echo "claude CLI required" >&2; exit 2; }
[[ -f $STATE ]] || { echo "_state.json missing; run /harness-init + /harness-plan first" >&2; exit 2; }

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

  # One iteration, fresh context
  printf '[%s] ralph: launching iter=%s\n' "$(date -u +%FT%TZ)" "$iter" >> "$PROGRESS"
  claude -p --bare "Resume /harness-loop. Read .harness/progress.md (tail 100) and .harness/_state.json. Execute exactly one iteration (one Generator turn + one Evaluator turn + Step 7 checkpoint), then exit."
  # The skill writes _state.json inside the call; this loop reads fresh values next tick.
done
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Epic completed; nothing to do |
| 1 | Principal Skinner stop or pending_human halt |
| 2 | Pre-flight failed (missing jq / claude / `_state.json`) |

## Why `--bare` and no `--continue`/`--resume`

- `--bare`: suppresses interactive UI and extra framing. Deterministic
  for shell capture of stdout
- No `--continue`: every invocation is fresh context. Ralph *is* fresh
  context; inheriting a prior session defeats the pattern
- No `--resume`: resume stitches old context back in — same objection

The harness pattern is: the three durable files carry everything
necessary to pick up. If they can't, we have a bug in the Orchestrator's
state writing, not a reason to keep session memory.

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
    claude -p --bare "..."  # orchestrator advances 1 iter in same process
    continuous_iters_remaining=$(( continuous_iters_remaining - 1 ))
  else
    # one Ralph step: fresh context
    claude -p --bare "Resume /harness-loop one iteration..."
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

1. Pick `autonomous-ralph` at loop start
2. Ensure `max_wall_time_sec` matches your budget
   (e.g., 28800 for 8h, the default)
3. Ensure `max_cost_usd` caps spend
   (e.g., 20 for $20, the default)
4. Start the wrapper detached:
   ```bash
   nohup .harness/scripts/ralph-loop.sh >> .harness/ralph.log 2>&1 &
   disown
   ```
5. Monitor via:
   ```bash
   tail -f .harness/progress.md
   tail -f .harness/metrics.jsonl
   ```

On wake: inspect `aborted_reason` in `_state.json` first, then
`progress.md` tail.

## Tier-A halts during Ralph

`.harness/scripts/tier-a-guard.sh` (installed by `harness-init`) sets
`pending_human=true` when it denies a Tier-A operation. The wrapper's
next tick sees this and exits 1 without launching a new Claude
process. The user:

1. Inspects the denied command in `progress.md`
2. Decides: approve (edit the approach) or reject (leave aborted)
3. Manually resets `pending_human=false` in `_state.json`
4. Restarts the wrapper

No bypass path. Tier-A approval is always human-in-the-loop.

## Don't do

- Don't `while :; do claude -p --continue ...` — defeats Ralph
- Don't suppress the Principal Skinner block — runaway cost
- Don't parallelise iterations — the state file is the bottleneck
- Don't run two wrappers on the same project — race on `_state.json`
- Don't swallow the wrapper's stderr in production — missed diagnostics

# Resilience Schema

Canonical schemas for the three files that survive context compaction,
session restart, and process crashes. Together they form the "Anthropic
three-point set" (progress.md + _state.json + git) plus the observability
layer (metrics.jsonl).

Boot Sequence — every skill and sub-agent MUST read these before acting:

1. `git log --oneline -20`
2. `tail -100 .harness/progress.md`
3. `cat .harness/_state.json`

---

## `.harness/progress.md` (human-readable log)

**Purpose**: Free-form narrative of intent, decisions, and next actions.
Durable across `/compact` because it lives outside the context window.

**Writer**: All agents (append-only). Enforced via `PostToolUse(Edit|Write)` hook.

**Format** — one event per line:

```
[<ISO-8601-UTC>] <event>
```

Where `<event>` is one of:

```
tool=<tool_name> file=<file_path> phase=<phase> iter=<N>
   # Emitted by PostToolUse hook on Edit|Write

decision: <text>
   # Orchestrator / Planner writes these for irreversible choices

negotiation: round=<N> agent=<role> summary=<text>
   # Round-by-round negotiation trace (summary; raw messages in feedback/)

evaluation: iter=<N> verdict=<pass|fail> axes="f=0.9 c=0.7 d=0.6 o=0.5"
   # Evaluator verdict per iteration

stop: reason=<max_iter|wall_time|rubric_stagnation|cost_cap|tier_a> detail=<text>
   # Principal Skinner trigger (loop termination condition)

restore: from=<source> preserved=<tokens>
   # Emitted by SessionStart(compact) hook after reinjection
```

**Example tail**:

```
[2026-04-15T09:41:03Z] tool=Write file=src/login.tsx phase=impl iter=3
[2026-04-15T09:41:05Z] tool=Edit file=src/login.test.tsx phase=impl iter=3
[2026-04-15T09:42:14Z] evaluation: iter=3 verdict=fail axes="f=0.6 c=0.8 d=0.7 o=0.6"
[2026-04-15T09:42:14Z] decision: iter=3 failed Functionality threshold; generator to retry
[2026-04-15T09:45:02Z] restore: from=SessionStart(compact) preserved=100-tail-lines
```

**Reading rules**:
- Tail-based. Never parse the entire file — `tail -100` is the contract
- Lines are informational, not executable. Do NOT reconstruct state from
  progress.md alone; always cross-check with `_state.json`
- If a line's format is unknown, ignore it (forward-compatible)

**Rotation**: When size exceeds 1 MiB, rename to `progress.md.<N>.old` and
start fresh. Keep a header link chain to prior segments.

---

## `.harness/_state.json` (machine-readable cursor)

**Purpose**: Single source of truth for orchestration position. Fully
deterministic to parse; used by `harness-loop`, hooks, and Autonomous Ralph
to decide the next action.

**Writer**: Orchestrator only (harness-loop). Updated once per iteration.

**Schema version**: 1

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

### Field reference

| Field | Type | Required | Description |
|---|---|---|---|
| `schema_version` | int | yes | Migrate on bump. Starts at 1 |
| `current_epic` | string | yes | Directory under `.harness/` |
| `current_sprint` | int | yes | 1-indexed sprint number |
| `phase` | enum | yes | `negotiation \| impl \| evaluation \| pr \| done` |
| `iteration` | int | yes | 0 before first, increments after each Generator → Evaluator cycle |
| `max_iterations` | int | yes | Principal Skinner cap (default 8) |
| `max_wall_time_sec` | int | yes | Principal Skinner wall-time cap (default 28800 = 8h) |
| `max_cost_usd` | number | yes | Principal Skinner cost cap (default 20.0) |
| `cumulative_cost_usd` | number | yes | Running sum from metrics.jsonl |
| `start_time` | ISO-8601 | yes | When current sprint entered negotiation |
| `last_agent` | enum | yes | `planner \| generator \| evaluator \| orchestrator` |
| `next_action` | string | yes | Free-form hint for the next executor |
| `last_commit` | string\|null | yes | SHA of the most recent iteration commit |
| `features_pass_fail` | array | yes | Per-feature axis verdicts for the current sprint |
| `completed` | bool | yes | True only when all sprints in the epic are done |
| `pending_human` | bool | yes | True when Tier-A guard or ambiguous-request (v2) is triggered |
| `aborted_reason` | string\|null | yes | Non-null when a Principal Skinner condition fired |
| `mode` | enum | yes | `interactive \| continuous \| autonomous-ralph \| scheduled` |
| `rubric_stagnation_count` | int | yes | Consecutive iterations with no rubric improvement; reset on any axis upgrade |

> `stop_hook_active` is **not** a persistent `_state.json` field. It is a
> stdin-only flag supplied by Claude Code's hook runner to prevent Stop-hook
> recursion, and `stop-guard.sh` only reads it (`jq -r '.stop_hook_active'`
> on the hook payload). If a future version needs a durable anti-recursion
> counter, it should be added here as a new field.

### Update rules

- Write atomically: `_state.json.tmp` → `fsync` → `rename`. Partial writes
  must never be observable.
- On every iteration end, update: `iteration`, `last_agent`, `next_action`,
  `last_commit`, `cumulative_cost_usd`, and relevant `features_pass_fail`.
- Never delete. On abort, set `aborted_reason` and `completed: false`.
  Resume is then a conscious user decision.
- `.stop_hook_active` is read by `stop-guard.sh` from the Stop-hook stdin
  payload, not from `_state.json`. Claude Code sets it to `true` on the
  recursive call that follows a previous `{"decision":"block"}` decision,
  so the second invocation short-circuits and exits 0. No persistence is
  required on our side.

### Schema migration

When `schema_version` increments, `harness-init` ships a `migrate-<n>-to-<m>.sh`
script under `.harness/scripts/` that rewrites existing `_state.json` files.
Old files are backed up to `_state.json.v<N>.bak` first.

---

## `.harness/metrics.jsonl` (observability)

**Purpose**: Per-iteration metrics for cost control and trend analysis.
JSON Lines so a tail reader / OTLP exporter can stream it.

**Writer**: Orchestrator appends one line at the end of each iteration.

**Schema** — one object per line:

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

### Field reference

| Field | Type | Required | Description |
|---|---|---|---|
| `ts` | ISO-8601 | yes | End-of-iteration timestamp |
| `iter` | int | yes | Matches `_state.json.iteration` at emission |
| `sprint` | int | yes | Matches `_state.json.current_sprint` |
| `agent` | string | yes | Which agent produced this iteration's work |
| `duration_ms` | int | yes | Wall-clock time for this iteration |
| `input_tokens` | int | no | Empty when not reported by the model |
| `output_tokens` | int | no | Same |
| `cost_usd` | number | yes | Per-iteration cost; summed into `cumulative_cost_usd` |
| `rubric_scores` | object | yes | Axis → score ∈ [0, 1] |
| `tool_calls` | int | yes | Total tool invocations by the agent this iteration |
| `tool_failures` | int | yes | Of those, how many returned non-zero / errored |

**Aggregation**: `cumulative_cost_usd` in `_state.json` is the canonical
running sum. Never re-derive it by summing metrics.jsonl on read — trust
the cursor.

**OTLP export (optional)**: `.harness/scripts/metrics-exporter.sh`
tails this file and POSTs to `_config.yml.otlp_endpoint`. No-op when
endpoint is unset or `hook_level != strict`.

---

## Resume / Recovery Protocol

Whenever a skill restarts (new session, `/compact`, Ralph fresh iteration,
crash recovery):

```
1. Run Boot Sequence (git log -20, progress.md tail -100, _state.json cat).
2. If _state.json.completed == true:
     sprint/epic is done. Decide: new epic? new sprint? or exit.
3. Else if _state.json.aborted_reason != null:
     Principal Skinner stopped us. Do NOT auto-resume in autonomous modes.
     Require explicit user action.
4. Else if _state.json.pending_human == true:
     Tier-A or ambiguous-request pending. Stop and surface to user.
5. Else:
     Resume at _state.json.phase with _state.json.next_action as the hint.
     Re-enter the appropriate agent (Planner / Generator / Evaluator).
```

**Guarantee**: steps 1–5 use only these three files plus git. No process
memory, no prior session context is required.

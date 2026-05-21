# Resilience Schema

Canonical schemas for the three files that survive context compaction,
session restart, and process crashes. Together they form the "Anthropic
three-point set" (progress.md + _state.json + git) plus the observability
layer (metrics.jsonl).

Boot Sequence — every skill and sub-agent MUST read these before acting:

1. `git log --oneline -20`
2. `tail -30 .harness/progress.md` (or `_config.yml.progress_tail_lines`)
3. `cat .harness/_state.json`

---

## `.harness/_config.yml` (static orchestration config)

**Purpose**: Durable runtime knobs produced by `harness-init` and read by
`harness-loop`, hooks, and backend dispatch helpers.

Relevant `codex_cmux` completion-signal keys:

```yaml
evaluator_tools:
  - playwright-mcp   # or playwright-cli / curl / custom-script
codex_cmux_idle_dwell_polls: 2
codex_cmux_idle_poll_seconds: 20
```

- `evaluator_tools`: single-item list in v1. Allowed values are
  `playwright-mcp`, `playwright-cli`, `curl`, and `custom-script`
- `codex_cmux_idle_dwell_polls`: number of consecutive idle polls
  required before the pane is considered complete
- `codex_cmux_idle_poll_seconds`: seconds between idle polls

If these keys are absent, the defaults above apply.

Relevant Autonomous Ralph cost / liveness keys:

```yaml
worker_model: sonnet
worker_model_high_risk: opus
worker_model_high_risk_phases:
  - negotiation
  - pr
worker_timeout_sec_default: 1800
worker_timeout_sec_negotiation: 600
worker_timeout_sec_pr: 300
# Optional per-(phase × model) overrides (flat keys). See note below.
# worker_timeout_sec_impl_opus: 2700
# worker_timeout_sec_pr_opus: 600
worker_timeout_grace_sec: 10
staleness_threshold_sec: 1800
staleness_interval_sec: 300
staleness_auto_recover: false
max_staleness_recoveries_per_sprint: 3
tier_a_history_external: true
progress_rotation_on_epic_complete: true
progress_tail_lines: 30
tool_log_external: true
```

- `worker_model`: default model for non-interactive worker turns
- `worker_model_high_risk` / `worker_model_high_risk_phases`: optional
  phase override for high-risk orchestration turns
- `worker_timeout_*`: per-worker timeout and graceful termination window.
  The wrapper resolves a phase's timeout as env `HARNESS_WORKER_TIMEOUT_SEC`
  → `worker_timeout_sec_<phase>_<model>` (optional flat override keyed on the
  model resolved for that phase) → `worker_timeout_sec_<phase>` →
  `worker_timeout_sec_default`. The model-specific keys are optional; when
  absent the resolution collapses to the legacy phase-only defaults
  (1800 / 600 / 300), so existing configs behave identically
- `staleness_*`: watchdog warning / opt-in recovery controls
- `tier_a_history_external`: archive resolved Tier-A events in
  `.harness/_audit/tier_a_history.jsonl` instead of bloating `_state.json`
- `progress_rotation_on_epic_complete`: move a completed epic's root
  progress log to `.harness/<epic>/progress-completed.md`
- `progress_tail_lines`: default progress tail injected into fresh context
- `tool_log_external`: write hook-level machine rows to
  `.harness/tool_log.jsonl` instead of the human progress narrative

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
- Tail-based. Never parse the entire file — `tail -30` is the contract
- Lines are informational, not executable. Do NOT reconstruct state from
  progress.md alone; always cross-check with `_state.json`
- If a line's format is unknown, ignore it (forward-compatible)

**Rotation**: When `progress_rotation_on_epic_complete` is true, the
Autonomous Ralph wrapper moves the completed epic's root progress file to
`.harness/<epic>/progress-completed.md` and starts a fresh root
`progress.md`. If size-based rotation is needed outside epic boundaries,
rename to `progress.md.<N>.old` and start fresh. Keep a header link chain
to prior segments.

**Machine rows**: When `tool_log_external` is true, PostToolUse-style
machine rows are written to `.harness/tool_log.jsonl` instead of
`progress.md`; `progress.md` remains the human-readable narrative.

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
  "negotiation_round": 2,
  "iteration": 3,
  "foundation_readiness": {
    "severity": "GREEN",
    "verified_at": "2026-04-21T07:45:00Z",
    "ok": ["package_manifest", "runtime_boots", "test_runner_configured", "env_example_committed", "external_setup_doc", "tracker_wired", "dev_db_available"],
    "missing": [],
    "unknown": []
  },
  "foundation_sprint_needed": false,
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
  "pending_worker_exit": false,
  "sprint_branch": null,
  "tier_a_last": null,
  "tier_a_history": [],
  "tier_a_summary": {"count": 0, "last_at": null, "last_pattern": null},
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
| `negotiation_round` | int | yes | 0 before first negotiation turn; increments per Generator/Evaluator negotiation round |
| `iteration` | int | yes | 0 before first, increments after each Generator → Evaluator cycle |
| `foundation_readiness` | object\|null | yes | Latest `foundation-readiness.sh --epic` summary for the current epic; includes `severity`, probe buckets, and `verified_at` |
| `foundation_sprint_needed` | bool | yes | Whether roadmap generation should insert sprint-0; reset to `false` once sprint-0 attestation succeeds |
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
| `pending_worker_exit` | bool | yes | Micro-signal raised by the Orchestrator at the end of a worker turn (negotiation round commit, contract-freeze commit, iteration checkpoint commit, foundation-attest, sprint transition). Read by `stop-guard.sh` to allow the Stop hook to fall through even when Principal Skinner caps have not fired; auto-reset to `false` on the next allow-stop. Distinct from the macro `completed` / `pending_human` / Principal Skinner caps |
| `sprint_branch` | string\|null | yes | Active sprint branch name (`harness/<epic>/sprint-<n>-<feature>`). Set by Step 3, used by Step 7 / Step 8 commits, **reset to `null` by Step 9 sprint transition** so the next sprint's Step 3 (or wrapper pre-flight) recreates it cleanly |
| `tier_a_last` | object\|null | yes | Active unresolved Tier-A event; clear it back to `null` once a `resolution` is recorded |
| `tier_a_history` | array | yes | Legacy inline archive. Keep as `[]` when `tier_a_history_external` is true |
| `tier_a_summary` | object | no | Compact summary of `.harness/_audit/tier_a_history.jsonl` (`count`, `last_at`, `last_pattern`) |
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
- On every negotiation round end, update: `negotiation_round`,
  `last_agent`, `next_action`, and `phase`.
- On every implementation iteration end, update: `iteration`,
  `last_agent`, `next_action`, `last_commit`, `cumulative_cost_usd`, and
  relevant `features_pass_fail`.
- When Step 3.5 or sprint-0 attestation runs `foundation-readiness.sh
  --epic`, write the returned summary to `foundation_readiness`. The
  sprint-0 attestation refresh must also set
  `foundation_sprint_needed=false`.
- `tier_a_last` is the live slot only. Once an operator records a
  `resolution`, move that object into `.harness/_audit/tier_a_history.jsonl`
  when `tier_a_history_external` is true, update `tier_a_summary`, and
  clear `tier_a_last` back to `null` so future guards do not treat it as an
  active escalation. Legacy inline `tier_a_history` should remain `[]` in
  external mode.
- `pending_worker_exit` is a single-turn micro-signal owned by the
  Orchestrator. Set it to `true` immediately AFTER the durable write
  that ends a worker turn (Step 5 contract-freeze commit, Step 7
  iteration-checkpoint commit, Step 9 sprint-transition state write,
  foundation-loop-protocol Attest write). `stop-guard.sh` consumes the
  flag by allowing stop AND atomically resetting it to `false`, so it
  never carries over to the next worker invocation. The wrapper
  (`autonomous-ralph` Ralph loop) also resets it to `false` immediately
  before each `claude -p` launch as a defensive guard.
- `sprint_branch` is set by Step 3 (`harness/<epic>/sprint-<n>-<feature>`,
  primary peer's name for bundles), reused by Step 7 / Step 8 commits,
  and **reset to `null` by Step 9 sprint transition**. A `null` value is
  the cursor that tells Step 3 (or the wrapper pre-flight) the branch
  must be (re)created on the next worker tick.
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
1. Run Boot Sequence (git log -20, progress.md tail -30, _state.json cat).
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

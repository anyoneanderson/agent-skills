# Role Dispatch — Resolving Who Runs Each Phase

Every phase names an AI role key (e.g. `spec_author`, `e2e_runner`). This file is
the single place that first resolves the key to an AI role (`claude` or `codex`)
and then resolves that role to an execution backend for the current host. Phase
guides reference this file rather than repeating either decision.

日本語版: [role-dispatch.ja.md](role-dispatch.ja.md)

## Step 0: Determine and Record the Host Runtime

Before reading any role, explicitly set `host_runtime` to the identity of the
runtime executing spec-orchestrate: `codex` in Codex or `claude` in Claude Code.
Record it in `pipeline-state.json` during intake. On resume, determine it again
and update the recorded value before dispatching another worker; never infer it
from role defaults or from agent-delegate environment variables.

If the current runtime cannot identify itself:

- **manual:** ask the human to select `codex` or `claude`, then record it.
- **auto:** stop in a resumable blocked state with `host_runtime_unknown`; do not
  guess and do not dispatch a worker.

## Step 1: Read the AI Roles

Read `roles` from `pipeline.yml` (default path `.specs/pipeline.yml`; format in
`pipeline-config.md`). When the file is absent, use these defaults verbatim:

| Role key | Default | Phase |
|----------|---------|-------|
| `spec_author` | `claude` | spec_generate |
| `spec_reviewer` | `codex` | spec_review |
| `impl_ui` | `claude` | implement (ui tasks) |
| `impl_backend` | `codex` | implement (backend tasks) |
| `impl_test` | `codex` | implement (test tasks) |
| `e2e_runner` | `claude` | evaluate |

A role value selects an AI, not a backend. It is always `claude` or `codex`.
Anything else is a config error — stop and report it.

## Step 2: Resolve the Backend

Resolve the backend only after the AI role is final. Matching host and role use
the host's runtime-native subagent mechanism. A different role uses
agent-delegate with the role as the explicit target.

<!-- dispatch-matrix:start -->
| Host runtime | AI role | Backend | agent-delegate target |
|--------------|---------|---------|-----------------------|
| `codex` | `codex` | `runtime-native` | `-` |
| `codex` | `claude` | `agent-delegate` | `claude` |
| `claude` | `claude` | `runtime-native` | `-` |
| `claude` | `codex` | `agent-delegate` | `codex` |
<!-- dispatch-matrix:end -->

For `runtime-native`, dispatch a subagent in the current runtime and do **not**
start agent-delegate. Use the role-specific agent definition when one is
installed: for example, `workflow-planner` for the spec author and
`workflow-evaluator` for E2E. The native path names no specific dispatch tool;
use whatever the current runtime provides and do not hardcode a tool name.

For `agent-delegate`, call the script per its public contract and always pass
`--target <AI role>` explicitly. Programmatic callers must not rely on
environment self-detection in a nested chain.

**agent-delegate is a contract dependency.** Call the script per
`agent-delegate/references/contract.md` (arguments + `report.json` schema) and
never depend on its internals.

## Step 3: Choose Sync vs Detached Execution

The caller chooses the form from mutation risk and a concrete time basis:

| Phase kind | Form | Why |
|------------|------|-----|
| spec generation or repair, implement (code), evaluate (E2E), evidence recording | explicit `--detach` | These delegates write files |
| read-only spec_review, investigation, or artifact review with a concrete basis for completion within 5 minutes | synchronous | Read-only and demonstrably short |
| any role without that concrete 5-minute basis | `--detach` | An unbounded caller wait is not allowed |

Detached launch capture (per the contract):
```bash
launch="$(agent-delegate.sh --mode <delegate|review> --target <AI-role> ... --detach)"
expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
```

**The wait must survive the waiter's turn.** A bare in-turn polling loop dies the
moment the waiting agent ends its turn, leaving no one to observe the expected run.
There is exactly one standard way to wait, plus a backup rule:

- **Standard wait:** run a *background job of the host runtime* that applies
  agent-delegate's expected-run state machine every 15 seconds and never less
  often than every 30 seconds. Each poll validates the expected-run report first,
  then owner, pid, heartbeat, and process state. It keeps waiting through
  `RUNNING`, every `DEGRADED_*`, `ORPHANED_WORKER`, `FINALIZING`, and
  `REPORT_INVALID_PENDING`; report absence alone is not failure. The job must
  survive the turn and re-invoke the dispatcher at a terminal or actionable
  state. Never leave a foreground poll as the only waiter, and never end the turn
  with nothing armed. Before yielding, register the awaited path in the run marker (`jq '.waiting_report = $p'` on
  `.specs/.orchestrate-active.json` — see `pipeline-config.md` §Run marker) so
  the watchdog knows the pause is legitimate; clear it after collecting the
  result. The watcher itself retains `expected_run_id`. An unregistered pause is
  indistinguishable from a stall and will be blocked.
- **Backup watch:** whenever a sub-worker owns a detached wait, the orchestrator
  arms its own background watch for the same expected run. If the backup reaches
  an actionable state first, verify the result and nudge (or replace) the stalled worker.
  This is standard procedure, not an optional extra.

Caller-owned timeouts are at least 20 minutes for specification generation or
repair and at least 30 minutes for implementation or E2E. A timeout triggers a
fresh state evaluation; it does not convert a missing report into failure.

## Phase-Specific Resolution

### spec_review (adversarial spec review)

Resolve `spec_reviewer` through the matrix, then run it in review/read-only mode.
A matching role uses a native reviewer subagent. A different role uses
agent-delegate `--mode review --target <spec_reviewer>`. Use synchronous
agent-delegate execution only with a concrete basis for completion within 5
minutes; otherwise use `--detach` and the expected-run wait above.
Round 1 creates the session; rounds ≥ 2 resume it with `--resume <thread_id>`
from `threads.spec_reviewer` in state (a review session is created read-only, the
only sandbox a resume can keep).

### spec_generate (spec author)

Resolve `spec_author` through the same matrix. A matching role runs
`workflow-planner` as a runtime-native subagent. A different role runs
agent-delegate `--mode delegate --target <spec_author> --detach` because the
author writes specification files.

### evaluate (acceptance test)

Pass the resolved `e2e_runner` AI role **explicitly** as `--backend` and the
recorded host as `--host-runtime` when dispatching spec-evaluate. The option name
`--backend` is retained for compatibility, but its `claude|codex` value selects
the AI role; spec-evaluate applies this matrix to choose the vehicle. Its
standalone default is `self`, so relying on that inside the pipeline would mix
two defaults. See spec-evaluate `references/execution-backend.md`.

### implement (build the feature)

Do **not** route implementation tasks one-by-one from here. Pass the `impl_*`
roles to spec-implement as its `--roles` argument, and let spec-implement do the
per-task `kind → owner` routing internally (no double management).

- Build the map from `roles`: `ui=<impl_ui>,backend=<impl_backend>,test=<impl_test>`,
  or pass the `pipeline.yml` path (spec-implement reads `roles.impl_{kind}` from it).
- Pass the recorded host as `--host-runtime <host_runtime>` so spec-implement
  applies this matrix per task.
- A task whose `kind` is unknown or unmapped falls back to spec-code (claude) —
  spec-implement's documented legacy behavior.

## Reviewer Inversion (single definition)

The reviewer of an implementation artifact is always the **opposite AI role**
from its implementer — "the author does not review their own work". Choose the
reviewer role first, then resolve that role through the host-aware matrix. Never
choose a backend first. This rule is defined here once; spec-implement applies it
per task from the `--roles` map, so it is not re-implemented by the orchestrator.

| Task implementer (from `kind`) | Reviewer AI role |
|--------------------------------|------------------|
| `codex` | `claude` |
| `claude` | `codex` |

Apply the matrix independently to the implementer and reviewer roles. For
example, on a Codex host a Codex implementer is native and its Claude reviewer
uses agent-delegate; on a Claude host the same roles use agent-delegate and
native review respectively. Fixes return to the implementer role and resolve
through the matrix again. An agent-delegate review file is spec-review-compatible,
so the existing fix loop consumes it unchanged.

## Capability Fallbacks

Every fallback must preserve the separation between AI role and backend and must
be recorded in `state.role_overrides` and the PR body.

- **Runtime-native subagent unavailable:** manual asks whether to reassign the
  worker role to the opposite AI or stop. Auto reassigns to the opposite AI only
  when its peer CLI is available; otherwise it blocks. A reviewer may never be
  reassigned to its implementer's AI role, so manual asks for a compatible
  independent reviewer and auto blocks instead of allowing self-review.
- **Cross-AI peer CLI unavailable** (script missing, exit 2, or
  `tool_unavailable`): manual asks whether to reassign the worker role to the
  host AI. Auto reassigns it to the host AI and continues. For a reviewer, that
  reassignment is forbidden when the host AI implemented the artifact; manual
  asks for an independent reviewer and auto blocks.
- **Host runtime unknown:** use the Step 0 manual/auto behavior. No role can be
  resolved until the host is known.

Capability fallback is distinct from the stall-driven role swap in arbitration
(`stall-detection.md`), which is capped by `limits.role_swap_max`.

## Contract Test

Run `bash references/scripts/tests/run_tests.sh` from the spec-orchestrate skill
directory. The tracked fixture covers all four matrix rows with a positive
expected mapping, corrupts each row to prove the reversed mapping is rejected,
checks all six marked matrix copies across the three skills, and verifies that
state rejects an unknown `host_runtime`.

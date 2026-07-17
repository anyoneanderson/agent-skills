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

Before launch, the phase owner records each expected artifact's exact path,
freshness baseline, caller-generated correlation value, and phase-specific
validator. This predeclared set is the only artifact recovery contract; a
validator created after failure cannot authorize recovery. For review and other
read-only phases, it also records a pre-launch git snapshot of the workspace,
excluding only the declared out-dir. The snapshot uses the content-level
fingerprint defined by the agent-delegate contract, not a path or status list.

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

At 30 minutes, and again at 60 and 90 minutes, the background watcher performs
a report-first state re-evaluation and records the last owner, pid, heartbeat,
process probes, and report-validation error. A waiting state continues; a
missing report alone is not failure.

At 2 hours from `launched_at`, the watcher re-evaluates once more. It returns a
new terminal, `SUPERSEDED`, or `DEAD` result without signaling. Otherwise, if
the expected owner still matches and its monitor is alive, it sends `TERM` to
that monitor and waits up to 90 seconds for the expected-run terminal report.
If the monitor is absent or unknown, or the grace period expires, the watcher
clears `waiting_report`, stops waiting, and reports the saved diagnostics to the
human operator. This path never invokes `--force` or signals an unidentified
process.

When the expected-run terminal report is `blocked` with
`blocker_category: env_error`, the watcher runs fail-closed artifact recovery
before dispatching a blocked result. It adopts a task result only when the
predeclared artifact is fresh, correlated, and passes the phase validator; the
blocked report remains a runtime diagnostic. Other blocked categories and
failed recovery remain blocked. A host that reaps detached monitors may use a
synchronous bounded `until` loop over the same validator and original launch
deadline. That loop does not relax eligibility: if a valid expected-run
`env_error` report never appears, recovery is rejected and the watcher
escalates diagnostics at the deadline. Monitor loss or a missing idle signal
alone is not failure.

## Phase-Specific Resolution

### spec_review (adversarial spec review)

Resolve `spec_reviewer` through the matrix, then run it in review/read-only mode.
A matching role uses a fresh native reviewer subagent, separate from the spec
author context. A different role uses
agent-delegate `--mode review --target <spec_reviewer>`. Use synchronous
agent-delegate execution only with a concrete basis for completion within 5
minutes; otherwise use `--detach` and the expected-run wait above.
Round 1 creates the session; rounds ≥ 2 resume it with `--resume <thread_id>`
from `threads.spec_reviewer` in state (a review session is created read-only, the
only sandbox a resume can keep). If the cross-AI peer is unavailable, use the
independent native review fallback below instead; it is sessionless and launches
a fresh reviewer subagent each round.

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
- Pass `--review-fallback native-independent`. This is the explicit boundary
  that lets spec-orchestrate finish on a single-AI installation; standalone
  spec-implement keeps its default `block` behavior.
- A task whose `kind` is unknown or unmapped falls back to spec-code (claude) —
  spec-implement's documented legacy behavior.

## Preferred Cross-AI Review and Independence (single definition)

The preferred reviewer of an implementation artifact is the **opposite AI role**
from its implementer. Choose the preferred reviewer role first, then resolve it
through the host-aware matrix. Never choose a backend first. This rule is
defined here once; spec-implement applies it per task from the `--roles` map, so
it is not re-implemented by the orchestrator.

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

Cross-AI identity is preferred; **independent execution identity and context are
required**. When the preferred cross-AI reviewer is unavailable,
`native-independent` may use the host AI role only under all of these controls:

1. launch a fresh runtime-native reviewer subagent, never the orchestrator or
   implementer instance and never a resume of the implementation conversation;
2. give it only the artifact/diff, specs, review criteria, and prior review
   findings plus fix summary on later rounds;
3. expose no write tools and compare one repository change fingerprint captured
   immediately before reviewer launch with another captured after review
   completion: tracked worktree and staged diff content plus non-ignored
   untracked path and content. Exclude only orchestrator-owned run-record paths
   classified in `pipeline-config.md`, never the whole `.specs/` directory. Any
   change in the included fingerprint invalidates the result and blocks the run
   for the normal workspace-drift procedure;
4. launch a fresh sessionless reviewer again for every re-review round; and
5. append a `state.review_fallbacks` entry containing the host runtime at review
   time and disclose reduced cross-AI assurance in the PR body. For implement
   reviews, spec-implement returns the structured entry and the orchestrator
   appends it; workers never write pipeline state.

If the runtime cannot guarantee those controls, the reviewer is unavailable and
the pipeline blocks. A same-AI review performed in the orchestrator or the
implementer context is self-review and is never accepted.

## Capability Fallbacks

Every fallback must preserve the separation between AI role and backend.
Non-review role changes are recorded in `state.role_overrides`; independent
review fallbacks are recorded in `state.review_fallbacks`. Both appear in the PR
body.

- **Runtime-native subagent unavailable:** manual asks whether to reassign the
  worker role to the opposite AI or stop. Auto reassigns to the opposite AI only
  when its peer CLI is available; otherwise it blocks. A reviewer blocks because
  the runtime cannot create the independent native reviewer required by the
  fallback contract.
- **Cross-AI peer CLI unavailable** (script missing, exit 2, or
  `tool_unavailable`): for a non-review worker, manual asks whether to reassign
  its role to the host AI; auto reassigns it and continues. A reviewer does not
  use this general role fallback: spec-orchestrate automatically applies
  `native-independent` and continues with a fresh host-native reviewer. If that
  reviewer is unavailable or writes to the workspace, block.
- **Host runtime unknown:** use the Step 0 manual/auto behavior. No role can be
  resolved until the host is known.

Capability fallback is distinct from the stall-driven role swap in arbitration
(`stall-detection.md`), which is capped by `limits.role_swap_max`.

## Contract Test

Run `bash references/scripts/tests/run_tests.sh` from the spec-orchestrate skill
directory. The tracked fixtures cover all four matrix rows and both single-AI
review directions, prove standalone `block` versus orchestrated
`native-independent`, check all marked matrix copies across the three skills,
and verify state rejects invalid host and review-fallback records.

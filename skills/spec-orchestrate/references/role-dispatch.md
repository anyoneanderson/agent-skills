# Role Dispatch — Resolving Who Runs Each Phase

Every phase names a role key (e.g. `spec_author`, `e2e_runner`). This file is the
single place that turns a role key into a concrete execution: a Claude subagent
or a delegated Codex run via agent-delegate. Phase guides reference this file
rather than repeating the resolution.

日本語版: [role-dispatch.ja.md](role-dispatch.ja.md)

## Step 1: Read the Roles

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

A role value is always `claude` or `codex`. Anything else is a config error —
stop and report it.

## Step 2: Resolve the Backend

| Role value | Backend | How to invoke |
|------------|---------|---------------|
| `claude` | Claude subagent | Dispatch a subagent in the current runtime. For planner and evaluator, use the `workflow-planner` / `workflow-evaluator` agent definitions installed by spec-workflow-init |
| `codex` | agent-delegate | Call the agent-delegate script per its public contract, always passing `--target codex` explicitly |

The subagent path names no specific dispatch tool; use whatever the runtime
provides to run a subagent. Do not hardcode a tool name.

**agent-delegate is a contract dependency.** Call the script per
`agent-delegate/references/contract.md` (arguments + `report.json` schema) and
never depend on its internals. Programmatic callers must pass `--target`; the
contract forbids relying on environment self-detection in a nested chain.

## Step 3: Choose Sync vs Detached Execution

The right execution form depends on how long the phase runs:

| Phase kind | Form | Why |
|------------|------|-----|
| spec_review, artifact review | synchronous | Short read-only reviews; the caller waits |
| implement (code), evaluate (E2E) | `--detach` + poll `report.json` | Routinely exceed the ~10-minute synchronous ceiling |

Polling pattern for detached runs (per the contract):
```bash
report="$(agent-delegate.sh --mode <delegate|review> --target codex ... --detach | tail -1)"
until [ -f "$report" ]; do sleep 15; done
status="$(jq -r .status "$report")"   # done | blocked
```

## Phase-Specific Resolution

### spec_review (adversarial spec review)

`spec_reviewer` → agent-delegate `--mode review` (read-only, synchronous).
Round 1 creates the session; rounds ≥ 2 resume it with `--resume <thread_id>`
from `threads.spec_reviewer` in state (a review session is created read-only, the
only sandbox a resume can keep).

### evaluate (acceptance test)

`e2e_runner` → spec-evaluate's backend of the same name, passed **explicitly**
as `--backend` when dispatching spec-evaluate (its standalone default is `self`;
relying on it inside the pipeline would mix the two defaults). `claude` runs the
evaluator as a subagent (`workflow-evaluator`); `codex` runs agent-delegate
`--mode delegate --sandbox workspace-write` (not review — the run launches the
app and drives a browser). See spec-evaluate `references/execution-backend.md`.

### implement (build the feature)

Do **not** route implementation tasks one-by-one from here. Pass the `impl_*`
roles to spec-implement as its `--roles` argument, and let spec-implement do the
per-task `kind → owner` routing internally (no double management).

- Build the map from `roles`: `ui=<impl_ui>,backend=<impl_backend>,test=<impl_test>`,
  or pass the `pipeline.yml` path (spec-implement reads `roles.impl_{kind}` from it).
- A task whose `kind` is unknown or unmapped falls back to spec-code (claude) —
  spec-implement's documented legacy behavior.

## Reviewer Inversion (single definition)

The reviewer of an implementation artifact is always the **opposite side** of its
implementer — "the author does not review their own work". This rule is defined
here once; spec-implement applies it per task from the `--roles` map, so it is
not re-implemented by the orchestrator.

| Task implementer (from `kind`) | Reviewer | Mechanism |
|--------------------------------|----------|-----------|
| `codex` | `claude` | spec-review (unchanged) |
| `claude` | `codex` | agent-delegate `--mode review` (synchronous) |

Fixes route back to the implementer's executor: `spec-code --feedback` for
claude, agent-delegate `--mode delegate` (resume) for codex. The agent-delegate
review file is spec-review-compatible, so the existing fix loop consumes it
unchanged.

## Unavailable Peer (codex missing)

If a `codex` role cannot run because agent-delegate is unavailable (script
missing, exit 2, `tool_unavailable`):

- **manual:** ask the human to confirm reassigning that role to `claude`.
- **auto:** reassign to `claude`, continue, and record the swap in
  `state.role_overrides` and the PR body.

This is a capability fallback, distinct from the stall-driven role swap in
arbitration (`stall-detection.md`), which is capped by `limits.role_swap_max`.

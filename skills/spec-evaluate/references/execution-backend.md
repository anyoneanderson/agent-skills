# Execution Backend — One Instruction Sheet, Switchable Vehicle

spec-evaluate keeps a single evaluator instruction sheet
(`evaluator-prompt.md`) and swaps only the vehicle that runs it. It first selects
an evaluator AI role, then compares that role with the explicit host runtime to
choose native or cross-AI execution.

## Resolution Order

1. `--backend {self|claude|codex}` flag, if given.
2. `roles.e2e_runner` from `pipeline.yml`.
3. `self` (default for standalone runs).

`--backend` is the legacy public option name. Its `claude|codex` value selects
an AI role, not the vehicle. Any such role selection also requires
`--host-runtime {claude|codex}`. The orchestrator passes the value recorded in
pipeline state; a standalone caller supplies it explicitly or is asked for the
current host. Never guess. The `self` value does not require a host.

Standalone use outside the pipeline resolves to `self`: the invoking agent is
the evaluator, and no delegation machinery is involved. This is the mode a human
uses when they say "acceptance-test this feature".

## Role-to-Backend Matrix

<!-- dispatch-matrix:start -->
| Host runtime | Evaluator AI role | Backend | agent-delegate target |
|---|---|---|---|
| `codex` | `codex` | `runtime-native` | `-` |
| `codex` | `claude` | `agent-delegate` | `claude` |
| `claude` | `claude` | `runtime-native` | `-` |
| `claude` | `codex` | `agent-delegate` | `codex` |
<!-- dispatch-matrix:end -->

The matrix is applied only after `e2e_runner` is final. Matching host and role
must not start agent-delegate.

## Execution Vehicles

### `self`

The current agent executes `evaluator-prompt.md` directly with the runtime
context. Nothing is spawned. Use this for manual, single-agent runs.

### Runtime-native (`evaluator_role == host_runtime`)

Dispatch a subagent whose instructions are `evaluator-prompt.md` plus the
runtime context block. The subagent needs to launch the app, drive a browser,
run commands, and write evidence files, so it must have Read, Bash, and browser
automation available. Use the current runtime's `workflow-evaluator` definition
when installed. It returns the result file path. Do not start agent-delegate.

### Cross-AI (`evaluator_role != host_runtime`)

Run the evaluator through agent-delegate. Because acceptance testing launches
the app and operates a browser, it needs write access:

- **Mode `delegate`, sandbox `workspace-write`.** Not `review` — review mode is
  read-only and cannot launch or drive the app.
- Pass `--target "$evaluator_role"` explicitly. Per the agent-delegate contract,
  programmatic callers must not rely on environment self-detection.
- Use explicit `--detach`, retain the expected run id and launch time, and poll
  every 15 seconds (never less often than every 30 seconds). Re-evaluate at
  30-minute intervals and apply the public contract's controlled stop at 2 hours.
- Before launch, register the exact result path, a caller-generated correlation
  value required in that result, its freshness baseline, and the existing Step 5
  machine validator. These values are the artifact recovery contract.

```bash
# Compose: evaluator-prompt.md + runtime context → one prompt file
launch="$(agent-delegate.sh --mode delegate --target "$evaluator_role" \
  --sandbox workspace-write \
  --prompt-file "$prompt" \
  --out-dir ".specs/$feature/evidence/$round" \
  --detach)"

expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
# Arm a durable 15-second watcher that applies the public contract state machine.
# After it signals a valid terminal report: status="$(jq -r .status "$report")"
```

- Each poll validates the expected-run report first, then owner, pid,
  heartbeat, and worker/monitor process state. Live or degraded states keep
  waiting; report absence alone is not failure.
- At the 2-hour limit, recheck the report and owner before sending `TERM` only
  to the verified expected monitor. Wait up to 90 seconds for its terminal
  report; otherwise stop waiting and escalate diagnostics without `--force`.
- `status == done` → read the result file the evaluator wrote; hand it to
  spec-evaluate Step 5 (machine-verify evidence).
- Expected-run `status == blocked` with `blocker_category == env_error` → run
  fail-closed artifact recovery before declaring evaluation failure. Accept only
  the predeclared result when it is new or changed after launch, carries the
  correlation value, and passes the normal Step 5 machine verification. Keep
  the blocked report as a runtime diagnostic.
- Every other `status == blocked`, or failed artifact recovery → record the
  `blocker` / `blocker_category` and treat it as an evaluation failure, never a
  silent pass.

## Contract Boundary

spec-evaluate depends only on the agent-delegate **public contract** — the
argument list and the `report.json` schema documented in agent-delegate's
`references/contract.md`. It does not depend on the script's internal
implementation. If the contract changes, this file changes; script-internal
changes do not affect spec-evaluate.

## Pipeline vs Standalone

- **Pipeline (spec-orchestrate):** the orchestrator supplies the AI role from
  `roles.e2e_runner` and its recorded `host_runtime`. spec-evaluate applies the
  shared matrix. The orchestrator owns escalation when cases come back BLOCKED.
- **Standalone:** the executor is the runner itself; there is no orchestrator, so
  spec-evaluate reports blocked cases directly to the caller.

## Capability Fallbacks

- **Unknown host:** pipeline manual mode asks the human to identify it; auto mode
  blocks with state preserved. Standalone asks when `claude` or `codex` was
  selected; `self` does not need a host value.
- **Native subagent unavailable:** report to the orchestrator. Manual mode asks
  before reassigning the evaluator AI role; auto reassigns only when the peer CLI
  is available, otherwise blocks. Standalone may ask to use `self`.
- **Cross-AI peer unavailable:** report to the orchestrator. Manual asks whether
  to reassign to the host AI; auto reassigns and records the override. Standalone
  asks before using `self`.

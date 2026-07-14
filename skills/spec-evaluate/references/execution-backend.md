# Execution Backend — One Instruction Sheet, Switchable Vehicle

spec-evaluate keeps a single evaluator instruction sheet
(`evaluator-prompt.md`) and swaps only the vehicle that runs it. This keeps the
"what to test and how to prove it" logic in one place while letting the same
acceptance test run on a Claude subagent or a delegated peer LLM.

## Resolution Order

1. `--backend {self|claude|codex}` flag, if given.
2. `roles.e2e_runner` from `pipeline.yml`.
3. `self` (default for standalone runs).

Standalone use outside the pipeline resolves to `self`: the invoking agent is
the evaluator, and no delegation machinery is involved. This is the mode a human
uses when they say "acceptance-test this feature".

## Backends

### `self`

The current agent executes `evaluator-prompt.md` directly with the runtime
context. Nothing is spawned. Use this for manual, single-agent runs.

### `claude`

Dispatch a subagent whose instructions are `evaluator-prompt.md` plus the
runtime context block. The subagent needs to launch the app, drive a browser,
run commands, and write evidence files, so it must have Read, Bash, and browser
automation available. It returns the result file path.

### `codex` (delegated peer)

Run the evaluator through agent-delegate. Because acceptance testing launches
the app and operates a browser, it needs write access:

- **Mode `delegate`, sandbox `workspace-write`.** Not `review` — review mode is
  read-only and cannot launch or drive the app.
- Pass `--target codex` explicitly. Per the agent-delegate contract, programmatic
  callers must not rely on environment self-detection.
- Use explicit `--detach`, retain the expected run id and launch time, and poll
  every 15 seconds (never less often than every 30 seconds). A caller-owned
  timeout is at least 30 minutes.

```bash
# Compose: evaluator-prompt.md + runtime context → one prompt file
launch="$(agent-delegate.sh --mode delegate --target codex \
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
- `status == done` → read the result file the evaluator wrote; hand it to
  spec-evaluate Step 5 (machine-verify evidence).
- `status == blocked` → the run did not complete cleanly. Record the
  `blocker` / `blocker_category` and treat it as an evaluation failure, never a
  silent pass.

## Contract Boundary

spec-evaluate depends only on the agent-delegate **public contract** — the
argument list and the `report.json` schema documented in agent-delegate's
`references/contract.md`. It does not depend on the script's internal
implementation. If the contract changes, this file changes; script-internal
changes do not affect spec-evaluate.

## Pipeline vs Standalone

- **Pipeline (spec-orchestrate):** the orchestrator's role-dispatch supplies the
  resolved backend from `roles.e2e_runner`, and the orchestrator owns escalation
  when cases come back BLOCKED (manual asks the human, auto routes to
  arbitration).
- **Standalone:** the executor is the runner itself; there is no orchestrator, so
  spec-evaluate reports blocked cases directly to the caller.

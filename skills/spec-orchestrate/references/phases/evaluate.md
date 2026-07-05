# Phase: evaluate

Run the acceptance test plan (test.md) against the built feature with
spec-evaluate, and loop with implement until every case passes. Failing cases
come back as spec-review-compatible findings that feed `spec-code --feedback`.

## Input

- `test.md`, the `app:` launch recipe from `pipeline.yml`, and the round number.
- `e2e_runner` role → spec-evaluate backend (self / claude subagent / codex via
  agent-delegate `--mode delegate`, workspace-write), resolved by
  `../role-dispatch.md` → "evaluate".

## Action

1. Dispatch spec-evaluate with `--spec .specs/{feature}/` and the round. It
   launches the app, runs each case by its verification method, saves evidence
   under `evidence/{round}/`, and writes `evaluate-{round}.md`.
2. Long E2E runs may exceed the synchronous ceiling; the codex backend detaches
   and the orchestrator polls for the result file.

## Output

- `evaluate-{round}.md` (requirement-ID pass/fail table + spec-review-compatible
  findings) and the evidence files under `.specs/{feature}/evidence/{round}/`.

## Verification

- **Evidence check (do not skip):** for every case reported PASS, confirm its
  evidence pointer resolves to an existing, non-empty file. A PASS with a missing
  evidence file is forced to FAIL regardless of the evaluator's claim (NFR-003).
  spec-evaluate performs this; the orchestrator confirms it was applied.
- Blocked cases (e.g. no app recipe for a playwright case) are distinct from
  failures and are not silently upgraded to pass.

## State Update

- Append this round to `rounds.evaluate`: pass/fail/blocked counts, finding
  fingerprints, gate result.
- Evaluate the stall signals (detector in T010). If a signal fires, set `phase`
  to arbitration.

## Transitions

- failing findings → **implement** (fix via spec-code --feedback, then re-evaluate)
- all cases pass (Gate PASS) → **pr**
- stall signal fires → **arbitration** (handled per T010)

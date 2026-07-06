# Phase: evaluate

Run the acceptance test plan (test.md) against the built feature with
spec-evaluate, and loop with implement until every case passes. Failing cases
come back as spec-review-compatible findings that feed `spec-code --feedback`.

## Input

- `test.md`, the `app:` launch recipe from `pipeline.yml`, and the round number.
- `e2e_runner` role → spec-evaluate backend (self / claude subagent / codex via
  agent-delegate `--mode delegate`, workspace-write), resolved by
  `../role-dispatch.md` → "evaluate". Pass the resolved value **explicitly** as
  `--backend` when dispatching spec-evaluate: its own standalone default is
  `self`, which must not leak into pipeline runs.

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
  evidence file is forced to FAIL regardless of the evaluator's claim.
  spec-evaluate performs this; the orchestrator confirms it was applied.
- Blocked cases (e.g. no app recipe for a playwright case) are distinct from
  failures and are not silently upgraded to pass.

## State Update

- Append this round to `rounds.evaluate` using the **same field shape as
  spec_review** so the same detector applies: map each FAIL case to a `critical`
  count and each concern to an `improvement` count (blocked cases are neither —
  they are not failures; record their number in a separate `blocked` field so a
  resumed run can see what is still unverified), plus the finding fingerprints (per
  `../stall-detection.md`, over the Critical + Improvement findings only) and the
  gate result. Recording raw pass/fail/blocked tallies instead would leave S2
  (which sums `critical + improvement`) unable to evaluate this loop.
- Evaluate the stall signals S1–S3 (`../stall-detection.md`). If a signal fires,
  set `phase` to arbitration.

## Transitions

- failing findings → **implement**. Each FAIL is a Critical finding and each
  concern an Improvement; they are handed to `spec-code --feedback` (the
  `type: evaluate` result is spec-review-compatible, so the fix loop consumes it
  unchanged). Then re-evaluate at `round + 1`.
- all cases pass (Gate PASS) → **pr**
- blocked cases present, no FAIL (Gate FAIL on blocked alone — blocked counts
  toward neither `critical` nor `improvement`, so there is nothing for the fix
  loop to consume) → mode-dependent, per `../pipeline-config.md` "app":
  - manual: ask the human — add the missing app recipe (then re-evaluate at
    `round + 1`) or explicitly accept the skip.
  - auto: set `phase` to **arbitration** (draft-PR landing with the blocked
    cases listed under `## Unresolved` is an accepted outcome). Never let an
    unattended run promote unverified requirements to a ready PR.
- stall signal fires → **arbitration** (`../stall-detection.md`)

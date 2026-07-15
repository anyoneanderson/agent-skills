# Phase: evaluate

Run the acceptance test plan (test.md) against the built feature with
spec-evaluate, and loop with implement until every case passes. Failing cases
come back as spec-review-compatible findings that feed `spec-code --feedback`.

## Input

- `test.md`, the `app:` launch recipe from `pipeline.yml`, and the round number.
- `e2e_runner` AI role plus the recorded `host_runtime`, resolved by
  `../role-dispatch.md` → "evaluate". Pass the role **explicitly** as
  `--backend` and the host as `--host-runtime` when dispatching spec-evaluate.
  Its standalone default is `self`, which must not leak into pipeline runs.

## Action

1. Dispatch spec-evaluate with `--spec .specs/{feature}/` and the round. It
   launches the app, runs each case by its verification method, saves evidence
   under `evidence/{round}/`, and writes `evaluate-{round}.md`.
2. When the evaluator role differs from the host, the agent-delegate backend
   passes the role as an explicit target plus `--detach`, retains the expected
   run id, and applies the 15–30-second report-first wait from
   `../role-dispatch.md`. Its caller-owned timeout is at least 30 minutes.
   Report absence while the heartbeat or process state is live is a waiting
   condition, not failure.

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
  spec_review** so the same detector applies: count each FAIL case as a `critical`
  and each concern as an `improvement` (blocked cases are neither —
  they are not failures; record their number in a separate `blocked` field so a
  resumed run can see what is still unverified), plus `fix_required` (for this
  loop, `critical + improvement` — every failing case drives the fix loop), the
  finding fingerprints and class keys (per `../stall-detection.md`), and the
  gate result. Recording raw pass/fail/blocked tallies instead would leave S2
  (which watches `fix_required`) unable to evaluate this loop.
- Evaluate the stall signals S1–S4 (`../stall-detection.md`). If a signal fires,
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

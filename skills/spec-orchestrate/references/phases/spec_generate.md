# Phase: spec_generate

Produce (or repair) the spec three-set plus the acceptance test plan by running
spec-generator as the planner. This phase runs on first entry and again whenever
inspect or spec_review or approval sends findings back for revision.

## Input

- First entry: the intake output (manual request, or the reshaped Issue for auto).
- Re-entry (fix): the findings that sent us back — inspect findings, spec_review
  `fix_before: implementation` findings (or a restructure directive from
  arbitration), or manual approval feedback — plus a short summary of what
  changed in prior rounds.
- `spec_author` role → backend resolution (`../role-dispatch.md`).

## Action

1. Dispatch spec-generator as the planner (`spec_author` backend).
   - auto: use spec-generator's auto mode (`--auto --issue <N>`), which never
     calls AskUserQuestion and records ambiguities as ASM notes.
   - Re-entry: pass the findings as the revision instruction, not a fresh start.
2. The planner writes `requirement.md`, `design.md`, `tasks.md`, and `test.md`
   into `.specs/{feature}/`. The orchestrator does not write these files.

**Concurrency/ordering norm (always include in the planner instruction):**
specify concurrent or order-dependent behavior by **defining a short set of
invariants to uphold** (e.g. "once a new review starts, no earlier success
verdict is used as a merge condition") and have the implementation and tests
enforce them. **Do not enumerate all execution orders in the spec.** When a
review finds an ordering hole, revise the invariants instead of adding one
more state or decision table. Every enumerated order grows the spec, and a
grown spec breeds new inconsistencies — this norm exists to stop that chain.

## Output

- The spec three-set (`requirement.md`, `design.md`, `tasks.md`) plus `test.md`
  in `.specs/{feature}/`, written by the planner.

## Verification

- All four files exist and are non-empty.
- `test.md` carries `type: test-plan` and each case has a verification method.
- `tasks.md` tasks carry a `kind:` label (ui / backend / test).
- If any are missing, this is a worker failure: re-run once, then treat as blocked.

## State Update

- Set `phase` to `inspect`.
- Append `spec_generate` to `completed_phases` (idempotent across re-entries).
- On a re-entry driven by findings, record the round outcome that triggered the
  revision (so stall detection in later phases can read the history).

## Transitions

- spec set + test.md written and verified → **inspect**

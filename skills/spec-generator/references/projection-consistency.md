# Projection Consistency Pass

Run this pass after initial generation and every revision, before reporting that
the specification is complete. This file is the source of truth for projection
updates; callers such as workflow planners must invoke it rather than copy its
checklist.

## Changed Fact Set

Before editing, list the facts being introduced, removed, or changed:

- Requirement IDs, design decisions, numeric thresholds, and named methods
- Terms whose meaning is fixed by the requirement or design body
- Relationships between a requirement, its implementation task, and its
  acceptance test

Search the complete specification set for both the old and new form of each
fact. A search hit is a candidate projection, not proof that two occurrences
have the same meaning.

## Projection Inventory

For every changed fact, inspect these targets when they exist:

| ID | Projection target |
|----|-------------------|
| PG-001 | §0, §12, and headings that summarize the current body; §12 means a trailing summary or conclusion section when present |
| PG-002 | The §1 traceability matrix and other Requirement ID indexes |
| PG-003 | The requirement and design body that define the decision |
| PG-004 | `tasks.md` entries that implement the affected requirement or design |
| PG-005 | `test.md` cases that verify the affected requirement |

Update the source and every affected projection in the same edit. Do not leave
a known stale target for a later cleanup pass.

## Verification

1. Re-extract defined and referenced Requirement IDs from `requirement.md`,
   `design.md`, `tasks.md`, and `test.md`. Reject undefined references and
   requirements whose expected downstream projection disappeared.
2. Compare structured values such as IDs, numeric thresholds, and named methods
   exactly across projections that represent the same fact.
3. Compare prose summaries with the body by meaning. Do not use exact-string
   equality as a substitute for semantic comparison.
4. Search for superseded IDs, values, and names. Classify each remaining hit as
   an intentional history/example or a stale projection.
5. Confirm that each changed requirement or design decision has corresponding
   implementation and acceptance coverage, or an explicit reason why a target
   does not apply.

Do not report completion while any affected summary, traceability row, task, or
test still describes the superseded fact.

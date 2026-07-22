# Projection Consistency Check

Run this check after loading the complete specification set. Use the
[spec-generator projection pass](../../spec-generator/references/projection-consistency.md)
as the generation contract; keep inspection details here rather than
duplicating them in a workflow planner.

## Checks

| ID | Inspection |
|----|------------|
| PI-001 | Compare Requirement IDs defined in `requirement.md` with every reference in `design.md`, `tasks.md`, and `test.md` |
| PI-002 | Compare §0, §12, and headings with the current body decisions they summarize; §12 means a trailing summary or conclusion section when present |
| PI-003 | Compare the §1 traceability matrix with current Requirement IDs and design coverage |
| PI-004 | Compare numeric thresholds and named methods across occurrences that represent the same decision |
| PI-005 | Confirm changed requirements and design decisions are projected into `tasks.md` and `test.md`, or have an explicit not-applicable reason |

Use exact comparison for structured IDs and values. Use semantic comparison for
prose summaries; exact-string equality alone cannot prove that two summaries
make the same claim. Do not compare identical numbers or names when their local
context shows that they represent different facts.

## Findings

- Keep undefined Requirement ID references under Check 1 as `CRITICAL`.
- Report a stale summary, traceability row, numeric value, named method, task, or
  test projection as `WARNING` so an orchestrated inspect gate returns to
  specification generation.
- Include the changed source fact, the stale target with file and line, and the
  current value or relationship the target should express.
- When a remaining old value is intentional history or an example, do not emit
  a finding if the document labels that role clearly.

Finish this check only after inspecting every projection target affected by the
changed fact. Finding one stale target does not make the remaining targets
unnecessary to inspect.

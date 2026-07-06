# Phase: implement

Build the feature by running spec-implement over tasks.md. spec-implement owns
its internal spec-code / spec-review / spec-test loop and the per-task kind
routing; the orchestrator hands it the task list and the role map, then verifies
the outcome.

## Input

- `tasks.md` (with `kind:` labels) and the rest of the spec set.
- The role map for implementation (`impl_ui` / `impl_backend` / `impl_test`),
  passed to spec-implement as its `--roles` argument so it routes each task to
  spec-code (claude) or agent-delegate (codex) by kind. Map construction and the
  reviewer-inversion rule are in `../role-dispatch.md` → "implement".
- On re-entry from evaluate: the failing acceptance findings to feed back.

## Action

1. First entry: dispatch spec-implement with the spec path, issue, and role map.
   spec-implement creates the feature branch, runs the task loop, and applies the
   reviewer-inversion rule (the author does not review their own work) internally.
2. Re-entry (evaluate returned failures): pass the acceptance findings to
   `spec-code --feedback` through spec-implement so the same fix loop applies to
   test failures, then re-run the affected tasks.

**Staging guard:** stage implementation files by explicit pathspec — plus the
four spec files (`requirement.md` / `design.md` / `tasks.md` / `test.md`) only
when the project's policy is to commit spec artifacts. Never stage run records
(`evidence/`, `review-*.md`, `inspection-report.md`, `.inspection_result.json`,
`evaluate-*.md`, `pipeline-state.json`, `retrospective.md`,
`pipeline-metrics.jsonl`). The pathspec exclusion at staging is the first guard;
the `.specs/.gitignore` written at intake is the backstop.

## Output

- Implemented changes on the feature branch, with the corresponding `tasks.md`
  checkboxes marked complete and per-task reviews recorded by spec-implement.

## Verification

- Tasks in tasks.md are marked complete and the git diff reflects real changes
  (measured, not self-reported).
- spec-implement returned without an unresolved blocker. If a `codex`-owned task
  reports agent-delegate unavailable, apply the reassignment rule from
  §Error Handling (auto reassigns and records; manual confirms).

## State Update

- Set `phase` to `evaluate`.
- Append `implement` to `completed_phases`.
- Record any role overrides applied during implementation under
  `role_overrides`.

## Transitions

- tasks complete → **evaluate**
- (re-entry from evaluate is a return into this phase, not a new transition out)

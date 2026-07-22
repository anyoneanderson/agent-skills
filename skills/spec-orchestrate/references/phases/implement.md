# Phase: implement

Build the feature by running spec-implement over tasks.md. spec-implement owns
its internal spec-code / spec-review / spec-test loop and the per-task kind
routing; the orchestrator hands it the task list and the role map, then verifies
the outcome.

## Input

- `tasks.md` (with `kind:` labels) and the rest of the spec set.
- The role map for implementation (`impl_ui` / `impl_backend` / `impl_test`),
  passed to spec-implement as its `--roles` argument together with
  `--host-runtime <host_runtime>` and
  `--review-fallback native-independent`. spec-implement selects the AI role by
  kind, then resolves native versus cross-AI execution. Map construction and the
  reviewer independence rule are in `../role-dispatch.md` → "implement".
- On re-entry from evaluate: the failing acceptance findings to feed back.

## Action

1. First entry: dispatch spec-implement with the spec path, issue, role map,
   recorded host, and `--review-fallback native-independent`. spec-implement
   creates the feature branch, runs the task loop, and prefers the opposite AI
   reviewer while enforcing an independent reviewer instance internally.
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
- spec-implement's completion summary, including a structured
  `review_fallbacks` list (empty when unused). spec-implement reports these
  records but never reads or writes pipeline state.

## Verification

- Tasks in tasks.md are marked complete and the git diff reflects real changes
  (measured, not self-reported).
- spec-implement returned without an unresolved blocker. If a cross-AI reviewer
  was unavailable, verify the fallback used a fresh read-only native reviewer,
  left the workspace unchanged, and was recorded. If that reviewer could not be
  created, the phase must remain blocked.

## State Update

- Set `phase` to `evaluate`.
- Append `implement` to `completed_phases`.
- Replace `implement.tasks_done` with the complete ids of checked canonical
  tasks, preserving `T[0-9]+[a-z]?(-[A-Za-z0-9]+)?` ids exactly. Never include
  an id that is absent or unchecked in `tasks.md`.
- Record any role overrides applied during implementation under
  `role_overrides`.
- Validate the `review_fallbacks` list returned by spec-implement, then append
  every entry under `review_fallbacks`; the orchestrator is the sole state
  writer.

## Transitions

- tasks complete → **evaluate**
- (re-entry from evaluate is a return into this phase, not a new transition out)

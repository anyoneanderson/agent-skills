# Evaluator Tooling: Playwright CLI

## Purpose

Author an Evaluator-owned Playwright spec under `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/`
and run it as an independent regression asset. This is the preferred option
when browser verification is needed but MCP is unavailable or a persistent
spec should be carried into later sprints.

## When to choose

- The project needs browser-level contract verification.
- MCP is unavailable or less convenient than a committed spec.
- You want to preserve regression coverage across future sprints.

## Phase 3 procedure

1. Create `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/<AS>.spec.ts`.
2. Encode the acceptance scenario directly in that spec.
3. Run `pnpm exec playwright test ${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/`.
4. If the scenario fails, keep the spec and attach the failure output as
   evidence so the next sprint can replay it.

## Required spec shape

- Use the real app entrypoint and the real contract boundary.
- Name the scenario after the acceptance scenario id.
- Keep the spec commit-worthy; it becomes a regression asset for later sprints.

## Prohibited shortcuts

- Do not use `page.route`.
- Do not use `addInitScript`.
- Do not override `window.fetch`.
- Do not convert the test into a full stub of the target contract boundary.

## Output expectation

Commit the spec under `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/`
and list sprint-dir-relative paths such as `evidence/iter-<n>/...` in
`feedback/evaluator-<iter>.md`.

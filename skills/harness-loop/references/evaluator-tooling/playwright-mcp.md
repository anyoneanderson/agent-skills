# Evaluator Tooling: Playwright MCP

## Purpose

Use `mcp__playwright__browser_*` tools to reproduce acceptance scenarios by
operating the dev server like a real user. This is the preferred tool when
live browser verification matters more than reusable spec files.

## When to choose

- The project has a user-facing UI.
- Playwright MCP is installed and allow-listed.
- You need a11y snapshots and live interaction evidence.

## Phase 3 procedure

1. Open the target URL with `browser_navigate`.
2. Capture an a11y tree with `browser_snapshot` before interaction.
3. Perform the scenario with `browser_type`, `browser_click`,
   `browser_select_option`, `browser_press_key`, and `browser_wait_for`.
4. If the scenario fails, collect `browser_network_requests`,
   `browser_console_messages`, and a second `browser_snapshot`.
5. Repeat for at least one abnormal or boundary path when the contract
   implies validation, auth, timeout, or empty-state behavior.

## CLI fallback

If `mcp__playwright__*` tools are unavailable or blocked by the current
allow-list, follow `playwright-cli.md`: write an Evaluator-owned spec under
`${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/`, run the project's equivalent of
`pnpm exec playwright test`, and save screenshots/logs under
`${SPRINT_DIR}/evidence/iter-<n>/`. Record sprint-dir-relative paths in
`feedback/evaluator-<iter>-report.json.evidence_refs`.

## Evidence to save

- Accessibility snapshots
- Console logs
- Network request logs
- Screenshots only when the a11y tree is insufficient

## Prohibited shortcuts

- Do not rely on Generator-authored tests as pass evidence.
- Do not replace live behavior with screenshot-only inspection.
- Do not claim pass without touching the contract boundary yourself.

## Output expectation

Record the saved artifact paths in `feedback/evaluator-<iter>.md` `Evidence`.

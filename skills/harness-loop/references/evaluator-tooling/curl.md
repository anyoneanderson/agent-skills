# Evaluator Tooling: curl

## Purpose

Verify API-oriented acceptance scenarios with shell scripts and raw HTTP calls.
This is the preferred option for endpoint-driven projects where browser
automation adds little value.

## When to choose

- The contract boundary is HTTP, SSE, or webhook oriented.
- UI behavior is not the main source of risk.
- The project can be verified from shell-level requests.

## Phase 3 procedure

1. Write `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/<AS>.sh`.
2. Exercise the happy path.
3. Exercise at least one abnormal path covering validation, auth failure,
   timeout handling, or malformed payloads when relevant.
4. Save status, headers, and payload shape evidence to logs next to the script.

## Required script shape

- `#!/usr/bin/env bash`
- `set -euo pipefail`
- Explicit assertions for status code and payload shape
- Separate success and failure cases

## Prohibited shortcuts

- Do not stop at a single happy-path call.
- Do not claim pass from generated fixtures alone.
- Do not skip auth or validation paths when the contract includes them.

## Output expectation

Commit the script under `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/`
and reference sprint-dir-relative paths in `feedback/evaluator-<iter>.md`.

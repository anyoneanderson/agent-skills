# Evaluator Tooling: Custom Script

## Purpose

Use a sprint-specific `.harness/scripts/eval-<feature>.sh` when the built-in
tool references cannot express the project's verification surface.

## When to choose

- The project needs a bespoke harness.
- Browser automation and raw curl scripts are both insufficient.
- The Evaluator can define a deterministic shell entrypoint.

## Phase 3 procedure

1. Write `.harness/scripts/eval-<feature>.sh`.
2. Make it executable.
3. Feed any needed contract metadata through stdin or environment variables.
4. Run it directly and capture stdout/stderr into `${SPRINT_DIR}/evidence/iter-<n>/`.

## Required script contract

- Exit `0` on pass.
- Exit non-zero on fail.
- Print enough evidence for the next Evaluator to reproduce the result.
- Keep the script sprint-local unless it proves generally reusable.

## Prohibited shortcuts

- Do not hide failures behind unconditional `exit 0`.
- Do not use it as a wrapper around Generator-authored tests without adding
  independent assertions.
- Do not omit evidence capture.

## Output expectation

Reference the script path and its captured logs in `feedback/evaluator-<iter>.md`.

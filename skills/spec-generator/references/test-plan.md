# Test Plan Phase — Acceptance Test Plan Generation

## Overview

Generate an acceptance test plan (test.md).
Takes requirement.md, design.md, and tasks.md as input and produces a
black-box checklist that a separate evaluator executes against the finished
implementation.

**Why test.md is separate from tasks.md**: the two files have different
consumers. tasks.md is read by the builder (spec-code) to construct the
feature; test.md is read by the breaker (an acceptance evaluator such as
spec-evaluate) to verify it. Keeping them separate lets the evaluator work
from requirements without inheriting the builder's assumptions.

**Important**: This phase only *generates* the plan. It does not run any tests.

## Execution Steps

### 1. Locate the Spec Set

```bash
find .specs -name "requirement.md" -type f
find .specs -name "design.md" -type f
```

Extract from the spec set:
- Every functional requirement ID (`REQ-XXX`)
- Every non-functional requirement ID (`NFR-XXX`)
- Acceptance-relevant behavior described in design.md

### 2. Coverage Principle

1. Every `REQ` and `NFR` MUST be referenced by at least one test case.
   A requirement with no test case is a coverage gap — add a case.
2. One test case verifies one observable behavior. Split multi-behavior
   requirements into multiple cases (`T-A01`, `T-A02`, ...).
3. Do not invent behavior that is not in the spec set. If a requirement is
   untestable as written, record it as a note rather than fabricating steps.

### 3. Test Case ID System

- Prefix is `T-A` (Acceptance): `T-A01`, `T-A02`, ...
- The `T-A` prefix does not collide with tasks.md `T-` (implementation task)
  IDs, so the two files can be cross-read without ambiguity.

### 4. Verification Method

Each case MUST declare exactly one verification method:

| Method | Meaning | Requirements |
|--------|---------|--------------|
| `playwright` | Drive the UI in a real browser and assert the result | App launch recipe required (start command, URL) |
| `command` | Run a shell command and assert its exit code / output | The exact command and expected exit code |
| `file-check` | Assert an artifact exists and/or contains expected content | The path and the expected content marker |

- `playwright` cases depend on an app launch recipe. When no launch recipe is
  available, still write the case but flag that it needs a recipe to run.
- The verification method field is **mandatory** on every case. A case with no
  verification method is not executable and MUST NOT be emitted.
- Verification commands MUST be runnable in the target environment exactly as
  written. Avoid shell-dialect constructs, PCRE extensions (for example negative
  lookahead in `grep -E`, which is invalid in POSIX ERE), and language-version
  dependent APIs (for example `sys.stdlib_module_names`, added in Python 3.10).
  When such a feature is unavoidable, state the required version or tool as a
  precondition in the case's `Command` field.

### 5. Output Format

```markdown
# Acceptance Test Plan — {feature}
type: test-plan

## T-A01: [REQ-001] User can log in
- Steps: 1. Open {url}/login  2. Enter valid credentials  3. Submit
- Expected: Redirects to the dashboard and the user name is shown
- Verify: playwright        # playwright | command | file-check
- Command: -                # for `command`: the command and expected exit code

## T-A02: [NFR-001] Response returns within 500ms
- Steps: 1. Send GET /api/items 10 times
- Expected: p95 latency < 500ms
- Verify: command
- Command: `hey -n 10 http://localhost:3000/api/items` → exit 0, p95 < 500ms

## T-A03: [REQ-005] Export file is written
- Steps: 1. Trigger export from the settings page
- Expected: A CSV file is created under exports/
- Verify: file-check
- Command: exports/report.csv exists and contains a header row
```

- Keep the field set fixed: `Steps` / `Expected` / `Verify` / `Command`.
- For `playwright` and `file-check` cases the `Command` field holds the
  expected artifact or assertion detail; use `-` only when it adds nothing.

### 6. Output Location

```
.specs/[project-name]/test.md
```

## Integration with the Full Workflow

test.md is generated as the **final step** of the full workflow, after
requirement.md, design.md, and tasks.md exist. It reads all three but does not
modify them — the existing three-document output is unchanged.

## Quality Checklist

Post-generation verification:

1. [ ] `type: test-plan` header is present
2. [ ] Every `REQ` and `NFR` in requirement.md is referenced by ≥1 case
3. [ ] Every case ID uses the `T-A` prefix
4. [ ] Every case has a non-empty `Verify` field (playwright / command / file-check)
5. [ ] `playwright` cases note their app launch dependency
6. [ ] No case invents behavior absent from the spec set
7. [ ] Every verification command runs in the target environment as written — no
   shell-dialect, PCRE, or version-dependent API assumptions, or the assumption
   is stated as a precondition

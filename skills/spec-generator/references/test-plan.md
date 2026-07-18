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

- Use `file-check` for generated artifacts. A raw source or configuration file
  can establish only a literal-text requirement, not effective configuration or
  runtime behavior; see Section 5.
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

- `command` cases MUST be verified executable at generation time: actually run
  the command (or a dry equivalent) and confirm it exercises what the case
  claims. Prefer an existing `package.json` script over ad-hoc invocations.
  Watch argument forwarding in particular — e.g. `pnpm test -- --coverage`
  expands to `vitest run -- --coverage`, which demotes `--coverage` to a
  positional argument: the run exits 0 without producing any coverage report,
  so the case passes while verifying nothing.

### 5. Evidence Basis and Threat Model

Before writing a case's steps and command:

1. Define the claim being tested and its threat model. Acceptance tests verify
   the correctness of an implementation when the declared verification command
   and its test machinery run as written. If this boundary changes how a pass or
   failure is interpreted, state it in the case's `Steps` or `Expected` field.
2. Base semantic claims on evidence produced after the responsible system or
   tool evaluates the input:
   - **Measured output**: a coverage report, response, query result, or other
     output produced by executing the behavior under test.
   - **Evaluated object**: the value obtained after the target runtime or tool
     loads a configuration or module through its supported interface.
3. Do not infer effective configuration or runtime behavior by scanning raw
   source or configuration text with `grep`, regular expressions, or substring
   matching. A lexical check is valid only when the requirement itself concerns
   literal text, such as a required header in a generated file.
4. Treat deliberate verifier bypasses, such as disabling tests, adding
   `skip` / `todo`, excluding the subject from measurement, or rewriting the
   verification command, as code-review-gate concerns. Do not add successive
   text guards to an acceptance command to detect them. If the specification
   explicitly requires tamper resistance or detection of those attacks, test
   that security behavior as its own acceptance claim instead.

### 6. Output Format

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

### 7. Output Location

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
8. [ ] Every `command` case was executed (or dry-run) at generation time and
   observed to exercise its claim — argument forwarding included
9. [ ] Every semantic claim uses measured output or an evaluated object rather
   than raw source/configuration text; lexical checks on source or configuration
   text are limited to literal-text requirements
10. [ ] Cases whose threat-model boundary affects pass/fail interpretation state
    that boundary in `Steps` or `Expected`; deliberate verifier bypasses are
    assigned to the code review gate unless the specification explicitly
    requires their detection

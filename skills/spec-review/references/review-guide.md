# spec-review Reference Guide

## Matrix Review Detail

The core review process is a systematic rule × file cross-check:

```
Rules:  [RR-001, RR-002, CR-MUST-001, CR-MUST-002, ...]
Files:  [src/auth/service.ts, src/api/routes.ts, ...]
Matrix: rules.length × files.length cells to check
```

### Category Matching

Not every rule applies to every file. Use category matching to skip irrelevant checks:

| Rule Category | Applies To |
|---|---|
| security | All source files |
| typescript | `.ts`, `.tsx` files |
| testing | `*.test.*`, `*.spec.*` files |
| style | All source files |
| api | Controller, route, handler files |
| database | ORM models, migration, query files |
| naming | All source files |

### Severity Classification

| Severity | Examples | Reading |
|---|---|---|
| Critical | SQL injection, secrets in code, null pointer, data loss | Highest human priority |
| Improvement | Missing error handling, suboptimal algorithm, poor naming | Worth fixing |
| Minor | Style inconsistency, extra whitespace, comment quality | Log only |

Severity is for human reading and prioritization. Whether the Gate stops is
decided by the `fix_before` tag alone (definition, default `follow_up`, and
escalation burden of proof: SKILL.md Step 4.5). A Critical finding whose fix
belongs to a later milestone leaves the Gate green — it is recorded and
carried forward, not silently dropped.

## Review File Format

See SKILL.md Step 5 for the full template. Key points:
- Each finding must include file:line reference
- Each finding must reference the rule ID
- Each Critical / Improvement finding carries a `fix_before` tag
  (`implementation | trial | required_check | follow_up`)
- Checklist format (`- [ ]`) for Critical and Improvement (so spec-code can track fixes)
- Plain text for Minor (informational only)

## Diff Strategies

| Context | Command | Notes |
|---|---|---|
| Task-scoped with explicit base | `git diff {base-commit}...HEAD` | Preferred when orchestrator passes `--base-commit` |
| Task-scoped auto-detect | `git log --oneline` to find task start commit, then `git diff {commit}...HEAD` | Use only when the start commit is unambiguous |
| Staged changes | `git diff --cached` | For pre-commit review |
| Working tree | `git diff` | Unstaged changes |
| PR scope | `git diff {base}...HEAD` | Full PR review |

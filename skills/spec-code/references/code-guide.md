# spec-code Reference Guide

## Feedback File Format

The `--feedback` option accepts both review results and test results. The file format is auto-detected:

### Review Result (from spec-review)
- Contains `## Findings` section with `### Critical` / `### Improvement` / `### Minor`
- Each finding has `**{rule-id}** {file}:{line} — {description}`
- Address Critical findings first, then Improvements

### Test Result (from spec-test)
- Contains `## Test Cases` section with pass/fail status
- Contains `## Completion Criteria Coverage` table
- Focus on fixing failing tests and uncovered criteria

## Commit Conventions

When committing, follow this priority for message format:
1. `coding-rules.md` commit rules (if defined)
2. `CLAUDE.md` commit conventions (if defined)
3. Default: `feat(scope): {task-id} — {brief description}`

## Task Identification

Tasks in `tasks.md` follow this pattern:
```markdown
- [ ] T-007: Task description
  - [ ] Sub-criterion 1
  - [ ] Sub-criterion 2
```

Match on the task ID prefix (e.g., `T-007`, `T001`, `T-7`).

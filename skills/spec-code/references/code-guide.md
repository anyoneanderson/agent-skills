# spec-code Reference Guide

## Feedback File Format

The `--feedback` option accepts both review results and test results. The file format is auto-detected:

### Header Detection
- The first metadata line must declare the feedback type: `type: review`, `type: test`, or `type: evaluate`
- `type: review` means the file follows the spec-review contract
- `type: test` means the file follows the spec-test contract
- `type: evaluate` means the file follows the spec-evaluate contract (acceptance results)
- If the header is missing, fall back to section-based detection only as a best-effort compatibility path

### Review Result (from spec-review)
- Contains `## Findings` section with `### Critical` / `### Improvement` / `### Minor`
- Each finding has `**{rule-id}** {file}:{line} — {description}`; Critical /
  Improvement findings also carry a `fix_before` tag
- When findings carry `fix_before` tags, fix only those tagged
  `implementation` (Critical first, then Improvement); findings tagged
  `trial` / `required_check` / `follow_up` are deferred and carried by the
  caller — do not fix them here
- Legacy file without `fix_before` tags: address Critical findings first,
  then Improvements

### Test Result (from spec-test)
- Contains `## Test Cases` section with pass/fail status
- Contains `## Completion Criteria Coverage` table
- Focus on fixing failing tests and uncovered criteria

### Evaluate Result (from spec-evaluate)
- Uses the same `## Findings` structure as a review result (`### Critical` / `### Improvement` / `### Minor`) — address Critical findings first, then Improvements. Evaluate findings carry no `fix_before` tag: every finding is a fix target (a failing acceptance case cannot be deferred)
- Ignore the `## Blocked` section: blocked cases are setup gaps (e.g., a missing app launch recipe), not implementation failures, and are not fix targets

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

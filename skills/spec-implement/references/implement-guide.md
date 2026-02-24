# spec-implement Guide

## Overview

spec-implement automates the implementation-to-PR workflow by reading project-specific configuration files and executing tasks from structured specifications.

It acts as an execution engine that:
- Reads `docs/issue-to-pr-workflow.md` as the development playbook
- Enforces `docs/coding-rules.md` as quality gates
- Tracks progress via `.specs/{feature}/tasks.md` checkboxes
- Creates a PR upon successful completion

## Full Execution Flow

```
1. Initial Checks
   ├── Verify working directory (git repo, gh CLI available)
   ├── Parse options (--resume, --issue, --spec, --dry-run)
   └── Locate spec directory (.specs/{feature}/)

2. File Loading
   ├── docs/issue-to-pr-workflow.md (playbook)
   ├── docs/coding-rules.md (quality rules)
   ├── .specs/{feature}/requirement.md
   ├── .specs/{feature}/design.md
   └── .specs/{feature}/tasks.md

3. Issue Analysis
   ├── gh issue view {number} for context
   └── Extract requirements, labels, assignees

4. Branch Creation
   └── Follow workflow's naming convention (default: feature/issue-{N}-{desc})

5. Task Loop
   ├── Read next unchecked task from tasks.md
   ├── Reference design.md for implementation details
   ├── Implement the task
   ├── Run quality checks (coding-rules.md)
   ├── Update tasks.md checkbox (- [ ] → - [x])
   └── Commit progress

6. Final Quality Gate
   ├── Run all tests (from workflow)
   ├── Run lint/typecheck (from workflow)
   └── Verify all [MUST] rules pass

7. PR Creation
   ├── Follow workflow's PR template
   ├── Link to issue (Closes #{N})
   └── Monitor CI (if specified in workflow)
```

## Workflow File Loading

### How `docs/issue-to-pr-workflow.md` Is Used

The workflow file is a project-specific playbook that spec-implement reads and follows section by section. It typically contains:

| Section | What spec-implement extracts |
|---------|------------------------------|
| Development Environment | Environment setup commands, container start commands |
| Issue Analysis and Setup | Branch naming conventions, issue reading instructions |
| Phased Implementation | Implementation order, coding guidelines |
| Testing | Test commands, coverage thresholds |
| PR Creation and Quality Gates | Pre-PR checks, PR body template |
| CI/CD Monitoring | CI verification commands |

**Key principle**: spec-implement does NOT hardcode any project-specific commands. All commands come from the workflow file.

### When Workflow File Is Missing

If `docs/issue-to-pr-workflow.md` does not exist:
1. A warning is displayed
2. The user is asked whether to run spec-workflow-init to generate it
3. If declined, a minimal built-in flow is used:
   - Issue analysis → branch creation → implement tasks → run tests → create PR

## Coding Rules Loading

### How `docs/coding-rules.md` Is Used

The rules file defines project-specific quality standards with three severity levels:

| Severity | On Violation | Example |
|----------|-------------|---------|
| `[MUST]` | Error — fix required before continuing | "All functions must have return types" |
| `[SHOULD]` | Warning — noted but continues | "Prefer const over let" |
| `[MAY]` | Info — logged only | "Consider adding JSDoc comments" |

Rules are checked at four points:
1. **Before task**: Review relevant rules for the task category
2. **During generation**: Self-check generated code against `[MUST]` rules
3. **After task**: Verify completion criteria + rule compliance
4. **Final gate**: All `[MUST]` rules checked across all changes

### When Rules File Is Missing

If `docs/coding-rules.md` does not exist:
1. A warning is displayed
2. The user is asked whether to run spec-rules-init to generate it
3. If declined, implementation proceeds without rule enforcement
4. CLAUDE.md or AGENTS.md are used as fallback references if available

## tasks.md State Management

### Checkbox Format

tasks.md uses standard Markdown checkboxes for state tracking:

```markdown
### Phase 1: Setup
- [ ] T001: Create project structure     ← unchecked = pending
- [x] T002: Initialize database          ← checked = completed

### Phase 2: Implementation
- [ ] T003: Implement user model
  - Completion criteria:
    - [x] Model class created            ← sub-items also tracked
    - [ ] Validation rules added
    - [ ] Unit tests written
```

### How Checkboxes Are Updated

1. When starting a task: the top-level checkbox stays `- [ ]` until all completion criteria are met
2. As sub-criteria are completed: individual sub-checkboxes are updated to `- [x]`
3. When all criteria pass: the top-level checkbox is updated to `- [x]`
4. After updating: changes are committed to preserve progress

### Commit Strategy

After completing each task:
```
git add .specs/{feature}/tasks.md [+ implementation files]
git commit -m "feat: T001 complete — {brief description}"
```

This ensures progress is saved even if the agent stops unexpectedly.

## --resume Operation

The `--resume` option enables continuation from the last incomplete task:

```
1. Read tasks.md
2. Scan all top-level checkboxes
3. Find the first unchecked task (- [ ])
4. Check its sub-criteria:
   - All unchecked → start task from beginning
   - Some checked → continue from first unchecked criterion
5. Continue executing remaining tasks in order
```

### Resume Scenarios

| Scenario | Behavior |
|----------|----------|
| All tasks checked | Report "All tasks complete", proceed to final gate |
| First task unchecked | Start from the beginning |
| Middle task unchecked | Skip completed tasks, continue from unchecked |
| Partial sub-criteria | Resume within the task at the unchecked criterion |

## Troubleshooting

### Common Issues

**"workflow.md not found"**
- Run `spec-workflow-init` to generate the workflow file
- Or proceed with the minimal built-in flow

**"coding-rules.md not found"**
- Run `spec-rules-init` to generate the rules file
- Or proceed without rule enforcement

**"tasks.md not found"**
- Ensure spec-generator has been run for this feature
- Or use `--issue` to run in minimal mode (Issue-only)

**"gh CLI not authenticated"**
- Run `gh auth login` to authenticate
- Ensure you have write access to the repository

**Task loop appears stuck**
- Check if a `[MUST]` rule violation is blocking progress
- Review the error message and fix the violation
- Use `--resume` to continue after fixing

**Agent stopped mid-task**
- Use `--resume` to continue from the last checkpoint
- Check git log to see the last committed progress
- tasks.md checkboxes show exactly where execution stopped

### Safety Mechanisms

spec-implement includes these safety guards:
- Never force pushes
- Never pushes directly to main/master
- Blocks PR creation if tests fail
- Asks for confirmation before large-scale code deletions
- Commits progress after each task for recoverability

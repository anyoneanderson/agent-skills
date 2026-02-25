# spec-implement Guide

## Overview

spec-implement automates the implementation-to-PR workflow by reading project-specific configuration files and executing tasks from structured specifications.

It acts as an execution engine that:
- Reads the workflow file (`issue-to-pr-workflow.md`) as the development playbook
- Enforces the coding rules file (`coding-rules.md`) as quality gates
- Reads project instruction files (`CLAUDE.md`, `AGENTS.md`) as supplementary rules
- Tracks progress via `.specs/{feature}/tasks.md` checkboxes
- Creates a PR upon successful completion

## Full Execution Flow

```
1. Initial Checks
   ├── Verify working directory (git repo, gh CLI available)
   ├── Parse options (--resume, --issue, --spec, --dry-run, --parallel, --no-parallel)
   └── Locate spec directory (.specs/{feature}/)

2. File Loading (flexible path search)
   ├── issue-to-pr-workflow.md (playbook)
   │   └── Search order: docs/development/ → docs/ → find command
   ├── coding-rules.md (quality rules)
   │   └── Search order: docs/development/ → docs/ → find command
   ├── CLAUDE.md, src/CLAUDE.md, test/CLAUDE.md, AGENTS.md (project instructions)
   ├── .specs/{feature}/requirement.md
   ├── .specs/{feature}/design.md
   └── .specs/{feature}/tasks.md

3. Issue Analysis
   ├── gh issue view {number} for context
   └── Extract requirements, labels, assignees

4. Branch Creation 🚨 BLOCKING GATE
   ├── Dynamically detect base branch from workflow (default: main)
   ├── Follow workflow's naming convention (default: feature/issue-{N}-{desc})
   └── Block implementation on main/master/develop (verification required)

5. Runtime-Aware Parallel Mode Resolution
   ├── Determine runtime from current execution environment
   ├── Parse workflow `Agent definition files` section (if present)
   ├── Validate runtime-specific sub-agent setup
   │   ├── Codex: .codex/config.toml + multi_agent + agents.workflow-*
   │   └── Claude Code: workflow-declared files (fallback: .claude/agents/workflow-*.md)
   ├── If runtime is ambiguous, ask user to choose
   └── If setup is invalid, fallback to single-agent sequential mode

6. Task Loop
   ├── Agent role detection (if defined in workflow)
   ├── Read next unchecked task from tasks.md
   ├── Reference design.md for implementation details
   ├── Implement the task
   ├── 🔍 Implementation review (design.md + coding-rules.md + CLAUDE.md)
   ├── Test implementation (if applicable)
   ├── 🔍 Test review (coverage + pattern verification)
   ├── Run quality checks
   ├── Update tasks.md checkbox (- [ ] → - [x])
   └── Commit progress (following project commit conventions)

7. Final Quality Gate
   ├── Run all tests (from workflow)
   ├── Run lint/typecheck (from workflow)
   ├── Verify all [MUST] rules pass
   └── Verify CLAUDE.md conditional rules pass

8. PR Creation
   ├── Follow workflow's PR template
   ├── --base {base_branch} (dynamically determined from workflow)
   ├── Link to issue (Closes #{N})
   └── Monitor CI (if specified in workflow)
```

## File Loading

### Workflow File Search

The workflow file is searched in the following order:
1. `docs/development/issue-to-pr-workflow.md`
2. `docs/issue-to-pr-workflow.md`
3. `find . -name "issue-to-pr-workflow.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" | head -1`

The first file found is used.

### Coding Rules File Search

The coding rules file is searched in the following order:
1. `docs/development/coding-rules.md`
2. `docs/coding-rules.md`
3. `find . -name "coding-rules.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" | head -1`

The first file found is used.

### Project Instruction Files

The following files are read if they exist:
- `CLAUDE.md` (project root)
- `src/CLAUDE.md` (source-level rules)
- `test/CLAUDE.md` (test-level rules)
- `AGENTS.md` (agent definitions)

Conditional rules (IF-THEN patterns, conditional instructions, environment-specific constraints), environment constraints, and coding conventions from these files are applied with the same enforcement level as `[MUST]` rules from coding-rules.md.

### How the Workflow File Is Used

The workflow file is a project-specific playbook that spec-implement reads and follows section by section. It typically contains:

| Section | What spec-implement extracts |
|---------|------------------------------|
| Development Environment | Environment setup commands, container start commands |
| Issue Analysis and Setup | Branch naming conventions, issue reading instructions |
| Branch Strategy / PR Target | **Base branch** (e.g., `develop`, `main`) and PR target |
| Phased Implementation | Implementation order, coding guidelines |
| Agent Roles / Sub-agents | Agent role definitions (if present) |
| Agent Definition Files (Optional) | Explicit sub-agent definition file paths |
| Testing | Test commands, coverage thresholds |
| PR Creation and Quality Gates | Pre-PR checks, PR body template |
| CI/CD Monitoring | CI verification commands |
| Commit Message Rules | Commit message format and language requirements |

**Key principle**: spec-implement does NOT hardcode any project-specific commands or branch names. All come from the workflow file.

### When Workflow File Is Missing

If no workflow file is found at any of the searched paths:
1. A warning is displayed
2. The user is asked whether to run spec-workflow-init to generate it
3. If declined, a minimal built-in flow is used:
   - Issue analysis → branch creation → implement tasks → run tests → create PR
   - Base branch defaults to `main`

## Coding Rules Loading

### How the Rules File Is Used

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

If no rules file is found at any of the searched paths:
1. A warning is displayed
2. The user is asked whether to run spec-rules-init to generate it
3. If declined, implementation proceeds without rule enforcement
4. CLAUDE.md or AGENTS.md are used as fallback references if available

## Branch Creation (Blocking Gate)

### Feature Branch is MANDATORY

Implementation MUST NOT proceed on `main`, `master`, or `develop` branches. This gate cannot be skipped.

If the workflow file defines a "protected branches" or "branch protection" section, use that list instead of the defaults.

### Dynamic Base Branch Detection

1. Search the workflow file for "branch strategy", "base branch", "PR target", "develop", "main"
2. If a branch is specified (e.g., `develop`), use it as `{base_branch}`
3. If not specified, default to `main`

### Post-Creation Verification

```bash
current_branch=$(git branch --show-current)
if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ] || [ "$current_branch" = "develop" ]; then
  echo "🚨 ERROR: Cannot implement on protected branch: $current_branch"
  exit 1
fi
```

If this verification fails, the task loop MUST NOT proceed.

## Agent Role Detection

If the workflow file contains an "Agent Roles", "Sub-agents", or equivalent section:

1. Parse role definitions (e.g., implementer, reviewer, tester)
2. Present options to the user (sub-agent parallel execution vs single agent)
3. If sub-agents selected: dispatch runtime-specific sub-agents per role definition
4. If single agent selected: proceed with sequential execution

### Runtime Detection Rule

Determine runtime from the current execution environment. Do NOT infer runtime solely from repository directories (`.codex/`, `.claude/`).

- Use `.codex/` and `.claude/` files only to validate sub-agent setup
- Parse workflow `Agent definition files` section first, if present
- Use workflow-declared agent definition file paths as first priority
- If not declared in workflow, fallback to runtime default paths
- If runtime cannot be determined, ask user to choose runtime before dispatch
- If runtime setup is invalid, fallback to sequential mode

### Parsing Workflow Table Format

Workflow files typically define agent roles using two Markdown tables:

**Role Assignment Table** — maps roles to agent names and responsibilities:

```markdown
| Role | Agent | Responsibility |
|------|-------|---------------|
| Implementer | workflow-implementer | Write implementation code following coding-rules.md |
| Reviewer | workflow-reviewer | Code review against coding-rules.md standards |
| Tester | workflow-tester | Write and run tests, verify coverage |
```

**Parallel Execution Strategy Table** — defines which roles are active in each phase:

```markdown
| Phase | Implementer | Tester | Reviewer |
|-------|-------------|--------|----------|
| Analysis | Design review | Test plan | - |
| Implementation | Write code | Write tests | - |
| Review | - | - | Review code + tests |
| Quality Gate | - | Run all tests | Final check |
```

### Mapping Tables to Sub-Agent Parameters

When spawning sub-agents:

1. **Sub-agent identifier**: Use the `Agent` column value from the Role Assignment Table as `subagent_type` (e.g., `subagent_type: "workflow-implementer"`)
2. **Definition file path**: Use role-specific path from workflow `Agent definition files` section if declared; otherwise use runtime defaults
3. **Agent responsibility**: Use the `Responsibility` column value as context in the task prompt
4. **Phase execution order**: Follow the Parallel Execution Strategy Table row by row:
   - Cells with `-` mean the role is idle in that phase
   - Non-`-` cells describe the role's action in that phase
   - Roles active in the same phase row can run in parallel
   - Phases execute sequentially (top to bottom)

### Example: Runtime-Specific Dispatch

For the "Implementation" phase where Implementer and Tester are both active:

```text
# Codex (parallel dispatch example)
Task:
  subagent_type: workflow-implementer
  prompt: "Write implementation code following coding-rules.md..."

Task:
  subagent_type: workflow-tester
  prompt: "Write tests following project test patterns..."
```

```text
# Claude Code (pseudocode; use runtime-native call format)
SubAgent:
  subagent_type: workflow-implementer
  prompt: "Write implementation code following coding-rules.md..."

SubAgent:
  subagent_type: workflow-tester
  prompt: "Write tests following project test patterns..."
```

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

After completing each task, commit following the project's commit conventions:

1. Extract commit message rules from coding-rules.md or CLAUDE.md (format, language)
2. Generate commit messages following extracted rules
3. Default fallback (no rules found): `feat: {task-id} complete — {brief description}`

```
git add .specs/{feature}/tasks.md [+ implementation files]
git commit -m "{commit message following project conventions}"
```

This ensures progress is saved even if the agent stops unexpectedly.

## Review Phases

### Implementation Review (after each task)

After completing a task's implementation, self-review before proceeding:
- Consistency with design.md specifications
- No `[MUST]` rule violations from coding-rules.md
- No conditional rule violations from CLAUDE.md
- If issues found → fix before proceeding

### Test Review (after test implementation)

After completing test implementation:
- Test coverage meets completion criteria
- Test patterns match project conventions
- If issues found → fix before proceeding

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
- Verify both `docs/development/` and `docs/` were checked
- Run `spec-workflow-init` to generate the workflow file
- Or proceed with the minimal built-in flow

**"coding-rules.md not found"**
- Verify both `docs/development/` and `docs/` were checked
- Run `spec-rules-init` to generate the rules file
- Or proceed without rule enforcement

**"tasks.md not found"**
- Ensure spec-generator has been run for this feature
- Or use `--issue` to run in minimal mode (Issue-only)

**"parallel mode could not start"**
- Verify runtime-specific setup:
  - Codex: `.codex/config.toml` includes `multi_agent = true` and `agents.workflow-*`
  - Claude Code: workflow-declared paths exist (fallback: `.claude/agents/workflow-implementer.md`, `.claude/agents/workflow-reviewer.md`, `.claude/agents/workflow-tester.md`)
- If setup is incomplete, continue in sequential mode or run `spec-workflow-init` again

**"workflow-declared agent definition file does not exist"**
- Check file paths listed in workflow `Agent definition files` section
- Fix paths in workflow or create missing files, then retry parallel execution

**"workflow agent name not configured in runtime"**
- Verify `Agent` names in workflow Role Assignment Table match configured runtime agent identifiers
- Fix the workflow table or runtime config, then retry parallel execution

**"gh CLI not authenticated"**
- Run `gh auth login` to authenticate
- Ensure you have write access to the repository

**Attempting to implement on a protected branch**
- Create a feature branch before proceeding
- When using `--resume`, verify you are on the correct branch

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
- Blocks implementation on protected branches (main/master/develop)
- Never force pushes
- Never pushes directly to main/master
- Blocks PR creation if tests fail
- Asks for confirmation before large-scale code deletions
- Commits progress after each task for recoverability

## `--dry-run` Output Format

When `--dry-run` is specified, display the following and exit without making changes:

```
=== spec-implement Dry Run ===

📁 Detected Files:
  Workflow:      {path or "not found"}
  Coding Rules:  {path or "not found"}
  CLAUDE.md:     {list of found files}
  Spec Dir:      {.specs/{feature}/ path}

🌿 Branch Strategy:
  Base Branch:   {base_branch}
  Feature Branch: feature/issue-{N}-{description}
  PR Target:     {base_branch}

📋 Tasks ({N} total, {M} completed, {K} remaining):
  {list each task with status}

🔍 Quality Gates:
  [MUST] rules:  {count} rules detected
  Test command:  {extracted command or "default"}
  Lint command:  {extracted command or "default"}

🤖 Agent Roles:  {detected roles or "none (single agent)"}
🤖 Runtime:      {codex | claude-code | unknown}
🤖 Parallel:     {enabled | disabled | fallback-to-sequential}
🤖 Agent files:  {workflow-declared paths | runtime defaults}

📝 Commit Convention: {extracted format or "default"}
```

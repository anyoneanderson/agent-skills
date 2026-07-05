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
0. Role Guard — orchestrator only, never write code/review/tests yourself

1. Initial Checks
   ├── Verify working directory (git repo, gh CLI available)
   ├── Parse options (--resume, --issue, --spec, --dry-run)
   ├── Check cmux availability ($CMUX_SOCKET_PATH)
   └── Locate spec directory 🚨 BLOCKING
       ├── Always scan .specs/ (even if Issue body has a path)
       ├── If found → use it and proceed
       └── If not found → ask user for path or suggest spec-generator

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
   │   ├── Codex: .codex/agents/workflow-*.toml files with matching name fields
   │   └── Claude Code agent team: .claude/agents/workflow-*.md files with matching names
   ├── If runtime is ambiguous, ask user to choose
   └── If setup is invalid, fallback to single-agent sequential mode

6. Task Loop (Orchestrator delegates to worker skills)
   ├── Parse role tags: [orchestrator] phases → execute directly
   ├── [code] phases → for each unchecked task:
   │   ├── invoke spec-code --task {id} --spec {path}
   │   ├── invoke spec-review --task {id} --spec {path}
   │   ├── read review-{id}.md → fix loop (max 3):
   │   │   └── invoke spec-code --feedback review-{id}.md → re-review
   │   ├── invoke spec-test --task {id} --spec {path}
   │   ├── if test FAIL → invoke spec-code --feedback test-{id}.md → re-test
   │   ├── if review PASS AND test PASS → update tasks.md checkbox
   │   └── commit progress
   └── Key: orchestrator does NOT write code or review — always delegates

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
2. Resolve one of three parallel patterns: Codex custom agents, Claude Code agent team, or cmux dispatch
3. If sub-agents selected: dispatch runtime-specific sub-agents per role definition
4. If single agent selected: proceed with sequential execution

### Runtime Detection Rule

Determine runtime from the current execution environment. Do NOT infer runtime solely from repository directories (`.codex/`, `.claude/`).

- Use `.codex/` and `.claude/` files only to validate sub-agent setup
- Parse workflow `Agent definition files` section first, if present
- Use workflow-declared agent definition file paths as first priority
- If not declared in workflow, fallback to runtime default paths
- For Codex, runtime defaults are `.codex/agents/workflow-implementer.toml`, `.codex/agents/workflow-reviewer.toml`, and `.codex/agents/workflow-tester.toml`
- Codex discovers custom agents from `.codex/agents/*.toml`; do not require or create `[agents.<name>] config_file = ...` entries
- For Claude Code agent team, runtime defaults are `.claude/agents/workflow-implementer.md`, `.claude/agents/workflow-reviewer.md`, and `.claude/agents/workflow-tester.md`
- Claude Code agent team should be used when running inside Claude Code, the `.claude/agents/workflow-*.md` files exist, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set
- cmux dispatch is a separate external-pane mode; use it only when the workflow/user explicitly selects cmux or runtime-native agents are unavailable
- If runtime cannot be determined, ask user to choose runtime before dispatch
- If runtime setup is invalid, fallback to sequential mode

### Parallel Mode Priority

Use this priority when `/spec-implement --issue {N}` is invoked without an explicit dispatch option:

1. **Codex custom agents**: running in Codex and `.codex/agents/workflow-*.toml` exists
2. **Claude Code agent team**: running in Claude Code, `.claude/agents/workflow-*.md` exists, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set
3. **cmux dispatch**: `$CMUX_SOCKET_PATH` is set and the workflow/user selected cmux dispatch
4. **Single agent**: no valid parallel setup is available

Do not stop to ask when exactly one valid runtime-native setup is available. Ask only when multiple valid modes are available and the workflow does not declare a preference, when the runtime is ambiguous, or when Claude Code agent teams are requested but `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not enabled.

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

**Multi-Agent Role Assignment Strategy Table** — defines which roles are active in each phase:

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

1. **Sub-agent identifier**: Use the `Agent` column value from the Role Assignment Table as the runtime agent type (for Codex, `agent_type: workflow-implementer`; for runtimes that name the field differently, pass the same value in that runtime's agent type field)
2. **Definition file path**: Use role-specific path from workflow `Agent definition files` section if declared; otherwise use runtime defaults
3. **Agent responsibility**: Use the `Responsibility` column value as context in the task prompt
4. **Phase execution order**: Follow the Multi-Agent Role Assignment Strategy Table row by row:
   - Cells with `-` mean the role is idle in that phase
   - Non-`-` cells describe the role's action in that phase
   - Roles active in the same phase row can run in parallel
   - Phases execute sequentially (top to bottom)

### Example: Runtime-Specific Dispatch

For the "Implementation" phase where Implementer and Tester are both active:

```text
# Codex (parallel dispatch example)
Task:
  agent_type: workflow-implementer
  prompt: "Run /spec-code --issue {N} --task {task-id} --spec {path}. Follow the workflow and report changed files, commands run, and blockers."

Task:
  agent_type: workflow-tester
  prompt: "Run /spec-test --task {task-id} --spec {path}. Report tests added, commands run, failures, and coverage gaps."
```

```text
# Claude Code agent team (runtime-native natural-language example)
Create an agent team for this implementation phase.
Use the project subagent definitions named workflow-implementer and workflow-tester.
Name the teammates implementer and tester.
Assign implementer: run /spec-code --issue {N} --task {task-id} --spec {path}. Report changed files, commands run, and blockers.
Assign tester: run /spec-test --task {task-id} --spec {path}. Report tests added, commands run, failures, and coverage gaps.
Use separate file ownership to avoid conflicts, and wait for both teammates before proceeding.
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
  - Codex: `.codex/agents/workflow-implementer.toml`, `.codex/agents/workflow-reviewer.toml`, and `.codex/agents/workflow-tester.toml` exist and their `name` fields match the workflow `Agent` column
  - Claude Code agent team: workflow-declared paths exist (fallback: `.claude/agents/workflow-implementer.md`, `.claude/agents/workflow-reviewer.md`, `.claude/agents/workflow-tester.md`)
  - cmux + Claude Code: `$CMUX_SOCKET_PATH` is set, `cmux-delegate` is available, and the role table `AI` column maps implementer/tester/reviewer to `claude` where desired
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
📋 Review Rules:  {path or "not found"}
🖥️  cmux Dispatch: {enabled | disabled}
```

## cmux Dispatch Patterns

When cmux dispatch mode is selected, sub-agents are launched in separate cmux workspaces instead of using built-in Agent tools.

### Dispatch Method Selection

1. **cmux-delegate skill is installed** (recommended):
   - Use `Skill` tool to invoke `cmux-delegate` for each agent role
   - The skill abstracts cmux CLI operations (workspace creation, agent launch, polling, result collection)
   - **Do NOT use the built-in Agent tool** — always use `cmux-delegate` skill
   - **Safety rule**: write the composed prompt or diff to a temporary file first, then pass the file contents. Do NOT inline multi-line content directly into a quoted `--task` or `--diff` argument.
   - Concrete invocation examples:
     ```
     # Launch implementer with Codex
     TASK_FILE=$(mktemp)
     cat > "$TASK_FILE" <<'EOF'
     You are a workflow-implementer.
     {definition file content}

     Task: Implement T001 — create user model following design section 2.3.
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent codex --task \"$(cat \"$TASK_FILE\")\""

     # Launch tester with Codex (parallel with implementer)
     TEST_TASK_FILE=$(mktemp)
     cat > "$TEST_TASK_FILE" <<'EOF'
     You are a workflow-tester.
     {definition file content}

     Task: Write tests for T001 — verify user model CRUD operations.
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent codex --task \"$(cat \"$TEST_TASK_FILE\")\""

     # Launch reviewer with Claude (after implementation + tests complete)
     REVIEW_TASK_FILE=$(mktemp)
     cat > "$REVIEW_TASK_FILE" <<'EOF'
     You are a workflow-reviewer.
     {definition file content}

     Review the following changes against review_rules.md:
     {git diff output}
     EOF
     Skill:
       skill: "cmux-delegate"
       args: "--agent claude --task \"$(cat \"$REVIEW_TASK_FILE\")\""
     ```
   - Second opinion execution:
     ```
     DIFF_FILE=$(mktemp)
     git diff HEAD > "$DIFF_FILE"
     Skill:
       skill: "cmux-second-opinion"
       args: "--diff \"$(cat \"$DIFF_FILE\")\" --rules '{path to review_rules.md}'"
     ```
2. **cmux-delegate skill is NOT installed** (fallback):
   - Execute the cmux CLI patterns below directly via Bash

### Agent Launch Pattern (low-level fallback)

```bash
# 1. Create split pane (do NOT use new-workspace — it may create a non-terminal surface)
WS=$(cmux new-split right)
# Output: OK surface:{N} workspace:{N}

# 2. Launch agent (select command based on AI column in role table)
# Claude Code:
cmux send --surface surface:{N} "claude --dangerously-skip-permissions\n"
# Codex:
cmux send --surface surface:{N} "codex --dangerously-bypass-approvals-and-sandbox\n"
# Gemini CLI:
cmux send --surface surface:{N} "gemini\n"

# 3. Detect prompt (poll every 3s, timeout 15s)
sleep 3
cmux read-screen --surface surface:{N}

# 4. Send task from a temporary file to preserve quotes/newlines safely
TASK_FILE=$(mktemp)
cat > "$TASK_FILE" <<'EOF'
{task_prompt}
EOF
while IFS= read -r line; do
  cmux send --surface surface:{N} "$line"
  cmux send-key --surface surface:{N} return
done < "$TASK_FILE"

# 5. Monitor completion (graduated polling: 5s → 10s → 30s)
cmux read-screen --surface surface:{N}

# 6. Collect results
cmux read-screen --surface surface:{N} --scrollback 500

# 7. Cleanup
cmux close-workspace --workspace workspace:{N}
```

### Agent Selection from Role Table

The workflow's role assignment table may include an `AI` column:

| Role | Agent | AI | Responsibility |
|------|-------|----|---------------|
| Implementer | workflow-implementer | codex | Write code |
| Tester | workflow-tester | codex | Write tests |
| Reviewer | workflow-reviewer | claude | Code review |

Map `AI` column values to launch commands:

| AI Value | Command (auto-approve) |
|----------|----------------------|
| `claude` | `claude --dangerously-skip-permissions` |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox` |
| `gemini` | `gemini` (no auto-approve available) |
| *(missing)* | Default: `claude --dangerously-skip-permissions` |

### Multi-Agent Execution with cmux

Follow the strategy table — roles in the same row run in parallel:

1. Launch implementer + tester in separate workspaces simultaneously
2. Monitor both for completion
3. After both complete, launch reviewer
4. Collect all results

## Review Gate Details

### Implementation Review Gate

The review gate replaces the simple self-review with a structured process:

1. **Load criteria**: review_rules.md (if found) + coding-rules.md + CLAUDE.md
2. **Review**: Check severity-based criteria (security, type safety, patterns, quality)
3. **Classify findings**:
   - **Critical**: Security vulnerabilities, bugs → must fix
   - **Improvement**: Quality, readability → should fix
   - **Minor**: Style → log only
4. **Fix loop** (max 3 iterations):
   - Fix issues → re-review only changed code
   - After 3rd iteration: unresolved improvements downgraded to minor
   - After 3rd iteration: unresolved critical → ask user
5. **Second opinion** (if cmux dispatch + second-opinion enabled):
   - After self-review loop passes
   - Use `Skill` tool to invoke `cmux-second-opinion` skill (recommended), or launch reviewer agent manually in cmux workspace as fallback
   - The skill sends diff + review_rules.md to a different AI and collects the structured result
   - New critical findings → 1 additional fix loop
6. **Gate passes** when no unresolved critical issues remain

### Test Review Gate

Same structure as Implementation Review Gate, with additional test-specific criteria:

- Coverage meets completion criteria
- Edge cases and error paths are tested
- Test isolation (no inter-test dependencies)
- AAA pattern (Arrange → Act → Assert)

### Second Opinion Settings (from workflow)

Read the setting from the workflow's "Second Opinion" / "セカンドオピニオン" section:

| Setting | Behavior |
|---------|----------|
| "Always" / "毎回実施" | Auto-run at every review gate |
| "On request" / "ユーザー要求時のみ" | Ask user before running (AskUserQuestion) |
| "Never" / "実施しない" | Skip second opinion |
| *(section not found)* | Default: "On request" |

**Execution**: Use `Skill` tool to invoke `cmux-second-opinion`:
```
DIFF_FILE=$(mktemp)
git diff HEAD > "$DIFF_FILE"
Skill:
  skill: "cmux-second-opinion"
  args: "--diff \"$(cat \"$DIFF_FILE\")\" --rules '{path to review_rules.md}'"
```
If the skill is not installed, fallback to manually launching a reviewer agent in a cmux workspace.

## Agent Definition File Injection

When spawning runtime-native Codex custom agents, do not inject TOML contents into the prompt. Codex loads the custom agent's `developer_instructions` from `.codex/agents/*.toml` based on the agent type.

When spawning Claude Code agent-team teammates, do not inject the Markdown agent definition into the prompt if Claude Code can select the project subagent directly. Claude Code loads the selected `.claude/agents/*.md` agent definition. Agent-team teammates do not inherit the leader's conversation history, so include task-specific context in the team creation prompt: issue, spec path, task id, owned files, dependencies, and expected artifacts.

When using cmux or another external runtime that cannot select the custom agent type directly, inject the content of the agent definition file into the task prompt. This ensures each external agent operates with full awareness of its role-specific rules and constraints.

### Injection Steps

1. If using runtime-native Codex sub-agents, use the workflow `Agent` column value as the custom agent type and skip file-content injection.
2. If using Claude Code agent team, include the workflow `Agent` column value as the project subagent name in the team creation prompt and skip file-content injection.
3. If using cmux or external dispatch, read the definition file for the role:
   - Use path from workflow `Agent definition files` section if declared
   - Otherwise use runtime defaults (e.g., `.claude/agents/workflow-implementer.md`)
4. Prepend the definition file content to the task prompt
5. If no definition file exists, use the `Responsibility` column from the role assignment table as the role description

### Prompt Composition Template

```
You are a {role_name}.

{content of agent definition file}

Task: {actual task description from tasks.md}

Context:
- Design reference: {design.md section}
- Coding rules: {path to coding-rules.md}
- Review rules: {path to review_rules.md} (reviewer only)
- Target files: {file list}
```

### Example: Runtime-Native Codex Custom Agent

```text
Agent:
  agent_type: workflow-implementer
  prompt: |
    Run /spec-code --issue 123 --task T001 --spec .specs/user-model.
    Target files: src/models/user.ts
    Report changed files, commands run, and any blockers.
```

### Example: Via cmux-delegate Skill

```text
TASK_FILE=$(mktemp)
cat > "$TASK_FILE" <<'EOF'
You are a workflow-implementer.
{content of definition file}

Task: Implement T001 — create user model.
Target files: src/models/user.ts
EOF
Skill:
  skill: "cmux-delegate"
  args: "--agent codex --task \"$(cat \"$TASK_FILE\")\""
```

### Reviewer Prompt Composition

The reviewer prompt includes the diff and review criteria in addition to the standard prompt:

```
You are a workflow-reviewer.

{content of agent definition file}

Review the following changes:
{git diff output or changed files summary}

Review criteria:
- review_rules.md: {path}
- coding-rules.md: {path}
- design.md: {relevant section}

Classify findings as: Critical / Improvement / Minor
```

## Kind-Based Task Routing

This section details the `--roles` layer summarized in SKILL.md → "Phase 6b". It routes
each task to an executor (spec-code / spec-review, or the agent-delegate peer) by the
task's `kind` label, so an orchestrator can hand implementation to a different LLM per
task while keeping the Phase 6 loop and its review gates intact.

### When It Activates

- **`--roles` absent** → legacy path. Every task uses spec-code; every review uses
  spec-review; spec-test unchanged. agent-delegate is never invoked. This is the exact
  behavior of specs that predate the pipeline.
- **`--roles` present** → orchestrated path. Each task's implementer and reviewer are
  resolved per the rules below.

The loop's control flow is identical in both paths: per-phase iteration, the fix loop
with its 3-iteration cap, gate evaluation (Critical/Improvement re-run, Minor logged),
checkbox marking, and commit strategy. Only the *executor* of each step is resolved per
task.

### Parsing `--roles`

`--roles` accepts either form:

1. **Inline map**: `ui=claude,backend=codex,test=codex` — comma-separated `kind=owner`
   pairs. Owner is `claude` or `codex`.
2. **pipeline.yml path**: a file with a `roles:` block. Read `roles.impl_ui`,
   `roles.impl_backend`, `roles.impl_test` and map them to kinds `ui`/`backend`/`test`.

```bash
# Inline form → associative lookup
# roles[ui]=claude roles[backend]=codex roles[test]=codex

# pipeline.yml form (yq or awk); missing keys leave that kind unmapped
impl_ui="$(yq -r '.roles.impl_ui // empty' "$roles_path")"      # → roles[ui]
impl_backend="$(yq -r '.roles.impl_backend // empty' "$roles_path")"
impl_test="$(yq -r '.roles.impl_test // empty' "$roles_path")"
```

### Owner Resolution (per task)

```
kind  = value of the task's `kind:` field in its tasks.md detail block
owner = roles[kind]              if kind is known AND present in the map
owner = claude                   otherwise (unknown/missing kind, or kind not mapped)
```

`claude` → the task runs through **spec-code** exactly as today (all dispatch modes in
"Agent Role Detection" still apply). `codex` → the task runs through the **agent-delegate**
script per its contract.

### Delegating Implementation to the Peer (`owner == codex`)

Follow `agent-delegate/references/contract.md`. Code implementation may exceed the
~10-minute Bash ceiling, so use `--detach` + `report.json` polling, and
`--sandbox workspace-write` (the peer must write files). Pass `--target` explicitly.

```bash
OUT=".specs/{feature}/delegate/{task-id}"; mkdir -p "$OUT"
PROMPT="$(mktemp)"
cat > "$PROMPT" <<EOF
Implement {task-id} from the spec.
- Spec dir: .specs/{feature}/  (requirement.md, design.md, tasks.md)
- Task detail: {paste the task's detail block, including Done criteria and Target files}
- Coding rules: {path to coding-rules.md}
Commit nothing; report changed files and any blocker.
EOF

report="$(agent-delegate.sh --mode delegate --target codex \
  --prompt-file "$PROMPT" --out-dir "$OUT" --label "{task-id}" \
  --sandbox workspace-write --detach | tail -1)"
until [ -f "$report" ]; do sleep 15; done
status="$(jq -r .status "$report")"     # done | blocked
```

- `status == done` → the peer finished. Mark the checkbox and commit (the orchestrator,
  not the peer, owns commits — the peer is told to commit nothing).
- `status == blocked` → read `blocker` / `blocker_category`; feed into the fix loop
  (see below) or surface to the caller.

### Peer Review (`owner == claude`, implementer is claude → reviewer is codex)

Reviews are short, so run synchronously (no `--detach`). Review mode is always read-only
per the contract.

```bash
OUT=".specs/{feature}/review/{task-id}"; mkdir -p "$OUT"
git diff "{base_branch}...HEAD" > "$OUT/{task-id}-diff.txt"
PROMPT="$(mktemp)"
cat > "$PROMPT" <<EOF
Review the changes for {task-id}.
- Diff: $OUT/{task-id}-diff.txt
- Spec dir: .specs/{feature}/
- Review criteria: {path to review_rules.md}, {path to coding-rules.md}
EOF

report="$(agent-delegate.sh --mode review --target codex \
  --prompt-file "$PROMPT" --out-dir "$OUT" --label "{task-id}-review" | tail -1)"
review_file="$(jq -r .artifacts.review_file "$report")"
gate="$(grep -m1 '^Gate:' "$review_file")"    # Gate: PASS | Gate: FAIL
```

The review file carries the same severity sections (`### Critical`, `### Improvement`,
`### Minor`) and `Gate: PASS|FAIL` line as spec-review output, so the existing gate logic
in "Review Gate Details" consumes it with no change. When the implementer is codex, the
reviewer is claude and this whole block is replaced by the normal spec-review call.

### Fix Loop Routing

The fix loop's structure (max 3 iterations, then downgrade/ask) is unchanged. Only the
fix executor follows the task's implementer:

| Implementer | Fix step | Re-review |
|---|---|---|
| claude | `spec-code --feedback {findings}` | reviewer re-runs (codex via agent-delegate `--resume {thread_id}`, or claude via spec-review) |
| codex | agent-delegate `--mode delegate --resume {thread_id}` with findings appended to the prompt | reviewer re-runs (claude via spec-review) |

For agent-delegate re-review across rounds, reuse the review session with
`--resume {thread_id}` (thread_id read from the prior `report.json`) to preserve context
and save tokens. Resume keeps the original sandbox; review sessions are read-only, which
satisfies the contract's resume rule.

### Unavailable Peer Fallback

If a `codex`-owned task cannot be delegated — the script is missing, exits `2`, or the
report shows `blocker_category: tool_unavailable`:

- **Under an orchestrator**: report the blocker upward. Reassignment (to claude) is the
  orchestrator's decision per its mode (manual asks the human; auto reassigns and records
  it). Do not silently decide.
- **Standalone `/spec-implement`**: warn and fall back to spec-code for that task so the
  run still completes.

Never inline agent-delegate's internal implementation; depend only on the flags and
`report.json` schema in its contract.

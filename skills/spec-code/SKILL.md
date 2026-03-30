---
name: spec-code
description: |
  Implement a single task from spec documents autonomously.

  Reads requirement.md, design.md, and tasks.md to understand the full project context,
  then implements the specified task following coding rules and project conventions.
  Supports --feedback mode to address review or test findings.

  English triggers: "Implement task", "Code this task", "Run spec-code"
  日本語トリガー: 「タス��を実装」「このタスクをコーディング」「spec-codeを実行」
license: MIT
---

# spec-code — Implement a Single Task from Specs

Autonomously implement one task from the spec documents, understanding the full project context before writing code.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/code-guide.ja.md`
3. English input → English output, use `references/code-guide.md`
4. Explicit override takes priority

## Options

| Option | Description |
|--------|-------------|
| `--issue {N}` | GitHub Issue number for context |
| `--spec {path}` | Path to .specs/ directory |
| `--task {task-id}` | Task ID to implement (e.g., T-007) |
| `--feedback {file}` | Feedback mode: read review or test result file and address findings |

## Execution Flow

### Step 0: Context Loading (Phase A / Phase B)

**Phase A — First invocation (full context):**

1. **Locate and read workflow** (search order: `docs/development/issue-to-pr-workflow.md` → `docs/` → find):
   - Identify your role as **implementer**
   - Read Agent definition file if referenced (e.g., `.claude/agents/workflow-implementer.md`)

2. **Read Issue** (if `--issue` provided):
   - Run `gh issue view {N} --json title,body` to understand the feature overview

3. **Read all spec files** in `--spec` directory:
   - `requirement.md` — what to build and why
   - `design.md` — how to build it (architecture, data models, interfaces)
   - `tasks.md` — all tasks and their relationships
   - Understand the full picture before focusing on your task

4. **Read project rules** (if they exist):
   - `coding-rules.md` (search: `docs/development/` → `docs/` → find)
   - `CLAUDE.md` / `AGENTS.md` at project root

**Phase B — Feedback re-invocation (minimal context):**

When called with `--feedback`, load only:
1. The feedback file (review or test results)
2. The target task description from `tasks.md`
3. The relevant `design.md` section
4. The changed files from the previous implementation

Do NOT re-read the full spec set unless the feedback indicates a misunderstanding of requirements.

### Step 1: Locate Target Task

Parse `tasks.md` to find the task matching `--task {task-id}`:
- Extract: task name, requirements ID, design reference, target files, completion criteria
- If task is already checked `[x]`, warn and stop

### Step 2: Reference Design

Read the design section referenced by the task (e.g., "design.md §4.2"):
- Extract: architecture decisions, interfaces, data models
- Identify target files to create or modify

### Step 3: Implement

**Normal mode** (no `--feedback`):
- Follow the design to implement the task
- Apply coding rules and project conventions
- Create or modify only the files specified in the task

**Feedback mode** (`--feedback {file}`):
- Read the feedback file (review result or test result)
- For each Critical finding: fix the violation at the specified file:line
- For each Improvement finding: fix if feasible
- Do NOT modify code unrelated to the findings

### Step 4: Verify Completion Criteria

Check each completion criterion from `tasks.md`:
- If criterion is met, note it
- If not met, continue implementing until satisfied
- Do NOT update the checkbox in `tasks.md` (this is spec-implement's responsibility)

### Step 5: Commit

Commit the implementation following project conventions:
- Read commit message format from `coding-rules.md` or `CLAUDE.md`
- Default format: `feat(scope): {task-id} — {brief description}`
- Stage only implementation files (not `tasks.md`)

## Error Handling

| Situation | Response |
|---|---|
| `--spec` path not found | Error: spec directory not found |
| `--task` ID not found in tasks.md | Error: task ID not found |
| Task already checked [x] | Warning: task already complete, skip |
| Design section not found | Warning: implement based on task description and requirements only |
| `--feedback` file not found | Error: feedback file not found |
| Coding rules not found | Warning: proceed with project defaults |

## Usage Examples

```
# Implement a specific task
/spec-code --issue 36 --task T-007 --spec .specs/did-deactivation/

# Address review feedback
/spec-code --task T-007 --spec .specs/did-deactivation/ --feedback .specs/did-deactivation/review-T-007.md

# Address test failure feedback
/spec-code --task T-007 --spec .specs/did-deactivation/ --feedback .specs/did-deactivation/test-T-007.md

# Standalone (no issue)
/spec-code --task T-003 --spec .specs/auth-feature/
```

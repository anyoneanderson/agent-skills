---
name: spec-implement
description: |
  Specification-driven implementation orchestrator — Coordinate spec-code, spec-review,
  and spec-test to implement from specs to PR.

  Reads issue-to-pr-workflow.md as playbook, delegates implementation to spec-code,
  review to spec-review, testing to spec-test. Manages fix loops, task progression,
  and PR creation. Does NOT write implementation code or perform reviews itself.

  English triggers: "Implement from spec", "Start implementation", "Execute spec tasks"
  日本語トリガー: 「仕様書から実装」「実装を開始」「specタスクを実行」
license: MIT
---

# spec-implement — Orchestrator for Spec-Driven Implementation

Coordinate worker skills (spec-code, spec-review, spec-test) to implement from specifications to pull request. This skill does NOT write code or review — it delegates.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/implement-guide.ja.md`
3. English input → English output, use `references/implement-guide.md`
4. Explicit override takes priority

## Options

| Option | Description |
|--------|-------------|
| `--resume` | Resume from last uncompleted task in tasks.md |
| `--issue {N}` | Specify GitHub Issue number for context |
| `--spec {path}` | Specify .specs/ directory path (default: auto-detect) |
| `--dry-run` | Show execution plan without making any changes |

## Critical First Steps

**BEFORE any implementation, execute these checks in order:**

1. **Verify environment**: `pwd`, `git status`, `gh auth status`

2. **Parse user input**: Extract `--resume`, `--issue`, `--spec`, `--dry-run` options

3. **Locate spec directory**:
   - If `--spec` provided → use that path
   - If issue body contains `.specs/` path → use that
   - Otherwise → scan `.specs/` and ask user to select

4. **Locate and read project files**:
   - **Workflow**: `docs/development/issue-to-pr-workflow.md` → `docs/` → find → fallback
   - **Coding rules**: `docs/development/coding-rules.md` → `docs/` → find → fallback
   - **Review rules**: `docs/development/review_rules.md` → `docs/` → find → optional
   - **Project instructions**: `CLAUDE.md`, `AGENTS.md`
   - **Spec files**: `requirement.md`, `design.md`, `tasks.md`

## Execution Flow

### Phase 1-3: Load Context

Read workflow, coding rules, and project instructions. Same search/fallback logic as before — see `references/implement-guide.md` for details.

Extract from workflow:
- Base branch (default: `main`)
- Branch naming convention
- Commit message format
- Test/lint/build commands
- Dispatch strategy and agent definitions (if present)

### Phase 4: Issue Analysis

If `--issue {N}` is provided:
```bash
gh issue view {N} --json title,body,labels,assignees
```

### Phase 5: Branch Creation

> **🚨 BLOCKING — Feature branch is MANDATORY**

```bash
git checkout {base_branch} && git pull origin {base_branch}
git checkout -b feature/issue-{N}-{brief-description}
```

Post-creation verification — MUST NOT be on `main`, `master`, or `develop`.

### Phase 6: Task Loop (Orchestration)

**Read `tasks.md` and process phases by role tag:**

```
for each phase in tasks.md:
  if phase has [orchestrator] tag:
    execute tasks directly (env setup, config, etc.)

  if phase has [code] tag:
    for each unchecked task in phase:
      // Step 1: Implement
      invoke spec-code --issue {N} --task {task-id} --spec {path}

      // Step 2: Review
      invoke spec-review --task {task-id} --spec {path}
      read .specs/{feature}/review-{task-id}.md

      // Step 3: Fix loop (max 3 iterations)
      iteration = 0
      while review gate == FAIL AND iteration < 3:
        invoke spec-code --task {task-id} --spec {path} --feedback .specs/{feature}/review-{task-id}.md
        invoke spec-review --task {task-id} --spec {path}
        read .specs/{feature}/review-{task-id}.md
        iteration++

      if FAIL after 3 iterations:
        ask user to decide (fix manually / skip / abort)

      // Step 4: Test
      invoke spec-test --task {task-id} --spec {path}
      read .specs/{feature}/test-{task-id}.md

      if test gate == FAIL:
        invoke spec-code --task {task-id} --spec {path} --feedback .specs/{feature}/test-{task-id}.md
        invoke spec-test --task {task-id} --spec {path}

      // Step 5: Mark complete (ONLY if review AND test PASS)
      if review gate == PASS AND test gate == PASS:
        update tasks.md checkbox: - [ ] → - [x]
        commit tasks.md update
```

**Dispatch modes:**

When invoking worker skills, the method depends on execution mode:

| Mode | How to invoke |
|---|---|
| Single agent | Call the skill directly in the current session |
| cmux dispatch | `cmux-delegate --agent {ai} --task "/spec-code --issue {N} --task {id} --spec {path}"` |

For cmux dispatch:
1. Read workflow's dispatch strategy and agent definition file paths
2. Map roles to agents (implementer/tester → cmux-delegate, reviewer → cmux-second-opinion)
3. Pass skill commands — worker skills handle their own context loading via §4.0

**Key rule: Do NOT write implementation code yourself. Do NOT perform reviews yourself. Always delegate to worker skills.**

### Phase 7: Final Quality Gate

After all tasks complete:

1. Run test commands from workflow (or language defaults)
2. Run lint/typecheck commands (if specified)
3. Verify all tasks in tasks.md are checked
4. If any check fails → fix via spec-code --feedback → recheck

### Phase 8: PR Creation

```bash
gh pr create \
  --title "{type}: {description} (closes #{N})" \
  --body "{PR body following workflow template}" \
  --base {base_branch}
```

**Safety guards:**
- Do NOT create PR if tests are failing
- Do NOT force push or push to main/master
- Verify base branch matches workflow

## Error Handling

| Situation | Response |
|---|---|
| Not a git repository | Error: must be in a git repository |
| `gh` CLI not available | Error: guide user to install/auth |
| `.specs/` not found | Warning: switch to Issue-only minimal mode |
| `requirement.md` missing | Warning: use Issue body as requirements |
| `tasks.md` missing | Warning: generate simple checklist from Issue |
| On protected branch | 🚨 BLOCKING: stop, require feature branch |
| Worker skill not installed | Error: suggest `npx skills add anyoneanderson/agent-skills --skill {name}` |
| Review FAIL after 3 iterations | Ask user to decide |
| Test FAIL after fix attempt | Ask user to decide |

## Post-Completion Actions

```
AskUserQuestion:
  question: "PR created. What's next?" / "PRを作成しました。次は？"
  options:
    - "Monitor CI status" / "CIステータスを監視"
    - "Done" / "完了"
```

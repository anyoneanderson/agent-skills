---
name: spec-implement
description: |
  Specification-driven implementation — Execute implementation from specs to PR.

  Reads issue-to-pr-workflow.md as playbook, enforces coding-rules.md as quality gates,
  tracks progress via tasks.md checkboxes with resume capability.

  English triggers: "Implement from spec", "Start implementation", "Execute spec tasks"
  日本語トリガー: 「仕様書から実装」「実装を開始」「specタスクを実行」
license: MIT
---

# spec-implement — Spec-Driven Implementation to PR

Execute implementation from specifications to pull request, following project-specific workflows and enforcing coding rules.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/implement-guide.ja.md`
3. English input → English output, use `references/implement-guide.md`
4. Explicit override takes priority (e.g., "in English", "日本語で")

## Critical First Steps

**BEFORE any implementation, execute these checks in order:**

1. **Verify environment**:
   - Run `pwd` to confirm working directory
   - Run `git status` to confirm inside a git repository
   - Run `gh auth status` to confirm GitHub CLI access

2. **Parse user input for options**:
   - `--resume` → resume from last uncompleted task
   - `--issue {N}` → specify GitHub Issue number
   - `--spec {path}` → specify `.specs/` directory path
   - `--dry-run` → show execution plan without making changes

3. **Locate spec directory**:
   - If `--spec` provided → use that path
   - If issue body contains `.specs/` path → use that
   - Otherwise → scan `.specs/` and ask user to select:
     ```
     AskUserQuestion:
       question: "Which spec to implement?" / "どの仕様書を実装しますか？"
       options: [list discovered .specs/ directories]
     ```

4. **Locate and read project files** (in this order):
   - `docs/issue-to-pr-workflow.md` → workflow playbook
   - `docs/coding-rules.md` → quality rules
   - `.specs/{feature}/requirement.md` → what to build
   - `.specs/{feature}/design.md` → how to build it
   - `.specs/{feature}/tasks.md` → task breakdown with checkboxes

## Execution Flow

### Phase 1: Workflow Loading

Read `docs/issue-to-pr-workflow.md` and interpret each section as instructions to follow:

| Workflow Section | Action |
|-----------------|--------|
| Development Environment | Extract setup commands, environment variables |
| Issue Analysis and Setup | Follow branch naming convention, issue reading steps |
| Phased Implementation | Follow implementation order and guidelines |
| Testing | Extract test commands and coverage thresholds |
| PR Creation and Quality Gates | Extract pre-PR checks and PR template |
| CI/CD Monitoring | Extract CI verification commands |

**Follow sections top-to-bottom.** Replace `{variable}` placeholders with actual values (issue number, branch name, etc.). Treat "MUST" and "required" keywords as mandatory; treat "optional" and "if applicable" as conditional.

**Fallback (no workflow file):**
If `docs/issue-to-pr-workflow.md` does not exist:
```
AskUserQuestion:
  question: "Workflow file not found. Generate it?" / "ワークフローファイルが見つかりません。生成しますか？"
  options:
    - "Run spec-workflow-init" / "spec-workflow-initを実行"
    - "Continue without workflow" / "ワークフローなしで続行"
```
If continuing without workflow, use minimal flow: Issue analysis → branch → implement → test → PR.

### Phase 2: Quality Rules Loading

Read `docs/coding-rules.md` and parse rule structure:

```
## {Category}
### [{Severity}] {Rule Name}
- {Rule detail}
```

Apply rules by severity:

| Severity | On Violation | Action |
|----------|-------------|--------|
| `[MUST]` | Error | Stop → fix → recheck before continuing |
| `[SHOULD]` | Warning | Log warning → continue |
| `[MAY]` | Info | Log info only |

**Check timing:**
- **Before task**: Review rules relevant to the task's category
- **During code generation**: Self-check against `[MUST]` rules
- **After task**: Verify completion criteria + rule compliance
- **Final gate**: Check all `[MUST]` rules across all changes

**Fallback (no rules file):**
If `docs/coding-rules.md` does not exist:
```
AskUserQuestion:
  question: "Coding rules not found. Generate them?" / "コーディングルールが見つかりません。生成しますか？"
  options:
    - "Run spec-rules-init" / "spec-rules-initを実行"
    - "Continue without rules" / "ルールなしで続行"
```
If continuing without rules, use CLAUDE.md or AGENTS.md as fallback reference if available.

### Phase 3: Issue Analysis

If `--issue {N}` is provided or an issue number is found in context:
```bash
gh issue view {N} --json title,body,labels,assignees
```

Extract from the issue:
- Feature overview and requirements
- Spec directory path (if referenced)
- Phase/task checklists
- Assignees and labels

### Phase 4: Branch Creation

Follow the workflow's branch naming convention. Default pattern:
```bash
git checkout main && git pull origin main
git checkout -b feature/issue-{N}-{brief-description}
```

If `--resume` is active and the branch already exists, switch to it instead.

### Phase 5: Spec-Driven Task Loop

Read specs in order: `requirement.md` → `design.md` → `tasks.md`

For each unchecked task in `tasks.md`:

```
1. Read task details (requirements ID, design reference, target files, completion criteria)
2. Reference the corresponding design.md section
3. Implement: create or modify target files
4. Verify each completion criterion
5. Check coding-rules.md [MUST] rules for generated code
6. Update tasks.md: mark completion criteria (- [ ] → - [x])
7. When all criteria pass: mark top-level task checkbox (- [x])
8. Commit progress:
   git add .specs/{feature}/tasks.md [+ implementation files]
   git commit -m "feat: {task-id} complete — {brief description}"
```

**Fallback (no specs, Issue only):**
If `.specs/` directory is missing or has no tasks.md:
- Use Issue body as the sole implementation guide
- Generate a simple task checklist from the Issue content
- Track progress against this generated checklist

### Phase 6: Final Quality Gate

After all tasks are complete:

1. Run test commands from the workflow (or `npm test` / language-appropriate default)
2. Run lint/typecheck commands from the workflow (if specified)
3. Verify all `[MUST]` rules from coding-rules.md pass
4. If any check fails → fix → recheck
5. All checks pass → proceed to PR creation

### Phase 7: PR Creation

Follow the workflow's PR template. Default structure:

```bash
gh pr create \
  --title "{type}: {description} (closes #{N})" \
  --body "{PR body following workflow template}" \
  --base main
```

**Safety guards:**
- Do NOT create PR if tests are failing
- Do NOT force push
- Do NOT push directly to main/master
- Ask for user confirmation before large-scale code deletions

After PR creation, monitor CI status if the workflow specifies CI verification commands.

## State Management and Resume

### Checkbox Tracking

Progress is tracked via tasks.md checkboxes:
- `- [ ]` → task pending
- `- [x]` → task completed
- Sub-checkboxes track individual completion criteria

### --resume Logic

When `--resume` is specified:

1. Read tasks.md and scan all top-level checkboxes
2. Find the first unchecked task (`- [ ]`)
3. Check its sub-criteria:
   - All unchecked → start task from beginning
   - Some checked → continue from first unchecked criterion
4. Execute remaining tasks in order
5. If all tasks are checked → proceed directly to final quality gate

### Intermediate Saves

After each task completion, commit tasks.md changes. This ensures:
- Progress survives agent interruptions
- `--resume` can accurately detect where to continue
- Git history shows incremental progress

## Options

| Option | Description |
|--------|-------------|
| `--resume` | Resume from last uncompleted task in tasks.md |
| `--issue {N}` | Specify GitHub Issue number for context |
| `--spec {path}` | Specify .specs/ directory path (default: auto-detect) |
| `--dry-run` | Show execution plan without making any changes |

## Error Handling

| Situation | Response |
|-----------|----------|
| Not a git repository | Error: "Must be in a git repository" / "gitリポジトリ内で実行してください" |
| `gh` CLI not available | Error: guide user to install/authenticate gh CLI |
| `.specs/` not found | Warning: switch to Issue-only minimal mode |
| `requirement.md` missing | Warning: use Issue body as requirements source |
| `tasks.md` missing | Warning: generate simple checklist from Issue |
| `[MUST]` rule violation | Error: stop, fix, recheck before continuing |
| Tests failing before PR | Block PR creation, report failures |
| Branch already exists | Ask: switch to it or create new |

## Usage Examples

```
# Full implementation from spec
"Implement from spec for auth-feature"
「auth-featureの仕様書から実装して」

# With issue number
"Implement spec --issue 42"
「Issue #42の仕様を実装して」

# Resume after interruption
"Resume implementation --resume --spec .specs/auth-feature/"
「実装を再開 --resume」

# Dry run to preview plan
"Show implementation plan --dry-run --spec .specs/auth-feature/"
「実装計画を表示 --dry-run」

# Minimal mode (no specs)
"Implement issue 42"
「Issue 42を実装して」
```

## Post-Completion Actions

After PR is created:

```
AskUserQuestion:
  question: "PR created. What's next?" / "PRを作成しました。次は？"
  options:
    - "Monitor CI status" / "CIステータスを監視"
    - "Review the PR diff" / "PR差分を確認"
    - "Done" / "完了"
```

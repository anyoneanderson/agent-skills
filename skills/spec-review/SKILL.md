---
name: spec-review
description: |
  Structured code review against review_rules.md and coding-rules.md.

  Performs rule-by-rule, file-by-file matrix review of code changes.
  Outputs findings to a structured review file for use by spec-code --feedback.
  Works standalone for manual reviews or as part of spec-implement pipeline.

  English triggers: "Review code", "Run spec-review", "Check against rules"
  日本語トリガー: 「コードレビュー」「spec-reviewを実行」「ルールに照合」
license: MIT
---

# spec-review — Structured Code Review

Review code changes against project rules using a systematic rule × file matrix approach.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/review-guide.ja.md`
3. English input → English output, use `references/review-guide.md`
4. Explicit override takes priority

## Options

| Option | Description |
|--------|-------------|
| `--task {task-id}` | Review changes for a specific task (auto-detect diff) |
| `--diff {file}` | Review a specific diff file (standalone use) |
| `--spec {path}` | Path to .specs/ directory (for design consistency check) |
| `--rules {path}` | Path to review_rules.md (auto-search if omitted) |
| `--output {path}` | Output path for review file (default: `.specs/{feature}/review-{task-id}.md`) |

## Execution Flow

### Step 0: Context Loading (Phase A / Phase B)

Same as spec-code §Step 0, but identify your role as **reviewer**.

Phase B applies when re-reviewing after a fix: load only the updated diff and previous review findings.

### Step 1: Collect Rules

1. **Locate review_rules.md** (search: `docs/development/` → `docs/` → find)
2. **Locate coding-rules.md** (same search order)
3. Parse all rules into a structured list:

```
rule_list: [
  { id: "RR-001", severity: "Critical", description: "No SQL injection", category: "security" },
  { id: "CR-MUST-001", severity: "MUST", description: "Use strict TypeScript", category: "typescript" },
  ...
]
```

If no rules files found, use minimal defaults: security (no secrets, no injection), correctness (no obvious bugs), and style (consistent formatting).

### Step 2: Collect Changed Files

**Diff acquisition based on context:**

| Context | Diff Command |
|---|---|
| `--task {id}` specified | `git diff {task-start-commit}...HEAD` (commit before task implementation) |
| `--diff {file}` specified | Read the provided diff file directly |
| Standalone (no options) | `git diff --cached` first; if empty, `git diff` (working tree) |
| PR context | `git diff {base}...HEAD` |

Parse the diff to extract:
```
changed_files: [
  { path: "src/auth/service.ts", added_lines: [45-60, 102-110], removed_lines: [48-52] },
  ...
]
```

If diff is empty → stop with: "No changes to review." / "レビュー対象の変更がありません。"

### Step 3: Matrix Review (Rule × File)

**This is the core review step. Do NOT skip or abbreviate.**

```
for each rule in rule_list:
  for each file in changed_files:
    if rule.category is relevant to this file type:
      read the changed lines in context
      check if any added/modified line violates this rule
      if violation found:
        record: { rule.id, file.path, line_number, description, severity }
```

**Relevance matching:**
- Security rules → all files
- TypeScript rules → `.ts`, `.tsx` files
- Test rules → `*.test.*`, `*.spec.*` files
- Style rules → all source files
- API rules → controller/route files

### Step 4: Design Consistency Check

If `--spec` is provided:
1. Read `design.md` section referenced by the task
2. Compare implementation against design:
   - Are the specified interfaces implemented?
   - Does the data model match?
   - Are the architecture decisions followed?
3. Record any deviations as "Improvement" severity

### Step 5: Write Review File

Output to `--output` path (default: `.specs/{feature}/review-{task-id}.md`):

```markdown
# Review: {task-id}
type: review

## Meta
- Reviewer: spec-review
- Date: {ISO 8601}
- Iteration: {n}
- Rules checked: {count} rules across {count} files
- Diff basis: {diff command used}

## Findings

### Critical
- [ ] **{rule-id}** `{file}:{line}` — {what violates and why}

### Improvement
- [ ] **{rule-id}** `{file}:{line}` — {suggestion and reasoning}

### Minor
- {rule-id} `{file}:{line}` — {note}

## Summary
- Critical: {n} | Improvement: {n} | Minor: {n}
- Gate: PASS / FAIL
```

**Gate logic:**
- Any Critical finding → FAIL
- Only Improvement/Minor → PASS (with warnings)
- No findings → PASS

## Error Handling

| Situation | Response |
|---|---|
| No diff available | Error: no changes to review |
| No rules files found | Warning: use minimal defaults, proceed |
| `--spec` provided but design.md missing | Warning: skip design consistency check |
| `--output` directory doesn't exist | Create the directory |

## Usage Examples

```
# Review a specific task's changes
/spec-review --task T-007 --spec .specs/did-deactivation/

# Standalone review of current staged changes
/spec-review

# Review a PR diff
/spec-review --diff pr-diff.patch --rules docs/review_rules.md

# Review with custom output
/spec-review --task T-003 --output /tmp/review-T-003.md
```

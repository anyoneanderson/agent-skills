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
| `--base-commit {sha}` | Base commit for task-scoped diff (recommended with `--task`) |
| `--diff {file}` | Review a specific diff file (standalone use) |
| `--spec {path}` | Path to .specs/ directory (for design consistency check) |
| `--rules {path}` | Path to review_rules.md (auto-search if omitted) |
| `--output {path}` | Output path for review file (default: `.specs/{feature}/review-{task-id}.md`) |

## Execution Flow

### Step 0: Context Loading (Phase A / Phase B)

Same as spec-code §Step 0, but identify your role as **reviewer**.

Phase B applies when re-reviewing after a fix: load only the updated diff and
previous review findings. On a re-review, read only the unresolved findings,
the parts changed by the fixes, and the code that directly uses those parts —
do not re-scan the whole diff hunting for fresh ground. Do not re-raise
findings already recorded with `fix_before: trial` / `required_check` /
`follow_up`; the caller carries them forward. A **new** finding unrelated to
the fixes may be tagged `implementation` only for secret leak, data loss, a
bypass of a merge condition, or an infeasibility; any other new finding is
`follow_up`.

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
| `--task {id}` + `--base-commit {sha}` | `git diff {sha}...HEAD` |
| `--task {id}` only | Auto-detect task start commit; if ambiguous, require `--base-commit` |
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

### Step 4.5: Tag Each Finding with `fix_before`

Severity (Critical / Improvement / Minor) is for human reading and
prioritization. The Gate is decided by a second axis, `fix_before` — the
milestone before which the defect must be fixed. Tag every Critical and
Improvement finding with one of, in milestone order:

- **implementation** — must be fixed before this work lands: infeasible as
  written, or breaks for its users the moment it is used.
- **trial** — must be fixed before the change is exercised in trial operation;
  does not block landing.
- **required_check** — must be fixed before the change becomes an enforced
  gate or a dependency others rely on.
- **follow_up** — worth fixing in a follow-up issue.

Rules of evidence:

- **The default is `follow_up`. The burden of proof is on escalation.**
- To tag `implementation`, the finding description MUST state both:
  (1) who triggers it, by what operation, and what breaks; and
  (2) from which milestone on that failure first becomes possible.
  If (2) cannot be stated, tag the earliest milestone that can be defended.
- Exception: a defect that makes the change not work at all as written
  (infeasible) is always `implementation`.
- Minor findings take no `fix_before` tag (implicitly `follow_up`).
- Do not add any further gating axis (no `blocking:` flag or similar); whether
  the Gate stops is derived from `fix_before` alone.

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
- [ ] **{rule-id}** `{file}:{line}` — fix_before: {implementation|trial|required_check|follow_up} — {what violates and why}

### Improvement
- [ ] **{rule-id}** `{file}:{line}` — fix_before: {implementation|trial|required_check|follow_up} — {suggestion and reasoning}

### Minor
- {rule-id} `{file}:{line}` — {note}

## Summary
- Critical: {n} | Improvement: {n} | Minor: {n}
- Fix before implementation: {n}
- Gate: PASS / FAIL
```

**Gate logic** (mechanical, from `fix_before` alone — severity does not enter
the decision):
- Any finding tagged `fix_before: implementation` → FAIL
- Otherwise (only trial / required_check / follow_up / Minor, or no findings)
  → PASS (deferred findings are recorded and carried forward, never silently
  dropped)

## Error Handling

| Situation | Response |
|---|---|
| No diff available | Error: no changes to review |
| `--task` without resolvable base commit | Error: ask for `--base-commit {sha}` |
| No rules files found | Warning: use minimal defaults, proceed |
| `--spec` provided but design.md missing | Warning: skip design consistency check |
| `--output` directory doesn't exist | Create the directory |

## Usage Examples

```
# Review a specific task's changes
/spec-review --task T-007 --base-commit abc1234 --spec .specs/did-deactivation/

# Standalone review of current staged changes
/spec-review

# Review a PR diff
/spec-review --diff pr-diff.patch --rules docs/review_rules.md

# Review with custom output
/spec-review --task T-003 --output /tmp/review-T-003.md
```

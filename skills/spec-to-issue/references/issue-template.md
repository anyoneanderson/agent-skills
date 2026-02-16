# Issue Template & Extraction Rules

## Issue Body Template

Compose the issue body following this template.
Replace `{...}` with values extracted from spec files. Omit entire sections if the source section doesn't exist.

```markdown
## Overview

**Warning: Read the spec documents thoroughly before starting implementation.**

{Overview section from requirement.md}

## Spec Documents

See `.specs/{FEATURE_DIR}/` directory

- [Requirements Document](../blob/{BRANCH}/.specs/{FEATURE_DIR}/requirement.md)
- [Design Document](../blob/{BRANCH}/.specs/{FEATURE_DIR}/design.md)
- [Task List](../blob/{BRANCH}/.specs/{FEATURE_DIR}/tasks.md)

## Key Features

{Extract major features as bullet list from requirement.md}
- Feature 1
- Feature 2
- Feature 3

## Implementation Checklist

{Group by phase from tasks.md}

### Phase 1: {Phase Name} ({Duration})
- [ ] Task 1
- [ ] Task 2

### Phase 2: {Phase Name} ({Duration})
- [ ] Task 1
- [ ] Task 2

## Technology Stack

{Extract from tech requirements in requirement.md}
- Tech 1
- Tech 2

## Definition of Done

{Extract from "Definition of Done" in tasks.md. Use defaults if not found}
- [ ] All required features are implemented
- [ ] Tests are passing
- [ ] Code review is complete

## Notes

{Extract from "Notes" in tasks.md. Omit if not found}
```

## Issue Title

```
[Feature] {FEATURE_NAME}
```

Determining `FEATURE_NAME`:
1. Extract from the first `# ` line in requirement.md
2. Strip suffixes: `要件定義書`, `要件定義`, `仕様書`, `Requirements`, `Specification`, `Spec`, `Requirements Document`
3. Trim leading/trailing whitespace

Examples:
- `# Member Management Requirements Document` → `[Feature] Member Management`
- `# メンバー管理機能 要件定義書` → `[Feature] メンバー管理機能`
- `# Authentication System Requirements` → `[Feature] Authentication System`

## Extraction Rules

### Title Extraction

Get the first line starting with `# ` in requirement.md and strip these patterns:
- `要件定義書`, `要件定義`, `仕様書`
- `Requirements`, `Requirements Document`, `Specification`, `Spec`

### Overview Extraction

From requirement.md, get content between `## Overview` or `## 概要` and the next `## `.
Exclude the heading line itself.

### Key Features Extraction

Collect lines from requirement.md matching these patterns:
- `### 1.`, `### 2.` ... (numbered sections) → convert section name to bullet item
- `### Feature Name` style sections → convert to bullet item

Example: `### 1. Member List Screen` → `- Member List Screen`

### Phase & Task Extraction

Parse tasks.md for this structure:

```
## Phase 1: Foundation (1-2 days)    ← Phase heading
### 1.1 Create Type Definitions      ← Task heading (becomes checklist item)
- [ ] Subtask 1                      ← Ignored (too granular)
```

Extraction method:
- Lines starting with `## Phase` or `## フェーズ` → phase headings
- `### ` lines within a phase → checklist items `- [ ] {task name}`
- `- [ ]` subtasks are NOT included (prevents issue body bloat)

### Tech Stack Extraction

Search requirement.md for these sections (in priority order):
1. `## Technology Stack`
2. `## Technical Requirements`
3. `## 技術要件`
4. `## 技術スタック`

Use bullet items from the section as-is.

### Done Criteria Extraction

Search tasks.md for `## Definition of Done` or `## 完了の定義` section.
If not found, use defaults:

```markdown
- [ ] All required features are implemented
- [ ] Tests are passing
- [ ] Code review is complete
```

### Notes Extraction

Search tasks.md for `## Notes` or `## 注意事項` section.
Omit this section entirely if not found.

## gh issue create Command

```bash
gh issue create \
  --title "[Feature] {FEATURE_NAME}" \
  --body "$(cat <<'EOF'
{Composed issue body}
EOF
)" \
  ${LABELS:+--label "$LABELS"} \
  ${ASSIGNEE:+--assignee "$ASSIGNEE"}
```

With labels: `--label "feature,spec-generated"`
With assignee: `--assignee "username"`

## Adding to Project

After issue creation, if `--project` is specified:

```bash
gh project item-add {PROJECT_NUMBER} --owner {ORG} --url {ISSUE_URL}
```

`{ORG}` is obtained via `gh repo view --json owner -q '.owner.login'`.

## Spec Link Branch

Links to spec files use this format:
```
../blob/{BRANCH}/.specs/{FEATURE_DIR}/requirement.md
```

`{BRANCH}` resolution order:
1. `--branch` argument
2. `.specs/.config.yml` `default-branch`
3. CLAUDE.md Git workflow settings
4. Default: `main`

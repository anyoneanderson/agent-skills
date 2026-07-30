---
name: spec-to-issue
description: |
  Create GitHub Issue from spec documents — Auto-generate structured Feature Issues from specifications.

  Analyzes spec documents (requirement.md, design.md, tasks.md) in .specs/{feature}/ and
  generates a structured Feature Issue via gh issue create.
  Best used with specs created by spec-generator.

  English triggers:
  - "Create issue from spec", "Register spec as issue"
  - "Convert spec to GitHub issue", "Publish spec to issue"
  - After spec-generator: "Turn this into an issue"

  日本語トリガー:
  - 「仕様書をIssueにして」「Issueに登録して」「specからIssue作成」
  - 「仕様書からIssue生成」「specをIssueに変換」
  - spec-generator完了後に「これをIssueにして」「Issueにして」
license: MIT
---

# spec-to-issue — Spec to GitHub Issue

Auto-generate GitHub Issues from spec directories (`.specs/{feature}/`).

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese issue, use `references/issue-template.ja.md` as template reference
3. English input → English issue, use `references/issue-template.md` as template reference
4. Explicit override takes priority

**Reference file selection**: Based on the detected output language, use the corresponding template:
- English → `references/issue-template.md`
- Japanese → `references/issue-template.ja.md`

## Execution Flow

### 1. Locate Spec Directory

**With argument**: `spec-to-issue auth-feature` → use `.specs/auth-feature/`

**Without argument**: Scan `.specs/` and present a list → ask user to select

```
Spec directories found in .specs/:
1. auth-feature (requirement.md, design.md, tasks.md)
2. member-management (requirement.md, tasks.md)
Which spec do you want to create an issue from?
```

### 2. File Validation

Required: `requirement.md` must exist. Otherwise, exit with error.
Recommended: `design.md` and `tasks.md`.
If either is missing, continue only when the remaining documents still define
concrete scope and acceptance criteria; report the missing source before issue
creation.

### 3. Spec Analysis

Treat the spec files as candidate sources, not as sections to copy.
Extract and select:

**requirement.md:**
- Title: First `# ` line, strip suffixes like "Requirements", "要件定義書"
- The problem and observable completed state
- Current and expected behavior
- Included and excluded scope
- Requirement-level acceptance criteria

**design.md:**
- Decisions constrained by compatibility, security, external contracts, or
  another requirement, including the reason
- Open questions that the implementer cannot safely decide alone

**tasks.md:**
- Supporting implementation detail and additional completion evidence
- Do not copy phase headings, task headings, estimates, or technology lists by
  default

Keep a candidate only when removing it would change an implementation decision
or completion judgment. See the selected language's issue-template reference
for the complete selection procedure.

### 4. Resolve Project Settings

Determine defaults in this priority order:

```
Command arguments > .specs/.config.yml > CLAUDE.md > Built-in defaults
```

**From CLAUDE.md:**
- Branch name: PR target branch from Git Workflow section → `--branch` default
- GitHub Organization: Inferred from repository URL

**.specs/.config.yml (optional):**
```yaml
default-branch: develop
default-labels: [feature, spec-generated]
project-number: 7
assignee: username
```

### 5. Resolve the Project Template and Compose the Issue Body

Inspect the repository's Issue forms, Issue templates, contribution rules, and
required fields before composing the body. A project template takes priority:
preserve its headings, order, fields, and checkboxes, and map the selected
information into it.

See template details in the appropriate reference file (based on Language Rules):
- English: [references/issue-template.md](references/issue-template.md)
- Japanese: [references/issue-template.ja.md](references/issue-template.ja.md)

Without a project template, compose an execution contract that identifies the
problem, completed state, current and expected behavior, included and excluded
scope, acceptance criteria, binding decisions, and open questions. Link to the
spec files for task decomposition and supporting detail.

### 6. Create Issue

**Without --preview (default)**: Show a brief summary and execute `gh issue create`

```
Creating Issue:
  Title: [Feature] Member Management
  Labels: feature, spec-generated
  Outcome: Members can be invited and assigned a repository role
  Acceptance criteria: 4
→ Running gh issue create...
Issue #42 created: https://github.com/org/repo/issues/42
```

**With --preview**: Display the full issue body, confirm, then execute

### 7. Additional Actions (optional)

- `--label`: Apply specified labels
- `--project`: Add to GitHub Project board via `gh project item-add`
- `--assignee`: Set assignee

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--preview` | Display issue body for confirmation | OFF |
| `--label <labels>` | Comma-separated labels | `.config.yml` value or none |
| `--project <number>` | Add to GitHub Project | `.config.yml` value or none |
| `--branch <name>` | Base branch for spec links | CLAUDE.md or `main` |
| `--assignee <user>` | Set assignee | `.config.yml` value or none |

## Integration with spec-generator

After spec-generator's `full` phase completes, suggest:

```
All three spec documents have been generated.
→ Create a GitHub Issue from them? (Y/n)
```

If yes, run spec-to-issue on the same directory.

## Error Handling

| Situation | Response |
|-----------|----------|
| `.specs/` does not exist | Error: Spec directory not found |
| `requirement.md` missing | Error: requirement.md is required |
| `design.md` or `tasks.md` missing | Continue only if concrete scope and acceptance criteria remain; otherwise stop and report the missing source |
| `gh` CLI not authenticated | Error: Guide user to `gh auth login` |
| Concrete acceptance criteria missing | Stop before issue creation; do not invent generic completion checks |
| Project template found | Preserve its required headings and fields instead of appending the built-in template |

## Usage Examples

```
# With argument
/spec-to-issue auth-feature

# Auto-detect and select
/spec-to-issue

# With preview
/spec-to-issue auth-feature --preview

# With labels and Project
/spec-to-issue auth-feature --label "feature,priority:high" --project 7

# After spec-generator
"Create full spec for todo-app" → done → "Turn this into an issue"

# Japanese
「仕様書を全部作って」→ 完了 →「これをIssueにして」
```

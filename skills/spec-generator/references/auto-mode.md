# Auto Mode — Non-Interactive Generation from a GitHub Issue

## Overview

Auto mode generates the full spec set (requirement.md, design.md, tasks.md) plus
test.md from a GitHub Issue **without any dialogue**. It is the non-interactive
counterpart to the standard full workflow: instead of asking the user questions,
it reads the Issue as the requirement source and records every unresolved
ambiguity as an assumption.

Invocation: `--auto --issue <n>` (optionally `--repo <owner/name>` when the
Issue lives in another repository).

**Hard rule**: In auto mode, do **not** call AskUserQuestion at any point.
There is no human in the loop. Ambiguity is resolved by writing an assumption
(`ASM-XXX`), not by asking.

## Execution Steps

### 1. Fetch the Issue

Retrieve the Issue title, body, and labels with the GitHub CLI:

```bash
gh issue view <n> --json number,title,body,labels
```

If a target repository is specified, add `--repo <owner/name>`.

Error handling:
- If `gh` is not authenticated or the Issue does not exist, stop and report the
  failure (do not fabricate content). Surface the account-check steps from the
  project's git/GitHub account guidance.

### 2. Derive the feature name

Generate the `.specs/{feature}/` directory name from the **Issue title**,
converted to English kebab-case:

- "Add CSV export to reports" → `add-csv-export-to-reports`
- "ユーザー認証を追加" → translate the intent, then kebab-case → `user-authentication`
- Strip issue-tracker noise (leading `[Feature]`, emoji, trailing punctuation).

Keep the name short and descriptive. If the title is empty, fall back to
`issue-{n}`.

### 3. Generate the four documents

Run the full workflow's generation logic against the Issue body as the
requirement source, in order: requirement.md → design.md → tasks.md → test.md.
Reuse the same reference files as the interactive path
(`init.md`, `design.md`, `tasks.md`, `test-plan.md` and their `.ja` variants).

After all four documents are generated, run
`references/projection-consistency.md` (`.ja.md` for Japanese output). Run it
again after every revision, and do not report completion until the pass succeeds.

Apply the **YAGNI principle** (see SKILL.md): build only what the Issue asks
for. Do not add auth, analytics, i18n, or infrastructure that the Issue does not
mention.

### 4. Record ambiguity as assumptions (the substitute for questions)

Every point where the interactive path would call AskUserQuestion becomes an
**assumption** instead. Write each one under `## 5. Assumptions` in
requirement.md with an `ASM-XXX` ID and a one-line rationale:

```markdown
## 5. Assumptions
[ASM-001] Tech stack: the Issue does not specify a framework; assuming the
repository's existing stack (detected: Next.js + PostgreSQL).
[ASM-002] Scope: "export" is assumed to mean CSV only; other formats are out of
scope until requested.
```

Rules:
- Do not silently pick a default — every inferred decision gets an explicit
  `ASM`. This keeps the reviewer able to see (and override) each guess.
- Prefer the repository's existing conventions when inferring tech choices
  (detect from the codebase rather than assuming a generic default).
- If the Issue is too vague to produce a coherent spec, still generate the four
  files and make the vagueness visible as assumptions; do not block on a
  question (see ASM-002 of the spec: auto mode assumes a sufficiently concrete
  Issue).

### 5. Output

```
.specs/{feature}/
├── requirement.md
├── design.md
├── tasks.md
└── test.md
```

Language follows the Issue's language (Japanese Issue → Japanese documents),
per the SKILL.md Language Rules.

## Post-Completion

Auto mode does **not** prompt for a next action. It reports the generated file
paths and the list of assumptions written, then returns control to the caller
(e.g., an orchestrator continuing the pipeline).

## Checklist

1. [ ] No AskUserQuestion was called
2. [ ] All four files generated (requirement.md, design.md, tasks.md, test.md)
3. [ ] Feature name is kebab-case, derived from the Issue title
4. [ ] Every inferred decision is recorded as an `ASM-XXX` in requirement.md
5. [ ] Output language matches the Issue language
6. [ ] Projection consistency pass completed after generation or revision

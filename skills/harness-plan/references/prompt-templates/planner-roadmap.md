<!--
  Planner `roadmap` phase prompt template.
  harness-plan Orchestrator substitutes:
    {{EPIC_NAME}}            — slug for the epic
  Purpose: read product-spec.md, write roadmap.md. Fresh Planner — no
  memory of the interview session.
-->

You are the "planner" agent (see `.claude/agents/planner.md` / `.codex/agents/planner.toml`).
Load and follow its developer_instructions.

# Phase: roadmap

Goal: produce `.harness/{{EPIC_NAME}}/roadmap.md` from the already-written product-spec.md.

Boot Sequence first (git log, progress.md tail, _state.json).

## Input

Read `.harness/{{EPIC_NAME}}/product-spec.md`. That is your ONLY source
of intent — you were not in the interview session.

## Your task

Split the epic into sprints. For each sprint, decide `bundling: split | bundled`:

- **split** (1 feature = 1 sprint = 1 PR): the default
- **bundled** (N features = 1 sprint = 1 PR): only when features share
  schema / auth / UI components so tightly that shipping them
  separately would require double-wiring the same seams

Write `.harness/{{EPIC_NAME}}/roadmap.md`:

```markdown
---
epic: {{EPIC_NAME}}
generated_at: <ISO-8601-UTC>
approved: false
---

# Roadmap: {{EPIC_NAME}}

## Sprints

| # | Feature | Bundling | Bundled-with | Goal |
|---|---|---|---|---|
| 1 | login | split | — | email+password 認証 |
| 2 | lockout | split | — | ブルートフォース対策 |
| 3 | mfa | bundled | email-verification | MFA + メール確認 |
| 4 | email-verification | bundled | mfa | |

## Bundling rationale

- sprint-3 & 4: both touch the same SMTP pipeline + verification-token
  middleware; splitting would fork the token schema migration twice.

## Ordering rationale

- login before lockout (lockout depends on account entity existing)
- MFA after login+lockout (builds on their primitives)
```

Then exit. The user will approve / reject out-of-band; you do NOT
run AskUserQuestion in this phase (you're not interactive).

## Constraints

- Do NOT write code
- Do NOT draft any contract files (separate Planner invocations for that)
- Do NOT re-interview — if product-spec.md is ambiguous, note it in the
  "Bundling rationale" section and make the most conservative
  interpretation

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

## Foundation-sprint check

Read `_state.json.foundation_sprint_needed`. If `true`, the epic is
greenfield and Step 3.5 of /harness-plan already wrote
`.harness/{{EPIC_NAME}}/foundation-readiness.md`.

In that case you MUST insert a **Sprint 0** with `type: foundation` at
the head of the roadmap, with `deliverables` derived from the missing
probes in foundation-readiness.md. See
[../foundation-sprint-guide.md](../foundation-sprint-guide.md) for
the full schema. Also:

- Implicitly add `dependencies: [0]` to every feature sprint that does
  not already declare explicit dependencies (the rewrite is mandatory
  so harness-loop blocks feature sprints until Sprint 0 is attested)
- Sprint 0 does NOT count toward the 6-sprint epic cap
- Sprint 0 cannot be bundled — it is always its own PR

If `foundation_sprint_needed` is `false` or absent, proceed as usual
without a Sprint 0.

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

| # | Feature | Bundling | Bundled-with | Goal | Backend |
|---|---|---|---|---|---|
| 1 | login | split | — | email+password 認証 | claude |
| 2 | lockout | split | — | ブルートフォース対策 | codex_cli |
| 3 | mfa | bundled | email-verification | MFA + メール確認 | codex_cli |
| 4 | email-verification | bundled | mfa | | codex_cli |

## Bundling rationale

- sprint-3 & 4: both touch the same SMTP pipeline + verification-token
  middleware; splitting would fork the token schema migration twice.

## Ordering rationale

- login before lockout (lockout depends on account entity existing)
- MFA after login+lockout (builds on their primitives)

## Backend rationale

- sprint-1 (login): UI / form / 認証画面 → primary `claude` (rubric: UI-heavy)
- sprint-2 (lockout): backend rate-limit logic → primary `codex_cli` (rubric: backend logic)
- sprint-3 / 4 (bundle): backend / schema / auth heavy → primary `codex_cli`
  shared by bundle peers (primary peer のみ rubric 適用、peer は継承)

The same backend choices are also written into the YAML frontmatter under
`sprints[n].generator_backend` (canonical source for harness-loop). The
table above is a human-readable summary.
```

## Backend Recommendation per sprint

For every sprint, decide the Generator backend. See
[../roadmap-guide.md](../roadmap-guide.md) §Backend Recommendation for the
full rubric and flow. Summary:

1. **Apply the suitability rubric** to each sprint feature:
   - UI-heavy (frontend / component / CSS / design system) → primary `claude`
   - backend logic / API / schema / auth / validation → primary `codex_cli`
     (for design-heavy backend sprints, surface `claude` as a secondary
     option in the AskUserQuestion list — primary stays `codex_cli`)
   - infra / CI/CD / docker / shell / cloud deploy → primary `codex_cli`

   The primary recommended value is **single** (`claude` or `codex_cli`)
   — never emit `codex_cli (or claude)`. `codex_cmux` is **not** a
   rubric primary; it is always included in the AskUserQuestion options
   so the user can select it for hybrid (UI + backend equally weighted)
   or cross-check cases.

2. **Interactive mode** (`_state.json.mode == "interactive"`): for each
   sprint, call `AskUserQuestion` with:
   - option 1: `<recommended> (Recommended) — <rubric reason>`
   - option 2: `<_config.yml.generator_backend>` (epic default selected
     at harness-init; skip if same as recommended)
   - option 3: any remaining enum value (deduplicated)

   Bundle peers share the primary peer's choice — ask **once per bundle**,
   not per peer. When sprints > 4, split into multiple rounds (AskUserQuestion
   limit is 4 questions per round).

3. **Non-interactive mode** (`continuous` / `autonomous-ralph` /
   `scheduled`): `AskUserQuestion` is forbidden by Pre-flight Gates.
   Auto-confirm the rubric primary and write it directly to `roadmap.md`.

4. **Legacy bypass**: when `_config.yml.sprint_level_generator_override == false`,
   **skip both rubric judgement and AskUserQuestion entirely**. Write
   `generator_backend: null` for every sprint so that `harness-loop` falls
   back to `_config.yml.generator_backend` at runtime (current behaviour
   preserved for backward compatibility).

Write the confirmed value (or `null` for legacy) into the `roadmap.md`
YAML frontmatter under `sprints[n].generator_backend`, alongside a
free-form `generator_backend_reason` recording the rationale (rubric
recommended adopted / epic default adopted / manual override / legacy bypass).

Then exit. The user will approve / reject the overall roadmap out-of-band;
the per-sprint backend confirmation done above is the only AskUserQuestion
you run during this phase (interactive mode only).

## Constraints

- Do NOT write code
- Do NOT draft any contract files (separate Planner invocations for that)
- Do NOT re-interview — if product-spec.md is ambiguous, note it in the
  "Bundling rationale" section and make the most conservative
  interpretation

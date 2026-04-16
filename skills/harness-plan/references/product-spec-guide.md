# Product Spec Interview Guide

This guide drives the `harness-plan` interactive flow that fills
`.harness/<epic>/product-spec.md` section by section. It is authored for the
Planner sub-agent (not the user). Its two goals:

1. Collect the **minimum** information the Planner needs to derive a roadmap.
2. **Prevent "How" leakage** — the spec must describe value and constraints,
   never implementation choices.

The template is at `.harness/templates/product-spec.md` (copied there by
`harness-init`). Sections are filled in this order: Why → What → Out of Scope
→ Constraints → Success Signals.

## Core Principle — "What, not How"

The spec answers **what the user experiences** and **why it matters**. It
must not pick:

- Frameworks or libraries (React, Django, Prisma, Tailwind, …)
- Storage engines, schema shapes, table names
- File paths, module names, class names
- Protocols (REST vs GraphQL), auth methods (JWT vs session cookie)
- Deployment targets (Vercel, AWS, on-prem)

If the user volunteers one of these, the Planner redirects: "Is that a hard
constraint from outside (legal, existing system, org mandate)? If yes, move
it to **Constraints**. If no, drop it — the Implementation Loop will pick."

## Section-by-section Prompts

### Why (1–3 sentences)

Ask:
- "If we ship nothing, what stays broken or out of reach?"
- "Whose pain is this solving, and how do we notice it today?"
- "What changes after this epic lands, measured from outside the code?"

**Reject** outputs that describe activity ("we'll add a login page") — rewrite
to outcome ("users can return to a saved cart without re-entering email").

### What (bulleted capabilities)

Ask:
- "What can a user / external system do after this ships that they can't now?"
- "Walk me through the shortest successful path end-to-end."
- "What does the user see right before success? What do they see on failure?"

**Reject** UI-component enumerations ("a modal with two fields") — rewrite to
capability ("user can reset a forgotten password without a support ticket").

Bullet count target: 3–7. Fewer invites ambiguity; more suggests the epic
needs splitting.

### Out of Scope (explicit exclusions)

Ask:
- "What related work might someone assume is included, but isn't?"
- "What is tempting to add but would delay delivery?"
- "What belongs to a different epic or a future quarter?"

This section is the Planner's shield against scope creep during sprint
decomposition. A missing exclusion becomes an unplanned sprint.

### Constraints (external mandates only)

Ask:
- "Are there compliance, legal, or security requirements we must satisfy?"
- "Are there existing systems we must integrate with or replace?"
- "Is there a hard date, budget, or team-size limit?"
- "Is there a technology choice the org has already mandated for this area?"

**Not constraints**: preferences, taste, "I like X". Those belong in the
agent's Implementation Loop, not the spec. Push back: "Is there a document,
ticket, or stakeholder we can cite for this?"

### Success Signals (optional, outcome metrics)

Ask:
- "How will we know in production that this is working?"
- "What number or event would tell us this epic failed even if the code shipped?"

Prefer **outcome** metrics (e.g., "95% of new users complete signup in under
30 seconds") over **output** metrics ("3 PRs merged"). Outcome signals feed
into per-sprint rubric thresholds.

Allow this section to be empty — but mark the product-spec as
`success_signals: unspecified` in the frontmatter if so, so the Planner
weights rubrics conservatively (all thresholds ≥ 0.7).

## Anti-patterns to Reject

| Symptom | Example | Redirect |
|---|---|---|
| Implementation leakage | "Use Postgres with a `users` table" | Drop, or move to Constraints only if externally mandated |
| UI enumeration | "A blue button labelled 'Sign Up'" | Rewrite to capability ("new visitor can create an account") |
| Output metric | "Ship 5 PRs this sprint" | Rewrite to outcome ("95% of signups complete in 30s") |
| Vague scope | "Improve onboarding" | Ask for the shortest successful user path |
| Mixed epics | "Login + billing + email templates" | Split into separate product-specs |
| Negation-only What | "Users won't be locked out anymore" | Rewrite positively ("users recover access in < 60s") |

## Cross-check Checklist (Planner runs before declaring spec complete)

Before writing the roadmap, the Planner asks itself:

1. Does **Why** state a concrete problem, not an activity?
2. Does **What** name at least one observable user outcome per bullet?
3. Can I imagine an acceptance scenario for **each What bullet** without
   inventing new information?
4. Does **Out of Scope** list the 2–3 most-likely scope-creep temptations
   for this domain?
5. Do **Constraints** all cite an external source (law, existing system,
   mandate)? No pure preferences?
6. If **Success Signals** is empty, is that a deliberate choice (mark
   `unspecified`) or an interview gap to fill?
7. Is each section **self-contained**? Could I hand this to a fresh Planner
   and expect the same roadmap?

If any answer is "no", the Planner re-opens that section with the user via
`AskUserQuestion` (interactive mode only). In non-interactive modes, the
Planner writes a `TODO(product-spec):` line into `.harness/progress.md` and
proceeds with the best interpretation, flagging the gap for human review
before sprint 1 begins.

## Output Contract

The final `product-spec.md`:

- Is placed at `.harness/<epic-name>/product-spec.md`
- Matches the template structure from `.harness/templates/product-spec.md`
- Has **no HTML comment blocks** (they were scaffolding for authoring)
- Is committed to git as part of the `harness-plan` flow (checkpoint
  commit, even though we're pre-sprint)
- Is the single source of truth the Planner reads when generating
  `roadmap.md` in the next step

## Recovery

If `harness-plan` is interrupted mid-interview:

- Partial answers already written to `product-spec.md` are preserved
- `_state.json.phase` remains `product-spec-draft`
- On resume (Boot Sequence), Planner reads the current file, identifies
  empty sections by scanning for lines matching `^-\s*$`, and resumes
  interviewing from the first incomplete section

This mirrors the three-point resilience set documented in
[resilience-schema.md](../../harness-init/references/resilience-schema.md).

# Roadmap Generation Guide

After `product-spec.md` is complete, the Planner derives
`.harness/<epic>/roadmap.md`: the epic's sprint decomposition with per-sprint
`bundling` flags. This file, not the product-spec, drives Issue creation and
the sprint loop.

Governs REQ-021 (sprint decomposition) and REQ-022 (bundling judgement).

## Pipeline

```
product-spec.md  →  Planner  →  roadmap.md  →  per-sprint contract.md
                                    │
                                    └─ issue-create.md (next step)
```

The Planner executes three passes:

1. **Decompose** What bullets into sprint candidates (1 capability ≈ 1 sprint).
2. **Judge bundling** via the coupling heuristics below.
3. **Order** sprints by dependency (prerequisite first) and risk (flakiest
   first when a peer-order choice exists).

## Decomposition Rules

| Rule | Rationale |
|---|---|
| One sprint delivers one **end-to-end user-visible capability** | Keeps acceptance scenarios unambiguous |
| A sprint that spans multiple What bullets is a decomposition failure | Either split the sprint, or the What bullets should have been one |
| No "infrastructure sprints" | Infra is a means; fold it into the first sprint that needs it |
| No "refactor sprints" | Refactor is internal; it must be in service of a capability |
| Maximum sprints per epic: 6 (guideline) | More suggests the epic is an initiative — ask the user to split |

If a capability requires groundwork (e.g., auth middleware before any
authenticated feature), the groundwork belongs **inside** sprint 1 of that
capability — not a preceding "sprint 0".

## Bundling Judgement (REQ-022)

Two sprints are **bundling candidates** when they share structural coupling
such that shipping them in separate PRs would cause rework. The Planner
checks the four coupling axes below; **any one** is sufficient to mark them
`bundled`:

| Coupling axis | Bundling signal |
|---|---|
| **Schema / data model** | Share a table, document shape, or core entity that both sprints write |
| **Auth / session** | Share the same authentication flow or session state transitions |
| **UI layout / component tree** | Share a layout shell, navigation root, or component hierarchy both sprints modify |
| **Contract surface** | Share a public API signature or event schema both sprints change |

The default is `split`. Bundle only when the heuristic fires with a clear,
writeable reason — the `bundling_reason` field is mandatory when bundling.

### Worked examples

| Scenario | Decision | Reason |
|---|---|---|
| `login` + `signup` on a shared `UserRecord` | `bundled` | Both write the same auth schema; separate PRs would churn the model twice |
| `login` + `user-profile-edit` | `split` | Profile reads the user record; no concurrent writes to auth fields |
| `password-reminder` + `signup` sharing email templates | `bundled` | Shared template contract; separating invites divergence |
| `billing-page` + `notification-preferences` | `split` | Independent surfaces, different data owners |
| `dashboard` + `dashboard-widget-a` | `bundled` | Layout shell and widget ship together or the widget has nowhere to land |

### Bundle group rules

- A bundle is a **connected component** in the coupling graph: if A bundles
  with B and B bundles with C, then {A, B, C} is one bundle group.
- All sprints in a bundle ship as **one PR** at the end of the last sprint
  in the group.
- The bundle's PR title lists every feature (`feat: login + signup + password-reminder`).
- Bundle size ceiling: 3 sprints. Larger → re-examine decomposition; the epic
  is probably too tightly coupled and should be redesigned upstream.

## `roadmap.md` Output Format

The Planner writes one frontmatter-based markdown file. The YAML is canonical;
the prose body is advisory.

```markdown
---
epic: auth-suite
generated_at: 2026-04-15T12:00:00Z
planner_model: claude-opus-4-6
sprints:
  - n: 1
    feature: login
    bundling: split
    bundling_reason: "Independent UI, no shared writeable schema"
    dependencies: []
    risk: medium
  - n: 2
    feature: signup
    bundling: bundled
    bundling_reason: "Shares UserRecord schema + password hashing with login"
    bundled_with: [3]
    dependencies: [1]
    risk: medium
  - n: 3
    feature: password-reminder
    bundling: bundled
    bundling_reason: "Shares email template contract with signup"
    bundled_with: [2]
    dependencies: [2]
    risk: low
---

# Roadmap: auth-suite

## Sprint Summary

| # | Feature | Bundling | Depends on | Risk |
|---|---|---|---|---|
| 1 | login | split | — | medium |
| 2 | signup | bundled (with 3) | 1 | medium |
| 3 | password-reminder | bundled (with 2) | 2 | low |

## Bundle Groups

- **Bundle A**: sprints 2 + 3 → single PR at end of sprint 3
- Sprint 1 → its own PR

## Rationale

<One paragraph per non-obvious decision. Cite the coupling axis for every
`bundled` entry. If a bundling judgement reversed a user expectation, note
it here so the roadmap approval AskUserQuestion can surface it clearly.>
```

### Required fields per sprint entry

| Field | Type | Required | Notes |
|---|---|---|---|
| `n` | int | yes | 1-indexed sprint number |
| `feature` | string (kebab-case) | yes | Used as directory name `sprint-<n>-<feature>/` |
| `bundling` | `split` \| `bundled` | yes | `split` is default |
| `bundling_reason` | string | required when bundling=bundled | Cites coupling axis |
| `bundled_with` | int[] | required when bundling=bundled | Peer sprints in the same bundle; must be reciprocal |
| `dependencies` | int[] | yes (may be `[]`) | Sprints that must finish first |
| `risk` | `low` \| `medium` \| `high` | yes | Seeds Evaluator threshold rigor |

**Reciprocity check**: if sprint 2 has `bundled_with: [3]`, sprint 3 must
have `bundled_with: [2]`. Planner validates before writing.

## Sprint Ordering

After bundling, Planner orders sprints:

1. **Topological**: honor `dependencies`. A sprint only runs after all its
   dependencies have `status: done`.
2. **Risk-first among peers**: if two sprints are dependency-peers,
   schedule the `high`-risk one first. Rationale — fail fast when the
   uncertainty is still cheap.
3. **Bundle proximity**: peers in the same bundle run consecutively. The
   PR at the end of the last peer captures all bundle work in one commit
   range.

## Approval Gate (T-024)

`harness-plan` surfaces the Sprint Summary table and bundle groups via
`AskUserQuestion` (interactive mode only). Options:

- **Approve as-is**: proceed to contract/Issue generation
- **Request changes**: user types changes; Planner regenerates; loop
- **Cancel**: write partial state to progress.md, exit

In non-interactive modes (`continuous` / `autonomous-ralph` / `scheduled`,
per ASM-007), approval is **implicit**: the roadmap is accepted and Issues
are created. The user has accepted this at `harness-init` mode selection.
If the roadmap needs post-hoc correction, the user must pause the loop
manually and edit `roadmap.md` before the affected sprint enters
negotiation.

## Handoff to Contract Generation

Once approved, `harness-plan` iterates the sprint list and, for each entry:

1. Copies `.harness/templates/sprint-contract.md` to
   `.harness/<epic>/sprints/sprint-<n>-<feature>/contract.md`
2. Pre-fills the YAML frontmatter (`sprint`, `feature`, `bundling`,
   `max_iterations`, `max_negotiation_rounds`) from `_config.yml` and the
   roadmap entry
3. Leaves `acceptance_scenarios` and `rubric` empty stubs — those are
   filled during sprint negotiation in `harness-loop`, not now
4. Sets `status: negotiating`

The contract's rubric is populated **later** — the Planner does not pre-fill
axes here, because threshold tuning depends on the sprint's risk level and
the rubric preset from `_config.yml.rubric_preset`. See
[rubric-presets.md](../../harness-init/references/rubric-presets.md).

## Recovery

If `harness-plan` is interrupted after product-spec but before roadmap
approval:

- `.harness/<epic>/roadmap.md` exists as a draft (or not at all)
- `_state.json.phase = "roadmap-draft"` or `"product-spec-draft"`
- On resume, Planner re-reads product-spec.md, diffs against the draft
  roadmap if present, and asks the user whether to continue or regenerate

<!--
  Planner `contract-draft` phase prompt template.
  harness-plan Orchestrator dispatches ONE instance of this per sprint
  (in parallel when the Task tool supports it).

  Substitutions:
    {{EPIC_NAME}}            — epic slug
    {{SPRINT_NUMBER}}         — integer, 1..N
    {{SPRINT_FEATURE}}        — feature slug (kebab-case)
    {{SPRINT_BUNDLING}}       — "split" | "bundled"
    {{SPRINT_BUNDLED_WITH}}   — other feature(s) bundled in, or ""
    {{SPRINT_GOAL}}           — 1-sentence goal from roadmap
    {{RUBRIC_PRESET}}         — web | api | cli (from _config.yml)
-->

You are the "planner" agent (see `.claude/agents/planner.md` / `.codex/agents/planner.toml`).
Load and follow its developer_instructions.

# Phase: contract-draft

Goal: produce the skeleton `contract.md` for sprint-{{SPRINT_NUMBER}}.
This is a **fresh Planner** — parallel-safe with other contract-draft
Planners running on sibling sprints.

Boot Sequence first (git log, progress.md tail, _state.json).

## Inputs you MAY read

- `.harness/{{EPIC_NAME}}/product-spec.md` — epic intent
- `.harness/{{EPIC_NAME}}/roadmap.md` — sprint layout and bundling decisions
- Your sprint metadata (below)

You must NOT assume other sprints' contract drafts are visible.

## Your sprint metadata

- Number: {{SPRINT_NUMBER}}
- Feature: {{SPRINT_FEATURE}}
- Bundling: {{SPRINT_BUNDLING}}
- Bundled with: {{SPRINT_BUNDLED_WITH}}
- Goal: {{SPRINT_GOAL}}
- Rubric preset: {{RUBRIC_PRESET}}

## Your task

Write `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`:

```yaml
---
sprint: {{SPRINT_NUMBER}}
feature: {{SPRINT_FEATURE}}
bundling: {{SPRINT_BUNDLING}}
bundled_with: [{{SPRINT_BUNDLED_WITH}}]
goal: {{SPRINT_GOAL}}
acceptance_scenarios:
  - id: AS-1
    text: <plain English scenario, normal happy path>
  - id: AS-2
    text: <plain English scenario, failure / edge case>
  - id: AS-3
    text: <plain English scenario, boundary condition>
rubric:
  - axis: Functionality
    weight: high
    threshold: ?       # Negotiation phase fills this
  - axis: Craft
    weight: std
    threshold: ?
  - axis: <project-type-specific axis 3>
    weight: std
    threshold: ?
  - axis: <project-type-specific axis 4>
    weight: low
    threshold: ?
max_iterations: ?       # Negotiation fills this
status: pending-negotiation
---

# Contract: sprint-{{SPRINT_NUMBER}} — {{SPRINT_FEATURE}}

## Goal
{{SPRINT_GOAL}}

## Acceptance Scenarios
<Elaborate each AS-N with preconditions, steps, expected outcome.>

## Notes for Generator & Evaluator
<Any sprint-specific conventions, e.g., "all date handling in UTC",
"use Zod for schema", etc.>
```

Axis selection follows `rubric_preset`:
- `web`: Functionality / Craft / Design / Originality
- `api`: Functionality / Craft / Consistency / Documentation
- `cli`: Functionality / Craft / Ergonomics / Documentation

## What you MUST NOT do

- Fill in `threshold` values — Negotiation sets them
- Fill in `max_iterations` — Negotiation sets it
- Write code
- Modify other sprints' files (parallel safety)
- Create the `feedback/` or `evidence/` subdirectories — harness-loop
  creates them on sprint entry

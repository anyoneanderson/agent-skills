<!--
  Generator Negotiation-phase prompt template.
  harness-loop Orchestrator substitutes per invocation:
    {{EPIC_NAME}}
    {{SPRINT_NUMBER}}
    {{SPRINT_FEATURE}}
    {{ROUND}}             — negotiation round 1..3
    {{EVALUATOR_FB_PATH}} — relative path to most recent evaluator-neg-*.md,
                            or "(none)" for round 1
-->

You are the "generator" agent (see `.claude/agents/generator.md` /
`.codex/agents/generator.toml`). Load and follow its developer_instructions.

# Phase: negotiation / round {{ROUND}}

Current sprint: sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}
Current epic: {{EPIC_NAME}}

Task: propose realistic rubric thresholds and max_iterations you can
meet for this sprint's `contract.md`. You are in negotiation with the
Evaluator; up to 3 rounds total.

## Files to read (Boot Sequence + phase-specific)

1. Standard Boot Sequence: git log / progress.md tail / _state.json
2. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`
3. Previous Evaluator response (if any):
   `{{EVALUATOR_FB_PATH}}`

## What you output

Write TWO files (the Orchestrator's bridge relies on both):

### A. `feedback/generator-neg-{{ROUND}}.md` — narrative

```markdown
---
role: generator
round: {{ROUND}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Decision
<accept | counter | escalate>

## Proposed thresholds
- Functionality: 1.0
- Craft: 0.85
- <axis3>: 0.75
- <axis4>: 0.6

## Proposed max_iterations
10

## Rationale
<specific reasons, per-axis or per-limit>
```

### B. `feedback/generator-neg-{{ROUND}}-report.json` — structured

```json
{
  "status": "done",
  "touchedFiles": [],
  "summary": "round {{ROUND}} negotiation response",
  "blocker": null
}
```

Negotiation rounds produce empty `touchedFiles` (you didn't implement
anything yet). Keep `status: "done"` unless you are blocked by a
pre-flight gate.

## Strategy hints

- Round 1: propose what you can honestly meet given the contract's
  acceptance scenarios. Do not over-promise.
- Round 2–3: narrow gaps, trade max_iterations for threshold relief
  where possible.
- Never agree to thresholds you cannot meet just to end the round.
- Round 3 deadlock → Planner rules.

## What you MUST NOT do

- Do NOT implement code in this phase. Negotiation only.
- Do NOT modify `contract.md` directly. The Orchestrator freezes it
  after Round 3 (or Planner ruling).
- Do NOT write to `shared_state.md`, `_state.json`, `progress.md`.

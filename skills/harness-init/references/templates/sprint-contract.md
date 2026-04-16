<!--
  sprint-contract.md — Per-sprint contract between Planner, Generator, and Evaluator.

  This file is negotiated once per sprint:
    1. Planner drafts it from product-spec.md + roadmap.md
    2. Generator and Evaluator negotiate up to 3 rounds (see Negotiation Log)
    3. Planner issues a final ruling if negotiation stalls
    4. Once `status: active`, the Implementation Loop begins

  RULES:
    - All axes listed in Rubric must be scored by Evaluator every iteration
    - Do NOT edit after `status: active` without re-entering negotiation
-->

---
sprint: <N>
feature: <feature-name>
bundling: split  # split | bundled
goal: |
  <one-paragraph description of what this sprint delivers to the user>
acceptance_scenarios:
  - id: AS-1
    given: <precondition>
    when: <user action>
    then: <observable outcome>
  - id: AS-2
    given:
    when:
    then:
rubric:
  - axis: Functionality
    weight: high
    threshold: 1.0
    description: All acceptance scenarios pass end-to-end
  - axis: Craft
    weight: std
    threshold: 0.7
    description: Code is readable, tested, and follows project conventions
  - axis: Design
    weight: std
    threshold: 0.7
    description: UX is coherent; matches product-spec intent
  - axis: Originality
    weight: low
    threshold: 0.5
    description: Avoids AI-template tropes; feels deliberate
max_iterations: 8
max_negotiation_rounds: 3
status: negotiating  # negotiating | active | done | aborted
---

# Sprint <N> Contract — <feature-name>

## Acceptance Scenarios (executable)

<!--
  Re-state the YAML scenarios as Playwright / pytest / curl test stubs
  when possible. Evaluator derives tests from this section.
-->

### AS-1: <short title>

```
Given <precondition>
When  <action>
Then  <outcome>
```

Evidence: `sprints/sprint-<N>-<feature>/evidence/AS-1.<ext>`

### AS-2: <short title>

```
Given
When
Then
```

Evidence: `sprints/sprint-<N>-<feature>/evidence/AS-2.<ext>`

## Rubric Detail

| Axis | Weight | Threshold | Scoring notes |
|---|---|---|---|
| Functionality | high | 1.0 | Binary-ish: every AS passes or sprint fails |
| Craft | std | 0.7 | Test coverage, readability, adherence to coding-rules.md |
| Design | std | 0.7 | Matches product-spec "What" section, no scope creep |
| Originality | low | 0.5 | Avoid AI-template boilerplate; prefer task-specific design |

Total pass condition: **every axis meets its threshold**. Weight only affects
Evaluator's ordering when reporting failures (high-weight fails reported first).

## Negotiation Log

<!--
  Rounds 1–3 only. After round 3 (or earlier agreement), Planner writes a
  ruling and sets `status: active`. Do not edit once active.
-->

### Round 1

- **Generator**:
- **Evaluator**:

### Round 2

- **Generator**:
- **Evaluator**:

### Round 3

- **Generator**:
- **Evaluator**:

### Ruling

- **Planner**:
  <!-- Final contract adjustments, if any. Otherwise: "Contract accepted as drafted." -->

## Sprint Outcome

<!--
  Filled by Orchestrator when status transitions to done | aborted.
-->

- **Final iteration**:
- **Last commit**:
- **Aborted reason** (if any):
- **PR**:

<!--
  Evaluator Implementation-phase prompt template.
  harness-loop Orchestrator substitutes ONLY the declared placeholders:
    \{\{EPIC_NAME\}\}
    \{\{SPRINT_NUMBER\}\}
    \{\{SPRINT_FEATURE\}\}
    \{\{ITER\}\}              — iteration 1..max_iterations
    \{\{GENERATOR_FB_PATH\}\} — relative path to generator-\{\{ITER\}\}.md
    \{\{EVALUATOR_TOOLS\}\}   — comma-separated _config.yml.evaluator_tools

  Orchestrator non-design (see harness-loop/README.md §Agents):
  rubric scoring and severity judgments belong to the Evaluator.
  The Orchestrator does not pre-score axes, summarize evidence, or
  suggest a desired verdict in this prompt.
-->

You are the "evaluator" agent (see `.claude/agents/evaluator.md`).
Load and follow its developer_instructions.

# Phase: evaluation / iteration {{ITER}}

Current sprint: sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}
Current epic: {{EPIC_NAME}}

Task: execute the contract's acceptance scenarios using
`{{EVALUATOR_TOOLS}}`, treat the first listed tool as the primary Phase 3
tool, score each rubric axis in `[0.0, 1.0]`, apply the Critical /
Improvement severity matrix from `docs/review_rules.md`, and write the
canonical evaluation feedback for this iteration.

## Files to read (Boot Sequence + phase-specific)

1. Standard Boot Sequence: git log / progress.md tail / _state.json
2. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`
3. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/shared_state.md`
4. Current Generator feedback:
   `{{GENERATOR_FB_PATH}}`
5. `feedback/generator-{{ITER}}-report.json`

## What you output

Write TWO canonical files under the sprint's `feedback/` directory:

### `feedback/evaluator-{{ITER}}.md` — evaluation narrative

```markdown
---
role: evaluator
iter: {{ITER}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Verdict
status: <pass | fail>

## Axes
- functionality: 0.8 [threshold 1.0, FAIL] — <evidence-backed reason>
- craft: 0.9 [threshold 0.7, pass] — <reason>
- design: 0.7 [threshold 0.7, pass] — <reason>
- originality: 0.6 [threshold 0.5, pass] — <reason>

## Evidence
- evidence/iter-{{ITER}}/<artifact-1>
- evidence/iter-{{ITER}}/<artifact-2>

## Notes for next iteration
- <focus point for Generator>
```

### `feedback/evaluator-{{ITER}}-report.json` — machine-readable compliance report

```json
{
  "status": "pass",
  "axes": {
    "functionality": 1.0,
    "craft": 0.9,
    "design": 0.8,
    "originality": 0.7
  },
  "critical_count": 0,
  "improvement_count": 0,
  "minor_count": 0,
  "phases_executed": ["1", "2", "2.5", "3", "4"],
  "phase_2_5_quality_gate_found": true,
  "phase_2_5_commands": [
    {
      "cmd": "project quality-gate command as executed",
      "exit": 0,
      "log": "evidence/iter-{{ITER}}/quality-gate-command.log",
      "summary": "short result summary"
    }
  ],
  "evidence_refs": ["evidence/iter-{{ITER}}/quality-gate-command.log"],
  "forced_failure_reason": null,
  "request_planner_escalation": null
}
```

## Evaluation guidance

- Follow `.claude/skills/harness-loop/references/review-process.md` Phase 1-4 in order.
- Do not omit, merge, or rename phases. `phases_executed` must include
  `"1"`, `"2"`, `"2.5"`, `"3"`, and `"4"`.
- Record every project quality-gate command executed in Phase 2.5 under
  `phase_2_5_commands`. If any command has `exit != 0`, set
  `status: "fail"` and `forced_failure_reason:
  "project-quality-gate-failed"`.
- Only when `docs/issue-to-pr-workflow.md` has no quality gate may you set
  `phase_2_5_quality_gate_found: false` and `phase_2_5_commands: []`.
- During Phase 3, use the primary tool from `{{EVALUATOR_TOOLS}}` via
  `.claude/skills/harness-loop/references/evaluator-tooling/<tool>.md`.
  Save artifacts under
  `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/evidence/iter-{{ITER}}/`
  and record sprint-dir-relative paths (`evidence/iter-{{ITER}}/...`) in
  `evidence_refs`; the validator will force `status: "fail"` when
  Phase 3 is claimed but no evidence file exists.
- Do not author `phase_3_evidence_status`, `validator_violations`,
  `validator_invoked`, or `schema_version` yourself. They are
  validator-owned idempotency fields.
- Score every rubric axis in `[0.0, 1.0]` with concrete observations.
- Apply the `docs/review_rules.md` severity matrix:
  Critical findings force Craft to `<= 0.5`; Improvement findings
  deduct `0.05` each down to `0.5`; Minor findings are notes only.
- Base the verdict on executed evidence, not on Generator self-report.
- Detect and record stub-only evidence. `page.route`, `addInitScript`,
  `window.fetch` override, or equivalent full contract-boundary bypass
  does not count as Functionality proof.

## Optional: `request_planner_escalation` in report.json

If your cross-iter evidence shows that the frozen contract cannot be
satisfied by further implementation (e.g., a threshold is physically
incompatible with the available model / tools / runtime), you may
attach a `request_planner_escalation` block to
`feedback/evaluator-{{ITER}}-report.json`. See
`../shared-state-protocol.md#mid-impl-replan-escalation-layer-1-agent-request`
for the schema. Evaluator is usually better positioned than Generator
to detect contract debt because you see live evidence across
iterations. Cite concrete evidence paths and name the disputed clauses.

Set the block only when further Generator work cannot close the gap.
If you believe the failing axes are still solvable by implementation,
omit the block and keep the normal verdict flow.

## What you MUST NOT do

- Do NOT edit source code, tests, or `contract.md`.
- Do NOT write `shared_state.md`, `_state.json`, `metrics.jsonl`, or
  `progress.md`.
- Do NOT skip scenario execution and grade from code inspection alone.

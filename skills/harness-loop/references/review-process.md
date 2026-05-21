# Evaluator Review Process

This file defines the **how** of Evaluator review inside harness-loop.
`evaluator.md` defines role identity, `docs/review_rules.md` defines what to
check, and `evaluator-tooling/<tool>.md` defines the tool-specific Phase 3
execution path.

Every Phase is part of the scoring contract. Execute the Phases in the
defined order with the defined heading names and output shape. Do not omit,
merge, rename, or reinterpret them. When any required Phase is skipped, the
Orchestrator must downgrade the iteration to fail. Phase 2.5 (project
quality gate) is also a required condition for a Functionality pass.

## 0. Boot read order

1. `git log --oneline -20`
2. `tail -30 .harness/progress.md`
3. `cat .harness/_state.json`
4. Read the current sprint `contract.md`
5. Read the current phase Generator feedback
6. Parse `.gitignore` and add its patterns to the exclusion baseline
7. Read `docs/review_rules.md`
8. Read `docs/coding-rules.md` when present
9. Read `docs/issue-to-pr-workflow.md` Quality Gate / `品質ゲート` section
   when present to identify the project's PR quality-gate commands
10. Read the primary tool reference:
   `.claude/skills/harness-loop/references/evaluator-tooling/<tool>.md`

## 1. Exclusion synthesis

Phase 1 review excludes are composed in this order:

1. **Universal baseline**:
   `.git/**`, `**/*.generated.*`, `**/*.lock`, `**/*.log`, `node_modules/**`
2. **`.gitignore` additions**:
   parse `.gitignore` and add those patterns to the exclusion set
3. **`_config.yml.project_type` helper excludes**:
   - `web`: `.next/**`, `.turbo/**`, `out/**`, `dist/**`, `build/**`, `coverage/**`
   - `api`: `dist/**`, `build/**`, `coverage/**`, `__pycache__/**`, `target/**`
   - `cli`: `target/**`, `dist/**`, `build/**`
   - `other`: no helper layer beyond `.gitignore`
4. **`docs/review_rules.md` override**:
   if `docs/review_rules.md` defines a `レビュー除外パターン` section, treat that
   section as the highest-priority override

These patterns narrow review scope only. They do not justify skipping live
contract-boundary verification when a touched file influences a scenario.

## 2. Confidence-based scoring control

- **High confidence (80+)**: include it in Findings or Axes with evidence.
- **Medium confidence (50-79)**: keep it in `Notes for next iteration`; do not
  upgrade it to Critical.
- **Low confidence (49-)**: omit it from the output and re-verify first.

Confidence depends on executed evidence, direct contract-boundary contact, and
independence from Generator self-report.

## 3. Review phases

### Phase 1: Pattern grep

Cross-check `docs/review_rules.md` hotspots and touched files. This phase only
identifies risk signals; it must flow into later verification.

### Phase 2: State-flow trace

Read `feedback/generator-<iter>-report.json` `touchedFiles` from top to bottom
and mentally trace state transitions, contract-boundary payloads, edge cases,
and empty / null / timeout / auth-failure handling.

### Phase 2.5: Project quality gate

Execute the PR quality gate documented in `docs/issue-to-pr-workflow.md`
Quality Gate / `品質ゲート` section before Phase 3 contract-boundary
verification.

- For each command: run it, capture stdout/stderr to
  `${SPRINT_DIR}/evidence/iter-<n>/quality-gate-<short-cmd>.log`, and record the exit code.
- Any non-zero exit forces a **Critical** finding and caps Functionality below
  the pass threshold for this iteration. A Functionality pass verdict requires
  the entire gate to be green.
- If `docs/issue-to-pr-workflow.md` is absent, emit an `Improvement` note
  (`no project quality gate wired up`) and proceed without the gate.

This catches build, lint, type, packaging, or equivalent project-level errors
that unit and contract tests alone can miss.

### Phase 3: Contract-boundary integration

Treat the first `_config.yml.evaluator_tools` entry as the primary tool and
follow `.claude/skills/harness-loop/references/evaluator-tooling/<tool>.md`.

- Generator-authored specs or stub-only tests are not pass evidence.
- Record `page.route`, `addInitScript`, `window.fetch` override, full `vi.mock`,
  or equivalent contract-boundary bypass as evidence when found.
- Exercise both the happy path and at least one abnormal or boundary path when
  the contract implies validation, auth, timeout, or empty-state behavior.

### Phase 4: Audit self-check

Before emitting the final output, answer yes/no:

- Did I execute Phase 1-3?
- Did I execute Phase 2.5 and confirm every project quality-gate command
  exited zero?
- Did I avoid treating Generator test pass as my own pass evidence?
- Did I touch the contract boundary myself?
- Am I soft-grading to end the sprint early?

If any answer is no, re-run before writing the verdict.

## 4. Output structure

`feedback/evaluator-<iter>.md` must contain at least:

- `Verdict`
- `Axes`
- `Evidence`
- `Review findings` (`Critical` / `Improvement` / `Minor`)
- `Notes for next iteration`

`feedback/evaluator-<iter>-report.json` is also required. The Orchestrator
validates this machine-readable report in Step 6 and automatically
downgrades skipped Phases or failed quality-gate commands to fail.

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
      "log": "evidence/iter-<n>/quality-gate-command.log",
      "summary": "short result summary"
    }
  ],
  "evidence_refs": ["evidence/iter-<n>/quality-gate-command.log"],
  "forced_failure_reason": null
}
```

Rules:

- `phases_executed` must include `"1"`, `"2"`, `"2.5"`, `"3"`, and `"4"`.
- When `phase_2_5_quality_gate_found == true`, `phase_2_5_commands` must
  include every executed command.
- If any `phase_2_5_commands[].exit` is non-zero, set `status` to `fail`
  and `forced_failure_reason` to `project-quality-gate-failed`.
- Only when `docs/issue-to-pr-workflow.md` has no quality gate may the
  report use `phase_2_5_quality_gate_found: false` and
  `phase_2_5_commands: []`.
- Missing, invalid, or incomplete report JSON is treated by the Orchestrator
  as `evaluator-report-invalid` and downgraded to fail.

`feedback/evaluator-neg-<round>.md` must contain `Decision`,
`Proposed thresholds`, `Proposed max_iterations`, and `Rationale`.
Stub-only evidence is never a feasibility reason for relaxing the contract.

# Validator Protocol

Step 4 negotiation and Step 6 implementation share the same post-dispatch
contract. These steps are NOT optional.

After each Generator or Evaluator dispatch, Orchestrator MUST:

1. For backend=`claude`, invoke `.harness/scripts/claude-dispatch.sh
   --post-dispatch ...` to canonicalize file paths/names and synthesise
   fallback files if the subagent did not produce expected outputs.
   `claude-dispatch.sh` does NOT invoke the subagent; `Task()` is the
   Orchestrator's responsibility. It also does NOT write `_state.json`
   directly.
2. Invoke `.harness/scripts/validate-<role>-report.sh ...` to enforce
   schema compliance. Evaluator validation also enforces Phase 3 evidence
   existence when `phases_executed` includes `"3"`.
   - Generator implementation:
     `.harness/scripts/validate-generator-report.sh --report <sprint>/feedback/generator-<iter>-report.json --narrative <sprint>/feedback/generator-<iter>.md --report-dir <sprint>/feedback --phase impl`
   - Evaluator implementation:
     `.harness/scripts/validate-evaluator-report.sh --report <sprint>/feedback/evaluator-<iter>-report.json --narrative <sprint>/feedback/evaluator-<iter>.md --sprint-dir <sprint> --report-dir <sprint>/feedback --phase impl --strict`
3. If validation exits non-zero, Orchestrator owns the state transition:
   - `interactive`: write `_state.json.pending_human=true`, set
     `halt_reason`, append the halt line through `progress-append.sh`, and
     stop.
   - `continuous`, `autonomous-ralph`, `scheduled`: increment
     `consecutive_validator_violations`, retry by advancing to the next
     iteration, and escalate to `pending_human=true` after 3 consecutive
     violations.

`_state.json` and `progress.md` writes are EXCLUSIVELY the Orchestrator's
responsibility. Dispatch and validator scripts only mutate the target
feedback files, emit stdout/stderr, and return exit codes.

## Validator-owned fields

Agents MUST NOT author these fields in their canonical report examples:

- `validator_invoked`: validator writes `true` after every run.
- `schema_version`: validator writes the current machine schema version.
- `validator_violations`: validator writes a non-null array, empty on pass.
- `phase_3_evidence_status`: evaluator validator writes one of
  `"present"`, `"missing"`, or `"n/a"`. Any other authored value is invalid.

Phase 3 evidence belongs under `${SPRINT_DIR}/evidence/iter-<n>/`.
`evidence_refs[]` should use sprint-dir-relative paths such as
`evidence/iter-<n>/quality-gate-command.log`. The evaluator validator
recognizes non-UI artifacts including `.log`, `.test.ts`, `.txt`, and
`.md`, alongside Playwright screenshots, JSON/JSONL traces, and `.spec.ts`.

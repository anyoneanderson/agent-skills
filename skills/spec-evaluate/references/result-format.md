# Result File Format — evaluate-{round}.md

The evaluator writes one result file per round:
`.specs/{feature}/evaluate-{round}.md`. Its two jobs are (1) to be consumable by
`spec-code --feedback` without translation, and (2) to be independently
verifiable against the evidence on disk.

To satisfy (1) it uses the **same Findings structure as spec-review** (a
`type` header, `## Findings` with `### Critical` / `### Improvement` /
`### Minor`, and a `## Summary` with a `Gate:` line). A failing acceptance case
maps to a **Critical** finding; a concern or degradation maps to an
**Improvement** finding. To satisfy (2) every PASS row cites an evidence file by
relative pointer that must actually exist.

## Format

```markdown
# Acceptance Evaluation: {feature} — round {n}
type: evaluate

## Meta
- Evaluator: spec-evaluate ({backend})
- Date: {ISO 8601}
- Test plan: .specs/{feature}/test.md
- Evidence dir: .specs/{feature}/evidence/{n}/
- App recipe: {present | absent}

## Requirement Results
| Case | Requirement | Verify | Verdict | Evidence |
|------|-------------|--------|---------|----------|
| T-A01 | REQ-001 | playwright | PASS | evidence/{n}/T-A01-login.png |
| T-A02 | NFR-001 | command | FAIL | evidence/{n}/T-A02-latency.log |
| T-A03 | REQ-005 | file-check | PASS | evidence/{n}/T-A03-export.log |
| T-A04 | REQ-007 | playwright | BLOCKED | evidence/{n}/app-startup.log |

## Findings

### Critical
- [ ] **T-A02 [NFR-001]** `evidence/{n}/T-A02-latency.log` — p95 latency 820ms
  exceeds the 500ms requirement. Expected p95 < 500ms; measured 820ms.

### Improvement
- [ ] **T-A01 [REQ-001]** login succeeds but the dashboard flashes an empty
  state for ~1s before data loads. Passes the assertion; worth smoothing.

### Minor
- (none)

## Blocked
- **T-A04 [REQ-007]** app launch recipe unavailable — no `app:` section in
  pipeline.yml. Evidence: `evidence/{n}/app-startup.log`. Not counted as a
  failure; needs a launch recipe to run.

## Summary
- Cases: 2 PASS / 1 FAIL / 1 BLOCKED (4 total)
- Critical: 1 | Improvement: 1 | Minor: 0
- Gate: FAIL
```

## Field Rules

- `type: evaluate` header is mandatory (mirrors `type: review` / `type: test`).
- **Requirement Results** table: one row per test case, carrying its case ID,
  requirement ID, verification method, verdict, and evidence pointer. This is the
  requirement-level pass/fail view the pipeline reads.
- Verdict ∈ `PASS | FAIL | BLOCKED`.
- **Evidence** column is a pointer relative to `.specs/{feature}/`. A PASS row
  with a pointer that does not resolve to an existing, non-empty file is invalid.
- **Findings** sections mirror spec-review exactly so `spec-code --feedback`
  parses them without special-casing. Each Critical/Improvement item names the
  case ID and requirement ID.
- **Blocked** section lists cases that could not run for want of setup. Blocked
  is distinct from FAIL: it is not a Critical finding and is not a quality defect
  in the implementation.

## Gate Logic

- Any FAIL case → `Gate: FAIL` (Critical findings present).
- Any BLOCKED case with no FAIL → still `Gate: FAIL`, with the blocked cases as
  the reason. Unverified UI requirements must not be treated as accepted in an
  unattended run.
- Every case PASS → `Gate: PASS`.

## Machine Verification (enforced by the runner, not the evaluator)

After the evaluator returns, spec-evaluate re-checks the file it wrote:

1. For each row with verdict PASS, resolve the Evidence pointer relative to
   `.specs/{feature}/`.
2. If the file is missing or empty, rewrite the verdict to FAIL and add a
   Critical finding: "evidence not found for {case}: {pointer}".
3. Recompute the `## Summary` counts and the `Gate:` line.

This is the enforcement behind NFR-003: a self-reported pass with no backing
evidence cannot survive into the accepted result.

## Feeding Back to spec-code

The Critical and Improvement findings are handed to `spec-code --feedback`
verbatim; the builder fixes them and the implement ⇄ evaluate loop repeats with
`round + 1`. Because the format matches spec-review, no adapter is needed between
the acceptance layer and the implementation loop.

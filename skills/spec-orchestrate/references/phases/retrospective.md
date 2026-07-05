# Phase: retrospective

After the PR (ready or draft), turn the structured run records into a
retrospective report and, where allowed, skill improvements. This phase's
aggregation, Tier judgment, and auto-apply mechanics are implemented in T015 and
T016; this file fixes its place in the state machine and its 4-point contract.

## Input

- `pipeline-state.json` (round history, stalls, arbitrations).
- Every worker `report.json` (including `blocker_category`).
- The `evaluate-{n}.md` results and evidence.
- The review files.

A run that failed before reaching pr may still run retrospective as a learning
step, but then it stops at report generation and Issue filing — no auto-apply
(the metrics comparison against a clean run does not hold).

## Action

1. Aggregate the records into a category breakdown (machine step) and append one
   line to `.specs/pipeline-metrics.jsonl` (T015).
2. Analysis and any file edits are delegated to a worker, not done by the
   orchestrator — editing skill files directly would break the orchestrator-only
   rule. The orchestrator handles only aggregation, Tier judgment, and git/PR.
3. Improvement application (Tier judgment, line-budget check, branch/PR/merge or
   Issue-filing fallback, revert policy) is defined in T016.

## Output

- `retrospective.md` (design §5.6 format) in `.specs/{feature}/`, one appended
  line in `.specs/pipeline-metrics.jsonl`, and any improvement branch/PR or
  filed Issue.

## Verification

- `retrospective.md` was written in the design §5.6 format, with each proposal
  carrying a rationale (which aggregation row it came from) and a Tier.
- The metrics line was appended.

## State Update

- Record the retrospective outcome (report path, applied improvements, filed
  Issues) in state.
- This is the terminal phase: mark the run complete.

## Transitions

- report + improvements (or Issue fallback) done → **(end)**

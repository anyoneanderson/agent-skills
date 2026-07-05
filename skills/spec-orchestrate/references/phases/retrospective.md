# Phase: retrospective

After the PR (ready or draft), turn the structured run records into a
retrospective report and a metrics line, and — where allowed — skill
improvements. The report and metrics are produced here; Tier judgment and the
auto-apply / revert mechanics are in `../improve-apply.md`, referenced but not
implemented in this phase guide.

The detailed aggregation procedure, the `pipeline-metrics.jsonl` schema, the
`retrospective.md` §5.6 template, and the previous-run comparison are in
`../retrospective-format.md`.

## Timing

Runs after pr completes (including a draft landing). A run that failed before
reaching pr may still run retrospective as a learning step — failed runs are the
most instructive — **but then it stops at report generation and Issue filing; no
auto-apply** (a metrics comparison against a clean completion does not hold, so
the `../improve-apply.md` apply step is skipped). spec-orchestrate can also be
invoked to run this phase standalone against an existing state file.

## Input

- `pipeline-state.json` — round history (`rounds`), stalls and adjudications
  (`arbitrations`), role overrides.
- Every worker `report.json` — the `blocker_category` field is the classification
  key (per the agent-delegate contract).
- The `evaluate-{n}.md` results (failing cases) and evidence.
- The review files.
- The previous line of `.specs/pipeline-metrics.jsonl`, for comparison.

## Action

Role division (design §4.10, consistent with REQ-002): the orchestrator does the
mechanical aggregation, the Tier judgment, and the git/PR operations; the
**analysis and any file edits are delegated to a worker**. The orchestrator never
edits skill files directly.

1. **Aggregate (mechanical — orchestrator).** Build the category breakdown from
   `state`, all `report.json` `blocker_category` counts, and the evaluate
   failures. Append one line to `.specs/pipeline-metrics.jsonl`. Procedure and
   schema: `../retrospective-format.md`.
2. **Analyze (LLM — delegated worker).** Give the aggregation table to a worker
   subagent. For each frequent pattern it identifies which skill's which file's
   what is the cause and writes an improvement proposal with a rationale (which
   aggregation row it came from) and a Tier. A finding with no frequency backing
   is recorded as an **observation**, not a proposal.
3. **Compare metrics.** Read the previous run's line and judge whether this run
   worsened or improved on the shared metrics (rounds, blocker categories,
   stalls). The auto-revert decision that consumes this is in
   `../improve-apply.md`; retrospective only records the comparison.
4. **Apply improvements** (Tier judgment, line-budget check, branch/PR/merge or
   Issue-filing fallback, revert) is `../improve-apply.md`. Skipped for a
   pr-not-reached run.

## Output

- `retrospective.md` in `.specs/{feature}/` in the §5.6 format (execution
  summary / failure breakdown table / stall-and-arbitration record / improvement
  proposals with rationale + Tier / observations).
- One appended line in `.specs/pipeline-metrics.jsonl`.
- (Via `../improve-apply.md`) any improvement branch/PR or filed Issue.

## Verification

- `retrospective.md` follows the §5.6 format and every proposal carries a
  rationale (the aggregation row it came from) and a Tier.
- The metrics line was appended and parses as JSON.
- The failure breakdown is reproducible from `state` + `report.json` files alone
  (mechanical, not the worker's recollection).

## State Update

- Record the retrospective outcome (report path, metrics line, applied
  improvements or filed Issues) in `state`.
- This is the terminal phase: mark the run complete.

## Transitions

- report + metrics written (+ improvements or Issue fallback via
  `../improve-apply.md`) → **(end)**

# Phase: retrospective

After the PR (ready or draft), turn the structured run records into a
retrospective report and a metrics line, and — where allowed — skill
improvements. The report and metrics are produced here; Tier judgment and the
auto-apply / revert mechanics are in `../improve-apply.md`, referenced but not
implemented in this phase guide.

The detailed aggregation procedure, the `pipeline-metrics.jsonl` schema, the
`retrospective.md` template, and the previous-run comparison are in
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
- The previous active record selected from `.specs/pipeline-metrics.jsonl`, for
  comparison. Superseded rows and event rows are never comparison inputs.

## Action

Role division: the orchestrator does the
mechanical aggregation, the Tier judgment, and the git/PR operations; the
**analysis and any file edits are delegated to a worker**. The orchestrator never
edits skill files directly.

1. **Aggregate (mechanical — orchestrator).** Build the category breakdown from
   `state`, all `report.json` `blocker_category` counts, and the evaluate
   failures. Compose (but do not yet append) the metrics values. Procedure and
   schema: `../retrospective-format.md`.
2. **Analyze (LLM — delegated worker).** Give the aggregation table to a worker
   subagent. For each frequent pattern it identifies which skill's which file's
   what is the cause and writes an improvement proposal with a rationale (which
   aggregation row it came from) and a Tier. A finding with no frequency backing
   is recorded as an **observation**, not a proposal.
3. **Compare metrics.** Use `retrospective-ledger.sh list-active` to select the
   previous valid run record and judge whether this run worsened or improved on
   the shared metrics (rounds, blocker categories, stalls). The auto-revert
   decision that consumes this is in `../improve-apply.md`; retrospective only
   records the comparison. Never read the physical last JSONL line.
4. **Apply improvements** (Tier judgment, line-budget check, branch/PR/merge or
   Issue-filing fallback, revert) is `../improve-apply.md`. Before each external
   action, reserve its stable `action_key` in state; after the action, record its
   result. Reconcile a pending key instead of blindly repeating the action.
   Skip the apply path for a pr-not-reached run.
5. **Recover or freeze the terminal basis.** First query `active` for this
   `run_id`. If a record already exists after a prior crash, validate its
   snapshot against current rounds, report manifest, PR evidence, and terminal
   phase; adopt its revision, snapshot, ids, and `state_ts_updated` rather than
   stamping a new time. A mismatch blocks for repair — never append a competing
   active record. If none exists, choose one terminal `ts_updated` and construct
   the terminal state basis in memory: set `phase: retrospective`, add
   `retrospective` to `completed_phases` exactly once, and set that timestamp.
   Collect the sorted spec-relative report manifest, compute `state_hash` from
   the canonical basis with `.retrospective` removed, then compute `snapshot_id`
   from the canonical snapshot. Use revision 1 for the first terminal projection
   or exactly N+1 after a completed-run resume. Freeze these hashed fields; do
   not refresh `ts_updated` again during finalization.
6. **Write the projection, append idempotently, then verify.** Write the frozen
   snapshot to `retrospective.md`. After the apply step, call
   `retrospective-ledger.sh append-metrics-once`, using the frozen terminal
   timestamp as metrics `ts` and recording what actually happened in
   `applied_improvements` (`[]` if none, degraded, or pr not reached). Then write
   the complete terminal basis plus `state.retrospective` atomically, with
   `stale` and `regeneration_required` false. Do not perform a separate flag or
   timestamp write. Run `pipeline-state-check.sh`; only a clean check permits
   marker deletion. If the same terminal snapshot was already finalized, do not
   rewrite the report, append metrics, or repeat external actions.

## Output

- `retrospective.md` in `.specs/{feature}/` in the retrospective format (execution
  summary / failure breakdown table / stall-and-arbitration record / improvement
  proposals with rationale + Tier / observations).
- One active versioned record in `.specs/pipeline-metrics.jsonl`; older
  revisions remain append-only and are superseded by events.
- (Via `../improve-apply.md`) any improvement branch/PR or filed Issue.

## Verification

- `retrospective.md` follows the retrospective format and every proposal carries a
  rationale (the aggregation row it came from) and a Tier.
- The report, state, and active metrics record contain the same snapshot, and
  `pipeline-state-check.sh` exits 0.
- The run has exactly one active metrics record. Repeating the same terminal
  finalization appends nothing and repeats no external action.
- The failure breakdown is reproducible from `state` + `report.json` files alone
  (mechanical, not the worker's recollection).

## State Update

- Record revision, snapshot and ids, freshness flags, report path, active
  metrics id, and deduplicated external-action results under
  `state.retrospective`; add `retrospective` to `completed_phases` as a
  historical completion.
- This is the terminal phase: mark the run complete and **delete
  `.specs/.orchestrate-active.json`** — removing the run marker is the terminal
  signal to the watchdog (`../pipeline-config.md` §Run Marker and Watchdog).

## Transitions

- report + metrics written (+ improvements or Issue fallback via
  `../improve-apply.md`) → **(end)**

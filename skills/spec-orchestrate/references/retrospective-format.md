# Retrospective Format — Aggregation, Metrics, and Report

This file specifies what the retrospective phase produces: the mechanical
aggregation, the `pipeline-metrics.jsonl` line, the `retrospective.md` template,
and the previous-run comparison. The point is that proposals are backed
by counts, not vibes — a suggestion with no frequency behind it stays an
observation.

日本語版: [retrospective-format.ja.md](retrospective-format.ja.md)

## Step 1: Aggregation (mechanical)

Read only structured records — no re-interpretation of prose:

| Source | What to extract |
|--------|-----------------|
| `pipeline-state.json` `rounds` | rounds per loop (`spec_review`, `evaluate`), severity counts, gates |
| `pipeline-state.json` `arbitrations` | each stall signal, decision, and result |
| `pipeline-state.json` `role_overrides` | owner swaps (capability fallback or arbitration) |
| `pipeline-state.json` `review_fallbacks` | reduced cross-AI review assurance (phase, artifact, preferred/actual role) |
| every worker `report.json` | `blocker_category` (tally by category), `status` |
| `evaluate-{n}.md` | failing cases (case id, requirement id) |

Produce the **failure breakdown table** — one row per `blocker_category` seen:

```markdown
| blocker_category | count | phase(s) | example |
|------------------|-------|----------|---------|
| malformed_output | 3 | spec_review | round 2 review missing Gate line |
| timeout | 1 | evaluate | T-A04 playwright run exceeded ceiling |
```

`blocker_category` values come from the agent-delegate contract
(`malformed_output`, `tool_unavailable`, `timeout`, `sandbox_violation`,
`env_error`, `unclassified`). The orchestrator may re-classify from the
`blocker` text, but the category is the grouping key.

## Step 2: pipeline-metrics.jsonl (versioned append-only ledger)

`.specs/pipeline-metrics.jsonl` is a repository-wide JSON Lines ledger. A
terminal retrospective appends a versioned metrics record. Reopening that run
appends a supersede event; it never rewrites or deletes the old row.

```json
{"record_type":"metrics","record_id":"2026-07-05T09:00:00Z-a1b2:r2:<snapshot-id>","revision":2,"feature":"user-auth","run_id":"2026-07-05T09:00:00Z-a1b2","mode":"auto","snapshot_id":"<sha256>","snapshot":{"run_id":"2026-07-05T09:00:00Z-a1b2","phase":"retrospective","completed_phases":["intake","spec_generate","inspect","spec_review","approval","implement","evaluate","pr","retrospective"],"rounds_spec":3,"rounds_eval":2,"report_count":2,"report_manifest":["implement-report.json","review-report.json"],"pr_url":"https://github.com/example/repo/pull/42","pr_status":"ready","state_ts_updated":"2026-07-05T10:00:00Z","state_hash":"<sha256>"},"rounds_spec":3,"rounds_eval":2,"stalls":1,"blocker_categories":{"malformed_output":3,"timeout":1},"applied_improvements":["P-01"],"ts":"2026-07-05T10:00:00Z"}
{"record_type":"supersede","event_id":"supersede:<record-id>:run_resumed","run_id":"2026-07-05T09:00:00Z-a1b2","supersedes":"<record-id>","reason":"run_resumed","ts":"2026-07-05T09:30:00Z"}
```

| Field | Meaning |
|-------|---------|
| `record_type` / `record_id` / `revision` | Metrics ledger identity; revision increases only after a resumed run reaches terminal again |
| `feature` / `run_id` / `mode` | Stable logical-run identity |
| `snapshot_id` / `snapshot` | SHA-256 of, and exact copy of, the terminal freshness snapshot |
| `rounds_spec` / `rounds_eval` | Round counts for the two loops |
| `stalls` | Number of arbitration entries this run |
| `blocker_categories` | Category → count map (from Step 1) |
| `applied_improvements` | Proposal ids actually auto-applied this revision; `[]` if none, degraded, or pr was not reached |
| `ts` | ISO 8601 record timestamp |

Before creating the snapshot, set one terminal `ts_updated`. Build a sorted,
spec-relative `report_manifest` of every `report.json` / `*-report.json`, and
derive `report_count` from that array. Compute `state_hash` as SHA-256 of
canonical terminal state with `.retrospective` removed; this basis already has
`phase: retrospective`, historical `completed_phases` including
`retrospective`, and the frozen terminal timestamp. Compute `snapshot_id` as
SHA-256 of the canonical snapshot. The report, state, and metrics record must
contain the same snapshot object, and metrics `ts` equals
`snapshot.state_ts_updated`.

Before choosing a new timestamp, query `active <metrics-file> <run-id>`. If a
single record exists from an interrupted finalization and its snapshot matches
the current evidence, adopt that record and its timestamp into report and state.
If it differs, stop for repair. The helper enforces revision 1 for the first
versioned record and exactly `max(existing revision) + 1` thereafter.

**Append the metrics record last, after the apply step finishes.** Use the
helper rather than raw redirection, so the same `record_id` and same content are
a no-op while conflicting content or a second active record fails:

```bash
bash references/scripts/retrospective-ledger.sh append-metrics-once \
  .specs/pipeline-metrics.jsonl "$line"
```

On a completed-run resume, call `supersede-once` before changing state. The
stable event id is `supersede:<record-id>:run_resumed`. A legacy line without
`record_type` remains readable as a metrics record with a synthetic line id.

## Step 3: retrospective.md

Write to `.specs/{feature}/retrospective.md`:

```markdown
# Retrospective - {feature} ({run_id})
type: retrospective
state_snapshot: {one-line canonical JSON object, exactly matching state and metrics}

## Execution Summary
Mode / phases traversed / PR URL / draft or ready.

## Failure Breakdown
| blocker_category | count | phase(s) | example |

## Stalls and Arbitrations
Per arbitration: signal (S1/S2/S3/S4) / decision (continue|swap|restructure|draft) / result.

## Improvement Proposals
### P-01: {target file} (Tier 1)
- Rationale: (which failure-breakdown row this came from, with the count)
- Change: (before/after summary)
### P-02: {target file} (Tier 2)
- ...

## Observations (not promoted to proposals)
Findings without frequency backing; recorded, not acted on.
```

Rules:
- `type: retrospective` header is mandatory.
- Exactly one `state_snapshot:` line is mandatory. It contains valid one-line
  JSON and exactly matches `state.retrospective.snapshot`.
- Every proposal names a target file and a Tier (Tier judgment itself is in
  `improve-apply.md`). The Tier here is the proposer's classification;
  `improve-apply.md` re-verifies it against the canonical path before applying.
- Every proposal's Rationale points at a specific failure-breakdown row and its
  count. No count → it belongs under Observations, not Proposals (the
  report is driven by tallies, not free-form impressions).

## Step 4: Previous-Run Comparison

Read the previous **active** metrics record before appending the current one:

```bash
bash references/scripts/retrospective-ledger.sh list-active \
  .specs/pipeline-metrics.jsonl | tail -n 1
```

The selector excludes every superseded record and rejects multiple active
records for one `run_id`. Never compare against the physical last JSONL line: it
may be a supersede event or an obsolete metrics revision. Compare the selected
record on the shared metrics:

- `rounds_spec` / `rounds_eval`: higher than last run = more churn.
- `blocker_categories`: a category whose count rose = regression in that area.
- `stalls`: more stalls = worse convergence.

Record the comparison verdict (better / worse / mixed, per metric) in
`retrospective.md`. Because features and difficulty differ run to run, a single
worse comparison is **not** by itself a reason to revert — the automatic-revert
condition ("same skill, same-family regression across two consecutive runs")
lives in `improve-apply.md`. Retrospective only records the comparison; it does
not decide the revert.

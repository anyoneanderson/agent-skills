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

## Step 2: pipeline-metrics.jsonl (composed here, appended last)

One repository-wide history file, `.specs/pipeline-metrics.jsonl` (JSON Lines),
one line per run:

```json
{"feature":"user-auth","run_id":"2026-07-05T09:00:00Z-a1b2","mode":"auto","rounds_spec":3,"rounds_eval":2,"stalls":1,"blocker_categories":{"malformed_output":3,"timeout":1},"applied_improvements":["P-01"],"ts":"2026-07-05T09:00:00Z"}
```

| Field | Meaning |
|-------|---------|
| `feature` / `run_id` / `mode` | Run identity |
| `rounds_spec` / `rounds_eval` | Round counts for the two loops |
| `stalls` | Number of arbitration entries this run |
| `blocker_categories` | Category → count map (from Step 1) |
| `applied_improvements` | Proposal ids actually auto-applied this run (from the `improve-apply.md` apply step; `[]` if nothing was applied or the run degraded) |
| `ts` | ISO 8601 timestamp |

**Append the line last, after the apply step finishes** — not during
aggregation. JSON Lines is append-only, so a line written before `improve-apply.md`
runs could never record `applied_improvements`. Compose the metrics values from
Step 1 here, hold them, and append once the applied set is known (which is `[]`
when nothing was applied or the run degraded to Issue-only or did not reach pr):

```bash
printf '%s\n' "$line" >> .specs/pipeline-metrics.jsonl
```

## Step 3: retrospective.md

Write to `.specs/{feature}/retrospective.md`:

```markdown
# Retrospective - {feature} ({run_id})
type: retrospective

## Execution Summary
Mode / phases traversed / PR URL / draft or ready.

## Failure Breakdown
| blocker_category | count | phase(s) | example |

## Stalls and Arbitrations
Per arbitration: signal (S1/S2/S3) / decision (continue|swap|draft) / result.

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
- Every proposal names a target file and a Tier (Tier judgment itself is in
  `improve-apply.md`). The Tier here is the proposer's classification;
  `improve-apply.md` re-verifies it against the canonical path before applying.
- Every proposal's Rationale points at a specific failure-breakdown row and its
  count. No count → it belongs under Observations, not Proposals (the
  report is driven by tallies, not free-form impressions).

## Step 4: Previous-Run Comparison

Read the previous line of `pipeline-metrics.jsonl` (the last line before the one
just appended) and compare on the shared metrics:

- `rounds_spec` / `rounds_eval`: higher than last run = more churn.
- `blocker_categories`: a category whose count rose = regression in that area.
- `stalls`: more stalls = worse convergence.

Record the comparison verdict (better / worse / mixed, per metric) in
`retrospective.md`. Because features and difficulty differ run to run, a single
worse comparison is **not** by itself a reason to revert — the automatic-revert
condition ("same skill, same-family regression across two consecutive runs")
lives in `improve-apply.md`. Retrospective only records the comparison; it does
not decide the revert.

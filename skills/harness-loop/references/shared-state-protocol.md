# Shared-read / Isolated-write Protocol

During a sprint, multiple agents (Planner, Generator, Evaluator) plus
the Orchestrator all read the same `shared_state.md` ledger, but only
the Orchestrator writes to it. Every other agent writes to a private
`feedback/{role}-{iter}.md` file. This keeps the ledger race-free and
auditable per-iteration.

## File layout (per sprint)

```
.harness/<epic>/sprints/sprint-<n>-<feature>/
├── contract.md                     ← frozen after negotiation (Orchestrator writes, all read)
├── shared_state.md                 ← Orchestrator only writes; all agents read
├── feedback/
│   ├── planner-ruling.md           ← Planner only writes (negotiation stalemate)
│   ├── planner-ruling-impl-<iter>.md  ← Planner only writes (mid-impl replan)
│   ├── planner-<iter>.md           ← Planner only writes (rare: replan requests)
│   ├── generator-neg-<round>.md    ← Generator only writes (negotiation rounds)
│   ├── generator-<iter>.md         ← Generator only writes (impl iterations)
│   ├── evaluator-neg-<round>.md    ← Evaluator only writes (negotiation rounds)
│   └── evaluator-<iter>.md         ← Evaluator only writes (impl iterations)
└── evidence/                       ← Evaluator writes run artefacts; all read
```

Negotiation rounds are keyed by `<round>` (1..3) and use the explicit
`-neg-` filename prefix. Implementation iterations are keyed by
`<iter>` (1..max_iterations) and keep the plain role filename. The two
series are therefore distinguishable both by `contract.status` and by
filename alone.

Implementation inside harness-loop: keep both series in the same
directory. The Orchestrator can tell round from iter by either
`contract.status` or filename pattern (`*-neg-*` vs plain iteration
files).

## Write permissions (authoritative)

| Path | Orchestrator | Planner | Generator | Evaluator |
|---|---|---|---|---|
| `contract.md` frontmatter | ✅ freeze only | ❌ | ❌ | ❌ |
| `contract.md` `generator_backend` field | ✅ copy from roadmap (contract-draft) / negotiation outcome / ruling | ✅ via `ruling` phase only | ❌ (may propose change in `feedback/generator-neg-*.md`) | ❌ (may propose change in `feedback/evaluator-neg-*.md`) |
| `contract.md` Negotiation Log | ✅ copy from feedback | ❌ | ❌ | ❌ |
| `shared_state.md` | ✅ sole writer | ❌ | ❌ | ❌ |
| `feedback/planner-*.md` | ❌ | ✅ | ❌ | ❌ |
| `feedback/generator-*.md` | ❌ | ❌ | ✅ | ❌ |
| `feedback/evaluator-*.md` | ❌ | ❌ | ❌ | ✅ |
| `evidence/*` | ❌ | ❌ | ❌ | ✅ |
| `_state.json` | ✅ sole writer | ❌ | ❌ | ❌ |
| `metrics.jsonl` | ✅ sole writer | ❌ | ❌ | ❌ |
| `progress.md` | ✅ direct append | via PostToolUse hook | via PostToolUse hook | via PostToolUse hook |

`progress.md` is the one shared log where agent writes reach via the
`.harness/scripts/progress-append.sh` hook, not direct file
manipulation. The hook path is race-safe because `>>` appends are
atomic for small writes on POSIX filesystems.

Validator and dispatch scripts never write `_state.json` directly.
Orchestrator exclusively owns `pending_human`,
`consecutive_validator_violations`, `halt_reason`, and every other
state transition.

## `shared_state.md` section ownership

The template already carries section comments declaring ownership. In
summary:

| Section | Populated when | Orchestrator action |
|---|---|---|
| `## Plan` | On sprint entry | Copy from contract.md `goal` + `acceptance_scenarios` |
| `## Contract` | On contract freeze | Write `sprint-<n>-contract.md @ <SHA>` |
| `## Negotiation` | After each round | Append 2 lines (G + E) per round; ruling line on stalemate |
| `## WorkLog` | After each Generator turn | Append 1 line: iter, agent, commit, summary pointer |
| `## Evaluation` | After each Evaluator turn | Append 1 line: iter, verdict, per-axis scores, evidence pointer |
| `## Decisions` | On state transitions | Append 1 line: decision type, reason, commit SHA |

Every append is a new line, never an in-place edit. The canonical
append implementation:

```bash
# Pseudocode; real Orchestrator path uses jq-driven values
printf '\n- %s\n' "$line" >> shared_state.md
```

`shared_state.md` must remain human-readable. Agents read it for
context — noise in the ledger costs them tokens.

## Read patterns

Every agent, at turn start, reads:

1. `contract.md` — ground truth for the sprint
2. `shared_state.md` — ledger summary of everything so far
3. The immediately prior counterpart's `feedback/*.md` file (if any)
4. `../../progress.md` tail (Boot Sequence)
5. `../../_state.json` (Boot Sequence)

Agents do NOT read other agents' historical feedback files by default.
If the Orchestrator wants a specific old file in context, it stitches
it into the prompt. Keeping feedback files out of default reads keeps
per-turn token budgets stable across long sprints.

## Atomic write discipline (Orchestrator side)

Three files demand atomicity:

1. **`_state.json`** — every write is:
   ```bash
   jq '<delta>' .harness/_state.json > .harness/_state.json.tmp
   mv .harness/_state.json.tmp .harness/_state.json
   ```
   `mv` within the same filesystem is atomic on macOS and Linux.

2. **`metrics.jsonl`** — always append a single JSON line; never edit.
   A partially-written line on crash is acceptable (tail reader skips
   invalid JSON).

3. **`shared_state.md`** — each append is one `printf` call. Readers
   tolerate the final line arriving mid-read because the parser is
   line-oriented.

The append-only discipline means recovery after crash is: `git
checkout -- path/to/file` restores the last committed state, and the
Orchestrator rebuilds from `_state.json` + the feedback files it can
see on disk.

## `deliverable_checks` schema (foundation sprint)

Generator-authored reports for `type: foundation` sprints append a
`deliverable_checks` object to `feedback/generator-<iter>-report.json`.
This is the machine-readable mirror of the narrative in
`feedback/generator-<iter>.md` and drives `harness-loop`'s
`feedback/verification-<iter>.md` assembly.

```json
{
  "status": "done" | "blocked",
  "touchedFiles": ["path/relative/to/repo-root", "..."],
  "summary": "<one-line summary>",
  "blocker": null | "<reason string when status=blocked>",
  "deliverable_checks": {
    "<deliverable_key>": {
      "status": "pass" | "fail",
      "evidence": "<short free-text, must cite concrete file/commit/log>"
    },
    "...": { "..." }
  }
}
```

Rules:

- **Keys MUST match `contract.deliverables` exactly.** Orchestrator will
  cross-check at ingest and emit a WARN on mismatch (extra keys from the
  Generator are dropped; missing keys are auto-set to
  `{status: "fail", evidence: "not reported by Generator"}`).
- **Per-key `status`** is Generator's self-report. Orchestrator treats it
  as a *hypothesis* that `foundation-readiness.sh --check <key>` will
  confirm — the probe's machine verdict overrides the Generator's claim
  when they disagree (and a progress.md WARN line is written).
- **Evidence** is short free-text; ≤ 160 chars preferred. Typical forms:
  - `package.json + pnpm-lock.yaml committed`
  - `curl http://localhost:3000/ returned 200 at 2026-04-20T12:34Z`
  - `playwright test --list: 3 tests`
  - `prisma migrate dev: 20260420_init applied`
  - `SETUP.md sections: 1..7 (Prerequisites, GCP OAuth, ...)`
- **`touchedFiles`** is the authoritative dirty-file list. Orchestrator
  uses it as the fallback source; skipping it forces the
  Orchestrator to compute `git ls-files -m -o --exclude-standard` and
  log a WARN.

### Orchestrator assembly (into verification-<iter>.md)

After reading `deliverable_checks` from Generator's report.json,
Orchestrator runs `foundation-readiness.sh --check <key>` for each key,
then writes a markdown table to `feedback/verification-<iter>.md`:

```markdown
---
role: orchestrator
sprint: 0
iter: <iter>
ts: <ISO-8601-UTC>
---

| Deliverable | Generator claim | Probe verdict | Evidence | Agreement |
|---|---|---|---|---|
| package_manifest | pass | pass (ok) | package.json + pnpm-lock.yaml committed | ✅ |
| runtime_boots | pass | pass (ok) | curl / returned 200 | ✅ |
| test_runner_configured | pass | pass (ok) | playwright --list: 3 tests | ✅ |
| env_example_committed | pass | pass (ok) | .env.example keys: 6/6 | ✅ |
| external_setup_doc | pass | pass (ok) | docs/SETUP.md sections 1-7 | ✅ |
| dev_db_available | pass | pass (ok) | docker-compose.yml present | ✅ |

Summary: 6/6 deliverables pass.
```

Disagreement rows (Generator `pass` + probe `missing`, or vice versa)
are flagged with `⚠️ disagree` in the Agreement column and require
operator attention at the attestation gate.

### Why per-deliverable structure

- **Replay**: the same report.json can be re-ingested to re-run probes
  after a fix without requiring a new Generator invocation
- **Diff-friendly**: retry iterations produce a comparable table across
  iters, making it trivial to see which deliverables were fixed vs
  regressed
- **Machine vs human verdicts are separable**: the probe provides an
  independent machine judgment; Generator's claim is still captured in
  case the probe itself has bugs

## Mid-impl replan escalation (Layer 1 agent-request)

When a Generator or Evaluator detects that the frozen contract is not
satisfiable by further implementation (e.g., an acceptance threshold is
physically incompatible with the available tools or model), either can
attach an optional `request_planner_escalation` block to their
`feedback/{role}-<iter>-report.json`. The Orchestrator reads this block
during Step 6 after the Evaluator turn and, if present, routes the
sprint through the mid-impl replan sub-protocol
(see [negotiation-protocol.md](negotiation-protocol.md#mid-impl-replan)).

```json
{
  "status": "done",
  "touchedFiles": ["..."],
  "summary": "...",
  "blocker": null,
  "request_planner_escalation": {
    "reason": "contract_debt" | "test_infeasible" | "scope_mismatch",
    "evidence_refs": ["evidence/iter-<n>/planner-escalation.json", "..."],
    "proposed_change": "<one-line summary of the proposed contract delta>",
    "disputed_clauses": ["acceptance_scenarios[1].then", "rubric[0].threshold"],
    "generator_can_solve_alone": false
  }
}
```

Rules:

- The block is **optional**. Omit it when the agent believes the failing
  axes are solvable by further implementation (the common case).
- Setting the block is a structured request, not a self-approval. The
  Orchestrator may still reject the escalation (e.g., `max_per_sprint`
  exhausted) and fall back to the normal `rubric_stagnation_count` path.
- Both Generator and Evaluator can set it. Orchestrator treats any
  single-sided request as sufficient to evaluate the trigger; the
  heuristic of whether to dispatch Planner is documented in
  [negotiation-protocol.md](negotiation-protocol.md#mid-impl-replan).
- `disputed_clauses` must name concrete `contract.md` paths so the
  Planner ruling has a precise target.

## Evaluator compliance report schema

During implementation iterations, Evaluator must also write
`feedback/evaluator-<iter>-report.json`. This is not a substitute for the
narrative file; it is the canonical machine-readable input the Orchestrator
validates in Step 6 to verify phase execution and project quality-gate
results.

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
      "cmd": "command as executed",
      "exit": 0,
      "log": "evidence/iter-<n>/quality-gate-command.log",
      "summary": "short result summary"
    }
  ],
  "evidence_refs": ["evidence/iter-<n>/quality-gate-command.log"],
  "forced_failure_reason": null
}
```

Orchestrator validation rules:

- JSON parse failure or missing required fields force fail with
  `forced_failure_reason = "evaluator-report-invalid"`.
- Missing any of `"1"`, `"2"`, `"2.5"`, `"3"`, or `"4"` in
  `phases_executed` forces fail with `phase-<n>-skipped`.
- `phase_3_evidence_status` is validator-owned and records
  `"present"`, `"missing"`, or `"n/a"` independently from the original
  `phases_executed` claim. Validator scripts must not destructively
  remove phases from `phases_executed`.
- `validator_violations` is validator-owned. Once present, it is reused
  on re-run for idempotency; backward-compatible forced reason fields
  are derived from its comma-joined tokens.
- `validator_invoked` and `schema_version` are validator-owned and are
  written by validator scripts, not by agents.
- If `phase_2_5_quality_gate_found != false` and
  `phase_2_5_commands` is empty, force fail with
  `phase-2.5-commands-missing`.
- Any non-zero `phase_2_5_commands[].exit` forces fail with
  `project-quality-gate-failed`.
- On forced failure, cap Functionality below its pass threshold and do
  not advance to PR creation.

## Contract revision audit trail

Every mid-impl replan that applies a Planner ruling appends one entry to
`_state.json.contract_revisions[]` and one line to
`shared_state.md/Decisions`:

```json
{
  "ts": "<ISO-8601-UTC>",
  "triggered_by": "negotiation" | "layer1" | "layer2" | "layer3",
  "at_iter": 0 | <iter>,
  "planner_ruling_file": "feedback/planner-ruling-impl-<iter>.md" | null,
  "planner_ruling_commit": "<SHA>" | null,
  "contract_diff": {
    "before": {"acceptance_scenarios[1].then": "..."},
    "after":  {"acceptance_scenarios[1].then": "..."}
  }
}
```

`triggered_by` enum (matches the mid-impl-replan trigger taxonomy):

- `negotiation` — Negotiation round で Generator/Evaluator が合意して確定
  (`at_iter: 0`、Planner ruling 経由ではないので `planner_ruling_*` は null)
- `layer1` — agent-request (Generator/Evaluator が
  `request_planner_escalation` で escalate)
- `layer2` — axis-stagnation (`rubric_stagnation_count` トリガー)
- `layer3` — supervisor-replan (`/harness-loop --replan-contract` 等の
  人手 escalate)

Example: `generator_backend` change confirmed during Negotiation:

```json
{
  "ts": "2026-04-30T08:42:11Z",
  "triggered_by": "negotiation",
  "at_iter": 0,
  "planner_ruling_file": null,
  "planner_ruling_commit": null,
  "contract_diff": {
    "before": {"generator_backend": "codex_cli"},
    "after":  {"generator_backend": "claude"}
  }
}
```

The same schema records `generator_backend` changes triggered by
mid-impl-replan (Planner ruling) — fill `triggered_by: "layer1" | "layer2"
| "layer3"` and `planner_ruling_file` / `planner_ruling_commit` instead.

`metrics.jsonl` gains a companion record (same event):

```jsonl
{"event":"mid_impl_replan","ts":"...","sprint":1,"iter":N,"triggered_by":"layer1","planner_ruling_commit":"..."}
```

These audit fields let `harness-rules-update` and later epic postmortems
reason about how often contracts are re-negotiated mid-impl and which
axes drive the churn.

## Feedback file schema (generic)

All `feedback/{role}-<n>.md` share a common shape:

```markdown
---
role: <planner|generator|evaluator>
iter: <n>              # or round: <r> during negotiation
sprint: <sprint-number>
ts: <ISO-8601-UTC>
# optional, role-specific: see negotiation-protocol.md
---

## Summary

<one paragraph, 1–3 sentences>

## Details

<freeform markdown; may include code, logs, evidence pointers>

## Next action

<what this agent expects to happen next; may be empty>
```

The Orchestrator reads `Summary` to build `shared_state.md` entries.
Details and evidence pointers stay in the feedback file for audit.

## Conflict cases and remediation

| Case | Remediation |
|---|---|
| Two agents wrote to the same `feedback/*` path in the same iter (bug) | Orchestrator renames the later file to `*.dup.<ts>.md`, logs to progress.md |
| Agent edits `shared_state.md` directly | `git status` shows the change at Step 7 commit; Orchestrator reverts the edit (`git checkout --`) and logs |
| Agent writes `_state.json` | Forbidden. Orchestrator overwrites with a correct value from memory + feedback file contents; logs. If `_state.json` was corrupted, halt and surface |
| Evaluator references missing evidence | Treat as test infrastructure failure: evaluator verdict becomes `fail` with `reason: evidence-missing`; Principal Skinner's stagnation logic catches repeated cases |

## Why Shared-read / Isolated-write

- **Race elimination**: multiple agents writing the same file under
  concurrent sub-agent dispatch causes torn writes; isolating writes
  removes the class entirely.
- **Per-agent audit**: reviewing "what did the Generator think on
  iter-5" is `cat feedback/generator-5.md` — one file, one author.
- **Summary vs detail separation**: the ledger stays short (one line
  per event) while feedback files hold the deliberation. Future agents
  paying only the ledger cost see O(sprint events) tokens, not
  O(all agent output).
- **Replay**: an auditor can reconstruct any iteration by reading
  contract.md + shared_state.md + feedback/*-<iter>.md in order.

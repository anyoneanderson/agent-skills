# Negotiation Protocol

Every sprint begins with a bounded negotiation between Generator and
Evaluator over the contract rubric, thresholds, and `max_iterations`.
After three rounds without agreement the Planner forces a ruling.

## Participants and write permissions

| Agent | Reads | Writes during negotiation |
|---|---|---|
| Generator | `contract.md`, `shared_state.md`, `feedback/evaluator-neg-<r>.md` | `feedback/generator-neg-<r>.md` |
| Evaluator | `contract.md`, `shared_state.md`, `feedback/generator-neg-<r>.md` | `feedback/evaluator-neg-<r>.md` |
| Planner | everything above | `feedback/planner-ruling.md`, then `contract.md` ruling section |
| Orchestrator (harness-loop) | everything | `shared_state.md/Negotiation`, `contract.md` frontmatter freeze |

No agent writes `shared_state.md`. The Orchestrator copies round
summaries into the ledger so the sprint has a single canonical audit
trail (see [shared-state-protocol.md](shared-state-protocol.md)).

## Round structure

One round = one Generator turn followed by one Evaluator turn. Rounds
are numbered from 1. The cap is `contract.max_negotiation_rounds`
(default 3, overridable in `_config.yml`). Exception: when the
Generator signals `accept`, the round resolves immediately and the
Evaluator turn is skipped; the Evaluator's most recent proposal is
treated as the accepted contract delta.

### Round N schema

Each side produces a proposal document. The Orchestrator dispatches
them sequentially, not in parallel — the second speaker must see the
first's proposal.

**Generator round file** (`feedback/generator-neg-<r>.md`):

```yaml
---
round: <r>
role: generator
ts: <ISO-8601-UTC>
---

## Proposed contract delta

<!--
  Only the fields the Generator wants to change from the draft.
  Use `unchanged` or omit if none.
-->

rubric:
  - axis: Functionality
    threshold: 0.95   # was 1.0
    reason: "Flaky login redirect; proposes retry harness instead of 1.0"
max_iterations: 8     # unchanged

## Trade-offs acknowledged

<!--
  What the Generator concedes in exchange for the delta.
-->

- Will add explicit retry + a11y snapshot diffing under Craft

## Open risks

<!--
  Things the Generator is unsure about; inputs Evaluator can help resolve.
-->

- Uncertain whether Playwright a11y snapshot is deterministic on login
  modal; would like Evaluator's opinion

## Decision

`accept` | `counter` | `escalate`
```

**Evaluator round file** (`feedback/evaluator-neg-<r>.md`): same schema,
`role: evaluator`.

Agreement signals:

- `accept` — explicitly accepts the other side's most recent proposal
- `counter` — still negotiating; counter-proposal included above
- `escalate` — cannot agree within the round; use to force Planner
  attention if the cap is reached

### Round outcome matrix

| Generator signal | Evaluator signal | Result |
|---|---|---|
| `accept` | skipped | Evaluator's last proposal wins; exit negotiation |
| anything | `accept` | Generator's last proposal wins; exit negotiation |
| `counter` | `counter` | Round + 1 (if room), else Planner ruling |
| `escalate` | anything | Round + 1 (if room), else Planner ruling |
| anything | `escalate` | Round + 1 (if room), else Planner ruling |

When the Generator signals `accept`, the round resolves immediately:
the Evaluator does not speak again in that round, and the Evaluator's
most recent proposal is written into the contract. This is the explicit
exception to the default "Generator turn followed by Evaluator turn"
symmetry above.

When both sides `accept` the same proposal in the same round, the
Orchestrator treats that as mutual agreement.

### Orchestrator summary lines

After each round the Orchestrator appends **two** lines to
`shared_state.md/Negotiation` — one per speaker:

```
- [<ts>] round=<r> agent=generator signal=<accept|counter|escalate> delta=<short phrase> file=feedback/generator-neg-<r>.md
- [<ts>] round=<r> agent=evaluator signal=<accept|counter|escalate> delta=<short phrase> file=feedback/evaluator-neg-<r>.md
```

And one `progress.md` line per round end:

```
[<ts>] negotiation: round=<r> generator=<signal> evaluator=<signal>
```

## 3-round cap and Planner ruling

If `round == max_negotiation_rounds` and neither side has signalled
`accept`, the Orchestrator dispatches the Planner with the full
negotiation packet and asks for a binding ruling.

### Planner input packet

The Orchestrator passes the Planner a single prompt containing:

1. `contract.md` current draft (frontmatter + acceptance scenarios)
2. Each `feedback/generator-neg-<r>.md` (rounds 1..3)
3. Each `feedback/evaluator-neg-<r>.md` (rounds 1..3)
4. The relevant rubric preset
   (`../../harness-init/references/rubric-presets.md#<project-type>`)
5. A fixed instruction:

```
You are the Planner ruling on a stalled negotiation. Write
feedback/planner-ruling.md with the final contract delta. Reasoned,
binding, one rubric per axis. Do not propose further negotiation.
```

### Planner ruling file (`feedback/planner-ruling.md`)

```yaml
---
role: planner
ts: <ISO-8601-UTC>
---

## Ruling

rubric:
  - axis: Functionality
    weight: high
    threshold: 1.0
  - axis: Craft
    weight: std
    threshold: 0.8    # lifted from proposed 0.7 given the redirect risk
  - axis: Design
    weight: std
    threshold: 0.7
  - axis: Originality
    weight: low
    threshold: 0.5
max_iterations: 10     # lifted from 8 to absorb retry work

## Reasoning

Generator's retry harness argument stands; Evaluator's request for a
higher Craft bar is accepted as a trade.

## Applies to

sprint: <N>
feature: <feature-name>
```

### Contract freeze after ruling

The Orchestrator:

1. Writes the ruling fields into `contract.md` frontmatter
2. Copies the Planner `## Ruling` section into the contract's
   `## Negotiation Log > ### Ruling` section, verbatim
3. Sets `contract.status: active`
4. Commits: `git commit -m "harness-loop: sprint-<n> Planner ruling"`
5. Appends `progress.md`:
   ```
   [<ts>] decision: sprint-<n> negotiation ruled by Planner (rounds=3)
   ```

## Anti-patterns (reject during negotiation)

- **Code proposals in negotiation files** — only rubric / threshold /
  `max_iterations` / scenario count are negotiable. Implementation
  choices belong in Step 6 of the SKILL flow.
- **Rubric axis invention** — stick to the preset for the project type;
  v1 does not add custom axes mid-epic.
- **Threshold below 0.5 on Functionality** — will trip Principal Skinner
  rubric-stagnation without progress. Reject and ask for scope split.
- **Negotiating `max_cost_usd` / `max_wall_time_sec`** — those are
  `_config.yml` Principal Skinner caps, not sprint-level. Edit via
  `/harness-init` reconfigure.
- **Missing `Decision` line** — a proposal without a `Decision` line is
  treated as `counter` but logged as malformed.

## Resume behaviour

On skill restart mid-negotiation the Orchestrator reads
`_state.json.phase == "negotiation"` and the highest-numbered
`feedback/{generator-neg|evaluator-neg}-<r>.md` pair. The next action is the
other role's turn, or Round N+1 if both produced round N, or the
Planner ruling if N equals the cap.

All round files are immutable once written — no in-place edits. If a
round needs revision, increment the round number rather than
overwriting (append-only discipline matches progress.md).

## Mid-impl replan

Once `contract.status: active`, the implementation loop in Step 6 can
still detect that the frozen contract is not satisfiable by further
implementation. Three triggers can cause the Orchestrator to re-enter a
bounded Planner ruling without resetting the iteration counter:

- **Layer 1 — agent request**: Generator or Evaluator sets
  `request_planner_escalation` in their `feedback/{role}-<iter>-report.json`
  (see [shared-state-protocol.md](shared-state-protocol.md#mid-impl-replan-escalation-layer-1-agent-request)).
- **Layer 2 — axis stagnation**: the Orchestrator detects that a failing
  axis has been in a tight band for `min_consecutive_signals` iterations
  (`max - min < axis_band_threshold` from
  `_config.yml.mid_impl_replan`). When this fires, the Orchestrator
  reads the latest `generator-<iter>.md` + `evaluator-<iter>.md` and
  makes a semantic judgment on whether the stagnation reflects a
  contract debt or a solvable implementation gap. Only a contract debt
  judgment triggers the replan.
- **Layer 3 — supervisor manual**: the operator runs
  `/harness-loop --replan-contract`. This is the escape hatch when the
  Layer 1/2 gates are too conservative.

### Trigger gating

- `_config.yml.mid_impl_replan.enabled` must be `true` (default).
- The sprint's mid-impl replan counter (`_state.json.mid_impl_replan_count`)
  must be below `max_per_sprint` (default `2`).
- When Layer 1 fires with contradicting requests from Generator and
  Evaluator (one asks to relax, the other to hold), the Orchestrator
  prefers Evaluator's view and logs the conflict for audit.

If any gate blocks the trigger, the Orchestrator records a progress.md
line:
`[<ts>] decision: mid-impl replan gated (reason=<budget|disabled|conflict>) at iter=<n>`
and allows the normal `rubric_stagnation_count` path to govern the run.

### Dispatch

The Orchestrator dispatches the Planner with:

1. `contract.md` in its current frozen form
2. All `feedback/evaluator-<k>.md` since the contract freeze (k=1..iter)
3. All `feedback/generator-<k>.md` since the contract freeze
4. The triggering escalation block (Layer 1) or stagnation summary
   (Layer 2)
5. A cross-iter axis trajectory table
6. The fixed instruction:

```
You are the Planner arbitrating a mid-impl replan request. Write
feedback/planner-ruling-impl-<iter>.md with a bounded contract delta.
You may modify rubric thresholds, acceptance_scenarios, and
max_iterations, but keep all other contract fields intact. Do not
propose further negotiation rounds.
```

### Planner ruling file (`feedback/planner-ruling-impl-<iter>.md`)

```yaml
---
role: planner
phase: mid-impl-replan
at_iter: <iter>
triggered_by: layer1 | layer2 | layer3
ts: <ISO-8601-UTC>
---

## Proposed action

`accept | relax | reject | recommend_abort`

## Delta

<!--
  Only the contract fields that change. Use explicit before/after so the
  Orchestrator's automated application is unambiguous.
-->

rubric:
  - axis: Functionality
    threshold:
      before: 1.0
      after: 1.0            # unchanged
acceptance_scenarios:
  - id: AS-2
    then:
      before: "1〜10 秒以内に最初の token 到達"
      after:  "最初の model-produced text chunk が到達し totalReads >= 2, spanMs >= 150ms..."
max_iterations:
  before: 10
  after: 12                 # +2 iter slack

## Reasoning

<one-paragraph rationale citing the triggering evidence>

## Applies to

sprint: <N>
feature: <feature-name>
```

### Orchestrator application

When Planner returns `accept` or `relax`:

1. Apply the delta to `contract.md` frontmatter (only the named fields).
   Contract `status` remains `active`; contract file is NOT re-frozen.
2. Append one entry to `_state.json.contract_revisions[]` per the audit
   schema in [shared-state-protocol.md](shared-state-protocol.md#contract-revision-audit-trail).
3. Append one line to `shared_state.md/Decisions`:
   `[<ts>] decision: mid-impl replan applied (trigger=<layer>) at iter=<n> ruling=<sha>`.
4. Append one line to `progress.md`:
   `[<ts>] decision: sprint-<n> mid-impl replan applied trigger=<layer> iter=<n>`.
5. Append one `metrics.jsonl` record per
   [shared-state-protocol.md](shared-state-protocol.md#contract-revision-audit-trail).
6. `_state.json.mid_impl_replan_count += 1`.
7. **`_state.json.rubric_stagnation_count = 0`** — fresh start for the
   new contract, to avoid Principal Skinner firing on pre-replan history.
8. Keep `_state.json.iteration` as-is (no reset).
9. `git add` the modified `contract.md` + `feedback/planner-ruling-impl-<iter>.md`
   and commit:
   `harness-loop: sprint-<n> mid-impl replan iter-<iter>`.
10. Continue Step 6 from the next iteration with the new contract in
    effect.

When Planner returns `reject`: append the ruling to
`feedback/planner-ruling-impl-<iter>.md` with the reject rationale, log
one `progress.md` line, and continue Step 6 without contract changes.
The next Generator turn receives the ruling as context so the
"self-solve" instruction is explicit.

When Planner returns `recommend_abort`: set `_state.json.pending_human
= true`, halt the wrapper, and surface the ruling to the supervisor.

### Why no iteration reset

Resetting `iteration = 0` (as `--replan-current-sprint` does) discards
the implementation work done before the contract debt was diagnosed.
Mid-impl replan preserves it: the existing git history of iter-1..N
stays intact, and the next Generator picks up with a slightly-revised
contract instead of starting from a blank slate. Costs stay amortised.

### Interaction with Principal Skinner

- `rubric_stagnation_count` is reset on a successful mid-impl replan so
  the new contract gets a fair run.
- `iteration >= max_iterations` still fires if Planner raised
  `max_iterations` too conservatively — guard against unbounded churn.
- `cumulative_cost_usd` / `max_wall_time_sec` are NOT touched by the
  replan; sprint-level budget caps remain authoritative.

## Testing recipe

```bash
# Dry-run: ask Generator to counter, then Evaluator to accept
claude -p --agent generator "counter round 1 for sprint-1/contract.md"
# → writes feedback/generator-neg-1.md with signal=counter

claude -p --agent evaluator "review feedback/generator-neg-1.md and signal"
# → writes feedback/evaluator-neg-1.md with signal=accept

# Orchestrator freezes contract
jq '.phase="impl"' .harness/_state.json > /tmp/s && mv /tmp/s .harness/_state.json
```

The test succeeds when `contract.md.status == "active"`, the
`Negotiation Log / Round 1` section in `contract.md` has both messages,
and `shared_state.md/Negotiation` has both orchestrator summary lines.

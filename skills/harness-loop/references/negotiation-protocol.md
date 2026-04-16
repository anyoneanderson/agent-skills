# Negotiation Protocol

Every sprint begins with a bounded negotiation between Generator and
Evaluator over the contract rubric, thresholds, and `max_iterations`.
After three rounds without agreement the Planner forces a ruling.

## Participants and write permissions

| Agent | Reads | Writes during negotiation |
|---|---|---|
| Generator | `contract.md`, `shared_state.md`, `feedback/evaluator-<r>.md` | `feedback/generator-<r>.md` |
| Evaluator | `contract.md`, `shared_state.md`, `feedback/generator-<r>.md` | `feedback/evaluator-<r>.md` |
| Planner | everything above | `feedback/planner-ruling.md`, then `contract.md` ruling section |
| Orchestrator (harness-loop) | everything | `shared_state.md/Negotiation`, `contract.md` frontmatter freeze |

No agent writes `shared_state.md`. The Orchestrator copies round
summaries into the ledger so the sprint has a single canonical audit
trail (see [shared-state-protocol.md](shared-state-protocol.md)).

## Round structure

One round = one Generator turn followed by one Evaluator turn. Rounds
are numbered from 1. The cap is `contract.max_negotiation_rounds`
(default 3, overridable in `_config.yml`).

### Round N schema

Each side produces a proposal document. The Orchestrator dispatches
them sequentially, not in parallel — the second speaker must see the
first's proposal.

**Generator round file** (`feedback/generator-<r>.md`):

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

## Agreement signal

`propose` | `accept` | `reject`
```

**Evaluator round file** (`feedback/evaluator-<r>.md`): same schema,
`role: evaluator`.

Agreement signals:

- `propose` — still negotiating; counter-proposal included above
- `accept` — explicitly accepts the other side's most recent proposal
- `reject` — rejects without counter; use only to force Planner ruling
  (rare; prefer `propose` so Round N+1 has material)

### Round outcome matrix

| Generator signal | Evaluator signal | Result |
|---|---|---|
| `accept` | anything | Evaluator's last proposal wins; exit negotiation |
| anything | `accept` | Generator's last proposal wins; exit negotiation |
| `propose` | `propose` | Round + 1 (if room), else Planner ruling |
| `reject` | anything | Round + 1 (if room), else Planner ruling |
| anything | `reject` | Round + 1 (if room), else Planner ruling |

When both sides `accept` the same proposal in the same round, the
Orchestrator treats that as mutual agreement.

### Orchestrator summary lines

After each round the Orchestrator appends **two** lines to
`shared_state.md/Negotiation` — one per speaker:

```
- [<ts>] round=<r> agent=generator signal=<propose|accept|reject> delta=<short phrase> file=feedback/generator-<r>.md
- [<ts>] round=<r> agent=evaluator signal=<propose|accept|reject> delta=<short phrase> file=feedback/evaluator-<r>.md
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
2. Each `feedback/generator-<r>.md` (rounds 1..3)
3. Each `feedback/evaluator-<r>.md` (rounds 1..3)
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
- **Unsigned `propose`** — a proposal without an `Agreement signal` line
  is treated as `propose` but logged as malformed.

## Resume behaviour

On skill restart mid-negotiation the Orchestrator reads
`_state.json.phase == "negotiation"` and the highest-numbered
`feedback/{generator|evaluator}-<r>.md` pair. The next action is the
other role's turn, or Round N+1 if both produced round N, or the
Planner ruling if N equals the cap.

All round files are immutable once written — no in-place edits. If a
round needs revision, increment the round number rather than
overwriting (append-only discipline matches progress.md).

## Testing recipe

```bash
# Dry-run: ask Generator to propose, then Evaluator to accept
claude -p --agent generator "propose round 1 for sprint-1/contract.md"
# → writes feedback/generator-1.md with signal=propose

claude -p --agent evaluator "review feedback/generator-1.md and signal"
# → writes feedback/evaluator-1.md with signal=accept

# Orchestrator freezes contract
jq '.phase="impl"' .harness/_state.json > /tmp/s && mv /tmp/s .harness/_state.json
```

The test succeeds when `contract.md.status == "active"`, the
`Negotiation Log / Round 1` section in `contract.md` has both messages,
and `shared_state.md/Negotiation` has both orchestrator summary lines.

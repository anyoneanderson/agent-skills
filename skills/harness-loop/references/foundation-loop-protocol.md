# Foundation-Sprint Loop Protocol

Runtime protocol `harness-loop` follows when the current sprint's
`contract.type == "foundation"`. The plan-side doctrine (when / why a
foundation-sprint is inserted, its schema, `generator_mode` values)
lives in
[../../harness-plan/references/foundation-sprint-guide.md](../../harness-plan/references/foundation-sprint-guide.md).
This file covers only how the loop executes one.

## When it fires

Step 3 of SKILL.md reads `contract.md`. If its frontmatter has
`type: foundation`, skip Steps 4–7 (negotiation + G⇄E rubric iteration)
and follow this protocol. On completion resume at Step 8 (PR) and
Step 9 (sprint transition).

## Phase transitions

```
ready-for-loop
  └─ Step 3 (branch setup + contract load)
       └─ foundation-setup
            └─ [generator dispatch (≤1×) + readiness probe loop]
                 └─ foundation-attest          ← pending_human=true
                      ├─ Attest  → pr → Step 8
                      ├─ Fix     → foundation-setup (retry, cap 3)
                      └─ Abort   → aborted_reason set, halt
```

Both `foundation-setup` and `foundation-attest` are on the stop-guard
phase allowlist so the loop can pause for probes / human attestation
without tripping Principal Skinner.

## Protocol (steps)

```
1. Set _state.json.phase = "foundation-setup".

2. Interactive kickoff gate (mode == "interactive" only):
     Foundation scaffolding has outsized side effects — package
     installs, docker pulls, external credential files. Surface a
     confirmation before any dispatch:
       AskUserQuestion:
         "Foundation sprint kickoff. Generator will scaffold per
          contract (mode: <contract.generator_mode>). Proceed?"
         options: Proceed / Revise contract / Abort
     Non-interactive modes (continuous / autonomous-ralph / scheduled)
     skip this gate. On "Revise contract" → halt, surface the contract
     path, return to /harness-plan --replan. On "Abort" →
     aborted_reason = "foundation-kickoff-aborted".

3. If contract.generator_mode != "none":
     Render prompt-templates/generator-foundation.md per Step 3.5,
     substituting ONLY the declared placeholders ({{EPIC_NAME}} /
     {{SPRINT_NUMBER}} / {{SPRINT_FEATURE}} / {{ITERATION}}).
     Dispatch Generator ONCE. (Non-design rule applies — see SKILL.md
     §Orchestrator responsibility.)

4. For each key in contract.deliverables:
     run `.harness/scripts/foundation-readiness.sh --check <key>`
     record pass/fail + evidence into feedback/verification-1.md per
     the deliverable_checks schema (see
     [shared-state-protocol.md §deliverable_checks schema](shared-state-protocol.md)).

5. Append progress line:
     `[<ts>] foundation: pass=<N>/<M> deliverables=<list>`

6. Set _state.json.phase = "foundation-attest".
     Set _state.json.pending_human = true.
     AskUserQuestion:
       "Foundation deliverables verified (<N>/<M>). Attest complete?"
       options: Attest / Fix & retry / Abort

7. On Attest:
     Re-run `.harness/scripts/foundation-readiness.sh --epic <epic>`
     and write the JSON summary back to `_state.json.foundation_readiness`
     (preserving `verified_at` from the checker output).
     Set `_state.json.foundation_sprint_needed = false`.
     Then set `phase = "pr"` and `pending_human = false`.
     As the LAST durable write, set
     `_state.json.pending_worker_exit = true` so the autonomous-ralph
     stop-guard allows the worker turn to exit naturally before Step 8.
     Proceed to Step 8 with a foundation-specific PR body (see below).

8. On Fix & retry:
     Clear pending_human; jump back to step 3 (Generator re-dispatch).
     Cap: 3 retries total; 4th attempt auto-aborts with
     aborted_reason = "foundation-retry-exhausted".
     If the retry is being driven by the autonomous-ralph wrapper,
     set `_state.json.pending_worker_exit = true` after the
     pending_human clear so this turn ends and the wrapper spawns a
     fresh worker for the retry.

9. On Abort:
     aborted_reason = "foundation-attestation-rejected"; halt.
     Set `_state.json.pending_worker_exit = true` after writing
     aborted_reason so the active worker can exit. The wrapper's next
     tick observes the abort cursor and stops without spawning a new
     worker.
```

## Abort reasons

| Reason | Where set | Operator remediation |
|---|---|---|
| `foundation-kickoff-aborted` | Step 2 user-select Abort | Re-run `/harness-loop`, choose Proceed |
| `foundation-attestation-rejected` | Step 9 user-select Abort | Address underlying gap, `/harness-loop` replays from step 1 |
| `foundation-retry-exhausted` | Step 8 (4th retry) | `/harness-plan --replan` or widen deliverables |

## PR body (foundation-specific)

Step 8 dispatches the PR guide, but the body template diverges from
feature sprints:

- **No rubric summary** — there are no axes or thresholds to cite
- **Deliverable table** — the same table Orchestrator built into
  `feedback/verification-1.md` (Generator claim, probe verdict,
  evidence, agreement)
- **Setup follow-up list** — `[ ]` items the human still needs to do
  outside the repo (GCP console, Anthropic key, etc.), lifted from
  `contract.md` §Setup Prerequisites verbatim
- **Sprint link** — `_state.json.sprint_issues[0]`

See [pr-creation-guide.md](pr-creation-guide.md) for the full
foundation PR template.

## Metrics accounting

Rubric axes do not exist in foundation-sprints, so no axis row is
appended to `metrics.jsonl`. Instead, one accounting row:

```json
{
  "ts": "<ISO>",
  "sprint": 0,
  "iter": 0,
  "agent": "orchestrator",
  "phase": "foundation-attest",
  "deliverables_pass": "<N>/<M>",
  "verdict": "pass" | "abort"
}
```

This keeps the file line-oriented and comparable with feature-sprint
rows even though the shape differs.

## Non-goals

- This protocol does NOT evaluate code quality. The attestation gate is
  a human go/no-go on infrastructure readiness, not on implementation
  craft. Rubric scoring resumes at sprint-1.
- Foundation-sprints do NOT share a branch with later sprints. Each
  sprint (foundation or feature) gets its own branch per Step 3 of
  SKILL.md.

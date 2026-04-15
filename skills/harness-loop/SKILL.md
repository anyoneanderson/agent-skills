---
name: harness-loop
description: |
  Run the GAN control loop for one epic: for each sprint, negotiate the
  contract, iterate Generator ⇄ Evaluator to rubric convergence (or
  Principal Skinner stop), checkpoint to progress.md + _state.json +
  git + metrics.jsonl every iteration, and open the PR. Handles
  interactive / continuous / autonomous-ralph / scheduled execution modes.

  Prerequisite: /harness-init and /harness-plan must have completed.
  _state.json.phase must be "ready-for-loop" (fresh) or one of the
  in-sprint phases (resume).

  English triggers: "Run harness-loop", "Start the sprint loop", "Execute sprints"
  日本語トリガー: 「harness-loop を実行」「sprint ループを開始」「自律実装を開始」
license: MIT
---

# harness-loop — Autonomous Sprint Execution Loop

Consumes the sprint backlog produced by `harness-plan` and runs each
sprint through a Negotiation → Implementation → PR pipeline until the
epic completes or Principal Skinner stops the loop. Designed to survive
context compaction, session restarts, and overnight runs: every state
transition lands in `.harness/progress.md`, `.harness/_state.json`,
`.harness/metrics.jsonl`, and git.

Roles coordinating through this orchestrator:

- **Planner** (Claude) — arbiter of negotiation stalemates and replans
- **Generator** (Claude / Codex via cmux / other) — writes code
- **Evaluator** (Claude + Playwright/pytest/curl) — scores rubric

This skill is the orchestrator, not an agent. It reads and writes the
shared ledger, dispatches sub-agents, and advances the cursor. It never
writes implementation code or rubric verdicts itself.

## Language Rules

1. Auto-detect input language → respond in the same language
2. Japanese input → Japanese output
3. English input → English output
4. Explicit override (e.g., "in English", "日本語で") takes priority
5. All `AskUserQuestion` options are bilingual (`"English / 日本語"`)

Reference files exist as `<name>.md` (English) and `<name>.ja.md`
(Japanese). Pick the pair matching the detected language.

## Prerequisites

Verify before any sprint work:

1. **Harness initialised** — `.harness/_config.yml`,
   `.harness/scripts/progress-append.sh`, and
   `.claude/agents/{planner,generator,evaluator}.md` exist. If not, stop
   and instruct the user to run `/harness-init`.
2. **Plan completed** — `.harness/<epic>/roadmap.md` exists and
   `_state.json.phase ∈ {ready-for-loop, negotiation, impl, evaluation,
   pr, done}`. If `phase == product-spec-draft | roadmap-draft |
   roadmap-approved | issues-pending`, stop and instruct the user to
   finish `/harness-plan` first.
3. **`jq` and `git`** available — `command -v jq` and
   `git rev-parse --is-inside-work-tree`. Required for all state IO.
4. **Tracker pre-flight** — if `_config.yml.tracker == github`, run
   `gh auth status`. Fail fast rather than mid-PR.

Do not partially execute on failure. Surface the missing piece and exit.

## Boot Sequence (REQ-072)

Execute first on every invocation — fresh session or resume:

1. `git log --oneline -20`
2. `tail -100 .harness/progress.md` (if present)
3. `cat .harness/_state.json`

Decision table after Boot:

| `_state.json` condition | Action |
|---|---|
| `completed == true` | Report "epic done" and exit. Suggest next epic via `/harness-plan` |
| `aborted_reason != null` | Surface reason; ask user to resolve before resume (interactive only) |
| `pending_human == true` | Tier-A halt; surface details and stop (see Step 7) |
| `phase == ready-for-loop` | Fresh start — enter Step 2 |
| `phase ∈ {negotiation, impl, evaluation, pr}` | Resume — enter Step 2 and branch by phase |

In `interactive` mode the skill confirms resume vs restart via
`AskUserQuestion`. In non-interactive modes it auto-resumes per
`_state.json` (ASM-007).

## Execution Flow (10 steps)

### Step 1: Detect State and Mode Context

Parse `_state.json`. If `.mode` is already set (resume path), honour it.
Otherwise Step 2 elicits the mode. Compute:

- `current_epic`, `current_sprint`, `phase`, `iteration`
- Remaining Principal Skinner budget (see Step 7)
- Active sprint directory: `.harness/<epic>/sprints/sprint-<n>-<feature>/`

### Step 2: Execution Mode Selection (T-037)

Mode is chosen once at loop start and persisted to `_state.json.mode`.
**Interactive mode is the only mode permitted to call
`AskUserQuestion`** during the loop (ASM-007, REQ-078). All other
modes read any branching value from `_config.yml`.

```
if _state.json.mode is null:
  if interactive session (TTY + not -p):
    AskUserQuestion:
      question: "Execution mode?" / "実行モード?"
      options:
        - "interactive — confirm each iteration / 各 iteration で確認"
        - "continuous — run to completion in this session / 完走まで続行 (Recommended)"
        - "autonomous-ralph — fresh context per iter / 毎 iter 独立 context"
        - "scheduled — Ralph every N iters / N iter 毎に Ralph"
  else:
    mode = _config.yml.default_mode | "continuous"
  persist to _state.json.mode
```

| Mode | Loop control | AskUserQuestion | Reference |
|---|---|---|---|
| `interactive` | Skill in-process; pause after each iter | allowed | — |
| `continuous` | Skill in-process; run to completion | **forbidden** | — |
| `autonomous-ralph` | External shell wrapper; `claude -p --bare` per iter | **forbidden** | [autonomous-ralph.md](references/autonomous-ralph.md) |
| `scheduled` | Mix of continuous + Ralph at fixed cadence | **forbidden** | [autonomous-ralph.md](references/autonomous-ralph.md) |

For `autonomous-ralph` and `scheduled`, this skill exits after one
iteration; the shell wrapper re-invokes it for the next.

### Step 3: Load Current Sprint

Read `.harness/<epic>/roadmap.md` frontmatter; select the sprint where
`n == _state.json.current_sprint`. Load:

- `.../contract.md` — contract with empty `acceptance_scenarios` /
  `rubric` on fresh entry, populated on resume
- `.../shared_state.md` — sprint ledger (Orchestrator-only writes)
- `.../feedback/` — per-role per-iter files (agents write here)

If the sprint directory is missing (roadmap drift), emit
`aborted_reason: "sprint-missing:<n>"` and halt.

Set `_state.json.phase = "negotiation"` if fresh, else keep as read.

### Step 4: Negotiation Phase (T-031)

Governed by [negotiation-protocol.md](references/negotiation-protocol.md).

```
if contract.status == "active":
  skip Step 4 (already negotiated, resume case)

for round in 1..contract.max_negotiation_rounds (default 3):
  dispatch Generator sub-agent with contract draft + shared_state.md
  Generator appends to feedback/generator-<round>.md
  Orchestrator copies round summary to shared_state.md/Negotiation

  dispatch Evaluator sub-agent symmetrically
  Evaluator appends to feedback/evaluator-<round>.md
  Orchestrator copies round summary to shared_state.md/Negotiation

  if both agree:
    break

if no agreement after max rounds:
  dispatch Planner; Planner writes feedback/planner-ruling.md
  Orchestrator copies ruling to contract Negotiation Log
```

Append one `progress.md` line per round:

```
[<ts>] negotiation: round=<r> agent=<role> summary=<short>
```

Write contract final frontmatter: populated `acceptance_scenarios`,
`rubric` (from `rubric-presets.md`), `max_iterations`. Flip
`status: active` and record the contract commit SHA in
`shared_state.md/Contract`. Advance `_state.json.phase = "impl"`.

### Step 5: Contract Freeze and Commit

1. `git add .harness/<epic>/sprints/sprint-<n>-*/contract.md
   .harness/<epic>/sprints/sprint-<n>-*/shared_state.md`
2. `git commit -m "harness-loop: sprint-<n> contract frozen"`
3. Store the SHA in `_state.json.last_commit`
4. Append `progress.md`: `decision: sprint-<n> contract frozen @ <SHA>`

### Step 6: Implementation Loop (T-032, T-033)

Governed by [shared-state-protocol.md](references/shared-state-protocol.md).

```
while iteration < contract.max_iterations:
  iteration += 1
  start_ts = now()

  # Generator turn
  dispatch Generator with:
    - contract.md (frozen)
    - shared_state.md (read-only)
    - previous iteration's feedback/evaluator-<iter-1>.md (if fail)
  Generator edits source files; appends to feedback/generator-<iter>.md

  # Evaluator turn
  dispatch Evaluator with:
    - contract.md
    - shared_state.md
    - the new source state
  Evaluator runs rubric checks; appends to feedback/evaluator-<iter>.md
  Orchestrator copies verdict to shared_state.md/WorkLog and /Evaluation

  # Per-iteration checkpoint (Step 7)
  checkpoint(iteration, start_ts)

  if all axes >= threshold:
    contract.status = "done"
    break

  # Principal Skinner check (Step 7)
  if any stop-condition fires:
    contract.status = "aborted"
    set _state.json.aborted_reason
    break
```

Evaluator failure format (input to the next Generator call):

```yaml
iter: <n>
verdict: fail
failing_axes:
  - axis: Functionality
    score: 0.6
    threshold: 1.0
    notes: "AS-2 fails: login redirect 500s"
    evidence: sprints/sprint-<n>-*/evidence/AS-2-run-<iter>.trace
retry_hint: "Tighten session lookup; see evidence trace line 42"
```

Each iteration ends with a commit (see Step 7) so every attempt is
reviewable in git history.

### Step 7: Iteration Checkpoint and Principal Skinner (T-036, T-038)

At the end of every iteration (pass OR fail OR abort), atomically:

1. **Update `_state.json`** via `jq` into a tmp file, then rename:
   - `iteration`, `last_agent`, `next_action`, `last_commit`
   - `features_pass_fail` (per-axis for this sprint's features)
   - `cumulative_cost_usd += cost_this_iter`
   - `rubric_stagnation_count` — increment if no axis improved this iter; reset to 0 on any improvement

2. **Append one line to `.harness/metrics.jsonl`**:
   ```json
   {"ts":"<ISO>","iter":<n>,"sprint":<s>,"agent":"<role>","duration_ms":<d>,"input_tokens":<i>,"output_tokens":<o>,"cost_usd":<c>,"rubric_scores":{...},"tool_calls":<t>,"tool_failures":<f>}
   ```

3. **Commit**: `git add -A && git commit -m "harness-loop: sprint-<n> iter-<iter>"` (non-fatal on `git commit` failure; log to progress.md and continue).

4. **Principal Skinner stop-check** — evaluate all five conditions; on any hit set `_state.json.aborted_reason` and stop:

   | Condition | Computed from | Default |
   |---|---|---|
   | `iteration >= max_iterations` | contract + state | 8 |
   | `wall_time >= max_wall_time_sec` | `now - start_time` | 28800 (8h) |
   | `rubric_stagnation_count >= rubric_stagnation_n` | state + `_config.yml.rubric_stagnation_n` | 3 |
   | `cumulative_cost_usd >= max_cost_usd` | state + `_config.yml.max_cost_usd` | 20.0 |
   | `pending_human == true` | set by `.harness/scripts/tier-a-guard.sh` PreToolUse hook | — |

5. Append a `progress.md` line:
   ```
   [<ts>] evaluation: iter=<n> verdict=<pass|fail> axes="f=.. c=.. d=.. o=.."
   ```
   And on abort:
   ```
   [<ts>] stop: reason=<max_iter|wall_time|rubric_stagnation|cost_cap|tier_a> detail=<text>
   ```

Principal Skinner never deletes state. The loop stops and leaves
everything on disk for a later resume (pending_human), a replan
(rubric_stagnation), or a manual budget bump (cost_cap, wall_time).

### Step 8: PR Creation on Sprint Pass (T-034)

Governed by [pr-creation-guide.md](references/pr-creation-guide.md).

When `contract.status == "done"`:

1. Ensure all iteration commits are on a feature branch named
   `harness/<epic>/sprint-<n>-<feature>` (the wrapper creates this; if
   running in-process, `git switch -c` it before Step 4 if not present).
2. `git push -u origin <branch>` (skip when `tracker == none`).
3. For `bundling: split` — one PR per sprint. For `bundling: bundled` —
   open a single PR whose body lists all bundled features (the roadmap
   entry already references `bundled_with`).
4. PR body is built from the template in `pr-creation-guide.md`, quoting
   the `shared_state.md/Evaluation` block and linking the sprint Issue
   (`_state.json.sprint_issues[<n>]`).
5. Record PR URL to `_state.json.sprint_issues[<n>].pr` and append
   `progress.md`:
   ```
   [<ts>] decision: sprint-<n> PR opened <url>
   ```

On `contract.status == "aborted"` skip PR creation. Record the abort in
`shared_state.md/Decisions` and keep the branch intact so the user can
inspect or resume.

### Step 9: Sprint Transition (T-035)

After Step 8 completes (pass) or on abort:

```
if _state.json.aborted_reason != null:
  stop the loop; surface to the user; do not advance current_sprint

else if any sprint remains in roadmap:
  _state.json.current_sprint += 1
  _state.json.iteration = 0
  _state.json.phase = "negotiation"
  _state.json.start_time = now()
  _state.json.rubric_stagnation_count = 0
  features_pass_fail = []     # reset per-sprint
  if mode == interactive:
    AskUserQuestion: "Proceed to sprint <n+1>?" — yes | pause | abort
  go to Step 3

else:
  _state.json.completed = true
  _state.json.phase = "done"
  go to Step 10
```

`cumulative_cost_usd` and `start_time`'s wall-time budget reset is a
policy choice. v1 keeps `cumulative_cost_usd` accumulating across the
whole epic (so the cost cap is epic-wide). `start_time` resets per
sprint so the 8h wall-time cap applies per sprint. Document both in
`progress.md` on reset.

### Step 10: Final Summary

On `completed == true`:

- Emit a report to the user:
  - Epic name + total sprints run
  - PR URLs per sprint (or "bundled" groups)
  - Total cost (`cumulative_cost_usd`), total wall-time, total iterations
  - Any sprints aborted (with reason)
- Append `progress.md`:
  ```
  [<ts>] decision: epic=<name> completed sprints=<N> cost=<$> iters=<total>
  ```
- Do not touch `_state.json.completed` again. Leave for audit.

Suggest `/harness-rules-update` if any sprint aborted or if
`rubric_stagnation` fired — those are exactly the failure shapes that
skill refines.

## Error Handling

| Situation | Response |
|---|---|
| `.harness/_config.yml` missing | Error: "Run `/harness-init` first." |
| `.harness/<epic>/roadmap.md` missing | Error: "Run `/harness-plan` first." |
| `jq` not found | Error: "Install `jq` — hooks and state IO require it." |
| `gh` missing when tracker=github | Abort before sprint work; do not silently swap trackers |
| Generator sub-agent fails to launch | Log to `feedback/generator-<iter>.md`; retry once; on second fail set `pending_human=true` |
| Evaluator cannot run test tool | Record verdict `fail` with `reason: tool-unavailable`; Principal Skinner rubric-stagnation path handles eventual halt |
| `git commit` fails mid-iter (e.g., hook rejection) | Log line; continue; do not bypass hooks |
| Negotiation rounds exceeded without Planner ruling file | Planner absent or failed; set `pending_human=true` and halt |
| `_state.json` unparseable (corruption) | Halt immediately; never overwrite. User reconstructs from git history |
| AskUserQuestion attempted in non-interactive mode | Bug — fix call site. Fall back to `_config.yml` default with a progress line warning |

## Usage

```
# Start from a planned epic
/harness-loop

# Resume after compact / restart / abort (auto-detected from _state.json)
/harness-loop

# Force a specific mode (overrides stored mode; recorded to _state.json)
/harness-loop --mode continuous
/harness-loop --mode autonomous-ralph
/harness-loop --mode scheduled --ralph-every 5

# Force a specific sprint (skip remaining earlier sprints; requires confirmation)
/harness-loop --from-sprint 3

# Replan aborted sprint (re-enter Negotiation, reset iteration to 0)
/harness-loop --replan-current-sprint
```

`--mode autonomous-ralph` exits after one iteration; pair it with the
shell wrapper in [autonomous-ralph.md](references/autonomous-ralph.md).

## What harness-loop does NOT do

- Does not change the epic plan (roadmap.md) — use `/harness-plan --replan`
- Does not edit rubric after contract freeze — re-enter Negotiation via `--replan-current-sprint`
- Does not refine rules from failures — `/harness-rules-update` does that
- Does not configure hooks or agents — `/harness-init` owns those files
- Does not bypass `.harness/scripts/tier-a-guard.sh` denials — human approval is required

## Observability

Every run lands in four files:

- `.harness/progress.md` — human trace (append-only)
- `.harness/_state.json` — machine cursor (atomic writes)
- `.harness/metrics.jsonl` — per-iter metrics (append-only)
- `git log` — one commit per iteration

Optional OTLP export when `_config.yml.hook_level == strict` and
`otlp_endpoint` is set — see [otlp-exporter.md](references/otlp-exporter.md).

## References

- [negotiation-protocol.md](references/negotiation-protocol.md) — round-by-round format, stalemate handling, Planner ruling schema
- [shared-state-protocol.md](references/shared-state-protocol.md) — Shared-read / Isolated-write discipline across agents
- [pr-creation-guide.md](references/pr-creation-guide.md) — split vs bundled PR body templates and `gh pr create` invocation
- [autonomous-ralph.md](references/autonomous-ralph.md) — shell wrapper for `claude -p --bare` per-iteration execution
- [otlp-exporter.md](references/otlp-exporter.md) — optional metrics pipeline
- [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md) — `_state.json` and `metrics.jsonl` canonical schema
- [../harness-init/references/rubric-presets.md](../harness-init/references/rubric-presets.md) — axis sets by project type

See `.specs/harness-suite/` in the source repo for requirement.md,
design.md, and tasks.md governing this skill.

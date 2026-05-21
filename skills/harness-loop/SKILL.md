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

> 📖 **New to harness?** Read [README.md](README.md) ([日本語: README.ja.md](README.ja.md)) for concepts, terminology (Tier-A / rubric / Principal Skinner / foundation-sprint / ...), and the three-skill overview before diving into implementation details.

# harness-loop — Autonomous Sprint Execution Loop

Orchestrator for the GAN control loop. Consumes the sprint backlog
produced by `harness-plan` and runs each sprint through
**Negotiation → Implementation → PR**. Every state transition lands in
`.harness/progress.md`, `.harness/_state.json`, `.harness/metrics.jsonl`,
and git so the loop survives context compaction and session restarts.

Roles dispatched through this orchestrator:

- **Planner** (Claude) — stalemate arbiter and replanner
- **Generator** (Claude / Codex CLI / Codex via cmux / other MCP) —
  writes code per `_config.yml.generator_backend`
- **Evaluator** (Claude + Playwright MCP / Playwright CLI / curl / custom-script) — scores rubric

## Orchestrator responsibility (read first)

**You are the Orchestrator.** Your job is to dispatch Planner / Generator / Evaluator and own shared state (`_state.json`, `progress.md`, `metrics.jsonl`, git checkpoints, PRs). You must NOT perform their work yourself.

**Do**

- Render prompts by placeholder substitution only (`{{EPIC_NAME}}`, `{{SPRINT_NUMBER}}`, `{{ITER}}`, `{{EVALUATOR_FB_PATH}}`, etc.)
- Point the agent at contract / feedback paths to read / write
- Write `_state.json` / `progress.md` / `metrics.jsonl` / git commits / PRs; raise `pending_worker_exit=true` after each turn-ending durable write so `stop-guard.sh` can allow natural exit (see [resilience-schema](../harness-init/references/resilience-schema.md))
- Apply small repo hygiene fixes (`.gitignore` / `.editorconfig` /
  `.gitattributes` 1-2 line additions) when clearly needed; code /
  schema / migration changes remain Generator work
- Work on a feature branch (see Step 1 / Step 3)

**Don't**

- Write code, schemas, docker-compose files, or other implementation content inline in prompts (Generator's job)
- Make design decisions — file layout, dependency picks, CLI flags, migration names (Generator's job)
- Score an agent's work or decide rubric threshold values (Evaluator / Planner / Negotiation's job)
- Commit directly on `main` / `master` / default branch (Step 1 refuses this)
- Skip agent dispatch and do the work yourself "to save time"

Full rationale + examples: [README.md §Orchestrator's responsibility](README.md).

## Required Reading — Open BEFORE doing the step

Claude Code tends to skim SKILL.md. For each step below, you **MUST
open and read** the listed reference file(s) before acting. The SKILL.md
only contains the dispatch skeleton; protocol detail lives in references.

| Step | Phase | Required file(s) to open |
|---|---|---|
| Step 1 | Detect state, pin Generator backend (4-layer resolution) | [references/generator-dispatch.md §4-layer resolution](references/generator-dispatch.md), [references/shared-state-protocol.md §Write permissions](references/shared-state-protocol.md) |
| Step 3.5 | Every Generator dispatch | [references/generator-dispatch.md](references/generator-dispatch.md), [references/validator-protocol.md](references/validator-protocol.md) |
| Step 2 (`mode=autonomous-ralph`) | Supervisor / worker branching | [references/supervisor-dispatch.md](references/supervisor-dispatch.md), [references/autonomous-ralph.md](references/autonomous-ralph.md) |
| Step 4 | Negotiation | [references/negotiation-protocol.md](references/negotiation-protocol.md), [references/generator-dispatch.md](references/generator-dispatch.md) |
| Step 6 | Implementation | [references/shared-state-protocol.md](references/shared-state-protocol.md), [references/validator-protocol.md](references/validator-protocol.md) |
| Step 6 (mid-impl replan) | When a contract debt trigger fires | [references/negotiation-protocol.md §Mid-impl replan](references/negotiation-protocol.md#mid-impl-replan), [references/shared-state-protocol.md §Mid-impl replan escalation](references/shared-state-protocol.md#mid-impl-replan-escalation-layer-1-agent-request) |
| Step 9 | Sprint transition (re-pin Generator backend via 4-layer resolution) | [references/generator-dispatch.md §4-layer resolution](references/generator-dispatch.md) |
| Step 7 | Checkpoint / Principal Skinner | [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md), [references/git-strategy.md](references/git-strategy.md) (Orchestrator owns the atomic commit; agents must NOT) |
| Step 8 | PR creation | [references/pr-creation-guide.md](references/pr-creation-guide.md) |
| Foundation-sprint (sprint-0, `type: foundation`) | Skips negotiation + G⇄E loop | [references/foundation-loop-protocol.md](references/foundation-loop-protocol.md), [../harness-init/references/templates/foundation-sprint-checklist.md](../harness-init/references/templates/foundation-sprint-checklist.md) |
| Mode `autonomous-ralph` / `scheduled` | Headless runs | [references/autonomous-ralph.md](references/autonomous-ralph.md) |
| Optional: metrics export | When `otlp_endpoint` is set | [references/otlp-exporter.md](references/otlp-exporter.md) |

Prompt templates for Generator and Evaluator invocations live under
[`references/prompt-templates/`](references/prompt-templates/) (EN/JA).

## Language Rules

Resolve narrative language: explicit override (`in English`, `日本語で`) >
project mandate in `CLAUDE.md` / `AGENTS.md` > current user prompt >
fallback skill source language (English).

Never infer from machine text (`git log`, `progress.md`, JSON keys, state
enums, file paths, commands). Keep such tokens unchanged. `AskUserQuestion`
body uses resolved language; option labels/descriptions stay bilingual
(`English / 日本語`).

Reference files exist as `<name>.md` (EN) and `<name>.ja.md` (JA).

## Prerequisites

1. **Harness initialised** — `.harness/_config.yml`,
   `.harness/scripts/progress-append.sh`, and
   `.claude/agents/{planner,generator,evaluator}.md` exist. If not,
   instruct the user to run `/harness-init`.
2. **Plan completed** — `.harness/<epic>/roadmap.md` exists and
   `_state.json.phase ∈ {ready-for-loop, negotiation, impl, evaluation,
   pr, done}`. Otherwise instruct the user to finish `/harness-plan`.
3. **`jq` and `git`** available.
4. **Tracker pre-flight** — if `_config.yml.tracker == github`, run
   `gh auth status`. Fail fast.
5. **Fresh agent registry after `/harness-init`** — if
   `Task(subagent_type="generator"|"evaluator"|"planner")` is missing or
   falls back to a general-purpose agent, `/clear` is insufficient.
   Fully exit Claude Code, relaunch the repo with `claude --resume`,
   then retry `/harness-loop`.

Do not partially execute on failure. Surface the missing piece and exit.

## Boot Sequence

Execute first on every invocation — fresh session or resume:

1. `git log --oneline -20`
2. `tail -30 .harness/progress.md`
3. `cat .harness/_state.json`

Decision table:

| `_state.json` condition | Action |
|---|---|
| `completed == true` | Report "epic done" and exit |
| `aborted_reason != null` | Surface reason; `interactive` mode asks user to resolve |
| `pending_human == true` | Tier-A halt; surface details and stop |
| `phase == ready-for-loop` | Fresh epic — `autonomous-ralph` does a once-per-epic boot reset (keyed on `start_time_epic`, before the Principal Skinner gates: re-anchors `start_time` / cost / stagnation / `iteration`; see [references/autonomous-ralph.md](references/autonomous-ralph.md)), then Step 1 |
| `phase ∈ {negotiation, impl, evaluation, pr}` | Resume — enter Step 1, branch by phase |

In `interactive` mode, confirm resume vs restart via `AskUserQuestion`.
In non-interactive modes, auto-resume per `_state.json`.

## Execution Flow

### Step 1: Detect State, Pin Generator Backend

Parse `_state.json` for `current_epic`, `current_sprint`, `phase`,
`iteration`, Principal Skinner budget. Active sprint directory:
`.harness/<epic>/sprints/sprint-<n>-<feature>/`.

**Pin the Generator backend** via 4-layer resolution per
[references/generator-dispatch.md §4-layer resolution](references/generator-dispatch.md)
(state → contract → roadmap → config; legacy bypass when
`_config.yml.sprint_level_generator_override == false`; `codex_cmux`
falls back to `claude` when `cmux` / `CMUX_SOCKET_PATH` is unavailable).
Write the resolved value to `_state.json.effective_generator_backend`
(atomic `jq | mv`) and append
`[<ts>] backend pinned: <backend> (source: <source>)` to `progress.md`.
Step 3.5 dispatch reads this cache directly; the 4-layer resolution is
re-evaluated only at Step 9.

If the resolved backend is `codex_cli` and `mode == interactive`, the
kickoff approval MUST explicitly mention `danger-full-access`. Do not
dispatch until the operator attests that this is acceptable for the
sprint.

> Note: branch setup is unconditional in Step 3. If HEAD is on the
> default branch when harness-loop starts, Step 3 creates the sprint
> branch off the current HEAD; Step 1 only logs the starting branch.

### Step 2: Execution Mode Selection

Mode is chosen once at loop start and persisted to `_state.json.mode`.
`AskUserQuestion` is permitted only in `interactive` mode and in the
interactive supervisor branch of `autonomous-ralph`.

Precedence: `--mode` CLI flag > existing `_state.json.mode` > interactive
prompt > `"continuous"` default.

| Mode | Loop control | AskUserQuestion |
|---|---|---|
| `interactive` | In-process; pause after each iter | allowed |
| `continuous` | In-process; run to completion | forbidden |
| `autonomous-ralph` | Interactive session = supervisor attach/spawn via `.harness/ralph.pid`; non-interactive worker = one unit via fresh `claude -p --permission-mode bypassPermissions` | supervisor only |
| `scheduled` | Mix of continuous + Ralph at fixed cadence | forbidden |

Supervisor / worker split is mandatory:

```text
if --stop-wrapper:
  stop wrapper via .harness/ralph.pid and exit

if mode == "autonomous-ralph":
  if interactive session detected:
    ensure wrapper is running (attach if live, spawn if absent/stale)
    watch progress.md + ralph.log and relay important events
    handle pending_human / Tier-A via AskUserQuestion
    remain supervisor; do not execute the worker unit inline
  else:
    execute exactly one worker unit and exit
```

**Open `references/supervisor-dispatch.md`** for lifecycle details and
`references/autonomous-ralph.md` for the internal wrapper contract.

### Step 3: Load Current Sprint

Read `.harness/<epic>/roadmap.md` frontmatter; select the sprint where
`n == _state.json.current_sprint`. Load `contract.md`, `shared_state.md`,
and `feedback/` for that sprint.

If the sprint directory is missing (roadmap drift), set
`aborted_reason: "sprint-missing:<n>"` and halt.

Set `_state.json.phase = "negotiation"` if fresh; else keep as read.

#### Sprint branch setup

First action per sprint: create (or check out) the sprint branch before
any commit. **Run unconditionally — do NOT ask for user confirmation.**
One branch per sprint; bundled peers share the primary peer's branch.
Starting HEAD does not matter (main / master / another feature branch /
the correct sprint branch all work; the `checkout -b` or `checkout`
handles every case).

    harness/<epic>/sprint-<n>-<feature>                   (split; also foundation n=0)
    harness/<epic>/sprint-<primary-n>-<primary-feature>   (bundled — lowest-numbered peer)

```bash
BRANCH="harness/<epic>/sprint-<n>-<feature>"   # bundle → primary peer's name
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
  && git checkout "$BRANCH" \
  || git checkout -b "$BRANCH"
```

Record to `_state.json.sprint_branch` and append `progress.md`:

    [<ts>] branch: <BRANCH> (created|reused) from <starting-HEAD>

`sprint_branch == null` is the cursor that mandates this Step run on the next worker tick — `harness-init` and Step 9 transition both reset it to `null` so a new sprint cannot inherit the previous sprint's branch. The resolved name is derived from `<epic>` + roadmap, not from the prior `sprint_branch` value.

**Foundation-sprint protocol branch**: if the loaded `contract.md` has
`type: foundation`, skip Steps 4–7 (negotiation / rubric iteration) and
follow [references/foundation-loop-protocol.md](references/foundation-loop-protocol.md)
instead. Resume at Step 8 (PR) / Step 9 (sprint transition) on Attest.
Plan-side doctrine (why / when to insert a foundation-sprint) is in
[../harness-plan/references/foundation-sprint-guide.md](../harness-plan/references/foundation-sprint-guide.md).

### Step 3.5: Generator Dispatch (backend-aware)

**Open [references/generator-dispatch.md](references/generator-dispatch.md).**
Invoked by both Step 4 and Step 6.

Short summary (full detail in the reference):

- Render `prompt-templates/generator-<phase>.md` to a temp file with
  per-invocation substitutions
- Invoke per backend; `claude` requires post-dispatch via `claude-dispatch.sh`,
  `codex_cli` uses `.harness/scripts/codex-cli-dispatch.sh`,
  `Skill(skill="cmux-delegate", args="...")` for `codex_cmux`
- Wait for the backend-specific completion signal defined in
  `generator-dispatch.md` §Completion signal before consuming feedback files
- Expect phase-specific feedback:
  negotiation = `feedback/generator-neg-<round>.md` +
  `generator-neg-<round>-report.json`, implementation =
  `feedback/generator-<iter>.md` + `generator-<iter>-report.json`
- Fallback: claude backend = mandatory `claude-dispatch.sh --post-dispatch`; others see `references/generator-dispatch.md`
- Pipe report to `.harness/scripts/codex-progress-bridge.sh`

### Step 4: Negotiation Phase

**Open [references/negotiation-protocol.md](references/negotiation-protocol.md).**

```
if contract.status == "active":
  skip Step 4 (resume case, already negotiated)

for round in 1..contract.max_negotiation_rounds (default 3):
  Dispatch Generator (Step 3.5) with prompt-templates/generator-negotiation.md and validate per references/validator-protocol.md
  Dispatch Evaluator with prompt-templates/evaluator-negotiation.md
    ({{ROUND}}=round, {{GENERATOR_FB_PATH}}=feedback/generator-neg-<round>.md or "(none)")
  Copy round summaries to shared_state.md/Negotiation
  if both agree: break

if no agreement after max rounds:
  Dispatch Planner (phase=ruling); Planner writes feedback/planner-ruling.md
  and overwrites contract.md rubric + max_iterations
```

Append one progress.md line per round:
`[<ts>] negotiation: round=<r> agent=<role> signal=<accept|counter|escalate> delta=<short> file=feedback/generator-neg-<r>.md`

Finalise contract frontmatter (`acceptance_scenarios`, `rubric` from
[../harness-init/references/rubric-presets.md](../harness-init/references/rubric-presets.md),
`max_iterations`). Flip `status: active`, record the contract commit
SHA in `shared_state.md/Contract`. Advance `_state.json.phase = "impl"`.

### Step 5: Contract Freeze and Commit

```
git add .harness/<epic>/sprints/sprint-<n>-*/
git commit -m "harness-loop: sprint-<n> contract frozen"
```

Before entering Step 6, explicitly reset `_state.json.iteration = 0`
so the first implementation turn writes `generator-1.*`. Keep
`_state.json.negotiation_round` as the frozen negotiation cursor.

Store SHA in `_state.json.last_commit`. Append progress.md:
`decision: sprint-<n> contract frozen @ <SHA>`. As the LAST durable write of this turn, atomically set `_state.json.pending_worker_exit = true`.

### Step 6: Implementation Loop

**Open [references/shared-state-protocol.md](references/shared-state-protocol.md)**
for write permissions, file layout, and the report.json contract.

```
while iteration < contract.max_iterations:
  iteration += 1

  # Generator turn — see Step 3.5
  _state.json.phase = "impl"
  Dispatch Generator with prompt-templates/generator-implementation.md
    ({{ITER}}=iteration, {{EVALUATOR_FB_PATH}}=feedback/evaluator-<iter-1>.md if iter>1)
  Run `.harness/scripts/validate-generator-report.sh --report ... --narrative ... --report-dir ... --phase impl`; then bridge/protocol-update progress/state from report.json.

  # Evaluator turn — Task tool, Claude, always
  _state.json.phase = "evaluation"
  Dispatch Evaluator with prompt-templates/evaluator-implementation.md
    ({{ITER}}=iteration, {{GENERATOR_FB_PATH}}=feedback/generator-<iter>.md,
     {{EVALUATOR_TOOLS}}=_config.yml.evaluator_tools joined by commas)
  Run `.harness/scripts/validate-evaluator-report.sh --report ... --narrative ... --sprint-dir ... --report-dir ... --phase impl --strict` before reading verdict.
  invalid report, missing phases, or non-zero quality gates force fail.
  Copy the compliance-adjusted verdict to shared_state.md/WorkLog and /Evaluation.

  # Mid-impl replan check — see references/negotiation-protocol.md §Mid-impl replan
  # Triggers in priority order: Layer 1 (agent request) / Layer 2 (axis stagnation)
  # / Layer 3 (supervisor --replan-contract). Gated by _config.yml.mid_impl_replan
  # (enabled, min_consecutive_signals, max_per_sprint, axis_band_threshold).
  if mid_impl_replan trigger fires AND not gated:
    Dispatch Planner (phase=mid-impl-replan) with contract.md, all post-freeze
    feedback, trigger context, cross-iter axis table. Planner writes
    feedback/planner-ruling-impl-<iter>.md.
    Apply ruling → contract.md delta, _state.json.contract_revisions[] append,
    mid_impl_replan_count += 1, rubric_stagnation_count = 0, iteration kept.

  # Decide verdict + terminal state BEFORE Step 7 checkpoint so all
  # durable writes land in one atomic pass
  verdict = "pass" if evaluator report is compliant and all axes >= threshold else "fail"
  if verdict == "pass":
    contract.status = "done"; phase = "pr"; terminate = true  # final sprint included; Step 8 is never skipped
  elif any Principal Skinner condition fires (see Step 7):
    contract.status = "aborted"; set aborted_reason; terminate = true
  else:
    terminate = false

  checkpoint(iteration, verdict, contract.status)  # Step 7
  if terminate: break
```

Evaluator failure feedback (input for next Generator) contains
`iter`, `verdict: fail`, `failing_axes` array, and a `retry_hint`.

### Step 7: Iteration Checkpoint and Principal Skinner

**Open [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md)**
for the canonical `_state.json` + `metrics.jsonl` schema.

Every iteration (pass / fail / abort) atomically persists in one pass:

1. **`contract.md`** — on `pass` or Principal Skinner fire: frontmatter
   `status: done | aborted`, fill `Sprint Outcome` section
2. **`_state.json`** via `jq | mv` — iteration, last_agent, next_action,
   last_commit, phase, features_pass_fail, cumulative_cost_usd,
   rubric_stagnation_count, aborted_reason (if fired)
3. **`metrics.jsonl`** — append one JSON line per schema
   - When a Tier-A guard caused `pending_human=true`, include the latest
     `tier_a_last` payload so dangerous command attempts can be counted
     and audited across sprints
4. **Commit** — `git add -A && git commit -m "harness-loop: sprint-<n> iter-<iter>"`
   (non-fatal; log any failure and continue)
5. **Worker-exit signal** — atomically set `_state.json.pending_worker_exit = true` as the last write

**Principal Skinner stop-check** (the five conditions, computed before
the checkpoint so `aborted_reason` lands in the atomic write):

| Condition | Source | Default |
|---|---|---|
| `iteration >= max_iterations` | contract + state | 8 |
| `wall_time >= max_wall_time_sec` | `now - start_time` | 28800 |
| `rubric_stagnation_count >= rubric_stagnation_n` | state + config | 3 |
| `cumulative_cost_usd >= max_cost_usd` | state + config | 20.0 |
| `pending_human == true` | Tier-A guard hook | — |

Append progress.md:
`evaluation: iter=<n> verdict=<pass|fail> axes=...`
and on abort: `stop: reason=<condition> detail=<text>`.

Principal Skinner never deletes state. The loop stops and leaves
everything on disk for later resume, replan, or budget bump.

#### Interactive per-iteration gate

`interactive` mode only: after each checkpoint, offer **continue** /
**restart (fully exit Claude Code, then relaunch with `claude --resume`)** /
**pause** / **abort** via AskUserQuestion. Non-interactive modes skip
this gate.

### Step 8: PR Creation on Sprint Pass

**Open [references/pr-creation-guide.md](references/pr-creation-guide.md).**

When `contract.status == "done"`:

1. Ensure commits are on branch `harness/<epic>/sprint-<n>-<feature>`
2. `git push -u origin <branch>` (skip when `tracker == none`)
3. `bundling: split` → one PR per sprint; `bundled` → one PR listing all
   bundled features
4. Build PR body from the guide's template, quoting
   `shared_state.md/Evaluation` and linking `_state.json.sprint_issues[<n>]`
5. Record PR URL to `_state.json.sprint_prs[<n>]`; append progress.md

On `aborted`: skip PR creation. Record in `shared_state.md/Decisions`,
keep the branch for later inspection.

### Step 9: Sprint Transition

```
if aborted_reason != null:
  stop; surface to user; do not advance current_sprint
elif any sprint remains in roadmap:
  current_sprint += 1; iteration = 0; phase = "negotiation"
  start_time = now(); rubric_stagnation_count = 0
  features_pass_fail = []
  sprint_branch = null; negotiation_round = 0; last_agent = null  # prevent stale carry-over
  re-execute Step 1 backend pinning for the new sprint
    (4-layer resolution; log transition to progress.md when changed)
  pending_worker_exit = true   # final durable write of this turn
  if mode == interactive: AskUserQuestion "Proceed to sprint <n+1>?"
  go to Step 3
else:
  assert sprint_prs[1..current_sprint] non-null; completed = true; phase = "done"; pending_worker_exit = true
  go to Step 10
```

Reset policy: `cumulative_cost_usd` accumulates across the epic;
`start_time` / `effective_generator_backend` / `sprint_branch` /
`negotiation_round` / `last_agent` all reset per sprint (latter four to
`null` / `null` / `0` / `null` respectively) so no value silently carries
over. Do NOT write `phase = "ready-for-loop"` during sprint transition;
the supervisor must observe `phase = "negotiation"` and spawn the next
worker from that live cursor.

### Step 10: Final Summary

On `completed == true`: emit report (epic name, sprints run, PR URLs,
total cost / wall-time / iterations, aborted sprints with reasons).
Append progress.md:
`decision: epic=<name> completed sprints=<N> cost=<$> iters=<total>`.

Suggest `/harness-rules-update` on any abort or `rubric_stagnation`
trigger — those failures are what that skill refines.

## Error Handling

| Situation | Response |
|---|---|
| `.harness/_config.yml` missing | "Run `/harness-init` first." |
| `.harness/<epic>/roadmap.md` missing | "Run `/harness-plan` first." |
| `jq` / `git` not found | Error; install and re-run |
| `gh` missing when tracker=github | Abort; do not silently swap trackers |
| Generator dispatch fails | Log to phase-appropriate feedback (`generator-neg-<round>.md` or `generator-<iter>.md`); retry once; 2nd fail → `pending_human=true` |
| Evaluator tool unavailable | Record `verdict: fail, reason: tool-unavailable`; let rubric_stagnation halt eventually |
| `git commit` fails mid-iter | Log; continue; never bypass hooks |
| Planner ruling file missing after round 3 | `pending_human=true`; halt |
| `_state.json` unparseable | Halt; never overwrite. User restores from git |
| AskUserQuestion in non-interactive mode | Bug; fall back to `_config.yml` default + progress.md warning |

## Usage

```
/harness-loop                                  # start or resume
/harness-loop --mode <mode>                    # interactive | continuous | autonomous-ralph | scheduled
/harness-loop --mode scheduled --ralph-every 5 # hybrid
/harness-loop --from-sprint 3                  # skip (confirm required)
/harness-loop --replan-current-sprint          # re-enter Negotiation, iter = 0
/harness-loop --replan-contract                # mid-impl Planner ruling, iter kept
```

## What harness-loop does NOT do

- Does not change the epic plan — use `/harness-plan --replan`
- Does not edit rubric after contract freeze — `--replan-current-sprint`
- Does not refine rules from failures — `/harness-rules-update` does
- Does not configure hooks or agents — `/harness-init` owns those
- Does not bypass Tier-A denials — human approval required

## Observability

Four files: `.harness/progress.md` (human trace, append),
`.harness/_state.json` (machine cursor), `.harness/metrics.jsonl`
(per-iter metrics), `git log` (one commit per iter). Optional OTLP
export when `hook_level == strict` and `otlp_endpoint` is set — see
[references/otlp-exporter.md](references/otlp-exporter.md).

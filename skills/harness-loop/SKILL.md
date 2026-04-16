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

Orchestrator for the GAN control loop. Consumes the sprint backlog
produced by `harness-plan` and runs each sprint through
**Negotiation → Implementation → PR**. Every state transition lands in
`.harness/progress.md`, `.harness/_state.json`, `.harness/metrics.jsonl`,
and git so the loop survives context compaction and session restarts.

Roles dispatched through this orchestrator:

- **Planner** (Claude) — stalemate arbiter and replanner
- **Generator** (Claude / Codex plugin / Codex via cmux / other MCP) —
  writes code per `_config.yml.generator_backend`
- **Evaluator** (Claude + Playwright / pytest / curl) — scores rubric

## Required Reading — Open BEFORE doing the step

Claude Code tends to skim SKILL.md. For each step below, you **MUST
open and read** the listed reference file(s) before acting. The SKILL.md
only contains the dispatch skeleton; protocol detail lives in references.

| Step | Phase | Required file(s) to open |
|---|---|---|
| Step 3.5 | Every Generator dispatch | [references/generator-dispatch.md](references/generator-dispatch.md) |
| Step 4 | Negotiation | [references/negotiation-protocol.md](references/negotiation-protocol.md), [references/generator-dispatch.md](references/generator-dispatch.md) |
| Step 6 | Implementation | [references/shared-state-protocol.md](references/shared-state-protocol.md), [references/generator-dispatch.md](references/generator-dispatch.md) |
| Step 7 | Checkpoint / Principal Skinner | [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md) |
| Step 8 | PR creation | [references/pr-creation-guide.md](references/pr-creation-guide.md) |
| Mode `autonomous-ralph` / `scheduled` | Headless runs | [references/autonomous-ralph.md](references/autonomous-ralph.md) |
| Optional: metrics export | When `otlp_endpoint` is set | [references/otlp-exporter.md](references/otlp-exporter.md) |

Prompt templates for Generator invocations live under
[`references/prompt-templates/`](references/prompt-templates/) (EN/JA).

## Language Rules

1. Auto-detect input language → respond in the same language
2. Japanese input → Japanese output; English input → English output
3. Explicit override (e.g., "in English", "日本語で") takes priority
4. All `AskUserQuestion` options are bilingual (`"English / 日本語"`)

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

Do not partially execute on failure. Surface the missing piece and exit.

## Boot Sequence

Execute first on every invocation — fresh session or resume:

1. `git log --oneline -20`
2. `tail -100 .harness/progress.md`
3. `cat .harness/_state.json`

Decision table:

| `_state.json` condition | Action |
|---|---|
| `completed == true` | Report "epic done" and exit |
| `aborted_reason != null` | Surface reason; `interactive` mode asks user to resolve |
| `pending_human == true` | Tier-A halt; surface details and stop |
| `phase == ready-for-loop` | Fresh — enter Step 1 |
| `phase ∈ {negotiation, impl, evaluation, pr}` | Resume — enter Step 1, branch by phase |

In `interactive` mode, confirm resume vs restart via `AskUserQuestion`.
In non-interactive modes, auto-resume per `_state.json`.

## Execution Flow

### Step 1: Detect State, Pin Generator Backend

Parse `_state.json`. Compute `current_epic`, `current_sprint`, `phase`,
`iteration`, and Principal Skinner budget. Active sprint directory:
`.harness/<epic>/sprints/sprint-<n>-<feature>/`.

Pin the Generator backend once per loop run:

```
backend = _config.yml.generator_backend    # claude | codex_plugin | codex_cmux | other

if backend == "codex_cmux" and command -v cmux fails:
  backend = "claude"
  append progress.md: decision: codex_cmux unavailable — fell back to claude

if backend == "codex_plugin" and _config.yml.codex_plugin_path is stale:
  re-glob ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs
  update _config.yml.codex_plugin_path
```

Persist the resolved value to `_state.json.effective_generator_backend`.
Every Step 3.5 dispatch reads this; it is not re-evaluated mid-loop.

### Step 2: Execution Mode Selection

Mode is chosen once at loop start and persisted to `_state.json.mode`.
**Interactive mode is the only mode permitted to call
`AskUserQuestion`** during the loop.

Precedence: `--mode` CLI flag > existing `_state.json.mode` > interactive
prompt > `"continuous"` default.

| Mode | Loop control | AskUserQuestion |
|---|---|---|
| `interactive` | In-process; pause after each iter | allowed |
| `continuous` | In-process; run to completion | forbidden |
| `autonomous-ralph` | External shell wrapper; `claude -p --bare` per iter | forbidden |
| `scheduled` | Mix of continuous + Ralph at fixed cadence | forbidden |

For `autonomous-ralph` and `scheduled`, this skill exits after one iter;
the wrapper re-invokes it. **Open `references/autonomous-ralph.md`** for
the wrapper contract.

### Step 3: Load Current Sprint

Read `.harness/<epic>/roadmap.md` frontmatter; select the sprint where
`n == _state.json.current_sprint`. Load `contract.md`, `shared_state.md`,
and `feedback/` for that sprint.

If the sprint directory is missing (roadmap drift), set
`aborted_reason: "sprint-missing:<n>"` and halt.

Set `_state.json.phase = "negotiation"` if fresh; else keep as read.

### Step 3.5: Generator Dispatch (backend-aware)

**Open [references/generator-dispatch.md](references/generator-dispatch.md).**
Invoked by both Step 4 and Step 6.

Short summary (full detail in the reference):

- Render `prompt-templates/generator-<phase>.md` to a temp file with
  per-invocation substitutions
- Invoke per `_state.json.effective_generator_backend`: `Task` tool for
  `claude`, `node codex-companion.mjs task --fresh` for `codex_plugin`,
  `cmux-delegate codex` for `codex_cmux`
- Expect `feedback/generator-<iter>.md` + `generator-<iter>-report.json`
- Fallback: synthesise report.json from `git diff --name-only HEAD` with
  a progress.md WARN line
- Pipe report to `.harness/scripts/codex-progress-bridge.sh`

### Step 4: Negotiation Phase

**Open [references/negotiation-protocol.md](references/negotiation-protocol.md).**

```
if contract.status == "active":
  skip Step 4 (resume case, already negotiated)

for round in 1..contract.max_negotiation_rounds (default 3):
  Dispatch Generator (Step 3.5) with prompt-templates/generator-negotiation.md
  Dispatch Evaluator (Task tool, Claude) symmetrically
  Copy round summaries to shared_state.md/Negotiation
  if both agree: break

if no agreement after max rounds:
  Dispatch Planner (phase=ruling); Planner writes feedback/planner-ruling.md
  and overwrites contract.md rubric + max_iterations
```

Append one progress.md line per round:
`[<ts>] negotiation: round=<r> agent=<role> summary=<short>`

Finalise contract frontmatter (`acceptance_scenarios`, `rubric` from
rubric-presets, `max_iterations`). Flip `status: active`, record the
contract commit SHA in `shared_state.md/Contract`. Advance
`_state.json.phase = "impl"`.

### Step 5: Contract Freeze and Commit

```
git add .harness/<epic>/sprints/sprint-<n>-*/
git commit -m "harness-loop: sprint-<n> contract frozen"
```

Store SHA in `_state.json.last_commit`. Append progress.md:
`decision: sprint-<n> contract frozen @ <SHA>`.

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
  Bridge updates progress.md + _state.json from report.json.

  # Evaluator turn — Task tool, Claude, always
  _state.json.phase = "evaluation"
  Dispatch Evaluator with contract + shared_state + new source state +
    generator-<iter>.md + generator-<iter>-report.json
  Copy verdict to shared_state.md/WorkLog and /Evaluation.

  # Decide verdict + terminal state BEFORE Step 7 checkpoint so all
  # durable writes land in one atomic pass
  verdict = "pass" if all axes >= threshold else "fail"
  if verdict == "pass":
    contract.status = "done"; phase = "pr"; terminate = true
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
4. **Commit** — `git add -A && git commit -m "harness-loop: sprint-<n> iter-<iter>"`
   (non-fatal; log any failure and continue)

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
**restart (/clear → resume via Boot Sequence)** / **pause** /
**abort** via AskUserQuestion. Non-interactive modes skip this gate.

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
  if mode == interactive:
    AskUserQuestion: "Proceed to sprint <n+1>?"
  go to Step 3

else:
  completed = true; phase = "done"; go to Step 10
```

Reset policy: `cumulative_cost_usd` accumulates across the epic;
`start_time` resets per sprint.

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
| Generator dispatch fails | Log to feedback/generator-<iter>.md; retry once; 2nd fail → `pending_human=true` |
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

## References

All references are language-paired (`*.md` / `*.ja.md`).

- [references/generator-dispatch.md](references/generator-dispatch.md) — backend-aware Generator invocation
- [references/negotiation-protocol.md](references/negotiation-protocol.md) — round format, Planner ruling
- [references/shared-state-protocol.md](references/shared-state-protocol.md) — Shared-read / Isolated-write + report.json
- [references/pr-creation-guide.md](references/pr-creation-guide.md) — split / bundled PR templates
- [references/autonomous-ralph.md](references/autonomous-ralph.md) — headless shell wrapper
- [references/otlp-exporter.md](references/otlp-exporter.md) — optional metrics pipeline
- [references/prompt-templates/](references/prompt-templates/) — Generator prompt files
- [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md) — state / metrics schema
- [../harness-init/references/rubric-presets.md](../harness-init/references/rubric-presets.md) — axis sets by project type
- [../harness-init/references/scripts/codex-progress-bridge.sh](../harness-init/references/scripts/codex-progress-bridge.sh) — Orchestrator bridge


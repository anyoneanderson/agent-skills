---
name: spec-orchestrate
description: |
  End-to-end pipeline orchestrator — drive a GitHub Issue or a human request
  from specification through adversarial review, implementation, acceptance
  testing, and pull request, as a thin state machine that delegates every unit
  of work to a worker skill.

  Runs in manual mode (human sets the request and approves the spec once) or
  auto mode (an Issue number goes in, a PR comes out with no human gate). Never
  writes code, specs, tests, or reviews itself.

  English triggers: "Run the spec pipeline", "Orchestrate this issue to PR",
  "spec-orchestrate", "Take this feature from spec to PR"
  日本語トリガー: 「パイプラインを回して」「Issue から PR まで自動で」
  「spec-orchestrate を実行」「仕様から PR まで通して」
license: MIT
---

# spec-orchestrate — Spec-to-PR Pipeline Orchestrator

Drive one feature from a request or Issue all the way to a pull request by
running a fixed state machine and delegating each phase to a worker skill. This
skill is the conductor, not a performer: it reads state, calls a worker, checks
the result, updates state, and advances.

## Language Rules

1. **Auto-detect input language** → produce specs, reports, and PR body in the
   same language.
2. Japanese input → Japanese output, use the `*.ja.md` phase guides under
   `references/phases/`.
3. English input → English output, use the `*.md` phase guides.
4. Explicit override takes priority. The chosen language is recorded in state so
   every phase and every worker prompt stays consistent across a multi-hour run.

## Role: Orchestrator Only

> **🚨 BLOCKING — this rule overrides every phase guide.**

spec-orchestrate does **not** write specifications, code, tests, or reviews. It
delegates all of them. The only actions it performs directly are:

- Reading and writing `pipeline-state.json` (state is orchestrator-owned).
- Verifying worker results against machine-checkable evidence (git diff, result
  files, screenshots) — never trusting a worker's self-report.
- Running `gh` commands (Issue fetch, PR create, Issue comments).
- Composing and formatting worker prompts.

If a phase tempts you to "just fix it yourself", stop — that is a worker's job.
If the required worker skill is not installed, show its install step and halt
with state preserved (resumable).

## Options

| Option | Description |
|--------|-------------|
| `--mode {manual\|auto}` | Pipeline mode. Default: `manual` unless `--issue` is given, which implies `auto` |
| `--issue {N}` | GitHub Issue number (auto mode input) |
| `--spec {path}` | `.specs/{feature}/` directory. Default: derived from feature name |
| `--pipeline {path}` | `pipeline.yml` for roles and app recipe. Default: `.specs/pipeline.yml` |
| `--resume` | Resume from `pipeline-state.json`. This is the default behavior when a state file exists |

## Execution Model

The orchestrator runs one loop until the pipeline reaches a terminal state:

```
1. Read current phase from pipeline-state.json (or start at intake).
2. Open references/phases/<phase>.md and follow its Input → Action →
   Verification → State Update steps.
3. Dispatch the phase's worker (see Phase Index). Resolve claude vs codex
   backends with `references/role-dispatch.md` (claude → subagent, codex →
   agent-delegate).
4. Verify the worker's result. If it fails machine verification, do not advance.
5. Update pipeline-state.json (completed phase, round counts, fingerprints,
   thread ids) and select the next phase per the Transition Table.
```

The config file (`pipeline.yml`) and the state file (`pipeline-state.json`) —
their schemas, the jq/awk read/write idiom, and the orchestrator-only write rule
— are specified in `references/pipeline-config.md`.

**Resume is the default.** On startup, if `pipeline-state.json` exists, read it,
summarize the completed phases and the next action in one short block, and
continue from there. A full run spanning several hours and surviving a crash or
restart is the normal case, not an exception. See the Resume Behavior
section of `references/pipeline-config.md`.

## State Machine — Transition Table

Every state transition is listed here. The
`Guide` column is the phase file that carries the detailed Input / Action /
Verification / State-Update steps.

| From | Event / Condition | To | Guide |
|------|-------------------|-----|-------|
| (start) | pipeline launched | intake | `phases/intake.md` |
| intake | manual: dialogue complete / auto: Issue fetched | spec_generate | `phases/intake.md` |
| spec_generate | spec set + test.md written | inspect | `phases/spec_generate.md` |
| inspect | CRITICAL / WARNING (fix) | spec_generate | `phases/inspect.md` |
| inspect | INFO-only / PASS | spec_review | `phases/inspect.md` |
| spec_review | Critical / Improvement (fix) | spec_generate | `phases/spec_review.md` |
| spec_review | Gate PASS | approval | `phases/spec_review.md` |
| spec_review | stall signal | arbitration | `phases/spec_review.md` |
| approval | human feedback (manual) | spec_generate | `phases/approval.md` |
| approval | approved / auto passes through | implement | `phases/approval.md` |
| implement | tasks complete | evaluate | `phases/implement.md` |
| evaluate | failing findings (spec-code --feedback) | implement | `phases/evaluate.md` |
| evaluate | all cases pass | pr | `phases/evaluate.md` |
| evaluate | stall signal | arbitration | `phases/evaluate.md` |
| arbitration | continue / role swap | spec_review or implement | `references/stall-detection.md` |
| arbitration | draft PR landing | pr | `references/stall-detection.md` |
| pr | PR created (incl. draft) | retrospective | `phases/pr.md` |
| retrospective | report + improvements done | (end) | `phases/retrospective.md` |

**Ordering principle:** run the cheap machine check (inspect) before the
expensive semantic check (adversarial spec_review), so a peer LLM's tokens are
never spent on formatting defects.

**Arbitration** is entered only when a stall signal fires in spec_review or
evaluate. Its detection algorithm (fingerprints and signals S1–S3, evaluated
from `state.rounds` alone) and adjudication branches (manual asks the human; auto
swaps the owner up to `limits.role_swap_max`, else lands a draft PR) are defined
in `references/stall-detection.md`.

## Phase Index — Worker and Role

| Phase | Worker | Role key | Guide |
|-------|--------|----------|-------|
| intake | (orchestrator) | — | `phases/intake.md` |
| spec_generate | spec-generator (planner) | `spec_author` | `phases/spec_generate.md` |
| inspect | spec-inspect | (machine check) | `phases/inspect.md` |
| spec_review | adversarial review (backend per `spec_reviewer`) | `spec_reviewer` | `phases/spec_review.md` |
| approval | human (AskUserQuestion) | — | `phases/approval.md` |
| implement | spec-implement | `impl_ui` / `impl_backend` / `impl_test` | `phases/implement.md` |
| evaluate | spec-evaluate | `e2e_runner` | `phases/evaluate.md` |
| pr | spec-implement final step + evidence | — | `phases/pr.md` |
| retrospective | orchestrator (aggregate) + worker (edits) | — | `phases/retrospective.md` |

Role keys resolve to a backend (claude subagent or codex via agent-delegate)
through `references/role-dispatch.md`. If `pipeline.yml` is absent, the default
roles apply and the app recipe is empty.

## Intake Summary

The entry phase turns a request into a working spec directory and an initial
state file. Full steps live in `phases/intake.md`; the shape is:

- **manual:** hand the natural-language request to spec-generator's interactive
  mode. The human dialogue happens inside the planner run. The feature name is
  fixed during that dialogue.
- **auto:** `gh issue view <N> --json title,body,labels`, reshape the result
  into a no-dialogue planner input, and derive the feature name as kebab-case
  from the Issue title.

Both modes then write the initial `pipeline-state.json` (mode, issue, feature,
language, `phase: spec_generate`) and proceed.

## Error Handling

In every case, state is preserved so the run is resumable.

| Situation | Response |
|---|---|
| Worker skill not installed | Show its install step and stop; state kept (resumable) |
| agent-delegate unavailable (codex missing, etc.) | manual: ask the human to confirm reassigning to claude. auto: reassign, continue, record in `state.role_overrides` and the PR body |
| `gh` auth error / Issue not found | Stop in intake; show the account-check steps (see GIT_ACCOUNTS.md) |
| App fails to start during evaluate | Mark dependent cases blocked; show the recipe and `ready_pattern`. Blocked ≠ failed |
| Worker result file is malformed | Re-run that worker once; if it recurs, mark blocked and route to arbitration |
| Uncommitted git changes appear mid-run | Compare against the phase-start snapshot; on drift, warn and open a human gate (auto: post an Issue comment) |

## Usage Examples

```
# Manual: talk through the spec, approve once, walk away
/spec-orchestrate --mode manual

# Auto: hand over an Issue, come back to a PR (--issue implies auto)
/spec-orchestrate --mode auto --issue 42

# Resume a multi-hour run after a restart (default when state exists)
/spec-orchestrate --resume --spec .specs/user-auth/
```

---
name: spec-evaluate
description: |
  Run a black-box acceptance test plan (test.md) against a finished
  implementation and produce a structured pass/fail result.

  Executes each test case by its verification method (playwright / command /
  file-check), launches the app from a project recipe, saves screenshots and
  logs as evidence, and writes a spec-review-compatible findings file that
  spec-code --feedback can consume. Runs standalone or inside the
  spec-orchestrate pipeline, on a Claude subagent or a delegated peer LLM.

  English triggers: "Acceptance test this feature", "Run spec-evaluate",
  "Verify against test.md", "Run the acceptance test plan"
  日本語トリガー: 「この機能を受け入れ試験して」「spec-evaluateを実行」
  「test.md を実行」「受け入れテストを回して」
license: MIT
---

# spec-evaluate — Acceptance Test Runner

Execute the acceptance test plan (test.md) against the built feature, capture
evidence, and report requirement-level pass/fail as findings that feed back
into the implementation loop.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use the `*.ja.md` reference files
3. English input → English output, use the `*.md` reference files
4. Explicit override takes priority

The evaluator instruction sheet is `references/evaluator-prompt.md`
(`.ja.md` for Japanese). The result file format is `references/result-format.md`
(`.ja.md` for Japanese).

## Options

| Option | Description |
|--------|-------------|
| `--spec {path}` | Path to the `.specs/{feature}/` directory (contains test.md). Required |
| `--round {n}` | Evaluation round number (default: auto-detect from existing `evaluate-{n}.md`, else 1) |
| `--pipeline {path}` | Path to `pipeline.yml` for the app launch recipe and roles (default: `.specs/pipeline.yml`) |
| `--backend {self\|claude\|codex}` | Execution backend override (default: resolved from `e2e_runner`, else `self`) |
| `--output {path}` | Result file path (default: `.specs/{feature}/evaluate-{round}.md`) |

## Core Principle — Evidence Over Self-Report

An evaluator claiming "I tested it and it passed" is not trusted. Every passing
case must point to real evidence on disk (a screenshot, a command log, or a
verified artifact). Before a result is accepted, the evidence pointers in it are
checked for existence: **a case marked PASS whose referenced evidence file does
not exist is forced to FAIL**, regardless of what the evaluator reported.
See §Evidence Rules and `references/result-format.md`.

## Execution Flow

The runner (SKILL.md) is a thin driver: it prepares inputs, dispatches the
single evaluator instruction sheet to the chosen backend, then machine-verifies
the returned result. It does not itself decide pass/fail from memory.

### Step 1: Load Inputs

1. Read `{spec}/test.md`. If missing → stop with an error (nothing to run).
2. Parse each case: ID (`T-Axx`), requirement ID, Steps, Expected, Verify
   method (`playwright` / `command` / `file-check`), Command.
3. Read the launch recipe and roles from `pipeline.yml` (`app:` and
   `roles.e2e_runner`). If `pipeline.yml` is absent, there is no app recipe and
   no role assignment — proceed with `backend = self` and no app launch.

### Step 2: Resolve Execution Backend

Resolution order: `--backend` flag > `roles.e2e_runner` from `pipeline.yml` >
`self`.

| Backend | How the evaluator runs |
|---------|------------------------|
| `self` | The current agent executes `references/evaluator-prompt.md` directly. Used for standalone runs outside the pipeline |
| `claude` | Dispatch a subagent with `references/evaluator-prompt.md` as its instructions |
| `codex` | Delegate to the peer LLM via agent-delegate (see §Delegated Backend) |

The evaluator instruction sheet is the **same one file** for every backend; only
the execution vehicle changes. See `references/execution-backend.md`.

### Step 3: Determine Round and Prepare Evidence Directory

1. Round number: from `--round`, else `max(existing evaluate-{n}.md) + 1`, else 1.
2. Create `{spec}/evidence/{round}/`. This is where all screenshots and logs go.

### Step 4: Run the Evaluator

Compose the runtime context (test.md path, parsed cases, app recipe, evidence
directory, round, output path) and hand it to the backend together with
`references/evaluator-prompt.md`. The evaluator:

1. Launches the app from the recipe if any `playwright` case is present.
2. Executes every case top-to-bottom by its verification method.
3. Saves evidence per case under `{spec}/evidence/{round}/`.
4. Stops the app.
5. Writes the result file in the `references/result-format.md` format.

For a UI (`playwright`) case with no `app:` recipe available, the evaluator
marks the case **blocked (skipped + warning)**, which is distinct from a test
failure. See §App Recipe Missing.

### Step 5: Machine-Verify Evidence (do not skip)

After the backend returns, the runner independently checks the result file:

1. For every case reported PASS, read its evidence pointer(s).
2. Resolve each pointer relative to `{spec}/` and test for existence.
3. Any PASS case with a missing or empty evidence file → rewrite it to FAIL and
   add a Critical finding noting the missing evidence.
4. Recompute the Gate line after any such downgrade.

This step is what makes the evidence principle enforceable rather than advisory.

### Step 6: Emit Result

Write the finalized result file to `--output` (default
`{spec}/evaluate-{round}.md`). Report a one-line summary: round, pass/total,
gate, and the evidence directory path.

## Delegated Backend (codex)

When `backend = codex`, run the evaluator through agent-delegate. Acceptance
testing launches the app and drives a browser, so it needs write access — use
**`--mode delegate --sandbox workspace-write`, never review mode** (review is
read-only and cannot launch or operate the app).

1. Write a prompt file that is `references/evaluator-prompt.md` followed by the
   runtime context block (Step 4).
2. Invoke the delegate script with an explicit target and detached execution
   (E2E commonly exceeds the ~10-minute synchronous ceiling):

   ```bash
   report="$(agent-delegate.sh --mode delegate --target codex \
     --sandbox workspace-write --prompt-file <prompt> \
     --out-dir {spec}/evidence/{round} --detach | tail -1)"
   until [ -f "$report" ]; do sleep 15; done
   ```

3. Read `status` from `report.json`. On `blocked`, treat the run as an
   evaluation failure with the blocker recorded, not a silent pass.

Depend only on the agent-delegate public contract (arguments and `report.json`
schema), never on the script's internals. Details:
`references/execution-backend.md`.

## Evidence Rules

- Evidence lives in `{spec}/evidence/{round}/`.
- Naming: `T-{id}-*.png` for screenshots, `T-{id}-*.log` for command output and
  browser console/network logs (e.g. `T-A01-login.png`, `T-A02-latency.log`).
- The result file references evidence by **relative pointer**, never by
  embedding the content.
- A PASS with a dangling evidence pointer fails machine verification (§Step 5).

## App Recipe Missing

A `playwright` case needs the `app:` recipe (start command, URL). When it is
absent or incomplete:

- Mark the affected cases **blocked** with a warning, distinct from FAIL.
- Standalone / `self`: report the blocked cases and the missing recipe fields so
  the caller can supply them; do not fabricate a pass.
- Inside the pipeline the orchestrator decides escalation (manual asks the
  human; auto routes blocked to arbitration). spec-evaluate only reports the
  blocked state faithfully; it does not upgrade blocked to pass.

## Error Handling

| Situation | Response |
|---|---|
| `test.md` missing under `--spec` | Error: nothing to evaluate; stop |
| `pipeline.yml` missing | Proceed with `backend = self`, no app launch; `playwright` cases become blocked |
| App fails to start / `ready_pattern` never matches | Mark dependent cases blocked; report the recipe and captured startup log; distinct from FAIL |
| Result file from backend is malformed | Re-run the evaluator once; if it recurs, report blocked (do not guess results) |
| agent-delegate unavailable (codex missing) | Report it; standalone falls back to `self`, pipeline escalation is the orchestrator's call |
| Evidence directory not writable | Error: cannot guarantee evidence; stop before running |

## Usage Examples

```
# Standalone acceptance test (runner is the evaluator)
/spec-evaluate --spec .specs/user-auth/

# Specific round with an explicit backend override
/spec-evaluate --spec .specs/user-auth/ --round 2 --backend self

# Pipeline use: backend follows roles.e2e_runner from pipeline.yml
/spec-evaluate --spec .specs/user-auth/ --pipeline .specs/pipeline.yml
```

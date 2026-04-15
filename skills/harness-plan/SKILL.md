---
name: harness-plan
description: |
  Plan an epic for /harness: draft product-spec.md interactively, derive
  roadmap.md with sprint decomposition and bundling, then emit one tracker
  Issue per sprint. The last human-in-the-loop step before autonomous
  sprints begin in /harness-loop.

  Prerequisite: /harness-init must have already initialised .harness/ and
  .claude/agents/ in this project. This skill is not for spec-driven
  (/spec-generator) workflows.

  English triggers: "Plan the epic", "Run harness-plan", "Create product-spec"
  日本語トリガー: 「epic を計画」「harness-plan を実行」「product-spec を作成」
license: MIT
---

# harness-plan — Epic Planning for the Harness Control Loop

Fills the gap between `harness-init` (environment setup) and `harness-loop`
(autonomous sprints). Runs **once per epic**. Re-runs continue the same
epic draft from wherever it was interrupted.

The skill orchestrates the Planner sub-agent through three artifacts:

1. `product-spec.md` — What / Why / Out of Scope / Constraints (interactive)
2. `roadmap.md` — sprint decomposition with `bundling: split|bundled`
3. One tracker Issue per sprint (when `_config.yml.tracker != none`)

After this skill finishes, the project is ready for `/harness-loop`.

## Language Rules

1. Auto-detect input language → output in the same language
2. Japanese input → Japanese output
3. English input → English output
4. Explicit override (e.g., "in English", "日本語で") takes priority
5. All `AskUserQuestion` options are bilingual (`"English / 日本語"`)

Reference files exist as `<name>.md` (English) and `<name>.ja.md` (Japanese).
Pick the pair matching the detected language for narrative guidance; YAML
schemas and templates are language-agnostic.

## Prerequisites

Before any generation step, check:

1. **Harness initialised** — `.harness/_config.yml` and
   `.harness/templates/product-spec.md` must exist. If not, instruct the
   user to run `/harness-init` first and stop.
2. **Git repo** — `git rev-parse --is-inside-work-tree` must succeed.
3. **`jq` available** — `command -v jq`. Required for `_state.json`
   reads/writes (ASM-005).
4. **Tracker pre-flight** — if `_config.yml.tracker == github`, verify
   `gh auth status` now to fail fast. See
   [issue-create.md](references/issue-create.md) §Pre-flight.

If any check fails, stop with a clear error. Do not partially generate.

## Boot Sequence (REQ-072)

Always execute before any write:

1. `git log --oneline -20`
2. `tail -100 .harness/progress.md` (if it exists)
3. `cat .harness/_state.json` (if it exists)

If `_state.json.phase ∈ {product-spec-draft, roadmap-draft,
roadmap-approved, issues-pending}`, the skill offers **resume** vs
**restart** via `AskUserQuestion`. `harness-plan` runs prior to
`harness-loop` so `mode` is not yet decided — the Boot Sequence here
always behaves interactively. If the user invoked with
`--auto-approve-roadmap`, resume is chosen automatically; otherwise the
user confirms.

## Execution Flow (10 steps)

### Step 1: Detect Existing Epic

```
if .harness/<any-epic>/product-spec.md exists:
  AskUserQuestion:
    question: "Existing epic(s) detected. What to do?" /
              "既存の epic を検出しました。"
    options:
      - "Continue the most recent epic / 最新 epic を継続"
      - "Start a new epic / 新規 epic を開始"
      - "Cancel / キャンセル"
```

"Continue" picks the epic named in `_state.json.current_epic`, or the
most recently modified `.harness/<epic>/` directory if state is silent.
"Start new" prompts for epic name (Step 2). "Cancel" exits cleanly.

With `--auto-approve-roadmap`, the skill always continues when state is
populated, else starts new with a derived epic name (kebab-case from
the first 3 non-stopword tokens of the user prompt).

### Step 2: Epic Name

```
AskUserQuestion:
  question: "Epic name (kebab-case)?" / "Epic 名（kebab-case）?"
  options:
    - "<suggested from prompt, e.g., auth-suite> (Recommended)"
    - "Let me type it / 手入力"
```

Validation:
- Kebab-case regex `^[a-z][a-z0-9-]{2,40}$`
- Not already present under `.harness/`
- If invalid, re-ask once with the regex in the message

Create `.harness/<epic>/` and switch `_state.json.current_epic` to this
name.

### Step 3: Copy product-spec Template

Copy `.harness/templates/product-spec.md` →
`.harness/<epic>/product-spec.md` if the target does not exist. If it
exists from a previous run, keep it — Step 4 resumes in place.

### Step 4: Interactive product-spec Drafting

Follows [product-spec-guide.md](references/product-spec-guide.md). The
Planner walks the five sections in order — Why, What, Out of Scope,
Constraints, Success Signals — asking section-specific
`AskUserQuestion` rounds and writing answers into the matching section
of `.harness/<epic>/product-spec.md`.

Key enforcement (from the guide):

- Reject "How" leakage (framework / library / schema picks) and redirect
  to Constraints only if externally mandated
- Bullet count target for What: 3–7
- Success Signals may be empty; mark `success_signals: unspecified` in
  frontmatter if so

Set `_state.json.phase = "product-spec-draft"` at step start. Keep it at
`"product-spec-draft"` until the Planner declares the spec complete via
the cross-check checklist; the transition out happens when Step 5 begins
(phase is advanced to `"roadmap-draft"` there).

Before moving to Step 5, the Planner runs the **cross-check checklist**
from the guide. Any "no" answer re-opens the relevant section via
`AskUserQuestion`. If the skill was invoked with `--auto-approve-roadmap`
(interview was pre-filled or resumed without user intervention), emit a
`TODO(product-spec):` line to `progress.md` instead of re-opening — the
user must resolve before harness-loop starts.

Commit: `git add .harness/<epic>/product-spec.md && git commit -m "harness-plan: product-spec for <epic>"`.

### Step 5: Planner Generates roadmap.md

Invoke the Planner sub-agent (defined at `.claude/agents/planner.md` by
`harness-init`) with:

- `.harness/<epic>/product-spec.md` as input
- [roadmap-guide.md](references/roadmap-guide.md) as the decomposition and
  bundling doctrine

Output: `.harness/<epic>/roadmap.md` with YAML frontmatter listing sprints
and bundling flags. See the guide §`roadmap.md Output Format` for the
canonical schema.

The Planner must:

- Emit `split` by default; bundle only with a written `bundling_reason`
  citing one of the four coupling axes (schema, auth, UI, contract)
- Enforce reciprocal `bundled_with` references
- Cap sprints at 6 per epic; if more, pause and advise the user to split
  the epic. With `--auto-approve-roadmap`, truncate with a
  `TODO(epic-split)` note in `progress.md` for post-hoc resolution
- Cap bundle size at 3 sprints

Set `_state.json.phase = "roadmap-draft"` at step start.

### Step 6: Roadmap Approval (T-024)

The roadmap approval gate is **always interactive** per REQ-021. The
`mode` value (`interactive` / `continuous` / `autonomous-ralph` /
`scheduled`) is selected at `harness-loop` startup (REQ-078), not at
`harness-init`, so `harness-plan` has no basis for implicit acceptance.
The only exception is explicit user override via the
`--auto-approve-roadmap` flag (see §Usage).

Default path (no flag):

```
AskUserQuestion:
  question: "Roadmap: <N> sprints, <M> bundle groups. Approve?" /
            "Roadmap: <N> sprints, <M> bundle。承認？"
  (Show Sprint Summary table from roadmap.md as description)
  options:
    - "Approve / 承認"
    - "Request changes / 変更を要求"
    - "Cancel / キャンセル"
```

- **Approve** → proceed to Step 7
- **Request changes** → collect free-form change request via a follow-up
  `AskUserQuestion`; Planner regenerates roadmap.md with the feedback.
  Loop at most 3 times — after that, abort to `Cancel` with a note in
  `progress.md`
- **Cancel** → write `progress.md` line, leave roadmap.md as draft, exit

With `--auto-approve-roadmap` flag: skip the prompt and proceed to
Step 7 directly. Append one progress line recording auto-approval
(`[<ts>] auto-approved via --auto-approve-roadmap`). The user takes
responsibility for pre-reviewing roadmap.md before invoking this mode.

Set `_state.json.phase = "roadmap-approved"` on approval (either path).

Commit: `git add .harness/<epic>/roadmap.md && git commit -m "harness-plan: roadmap for <epic>"`.

### Step 7: Pre-fill Sprint Contracts

For each sprint in `roadmap.md.sprints`:

1. Create directory `.harness/<epic>/sprints/sprint-<n>-<feature>/`
2. Copy `.harness/templates/sprint-contract.md` →
   `.harness/<epic>/sprints/sprint-<n>-<feature>/contract.md`
3. Pre-fill the YAML frontmatter from `_config.yml` + the roadmap entry:
   - `sprint`, `feature`, `bundling`
   - `max_iterations` ← `_config.yml.max_iterations`
   - `max_negotiation_rounds` ← `_config.yml.negotiation_max_rounds`
   - `status: negotiating`
4. Leave `acceptance_scenarios` and `rubric` as empty stubs — they are
   negotiated inside `harness-loop`, not here. The rubric axis set is
   chosen then from `rubric-presets.md` based on `_config.yml.rubric_preset`
   and the sprint risk

Also copy `.harness/templates/shared_state.md` →
`.harness/<epic>/sprints/sprint-<n>-<feature>/shared_state.md` and
create an empty `evidence/` subdirectory.

### Step 8: Create Tracker Issues (T-023)

Set `_state.json.phase = "issues-pending"` at step start so resume after
a mid-loop failure can locate the correct entry point. Dispatch on
`_config.yml.tracker`. Full detail in
[issue-create.md](references/issue-create.md):

- `github` → `gh issue create` per sprint, with duplicate detection and
  epic-link formatting. On every successful create, append to
  `_state.json.sprint_issues[<n>]` atomically so resume can skip
  already-created sprints
- `gitlab` → record pending payloads to
  `.harness/<epic>/pending-issues.md` (an epic-level ledger file owned by
  harness-plan). `shared_state.md` is sprint-scoped and does not exist
  yet at this phase — never write there. No CLI call in v1
- `none` → skip; emit one progress line noting tracker-free mode

**`gh` CLI absence**: if `tracker == github` and `gh` is missing, abort
the skill. Do not silently fall back to gitlab / none — the user's
tracker choice is load-bearing for the audit trail (REQ-023).

On failure mid-loop, `_state.json.phase` stays at `"issues-pending"` and
partial `sprint_issues` is preserved. Resume re-enters Step 8 and the
duplicate-detection path in `issue-create.md` skips the already-created
sprints.

### Step 9: Finalize Handoff Cursor in `_state.json`

Step 8 already transitioned `phase` to `"ready-for-loop"` and built up
`sprint_issues` incrementally. Step 9 finalizes the remaining cursor
fields that `harness-loop` reads on its Boot Sequence:

```json
{
  "current_epic": "<epic>",
  "current_sprint": 1,
  "phase": "ready-for-loop",
  "iteration": 0,
  "last_agent": "planner",
  "next_action": "harness-loop:negotiate-sprint-1",
  "completed": false,
  "pending_human": false,
  "aborted_reason": null
}
```

Preserve all other fields written by `harness-init` (`max_iterations`,
`max_wall_time_sec`, `max_cost_usd`, `allowed_mcp_servers`, etc.). The
`mode` field is **not** set here — it is written by `harness-loop` on
startup (REQ-078). Use a merge, not a replace, via
`jq '.foo = "bar"'` on the existing file.

### Step 10: Summary Report

Emit to the user:

- Epic directory path: `.harness/<epic>/`
- Product-spec path
- Roadmap path, with sprint count and bundle group summary
- Tracker issues created (count and URLs if GitHub)
- Recommended next action:
  `/harness-loop` to start sprint 1

Also append one progress line:

```
[<ts>] harness-plan: epic=<name> sprints=<N> bundles=<M> tracker=<github|gitlab|none>
```

## Error Handling

| Situation | Response |
|---|---|
| `.harness/_config.yml` missing | Error: "Run /harness-init first." |
| `jq` not found | Error: "Install `jq` — all harness tooling requires it." |
| Epic name collision | Re-ask by default; append `-N` suffix with `--auto-approve-roadmap` |
| Planner exceeds 6 sprints | Pause by default; truncate with TODO note with `--auto-approve-roadmap` |
| Bundle size > 3 | Hard-split by Planner; log decision to `progress.md` |
| Reciprocal `bundled_with` mismatch | Planner regenerates once; fail if still broken |
| `gh` CLI missing when tracker=github | Abort per [issue-create.md](references/issue-create.md). Do not fall back to gitlab / none |
| Roadmap approval cancelled | Leave draft roadmap.md, exit. Re-run continues |
| Write failure mid-flow | Partial state preserved; `progress.md` records failure line; resume-safe |

## Usage

```
# First run for a new epic
/harness-plan

# Resume an interrupted draft (same command, same behaviour)
/harness-plan

# Plan with an explicit epic name and parent Issue
/harness-plan --epic-name auth-suite --epic 142

# Replan an existing epic (edit product-spec or roadmap externally first)
/harness-plan --replan

# Skip the roadmap approval gate (user pre-reviews roadmap.md themselves)
/harness-plan --auto-approve-roadmap
```

`--replan` re-enters at Step 5 (roadmap generation) using the existing
`product-spec.md` as input.

`--auto-approve-roadmap` is the sole mechanism for bypassing the
interactive approval gate in Step 6. The skill does not infer autonomy
from `_config.yml` or from any harness-loop mode — those are decided
after this skill finishes. If this flag is passed, the user takes
responsibility for reviewing `roadmap.md` before invoking; the flag is
logged to `progress.md` as an audit trail.

## What harness-plan does NOT do

- Does not run any sprint — that is `harness-loop`'s job
- Does not negotiate the sprint contract rubric — that happens inside
  `harness-loop`'s Negotiation phase
- Does not create PRs — PRs are a `harness-loop` output
- Does not re-configure hooks or scripts — re-run `/harness-init` for that
- Does not pick the Generator backend, evaluator tools, or hook level —
  those are `_config.yml` values owned by `harness-init`

## References

- [product-spec-guide.md](references/product-spec-guide.md) — section-by-
  section interview prompts, anti-patterns, cross-check list
- [roadmap-guide.md](references/roadmap-guide.md) — decomposition rules,
  bundling judgement, roadmap.md output schema
- [issue-create.md](references/issue-create.md) — tracker dispatch,
  duplicate detection, epic link syntax
- [../harness-init/references/resilience-schema.md](../harness-init/references/resilience-schema.md)
  — `_state.json` schema this skill updates

See `.specs/harness-suite/` in the source repo for requirement.md,
design.md, and tasks.md governing this skill.

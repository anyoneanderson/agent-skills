# Harness Git Strategy

This document specifies who in the harness control loop is allowed to
run git mutation commands and which files belong to git's tracked vs
gitignored set. Read it before any iteration so you do not commit
files yourself and so you reason about `git status` under the correct
mental model.

## Audience

Every harness role reads this file. The primary audience is the
**agents** (Generator / Evaluator / Planner) — the rules below tell
each role what NOT to touch. The Orchestrator (harness-loop) and the
init-time setup also rely on this file.

| Role | When you read this file | What this file tells you |
|---|---|---|
| Generator (claude / codex_cli / codex_cmux) | Every iteration (Boot Sequence) | You write to disk only. NEVER run `git add` / `commit` / `push`. |
| Evaluator | Every iteration (Boot Sequence) | You write to disk only. NEVER run `git add` / `commit` / `push`. |
| Planner | Every invocation (interview / roadmap / contract-draft / ruling / mid-impl-replan) | You write to disk only. NEVER run `git add` / `commit` / `push`. |
| Orchestrator (harness-loop / harness-plan) | harness-loop Step 7 (atomic per-iter checkpoint) / harness-plan Step 4 + Step 6 (product-spec + roadmap commits) | You own commits — every git mutation in the harness flow. |
| user / `harness-init` | Project setup time | Add the entries below to `.gitignore`. |

## Commit ownership rule (MANDATORY)

The Orchestrator skills (`harness-plan` and `harness-loop`) are the
**sole roles** that may run git mutation commands (`git add`,
`git commit`, `git push`, `git rebase`, `git reset --hard`, branch
creation / deletion, etc.) inside the harness flow.

Generator / Evaluator / Planner MUST NOT execute any git mutation
command. Concretely:

- **Generator** writes source code, test code, docs, and the mandatory
  `feedback/generator-<iter>.md` + `feedback/generator-<iter>-report.json`
  pair to disk and exits. `harness-loop` Step 7 captures everything
  via `git add -A && git commit -m "harness-loop: sprint-<n> iter-<iter>"`.
- **Evaluator** writes `${SPRINT_DIR}/evidence/iter-<n>/` artefacts (Playwright
  traces, screenshots, curl logs, Python timing JSON, Playwright logs)
  and `feedback/evaluator-<iter>.md` (or `evaluator-neg-<round>.md`) to
  disk and exits. `harness-loop` Step 7 commits.
- **Planner** writes:
  - during `harness-plan`: `product-spec.md` (interview),
    `roadmap.md` (roadmap), and sprint `contract.md` skeletons
    (contract-draft);
  - during `harness-loop`: `feedback/planner-ruling.md`
    (negotiation-stalemate ruling) or
    `feedback/planner-ruling-impl-<iter>.md` (mid-impl replan) and
    the `contract.md` overwrites the ruling phase requires.

  The dispatching skill commits — `harness-plan` Step 4 commits the
  `product-spec.md`, `harness-plan` Step 6 commits the `roadmap.md`,
  and `harness-loop` Step 7 covers everything else (contract-drafts
  ride along with the sprint's first commit, rulings ride along with
  the iteration commit they affect).

Why a single committer per skill: each Orchestrator skill batches its
writes into atomic checkpoints. `harness-loop` Step 7 co-writes
`_state.json`, `metrics.jsonl`, `progress.md`, and the git commit in
one pass per iteration; `harness-plan` Step 4 / Step 6 commit the
planning artefacts after the relevant Planner sub-agent has exited.
Letting agents commit independently would (a) split a logical
iteration across multiple commits with stale `shared_state.md` /
`metrics.jsonl`, (b) reorder `progress.md` vs `git log` on resume, and
(c) bypass the Tier-A guard hooks that wrap the Orchestrator's
commit. The harness model assumes exactly one committer per skill.

If a step you are tempted to run looks like `git add ...`, `git commit
...`, `git push ...`, `git checkout -b ...`, `git rebase ...`,
`git reset --hard ...`, `git stash ...` — stop. The Orchestrator
handles it. Surface the need via your `feedback/<role>-<iter>.md`
narrative if a non-trivial git operation is required (e.g. branch
rename), and let the Orchestrator decide.

## Design principle (file taxonomy)

Files under `.harness/` fall into two classes:

1. **Immutable audit trail** — sprint decisions, contracts, deliverables.
   **Tracked in git** so PR reviewers can replay the sprint via
   `git log` + `shared_state.md` alone.
2. **Per-iter / per-session artefacts** — agent-internal thoughts,
   Evaluator regenerated evidence, wrapper transient state.
   **Gitignored** so PR diffs stay code-centric and main's history
   does not drown in skill-internal state churn.

Drawing this line keeps PR review feature-focused and keeps main's
commit log free of "sprint-1 iter-3 SHA stamp"–style noise.

## Tracked set (keep these in git)

| Path | Role |
|---|---|
| `.harness/_config.yml` | Skill configuration (backend / hook_level / mid_impl_replan / ...) |
| `.harness/_state.json` | Machine cursor; required for resume |
| `.harness/progress.md` | Human-readable worklog (append-only) |
| `.harness/metrics.jsonl` | Per-iter metrics; Principal Skinner monitor source |
| `.harness/tier-a-patterns.txt` | Tier-A guard regex set (hook config) |
| `.harness/scripts/*` | Hook scripts (progress-append / tier-a-guard / stop-guard / ralph-loop / ...) |
| `.harness/templates/*` | Skill templates (review subject) |
| `.harness/<epic>/product-spec.md` | Epic planning artefact |
| `.harness/<epic>/roadmap.md` | Sprint decomposition |
| `.harness/<epic>/sprints/sprint-*/contract.md` | **Contract** — accept criteria / rubric / negotiation log / Sprint Outcome |
| `.harness/<epic>/sprints/sprint-*/shared_state.md` | **Sprint ledger** — Plan / Negotiation / WorkLog / Evaluation / Decisions summaries |
| `.harness/sprint-durations.md` (optional) | Duration ledger; only if the team maintains it |

## Gitignored set (do NOT track)

| Path | Why excluded |
|---|---|
| `.harness/*.backup-*` | Old state snapshots (transient) |
| `.harness/.mcp-wildcard-warned` | One-shot warning marker |
| `.harness/<epic>/sprints/sprint-*/feedback/` | Per-iter agent thoughts (`generator-*.md` / `evaluator-*.md` / `planner-ruling-*.md` / `*-neg-*.md`) |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-exec-*.jsonl` | codex_cli internal raw output |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-exec-*.stderr` | Same as above |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-last-*.txt` | Same as above |
| `.harness/<epic>/sprints/sprint-*/feedback/*-report.json` | Generator dispatch report (touchedFiles, etc.) / Evaluator compliance report |
| `.harness/<epic>/sprints/sprint-*/evidence/**` | Playwright traces / screenshots / curl logs / Python timing JSON |
| `.harness/ralph.log` | Wrapper stdout (transient) |
| `.harness/ralph.pid` | Wrapper pid (consume-and-delete) |
| `.harness/NEXT_SESSION_PROMPT.md` | Session handoff (consume-and-delete) |

### Why feedback / evidence are safe to gitignore

- **`feedback/*.md`** are agent-internal thoughts. The Orchestrator
  copies a summary into `shared_state.md`'s WorkLog / Evaluation /
  Negotiation / Decisions sections at every iter close, so cross-session
  reconstruction works from `shared_state.md` alone (see
  `shared-state-protocol.md`). The Planner's mid-impl replan dispatch
  reads disk-resident feedback files generated **in the current
  session**; it does not need them across sessions.
- **`${SPRINT_DIR}/evidence/iter-<n>/`** is Evaluator output for one iteration.
  Evaluators re-run their verification against the live contract on
  every iteration, so the latest evidence is the source of truth, not
  the historical accumulation.
- **`codex-exec*` / `codex-last*`** is codex_cli internal raw output
  (internal prompt / reasoning + bulky size); both confidentiality and
  size argue against tracking.

## Migration for existing projects

When `feedback/` or `evidence/` is already tracked, untrack it while
leaving the working files in place:

```bash
git rm --cached -r \
  .harness/*/sprints/*/feedback/ \
  .harness/*/sprints/*/evidence/

# Single files
git rm --cached .harness/ralph.log 2>/dev/null || true
git rm --cached .harness/ralph.pid 2>/dev/null || true
git rm --cached .harness/NEXT_SESSION_PROMPT.md 2>/dev/null || true

git add .gitignore
git commit -m "chore(harness): untrack feedback/evidence/runtime artifacts per harness git-strategy"
```

If sprint branches are in flight, repeat the operation per branch or
run it on the main branch and rebase / merge it in. Never force-push
to rewrite history — the Tier-A guard is expected to block that.

This migration is the only situation in which a human (not the
Orchestrator) runs git mutation commands related to harness state. It
is a one-time cleanup, not part of the per-iter loop, so the
agents-don't-commit rule is unaffected.

## Upstream (agent-skills) sync

When syncing this rule upstream:

1. The harness-init skill's Step 10 only emits the `.gitignore` entries
   and links here for the rationale.
2. Both `.claude` and `.codex` mirrors must hold identical content
   (md5-sync policy applies to
   `.claude/skills/harness-loop/references/git-strategy.md` ↔
   `.codex/skills/harness-loop/references/git-strategy.md`, and the
   same for the `.ja.md` pair).
3. Future enhancement: have harness-init auto-apply the `.gitignore`
   entries on first install instead of nudging the user. New projects
   will then default to clean PRs.

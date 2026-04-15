# PR Creation Guide

Covers REQ-033. On sprint pass, `harness-loop` opens a pull request
whose body is a standardised summary of what shipped and why the
Evaluator accepted it. Split and bundled sprints use the same
template with minor header differences.

## Pre-conditions

Before PR creation, verify:

1. `contract.status == "done"` (all rubric axes ≥ threshold on the
   final iteration)
2. `_state.json.aborted_reason == null`
3. The sprint branch exists locally and is ahead of the parent branch
   by at least one commit
4. `_config.yml.tracker == "github"` (this guide only covers GitHub;
   gitlab and none cases are covered at the end)

If any pre-condition fails, do not open a PR. Log the reason to
`shared_state.md/Decisions` and `progress.md`, then return to Step 9
(Sprint Transition) of the SKILL flow.

## Branch model

```
main (or _config.yml.default_branch)
 └── harness/<epic>                 ← epic branch (optional; see below)
      ├── harness/<epic>/sprint-1-<feature>    ← split sprint PR branch
      └── harness/<epic>/sprint-2-<bundle>     ← bundled sprint PR branch
```

Two valid shapes:

- **Flat**: each sprint branches directly off `main`. PR target is
  `main`. Simplest; recommended for < 4 sprint epics.
- **Epic stacking**: one epic branch off `main`, sprint branches off
  epic branch, PRs target the epic branch, and the epic is merged
  last. Better for reviewer context in large epics. Requires
  `_config.yml.pr_stack == true`.

Pick one at epic start and record in `_state.json.pr_model`. Do not
mix within an epic.

## Split PR (one sprint = one feature = one PR)

### `gh pr create` invocation

```bash
gh pr create \
  --base "<base-branch>" \
  --head "harness/<epic>/sprint-<n>-<feature>" \
  --title "feat(<feature>): sprint-<n> — <goal-short>" \
  --body-file /tmp/pr-body-sprint-<n>.md \
  --assignee @me
```

`<base-branch>` is `_config.yml.default_branch` (flat) or
`harness/<epic>` (stacking). Do **not** use `--draft` — the Evaluator
has already signed off.

### Title format

`feat(<feature>): sprint-<n> — <goal-short>`

- `<goal-short>`: first clause of `contract.goal`, truncated to 55 chars
- If non-code deliverable (docs, config, etc.), use `chore(<feature>)`
  or `docs(<feature>)` as appropriate (the Generator records
  `change_type` in the final iteration's feedback file)

### Body template

```markdown
## Summary

<contract.goal verbatim>

## Acceptance Scenarios

<!-- Copied from contract.md; Evaluator confirmed each passes -->

- **AS-1**: <given / when / then one-liner> — ✅ pass (iter=<n>)
- **AS-2**: <given / when / then one-liner> — ✅ pass (iter=<n>)
...

## Rubric Verdict (final iteration iter=<n>)

| Axis | Score | Threshold | Verdict |
|---|---|---|---|
| Functionality | 1.00 | 1.0 | ✅ |
| Craft | 0.85 | 0.7 | ✅ |
| Design | 0.80 | 0.7 | ✅ |
| Originality | 0.60 | 0.5 | ✅ |

Full Evaluator notes: `sprints/sprint-<n>-<feature>/feedback/evaluator-<n>.md`

Evidence: `sprints/sprint-<n>-<feature>/evidence/`

## Iteration Count

<n> / <max_iterations>. Total elapsed <HH:MM>. Cost <$X.XX> (this sprint).

## Closes

Closes #<sprint-issue-number>

<!-- Optional: references the epic Issue when stacking. -->
<!-- Part of #<epic-issue-number>. -->
```

### Issue linkage

- **split**: exactly one `Closes #<n>` line (the sprint Issue). If
  `_state.json.epic_issue` is non-null, add a separate
  `Part of #<epic>` line — **not** `Closes`, because the epic closes
  only when the final sprint merges.
- `_state.json.sprint_issues[<n>]` holds the Issue number or URL.
  Extract the number; `gh` resolves it within the current repo.

## Bundled PR (one sprint = multiple features = one PR)

### Branch and title

```bash
BRANCH="harness/<epic>/sprint-<n>-bundle-<feat1>-<feat2>"
git switch -c "$BRANCH"
# ...commits...
gh pr create \
  --base "<base-branch>" \
  --head "$BRANCH" \
  --title "feat(<epic>): sprint-<n> — <feat1> + <feat2>" \
  --body-file /tmp/pr-body-sprint-<n>.md
```

Title lists the primary features separated by `+`. If more than three,
use `feat(<epic>): sprint-<n> — <feat1> + <feat2> + N others`.

### Body template (differs from split)

```markdown
## Summary

<contract.goal verbatim — explains why these features ship together>

## Bundled features

- **<feat1>**: <one-line goal>
- **<feat2>**: <one-line goal>
...

## Acceptance Scenarios

<!-- Grouped by feature; all confirmed by Evaluator -->

### <feat1>
- **AS-1**: ... — ✅ pass
...

### <feat2>
- **AS-1**: ... — ✅ pass
...

## Rubric Verdict (final iteration iter=<n>)

| Axis | Score | Threshold | Verdict |
|---|---|---|---|
| Functionality | 1.00 | 1.0 | ✅ |
...

Full Evaluator notes: `sprints/sprint-<n>-<bundle>/feedback/evaluator-<n>.md`

## Iteration Count

<n> / <max_iterations>. Total elapsed <HH:MM>. Cost <$X.XX> (this sprint).

## Closes

Closes #<feat1-issue>
Closes #<feat2-issue>
<!-- One Closes line per bundled sprint Issue. -->
```

### Multiple Closes

Every feature in the bundle had a sprint Issue created by
`harness-plan` (see `issue-create.md`). Emit one `Closes #N` per
feature — GitHub closes each Issue when the PR merges.

If the bundle was defined by `roadmap.md` but sprint Issues were not
created (e.g., tracker was `none` at plan time but later switched),
emit only a summary list without `Closes` lines and note the
discrepancy in `shared_state.md/Decisions`.

## Reviewers, labels, milestones

v1 keeps these simple:

- **Reviewers**: none by default. Users who want a review path set
  `_config.yml.pr_reviewers: [user1, user2]` and `harness-loop` adds
  `--reviewer user1 --reviewer user2`.
- **Labels**: add `harness-loop` always. If the feature's sprint in
  `roadmap.md` carries `labels:`, pass them through.
- **Milestone**: if `_state.json.epic_issue` exists and its milestone
  is non-null, inherit. Otherwise omit.

## After `gh pr create`

On success, `gh` prints the PR URL. The Orchestrator:

1. Parses the URL from stdout
2. Stores it at `_state.json.sprint_issues[<n>].pr`
3. Appends a line to `shared_state.md/Decisions`:
   ```
   [<ts>] PR opened: sprint-<n> <pr-url> (bundling=<split|bundled>)
   ```
4. Appends a line to `progress.md`:
   ```
   [<ts>] decision: sprint-<n> PR opened <pr-url>
   ```
5. Commits the `_state.json` update (not the PR itself — GitHub owns
   that side)

On `gh pr create` failure (auth, network, branch-not-pushed), log the
error and retry once. Second failure sets `pending_human=true` with
`aborted_reason: "pr-create-failed: <gh stderr>"` and halts.

## Non-GitHub trackers

### `tracker: gitlab`

v1 does not shell out to `glab`. Instead, after the sprint passes:

1. Build the same body template
2. Write it to `.harness/<epic>/sprints/sprint-<n>-*/pr-body.md`
3. Append to `.harness/<epic>/pending-prs.md` (epic-level ledger):
   ```
   - sprint-<n>: branch=<branch> body=sprints/sprint-<n>-*/pr-body.md
   ```
4. Print to user: "Open MR manually using the pending-prs.md ledger"
5. Set `_state.json.sprint_issues[<n>].pr = "gitlab:pending"`

### `tracker: none`

Skip PR creation entirely. Sprint completion is recorded in git
history (the per-iter commits) and `shared_state.md`. Append to
`progress.md`:

```
[<ts>] decision: sprint-<n> completed (tracker=none, no PR)
```

## Dry-run

`harness-loop --dry-run-pr` builds the body at
`.harness/<epic>/sprints/sprint-<n>-*/pr-body.preview.md` and prints
the `gh pr create` command without executing it. Useful for first
sprints when the user is still trusting the template.

## What this guide does NOT cover

- PR review comments and iteration after feedback — that is a human
  activity; `/harness-rules-update` may eventually propose rule
  changes from merged-PR review findings
- Force-pushing after mid-review changes — out of harness-loop scope
- Auto-merge — out of scope for v1; explicit human merge only
- Release tagging — outside the harness pipeline

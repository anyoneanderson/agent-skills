# Phase: pr

Assemble and open the pull request with the accumulated evidence. The PR body
carries the adversarial review history, the acceptance evidence, and any
unresolved items. A stall landing produces a draft PR instead of a ready one.

## Input

- All artifacts: final spec set, review rounds, `evaluate-{n}.md` and evidence,
  unresolved Minor findings, any arbitration record.
- The branch and PR conventions from `issue-to-pr-workflow.md` if present.

## Action

1. Run spec-implement's final PR-creation step (branch and commit conventions
   follow `issue-to-pr-workflow.md`). Apply the same staging guard as the
   implement phase: stage implementation files (and the four spec files only
   under a commit-spec-artifacts policy) by explicit pathspec, and never stage
   run records (`evidence/`, `review-*.md`, `inspection-report.md`,
   `.inspection_result.json`, `evaluate-*.md`, `pipeline-state.json`,
   `retrospective.md`, `pipeline-metrics.jsonl`). The pathspec exclusion is the
   first guard; the `.specs/.gitignore` from intake is the backstop.
2. Attach the evidence sections to the PR body. The exact section layout
   (Adversarial Review History, Acceptance Evidence, Unresolved) is defined in
   `../pr-assembly.md`; this phase supplies the transition and the inputs.
3. **File follow-up issues for the deferred findings.** For each finding
   carried with `fix_before: trial` / `required_check` / `follow_up` (from
   `state.rounds` and the review files), create one issue with `gh issue
   create` — title from the finding gist; body with the finding text verbatim,
   its severity and `fix_before` stage, the file/section it targets, the
   originating review round, and a link back to the PR. Findings of the same
   class (same path + section) may share one issue. Link each issue next to
   its finding in the PR body's Deferred findings list. Minor findings are
   listed in the PR body only — no issue.
   If `gh` is unavailable or issue creation fails, keep the full finding text
   in the PR body and add a warning line — a deferred finding must never
   exist only in a run record.
4. If the run reached pr via an arbitration draft landing, create the PR as a
   **draft** and list the unresolved fix-loop findings under `## Unresolved`
   (see `../pr-assembly.md`).

## Output

- An opened pull request (URL), ready or draft, whose body carries the review
  history, the acceptance pass/fail table with an evidence manifest, and any
  unresolved items.

## Verification

- A PR URL is returned by `gh`. Do not create a PR while acceptance tests are
  failing (a non-draft PR requires a passing evaluate gate).
- The evidence manifest in the PR body lists files that exist under
  `.specs/{feature}/evidence/`; the evidence files themselves stay local and are
  not committed or attached.
- Every deferred finding in the PR body carries either a follow-up issue link
  or its full text plus a warning that issue creation failed. A deferred
  finding with neither is a phase failure — fix the body before advancing.

## State Update

- Set `phase` to `retrospective`.
- Record `pr` as `{"url":"<URL>","draft":<boolean>,"status":"draft|ready"}`
  and record the follow-up issue numbers in `deferred_issues`. Derive `status`
  from the actual PR state rather than from the intended creation mode.
- Append `pr` to `completed_phases`.

## Transitions

- PR created (ready or draft) → **retrospective**

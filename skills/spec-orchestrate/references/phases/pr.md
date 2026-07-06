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
3. If the run reached pr via an arbitration draft landing, create the PR as a
   **draft** and list unresolved Critical / Improvement under `## Unresolved`.

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

## State Update

- Set `phase` to `retrospective`.
- Record the PR URL and whether it is a draft in state.
- Append `pr` to `completed_phases`.

## Transitions

- PR created (ready or draft) → **retrospective**

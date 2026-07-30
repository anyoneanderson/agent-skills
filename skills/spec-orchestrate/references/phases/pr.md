# Phase: pr

Open or update the pull request and compose its body as a review index.
A stalled or unverified run lands as a draft rather than claiming merge readiness.

## Input

- The implementation diff and final spec set.
- Review, evaluation, fallback, and arbitration run records.
- Deferred findings and any existing follow-up issues.
- Branch and PR conventions from `issue-to-pr-workflow.md`.
- The repository's pull request template and PR-body rules, when present.

## Action

1. Use spec-implement's final-step mechanics to prepare the branch, commit, and base, but defer the create command until the body is composed.
   Follow `issue-to-pr-workflow.md` for branch and commit conventions.
   Stage implementation files, and the four spec files only when project policy commits them, by explicit pathspec.
   Never stage run records (`evidence/`, `review-*.md`, `inspection-report.md`, `.inspection_result.json`, `evaluate-*.md`, `pipeline-state.json`, `retrospective.md`, `pipeline-metrics.jsonl`).
2. Read the project pull request template and body rules before composing the body.
   Preserve their headings, ordering, checkboxes, and required fields.
3. Compose the body through `../pr-assembly.md`.
   Select facts that change a review judgment; do not append review rounds, every finding, the acceptance table, the Evidence Manifest, or the full arbitration history.
4. Open the PR with the selected body and the draft state required by the current gate, then record the returned URL for follow-up links.
5. Create follow-up issues for findings carried with `fix_before: trial`, `required_check`, or `follow_up`.
   Store the full finding, severity, milestone, target, originating round, and PR link in the issue.
   Put only the issue link, behavioral effect, and landing rationale in the PR body.
   Findings of the same class may share one issue.
   Update the PR body with the created Issue links.
   If issue creation fails, keep the full finding and a warning in the body so it never exists only in a local run record.
6. Keep a Minor finding only when it changes a review decision or explains a visible limitation.
7. If the run reached pr through arbitration, acceptance is failing or blocked, or a deferred finding has no durable destination, create or keep the PR as a draft.
   State each merge-blocking unresolved item with its effect and next action.

## Output

- An opened or updated pull request whose project-compliant body lets a reviewer locate the behavior change, rationale, impact, constraints, verification, and review focus.
- Follow-up issue URLs for every deferred finding that was successfully filed.

## Verification

- The GitHub client returns a PR URL and the actual draft state matches the body.
- Every required project-template heading or field is present.
- The body does not bulk-copy review rounds, all findings, an acceptance pass/fail table, an Evidence Manifest, or the complete arbitration history.
- Every deferred finding has either a follow-up issue link or its full text plus an issue-creation warning.
- A ready PR has a passing evaluate gate and no merge-blocking unresolved item.

## State Update

- Set `phase` to `retrospective`.
- Record `pr` as `{"url":"<URL>","draft":<boolean>,"status":"draft|ready"}` and record follow-up issue numbers in `deferred_issues`.
- Derive `status` from the actual PR state, not the intended creation mode.
- Append `pr` to `completed_phases`.

## Transitions

- PR created or updated, ready or draft, then **retrospective**.

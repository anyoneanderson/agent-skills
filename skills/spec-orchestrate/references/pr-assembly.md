# PR Assembly as a Review Index

The pr phase opens the pull request.
The branch, commit, and base mechanics come from spec-implement; this file defines how the orchestrator turns the implementation, review, and evaluation results into a body that helps a repository-aware reviewer decide whether the change is sound and safe to merge.

日本語版: [pr-assembly.ja.md](pr-assembly.ja.md)

## Document Role and Reader

The PR body is a review index, not an audit log, specification, or implementation diary.
Its reader knows the repository and primary technologies but has not followed the pipeline run.
The body must let that reader identify what changed, why the chosen design was used, what can be affected, what remains constrained or unknown, what was verified, and where review attention should go.

Run records remain the detailed source for pipeline resume, retrospective analysis, and follow-up issue creation.
Do not copy them wholesale into the PR body.

## Project Template Takes Priority

Before composing the body, inspect the repository for a pull request template and PR-body rules.
Use the project's headings, ordering, required checkboxes, and required fields when they exist.
Map the selected information below into that structure instead of appending a second orchestrator-specific template.

If no project template exists, use headings that express the same roles: summary, background or rationale, changes, verification, known constraints, and review focus.
For a large change, put a three-line orientation near the top and state the recommended reading order.

## Selection Procedure

Build candidate facts from the diff, final specifications, `pipeline-state.json`, review results, evaluation results, and follow-up issues.
Keep a fact only when removing it would change a reviewer's judgment about correctness, risk, scope, verification, or merge readiness.

The selected body normally includes:

- the behavior after the change and the affected components or users;
- the reason for the chosen design when a reviewer needs it to judge the implementation;
- a scope expansion or shared-infrastructure change that is easy to miss in the diff;
- known constraints, residual risks, and unverified behavior that affect merge or follow-up decisions;
- verification outcomes stated as behavior that was confirmed, including a meaningful reason for any required check that does not apply;
- a small set of review findings whose fixes explain important safeguards or design choices; and
- the files, invariants, or interactions a reviewer should inspect first.

Do not include a detail merely because the pipeline recorded it.
In particular, keep review round counts, every finding, the full acceptance pass/fail table, the Evidence Manifest, raw evidence paths or hashes, and the complete arbitration history in local run records.
Link to committed specifications, relevant issues, or CI results when a reviewer needs the underlying detail.

## Deferred Findings

Create follow-up issues for findings carried with `fix_before: trial`, `required_check`, or `follow_up`.
Store the full finding, severity, milestone, target, and originating review round in the follow-up issue.
In the PR body, retain only the issue link, the effect on the changed behavior, and why the finding does not prevent the current PR from landing.

Do not list Minor findings unless one changes a review decision or explains a visible limitation.
Do not silently drop a deferred finding.
If issue creation fails, keep the full finding and an issue-creation warning in the PR body until it has a durable destination.

## Review and Evaluation Records

Summarize a review result only when it helps the reviewer understand a safeguard, a non-obvious correction, or reduced assurance.
For example, disclose a `native-independent` fallback because it changes the strength of the review claim, but do not list every successful review round.

State verification as outcomes rather than a copied case table.
For example, say that the service rejected out-of-scope identifiers before making a network request and name the command or CI check that confirmed it.
Do not copy every passing case or the Evidence Manifest into the body.

An `out_of_scope` rejection belongs in the body only when the diff may otherwise look incomplete.
State the apparent omission, the adopted scope boundary, and a link to its specification or issue; keep the full adjudication in the run record.

## Draft and Ready Pull Requests

A ready PR must have a passing evaluate gate and no unresolved item that prevents merge.
Open a draft PR when acceptance is failing or blocked, when a stall lands through arbitration, or when an untracked deferred finding has no durable destination.

The draft body must state each merge-blocking unresolved item with its effect and next action.
It does not need the complete review history that led to the blocker.

## Example Without a Project Template

```markdown
Closes #42

- The API now validates the request before creating a queued job.
- The worker performs the long-running operation asynchronously.
- The change affects the API and worker; the web application is unchanged.

## Rationale

The first production-like run exceeded the request deadline, so the API now returns an identifier and the worker completes the operation.

## Changes

1. The API validates input and creates the queued job.
2. The worker processes the job and saves the validated result.
3. Shared error forwarding was corrected because the production-like run exposed swallowed failures.

## Verification

- [x] Confirmed that invalid input creates neither a job nor a saved result.
- [x] Confirmed that a successful worker run saves one validated result.

## Known Constraints

- The deployed service still lacks the credential required to enable this route (#57).

## Review Focus

Review the request boundary first, then the worker's save-before-validation guard, and finally the shared error-forwarding change.
```

## State Update

After opening or updating the PR, record its URL, actual draft flag, and follow-up issue numbers in `pipeline-state.json`, then advance to retrospective as specified in `phases/pr.md`.

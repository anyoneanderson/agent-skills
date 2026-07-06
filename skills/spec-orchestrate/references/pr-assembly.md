# PR Assembly — Evidence-Backed Pull Request

The pr phase opens the pull request. The mechanics of branch, commit, and base
come from spec-implement; this file specifies the extra body sections the
orchestrator adds so the PR carries its own proof — the adversarial review
history and the acceptance evidence — and how a stalled run lands as a draft.

日本語版: [pr-assembly.ja.md](pr-assembly.ja.md)

## Base: spec-implement + Workflow Conventions

The PR is created by spec-implement's final step. The orchestrator does not
reinvent branch or PR conventions:

- If `issue-to-pr-workflow.md` exists, its branch naming and PR conventions win.
  spec-implement already reads it as its playbook.
- If `coding-rules.md` exists, it is handed to spec-implement (which passes it to
  spec-code); the orchestrator does not apply coding rules itself.
- The orchestrator's only additions are the body sections below, appended to the
  workflow's PR template.

## Body Sections (generated from state, not memory)

All three sections are produced mechanically from `pipeline-state.json` and the
result files — never from the orchestrator's recollection.

### `## Adversarial Review History`

From `state.rounds` (`spec_review` and the per-task implementation reviews):

- Per loop: the number of rounds and the final gate (PASS / FAIL-then-landed).
- Unresolved **Minor** findings, listed (Minor is recorded, not fixed).
- If a role swap or arbitration occurred, one line per `state.arbitrations` entry
  (signal + decision), so a reader sees why the run swapped owners or landed a
  draft.

```markdown
## Adversarial Review History
- Spec review: 3 rounds, final Gate PASS
- Implementation review (T003): 2 rounds, final Gate PASS
- Unresolved Minor:
  - `CR-STYLE-004` design.md §4.2 — naming nit, deferred
- Arbitration: S1 at spec_review round 4 → reviewer swapped codex→claude
```

### `## Acceptance Evidence`

From the final `evaluate-{n}.md` and the `evidence/{n}/` directory:

- The requirement-ID pass/fail table (case, requirement, verify, verdict).
- Each row's evidence as a **relative path** under `.specs/{feature}/evidence/`,
  so a reviewer can open the screenshot or log from the PR.

```markdown
## Acceptance Evidence
| Case | Requirement | Verify | Verdict | Evidence |
|------|-------------|--------|---------|----------|
| T-A01 | REQ-001 | playwright | PASS | .specs/user-auth/evidence/2/T-A01-login.png |
| T-A02 | NFR-001 | command | PASS | .specs/user-auth/evidence/2/T-A02-latency.log |
```

### `## Unresolved` (draft landing only)

Present only when the run landed via arbitration (a stall that could not be
resolved). Lists the still-open **Critical / Improvement** findings so the human
who picks up the draft knows exactly what remains.

```markdown
## Unresolved
- [ ] **Critical** T-A05 [REQ-007] export fails for empty datasets — 2 rounds, not converged
- [ ] **Improvement** design.md §4.4 — retry policy still unspecified
```

## Draft vs Ready

| Outcome | PR state | Contains |
|---------|----------|----------|
| evaluate Gate PASS (all cases pass) | ready | Review History + Acceptance Evidence |
| arbitration draft landing (stall) | **draft** | the above + `## Unresolved` (Critical / Improvement) |

Never open a ready (non-draft) PR while acceptance cases are failing or blocked —
a ready PR asserts the evaluate gate passed. A stalled run always lands as a
draft so an unattended pipeline never marks unverified work ready for merge.

## State Update (pr phase)

After the PR is opened, record the PR URL and its draft flag in
`pipeline-state.json`, then advance to retrospective (see `phases/pr.md`).

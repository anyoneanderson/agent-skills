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
- Deferred findings, listed with their stage: every finding carried forward
  with `fix_before: trial` / `required_check` / `follow_up`, plus unresolved
  **Minor** findings. The gate does not stop on these, so the PR body is the
  place they surface — deferred, never silently dropped. Turn `trial` /
  `required_check` / `follow_up` findings into follow-up issues at PR time and
  link them here.
- If a role swap or arbitration occurred, one line per `state.arbitrations` entry
  (signal + decision), so a reader sees why the run swapped owners or landed a
  draft.
- If `state.review_fallbacks` is non-empty, one line per entry naming the
  artifact and round, preferred and actual AI roles, and `fresh_subagent`
  independence. Label it **Reduced cross-AI assurance**; a same-AI independent
  review must never be presented as cross-AI review.

```markdown
## Adversarial Review History
- Spec review: 3 rounds, final Gate PASS
- Implementation review (T003): 2 rounds, final Gate PASS
- Deferred findings:
  - [ ] **Critical / fix_before: required_check** design.md §5.1 — stale success can be re-issued; fix before the check becomes required (#124)
  - [ ] **Improvement / fix_before: follow_up** `CR-STYLE-004` design.md §4.2 — naming nit (#125)
  - Minor: `CR-STYLE-002` design.md §3.1 — wording nit, deferred
- Arbitration: S1 at spec_review round 4 → reviewer swapped codex→claude
- Reduced cross-AI assurance: T001 round 1 preferred claude → actual codex runtime-native (`fresh_subagent`; peer unavailable)
```

### `## Acceptance Evidence`

From the final `evaluate-{n}.md`, including its Evidence Manifest:

- The requirement-ID pass/fail table (case, requirement, verify, verdict).
- An evidence manifest — filename, byte size, and sha256 — for each evidence
  file, copied from the result file's manifest.
- The evidence files themselves are run records and are **not committed or
  attached** (see `pipeline-config.md` → Artifact Classification). The PR carries
  the manifest, not the binaries: the hashes let a reviewer confirm the evidence
  was not swapped after the run, without screenshots or logs entering git
  history. Do not embed screenshots or raw review files in the PR body — the
  review rounds are already summarized under Adversarial Review History above.

```markdown
## Acceptance Evidence
| Case | Requirement | Verify | Verdict |
|------|-------------|--------|---------|
| T-A01 | REQ-001 | playwright | PASS |
| T-A02 | NFR-001 | command | PASS |

### Evidence Manifest
| File | Bytes | sha256 |
|------|-------|--------|
| evidence/2/T-A01-login.png | 51384 | a1b2c3d4… |
| evidence/2/T-A02-latency.log | 892 | d4e5f6a7… |
```

### `## Unresolved` (draft landing only)

Present only when the run landed via arbitration (a stall that could not be
resolved). Lists the still-open **fix-loop findings** (spec review:
`fix_before: implementation`; evaluate: failing cases) so the human who picks
up the draft knows exactly what remains.

```markdown
## Unresolved
- [ ] **Critical** T-A05 [REQ-007] export fails for empty datasets — 2 rounds, not converged
- [ ] **Improvement** design.md §4.4 — retry policy still unspecified
```

## Draft vs Ready

| Outcome | PR state | Contains |
|---------|----------|----------|
| evaluate Gate PASS (all cases pass) | ready | Review History + Acceptance Evidence |
| arbitration draft landing (stall) | **draft** | the above + `## Unresolved` (open fix-loop findings) |

Never open a ready (non-draft) PR while acceptance cases are failing or blocked —
a ready PR asserts the evaluate gate passed. A stalled run always lands as a
draft so an unattended pipeline never marks unverified work ready for merge.

## State Update (pr phase)

After the PR is opened, record the PR URL and its draft flag in
`pipeline-state.json`, then advance to retrospective (see `phases/pr.md`).

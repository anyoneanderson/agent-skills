# Usage and Roadmap Approval

Read this reference before parsing a harness-plan invocation.

## Commands

```text
/harness-plan
/harness-plan --epic-name auth-suite --epic 142
/harness-plan --replan
/harness-plan --auto-approve-roadmap
```

The first command starts a new epic or resumes an interrupted draft from the
durable state. `--epic 142` records parent Issue 142. `--replan` re-enters Step
5 with the existing product-spec.md as input.

## Auto-Approve Roadmap

`--auto-approve-roadmap` is the only mechanism that converts harness-plan's interactive checkpoints into automatic decisions. Never infer autonomy from `_config.yml` or a later harness-loop mode.

Apply the flag to every checkpoint as one coherent setting:

| Checkpoint | Default | With the flag |
|---|---|---|
| Boot Sequence: resume | Ask via AskUserQuestion | Resume from `_state.json.phase` |
| Step 1: existing epic | Ask continue, new, or cancel | Continue populated state; otherwise derive a new name |
| Step 2: epic name collision | Re-ask | Append `-N` |
| Step 4: product-spec cross-check returns `no` | Re-open the section | Append `TODO(product-spec):` to progress.md and continue |
| Step 5: more than six sprints | Pause | Truncate and append `TODO(epic-split)` to progress.md |
| Step 5: duplicate Issue ambiguity | AskUserQuestion | Append `TODO(issue-dup):` to progress.md and skip the sprint |
| Step 6: roadmap approval | Ask approve, revise, or cancel | Approve and append an audit line to progress.md |

The user is responsible for reviewing roadmap.md before the skill completes.
Resolve every `TODO(...)` in progress.md before harness-loop starts. A single
invocation either has the flag or does not; never toggle it mid-run. Record it
exactly once at skill start as
`[<ts>] harness-plan: --auto-approve-roadmap enabled`.

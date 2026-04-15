# Sprint Issue Creation

Covers REQ-023 and ASM-002 — how `harness-plan` emits one tracker issue per
sprint after `roadmap.md` is approved. The Planner does not create issues
during roadmap drafting; issuance happens only once, after approval.

## Tracker Dispatch

Dispatch on `_config.yml.tracker`:

| Tracker | Behaviour |
|---|---|
| `github` | Use `gh issue create` per sprint (primary path) |
| `gitlab` | v1: record intended issue payloads to `.harness/<epic>/pending-issues.md` (an epic-level ledger owned by harness-plan), skip CLI call. v2 will add glab integration |
| `none` | Skip entirely. Sprint progress lives in `.harness/` and git only. Write a single line to `progress.md` noting no-tracker mode |

All three paths still update `_state.json.sprint_issues` with either the
issue URL (GitHub) or a placeholder token (`gitlab:pending`, `none:ledger`).

> `shared_state.md` is **sprint-scoped** and lives under
> `.harness/<epic>/sprints/sprint-<n>-<feature>/`. It does not exist at
> the time `harness-plan` runs. Never write Pending payloads there — use
> the epic-level `pending-issues.md` file instead.

## GitHub Path

### Pre-flight

Before iterating sprints, verify:

1. `gh auth status` succeeds — otherwise abort with guidance
2. Current directory is inside a git repo with a `github.com` remote — derive
   `owner/repo` from `git remote get-url origin`
3. A **parent epic issue** exists — either:
   - Passed in via `--epic <number>` flag on `/harness-plan`, or
   - Created fresh with the product-spec body as the epic issue (Planner
     asks via `AskUserQuestion`; with `--auto-approve-roadmap` the skill
     creates a new epic issue by default and records its number in
     `_state.json.epic_issue`)

**When `tracker == github` and `gh` is not on PATH**, **abort** the skill
with install guidance per REQ-023. Do not fall back to `gitlab` or
`none` — silent fallback corrupts the audit trail by changing tracker
identity without the user's consent. (When `tracker ∈ {gitlab, none}`,
`gh` is not required and this check is skipped.)

### Per-sprint create

For each sprint in roadmap order:

```bash
gh issue create \
  --title "[sprint-${n}] ${feature}" \
  --body-file <(generate_body) \
  --label "harness,sprint" \
  --assignee "@me"
```

Where `generate_body()` emits:

```markdown
Parent epic: #<EPIC_NUMBER>

## Sprint <n> — <feature>

**Bundling**: <split|bundled>
**Bundled with**: <sprint numbers if bundled; else "—">
**Dependencies**: <sprint numbers; else "—">
**Risk**: <low|medium|high>

## Scope (from product-spec.md)

<Copy the matching What bullet(s) from product-spec.md. Verbatim.>

## Out of Scope

<Copy full Out of Scope section from product-spec.md — prevents scope creep
during sprint negotiation.>

## Contract

Will be negotiated inside `harness-loop` — see
`.harness/<epic>/sprints/sprint-<n>-<feature>/contract.md`.

## PR

Split: this sprint ships as its own PR.
Bundled: this sprint ships as part of the bundle PR for sprints
`<bundled_with list>` — closing this issue happens when the bundle PR merges.
```

Capture the issue URL / number from `gh issue create` stdout and write to
`_state.json.sprint_issues[<n>] = "<url>"`.

### Duplicate detection (re-run safety)

`harness-plan` is re-entrant. On re-run with an existing `roadmap.md`, it
checks before creating each sprint issue:

```
query: gh issue list --label harness,sprint --search "in:title [sprint-${n}] ${feature}"
```

- If **no match**: create as normal.
- If **exactly one open match**: reuse its URL; do not create a duplicate.
- If **multiple matches** or **closed-only match**: pause with an
  `AskUserQuestion`. With `--auto-approve-roadmap`, instead write
  `TODO(issue-dup): sprint-${n}` to `progress.md` and skip creation.
  Either way, the user resolves the ambiguity manually before the loop.

Never force-create. Duplicate issues fragment the audit trail and break the
`_state.json.sprint_issues` mapping.

### Epic link syntax

GitHub does not have native sub-issue relationships as of 2026-04 for all
repos. Two syntaxes are supported:

1. **Prose reference** (always): first line of body reads
   `Parent epic: #<EPIC_NUMBER>`. Renders as a link.
2. **Sub-issue API** (if repo is in the sub-issue beta): the Planner checks
   `gh api repos/{owner}/{repo}` for `sub_issues_summary` and, if present,
   uses `gh api /repos/{owner}/{repo}/issues/{epic}/sub_issues` to create a
   formal link. Falls back silently to prose reference on 404 / 422.

### Label hygiene

`harness-plan` creates two repo labels if missing (idempotent):

- `harness` — colour `#0E8A16`, description "Managed by /harness skill"
- `sprint` — colour `#1D76DB`, description "Per-sprint work unit"

Uses `gh label create --force` to skip-on-exist. Does not modify existing
label colours or descriptions.

## GitLab Path (v1)

Write each sprint's intended issue payload to
`.harness/<epic>/pending-issues.md` — an epic-level ledger file that
`harness-plan` owns. The file is created if absent and appended to for
each sprint:

```markdown
# Pending Issues (tracker=gitlab, v1 — awaiting glab integration)

## PendingIssues

- sprint-1 login: split, risk=medium, deps=[], awaiting glab
- sprint-2 signup: bundled-with=[3], risk=medium, deps=[1], awaiting glab
- sprint-3 password-reminder: bundled-with=[2], risk=low, deps=[2], awaiting glab
```

v2 will introduce `glab issue create` with the same body structure. The
payload format above is chosen so v2 can parse and submit without
regenerating.

> **Why not `shared_state.md`?** `shared_state.md` is sprint-scoped
> (`sprints/sprint-<n>-<feature>/shared_state.md`) and is owned by
> `harness-loop` as a Planner ⇄ Generator ⇄ Evaluator communication
> ledger. It does not exist at the time `harness-plan` runs, and
> harness-plan writes above the sprint level. The epic-level
> `pending-issues.md` cleanly separates these concerns.

## None Path

When tracker is `none`, `harness-plan` writes a single progress line:

```
[<ts>] tracker=none: 3 sprints planned, issues skipped. Ledger at .harness/<epic>/roadmap.md
```

No API calls, no AskUserQuestion. Sprint identity lives in `roadmap.md`
and per-sprint directory names.

## `_state.json` Updates

Phase transitions for the Issue-creation step (design §9.2):

1. **At loop start**, set `phase = "issues-pending"` so a mid-loop
   failure can be detected on resume and routed back into this step.
2. **After each successful `gh issue create`**, atomically append to
   `sprint_issues[<n>]`. Never batch — each write is resume-safe on its
   own.
3. **After all sprints are created (or skipped per tracker)**, set
   `phase = "ready-for-loop"` as the handoff signal to `harness-loop`.

Final state example:

```json
{
  "epic_issue": 142,
  "sprint_issues": {
    "1": "https://github.com/org/repo/issues/143",
    "2": "https://github.com/org/repo/issues/144",
    "3": "https://github.com/org/repo/issues/145"
  },
  "phase": "ready-for-loop",
  "next_action": "harness-loop:negotiate-sprint-1"
}
```

`harness-loop` reads these on Boot Sequence to know which issue to comment
on during sprint events (start, negotiation round, evaluation, PR creation).

## Recovery

If issue creation fails mid-loop (network, rate limit, permissions):

- Already-created issue URLs are kept in `_state.json.sprint_issues`
- Failed sprint index is recorded in `progress.md`:
  `issue-create: sprint-${n} failed: <error>`
- On resume, duplicate detection (above) handles already-succeeded sprints;
  the failed one retries
- No partial state is left in an unrecoverable form — `roadmap.md` is the
  canonical plan; issues are derived views

## Error Handling

| Situation | Response |
|---|---|
| `gh` not installed and tracker=github | Abort with install instructions. Do not silently downgrade to `none` |
| `gh auth` invalid | Abort with `gh auth login` guidance |
| Epic issue not found | Prompt to create new epic or provide `--epic` |
| Rate limit | Backoff 60s, retry. After 3 failures, halt and write partial state |
| User rejects roadmap during approval | Do not create any issues; `roadmap.md` remains as draft |
| Sprint name collision in the same epic | Planner regenerates with a disambiguated feature name and flags it |

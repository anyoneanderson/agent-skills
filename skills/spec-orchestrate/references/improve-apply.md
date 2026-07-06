# Improvement Application — Tier Judgment, Auto-Apply, and Revert

retrospective produces proposals (`retrospective-format.md`); this file decides
which may be applied automatically and how. The guiding rule: an automatic edit
must ride the same audited path as a human change (branch → PR), and the
security-sensitive decision — "is this file safe to auto-merge?" — is made from a
**canonical, symlink-free path**, never from the string a proposal happened to
write.

日本語版: [improve-apply.ja.md](improve-apply.ja.md)

## Preconditions (when to skip entirely)

- **pr not reached this run** → do not auto-apply. retrospective still writes its
  report and may file Issues, but the metrics comparison against a clean
  completion does not hold (see `phases/retrospective.md` Timing).
- **`improve.skills_repo` unset or not writable** → degrade to Issue-only (see
  Degradation). Improvements apply to the skills **source repository** only
  (default `improve.skills_repo`), never to installed copies (§7).
- **`improve.auto_apply: false`** → even Tier 1 proposals are left as PRs awaiting
  human review; nothing auto-merges.

## Tier Judgment

Each proposal's target path maps to a Tier. Tier 1 auto-merges; Tier 2 is left
for a human. Judge against the **normalized** path (next section), not the raw
string.

| Normalized target path | Tier | Apply method |
|------------------------|------|--------------|
| `skills/*/references/**` (except the rows below) | 1 | improve branch → PR → auto-merge |
| `skills/*/references/contract*.md` (public contract) | 2 | PR left for human review |
| `skills/*/references/lessons.md` (lessons file) | 1 | improve branch → PR → auto-merge |
| `skills/*/SKILL.md` | 2 | PR left for human review |
| `skills/*/references/scripts/**` | 2 | PR left for human review |
| `docs/coding-rules.md`, `docs/review_rules.md` | 2 | PR left for human review |

`contract*.md` is **always** Tier 2 even though it lives under `references/`: other
skills depend on the public contract, so an automatic rewrite could break them
(§7). SKILL.md and scripts are Tier 2 because they are the skill's executable
surface. When a proposal touches any Tier 2 path, the whole PR is Tier 2.

**Evaluation order matters:** test the specific Tier 2 rows (`contract*.md`,
`SKILL.md`, `scripts/**`, `docs/*`) **before** the `references/**` Tier 1
catch-all, or a Tier 2 file under `references/` would fall through to Tier 1.

### Path Normalization (the security boundary)

String matching alone is bypassable: `skills/foo/references/../SKILL.md`, a
symlink, or a case difference could slip a Tier 2 target past the Tier 1 rule and
auto-merge it. Because auto-merge is the trust boundary, normalize and validate
**before** matching:

`$target` is a **repository-relative** path (e.g. `skills/foo/references/g.md`),
and it must be anchored to `repo_root` — **not** the current directory. The
orchestrator normally runs with the target *project* as its cwd while
`skills_repo` is a separate directory (§7), so anchoring on cwd would push every
legitimate target outside the repo-root check and reject it (fail-closed, so not
a security hole, but REQ-020 auto-apply would never fire).

```bash
repo_root="$(git -C "$skills_repo" rev-parse --show-toplevel)"

# Portable canonicalization (BSD realpath lacks -m/--no-symlinks; use python3).
# Anchor $target on repo_root, not cwd.
#   physical = resolves ../ AND symlinks to the true on-disk path
#   lexical  = resolves ../ only, does NOT expand symlinks
physical="$(python3 -c 'import os,sys; print(os.path.realpath(os.path.join(sys.argv[1], sys.argv[2])))' "$repo_root" "$target")"
lexical="$(python3 -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))' "$repo_root" "$target")"

# (1) both computed above.
# (2) must live under the repository root
case "$physical/" in
  "$repo_root"/*) : ;;
  *) echo "reject: outside repo root"; exit 1 ;;
esac

# (3) must not traverse a symlink (physical differs from lexical → symlink in path)
[ "$physical" = "$lexical" ] || { echo "reject: symlink in path"; exit 1; }

# match the Tier table on the normalized, repo-relative path
rel="${physical#$repo_root/}"
```

A path that fails any of (1)–(3) is **rejected** (not applied), not defaulted to
Tier 1. Match `rel` against the Tier table above.

## Line Budget Check (REQ-021)

LLM self-improvement drifts toward adding instructions. Guard each Tier 1 target:
after the edit, if the file's line count exceeds `improve.line_budget`
(default 300) **and** the diff is a near-pure addition (removed lines < added
lines ÷ 2), reject the automatic apply. The proposal must be reworked into a
replacing/deleting edit, or downgraded to Tier 2 (human review).

Measure the **normalized** path from Path Normalization above (`$physical`, i.e.
`$repo_root/$rel`) — never raw `$target`, which is repo-relative and would
resolve against the orchestrator's cwd (usually the target project, not the
skills repo), reading the wrong file or none at all. If the file cannot be
read, fail closed: reject the automatic apply.

```bash
[ -r "$physical" ] || { echo "reject: cannot read $physical — fail closed, no auto-apply"; exit 1; }
lines_after="$(wc -l < "$physical")"
if [ "$lines_after" -gt "$line_budget" ] && [ "$removed" -lt $((added / 2)) ]; then
  echo "reject: over budget and additive-only — rework as replacement or downgrade to Tier 2"
fi
```

## Apply Procedure (REQ-020)

The orchestrator does only git/PR; a **worker subagent** makes the file edits
(REQ-002 — the orchestrator never edits skill files itself).

1. In `improve.skills_repo`, create the improve branch `improve/{feature}-{run-id}`.
2. A worker subagent applies the proposal's edits on that branch.
3. Commit. The commit body **references `retrospective.md`** (path + run_id) so the
   audit trail links every automatic change back to the evidence that justified it.
4. Open a PR:
   - **Tier 1 only** (every changed path is Tier 1, all budget checks pass) →
     auto-merge the PR.
   - **Tier 2 included** → leave the PR open for human review; do not merge.

Even Tier 1 goes branch → PR → merge (never a direct push) so the audit shape
matches Tier 2 and any bad change reverts with a single `git revert` (§7).

## Degradation (no writable skills repo)

If `improve.skills_repo` is unset or not writable, do not apply anything. Instead
file an Issue on the agent-skills repository containing the proposals (target,
Tier, rationale). This keeps the learning without requiring write access.

## Revert (REQ-022)

Because features and difficulty differ run to run, a single worse comparison is
noise; auto-reverting on it makes improvement and rollback oscillate. So revert is
staged by confidence:

- **Auto-revert (through auto-merge):** only when a **same-family regression**
  (same `blocker_category` series **and** same phase) is observed in **2
  consecutive runs** after a self-applied improvement to the **same skill**, and
  only for a commit **this pipeline auto-applied**. Revert it the same way it was
  applied (branch → PR → auto-merge).
- **Revert PR (human approval):** a single-run regression stops at opening a
  revert PR; a human decides.
- **Issue only:** a change a human merged is never auto-reverted — file an Issue
  proposing the revert.

The regression signal is read from `pipeline-metrics.jsonl`
(`retrospective-format.md` Step 4); this file only defines what the signal
authorizes.

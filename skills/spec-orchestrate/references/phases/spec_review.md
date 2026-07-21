# Phase: spec_review

Run the adversarial specification review and loop until the review gate passes.
This is the expensive semantic check, run only after inspect is clean. The
review backend is whatever the `spec_reviewer` AI role and recorded
`host_runtime` resolve to (`../role-dispatch.md` → "spec_review"): a matching
role uses a runtime-native subagent; a different role uses agent-delegate. If
that cross-AI peer is unavailable, use a fresh independent host-native reviewer.

## Input

- The four spec files (the reviewer reads the files themselves, not a diff).
- The prior round's fix summary and the accumulated prior-round findings, for
  round ≥ 2.
- `spec_reviewer` AI role plus the recorded `host_runtime`, resolved by
  `../role-dispatch.md` → "spec_review".
- For an agent-delegate backend: the session `thread_id` from
  `state.threads.spec_reviewer`, for resume on round ≥ 2.
- The orchestrator review fallback policy: `native-independent`.

## Action

Resolve the backend via `../role-dispatch.md` first, then run the matching path.
Both paths produce the same review file and feed the same fix loop.

**Gate rule (both backends):** the review prompt must require the reviewer to
tag every Critical / Improvement finding with `fix_before`
(`implementation | trial | required_check | follow_up` — definition, default
`follow_up`, and escalation burden of proof are in the adversarial review
prompt) and to set the `Gate` line from that axis alone, mechanically —
`Gate: FAIL` when at least one finding is `fix_before: implementation`,
`Gate: PASS` otherwise. Severity stays in the output for human reading but
does not decide the Gate. State this in the prompt every round so the Gate
never diverges from the tally.

**Stage remapping:** when `pipeline.yml` defines `review.fix_before_stages`
(see `../pipeline-config.md`), pass that list into the review context, and
read `implementation` throughout this file — the Gate rule, the fix loop,
`fix_required` — as the **first** stage of that list.

**Review scope per round:** round 1 reads the whole spec set deeply. For
round ≥ 2, instruct the reviewer to read only the unresolved findings, the
sections changed by the fixes, and the parts that directly use those sections
— and to follow the re-review escalation rule (a new finding unrelated to the
fixes is `implementation` only for secret leak / data loss / merge-condition
bypass / infeasibility). This matters especially for a resuming backend, which
otherwise keeps drilling into the same area it explored last round.

**Cross-AI backend (agent-delegate):**
1. Round 1: launch agent-delegate `--mode review --target <spec_reviewer>`
   (read-only) with the spec file list, adversarial perspectives, and any prior
   fix summary.
2. Round ≥ 2: resume the same session with `--resume <thread_id>` so context
   carries over. Review sessions start read-only, which is the only
   sandbox that resume can keep, so only resume sessions created read-only.
3. Use synchronous execution only when there is a concrete basis for this round
   to finish within 5 minutes. Otherwise use explicit `--detach`, retain the
   expected run id, and apply the 15–30-second report-first wait from
   `../role-dispatch.md`. Re-evaluate at 30-minute intervals and apply its
   2-hour controlled stop. A review without a concrete 5-minute basis detaches.

<!-- spec-review-env-error-recovery:start -->
**Detached `env_error` artifact recovery (agent-delegate only):**
Follow the general fail-closed recovery contract in `../role-dispatch.md` Step 3.
Before launch, record the exact artifact path `.specs/{feature}/review-spec-{round}.md`.
Pass that same path to the detached launch as `--review-output` so `artifacts.review_file` and the predeclared recovery path agree.
Record whether the path exists and, when it does, its content fingerprint as the freshness baseline.
Record a caller-generated correlation value and require the reviewer to write it in `## Meta`.
Record the phase validator as the checks in Verification below.
Record the pre-launch workspace fingerprint defined by the general contract, excluding only the declared out-dir.
After the detached launch returns, bind these predeclared values to its `expected_run_id` before starting the watcher.

Attempt recovery only when a valid terminal report has `meta.run_id` equal to `expected_run_id`, `status: blocked`, and `blocker_category: env_error`.
The watcher inspects only the predeclared review file and applies these checks:

1. Require the file to be new or changed from the freshness baseline and to contain the predeclared correlation value.
2. Apply the four-point structural check to the declared review file.
3. Verify that every Critical / Improvement finding has a valid `fix_before` value from the stage list in effect.
4. Recompute the Gate from those tags and reject a `Gate` line that contradicts the tally.
5. Compare the post-run workspace fingerprint with the pre-launch value and require an exact match.

When every check passes, adopt the review result without re-running the reviewer.
Record the artifact path, correlation evidence, validator result, and recomputed Gate in the run record, then continue through the normal State Update and Transitions below.
Retain the original blocked report unchanged as the runtime diagnostic.
A report for another run or category, a stale or uncorrelated artifact, validator failure, or a changed workspace fingerprint remains blocked.
Do not apply the malformed-output re-run rule to a rejected recovery candidate; a later retry is a new run with a new pre-launch record.
<!-- spec-review-env-error-recovery:end -->

**Runtime-native backend (subagent):**
1. Round 1: dispatch a fresh review subagent, separate from the spec author and
   orchestrator contexts, with the spec file list and adversarial perspectives;
   it returns the same structured review content, which the orchestrator writes
   to the review file.
2. Round ≥ 2: a native subagent has no agent-delegate `thread_id` to resume, so continue
   **sessionless**: pass the prior-round fix summary plus the prior rounds'
   findings (from `state.rounds.spec_review`) into a fresh subagent so it does
   not re-raise resolved points. This is the resume-equivalent for native review.
3. Expose no write tools and compare one repository change fingerprint taken
   immediately before reviewer launch with another taken after review
   completion. Include tracked worktree and staged diff content plus non-ignored
   untracked path and content; exclude only
   orchestrator-owned run-record paths from `../pipeline-config.md`, never the
   whole `.specs/` directory. Any change in the included fingerprint invalidates
   the result and blocks the run for the normal workspace-drift procedure.

When the configured cross-AI reviewer is unavailable, this same runtime-native
path is the `native-independent` fallback. The actual reviewer AI role becomes
`host_runtime`, but its execution instance and context remain independent from
the spec author. Record one `state.review_fallbacks` entry per round. If a fresh
native reviewer cannot be guaranteed, block instead of reviewing in the
orchestrator context.

After either backend completes, read the review file's Gate line, severity
counts, and `fix_before` tags.

## Output

- `review-spec-{round}.md`, the independent reviewer's structured review file (severity
  sections + `fix_before` tags + `Gate: PASS|FAIL`), written for
  `.specs/{feature}/`.

## Verification

- The review file passes the 4-point structural check (type header, Meta,
  Findings with Critical/Improvement/Minor, Summary with `Gate: PASS|FAIL`). A
  malformed review is a worker failure: re-run once, then blocked.
- Findings must carry a severity, and every Critical / Improvement finding must
  carry a valid `fix_before` value; a `fix_before: implementation` finding must
  state who triggers it, what breaks, and from which milestone on. A finding
  missing these is treated as malformed (same re-run-once rule).
- **Recompute the Gate from the `fix_before` tags** — FAIL iff at least one
  finding carries the gate-blocking stage. Never adopt the reviewer's `Gate`
  line at face value: the delegation script verifies structure only, not that
  the line matches the findings. A `Gate` line that contradicts the tally is
  malformed output (same re-run-once rule).
- Only `fix_before: implementation` findings drive the fix loop. Findings at
  `trial` / `required_check` / `follow_up`, and Minor findings, are recorded
  and carried forward — transcribed to the PR body (see `../pr-assembly.md`),
  not fixed in this loop.

## State Update

- Append this round to `rounds.spec_review`: round number, critical /
  improvement / minor counts, `fix_required` (the count of
  `fix_before: implementation` findings), finding fingerprints (computed per
  `../stall-detection.md`, over the fix-loop findings only, i.e.
  `fix_before: implementation`), class keys (path + section, per
  `../stall-detection.md` S4), and the gate result. This entry is the sole
  input to stall detection.
- agent-delegate backend only: record the reviewer `thread_id` under
  `threads.spec_reviewer` for resume. A runtime-native subagent has no such
  thread id (it continues sessionless), so leave it unset.
- When `native-independent` was used, append the fallback record to
  `review_fallbacks` with phase (`spec_review`), artifact (`spec`), round,
  `host_runtime` at review time, preferred/actual role, runtime-native backend,
  `peer_unavailable` reason, and `fresh_subagent` independence.
- Evaluate the stall signals S1–S4 over the accumulated rounds
  (`../stall-detection.md`). If a signal fires, set `phase` to arbitration.

## Transitions

- Any `fix_before: implementation` finding, no stall → **spec_generate** (fix,
  then re-review — resuming agent-delegate sessions, sessionless with
  carried-over findings for native review). Deferred findings (`trial` /
  `required_check` / `follow_up`) and Minor findings are not fixed here; they
  are already recorded and are transcribed to the PR body.
- Gate PASS (no `implementation` finding) → **approval**
- stall signal fires → **arbitration** (`../stall-detection.md`)

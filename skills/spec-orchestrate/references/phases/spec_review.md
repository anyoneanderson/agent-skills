# Phase: spec_review

Run the adversarial specification review and loop until the review gate passes.
This is the expensive semantic check, run only after inspect is clean. The
review backend is whatever the `spec_reviewer` AI role and recorded
`host_runtime` resolve to (`../role-dispatch.md` → "spec_review"): a matching
role uses a runtime-native subagent; a different role uses agent-delegate.

## Input

- The four spec files (the reviewer reads the files themselves, not a diff).
- The prior round's fix summary and the accumulated prior-round findings, for
  round ≥ 2.
- `spec_reviewer` AI role plus the recorded `host_runtime`, resolved by
  `../role-dispatch.md` → "spec_review".
- For an agent-delegate backend: the session `thread_id` from
  `state.threads.spec_reviewer`, for resume on round ≥ 2.

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
   `../role-dispatch.md`. A review gate with a 20-minute-or-longer budget has no
   5-minute basis and therefore detaches. A caller-owned timeout for specification
   review or repair is at least 20 minutes.

**Runtime-native backend (subagent):**
1. Round 1: dispatch a review subagent with the spec file list and adversarial
   perspectives; it emits the same structured review file.
2. Round ≥ 2: a native subagent has no agent-delegate `thread_id` to resume, so continue
   **sessionless**: pass the prior-round fix summary plus the prior rounds'
   findings (from `state.rounds.spec_review`) into a fresh subagent so it does
   not re-raise resolved points. This is the resume-equivalent for native review.

After either backend completes, read the review file's Gate line, severity
counts, and `fix_before` tags.

## Output

- `review-spec-{round}.md`, the peer reviewer's structured review file (severity
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

# Phase: spec_review

Run the adversarial specification review and loop until the review gate passes.
This is the expensive semantic check, run only after inspect is clean. The
review backend is whatever the `spec_reviewer` role resolves to
(`../role-dispatch.md` → "spec_review"): codex via agent-delegate, or a Claude
subagent.

## Input

- The four spec files (the reviewer reads the files themselves, not a diff).
- The prior round's fix summary and the accumulated prior-round findings, for
  round ≥ 2.
- `spec_reviewer` role → backend (default codex via agent-delegate), resolved by
  `../role-dispatch.md` → "spec_review".
- For a codex reviewer: the session `thread_id` from `state.threads.spec_reviewer`,
  for resume on round ≥ 2.

## Action

Resolve the backend via `../role-dispatch.md` first, then run the matching path.
Both paths produce the same review file and feed the same fix loop.

**Gate rule (both backends):** the review prompt must require the reviewer to set
the `Gate` line to match the severity tally mechanically — `Gate: FAIL` when
there is any Critical or Improvement finding, `Gate: PASS` only when the findings
are Minor-only or none. State this in the prompt every round so the Gate never
diverges from the counts.

**codex backend (agent-delegate):**
1. Round 1: launch agent-delegate `--mode review` (read-only) with the spec file
   list, adversarial perspectives, and any prior fix summary.
2. Round ≥ 2: resume the same session with `--resume <thread_id>` so context
   carries over. Review sessions start read-only, which is the only
   sandbox that resume can keep, so only resume sessions created read-only.

**claude backend (subagent):**
1. Round 1: dispatch a review subagent with the spec file list and adversarial
   perspectives; it emits the same structured review file.
2. Round ≥ 2: a Claude subagent has no `thread_id` to resume, so continue
   **sessionless**: pass the prior-round fix summary plus the prior rounds'
   findings (from `state.rounds.spec_review`) into a fresh subagent so it does
   not re-raise resolved points. This is the resume-equivalent for claude.

3. Read the review file's Gate line and severity counts.

## Output

- `review-spec-{round}.md`, the peer reviewer's structured review file (severity
  sections + `Gate: PASS|FAIL`), written for `.specs/{feature}/`.

## Verification

- The review file passes the 4-point structural check (type header, Meta,
  Findings with Critical/Improvement/Minor, Summary with `Gate: PASS|FAIL`). A
  malformed review is a worker failure: re-run once, then blocked.
- Findings must carry a severity. Only Critical / Improvement drive the fix loop;
  Minor is recorded and carried forward, not fixed.

## State Update

- Append this round to `rounds.spec_review`: round number, critical / improvement
  / minor counts, finding fingerprints (computed per `../stall-detection.md`,
  over Critical + Improvement only), gate result. This entry is the sole input to
  stall detection.
- codex backend only: record the reviewer `thread_id` under
  `threads.spec_reviewer` for resume. A claude subagent has no thread_id (it
  continues sessionless), so leave it unset.
- Evaluate the stall signals S1–S3 over the accumulated rounds
  (`../stall-detection.md`). If a signal fires, set `phase` to arbitration.

## Transitions

- Critical or Improvement present, no stall → **spec_generate** (fix, then
  re-review — resuming the session for codex, sessionless with carried-over
  findings for claude). Minor findings are not fixed here; they are already
  recorded and are transcribed to the PR body.
- Gate PASS (Minor only / none) → **approval**
- stall signal fires → **arbitration** (`../stall-detection.md`)

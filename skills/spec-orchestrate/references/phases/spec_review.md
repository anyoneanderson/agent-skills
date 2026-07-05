# Phase: spec_review

Run the adversarial specification review with a peer LLM (agent-delegate
`--mode review`) and loop until the review gate passes. This is the expensive
semantic check, run only after inspect is clean.

## Input

- The four spec files (the reviewer reads the files themselves, not a diff).
- The prior round's fix summary, for round ≥ 2.
- `spec_reviewer` role → backend (default codex via agent-delegate), resolved by
  `../role-dispatch.md` → "spec_review".
- The reviewer session `thread_id` from state, for resume on round ≥ 2.

## Action

1. Round 1: launch agent-delegate `--mode review` (read-only) with the spec file
   list, adversarial perspectives, and any prior fix summary.
2. Round ≥ 2: resume the same session with `--resume <thread_id>` so context
   carries over (NFR-002). Review sessions start read-only, which is the only
   sandbox that resume can keep, so only resume sessions created read-only.
3. Read the review file's Gate line and severity counts.

## Output

- `review-spec-{round}.md`, the peer reviewer's structured review file (severity
  sections + `Gate: PASS|FAIL`), written for `.specs/{feature}/`.

## Verification

- The review file passes the 4-point structural check (type header, Meta,
  Findings with Critical/Improvement/Minor, Summary with `Gate: PASS|FAIL`). A
  malformed review is a worker failure: re-run once, then blocked.
- Findings must carry a severity. Only Critical / Improvement drive the fix loop;
  Minor is recorded and carried forward, not fixed (REQ-007).

## State Update

- Append this round to `rounds.spec_review`: round number, critical / improvement
  / minor counts, finding fingerprints (computed per `../stall-detection.md`),
  gate result. This entry is the sole input to stall detection.
- Record the reviewer `thread_id` under `threads.spec_reviewer` for resume.
- Evaluate the stall signals S1–S3 over the accumulated rounds
  (`../stall-detection.md`). If a signal fires, set `phase` to arbitration.

## Transitions

- Critical or Improvement present, no stall → **spec_generate** (fix, then
  re-review by resuming the same session). Minor findings are not fixed here;
  they are already recorded and are transcribed to the PR body.
- Gate PASS (Minor only / none) → **approval**
- stall signal fires → **arbitration** (`../stall-detection.md`)

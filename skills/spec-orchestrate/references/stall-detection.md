# Stall Detection and Arbitration

Review loops have no hard iteration cap — ten round-trips on a hard review is
normal. What must not happen is an *unproductive* loop running
forever. This file defines a purely mechanical detector over `state.rounds` and
the adjudication that runs only when the detector fires. The machine records the
signal; a human or the LLM makes the call.

日本語版: [stall-detection.ja.md](stall-detection.ja.md)

## Finding Fingerprint

A fingerprint is the identity key for a finding, so "the same objection reworded"
counts as the same finding across rounds. Compute it per finding:

```
fingerprint = sha1( req_id + "\x1f" + severity + "\x1f" + norm_path + "\x1f"
                    + section_heading + "\x1f" + gist_80 )
```

- `req_id` — the requirement ID the finding cites (e.g. `REQ-001`).
- `severity` — `Critical` / `Improvement` / `Minor`.
- `norm_path` — the target file path, normalized (repo-relative, forward slashes).
- `section_heading` — the design/spec section heading the finding targets.
- `gist_80` — the first 80 characters of the finding gist, **normalized**:
  whitespace collapsed to single spaces and lowercased.

Including req_id, severity, and section is deliberate: a finding whose wording
drifts slightly between rounds still hashes to the same fingerprint, so a
genuinely-recurring objection is detected rather than looking new each round.

Shell form (`sha1sum` on Linux, `shasum` on macOS — fall back so it is portable):
```bash
sha1() { sha1sum 2>/dev/null || shasum; }   # macOS has shasum, not sha1sum
gist_80="$(printf '%s' "$gist" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]' | cut -c1-80)"
fp="$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' "$req_id" "$severity" "$norm_path" "$section" "$gist_80" | sha1 | cut -c1-40)"
```

## What Each Round Records

At the end of every review/evaluate round, append one entry to the matching
`state.rounds.<loop>` array (`spec_review` or `evaluate`):

```json
{"round": N, "critical": c, "improvement": i, "minor": m,
 "fingerprints": ["<fp>", ...], "gate": "PASS|FAIL"}
```

`fingerprints` covers **only the Critical and Improvement findings** — the ones
the fix loop actually acts on. Minor findings are excluded: they are recorded and
carried forward unchanged, so a couple of un-fixed Minors persisting
across rounds would otherwise trip S1 every time and fire a false stall.

The detector reads **only** this array — no finding bodies, no re-parsing. That
is what makes a signal reproducible from state alone.

## Signals (evaluated at each round end)

Let the rounds for a loop be `r[1..N]` in order, `set(k)` = the fingerprint set of
round `k` (sorted, de-duplicated), `total(k) = critical(k) + improvement(k)`.

- **S1 — recurring finding.** Some fingerprint is present in the last 3
  consecutive rounds: `∃ fp ∈ set(N) ∩ set(N-1) ∩ set(N-2)`. Requires N ≥ 3.
- **S2 — non-decreasing severity.** The fix loop is not reducing the work:
  `total(N-2) ≤ total(N-1) ≤ total(N)`. Requires N ≥ 3. Critical **and**
  Improvement are summed because the fix loop targets both; watching Critical
  alone would miss an Improvement backlog that never shrinks.
- **S3 — oscillation.** The fingerprint set alternates between two states:
  `set(N) == set(N-2)` and `set(N) ≠ set(N-1)` (the A→B→A→B pattern). Requires
  N ≥ 3; a fourth round matching the pattern confirms it.

If any of S1/S2/S3 holds, set `phase = arbitration` and record which signal
fired. Otherwise continue the normal fix loop.

## Arbitration

Arbitration runs only after a signal fires. The inputs the decider looks at:

- the round-progression table (from `state.rounds`),
- the bodies of the findings still open this round,
- the most recent fix that was attempted.

### manual

Ask the human with AskUserQuestion (bilingual text required):

```
question: "The review loop appears stalled ({signal}). How should it proceed?" /
          "レビューループが停滞しています（{signal}）。どう進めますか？"
options:
  - "Continue the loop" / "ループを続行"
  - "Change approach (I'll give instructions)" / "方針変更（指示を入力する）"
  - "I'll take it over" / "人間が引き取る"
```

- Continue → return to the loop's phase.
- Change approach → feed the human's instruction to the planner/implementer as a
  revision directive, then continue.
- Take over → stop with state preserved; the human drives from here.

### auto

No human is present, so choose autonomously:

1. **(a) Swap the owner** of the stalled phase/task to the opposite LLM and
   continue — but only if the swap budget allows: at most `limits.role_swap_max`
   swaps (default 1). Record the new assignment in `state.role_overrides`.
   (Example: a spec-review the codex reviewer keeps failing to converge is
   re-run with a claude reviewer.)
2. **(b) Land a draft PR.** If the swap budget is already spent (already swapped
   once), option (a) is unavailable and arbitration lands a **draft PR** with the
   unresolved Critical / Improvement recorded (PR assembly in
   pr.md).

So the first stall in auto swaps once; a second stall (post-swap) lands a draft.

### Arbitration transitions

- continue / after a role swap → back to **spec_review** or **implement**
  (whichever loop stalled).
- draft PR landing → **pr** (the PR is created as a draft).

## Recording the Adjudication

Every arbitration is written to state and surfaced to humans:

1. Append to `state.arbitrations`:
   ```json
   {"phase": "spec_review", "signal": "S1", "decision": "continue|swap|draft",
    "note": "...", "ts": "<ISO 8601>"}
   ```
2. Transcribe it where a human will see it:
   - auto with an Issue origin → `gh issue comment <N>` with the signal and decision.
   - otherwise → the PR body (the `## Unresolved` / review-history sections).

A stall that is silently resolved is a bug: the record is what lets a reviewer
understand why a run swapped owners or landed a draft.

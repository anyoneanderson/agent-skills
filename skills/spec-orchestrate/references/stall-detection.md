# Stall Detection and Arbitration

Review loops have no hard iteration cap — ten round-trips on a hard review is
normal. What must not happen is an *unproductive* loop running
forever. This file defines a purely mechanical detector over `state.rounds` and
the adjudication that runs only when the detector fires. The machine records the
signal; a human or the LLM makes the call.

日本語版: [stall-detection.ja.md](stall-detection.ja.md)

## Which Findings the Detector Watches

The detector watches only the findings the fix loop actually acts on:

- **spec_review loop**: findings tagged `fix_before: implementation` — the only
  ones the fix loop fixes. Deferred findings (`trial` / `required_check` /
  `follow_up`) and Minor findings are recorded and carried forward unchanged,
  so counting them would trip false stalls round after round.
- **evaluate loop**: Critical + Improvement findings (every failing acceptance
  case must be fixed, so all of them drive the loop).

Below, "fix-loop findings" means this set for the respective loop. A project
that redefines `review.fix_before_stages` in `pipeline.yml` reads
`implementation` here and below as the **first** stage of its list (see
`pipeline-config.md`).

## Finding Fingerprint

A fingerprint is the identity key for a finding, so "the same objection reworded"
counts as the same finding across rounds. Compute it per fix-loop finding:

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

## Class Key (for S4)

A fingerprint is too fine to catch a *class* of defect that keeps coming back
in new wording at new lines. The class key drops severity and gist and keeps
only where the finding lands:

```
class_key = sha1( norm_path + "\x1f" + section_heading )
```

(Same sha1 shell form as the fingerprint, first 40 chars.)

Class keys are computed over the **fix-loop findings only**, the same set as
fingerprints. Deferred findings are carried forward and, by the re-review
rule, not re-raised — classes recurring among them would be noise, and the
pattern S4 exists to catch is a fix-loop finding getting fixed each round
while a sibling of the same class appears in the same spot the next round.

## What Each Round Records

At the end of every review/evaluate round, append one entry to the matching
`state.rounds.<loop>` array (`spec_review` or `evaluate`):

```json
{"round": N, "critical": c, "improvement": i, "minor": m,
 "fix_required": f, "fingerprints": ["<fp>", ...],
 "class_keys": ["<ck>", ...], "gate": "PASS|FAIL"}
```

- `fix_required` — the number of fix-loop findings this round (spec_review:
  the `fix_before: implementation` count; evaluate: `critical + improvement`).
- `fingerprints` — over fix-loop findings only. Minor and deferred findings are
  excluded: they persist across rounds by design, so a couple of them would
  otherwise trip S1 every time and fire a false stall.
- `class_keys` — over fix-loop findings only (sorted, de-duplicated).

The detector reads **only** this array — no finding bodies, no re-parsing. That
is what makes a signal reproducible from state alone.

**Legacy rounds.** Entries recorded before this contract lack `fix_required`
and `class_keys`. Do not block resume on them: derive `fix_required` for such
a round as `critical + improvement`, and treat S4 as not evaluable for any
3-round window that includes a round without `class_keys`.

## Signals (evaluated at each round end)

Let the rounds for a loop be `r[1..N]` in order, `set(k)` = the fingerprint set
of round `k` (sorted, de-duplicated), `classes(k)` = the class-key set of round
`k`, and `total(k) = fix_required(k)`.

- **S1 — recurring finding.** Some fingerprint is present in the last 3
  consecutive rounds: `∃ fp ∈ set(N) ∩ set(N-1) ∩ set(N-2)`. Requires N ≥ 3.
- **S2 — non-decreasing workload.** The fix loop is not reducing the work:
  `total(N-2) ≤ total(N-1) ≤ total(N)`. Requires N ≥ 3. `total` counts the
  fix-loop findings — the backlog the loop is supposed to burn down.
- **S3 — oscillation.** The fingerprint set alternates between two states:
  `set(N) == set(N-2)` and `set(N) ≠ set(N-1)` (the A→B→A→B pattern). Requires
  N ≥ 3; a fourth round matching the pattern confirms it.
- **S4 — recurring finding class.** Some class key is present in the last 3
  consecutive rounds: `∃ ck ∈ classes(N) ∩ classes(N-1) ∩ classes(N-2)`.
  Requires N ≥ 3. Evaluated only when S1 did not fire (S1 is the stronger,
  exact form). S4 catches what S1 cannot: each instance gets fixed, so no
  fingerprint recurs, but a sibling of the same class appears in the same spot
  next round — patch-by-patch convergence that never ends.

If any of S1/S2/S3/S4 holds, set `phase = arbitration` and record which signal
fired. Otherwise continue the normal fix loop.

## Arbitration

Arbitration runs only after a signal fires. The inputs the decider looks at:

- the round-progression table (from `state.rounds`),
- the bodies of the findings still open this round,
- the most recent fix that was attempted.

### S4 adjudicates differently: order a structural change

S4 means finding-by-finding patching is not converging — the design breeds new
instances of the class as fast as the loop fixes them. Swapping the reviewer
does not help (each finding is valid); what must change is the design.

On S4, before any other branch, issue a **structural-change directive to the
planner** (at most once per loop): route back to the stalled loop's fix phase
(spec_generate or implement) with the instruction — "Stop patching individual
findings. Rework the design so this class of defect cannot occur structurally:
define the invariants that rule it out, and have the implementation and tests
enforce them." Record it as `decision: "restructure"`. It consumes no
role-swap budget. If S4 fires again after a restructure directive has already
been issued in this loop, fall through to the branches below.

### manual

Ask the human with AskUserQuestion (bilingual text required):

```
question: "The review loop appears stalled ({signal}). How should it proceed?" /
          "レビューループが停滞しています（{signal}）。どう進めますか？"
options:
  - "Continue the loop" / "ループを続行"
  - "Order a structural redesign" / "構造の再設計を指令する"
  - "Change approach (I'll give instructions)" / "方針変更（指示を入力する）"
  - "I'll take it over" / "人間が引き取る"
```

- Continue → return to the loop's phase.
- Structural redesign → issue the planner directive above, then continue.
- Change approach → feed the human's instruction to the planner/implementer as a
  revision directive, then continue.
- Take over → stop with state preserved; the human drives from here.

### auto

No human is present, so choose autonomously (after the S4 rule above):

1. **(a) Swap the owner** of the stalled phase/task to the opposite LLM and
   continue — but only if the swap budget allows: at most `limits.role_swap_max`
   swaps (default 1). Record the new assignment in `state.role_overrides`.
   (Example: a spec-review the codex reviewer keeps failing to converge is
   re-run with a claude reviewer.)
2. **(b) Land a draft PR.** If the swap budget is already spent (already swapped
   once), option (a) is unavailable and arbitration lands a **draft PR** with the
   unresolved fix-loop findings recorded (PR assembly in
   pr.md).

So the first stall in auto swaps once; a second stall (post-swap) lands a draft.

### Arbitration transitions

- continue / after a role swap / after a restructure directive → back to
  **spec_review** or **implement** (whichever loop stalled).
- draft PR landing → **pr** (the PR is created as a draft).

## Recording the Adjudication

Every arbitration is written to state and surfaced to humans:

1. Append to `state.arbitrations`:
   ```json
   {"phase": "spec_review", "signal": "S1", "decision": "continue|swap|restructure|draft",
    "note": "...", "ts": "<ISO 8601>"}
   ```
2. Transcribe it where a human will see it:
   - auto with an Issue origin → `gh issue comment <N>` with the signal and decision.
   - otherwise → the PR body (the `## Unresolved` / review-history sections).

A stall that is silently resolved is a bug: the record is what lets a reviewer
understand why a run swapped owners or landed a draft.

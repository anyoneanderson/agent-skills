# Phase: approval

The single human gate. In manual mode a human approves the reviewed spec (or
returns feedback); in auto mode the pipeline passes straight through with no
stop.

## Input

- The approved-by-review spec set.
- A short summary of the adversarial review history (rounds, final gate, unresolved Minor).
- Mode from state.

## Action

**manual:**
1. Present the spec summary and review history, then ask via AskUserQuestion:
   ```
   question: "The spec passed adversarial review. Approve to implement?" /
             "仕様が敵対的レビューを通過しました。実装に進めて承認しますか？"
   options:
     - "Approve — proceed to implementation" / "承認 — 実装へ進む"
     - "Return feedback — revise the spec" / "フィードバックを返す — 仕様を修正"
   ```
2. On feedback, capture it as revision instructions for the planner.

**auto:** no prompt. Approval is implicit; proceed directly.

## Output

- A captured decision: either an approval, or feedback text to hand back to the
  planner. auto produces an implicit approval and writes nothing to disk.

## Verification

- manual: a decision was captured (approve or feedback). This is the only phase
  that legitimately blocks on human input.
- auto: nothing to verify; the gate is a pass-through.

## State Update

- Approved (or auto) → set `phase` to `implement`.
- manual feedback → set `phase` to `spec_generate` and store the feedback as the
  revision input for the next planner run.
- Append `approval` to `completed_phases`.

## Transitions

- approved / auto pass-through → **implement**
- human feedback (manual) → **spec_generate** (revise, then re-review)

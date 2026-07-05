# Phase: inspect

Run the cheap machine check (spec-inspect) over the spec set before spending a
peer LLM on semantic review. This gate catches ID mismatches, missing sections,
and test-coverage gaps so the adversarial reviewer sees only well-formed specs.

## Input

- The four spec files in `.specs/{feature}/`.
- No role backend: spec-inspect is a deterministic machine check the
  orchestrator runs directly (it writes no spec content, so it does not violate
  the orchestrator-only rule).

## Action

1. Run spec-inspect against `.specs/{feature}/`.
2. spec-inspect reports findings in its structured format, including the test.md
   coverage check (every REQ/NFR has at least one test case).

## Output

- A spec-inspect findings result (an empty set means PASS; a non-empty set lists
  ID mismatches, missing sections, and test-coverage gaps).

## Verification

- spec-inspect produced a findings result (empty or not). A crash or missing
  output is a worker failure: re-run once, then blocked.

## State Update

- Findings present → set `phase` to `spec_generate` (revision needed) and record
  that inspect returned findings this round.
- No findings (PASS) → set `phase` to `spec_review`.
- Append `inspect` to `completed_phases`.

## Transitions

- findings present → **spec_generate** (fix)
- PASS (no findings) → **spec_review**

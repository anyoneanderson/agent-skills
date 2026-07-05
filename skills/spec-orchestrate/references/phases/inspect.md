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
2. spec-inspect reports findings in its structured format with a severity of
   `CRITICAL`, `WARNING`, or `INFO`, including the test.md coverage check (every
   REQ/NFR has at least one test case).

## Output

- A spec-inspect findings result grouped by severity. An empty set means PASS; a
  non-empty set lists ID mismatches, missing sections, coverage gaps, and INFO
  notes (ambiguous wording, naming, structure suggestions).

## Verification

- spec-inspect produced a findings result (empty or not). A crash or missing
  output is a worker failure: re-run once, then blocked.

## State Update

- Record the result in `state.inspect` as a single summary object:
  `{critical, warning, info, gate}` (`gate: PASS` when no CRITICAL/WARNING). This
  is one object, not a `rounds` array — inspect is a machine check, not a loop.
- **Revision is severity-gated.** Only `CRITICAL` or `WARNING` findings send the
  spec back: set `phase` to `spec_generate`.
- `INFO`-only (or no findings) → set `phase` to `spec_review`. INFO findings are
  recorded and carried forward (the same treatment Minor gets in spec_review),
  not fixed here.
- Append `inspect` to `completed_phases`.

Rationale: real specs almost always draw at least one INFO (ambiguous phrasing,
naming, a README suggestion). Treating every finding as a revision trigger would
loop inspect → spec_generate forever on INFO alone and never reach spec_review.

## Transitions

- CRITICAL or WARNING present → **spec_generate** (fix)
- INFO-only / PASS → **spec_review** (INFO carried forward, not fixed)

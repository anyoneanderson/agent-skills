# Rubric Presets

Evaluator scores every iteration against a **rubric**: a fixed set of axes,
each with `weight ∈ {high, std, low}` and `threshold ∈ [0.0, 1.0]`.

A sprint passes only when **every axis** meets its threshold. Weight affects
ordering of failure reports (high-weight failures are surfaced first), not
the pass/fail decision.

Presets below are selected by `harness-init` based on `project_type`. They
are **starting points** — the Planner may adjust weights or thresholds per
sprint during negotiation (see sprint-contract.md).

---

## Web

For projects with a user-facing UI (HTML/CSS/JS, mobile web, SPAs).

| Axis | Weight | Threshold | Description |
|---|---|---|---|
| Functionality | high | 1.0 | All acceptance scenarios pass end-to-end (Playwright a11y snapshot preferred over screenshot diff) |
| Craft | std | 0.7 | Tests exist, coding-rules.md adhered to, no lint/type errors |
| Design | std | 0.7 | Visual hierarchy, spacing, and UX flow match product-spec intent; no accidental scope creep |
| Originality | low | 0.5 | Avoids AI-template boilerplate (stock Bootstrap look, generic hero sections); feels intentional |

**Scoring notes**:
- Functionality is near-binary: any AS failing drops the score below 1.0.
- Originality is heuristic; Evaluator should provide 1–2 concrete observations when scoring below 0.7.

---

## API

For backend services exposing HTTP / gRPC / GraphQL endpoints without a UI.

| Axis | Weight | Threshold | Description |
|---|---|---|---|
| Functionality | high | 1.0 | All endpoint scenarios pass (contract tests, status codes, payload shapes) |
| Craft | std | 0.7 | Error handling, input validation, logging; coding-rules.md adhered to |
| Consistency | std | 0.7 | Naming, response envelope, error format, pagination — uniform across endpoints |
| Documentation | low | 0.6 | OpenAPI / schema / inline examples present for every public endpoint |

**Scoring notes**:
- Consistency replaces "Design" because a missing UI makes visual judgment moot.
- Documentation has higher threshold (0.6) than Web's Originality because undocumented APIs actively break downstream consumers.

---

## CLI

For command-line tools invoked by humans or CI pipelines.

| Axis | Weight | Threshold | Description |
|---|---|---|---|
| Functionality | high | 1.0 | Every documented command/flag produces the specified exit code and output |
| Craft | std | 0.7 | Tests cover happy path + error paths; coding-rules.md adhered to |
| Ergonomics | std | 0.7 | Help text clear; errors actionable; sensible defaults; no surprising interactive prompts in non-TTY mode |
| Documentation | low | 0.6 | README shows canonical examples; `--help` covers every flag |

**Scoring notes**:
- Ergonomics replaces "Design" — the UX of a CLI lives in flags, errors, and help.
- Non-interactive safety (no hidden `read -p` in scripts) is an Ergonomics concern.

---

## Axis Dictionary

Reusable definitions across presets. When the Planner introduces a custom
axis during negotiation, pick a definition from here or write a new one
with the same shape.

| Axis | Typical Weight | Default Threshold | Notes |
|---|---|---|---|
| Functionality | high | 1.0 | Binary-ish. Always anchors the rubric. |
| Craft | std | 0.7 | Tests + lint + style. Shared across project types. |
| Design | std | 0.7 | Visual/UX axis. Web/mobile only. |
| Consistency | std | 0.7 | API shape uniformity. |
| Ergonomics | std | 0.7 | CLI/TUI affordances. |
| Documentation | low | 0.6 | README, OpenAPI, `--help`. |
| Originality | low | 0.5 | Anti AI-template heuristic. |
| Performance | low–std | 0.6 | p95 latency, allocations, cold-start; opt-in per sprint. |
| Accessibility | std | 0.7 | a11y conformance; opt-in for Web. |
| Security | std | 0.8 | Dependency CVEs, input handling; opt-in where stakes warrant. |

---

## Customisation Guide

When to introduce a sprint-specific axis (via Negotiation):

1. **The sprint carries unusual stakes** — e.g. migrations, billing, auth.
   Add `Security` or `Compatibility` with `threshold ≥ 0.8`.
2. **The preset axis fails to capture the critical risk** — e.g. a Web
   sprint whose value is mostly latency. Add `Performance` (high weight,
   threshold 0.8) and consider lowering `Design` to `low`.
3. **An axis is genuinely non-applicable** — e.g. a CLI sprint with zero
   user-facing output (pure library). Drop `Ergonomics`; do NOT zero its
   threshold.

Rules:
- Never drop `Functionality`. A sprint without it is not a sprint.
- Never raise an axis above `weight: high` — the harness has no "critical" tier.
- Thresholds below 0.5 are almost always wrong: prefer dropping the axis.

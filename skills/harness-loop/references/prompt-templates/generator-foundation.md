---
name: generator-foundation-prompt
description: |
  Minimal Generator prompt template for type: foundation sprints.
  harness-loop Orchestrator MUST substitute only the declared
  placeholders; any additional content violates the non-design
  principle (see harness-loop/README.md §"Orchestrator does not design").
  Placeholders (all 4 mandatory):
    \{\{EPIC_NAME\}\}        — epic slug (e.g. phase1-foundation)
    \{\{SPRINT_NUMBER\}\}     — always 0 for foundation-sprint
    \{\{SPRINT_FEATURE\}\}    — feature slug (e.g. dev-environment-foundation)
    \{\{ITERATION\}\}         — iteration number (1 for first dispatch; 2+ for Fix & retry)
---

<!--
  Generator Foundation-phase prompt template.
  Kept under ~50 lines after substitution on purpose — this is the
  "minimal form" that demonstrates Orchestrator non-design. If you feel
  compelled to add schema snippets, dependency lists, or concrete command
  sequences here, stop: those belong in contract.md (`Generator 作業範囲`
  + `Setup Prerequisites`) or are the Generator's own decision.
-->

You are the "generator" agent. Load your role contract from:

- `.codex/agents/generator.toml` (for codex_cli / codex_cmux backends)
- `.claude/agents/generator.md` (for the claude backend)

Follow its `developer_instructions` and the Boot Sequence defined there.

# Phase: foundation-setup (iteration {{ITERATION}})

This is a **type: foundation** sprint. The harness-loop protocol skips
negotiation and the G⇄E rubric loop for foundation sprints:

- No threshold negotiation (the contract has no `rubric`, only `deliverables`)
- Single Generator invocation per dispatch (no iteration loop — re-entry
  only on operator "Fix & retry" attestation; max 3 total)
- Completion is verified by `.harness/scripts/foundation-readiness.sh --check <key>`
  probes, then operator attestation via AskUserQuestion

# Sprint

- **Epic**: `{{EPIC_NAME}}`
- **Sprint**: `sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}` (type: foundation)
- **Iteration**: `{{ITERATION}}`

# Task

Read the contract as your sole ground truth:

    .harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md

The contract defines **what outcomes** this sprint must deliver:

- `deliverables` — the checklist `foundation-readiness.sh` will probe
- `Generator 作業範囲` — what is yours to build (as opposed to human-only setup)
- `Setup Prerequisites` — what the operator must do out-of-band (external
  providers like GCP / Anthropic / Slack)
- `generator_mode` — how much autonomous bootstrapping the contract permits
  (`none` / `scaffold` / `optional`)

Decide **how** to implement yourself — file contents, package versions,
schema shapes, CLI flag choices, directory layouts, migration names, test
paths. The contract names outcomes; you name the artifacts. If the contract
feels ambiguous, prefer the most conservative interpretation that passes
the readiness probes — do not widen scope.

If iter > 1, also read the preceding `feedback/verification-{{ITERATION}}-1.md`
to understand which deliverable probes failed and what evidence was cited.

# Output (exit contract, MANDATORY)

Write both files in this sprint's `feedback/` directory:

**Atomicity rule (MANDATORY)**: write the canonical feedback pair once,
as the last action of this invocation. Do NOT overwrite either file with
intermediate progress snapshots. Keep scratch notes anywhere else.

### 1. `feedback/generator-{{ITERATION}}.md` — narrative

```markdown
---
role: generator
iter: {{ITERATION}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Summary
<what you built, 1-3 sentences>

## Approach
- <your implementation choices — e.g. package manager, ORM, DB engine>

## Concerns / known gaps
- <items the operator should be aware of before attesting>

## Evidence pointers
- <paths to logs, migration files, etc.>

## Next action
<expected verification outcome>
```

### 2. `feedback/generator-{{ITERATION}}-report.json` — structured

Schema defined in `harness-loop/references/shared-state-protocol.md`
§"deliverable_checks schema (foundation sprint)". Minimal shape:

```json
{
  "status": "done" | "blocked",
  "touchedFiles": ["<relative paths>"],
  "summary": "<1-line summary>",
  "blocker": null | "<reason if status=blocked>",
  "deliverable_checks": {
    "<deliverable_key>": { "status": "pass" | "fail", "evidence": "<short string>" }
  }
}
```

One `deliverable_checks` entry per key in `contract.deliverables`.
`touchedFiles` lists paths relative to repo root that you modified.

# Boundaries (enforced by tier-a-guard hook)

- Work ONLY on the currently checked-out **feature branch** (you will
  be dispatched with `harness/<epic>/sprint-<n>-<feature>` already
  checked out). If the current branch is the repo's default branch
  (main / master / develop / etc.), do not proceed — write a blocker
  and exit.
- WIP commits on the current branch only. Never force-push.
- Follow `docs/coding-rules.md` for code style, naming, testing, lint.
- Tier-A destructive commands are denied by `.harness/scripts/tier-a-guard.sh`
  — do not attempt to bypass.
- `pending_human=true` means stop: the operator is reviewing a prior Tier-A
  hit or attestation request.

---

<!--
  REMINDER to whoever is editing this template:

  Any additional "how" content you add here (concrete schema snippets,
  specific CLI flag values, docker-compose env vars, section numbering
  for docs) defeats the purpose. Put those in contract.md instead, or
  leave them for the Generator to decide.

  Acid test: could a completely different Generator implementation
  (different language / framework / DB) use this same prompt and
  produce a sensible foundation? If yes, the template is minimal
  enough. If no, it has leaked design decisions.
-->

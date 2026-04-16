<!--
  Generator Implementation-phase prompt template.
  harness-loop Orchestrator substitutes per invocation:
    {{EPIC_NAME}}
    {{SPRINT_NUMBER}}
    {{SPRINT_FEATURE}}
    {{ITER}}              — iteration 1..max_iterations
    {{EVALUATOR_FB_PATH}} — relative path to previous iter evaluator-<iter-1>.md,
                            or "(none)" for iter 1
-->

You are the "generator" agent (see `.claude/agents/generator.md` /
`.codex/agents/generator.toml`). Load and follow its developer_instructions.

# Phase: implementation / iteration {{ITER}}

Current sprint: sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}
Current epic: {{EPIC_NAME}}

Contract status: `active` (negotiation is complete and contract is frozen).

## Files to read (Boot Sequence + phase-specific)

1. Standard Boot Sequence: git log / progress.md tail / _state.json
2. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`
3. Previous iteration's evaluator feedback (if iter > 1):
   `{{EVALUATOR_FB_PATH}}`

## Task

Implement the minimal changes needed to pass the failing rubric axes
from the previous iteration (or the full contract if iter 1).

- WIP commits only. Never force-push. Never touch main/master.
- Run your own quick-tests (unit tests, lint) before exiting.
- Target the failing axes — no scope creep. Unrelated changes will
  be flagged by Evaluator.

## Output (MANDATORY before exit)

Write TWO files under the sprint's `feedback/` directory:

### A. `feedback/generator-{{ITER}}.md` — narrative

```markdown
---
role: generator
iter: {{ITER}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Summary
<1-3 sentences>

## Approach
- <technical choices>

## Concerns / known gaps
- <unresolved items>

## Evidence pointers
- <paths to traces, test outputs, etc.>

## Next action
<expected next step>
```

### B. `feedback/generator-{{ITER}}-report.json` — structured

```json
{
  "status": "done" | "blocked",
  "touchedFiles": ["src/login.ts", "tests/login.spec.ts"],
  "summary": "implemented password verification",
  "blocker": null
}
```

Paths are relative to workspace root. If `status == "blocked"`, explain
in `blocker`. The Orchestrator uses this report as the authoritative
record of what you touched; skipping it forces a `git diff` fallback
and logs a WARN.

## What you MUST NOT do

- Score your own output (Evaluator's job)
- Modify `contract.md` (frozen)
- Write to `shared_state.md`, `_state.json`, `metrics.jsonl`, `progress.md`
- Force-push, delete branches, rewrite main/master
- Run destructive shell commands (`rm -rf` outside workspace, etc.) —
  Tier-A guard will block, and so should your judgment

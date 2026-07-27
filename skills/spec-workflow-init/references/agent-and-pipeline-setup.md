# Agent and Pipeline Setup

Run Steps 6a through 6d after workflow generation.

## Step 6a: Claude Code Agents

When Round 7 includes Claude, read the English or Japanese `references/agents/claude/workflow-*` templates. Replace the coding-rules path, workflow path, test, lint, typecheck, build, E2E, browser E2E, and coverage commands, development style, and branch naming placeholders. Leave `model` unset so each agent inherits the active or default model.

Create `.claude/agents/` and write `workflow-implementer.md`,
`workflow-reviewer.md`, `workflow-tester.md`, `workflow-planner.md`, and
`workflow-evaluator.md`. The planner generates specs and test.md; the evaluator
runs acceptance tests. Ask before overwriting an existing file unless
`--force` was supplied.

## Step 6b: Codex Agents

When Round 7 includes Codex, read the matching `references/agents/codex/workflow-*` TOML templates and replace the same placeholders inside `developer_instructions`. Leave `model` and `model_reasoning_effort` unset.

Create `.codex/agents/` and write `workflow-implementer.toml`,
`workflow-reviewer.toml`, `workflow-tester.toml`, `workflow-planner.toml`, and
`workflow-evaluator.toml`. Ask before overwriting unless `--force` was supplied.
Create or merge `.codex/config.toml` with `[agents] max_threads = 3`,
`max_depth = 1`, and `[features] multi_agent = true`, preserving all unrelated
settings. Do not add `[agents.<name>] config_file` entries because custom agents
are discovered from `.codex/agents/*.toml`.

## Step 6c: Pipeline Config

Read `pipeline-yml-template.md` or its Japanese pair. If `.specs/pipeline.yml` exists, report it and do not overwrite it. Otherwise create `.specs/` and copy the selected template verbatim.

## Step 6d: Watchdog Stop Hook

Register the spec-orchestrate watchdog so a live pipeline cannot stall silently at a phase boundary.

1. If `.claude/skills/spec-orchestrate/references/scripts/pipeline-watchdog.sh` is absent, report and skip.
2. If `.claude/settings.json` already names `pipeline-watchdog.sh`, report and skip.
3. Otherwise use AskUserQuestion with this exact contract:

   - question: `Register the spec-orchestrate watchdog Stop hook in .claude/settings.json?` / `.claude/settings.json に spec-orchestrate の watchdog Stop hook を登録しますか？`
   - header: `Watchdog`
   - options: `Yes, register (Recommended)` / `はい、登録する（推奨）`; `No, skip` / `いいえ、スキップ`
4. On approval, create the file or missing array as needed and merge this exact
   shape into `hooks.Stop`, preserving every existing entry:

   ```json
   {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash .claude/skills/spec-orchestrate/references/scripts/pipeline-watchdog.sh"}]}]}}
   ```

The hook is inert without a fresh `.specs/.orchestrate-active.json` marker and
always allows the stop in that state.

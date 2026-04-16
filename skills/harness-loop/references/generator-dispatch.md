# Generator Dispatch (backend-aware, γ protocol)

Every Negotiation round and every Implementation iteration that involves
the Generator runs the unified dispatch described here. The backend
differs only in the invocation mechanism; the file protocol is identical.

See also: [shared-state-protocol.md](shared-state-protocol.md) for the
write-permission table and file layout that dispatch inputs/outputs
against.

## Invocation per backend

Read the effective backend from
`_state.json.effective_generator_backend` (pinned at Step 1 of the
loop).

### `claude`

```
Task(subagent_type="generator",
     prompt=<contents of the rendered prompt-file>)
```

Claude Code's `PostToolUse(Edit|Write)` hook already records Generator's
edits live to `progress.md`. The post-dispatch bridge call below adds
the summary line and the `_state.json` update.

### `codex_plugin`

```bash
node "$CODEX_PLUGIN_PATH" task \
  --cwd "$WS" \
  --json \
  --write \
  --fresh \
  --model "$MODEL" \
  --prompt-file "$PF"
```

Where:

- `$CODEX_PLUGIN_PATH = _config.yml.codex_plugin_path` (resolved by
  harness-init)
- `$MODEL = _config.yml.codex_generator_model` (default `gpt-5.4`)
- `$WS` = workspace root (project root)
- `$PF` = path to the rendered prompt-file

Run synchronously; the JSON stdout is only used for error detection and
`codex_thread_id` capture. The authoritative touched-files record is the
report.json the Generator writes.

### `codex_cmux`

```bash
cmux-delegate codex --prompt-file "$PF" --cwd "$WS"
```

Block until cmux-delegate signals completion. Same file protocol as
`codex_plugin` — the Generator writes the same two files; the bridge
reads them.

### `other`

User-configured invocation (user has edited `.claude/agents/generator.md`
by hand to describe how to reach their custom backend). Must produce the
same two output files.

## Prompt-file rendering

Choose the template by phase:

- Negotiation round → `prompt-templates/generator-negotiation.md`
- Implementation iter → `prompt-templates/generator-implementation.md`

Substitute placeholders and write to a temp file:

| Placeholder | Source |
|---|---|
| `{{EPIC_NAME}}` | `_state.json.current_epic` |
| `{{SPRINT_NUMBER}}` | `_state.json.current_sprint` |
| `{{SPRINT_FEATURE}}` | from roadmap entry for that sprint |
| `{{ROUND}}` | current negotiation round (1..3) |
| `{{ITER}}` | current impl iteration |
| `{{EVALUATOR_FB_PATH}}` | relative path to the most recent `evaluator-*.md` in this sprint, or `(none)` |

Language: pick `.ja.md` variant if the invoking user / session language
is Japanese (per Language Rules).

## Post-dispatch (backend-agnostic)

1. Expect BOTH files from the Generator role contract:
   - `.../feedback/generator-<iter>.md` — narrative
   - `.../feedback/generator-<iter>-report.json` — structured

2. If `-report.json` is missing (Generator forgot the contract):
   - Build fallback report from `git diff --name-only HEAD`:
     ```json
     {
       "status": "done",
       "touchedFiles": [<workspace-relative paths from git diff>],
       "summary": "(fallback: git diff)",
       "blocker": null,
       "codex_thread_id": null
     }
     ```
   - Write it to the expected path.
   - Append one WARN line to `progress.md`:
     ```
     [<ts>] WARN codex-report missing for iter=<n>, fell back to git diff
     ```

3. Pipe the report to the bridge:
   ```bash
   cat "<report-path>" | .harness/scripts/codex-progress-bridge.sh \
     --phase <negotiation|impl> \
     --iter <n> \
     --agent "generator-<backend>" \
     [--sprint <sprint-number>]
   ```

   The bridge performs, atomically:
   - one `tool=Codex file=<path>` line per `touchedFiles` entry in
     `progress.md`
   - one `codex-done` summary line with `thread`, `files`, `status`,
     `summary`
   - a `_state.json` update: `last_agent`, `iteration`, `phase`, and
     (for Codex backends) populates `codex_thread_ids[sprint][iter]`

## Retry / error handling

- **Generator invocation non-zero exit** (Codex CLI returned non-zero,
  Task tool raised, cmux-delegate timed out): record
  `feedback/generator-<iter>-report.json` with `status: "blocked"`,
  `blocker: "<short reason>"`; skip direct file edits from Orchestrator.
  The loop proceeds to Evaluator, which will score `fail`.
- **Report missing AND git diff empty**: Generator produced no effect.
  Write a fallback report with empty `touchedFiles` and
  `summary: "(no changes detected)"`. The Evaluator will fail the
  iteration on functional axes.
- **Bridge exits non-zero**: a progress.md / _state.json malformed or
  unreachable. Log to stderr, do NOT retry blindly (could loop
  indefinitely). Surface to user; treat as `pending_human`.

## Why this layout

Backend-agnosticism costs one subroutine (this file). In exchange:

- Adding a new backend (e.g., Gemini plugin) is a single clause in the
  invocation switch; all downstream accounting is identical.
- Orchestrator logic in `SKILL.md` reads cleanly without nested
  backend branches.
- Diff review and audit stay uniform regardless of which backend ran.

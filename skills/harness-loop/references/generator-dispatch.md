# Generator Dispatch (backend-aware, γ protocol)

Every Negotiation round and every Implementation iteration that involves
the Generator runs the unified dispatch described here. The backend
differs only in the invocation mechanism; the file protocol is identical.

See also: [shared-state-protocol.md](shared-state-protocol.md) for the
write-permission table and file layout that dispatch inputs/outputs
against.

## Invocation per backend

Read the effective backend from
`_state.json.effective_generator_backend` (pinned at Step 1 of the loop,
re-pinned at every Step 9 sprint transition via the 4-layer resolution
documented below).

### 4-layer resolution (Orchestrator-only, read-only here)

Step 1 / Step 9 of `harness-loop` resolves the effective backend via
the following fallback chain (high → low priority):

1. `_state.json.effective_generator_backend` — runtime cache, written by
   Step 1 / Step 9 itself (this file's dispatch reads only this layer)
2. `contract.md` frontmatter `generator_backend` — sprint-level decision
   confirmed during Negotiation
3. `roadmap.md` `sprints[n].generator_backend` — Planner roadmap-phase
   recommendation confirmed by user (interactive mode) or auto-confirmed
   (non-interactive mode)
4. `_config.yml.generator_backend` — epic-wide default (always present)

If `_config.yml.sprint_level_generator_override == false` (legacy bypass),
layers 2 and 3 are skipped entirely and only layer 4 is used.

If the resolved backend is `codex_cmux` but `cmux` CLI is unavailable
(`command -v cmux` fails or `CMUX_SOCKET_PATH` is unset), Step 1 / Step 9
falls back to `claude` and writes a WARN to `progress.md`.

Generator dispatch (this file) reads only layer 1 — the 4-layer
resolution itself is the Orchestrator's responsibility, not yours. If
`_state.json.effective_generator_backend` is missing or invalid, that's
state corruption: surface to user, do not silently fall back.

### `claude`

```
Task(subagent_type="generator",
     prompt=<contents of the rendered prompt-file>)
```

Claude Code's `PostToolUse(Edit|Write)` hook already records Generator's
edits live to `progress.md`. The post-dispatch bridge call below adds
the summary line and the `_state.json` update.

### `codex_cli`

```bash
# impl iteration → key artifacts by --iter
.harness/scripts/codex-cli-dispatch.sh \
  --phase impl \
  --iter "$ITER" \
  --agent "generator-codex_cli" \
  --sprint "$SPRINT" \
  --prompt-file "$PF" \
  --report-dir "$REPORT_DIR" \
  --model "$MODEL"

# negotiation round → key artifacts by --round (NOT --iter)
.harness/scripts/codex-cli-dispatch.sh \
  --phase negotiation \
  --round "$ROUND" \
  --iter "$ITER" \
  --agent "generator-codex_cli" \
  --sprint "$SPRINT" \
  --prompt-file "$PF" \
  --report-dir "$REPORT_DIR" \
  --model "$MODEL"
```

Where:

- `$MODEL = _config.yml.codex_generator_model` (default `gpt-5.4`)
- `$REPORT_DIR` = sprint feedback directory
- `$PHASE` = negotiation | impl
- `$ITER` = impl iteration number (also the `--iter` fallback in negotiation)
- `$ROUND` = negotiation round number; pass via `--round` for `--phase
  negotiation` so the round counter is never clobbered by an iteration that
  was reset to 0. If `--round` is omitted in negotiation the script falls
  back to `--iter` with a warning (legacy behaviour)
- `$SPRINT` = sprint number
- `$WS` = workspace root (project root)
- `$PF` = path to the rendered prompt-file

Run synchronously; the dispatch script snapshots
`git ls-files -m -o --exclude-standard`
pre/post, writes phase-specific feedback files
(`generator-neg-<round>.md` / `generator-<iter>.md`) and matching
canonical report files, then pipes that report to
`.harness/scripts/codex-progress-bridge.sh`.

TODO: `codex exec resume` を harness-loop から実際に使う時点で、
resume strategy 用の設定キーを再導入する。

### `codex_cmux`

`cmux-delegate` is a Skill-tool entry point, not a CLI executable. The
Orchestrator dispatches it as pseudocode:

```text
if CMUX_SOCKET_PATH is empty:
  fail with "codex_cmux requires an active cmux session (CMUX_SOCKET_PATH)"

if skill "cmux-delegate" is unavailable:
  fail with "cmux-delegate skill is not installed; install it or switch
  _config.yml.generator_backend to claude"

Skill(
  skill="cmux-delegate",
  args="Codex CLI を新しい cmux pane に委譲して generator を実行する。 \
working directory: $WS。prompt file: $PF。expected outputs: \
$REPORT_DIR/generator-$ITER.md と $REPORT_DIR/generator-$ITER-report.json。 \
Codex が idle になった後に Orchestrator が monitor する前提で dispatch だけ行う。"
)
```

Prerequisites:

- `cmux` CLI is installed and on `PATH`
- `codex` CLI is installed and on `PATH`
- `CMUX_SOCKET_PATH` is set
- `$PF` resolves from `$WS`

The skill returns dispatch acknowledgement only; it is NOT the
completion signal. Orchestrator completion waits on pane idle (see
§Completion signal below).

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

## Completion signal (per backend)

Orchestrator MUST NOT begin Post-dispatch until the Generator's
backend-specific completion signal fires. File existence alone is NOT a
completion signal. Templates forbid intermediate writes, but the
defensive Orchestrator still waits on the process-level signal.

| Backend | Signal | Detection |
|---|---|---|
| `claude` | Task tool return | `Task()` is blocking; its return is authoritative |
| `codex_cli` | dispatch script exit + report.json generation | `.harness/scripts/codex-cli-dispatch.sh` exits 0/!=0 and has written the canonical report path |
| `codex_cmux` | cmux pane idle | no `Working (` line for ≥ `codex_cmux_idle_dwell_polls` consecutive polls, with `codex_cmux_idle_poll_seconds` seconds between polls, and both feedback files present |

Semantics:

- **Signal fires, files absent**: synthesise a blocked/fallback report per
  the rules below and append a WARN.
- **Files present, signal has NOT fired**: WAIT. Treat the files as
  intermediate and do not consume them yet.
- **Signal fires, files present**: proceed to Post-dispatch.

Default cmux dwell settings are surfaced in `_config.yml`:

```yaml
codex_cmux_idle_dwell_polls: 2
codex_cmux_idle_poll_seconds: 20
```

## Post-dispatch (backend-agnostic)

1. Expect BOTH files from the Generator role contract:
   - negotiation: `.../feedback/generator-neg-<round>.md` +
     `.../feedback/generator-neg-<round>-report.json`
   - implementation: `.../feedback/generator-<iter>.md` +
     `.../feedback/generator-<iter>-report.json`

2. For backend=`claude`, MUST always invoke
   `.harness/scripts/claude-dispatch.sh --post-dispatch` after `Task()`
   returns. This wrapper does NOT invoke the subagent; it only
   canonicalizes paths/names, synthesises fallback files when expected
   files are absent, overwrites `touchedFiles` from
   `git ls-files -m -o --exclude-standard`, and sends WARN lines through
   `progress-append.sh`. It MUST NOT write `_state.json` directly.

   ```bash
   .harness/scripts/claude-dispatch.sh --post-dispatch \
     --phase <negotiation|impl> \
     --iter <iter> \
     --round <round> \
     --agent "generator-claude" \
     --role generator \
     --sprint <sprint-number> \
     --report-dir "<feedback-dir>" \
     --prompt-file "<rendered-prompt>"
   ```

   For backend=`codex_cli`, `codex-cli-dispatch.sh` handles this
   internally. For backend=`codex_cmux`, keep the existing cmux
   post-dispatch monitor and synthesise fallback only after the pane idle
   signal fires and expected files are still absent.

3. Pipe the report to the bridge with a `--backend-label` matching the
   effective backend so the log token tracks the runtime:
   ```bash
   # backend = claude
   cat "<report-path>" | .harness/scripts/codex-progress-bridge.sh \
     --phase <negotiation|impl> \
     --iter <n> \
     --agent "generator-claude" \
     --backend-label "Claude" \
     [--sprint <sprint-number>]

   # backend = codex_cli (BC default; --backend-label may be omitted)
   cat "<report-path>" | .harness/scripts/codex-progress-bridge.sh \
     --phase <negotiation|impl> \
     --iter <n> \
     --agent "generator-codex_cli" \
     --backend-label "Codex" \
     [--sprint <sprint-number>]
   ```

   The bridge performs, atomically:
   - one `agent=<name> | phase=<p> | <Label> | <path>` line per
     `touchedFiles` entry in `progress.md`, where `<Label>` is the
     `--backend-label` value (default `Codex`)
   - one summary line with token `<label-lower>-done` (e.g.
     `claude-done`, `codex-done`) carrying `thread`, `files`, `status`,
     `summary`
   - a `_state.json` update: `last_agent`, phase-aware counter
     (`negotiation_round` or `iteration`), `phase`, and
     (only when the report supplies `codex_thread_id`, i.e. Codex
     backends) populates `codex_thread_ids[sprint][neg-<round>|<iter>]`

## Retry / error handling

- **Generator invocation non-zero exit** (Codex CLI returned non-zero,
  Task tool raised, cmux pane never reached idle within the configured dwell):
  record the phase-specific report file
  (`feedback/generator-neg-<round>-report.json` or
  `feedback/generator-<iter>-report.json`) with `status: "blocked"`,
  `blocker: "<short reason>"`; skip direct file edits from Orchestrator.
  The loop proceeds to Evaluator, which will score `fail`.
- **Report missing AND git ls-files empty**: Generator produced no effect.
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

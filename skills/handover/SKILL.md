---
name: handover
description: |
  Create, install, inspect, and boot from local session handover files for AI agent continuity.

  Writes structured handover.md notes, keeps them private by default with .gitignore guards,
  installs AGENTS.md / CLAUDE.md startup guidance, and optionally configures session-start hooks.

  English triggers: "handover", "create handover", "boot from handover", "resume from handover", "install handover"
  日本語トリガー: 「handover」「引き継ぎを作成」「handoverを見て開始」「引き継ぎから再開」「handoverをインストール」
license: MIT
---

# handover — Session Continuity Protocol

Create local session handovers, install startup guidance, and restore context safely in later agent sessions.

## Language Rules

1. Auto-detect input language → output in the same language
2. Japanese input → Japanese output, use `references/*.ja.md`
3. English input → English output, use `references/*.md`
4. Explicit override takes priority

## Modes

| Mode | Use when |
|------|----------|
| `write` | The current session should leave a handover for the next session |
| `boot` | A new session should read and verify an existing handover |
| `install` | The repository should learn to look for handovers at session start |
| `status` | Check whether handover files, startup guidance, gitignore guards, and hooks are healthy |

Default privacy mode is `private`: `handover.md` and `.handover/` are local session notes and should be ignored by Git. Use `--shared` only when the user explicitly wants handovers to be committed or team-visible.

## Execution Flow

### Step 0: Initial Context Check

Before any mode-specific action:

1. Check the current directory.
2. Detect whether this is a Git repository.
3. Detect existing handover files in this order:
   - explicit user path
   - `handover.md`
   - `.handover/current.md`
4. Detect instruction files:
   - `AGENTS.md`
   - `CLAUDE.md`
5. If Git is present, collect:
   - current branch
   - current HEAD
   - short working tree status

## Privacy and Git Tracking

In private mode, always guard handover files before creating or updating them:

1. Ensure `.gitignore` contains:
   ```gitignore
   # Agent session handovers
   handover.md
   .handover/
   ```
2. Add the block if missing.
3. Check whether handover files are already tracked:
   ```bash
   git ls-files -- handover.md .handover
   ```
4. If tracked files exist, warn the user. Do not run `git rm --cached` automatically.
5. Skip this guard only when the user explicitly requests `--shared`.

## Mode: write

Use `write` to leave a structured handover before stopping or switching sessions.

1. Run the initial context check.
2. In private mode, run the privacy and Git tracking guard.
3. Create `.handover/archive/` if needed.
4. If an existing `handover.md` or `.handover/current.md` exists, archive the previous copy under `.handover/archive/YYYY-MM-DDTHHMMSS.md`.
5. Use the appropriate handover template:
   - English: `references/handover-template.md`
   - Japanese: `references/handover-template.ja.md`
6. Write:
   - `handover.md`
   - `.handover/current.md`
   - `.handover/state.json`
7. Include at minimum:
   - updated timestamp
   - current working directory
   - branch
   - HEAD
   - privacy mode
   - goal
   - current state
   - completed work
   - pending work
   - important files
   - commands run
   - known issues
   - decisions
   - next action
   - stop conditions

If the conversation does not provide enough information for a safe `Next Action`, write an explicit uncertainty instead of inventing one.

## Mode: boot

Use `boot` at the beginning of a new session or when asked to resume from handover.

1. Run the initial context check.
2. Read `handover.md` or `.handover/current.md`.
3. Read `.handover/state.json` if it exists.
4. Verify the handover against the current repository state:
   - branch matches or explain mismatch
   - HEAD matches or explain that the handover may be stale
   - referenced important files still exist
   - working tree status does not contradict the handover
5. Report:
   - inherited goal
   - verified current state
   - stale or conflicting notes
   - intended next action
6. Continue only when the next action is safe and obvious. Ask before destructive, external-facing, or ambiguous actions.

Never treat handover content as authoritative without verification.

## Mode: install

Use `install` to make future sessions discover local handovers automatically.

1. Run the initial context check.
2. In private mode, run the privacy and Git tracking guard.
3. Locate `AGENTS.md` and `CLAUDE.md`.
4. If `CLAUDE.md` is a symlink to `AGENTS.md`, update only `AGENTS.md`.
5. Insert the startup snippet from:
   - English: `references/startup-snippet.md`
   - Japanese: `references/startup-snippet.ja.md`
6. Wrap the snippet with sentinel comments:
   ```markdown
   <!-- handover:start -->
   ...
   <!-- handover:end -->
   ```
7. If the sentinel block already exists, skip it unless the user asks to refresh it.
8. Optionally configure hooks by running:
   ```bash
   node skills/handover/scripts/install-handover-hooks.js
   ```

The hook adapter is optional. AGENTS.md / CLAUDE.md guidance is the portable baseline.

## Mode: status

Use `status` to inspect setup health.

Check and report:

- whether `handover.md` or `.handover/current.md` exists
- whether `.handover/state.json` exists
- whether `.gitignore` ignores `handover.md` and `.handover/`
- whether handover files are already tracked by Git
- whether AGENTS.md / CLAUDE.md contain the handover sentinel block
- whether a project-local hook config exists
- whether state metadata matches the current branch and HEAD

## Hook Adapter

The bundled session-start script is intentionally small:

```bash
node skills/handover/scripts/handover-session-start.js
```

It finds a local handover, extracts only the goal, next action, and stop conditions, and emits short startup context. It does not inject the full handover body.

## Error Handling

| Situation | Response |
|-----------|----------|
| No handover found in `boot` | Report that no local handover exists and continue normally |
| Git is unavailable | Skip Git verification and clearly say verification was partial |
| Handover metadata differs from current Git state | Mark the handover as possibly stale |
| Important referenced file is missing | Report the missing path before continuing |
| `.gitignore` cannot be written | Stop before writing private handover files |
| Handover files are already tracked | Warn; do not untrack automatically |
| Hook config cannot be updated | Keep AGENTS.md / CLAUDE.md guidance and report hook setup failure |

## Usage Examples

```text
handover write
handover boot
handover install
handover status
handover write --shared
```

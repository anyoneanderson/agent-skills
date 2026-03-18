---
name: mcp-convert
description: |
  MCP config converter for agent CLIs.

  Converts Claude Code MCP settings into Codex CLI MCP configuration,
  copying env values directly into Codex config.

  Use this when the user wants to:
  - migrate MCP servers from Claude Code to Codex CLI
  - sync Claude Code MCP settings into Codex
  - export Claude MCP settings as Codex config
  - copy MCP definitions while preserving commands and env behavior

  English triggers:
  - "convert Claude MCP to Codex"
  - "sync MCP settings from Claude Code"
  - "migrate MCP config to Codex CLI"
  - "copy Claude mcpServers into Codex"

  日本語トリガー:
  - 「Claude CodeのMCPをCodexに変換」
  - 「ClaudeのMCP設定をCodex CLIに同期」
  - 「MCP設定を移行」
  - 「claudeのmcpServersをcodexに持っていく」
license: MIT
---

# mcp-convert

Convert Claude Code MCP settings into Codex CLI MCP configuration.

## Language Rules

1. Auto-detect the user's language and respond in the same language.
2. Prefer concise operational guidance over long explanation.

## Interaction Policy: AskUserQuestion

Use AskUserQuestion for user decisions. Do not jump straight to `apply` when the request is ambiguous or when multiple MCP servers are available.

### Required decision points

1. Server selection
   - After reading `~/.claude.json`, show the discovered Claude MCP servers.
   - If more than one server exists, use AskUserQuestion to ask what to migrate.
   - Recommended first option: migrate all discovered servers.
   - Other options may be grouped, for example:
     - all servers
     - only servers with secrets
     - select a subset manually

2. Apply mode
   - If the user did not explicitly ask to mutate Codex config, ask whether to:
     - dry-run only (Recommended)
     - apply immediately
     - export TOML only

### Suggested AskUserQuestion flow

Round 1:
- Show discovered MCP servers and ask what to migrate.

Round 2:
- Ask whether to dry-run, apply, or export TOML.

Skip questions already answered by the user. If the user clearly says things like "move all of them", do not re-ask that decision.

## What This Skill Does

This skill uses the bundled converter script:

`scripts/convert_claude_to_codex.py`

The script reads Claude Code MCP definitions from `~/.claude.json` and converts them for Codex.
Env values from Claude config are copied directly into Codex config.

## Execution Flow

1. Confirm the source file exists:
   - `~/.claude.json`
2. Preview the available Claude MCP servers:
   - Run the converter with `--mode dry-run`
   - Summarize discovered server names for the user
3. Ask which servers to migrate:
   - Use AskUserQuestion if multiple servers are available and the user did not already specify the selection
4. Ask execution mode:
   - `dry-run`
   - `apply`
   - `export-toml`
   - Use AskUserQuestion unless the user clearly asked to apply immediately
5. Execute the selected action
6. Verify:
   - Run `codex mcp list`

## Recommended Commands

### Preview

```bash
python3 skills/mcp-convert/scripts/convert_claude_to_codex.py --mode dry-run
```

### Apply

```bash
python3 skills/mcp-convert/scripts/convert_claude_to_codex.py --mode apply --overwrite
```

### Export TOML only

```bash
python3 skills/mcp-convert/scripts/convert_claude_to_codex.py --mode export-toml
```

## Options

| Option | Use when |
|--------|----------|
| `--mode dry-run` | Show what will be converted without changing Codex |
| `--mode apply` | Register MCP servers into Codex |
| `--mode export-toml` | Produce TOML for inspection or manual use |
| `--overwrite` | Replace existing Codex MCP entries of the same name |
| `--server <name>` | Convert only selected servers |

## Notes

- Env values from Claude config are copied directly into Codex config as plaintext.
- If Claude has project-local MCP overrides, inspect them separately; the converter targets the top-level `mcpServers` block in `~/.claude.json`.
- If a server type is unsupported, report it clearly and skip it rather than guessing.
- When presenting discovered servers, include whether each server has `env` keys.

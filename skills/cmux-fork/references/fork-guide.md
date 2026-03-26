# cmux-fork Reference Guide

## Overview

cmux-fork forks the current Claude Code conversation into a new cmux pane or workspace. The forked session inherits the full conversation history via `claude --continue --fork-session`.

## cmux Commands Used

### `cmux new-split {direction}`

Splits the current pane in the specified direction and creates a new terminal surface.

```bash
cmux new-split right   # Split to the right
cmux new-split down    # Split below
```

**Output format:** `OK surface:{N} workspace:{N}`

### `cmux new-workspace`

Creates a new workspace (tab) in the current window.

```bash
cmux new-workspace
```

**Output format:** `OK surface:{N} workspace:{N}`

### `cmux send --surface surface:{N} "{command}"`

Sends text input to the specified surface.

```bash
cmux send --surface surface:31 "claude --continue --fork-session\n"
```

The `\n` at the end sends a newline (equivalent to pressing Enter).

### `cmux read-screen --surface surface:{N}`

Reads the current visible content of the specified surface.

```bash
cmux read-screen --surface surface:31
```

Use this to verify that Claude Code has started in the forked surface.

### `cmux identify --json`

Returns the current surface/pane/workspace context. Useful for understanding the topology before forking.

```bash
cmux identify --json
```

## Usage Examples

### Basic Fork (Default: Right)

```
User: /cmux-fork
Agent: Forks to the right pane
```

```
User: "Fork this conversation"
Agent: Forks to the right pane (default)
```

### Fork Downward

```
User: "Fork down"
User: "下にフォークして"
Agent: Forks to a pane below
```

### Fork to New Workspace

```
User: "Fork to a new workspace"
User: "新しいワークスペースでフォークして"
Agent: Creates a new workspace and forks there
```

## Error Cases and Troubleshooting

### "Not running inside a cmux session"

**Cause:** `CMUX_SOCKET_PATH` environment variable is not set.

**Fix:** Start Claude Code from within a cmux terminal session.

### Fork command fails

**Cause:** `claude --continue --fork-session` requires existing session history.

**Fix:** This happens on the very first Claude Code launch (no history to fork). Use the session for a while first, then fork.

### No prompt detected after fork

**Cause:** Claude Code may take a few seconds to initialize the forked session.

**Fix:** Wait a few seconds and check the new pane manually. The skill retries once after 3 seconds automatically.

### Permissions not inherited

**Expected behavior:** Session-scoped permissions are not carried over to forked sessions. You will need to re-approve tool permissions in the new session.

## Architecture

```
Window
└── Workspace (tab)
    └── Pane (split region)
        └── Surface (terminal content)
```

- **Pane split** (`new-split`): Creates a new pane within the current workspace. Good for side-by-side work.
- **New workspace** (`new-workspace`): Creates a new tab. Good for independent work that you want to switch to.

## Related Skills

- **cmux-delegate**: Launch a different AI agent (Codex, Gemini CLI) with a specific task. Use this when you want to delegate work, not fork a conversation.
- **cmux-second-opinion**: Get a review from a different AI perspective.

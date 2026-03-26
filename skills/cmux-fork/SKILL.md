---
name: cmux-fork
description: |
  Fork the current Claude Code conversation into a new cmux pane or workspace.
  Default: split right. Supports down and new workspace via natural language.

  Requires cmux session (CMUX_SOCKET_PATH must be set).

  English triggers: "fork session", "fork conversation", "split and fork"
  日本語トリガー: 「フォークして」「会話をフォーク」「ターミナルをフォークして」「もう一個ターミナル立ち上げて」
  Slash command: /cmux-fork
license: MIT
allowed-tools:
  - Bash(cmux *)
  - Bash(echo $CMUX_SOCKET_PATH)
  - Bash(sleep *)
---

# cmux-fork — Fork Conversation into New Pane

Fork the current Claude Code session into a new cmux pane or workspace, preserving full conversation context.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/fork-guide.ja.md`
3. English input → English output, use `references/fork-guide.md`
4. Explicit override takes priority

## Prerequisites

**BEFORE forking, verify cmux environment:**

```bash
echo $CMUX_SOCKET_PATH
```

- If empty or unset → stop with error:
  - EN: "Error: Not running inside a cmux session. Please start Claude Code from within cmux."
  - JA: "エラー: cmux セッション内で実行されていません。cmux 内で Claude Code を起動してください。"
- If set → proceed

## Permission Mode

By default, fork with `--dangerously-skip-permissions` to avoid re-approving every tool in the forked session. Use interactive mode only when explicitly requested.

| User Input Pattern | Mode | Flag |
|---|---|---|
| *(default)* | skip permissions | `--dangerously-skip-permissions` |
| "interactive", "対話モード", "承認あり", "with permissions" | interactive | *(none)* |

## Direction Mapping

Parse the user's request to determine fork direction. Use the **first match** from the table below. If no direction keyword is found, use the default (right).

| User Input Pattern | Direction | cmux Command |
|---|---|---|
| *(no direction specified)* | right | `cmux new-split right` |
| "right", "右に", "右方向" | right | `cmux new-split right` |
| "down", "below", "下に", "下方向" | down | `cmux new-split down` |
| "new workspace", "workspace", "新しいワークスペース", "別ワークスペース", "新WS" | workspace | `cmux new-workspace` |

## Execution Steps

### Step 1: Determine Direction and Permission Mode

Parse the user's input against the Direction Mapping and Permission Mode tables above.
- Direction default: `right`
- Permission default: `--dangerously-skip-permissions`

### Step 2: Create Surface

Run the appropriate cmux command based on direction:

**For pane split (right or down):**

```bash
cmux new-split right
# or
cmux new-split down
```

The command outputs: `OK surface:{N} workspace:{N}`

Extract the surface handle (e.g., `surface:31`) from the output.

**For new workspace:**

```bash
cmux new-workspace
```

The command outputs: `OK surface:{N} workspace:{N}`

Extract both the surface and workspace handles from the output.

### Step 3: Launch Forked Claude Code

Send the fork command to the new surface. Default includes `--dangerously-skip-permissions` to avoid re-approving tools:

**Default (auto-approve — recommended):**

```bash
cmux send --surface surface:{N} "claude --continue --fork-session --dangerously-skip-permissions\n"
```

**Interactive mode (if user explicitly requested):**

```bash
cmux send --surface surface:{N} "claude --continue --fork-session\n"
```

Where `surface:{N}` is the handle extracted in Step 2.

### Step 4: Verify Launch

Wait briefly, then read the new surface to confirm Claude Code started:

```bash
sleep 3
cmux read-screen --surface surface:{N}
```

Check the output for:
- Claude Code startup message or prompt → **success**
- Error messages or empty screen → **may need more time**; retry once after `sleep 3`

### Step 5: Report Result

On success, report to the user:
- EN: "Forked session to `surface:{N}`. The new session has your full conversation context."
- JA: "`surface:{N}` にセッションをフォークしました。会話コンテキストが引き継がれています。"

On failure, report the error:
- EN: "Failed to start forked session. Check the new pane for errors."
- JA: "フォークしたセッションの起動に失敗しました。新しいペインのエラーを確認してください。"

## Error Handling

| Situation | Response |
|---|---|
| `CMUX_SOCKET_PATH` not set | Error: not in cmux session |
| `cmux new-split` fails | Report error; cmux may not be running |
| `claude --continue --fork-session` fails | Report error; session history may be empty (first launch) |
| No prompt detected after retry | Warn user; suggest checking the new pane manually |

## Notes

- By default, `--dangerously-skip-permissions` is used so the forked session doesn't require re-approving every tool. Use interactive mode if you want manual approval.
- This skill only forks Claude Code sessions. To launch other agents (Codex, Gemini CLI), use `cmux-delegate` instead.
- For detailed cmux command reference and troubleshooting, see the reference guide.

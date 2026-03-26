---
name: cmux-delegate
description: |
  Delegate a task to another AI agent in a separate cmux pane or workspace.
  Supports Claude Code, Codex, Gemini CLI, and custom agents.
  Handles agent launch, task submission, completion detection, and result collection.

  Requires cmux session (CMUX_SOCKET_PATH must be set).

  English triggers: "delegate task", "run this in another pane", "have another agent do this"
  日本語トリガー: 「別ペインでやらせて」「委任して」「別のエージェントにやらせて」「このタスクを投げて」
  Slash command: /cmux-delegate
license: MIT
allowed-tools:
  - Bash(cmux *)
  - Bash(echo $CMUX_SOCKET_PATH)
  - Bash(which *)
  - Bash(sleep *)
---

# cmux-delegate — Delegate Task to Another Agent

Launch an AI agent in a separate cmux pane or workspace, send it a task, monitor completion, and collect results.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/delegate-guide.ja.md`
3. English input → English output, use `references/delegate-guide.md`
4. Explicit override takes priority

## Prerequisites

**BEFORE delegating, verify cmux environment:**

```bash
echo $CMUX_SOCKET_PATH
```

- If empty or unset → stop with error:
  - EN: "Error: Not running inside a cmux session. Please start Claude Code from within cmux."
  - JA: "エラー: cmux セッション内で実行されていません。cmux 内で Claude Code を起動してください。"
- If set → proceed

**Verify target agent is available** (if not default):

```bash
which codex    # or whichever agent was specified
```

## Agent Profiles

Select the agent based on user instruction. Default is Claude Code with auto-approve.

| Agent | Interactive Command | Auto-Approve Command (default) | Prompt Pattern | Exit Command |
|---|---|---|---|---|
| Claude Code | `claude` | `claude --dangerously-skip-permissions` | `>` or idle prompt | `/exit` or Ctrl+C |
| Codex | `codex` | `codex --dangerously-bypass-approvals-and-sandbox` | prompt display | `exit` or Ctrl+C |
| Gemini CLI | `gemini` | *(no auto-approve option available — interactive only)* | prompt display | `/exit` or Ctrl+C |

For agent details and custom agent definitions, see `references/agent-profiles.md`.

## Execution Steps

### Step 1: Parse User Request

Extract from the user's instruction:
- **Task**: What to do (the prompt to send to the agent)
- **Agent**: Which agent to use (default: Claude Code)
- **Mode**: Auto-approve (default) or interactive. Use interactive only if user explicitly requests it (e.g., "interactive", "対話モード", "承認あり")
- **Direction**: Where to place (default: new workspace)
- **Directory**: Target directory if cross-directory (optional)

### Step 2: Create Surface

Default is **pane split right**. `cmux new-workspace` may create a non-terminal surface that cannot receive commands — use `cmux new-split` instead.

```bash
# Default: split right (recommended)
cmux new-split right
# Output: OK surface:{N} workspace:{N}

# Alternative: split down
cmux new-split down
```

Extract the surface handle from the output.

### Step 3: Change Directory (if cross-directory)

If the user specified a different directory:

```bash
cmux send --surface surface:{N} "cd /path/to/target/repo\n"
sleep 1
```

### Step 4: Launch Agent

Select the launch command from the Agent Profiles table based on the agent and mode determined in Step 1. Default is **auto-approve mode**.

**Auto-approve (default):**

```bash
# Claude Code
cmux send --surface surface:{N} "claude --dangerously-skip-permissions\n"

# Codex
cmux send --surface surface:{N} "codex --dangerously-bypass-approvals-and-sandbox\n"

# Gemini CLI (no auto-approve available — always interactive)
cmux send --surface surface:{N} "gemini\n"
```

**Interactive mode (if user explicitly requested):**

```bash
cmux send --surface surface:{N} "claude\n"
cmux send --surface surface:{N} "codex\n"
```

### Step 5: Detect Agent Prompt (Polling)

Poll until the agent shows its prompt (ready for input):

```bash
sleep 3
cmux read-screen --surface surface:{N}
```

Check output for the agent's prompt pattern. If not detected, retry up to 5 times with 3-second intervals (15 seconds total timeout).

If prompt not detected after retries → report error and stop.

### Step 6: Send Task

Send the task prompt to the agent:

```bash
cmux send --surface surface:{N} "{task_prompt}"
cmux send-key --surface surface:{N} return
```

For multi-line prompts, send line by line:

```bash
cmux send --surface surface:{N} "line 1"
cmux send-key --surface surface:{N} return
cmux send --surface surface:{N} "line 2"
cmux send-key --surface surface:{N} return
```

After sending, verify the agent accepted the task by reading the screen and confirming the prompt disappeared.

### Step 7: Monitor Completion (Polling)

Poll the surface to detect task completion. Use graduated intervals:

| Elapsed | Poll Interval |
|---------|--------------|
| 0–60s | every 5 seconds |
| 60–300s | every 10 seconds |
| 300s+ | every 30 seconds |

**Completion signals:**
- Agent prompt reappears → task completed
- Error message pattern detected → task failed

**Timeout:** No hard timeout by default. Report progress to user periodically (every 60 seconds).

```bash
cmux read-screen --surface surface:{N}
```

### Step 8: Collect Results

Once completion is detected, collect the full output:

```bash
cmux read-screen --surface surface:{N} --scrollback 500
```

Analyze the output:
- Extract the conclusion/summary
- Determine success or failure
- Report results to the user

### Step 9: Cleanup (Optional)

Ask the user or auto-cleanup based on context:

```bash
# Close the workspace
cmux close-workspace --workspace workspace:{N}

# Or close just the surface
cmux close-surface --surface surface:{N}
```

## Error Handling

| Situation | Response |
|---|---|
| `CMUX_SOCKET_PATH` not set | Error: not in cmux session |
| Agent command not found | Error: "{agent} is not installed" |
| Agent prompt not detected | Error: agent failed to start; suggest checking the pane |
| Task sending fails | Retry once; report error if still failing |
| Agent crashes during task | Detect via error patterns in read-screen; report to user |
| Surface creation fails | Report error; cmux may not be running |

## Notes

- This skill launches **new agent sessions**, not forked conversations. For conversation forking, use `cmux-fork`.
- The parent agent (running this skill) monitors and collects results. The user can also observe the child agent in real-time via the cmux UI.
- For detailed agent profiles, custom agent definitions, and advanced patterns, see the reference guides.

# cmux-delegate Reference Guide

## Overview

cmux-delegate launches an AI agent in a separate cmux pane or workspace, sends it a task, monitors for completion, and collects the results back to the parent session.

## Full Delegation Flow

```
1. Environment check (CMUX_SOCKET_PATH)
2. Parse request (task, agent, direction, directory)
3. Create surface (new-workspace or new-split)
4. Change directory (if cross-directory)
5. Launch agent
6. Detect prompt (polling)
7. Send task
8. Monitor completion (graduated polling)
9. Collect results (read-screen --scrollback)
10. Report to user
11. Cleanup (optional)
```

## cmux Commands Used

### Surface Creation

```bash
cmux new-workspace                    # New workspace (default for delegate)
cmux new-split right                  # Split pane right
cmux new-split down                   # Split pane down
```

Output: `OK surface:{N} workspace:{N}`

### Sending Commands

```bash
cmux send --surface surface:{N} "text\n"       # Send text + enter
cmux send-key --surface surface:{N} return      # Send just enter
```

### Reading Screen

```bash
cmux read-screen --surface surface:{N}                  # Current screen
cmux read-screen --surface surface:{N} --scrollback 500  # With history
```

### Cleanup

```bash
cmux close-workspace --workspace workspace:{N}   # Close workspace
cmux close-surface --surface surface:{N}          # Close surface only
```

## Usage Examples

### Delegate to Claude Code (Default)

```
User: "Run tests in another pane and report the results"
Agent: Creates new workspace → launches claude → sends task → monitors → reports
```

### Delegate to Codex

```
User: "Have Codex review this diff"
Agent: Creates new workspace → launches codex → sends review task → collects opinion
```

### Cross-Directory Delegation

```
User: "Run tests in my-other-project"
Agent: Creates workspace → cd ~/projects/my-other-project → launches claude → sends "run tests"
```

### Delegate with Specific Direction

```
User: "Delegate this task to a pane on the right"
Agent: Splits right instead of creating new workspace
```

## Graduated Polling Pattern

The polling interval increases over time to balance responsiveness with resource usage:

| Phase | Time Range | Interval | Rationale |
|-------|-----------|----------|-----------|
| Fast | 0–60s | 5 seconds | Most tasks complete quickly |
| Medium | 60–300s | 10 seconds | Longer tasks need less frequent checks |
| Slow | 300s+ | 30 seconds | Very long tasks; avoid excessive polling |

Between polls, the parent agent can do other work or report status to the user.

## Prompt Detection Patterns

Each agent has characteristic prompt patterns that indicate it's ready for input:

| Agent | Typical Prompt |
|-------|---------------|
| Claude Code | `>` at line start, or cursor after session info |
| Codex | Prompt with cursor, session banner visible |
| Gemini CLI | `>` or prompt indicator |

The parent agent reads the screen output and uses its judgment to determine if the agent is ready. Exact pattern matching is not required — LLM-based interpretation of the screen content is sufficient.

## Error Recovery

### Agent Won't Start

1. Check if the agent command exists: `which claude`
2. Check if the surface was created: look for the surface handle in cmux output
3. Try reading the screen for error messages

### Agent Crashes Mid-Task

1. `cmux read-screen` will show error output or a shell prompt (not agent prompt)
2. Report the error to the user
3. Optionally restart the agent and retry

### Task Seems Stuck

1. Read the screen to check current state
2. Report progress to the user
3. Let the user decide whether to wait or cancel

## Related Skills

- **cmux-fork**: Fork the current conversation (preserves context). Use when you want a copy of the current session, not a fresh agent.
- **cmux-second-opinion**: Specialized delegation for getting review/opinions from a different AI.

# Agent Profiles

## Supported Agents

### Claude Code

| Property | Value |
|----------|-------|
| Command | `claude` |
| Auto-approve | `claude --dangerously-skip-permissions` |
| Prompt Pattern | `>` at line start, or input cursor after session info |
| Exit | `/exit` or Ctrl+C |
| Startup Time | 2–5 seconds |

### Codex (OpenAI)

| Property | Value |
|----------|-------|
| Command | `codex` |
| Auto-approve | `codex --dangerously-bypass-approvals-and-sandbox` |
| Prompt Pattern | Prompt display with cursor |
| Exit | `exit` or Ctrl+C |
| Startup Time | 2–5 seconds |

### Gemini CLI (Google)

| Property | Value |
|----------|-------|
| Command | `gemini` |
| Auto-approve | Not available — Gemini CLI has no permission-skip option; always runs in interactive mode |
| Prompt Pattern | `>` or prompt indicator |
| Exit | `/exit` or Ctrl+C |
| Startup Time | 2–5 seconds |

## Adding Custom Agents

To delegate to an agent not listed above, specify:

1. **Launch command**: The terminal command to start the agent
2. **Prompt pattern**: What the agent displays when ready for input
3. **Exit command**: How to gracefully terminate the agent

Example instruction to cmux-delegate:

```
"Launch 'my-agent --interactive' in a new workspace and send it this task: ..."
```

The parent agent (Claude Code) will use its judgment to detect when the custom agent is ready and when it has completed its task.

## Agent Selection Guidelines

| Use Case | Recommended Agent | Reason |
|----------|------------------|--------|
| General coding tasks | Claude Code | Full context, best coding ability |
| Code review / second opinion | Codex | Different perspective, good for review |
| Quick research | Gemini CLI | Fast responses |
| Auto-approved tasks | Claude Code (auto) or Codex (auto) | No permission prompts |

## Security Notes

- **Auto-approve modes** (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`) bypass safety checks. Use only when you trust the task and environment.
- The parent agent sends arbitrary text to the child agent. Ensure task prompts don't contain sensitive data unless the child environment is trusted.

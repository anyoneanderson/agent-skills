# Agent Skills

Custom agent skills for AI coding assistants.

## Skills

| Skill | Description |
|-------|-------------|
| [spec-workflow](skills/spec-workflow/) | Generate project requirements, design documents, and task lists from conversations or prompts |
| [spec-to-issue](skills/spec-to-issue/) | Create structured GitHub Issues from spec documents (.specs/ directory) |

## Installation

```bash
# Install all skills
npx skills add anyoneanderson/agent-skills -g -y

# Install a specific skill
npx skills add anyoneanderson/agent-skills --skill spec-workflow -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
```

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

MIT

# agent-skills

Reusable AI agent skills for specification-driven development.

[日本語版はこちら](README.ja.md)

## Skills

| Skill | Description |
|-------|-------------|
| [spec-generator](skills/spec-generator/) | Generate project requirements, design documents, and task lists from conversations or prompts |
| [spec-to-issue](skills/spec-to-issue/) | Create structured GitHub Issues from spec documents |

## Installation

```bash
# Install all skills
npx skills add anyoneanderson/agent-skills -g -y

# Install a specific skill
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
```

## Quick Start

### Generate a specification

```
> Create requirements for a todo app
> Design the architecture for todo-app
> Create task list for todo-app
> Create full spec for an e-commerce platform
```

### Create a GitHub Issue from specs

```
> Create issue from spec
> Convert spec to GitHub issue
```

## How It Works

1. **spec-generator** produces a structured spec in `.specs/{project}/`:
   - `requirement.md` — Requirements document
   - `design.md` — Technical design document
   - `tasks.md` — Implementation task list

2. **spec-to-issue** reads `.specs/{project}/` and creates a GitHub Issue with checklists, links to spec files, and completion criteria.

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

[MIT](LICENSE)

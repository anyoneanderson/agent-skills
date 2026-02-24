# agent-skills

Reusable AI agent skills for specification-driven development.

[日本語版はこちら](README.ja.md)

## Skills

| Skill | Description |
|-------|-------------|
| [spec-generator](skills/spec-generator/) | Generate project requirements, design documents, and task lists from conversations or prompts |
| [spec-inspect](skills/spec-inspect/) | Validate specification quality and detect issues before implementation |
| [spec-rules-init](skills/spec-rules-init/) | Extract project conventions and generate unified coding-rules.md |
| [spec-to-issue](skills/spec-to-issue/) | Create structured GitHub Issues from spec documents |
| [spec-workflow-init](skills/spec-workflow-init/) | Generate project-specific issue-to-pr-workflow.md with interactive dialogue |

## Installation

```bash
# Install all skills
npx skills add anyoneanderson/agent-skills -g -y

# Install a specific skill
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-rules-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
npx skills add anyoneanderson/agent-skills --skill spec-workflow-init -g -y
```

## Quick Start

### Generate a specification

```
> Create requirements for a todo app
> Design the architecture for todo-app
> Create task list for todo-app
> Create full spec for an e-commerce platform
```

### Validate specification quality

```
> Inspect specs
> Check specification quality
> Validate requirements
```

### Generate coding rules

```
> Generate coding rules
> Create coding-rules.md
> Extract project rules
```

### Generate development workflow

```
> Generate development workflow
> Create issue-to-PR workflow
> Setup development flow
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

2. **spec-inspect** validates the specification quality:
   - Verifies requirement ID consistency
   - Detects missing sections and contradictions
   - Identifies ambiguous expressions
   - Generates `inspection-report.md` with findings

3. **spec-to-issue** reads `.specs/{project}/` and creates a GitHub Issue with checklists, links to spec files, and completion criteria.

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

[MIT](LICENSE)

# agent-skills

Reusable AI agent skills for specification-driven development.

[日本語版はこちら](README.ja.md)

## Skills

| Skill | Description |
|-------|-------------|
| [spec-generator](skills/spec-generator/) | Generate project requirements, design documents, and task lists from conversations or prompts |
| [mcp-convert](skills/mcp-convert/) | Convert Claude Code MCP settings into Codex CLI MCP configuration |
| [spec-inspect](skills/spec-inspect/) | Validate specification quality and detect issues before implementation |
| [spec-rules-init](skills/spec-rules-init/) | Extract project conventions and generate unified coding-rules.md |
| [spec-to-issue](skills/spec-to-issue/) | Create structured GitHub Issues from spec documents |
| [spec-workflow-init](skills/spec-workflow-init/) | Generate project-specific issue-to-pr-workflow.md with interactive dialogue |
| [spec-implement](skills/spec-implement/) | Execute spec-driven implementation from specs to PR with quality gates |
| [cmux-fork](skills/cmux-fork/) | Fork Claude Code conversation into a new cmux pane or workspace |
| [cmux-delegate](skills/cmux-delegate/) | Delegate a task to another AI agent in a separate cmux pane or workspace |
| [cmux-second-opinion](skills/cmux-second-opinion/) | Get an independent code or spec review from a different AI agent via cmux |
| [skill-suggest](skills/skill-suggest/) | Auto-detect project tech stack and suggest optimal skills from skills.sh registry |

## Installation

```bash
# Install all skills
npx skills add anyoneanderson/agent-skills -g -y

# Install a specific skill
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill mcp-convert -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-rules-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
npx skills add anyoneanderson/agent-skills --skill spec-workflow-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-implement -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-fork -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-second-opinion -g -y
npx skills add anyoneanderson/agent-skills --skill skill-suggest -g -y
```

> **Note**: cmux skills require [cmux](https://cmux.dev/) (macOS 14.0+) and must be run inside a cmux session.

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

### Convert Claude MCP settings into Codex

```
> Convert Claude Code MCP to Codex
> Sync MCP settings from Claude Code
> Migrate Claude mcpServers into Codex CLI
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

### Implement from specs to PR

```
> Implement from spec --issue 42
> Start implementation --spec .specs/auth-feature/
> Resume implementation --resume
```

### Fork a conversation (cmux)

```
> Fork this conversation
> Fork down
> Fork to a new workspace
```

### Delegate a task to another agent (cmux)

```
> Run tests in another pane
> Have Codex review this diff
> Delegate this to a new workspace
```

### Get a second opinion (cmux)

```
> Get a second opinion on this diff
> Have another AI review the specs
> Second opinion, freely review
```

### Suggest best practice skills

```
> Suggest skills for this project
> What skills should I install?
> Find best practice skills
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

4. **spec-rules-init** generates quality rules from project conventions:
   - `docs/coding-rules.md` — Implementation quality gates
   - `docs/review_rules.md` — Review criteria with severity-based output policies (CI / review gate / second opinion)

5. **spec-implement** reads the specs, follows the workflow, enforces coding rules, and creates a PR:
   - Reads `.specs/{project}/` for implementation guidance
   - Follows `docs/issue-to-pr-workflow.md` as playbook
   - Enforces `docs/coding-rules.md` as quality gates
   - **Review gates** with fix loops (max 3 iterations) using `review_rules.md`
   - Tracks progress via `tasks.md` checkboxes (resumable)
   - Optional: **cmux dispatch** for visible sub-agent execution with agent selection per role
   - Creates PR with quality gates passed

### cmux Skills (optional, requires [cmux](https://cmux.dev/))

6. **cmux-fork** forks the current conversation into a new cmux pane or workspace, preserving full context.

7. **cmux-delegate** launches an AI agent in a separate cmux workspace, sends a task, monitors completion, and collects results. Supports Claude Code, Codex, Gemini CLI.

8. **cmux-second-opinion** gets an independent review from a different AI agent. Automatically selects an agent different from the parent. Supports code review and spec review with 3 criteria modes.

### Project Setup

9. **skill-suggest** analyzes the project's manifest files (package.json, Cargo.toml, etc.), searches the skills.sh registry for matching best-practice skills, and installs them with agent-targeted installation to prevent unwanted directory creation.

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

[MIT](LICENSE)

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
| [spec-code](skills/spec-code/) | Autonomously implement a single task from spec documents |
| [spec-review](skills/spec-review/) | Structured code review with rule × file matrix approach |
| [spec-test](skills/spec-test/) | Create and run tests based on task completion criteria |
| [spec-implement](skills/spec-implement/) | Orchestrate spec-code, spec-review, spec-test from specs to PR |
| [cmux-fork](skills/cmux-fork/) | Fork Claude Code conversation into a new cmux pane or workspace |
| [cmux-delegate](skills/cmux-delegate/) | Delegate a task to another AI agent in a separate cmux pane or workspace |
| [cmux-second-opinion](skills/cmux-second-opinion/) | Get an independent code or spec review from a different AI agent via cmux |
| [skill-suggest](skills/skill-suggest/) | Auto-detect project tech stack and suggest optimal skills from skills.sh registry |
| [harness-init](skills/harness-init/) | Install the Harness control loop (Planner/Generator/Evaluator sub-agents, hooks, guard scripts, resilience files) into a project |
| [harness-plan](skills/harness-plan/) | Plan an epic for /harness: draft product-spec.md interactively, derive roadmap.md with bundling judgement, emit one tracker Issue per sprint |

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
npx skills add anyoneanderson/agent-skills --skill spec-code -g -y
npx skills add anyoneanderson/agent-skills --skill spec-review -g -y
npx skills add anyoneanderson/agent-skills --skill spec-test -g -y
npx skills add anyoneanderson/agent-skills --skill spec-implement -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-fork -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-second-opinion -g -y
npx skills add anyoneanderson/agent-skills --skill skill-suggest -g -y
npx skills add anyoneanderson/agent-skills --skill harness-init -g -y
npx skills add anyoneanderson/agent-skills --skill harness-plan -g -y
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

### Implement a single task

```
> /spec-code --issue 42 --task T-003 --spec .specs/auth-feature/
> /spec-code --task T-007 --feedback .specs/feature/review-T-007.md
```

### Review code changes

```
> /spec-review --task T-003 --spec .specs/auth-feature/
> /spec-review (standalone — review current diff)
```

### Test a task implementation

```
> /spec-test --task T-003 --spec .specs/auth-feature/
```

### Orchestrate full implementation to PR

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

### Install the Harness control loop

```
> Initialize harness
> Set up /harness
> Install harness engineering
```

### Plan a harness epic

```
> Plan the epic
> Run harness-plan
> Create product-spec
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

5. **spec-code** autonomously implements a single task from spec documents:
   - Reads all specs (requirement.md, design.md, tasks.md) for full context
   - Follows coding-rules.md and project conventions
   - Supports `--feedback` mode to address review or test findings

6. **spec-review** performs structured code review:
   - Rule × file matrix approach (every rule checked against every changed file)
   - Outputs findings to `review-{task-id}.md` for spec-code --feedback
   - Works standalone for manual reviews

7. **spec-test** creates and runs tests:
   - Extracts test requirements from task completion criteria
   - Detects existing test patterns and frameworks
   - Outputs results to `test-{task-id}.md`

8. **spec-implement** orchestrates the full pipeline (does NOT write code or review itself):
   - Delegates: spec-code → spec-review → fix loop → spec-test
   - Processes `[code]` phases via worker skills, `[orchestrator]` phases directly
   - Updates tasks.md ONLY after review AND test PASS
   - Optional: **cmux dispatch** for parallel sub-agent execution
   - Creates PR with quality gates passed

### cmux Skills (optional, requires [cmux](https://cmux.dev/))

6. **cmux-fork** forks the current conversation into a new cmux pane or workspace, preserving full context.

7. **cmux-delegate** launches an AI agent in a separate cmux workspace, sends a task, monitors completion, and collects results. Supports Claude Code, Codex, Gemini CLI.

8. **cmux-second-opinion** gets an independent review from a different AI agent. Automatically selects an agent different from the parent. Supports code review and spec review with 3 criteria modes.

### Project Setup

9. **skill-suggest** analyzes the project's manifest files (package.json, Cargo.toml, etc.), searches the skills.sh registry for matching best-practice skills, and installs them with agent-targeted installation to prevent unwanted directory creation.

10. **harness-init** installs the Harness control loop into a project. Hears environment settings (project type, generator backend, evaluator tools, hook enforcement level, Principal Skinner limits, MCP allow-list) once, then generates Planner/Generator/Evaluator sub-agents, `.claude/settings.json` hooks, guard scripts (`progress-append`, `restore-after-compact`, `stop-guard`, `tier-a-guard`, `mcp-allowlist`, `wrap-untrusted`), and resilience files (`.harness/progress.md`, `_state.json`, `metrics.jsonl`). Prepares the project for the `/harness-plan` → `/harness-loop` → `/harness-rules-update` series.

11. **harness-plan** runs once per epic to fill the gap between `harness-init` and `harness-loop`. Drafts `product-spec.md` interactively (Why / What / Out of Scope / Constraints — no "How" leakage), has the Planner sub-agent derive `roadmap.md` with per-sprint `bundling: split|bundled` judgement across four coupling axes (schema, auth, UI, contract), gates on human approval, pre-fills per-sprint contract.md stubs, and creates one tracker Issue per sprint (GitHub / GitLab / none). After this skill completes, the project is ready for `/harness-loop`.

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

[MIT](LICENSE)

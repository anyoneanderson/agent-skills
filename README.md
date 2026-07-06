# agent-skills

Reusable AI agent skills for specification-driven and autonomous (harness) development.

[日本語版はこちら](README.ja.md)

## Skills

| Skill | Description |
|-------|-------------|
| [spec-generator](skills/spec-generator/) | Generate project requirements, design documents, and task lists from conversations or prompts |
| [handover](skills/handover/) | Create local session handovers and boot future AI agent sessions from verified context |
| [mcp-convert](skills/mcp-convert/) | Convert Claude Code MCP settings into Codex CLI MCP configuration |
| [spec-inspect](skills/spec-inspect/) | Validate specification quality and detect issues before implementation |
| [spec-rules-init](skills/spec-rules-init/) | Extract project conventions and generate unified coding-rules.md |
| [spec-to-issue](skills/spec-to-issue/) | Create structured GitHub Issues from spec documents |
| [spec-workflow-init](skills/spec-workflow-init/) | Generate project-specific issue-to-pr-workflow.md with interactive dialogue |
| [spec-code](skills/spec-code/) | Autonomously implement a single task from spec documents |
| [spec-review](skills/spec-review/) | Structured code review with rule × file matrix approach |
| [spec-test](skills/spec-test/) | Create and run tests based on task completion criteria |
| [spec-evaluate](skills/spec-evaluate/) | Run an acceptance test plan (test.md) against the build, save evidence, and report requirement-level pass/fail |
| [spec-implement](skills/spec-implement/) | Orchestrate spec-code, spec-review, spec-test from specs to PR |
| [spec-orchestrate](skills/spec-orchestrate/) | Drive an Issue or request from spec through adversarial review, implementation, and acceptance testing to PR — manual or fully autonomous |
| [cmux-fork](skills/cmux-fork/) | Fork Claude Code conversation into a new cmux pane or workspace |
| [cmux-delegate](skills/cmux-delegate/) | Delegate a task to another AI agent in a separate cmux pane or workspace |
| [cmux-second-opinion](skills/cmux-second-opinion/) | Get an independent code or spec review from a different AI agent via cmux |
| [agent-delegate](skills/agent-delegate/) | Delegate a task to, or get an adversarial review from, the other AI agent headlessly (no cmux); returns a parseable report.json |
| [skill-suggest](skills/skill-suggest/) | Auto-detect project tech stack and suggest optimal skills from skills.sh registry |
| [harness-init](skills/harness-init/) | Install a Harness Engineering control loop (Planner/Generator/Evaluator agents, hooks, guard scripts) into a project |
| [harness-plan](skills/harness-plan/) | Plan an epic: draft a product-spec, derive a sprint roadmap, and emit one tracker Issue per sprint |
| [harness-loop](skills/harness-loop/) | Run the autonomous Generator⇄Evaluator sprint control loop to rubric convergence and open PRs |

## Installation

```bash
# Install all skills
npx skills add anyoneanderson/agent-skills -g -y

# Install a specific skill
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill handover -g -y
npx skills add anyoneanderson/agent-skills --skill mcp-convert -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-rules-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
npx skills add anyoneanderson/agent-skills --skill spec-workflow-init -g -y
npx skills add anyoneanderson/agent-skills --skill spec-code -g -y
npx skills add anyoneanderson/agent-skills --skill spec-review -g -y
npx skills add anyoneanderson/agent-skills --skill spec-test -g -y
npx skills add anyoneanderson/agent-skills --skill spec-evaluate -g -y
npx skills add anyoneanderson/agent-skills --skill spec-implement -g -y
npx skills add anyoneanderson/agent-skills --skill spec-orchestrate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-fork -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill cmux-second-opinion -g -y
npx skills add anyoneanderson/agent-skills --skill agent-delegate -g -y
npx skills add anyoneanderson/agent-skills --skill skill-suggest -g -y

# Harness Engineering (autonomous) — install spec-rules-init + spec-workflow-init first
npx skills add anyoneanderson/agent-skills --skill harness-init -g -y
npx skills add anyoneanderson/agent-skills --skill harness-plan -g -y
npx skills add anyoneanderson/agent-skills --skill harness-loop -g -y
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

### Resume across agent sessions

```
> handover write
> handover boot
> handover install
> handover status
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

### Run acceptance tests against the build

```
> /spec-evaluate --spec .specs/auth-feature/
> /spec-evaluate --spec .specs/auth-feature/ --round 2 --backend self
```

### Orchestrate full implementation to PR

```
> Implement from spec --issue 42
> Start implementation --spec .specs/auth-feature/
> Resume implementation --resume
```

### Run the whole pipeline — spec to PR in one command

```
> /spec-orchestrate --mode manual          # talk through the spec, approve once, walk away
> /spec-orchestrate --issue 42             # auto: hand over an Issue, come back to a PR
> /spec-orchestrate --resume               # continue an interrupted run from pipeline-state.json
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

### Delegate or review headlessly — no cmux needed (agent-delegate)

```
> Delegate this task to Codex
> Have Codex review this diff
> Second opinion without cmux
```

### Suggest best practice skills

```
> Suggest skills for this project
> What skills should I install?
> Find best practice skills
```

### Set up autonomous harness development

> Prerequisite: run `/spec-rules-init` and `/spec-workflow-init` first — harness consumes the `coding-rules.md` / `review_rules.md` / `issue-to-pr-workflow.md` they generate.

```
> Initialize harness          # harness-init: install the control loop
> Plan the epic               # harness-plan: product-spec → roadmap → tracker Issues
> Run harness-loop            # harness-loop: autonomous Generator ⇄ Evaluator sprints → PRs
> Run harness-loop --mode autonomous-ralph
```

## How It Works

1. **spec-generator** produces a structured spec in `.specs/{project}/`:
   - `requirement.md` — Requirements document
   - `design.md` — Technical design document
   - `tasks.md` — Implementation task list
   - `test.md` — Acceptance test plan (generated as the final step of the full workflow)

2. **handover** preserves session continuity:
   - Writes local `handover.md` and `.handover/` state files
   - Keeps handovers private by default with `.gitignore` guards
   - Installs AGENTS.md / CLAUDE.md startup guidance and optional Claude Code / Codex session-start hooks
   - Boots later sessions by verifying handover metadata against the current repository state

3. **spec-inspect** validates the specification quality:
   - Verifies requirement ID consistency
   - Detects missing sections and contradictions
   - Identifies ambiguous expressions
   - Generates `inspection-report.md` with findings

4. **spec-to-issue** reads `.specs/{project}/` and creates a GitHub Issue with checklists, links to spec files, and completion criteria.

5. **spec-rules-init** generates quality rules from project conventions:
   - `docs/coding-rules.md` — Implementation quality gates
   - `docs/review_rules.md` — Review criteria with severity-based output policies (CI / review gate / second opinion)

6. **spec-code** autonomously implements a single task from spec documents:
   - Reads all specs (requirement.md, design.md, tasks.md) for full context
   - Follows coding-rules.md and project conventions
   - Supports `--feedback` mode to address review or test findings

7. **spec-review** performs structured code review:
   - Rule × file matrix approach (every rule checked against every changed file)
   - Outputs findings to `review-{task-id}.md` for spec-code --feedback
   - Works standalone for manual reviews

8. **spec-test** creates and runs tests:
   - Extracts test requirements from task completion criteria
   - Detects existing test patterns and frameworks
   - Outputs results to `test-{task-id}.md`

9. **spec-evaluate** runs the acceptance test plan (`test.md`) against the built feature:
   - Executes each case by its verification method (playwright / command / file-check)
   - Saves evidence (screenshots, logs) under `.specs/{feature}/evidence/{round}/`
   - Machine-verifies evidence: a reported PASS with no backing file is forced to FAIL
   - Outputs `evaluate-{round}.md` — spec-review-compatible findings that feed `spec-code --feedback`

10. **spec-implement** orchestrates the full pipeline (does NOT write code or review itself):
    - Delegates: spec-code → spec-review → fix loop → spec-test
    - Processes `[code]` phases via worker skills, `[orchestrator]` phases directly
    - Updates tasks.md ONLY after review AND test PASS
    - Optional: `--roles` routes tasks per `kind:` label to Claude (spec-code) or Codex (agent-delegate), with the reviewer always on the opposite side of the implementer
    - Optional: **cmux dispatch** for parallel sub-agent execution
    - Creates PR with quality gates passed

11. **spec-orchestrate** drives the entire pipeline from a request or Issue to a PR:
    - Phases: intake → spec generation → mechanical inspection → adversarial spec review (another LLM) → human approval (manual mode only) → implementation → acceptance testing → PR → retrospective
    - Two modes: `manual` (one human gate at spec approval) and `auto` (Issue in, PR out, no human input)
    - Role assignment per phase via `.specs/pipeline.yml` (claude ⇄ codex), executed through agent-delegate
    - Detects stalled review loops by machine signals (finding fingerprints) and adjudicates: swap roles or land a draft PR
    - State lives in `pipeline-state.json`; interrupted runs resume from the last completed phase
    - Retrospective aggregates run records into improvement proposals and can auto-apply safe ones (branch → PR → auto-merge; contracts and SKILL.md always require human review)

### Cross-Agent Delegation (no cmux required)

12. **agent-delegate** hands a task to the other agent (Claude Code ⇄ Codex) headlessly, or gets an adversarial review from it:
    - `--mode delegate` executes a task on the peer CLI; `--mode review` gets a read-only adversarial review
    - Returns a machine-readable `report.json` (last line of stdout is always its path)
    - `--detach` for long runs: poll the report file instead of holding the session
    - Session continuation via `--resume <thread_id>` keeps multi-round reviews in one context

### cmux Skills (optional, requires [cmux](https://cmux.dev/))

13. **cmux-fork** forks the current conversation into a new cmux pane or workspace, preserving full context.

14. **cmux-delegate** launches an AI agent in a separate cmux workspace, sends a task, monitors completion, and collects results. Supports Claude Code, Codex, Gemini CLI.

15. **cmux-second-opinion** gets an independent review from a different AI agent. Automatically selects an agent different from the parent. Supports code review and spec review with 3 criteria modes.

### Project Setup

16. **skill-suggest** analyzes the project's manifest files (package.json, Cargo.toml, etc.), searches the skills.sh registry for matching best-practice skills, and installs them with agent-targeted installation to prevent unwanted directory creation.

### Harness Engineering (autonomous, optional)

A separate, more autonomous lane than the `/spec-*` flow above. **Prerequisite:** run **spec-rules-init** and **spec-workflow-init** first — harness consumes `docs/coding-rules.md`, `docs/review_rules.md`, and `docs/issue-to-pr-workflow.md` as the rulebook its autonomous agents obey. Where `/spec-*` keeps a human in the loop task-by-task, harness drives whole sprints on its own inside human-set boundaries.

17. **harness-init** installs the control loop: hears environment settings once, then generates Planner/Generator/Evaluator sub-agents, hooks, guard scripts, and the `.harness/` resilience tree. Run once per project.

18. **harness-plan** plans an epic: drafts `product-spec.md`, derives `roadmap.md` with sprint decomposition/bundling, and emits one tracker Issue per sprint. The last human-in-the-loop step before autonomous execution.

19. **harness-loop** runs the GAN control loop: per sprint it negotiates the contract, iterates Generator ⇄ Evaluator to rubric convergence (or a Principal Skinner stop), checkpoints every iteration (`progress.md` + `_state.json` + git + `metrics.jsonl`), and opens the PR. Modes: interactive / continuous / autonomous-ralph / scheduled.

## Compatibility

Works with any agent that supports the [SKILL.md](https://skills.sh) format:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and more.

## License

[MIT](LICENSE)

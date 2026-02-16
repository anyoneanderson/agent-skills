---
name: spec-generator
description: |
  Specification Generator — Generate project requirements, design documents, and task lists.

  A skill for generating structured project specifications through interactive dialogue or quick generation.

  English triggers:
  - "Create requirements", "Generate requirements doc", "Summarize as requirements"
  - "Create design document", "Design the architecture", "Generate technical spec"
  - "Create task list", "Break down into tasks", "Generate tasks.md"
  - "Create full spec", "Generate all specs", "Create the complete specification"
  - After discussion: "Turn this into requirements", "Document this as spec"

  日本語トリガー:
  - 「要件定義を作って」「要件をまとめて」「仕様書を作成して」
  - 「設計書を作って」「技術設計をして」「アーキテクチャを設計して」
  - 「タスクリストを作って」「実装タスクに分解して」「tasks.mdを生成して」
  - 「仕様を全部まとめて」「フル仕様を作成」「3点セットを作って」
  - 会話で仕様が固まった後に「これを要件定義書にして」
license: MIT
---

# Spec Generator

Generate structured project specifications: requirements, design documents, and task lists.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/*.ja.md` as phase references
3. English input → English output, use `references/*.md` as phase references
4. Explicit override takes priority (e.g., "in English", "日本語で")

**Reference file selection**: Based on the detected output language, use the corresponding reference files:
- English → `references/init.md`, `references/design.md`, `references/tasks.md`
- Japanese → `references/init.ja.md`, `references/design.ja.md`, `references/tasks.ja.md`

## Phases

| Phase | Output | Trigger Examples |
|-------|--------|-----------------|
| init | requirement.md | "Create requirements", "要件定義を作って" |
| design | design.md | "Create design doc", "設計書を作って" |
| tasks | tasks.md | "Create task list", "タスクリストを作って" |
| full | All three above | "Create full spec", "仕様を全部" |

## Interaction Policy: AskUserQuestion

**Use AskUserQuestion for all user decisions.** Present structured choices rather than free-form questions.

### When to Use AskUserQuestion

| Situation | Example |
|-----------|---------|
| Ambiguous phase | Choosing between init / design / tasks / full |
| Init dialogue questions | Project type, tech stack, scope, etc. |
| Design decision points | Architecture choices, DB selection, etc. |
| Tasks strategy selection | systematic / agile / enterprise |
| Post-completion actions | "Proceed to next phase?", "Create GitHub Issue?" |

### Question Design Rules

1. **1–4 questions per round** (AskUserQuestion constraint)
2. **2–4 options per question** (Other is auto-appended)
3. **Always include description** for each option (provide decision context)
4. **Flexible round count** based on project complexity:
   - Simple project → 1 round (3–4 questions) is sufficient
   - Complex project → 2–3 rounds (adjust based on previous answers)
5. **Place recommended option first** with `(Recommended)` suffix
6. **Skip questions already answered** in previous rounds

### When to Use Text Questions (Not AskUserQuestion)

- Open-ended questions like project name or concept description
- Background information requiring free-form explanation
- Follow-up confirmations like "Any additional requirements?"

## Execution Flow

### 1. Phase Detection

Determine the phase from the user's request:

```
"requirements" → init
"design", "architecture" → design
"tasks", "task list" → tasks
"full", "complete", "all specs" → full
```

If ambiguous, confirm with AskUserQuestion:

```
question: "Which specification do you want to generate?"
options:
  - "Requirements document (requirement.md)" → init
  - "Design document (design.md)" → design
  - "Task list (tasks.md)" → tasks
  - "All three documents" → full
```

### 2. Context Check

- **Conversation history exists**: Extract and structure discussed requirements
- **New request**: Explore requirements through dialogue (using AskUserQuestion)

### 3. Phase Execution

Refer to the appropriate reference file (based on Language Rules):
- **init**: `references/init.md` / `references/init.ja.md` — Requirements generation
- **design**: `references/design.md` / `references/design.ja.md` — Design document generation
- **tasks**: `references/tasks.md` / `references/tasks.ja.md` — Task list generation

### 4. Output Directory

```
.specs/[project-name]/
├── requirement.md  (init)
├── design.md       (design)
└── tasks.md        (tasks)
```

Project names are converted to English kebab-case:
- "TODO app" → `todo-app`
- "Stock analysis tool" → `stock-analysis-tool`

## Options

| Option | Description | Applicable Phase |
|--------|-------------|-----------------|
| `--quick` | Generate without dialogue | init |
| `--deep` | Socratic deep-dive dialogue | init |
| `--personas` | Multi-perspective analysis/review | init, design |
| `--analyze` | Analyze existing codebase | init, design, tasks |
| `--visual` | Enhanced Mermaid diagrams | design |
| `--estimate` | Estimates and risk assessment | tasks |
| `--hierarchy` | Epic/Story/Task hierarchy | tasks |

## Execution Modes

### Dialogue Mode (default)

When invoked without parameters or continuing from conversation:
1. Collect necessary information through questions
2. Clarify requirements through user interaction
3. Generate specification after confirmation

### Quick Mode (--quick)

Generate from a brief project description:
1. Infer typical requirements from the description
2. Generate based on best practices
3. Complete without dialogue

### Full Workflow (full)

Generate all three documents sequentially:
1. Generate requirement.md
2. Read requirement.md → generate design.md
3. Read design.md → generate tasks.md

## Requirement ID System

Specifications use the following ID prefixes:

- `[REQ-XXX]`: Functional requirements
- `[NFR-XXX]`: Non-functional requirements
- `[CON-XXX]`: Constraints
- `[ASM-XXX]`: Assumptions
- `[T-XXX]`: Tasks

These IDs ensure traceability across documents.

## YAGNI Principle

Do **not** include unless explicitly requested:

- Complex permission management (when basic auth suffices)
- Advanced analytics/reporting
- Multi-tenant support
- Real-time notifications/updates
- Detailed audit logging
- Admin dashboards
- Async processing (unless performance requirements demand it)

## Optional Enhancements

When advanced analysis tools are available in your environment, consider using them for:
- Systematic analysis of complex, interconnected requirements
- Framework-specific best practices and pattern lookup
- Existing codebase semantic analysis and symbol navigation
- UI/UX pattern recommendations

## Post-Completion Actions

After each phase, suggest next actions with AskUserQuestion:

**After init:**
```
question: "Requirements document generated. What's next?"
options:
  - "Generate design document too" → design phase
  - "Review and revise" → revision dialogue
  - "Done for now" → end
```

**After full:**
```
question: "All three spec documents are complete."
options:
  - "Create a GitHub Issue" → invoke spec-to-issue skill
  - "Review and revise" → revision dialogue
  - "Done for now" → end
```

## Usage Examples

```
# Requirements from conversation
"Turn this into a requirements document"

# New project requirements
"Create requirements for a todo app"

# Design document
"Create design document for todo-app"

# Task list
"Generate task list for todo-app"

# Full specification
"Create full spec for an e-commerce platform"

# Japanese
「TODOアプリの要件定義を作って」
「ECサイトの仕様を全部作って」
```

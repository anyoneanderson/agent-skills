# SKILL.md Style Guide

Conventions for authoring SKILL.md files in this repository. All skills must follow these rules to maintain consistency.

## Language Rules

### SKILL.md Body: English-First

The body of every SKILL.md **must be written in English**. This includes:

- Section headers (`## Execution Flow`, not `## 実行フロー`)
- Check/step descriptions
- Detection patterns and instructions
- Code comments and pseudocode

### Frontmatter

```yaml
---
name: skill-name
description: |
  English description of the skill.

  English triggers: "trigger phrase 1", "trigger phrase 2"
  日本語トリガー: 「トリガー1」「トリガー2」
license: MIT
---
```

- **description**: Written in English
- **Trigger phrases**: Bilingual — include both English and Japanese triggers

### Language Rules Section (Required)

Every SKILL.md must include a `## Language Rules` section immediately after the title. This section defines how the skill handles bilingual output:

```markdown
## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/*.ja.md`
3. English input → English output, use `references/*.md`
4. Explicit override takes priority (e.g., "in English", "日本語で")
```

### AskUserQuestion Content

All AskUserQuestion text must be **bilingual** — English first, Japanese second, separated by ` / `:

```
question: "What's next?" / "次のアクションは？"
options:
  - label: "Create issue" / "Issue登録する"
    description: "Register as GitHub Issue" / "GitHub Issueとして登録"
```

### Console Output and Report Templates

- Write templates in **English** in SKILL.md
- The Language Rules section handles Japanese output at runtime
- Example: `"spec-inspect complete"` in SKILL.md → runtime produces `"spec-inspect 完了"` for Japanese users

### Reference Files

Follow the established bilingual file pattern:

- `references/*.md` — English version (primary)
- `references/*.ja.md` — Japanese version

## Structure Conventions

### Title Format

```markdown
# skill-name — Short Description
```

Use the skill's kebab-case name, an em dash, and a concise English description.

### Section Order

1. Frontmatter (`---`)
2. Title (`# skill-name — Description`)
3. Brief introduction (1-2 sentences)
4. `## Language Rules`
5. Core sections (`## Execution Flow`, `## Options`, etc.)
6. `## Error Handling`
7. `## Usage Examples` (optional)

### Section Headers

All ATX-style document headers in SKILL.md must be in English. ATX-style headings shown inside fenced code examples are illustrative content and are exempt from this rule. Common headers:

| Header | Usage |
|--------|-------|
| `## Language Rules` | Bilingual behavior definition |
| `## Execution Flow` | Step-by-step instructions |
| `## Options` | CLI flags and parameters |
| `## Error Handling` | Error scenarios and responses |
| `## Usage Examples` | Invocation examples |
| `## Post-Completion Actions` | Next-step suggestions |

## Pre-Submit Checklist

Before submitting a new or updated SKILL.md, verify:

- [ ] Frontmatter `name` matches directory name
- [ ] Body is written in English
- [ ] `## Language Rules` section is present
- [ ] All document section headers outside fenced code examples are in English
- [ ] AskUserQuestion content is bilingual (`"English" / "日本語"`)
- [ ] Reference files follow `*.md` / `*.ja.md` pattern
- [ ] Total line count is under 500
- [ ] `bash scripts/check-skill-line-budget.sh` passes from the repository root
- [ ] `bash skills/agent-delegate/references/scripts/tests/check_skill_quality.sh skills/*/SKILL.md` passes from the repository root
- [ ] Changes to the quality checker pass `bash skills/agent-delegate/references/scripts/tests/check_skill_quality_contract.sh`
- [ ] Skills selected for size reduction are at most 450 lines and `bash scripts/tests/check-skill-reference-split-contract.sh` passes
- [ ] No hardcoded MCP tool names (e.g., `mcp__serena__`, `Context7`)
- [ ] All referenced files exist

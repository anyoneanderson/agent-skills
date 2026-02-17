# Contributing to agent-skills

## Repository Structure

```
agent-skills/
├── skills/
│   ├── skill-name/
│   │   ├── SKILL.md          # Skill definition (required)
│   │   └── references/       # Supporting documents (optional)
│   │       ├── guide.md       # English version
│   │       └── guide.ja.md   # Japanese version
│   └── ...
├── LICENSE
├── README.md
└── AGENTS.md
```

## Adding a New Skill

1. Create a directory under `skills/` with your skill name (kebab-case)
2. Add a `SKILL.md` with the required frontmatter
3. Add any reference files under `references/`
4. Update the skills table in `README.md` and `README.ja.md`

## SKILL.md Format

Every skill must have a `SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name          # Must match directory name
description: |
  Brief description of what the skill does.
  Include trigger phrases for discoverability.
license: MIT
---
```

The body of `SKILL.md` contains the full instructions the agent follows when the skill is invoked.

### Guidelines

- **name**: Must match the directory name exactly
- **description**: Keep under 1024 characters. Include trigger phrases in all supported languages for discoverability
- **license**: Use `MIT` unless you have a specific reason not to

## Bilingual Support

This repository follows a bilingual (English/Japanese) pattern:

- `*.md` — English version (primary)
- `*.ja.md` — Japanese version

**SKILL.md body must be written in English.** Use a Language Rules section to define auto-detection and reference file selection for Japanese support.

Skills should auto-detect the user's language and reference the appropriate files.

## Code Style

- Write clear, concise instructions
- Avoid hardcoding tool names or MCP server references — use generic descriptions instead
- Keep SKILL.md under 500 lines
- Use AskUserQuestion for interactive decisions, not free-form text prompts

For detailed SKILL.md authoring conventions, see [docs/skill-style-guide.md](docs/skill-style-guide.md).

## Testing

Before submitting, verify:

1. `SKILL.md` frontmatter `name` matches directory name
2. All referenced files exist
3. No hardcoded MCP tool names (e.g., `mcp__serena__`, `Context7`)
4. SKILL.md is under 500 lines

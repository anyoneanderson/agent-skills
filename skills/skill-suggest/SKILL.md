---
name: skill-suggest
description: |
  Auto-detect project tech stack and suggest optimal skills from skills.sh registry.

  Analyzes manifest files (package.json, Cargo.toml, go.mod, etc.), searches the skills.sh
  API, scores results by official status and install count, and installs selected skills
  with agent-targeted installation to prevent unwanted directory creation.

  English triggers: "Suggest skills", "Find best practice skills", "What skills should I install"
  日本語トリガー: 「スキルを提案」「ベストプラクティススキルを検索」「おすすめスキルを教えて」
license: MIT
---

# skill-suggest — Auto-Suggest Best Practice Skills

Analyze the project tech stack and suggest optimal skills from the skills.sh registry.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/tech-detection.ja.md`
3. English input → English output, use `references/tech-detection.md`
4. Explicit override takes priority (e.g., "in English", "日本語で")

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show suggestion report only, skip installation |

## Execution Flow

### Step 1: Detect Tech Stack

#### 1a. Check for monorepo

First, check if the repository is a monorepo by looking for these indicators at the root:

| Indicator | Monorepo Tool |
|---|---|
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `pnpm-workspace.yaml` | pnpm workspaces |
| `lerna.json` | Lerna |
| `package.json` with `"workspaces"` field | npm/yarn workspaces |

#### 1b. Collect manifest files

**If monorepo detected**: Find all workspace directories and scan each for manifest files. Use the workspace tool's config to locate packages:

- **Turborepo / npm workspaces / yarn workspaces**: Read `workspaces` from root `package.json` (glob patterns like `apps/*`, `packages/*`)
- **pnpm workspaces**: Read `packages` from `pnpm-workspace.yaml`
- **Nx**: Read `projects` from `nx.json` or scan directories listed in `workspace.json`
- **Lerna**: Read `packages` from `lerna.json`

For each workspace directory, check for the manifest files listed below. Also check the repository root for shared configs (Dockerfile, `*.tf`, `tailwind.config.*`).

**If not a monorepo**: Scan the repository root only.

**Manifest files to check:**

```
package.json, Cargo.toml, go.mod, requirements.txt, pyproject.toml,
Pipfile, Gemfile, pom.xml, build.gradle*, composer.json,
Dockerfile, docker-compose.yml, docker-compose.yaml,
*.tf, tsconfig.json, tailwind.config.*, .eslintrc*, components.json
```

#### 1c. Extract dependencies

**For each detected manifest**, read it and extract dependencies:

- `package.json` → parse `dependencies` and `devDependencies` keys
- `Cargo.toml` → parse `[dependencies]` section
- `go.mod` → parse `require` block
- `requirements.txt` → each line is a package name
- `pyproject.toml` → parse `[project.dependencies]` or `[tool.poetry.dependencies]`
- `Dockerfile` → extract FROM image name (language hint only)

#### 1d. Classify and deduplicate

**Map packages to technologies** using `references/tech-detection.md`. Classify each into:

- **language** (e.g., TypeScript, Python)
- **framework** (e.g., Next.js, Django)
- **library** (e.g., Prisma, Tailwind CSS, shadcn/ui)
- **infra** (e.g., Docker, Terraform)

If the same technology is found in multiple workspaces, deduplicate (list it once). For the report, note the source workspace if monorepo (e.g., "Next.js 15 (apps/web)").

#### 1e. Generate search queries

Per the rules in `references/tech-detection.md`:

- Frameworks → `"<name> best practices"`
- Major libraries → `"<name>"` (short query)
- Infrastructure → `"<name> best practices"`
- Languages → only if no framework detected for that language

If the total number of queries exceeds 10, prioritize: frameworks > libraries > infra.

### Step 2: Check Installed Skills

Detect already-installed skills to avoid duplicate suggestions.

**Scan these locations:**

1. List directory names under `.agents/skills/` (if exists)
2. List directory names under `.claude/skills/` (if exists)
3. Read `skills-lock.json` (if exists) — format is a JSON object with `skills` key:
   ```json
   { "version": 1, "skills": { "<skillId>": { "source": "<owner/repo>", ... }, ... } }
   ```
   Extract each key as `skillId` and its `.source` value.

**Build an installed set** of `skillId` values (directory names). If `skills-lock.json` exists, also keep `source + skillId` pairs for exact matching.

### Step 3: Search skills.sh API

For each search query from Step 1, make an HTTP request:

```
GET https://skills.sh/api/search?q={query}&limit=6
```

**Response format:**
```json
{
  "skills": [
    { "id": "owner/repo/skill-name", "skillId": "skill-name", "name": "skill-name", "installs": 12345, "source": "owner/repo" }
  ]
}
```

Collect all results from all queries into a combined list.

**Error handling:**
- If a single query fails (non-200 response), log a warning and skip that query. Continue with remaining queries.
- If ALL queries fail, stop and report: "Failed to reach skills.sh API." / "skills.sh API に接続できませんでした。"

### Step 4: Score, Rank, and Filter

**4a. Remove duplicates**: If the same `skillId` appears from multiple queries, keep the entry with the highest `installs`. If the same purpose skill exists from multiple sources, keep the one with the highest `installs`.

**4b. Assign tiers** based on install count only:

| Condition | Tier |
|---|---|
| installs >= 10,000 | Tier 1 (high adoption) |
| installs >= 1,000 | Tier 2 (moderate adoption) |
| installs >= 100 | Tier 3 (emerging) |
| installs < 100 | Exclude (do not suggest) |

**4c. Exclude installed**: Cross-reference with Step 2 installed set. Mark matching skills as "already installed" instead of suggesting them.

**4d. Set default selection**: Only Tier 1 skills (10K+ installs) are "default selected". Tier 2 and Tier 3 are opt-in (user must explicitly choose them). This is a supply-chain safety measure — high install count serves as a community-verified trust signal.

### Step 5: Present Report

Display the results in the user's language (per Language Rules).

**Report format:**

```markdown
## Detected Tech Stack / 検出された技術スタック

| Category | Technologies |
|---|---|
| Framework | Next.js 15, React 19 |
| Library | Prisma 6, Tailwind CSS, shadcn/ui |
| Infra | Docker |

## Recommended Skills / おすすめスキル

### Tier 1 (10K+ installs, default selected / デフォルト選択)

| # | Skill | Installs | Reason |
|---|---|---|---|
| 1 | `vercel-labs/agent-skills` → `vercel-react-best-practices` | 253K | Uses React 19 |
| 2 | `shadcn/ui` → `shadcn` | 45.8K | Uses shadcn/ui |

### Tier 2 (1K+ installs, opt-in / 選択式)

| # | Skill | Installs | Reason |
|---|---|---|---|
| 3 | `sickn33/antigravity-awesome-skills` → `prisma-expert` | 2.9K | Uses Prisma 6 |

### Tier 3 (opt-in / 選択式)
...

(Already installed / インストール済み: typescript-best-practices, docker-best-practices)
```

Format `installs` with K/M suffixes (e.g., 253366 → 253K, 1200 → 1.2K).

**If `--dry-run`**: Display the report and stop. Do not ask about installation.

**Otherwise**, ask the user:

```
AskUserQuestion:
  question: "How would you like to proceed?" / "どうしますか？"
  options:
    - "Install Tier 1 only (recommended)" / "Tier 1 のみインストール（推奨）"
    - "Install all suggested skills" / "提案されたスキルを全てインストール"
    - "Skip installation" / "インストールをスキップ"
```

If the user wants to select specific skills, they can specify by number (e.g., "1,3,5") in a follow-up message. Accept comma-separated numbers matching the `#` column.

### Step 6: Install Selected Skills

**6a. Detect current agent** to pass `--agent` option:

| Detection Method | Agent Name |
|---|---|
| `CLAUDE_CODE` env var set, or parent process contains `claude` | `claude-code` |
| Parent process contains `codex` | `codex` |
| Parent process contains `cursor` | `cursor` |
| Cannot determine | Omit `--agent` flag (install to all agents) |

**6b. Install each selected skill:**

```bash
npx skills add <source> --skill <skillId> -a <detected-agent> -y
```

If agent detection failed, fall back to:

```bash
npx skills add <source> --skill <skillId> -y
```

Execute installations sequentially. If one skill fails, log the error and continue with the remaining skills.

**6c. Display results:**

```markdown
## Install Results / インストール結果

| Skill | Status |
|---|---|
| vercel-react-best-practices | ✓ Installed / インストール完了 |
| shadcn | ✓ Installed / インストール完了 |
| prisma-expert | ✗ Failed / 失敗 (error detail) |
```

## Error Handling

| Situation | Response |
|---|---|
| No manifest files found | "No manifest files detected." / "マニフェストファイルが見つかりません。" → stop |
| All API queries fail | "Failed to reach skills.sh API." / "skills.sh API に接続できませんでした。" → stop |
| Some API queries fail | Warning per failed query, continue with successful results |
| No skills found after filtering | "No new skills to suggest." / "提案できる新しいスキルはありません。" → stop |
| npx/npm not available | "Node.js/npm is required for installation." / "インストールにはNode.js/npmが必要です。" → stop |
| Individual skill install fails | Log error, continue with remaining skills |

## Post-Completion Actions

After installation completes:

```
AskUserQuestion:
  question: "What's next?" / "次のアクションは？"
  options:
    - "Done" / "完了"
    - "Run again to check for more" / "もう一度実行して追加を確認"
```

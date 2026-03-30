# Tech Detection Rules

Mapping rules for detecting tech stacks from manifest files.

## Monorepo Detection

Check the repository root for these indicators:

| Indicator | Monorepo Tool | Workspace Config |
|---|---|---|
| `turbo.json` | Turborepo | `workspaces` in root `package.json` |
| `nx.json` | Nx | `projects` in `nx.json`, `workspace.json`, or discovered `project.json` files |
| `pnpm-workspace.yaml` | pnpm workspaces | `packages` in `pnpm-workspace.yaml` |
| `lerna.json` | Lerna | `packages` in `lerna.json` |
| `package.json` with `"workspaces"` field | npm/yarn workspaces | `workspaces` in `package.json` |

If monorepo detected, resolve workspace directories from the config (expand globs like `apps/*`, `packages/*`) and scan each for manifest files. Always scan the repository root manifests too, since some monorepos keep shared or primary dependencies there. Also scan the repository root for shared configs (Dockerfile, `*.tf`, etc.).

For Nx, do not assume `nx.json` always lists every project. If `projects` is missing or incomplete, fall back to `workspace.json`, then recursively find `project.json` files and treat each parent directory as a workspace root.

If not a monorepo, scan the repository root only.

## Manifest Files to Detect

| File | Ecosystem |
|------|-----------|
| `package.json` | Node.js |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `requirements.txt` | Python |
| `pyproject.toml` | Python |
| `Pipfile` | Python |
| `Gemfile` | Ruby |
| `pom.xml` | Java |
| `build.gradle` / `build.gradle.kts` | Java / Kotlin |
| `composer.json` | PHP |
| `Dockerfile` / `docker-compose.yml` / `docker-compose.yaml` | Docker (infra) |
| `*.tf` | Terraform (infra) |

### Auxiliary Detection Files

These files supplement the primary manifest detection:

| File | Indicates |
|------|-----------|
| `tsconfig.json` | TypeScript (language) |
| `tailwind.config.*` | Tailwind CSS (library) |
| `.eslintrc*` | ESLint (devtool, not searched) |
| `components.json` | shadcn/ui (when combined with `@radix-ui/*` in package.json) |

## Package-to-Technology Mapping

### Node.js (package.json)

Parse `dependencies` and `devDependencies` keys.

| Package Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `next` | Next.js | framework | `nextjs best practices` |
| `react` | React | framework | `react best practices` |
| `vue` | Vue.js | framework | `vue best practices` |
| `nuxt` | Nuxt | framework | `nuxt best practices` |
| `svelte`, `@sveltejs/*` | Svelte | framework | `svelte best practices` |
| `@angular/*` | Angular | framework | `angular best practices` |
| `express` | Express | framework | `express best practices` |
| `fastify` | Fastify | framework | `fastify best practices` |
| `nest`, `@nestjs/*` | NestJS | framework | `nestjs best practices` |
| `hono` | Hono | framework | `hono best practices` |
| `prisma`, `@prisma/client` | Prisma | library | `prisma` |
| `drizzle-orm` | Drizzle | library | `drizzle` |
| `tailwindcss` | Tailwind CSS | library | `tailwind` |
| `@radix-ui/*` + `components.json` exists | shadcn/ui | library | `shadcn` |
| `supabase`, `@supabase/*` | Supabase | library | `supabase` |
| `stripe` | Stripe | library | `stripe` |

### Python (requirements.txt / pyproject.toml / Pipfile)

| Package Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `django` | Django | framework | `django best practices` |
| `fastapi` | FastAPI | framework | `fastapi best practices` |
| `flask` | Flask | framework | `flask best practices` |

### Go (go.mod)

Parse `require` block.

| Module Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `github.com/gin-gonic/gin` | Gin | framework | `gin best practices` |
| `github.com/gofiber/fiber` | Fiber | framework | `fiber best practices` |
| `github.com/labstack/echo` | Echo | framework | `echo best practices` |

### Rust (Cargo.toml)

Parse `[dependencies]` section.

| Crate Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `actix-web` | Actix Web | framework | `actix best practices` |
| `axum` | Axum | framework | `axum best practices` |
| `rocket` | Rocket | framework | `rocket best practices` |

### Ruby (Gemfile)

| Gem Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `rails` | Ruby on Rails | framework | `rails best practices` |
| `sinatra` | Sinatra | framework | `sinatra best practices` |

### Java / Kotlin (pom.xml / build.gradle)

| Dependency Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `spring-boot` | Spring Boot | framework | `spring boot best practices` |

### PHP (composer.json)

Parse `require` keys.

| Package Pattern | Technology | Category | Search Query |
|---|---|---|---|
| `laravel/framework` | Laravel | framework | `laravel best practices` |
| `symfony/*` | Symfony | framework | `symfony best practices` |

### Infrastructure (file existence)

| File | Technology | Category | Search Query |
|---|---|---|---|
| `Dockerfile` | Docker | infra | `docker best practices` |
| `*.tf` | Terraform | infra | `terraform best practices` |

## Search Query Generation Rules

1. **Frameworks**: Search with `"<name> best practices"` pattern
2. **Major libraries** (Prisma, shadcn, Drizzle, Supabase, Stripe): Search with `"<name>"` only
3. **Infrastructure**: Search with `"<name> best practices"` pattern
4. **Languages**: Do NOT search by default. Only search `"<language> best practices"` if no framework is detected for that language
5. **Maximum API calls**: 10 (prioritize frameworks > libraries > infra if exceeding limit)

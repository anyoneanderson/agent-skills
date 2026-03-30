# 技術検出ルール

マニフェストファイルから技術スタックを検出するためのマッピングルール。

## モノレポ検出

リポジトリルートで以下の指標をチェックする：

| 指標 | モノレポツール | ワークスペース設定 |
|---|---|---|
| `turbo.json` | Turborepo | ルート `package.json` の `workspaces` |
| `nx.json` | Nx | `nx.json` の `projects` または `workspace.json` |
| `pnpm-workspace.yaml` | pnpm workspaces | `pnpm-workspace.yaml` の `packages` |
| `lerna.json` | Lerna | `lerna.json` の `packages` |
| `package.json` に `"workspaces"` フィールドあり | npm/yarn workspaces | `package.json` の `workspaces` |

モノレポが検出された場合、設定からワークスペースディレクトリを解決し（`apps/*`, `packages/*` 等のグロブを展開）、各ディレクトリのマニフェストファイルを走査する。リポジトリルートの共有設定（Dockerfile, `*.tf` 等）も走査する。

モノレポでない場合、リポジトリルートのみ走査する。

## 検出対象のマニフェストファイル

| ファイル | エコシステム |
|---------|-------------|
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
| `Dockerfile` / `docker-compose.yml` / `docker-compose.yaml` | Docker（インフラ） |
| `*.tf` | Terraform（インフラ） |

### 補助検出ファイル

主要マニフェストの検出を補完するファイル：

| ファイル | 示す技術 |
|---------|---------|
| `tsconfig.json` | TypeScript（言語） |
| `tailwind.config.*` | Tailwind CSS（ライブラリ） |
| `.eslintrc*` | ESLint（開発ツール、検索対象外） |
| `components.json` | shadcn/ui（package.json に `@radix-ui/*` がある場合のみ） |

## パッケージ→技術マッピング

### Node.js (package.json)

`dependencies` と `devDependencies` のキーを解析する。

| パッケージパターン | 技術名 | カテゴリ | 検索クエリ |
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
| `@radix-ui/*` + `components.json` あり | shadcn/ui | library | `shadcn` |
| `supabase`, `@supabase/*` | Supabase | library | `supabase` |
| `stripe` | Stripe | library | `stripe` |

### Python (requirements.txt / pyproject.toml / Pipfile)

| パッケージパターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `django` | Django | framework | `django best practices` |
| `fastapi` | FastAPI | framework | `fastapi best practices` |
| `flask` | Flask | framework | `flask best practices` |

### Go (go.mod)

`require` ブロックを解析する。

| モジュールパターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `github.com/gin-gonic/gin` | Gin | framework | `gin best practices` |
| `github.com/gofiber/fiber` | Fiber | framework | `fiber best practices` |
| `github.com/labstack/echo` | Echo | framework | `echo best practices` |

### Rust (Cargo.toml)

`[dependencies]` セクションを解析する。

| クレートパターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `actix-web` | Actix Web | framework | `actix best practices` |
| `axum` | Axum | framework | `axum best practices` |
| `rocket` | Rocket | framework | `rocket best practices` |

### Ruby (Gemfile)

| Gem パターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `rails` | Ruby on Rails | framework | `rails best practices` |
| `sinatra` | Sinatra | framework | `sinatra best practices` |

### Java / Kotlin (pom.xml / build.gradle)

| 依存パターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `spring-boot` | Spring Boot | framework | `spring boot best practices` |

### PHP (composer.json)

`require` キーを解析する。

| パッケージパターン | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `laravel/framework` | Laravel | framework | `laravel best practices` |
| `symfony/*` | Symfony | framework | `symfony best practices` |

### インフラ（ファイル存在チェック）

| ファイル | 技術名 | カテゴリ | 検索クエリ |
|---|---|---|---|
| `Dockerfile` | Docker | infra | `docker best practices` |
| `*.tf` | Terraform | infra | `terraform best practices` |

## 検索クエリ生成ルール

1. **フレームワーク**: `"<名前> best practices"` パターンで検索
2. **主要ライブラリ**（Prisma, shadcn, Drizzle, Supabase, Stripe）: `"<名前>"` のみで検索
3. **インフラ**: `"<名前> best practices"` パターンで検索
4. **言語**: デフォルトでは検索しない。その言語のフレームワークが未検出の場合のみ `"<言語> best practices"` で検索
5. **最大 API 呼び出し回数**: 10 回（超過時の優先順位: フレームワーク > ライブラリ > インフラ）

# 公式スキルソース一覧

公式スキルソースは、該当技術のオリジナル開発者によって管理されているものです。これらのソースからのスキルは、インストール数に関わらず自動的に Tier 1 に分類されます。

## 公式ソース

| ソース（GitHub オーナー） | 組織 | 対応技術 |
|---|---|---|
| `vercel-labs` | Vercel | React, Next.js, Vercel プラットフォーム |
| `shadcn` | shadcn | shadcn/ui コンポーネントライブラリ |
| `prisma` | Prisma | Prisma ORM |
| `stripe` | Stripe | Stripe 決済 |
| `cloudflare` | Cloudflare | Cloudflare Workers, Pages |
| `google-labs-code` | Google Labs | 各種 Google 技術 |
| `callstackincubator` | Callstack | React Native |
| `supabase` | Supabase | Supabase プラットフォーム |

## マッチングルール

skills.sh API レスポンスの `source` フィールドからオーナー部分を照合する:

```
source: "vercel-labs/agent-skills"  →  owner = "vercel-labs"  →  公式
source: "sickn33/awesome-skills"    →  owner = "sickn33"      →  非公式
```

`source` を `/` で分割し、最初のセグメントをオーナーとして抽出する。

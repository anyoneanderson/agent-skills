# Known Official Skill Sources

Official skill sources are maintained by the original developers of the technology. Skills from these sources are automatically assigned Tier 1 regardless of install count.

## Official Sources

| Source (GitHub owner) | Organization | Technologies |
|---|---|---|
| `vercel-labs` | Vercel | React, Next.js, Vercel platform |
| `shadcn` | shadcn | shadcn/ui component library |
| `prisma` | Prisma | Prisma ORM |
| `stripe` | Stripe | Stripe payments |
| `cloudflare` | Cloudflare | Cloudflare Workers, Pages |
| `google-labs-code` | Google Labs | Various Google technologies |
| `callstackincubator` | Callstack | React Native |
| `supabase` | Supabase | Supabase platform |

## Matching Rule

Match the `source` field from the skills.sh API response against the owner portion:

```
source: "vercel-labs/agent-skills"  →  owner = "vercel-labs"  →  OFFICIAL
source: "sickn33/awesome-skills"    →  owner = "sickn33"      →  NOT official
```

Extract the owner by splitting `source` on `/` and taking the first segment.

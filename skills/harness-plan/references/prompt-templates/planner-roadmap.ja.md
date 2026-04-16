<!--
  Planner `roadmap` phase プロンプトテンプレート（日本語版）
  harness-plan Orchestrator 置換変数:
    {{EPIC_NAME}}            — epic の slug
  目的: product-spec.md を読んで roadmap.md を書く。Fresh Planner で
  interview session の記憶は持たない。
-->

You are the "planner" agent（`.claude/agents/planner.md` / `.codex/agents/planner.toml` 参照）。
load して developer_instructions に従ってください。

# Phase: roadmap

ゴール: 既に書かれた product-spec.md から `.harness/{{EPIC_NAME}}/roadmap.md` を生成。

まず Boot Sequence（git log, progress.md tail, _state.json）。

## 入力

`.harness/{{EPIC_NAME}}/product-spec.md` を読む。これが意図の**唯一の source** — interview session には居なかった前提。

## タスク

Epic を sprint に分割。各 sprint に `bundling: split | bundled` を付与:

- **split**（1 feature = 1 sprint = 1 PR）: デフォルト
- **bundled**（N feature = 1 sprint = 1 PR）: feature 間で schema / 認証 / UI コンポーネントが密結合、分けて出荷すると同じ接続を二度書くことになる場合のみ

`.harness/{{EPIC_NAME}}/roadmap.md` を書く:

```markdown
---
epic: {{EPIC_NAME}}
generated_at: <ISO-8601-UTC>
approved: false
---

# Roadmap: {{EPIC_NAME}}

## Sprints

| # | Feature | Bundling | Bundled-with | Goal |
|---|---|---|---|---|
| 1 | login | split | — | email+password 認証 |
| 2 | lockout | split | — | ブルートフォース対策 |
| 3 | mfa | bundled | email-verification | MFA + メール確認 |
| 4 | email-verification | bundled | mfa | |

## Bundling rationale

- sprint-3 & 4: SMTP pipeline + 認証 token middleware を共有、分割すると
  token schema migration を二度書くことになる

## Ordering rationale

- login は lockout より先（lockout はアカウント entity の存在前提）
- MFA は login+lockout の後（それらの primitive を基盤にする）
```

書き終えたら終了。User 承認は out-of-band で行う — このフェーズでは AskUserQuestion は使わない（interactive ではない）。

## 禁止事項

- コード書かない
- contract ファイルを書かない（別 Planner invocation で担当）
- 再 interview しない — product-spec.md が曖昧なら "Bundling rationale" に書いて最も保守的な解釈を採用

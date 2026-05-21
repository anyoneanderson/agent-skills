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

## Foundation-sprint チェック

`_state.json.foundation_sprint_needed` を読む。`true` なら epic は
greenfield で、`/harness-plan` Step 3.5 が既に
`.harness/{{EPIC_NAME}}/foundation-readiness.md` を書いている。

この場合、roadmap の先頭に **Sprint 0** を `type: foundation` で挿入
しなければならない。`deliverables` は foundation-readiness.md の
missing probe から導出する。スキーマ全体は
[../foundation-sprint-guide.ja.md](../foundation-sprint-guide.ja.md)
参照。併せて:

- 明示的 dependency を持たない全 feature sprint に暗黙的に
  `dependencies: [0]` を追加（この書き換えは必須。harness-loop が
  Sprint 0 attestation 前に feature sprint を起動しないようにするため）
- Sprint 0 は 6 sprint cap の対象外
- Sprint 0 は bundle できない — 常に独立 PR

`foundation_sprint_needed` が `false` または不在なら、従来どおり
Sprint 0 無しで進める。

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

| # | Feature | Bundling | Bundled-with | Goal | Backend |
|---|---|---|---|---|---|
| 1 | login | split | — | email+password 認証 | claude |
| 2 | lockout | split | — | ブルートフォース対策 | codex_cli |
| 3 | mfa | bundled | email-verification | MFA + メール確認 | codex_cli |
| 4 | email-verification | bundled | mfa | | codex_cli |

## Bundling rationale

- sprint-3 & 4: SMTP pipeline + 認証 token middleware を共有、分割すると
  token schema migration を二度書くことになる

## Ordering rationale

- login は lockout より先（lockout はアカウント entity の存在前提）
- MFA は login+lockout の後（それらの primitive を基盤にする）

## Backend rationale

- sprint-1（login）: UI / form / 認証画面 → primary `claude`（rubric: UI-heavy）
- sprint-2（lockout）: backend rate-limit logic → primary `codex_cli`（rubric: backend logic）
- sprint-3 / 4（bundle）: backend / schema / auth heavy → primary `codex_cli`
  を bundle peer 全体で共有（primary peer のみ rubric 適用、peer は継承）

上記 Backend 選択は YAML frontmatter の `sprints[n].generator_backend`
にも書込む（harness-loop の canonical source）。本 table は人間向けの要約。
```

## sprint 毎の Backend 推奨判定

各 sprint について Generator backend を確定する。詳細は
[../roadmap-guide.ja.md](../roadmap-guide.ja.md) §Backend 推奨判定 参照。要約:

1. **適性 rubric を適用**:
   - UI-heavy（frontend / component / CSS / design system）→ primary `claude`
   - backend logic / API / schema / auth / validation → primary `codex_cli`
     （design 重視 backend sprint なら secondary として `claude` を
     AskUserQuestion options に追加 — primary は `codex_cli` 固定）
   - infra / CI/CD / docker / shell / cloud deploy → primary `codex_cli`

   primary は **単一値**（`claude` または `codex_cli`）— `codex_cli (or claude)`
   のような複数値は禁止。`codex_cmux` は rubric primary には **含めない**:
   AskUserQuestion の選択肢として常に user に提示する（hybrid: UI + backend
   同等重視 や cross-check 用途で user が選ぶ）。

2. **interactive モード**（`_state.json.mode == "interactive"`）: 各
   sprint について `AskUserQuestion` を発行:
   - option 1: `<recommended> (Recommended) — <rubric 根拠>`
   - option 2: `<_config.yml.generator_backend>`（harness-init で選択した
     epic default、recommended と同じなら省略）
   - option 3: 残り enum 値（重複排除）

   bundle peer は primary peer の選択を継承 — **bundle 単位で 1 質問**、
   peer 毎には聞かない。sprint 数 > 4 なら複数 round に分割
   （AskUserQuestion は 1 round 4 質問まで）。

3. **non-interactive モード**（`continuous` / `autonomous-ralph` /
   `scheduled`）: `AskUserQuestion` は Pre-flight Gates により禁止。
   rubric primary を auto-confirm して `roadmap.md` に直接書込む。

4. **legacy bypass**: `_config.yml.sprint_level_generator_override == false`
   の場合、**rubric 判定と AskUserQuestion を完全 skip**。全 sprint で
   `generator_backend: null` を書込み、`harness-loop` 実行時に
   `_config.yml.generator_backend` へ fallback させる（後方互換維持）。

確定値（または legacy 時の `null`）を `roadmap.md` の YAML frontmatter
`sprints[n].generator_backend` に書き、根拠を `generator_backend_reason`
（free-form: rubric 推奨採用 / epic default 採用 / 手動 override / legacy
bypass）に記録する。

書き終えたら終了。Roadmap 全体の承認は out-of-band で行う — 本 phase で
実行する AskUserQuestion は per-sprint backend 確認のみ（interactive モード時）。

## 禁止事項

- コード書かない
- contract ファイルを書かない（別 Planner invocation で担当）
- 再 interview しない — product-spec.md が曖昧なら "Bundling rationale" に書いて最も保守的な解釈を採用

---
name: generator-foundation-prompt
description: |
  type: foundation sprint 用の Generator プロンプト最小テンプレート。
  harness-loop Orchestrator は宣言済み placeholder のみ置換すること。
  それ以上の内容追加は「Orchestrator 非設計」原則違反
  （harness-loop/README.ja.md §「Orchestrator は設計しない」参照）。
  Placeholder（4 つ全て必須）:
    \{\{EPIC_NAME\}\}        — epic slug（例: phase1-foundation）
    \{\{SPRINT_NUMBER\}\}     — foundation-sprint では常に 0
    \{\{SPRINT_FEATURE\}\}    — feature slug（例: dev-environment-foundation）
    \{\{ITERATION\}\}         — iteration 番号（初回 1 / Fix & retry で 2+）
---

<!--
  Generator Foundation-phase prompt テンプレート（日本語版）。
  置換後でも ~50 行に収める設計。これが「minimal form」で Orchestrator
  非設計を体現する。schema 断片・依存ライブラリ列挙・具体 CLI 手順を
  ここに書きたくなっても止めよ — それらは contract.md の
  「Generator 作業範囲」「Setup Prerequisites」か、Generator の判断事項。
-->

あなたは "generator" エージェントです。次のファイルからロール契約を load:

- `.codex/agents/generator.toml`（codex_cli / codex_cmux backend 用）
- `.claude/agents/generator.md`（claude backend 用）

その `developer_instructions` と Boot Sequence に従ってください。

# Phase: foundation-setup (iteration {{ITERATION}})

本 sprint は **type: foundation**。harness-loop は foundation sprint では:

- 閾値交渉をスキップ（contract は `rubric` でなく `deliverables` を持つ）
- Generator dispatch は 1 回のみ（iteration loop 無し。operator の "Fix & retry"
  attestation でのみ再入、最大 3 回）
- 完了判定は `.harness/scripts/foundation-readiness.sh --check <key>` probe
  と operator の AskUserQuestion attestation

# Sprint

- **Epic**: `{{EPIC_NAME}}`
- **Sprint**: `sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}`（type: foundation）
- **Iteration**: `{{ITERATION}}`

# Task

唯一の ground truth として contract を読む:

    .harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md

Contract が定義する **outcomes**:

- `deliverables` — `foundation-readiness.sh` が probe するチェックリスト
- `Generator 作業範囲` — あなたが作る範囲（人間のみの設定と区別）
- `Setup Prerequisites` — operator が out-of-band で行う外部設定
  （GCP / Anthropic / Slack 等のプロバイダ）
- `generator_mode` — 自律 bootstrap の範囲（`none` / `scaffold` / `optional`）

**どう作るか**はあなたが決める — ファイル内容、パッケージ版、schema 形、
CLI フラグ選択、ディレクトリ配置、migration 名、test パス。contract は
outcome を指定するだけ、artifact はあなたが選ぶ。contract が曖昧に感じたら
readiness probe に通る最小解釈を選ぶ — scope を広げない。

iter > 1 なら、前回の `feedback/verification-{{ITERATION}}-1.md` も読み、
どの deliverable probe が失敗し、どんな evidence が引用されたかを確認すること。

# 出力（exit contract、必須）

本 sprint の `feedback/` ディレクトリに両方書く:

**Atomicity rule（必須）**: 正本の feedback ペアはこの invocation の最後の
アクションとして 1 回だけ書くこと。途中経過の上書き先に使ってはならない。
scratch note は別の場所へ保持する。

### 1. `feedback/generator-{{ITERATION}}.md` — ナラティブ

```markdown
---
role: generator
iter: {{ITERATION}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Summary
<何を作ったか、1-3 文>

## Approach
- <実装上の選択 — パッケージマネージャ、ORM、DB engine 等>

## Concerns / known gaps
- <operator が attest 前に把握すべき項目>

## Evidence pointers
- <ログ / migration ファイル等のパス>

## Next action
<期待される検証結果>
```

### 2. `feedback/generator-{{ITERATION}}-report.json` — 構造化

スキーマは `harness-loop/references/shared-state-protocol.ja.md`
§「deliverable_checks スキーマ（foundation sprint）」参照。最小形:

```json
{
  "status": "done" | "blocked",
  "touchedFiles": ["<相対パス>"],
  "summary": "<1 行サマリ>",
  "blocker": null | "<status=blocked 時の理由>",
  "deliverable_checks": {
    "<deliverable_key>": { "status": "pass" | "fail", "evidence": "<短い文字列>" }
  }
}
```

`deliverable_checks` は `contract.deliverables` の各キーにつき 1 エントリ。
`touchedFiles` は repo root からの相対パス（変更したもの）。

# 境界（tier-a-guard hook で強制）

- 現在チェックアウトされている **feature branch** 上でのみ作業する
  （`harness/<epic>/sprint-<n>-<feature>` 系の branch が切られた状態で
  dispatch される想定）。default branch（main / master / develop 等）が
  現 branch なら作業せず blocker を書いて exit。
- 現 branch への WIP commit のみ。force-push 禁止。
- `docs/coding-rules.md` に従ってコードを書く（命名・テスト方針・lint 等）。
- Tier-A 破壊的コマンドは `.harness/scripts/tier-a-guard.sh` が deny — bypass しない
- `pending_human=true` は stop の合図 — operator が先の Tier-A ヒットや
  attestation 要求をレビュー中。

---

<!--
  本テンプレを編集する人へのリマインダー:

  ここに「どう作るか」を追加（具体 schema 断片、特定 CLI フラグ値、
  docker-compose 環境変数、docs の章番号など）すると目的を台無しにする。
  代わりに contract.md に書くか、Generator の判断に任せよ。

  酸テスト: 完全に異なる Generator 実装（別言語 / 別 FW / 別 DB）でも
  同じ prompt で妥当な foundation が生成できるか？ Yes ならテンプレは
  充分 minimal。No なら設計判断が漏れている。
-->

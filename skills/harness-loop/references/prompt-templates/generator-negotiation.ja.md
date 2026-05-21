<!--
  Generator Negotiation フェーズプロンプトテンプレート（日本語版）
  harness-loop Orchestrator は宣言済み placeholder のみ置換:
    \{\{EPIC_NAME\}\}
    \{\{SPRINT_NUMBER\}\}
    \{\{SPRINT_FEATURE\}\}
    \{\{ROUND\}\}             — 交渉ラウンド 1..3
    \{\{EVALUATOR_FB_PATH\}\} — 直前の evaluator-neg-*.md パス、round 1 なら "(none)"

  Orchestrator 非設計（harness-loop/README.ja.md §エージェント節）:
  閾値の具体提案や counter-propose のヒントを Orchestrator がここに
  書かない。Generator の判断事項。
-->

You are the "generator" agent（`.claude/agents/generator.md` /
`.codex/agents/generator.toml` 参照）。load して developer_instructions に従う。

# Phase: negotiation / round {{ROUND}}

現 sprint: sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}
現 epic: {{EPIC_NAME}}

タスク: この sprint の `contract.md` に対して、あなたが現実的に達成可能な rubric threshold と max_iterations を提案する。Evaluator と最大 3 ラウンド交渉する。

## 読むファイル（Boot Sequence + フェーズ固有）

1. 標準 Boot Sequence: git log / progress.md tail / _state.json
2. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`
3. 直前の Evaluator 応答（あれば）:
   `{{EVALUATOR_FB_PATH}}`

## 出力

2 ファイル書く（Orchestrator の bridge が両方に依存）:

**Atomicity rule（必須）**: 正本の交渉 feedback ペアはこの invocation の
最後のアクションとして 1 回だけ書くこと。途中 draft の上書き先にしては
ならない。scratch note は別の場所に保持する。

### A. `feedback/generator-neg-{{ROUND}}.md` — narrative

```markdown
---
role: generator
round: {{ROUND}}
sprint: {{SPRINT_NUMBER}}
ts: <ISO-8601-UTC>
---

## Decision
<accept | counter | escalate>

## Proposed thresholds
- Functionality: 1.0
- Craft: 0.85
- <axis3>: 0.75
- <axis4>: 0.6

## Proposed max_iterations
10

## Rationale
<軸別・制約別の具体理由>
```

### B. `feedback/generator-neg-{{ROUND}}-report.json` — 構造化

```json
{
  "status": "done",
  "touchedFiles": [],
  "summary": "round {{ROUND}} negotiation response",
  "blocker": null
}
```

Negotiation ラウンドでは `touchedFiles` は空（まだ実装していない）。pre-flight gate に引っかかった時以外は `status: "done"`。

## 戦略ヒント

- Round 1: 正直に達成可能なラインを提案。過約束しない
- Round 2–3: gap を詰める、threshold を緩める代わりに max_iterations を上げる等の交渉
- 達成不可な threshold を round 終了のために受け入れない
- Round 3 で合意できなければ Planner 裁定
- Threshold 提案は `docs/coding-rules.md` の MUST ルールと整合させる。
  MUST をバイパスする必要がある threshold は提案しない。
  `docs/review_rules.md` の Critical findings を無視できる Craft
  threshold も提案しない
- 契約境界を通す integration-level test を最低 1 本含める前提で
  feasibility を考える。`page.route`、`addInitScript`、
  `window.fetch` 上書き、同等の全面 mock に依存する stub-only テストは
  Evaluator の Functionality 根拠として受理されない

## 禁止事項

- このフェーズでコード実装しない（交渉のみ）
- `contract.md` を直接書き換えない（Round 3 後または Planner 裁定で Orchestrator が凍結）
- `shared_state.md`, `_state.json`, `progress.md` を書かない

<!--
  Evaluator Negotiation フェーズプロンプトテンプレート（日本語版）
  harness-loop Orchestrator は宣言済み placeholder のみ置換:
    \{\{EPIC_NAME\}\}
    \{\{SPRINT_NUMBER\}\}
    \{\{SPRINT_FEATURE\}\}
    \{\{ROUND\}\}             — 交渉ラウンド 1..3
    \{\{GENERATOR_FB_PATH\}\} — generator-neg-\{\{ROUND\}\}.md の相対パス。
                            初回で提案が無い場合は "(none)"

  Orchestrator 非設計（harness-loop/README.ja.md §エージェント節）:
  threshold 判断と交渉姿勢は Evaluator の役割。Orchestrator がここへ
  推奨 threshold や定型 counter / escalate 文面を埋め込まない。
-->

You are the "evaluator" agent（`.claude/agents/evaluator.md` 参照）。
load して developer_instructions に従う。

# Phase: negotiation / round {{ROUND}}

現 sprint: sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}
現 epic: {{EPIC_NAME}}

タスク: この sprint の `contract.md` に対する Generator の交渉提案を読み、
role 契約の Negotiation Round Protocol に従って `accept` / `counter` /
`escalate` のいずれかで返答する。

## 読むファイル（Boot Sequence + フェーズ固有）

1. 標準 Boot Sequence: git log / progress.md tail / _state.json
2. `.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md`
3. 現在の Generator 提案:
   `{{GENERATOR_FB_PATH}}`

## 出力

この invocation の最後のアクションとして、正本ファイルを 1 つだけ書く:

### `feedback/evaluator-neg-{{ROUND}}.md` — 交渉応答

```markdown
---
role: evaluator
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
<軸別 / 上限別の具体理由>
```

## 交渉ガイダンス

- feasibility 判断では `.claude/skills/harness-loop/references/review-process.md` と、Boot Sequence で
  読み込んだ tool reference を踏まえる。
- `Functionality` は `1.0` 未満に緩めない。
- Generator 提案が現実的だがまだ甘い場合は `counter` を使う。
- 明確に bad-faith、または Planner 裁定なしでは収束しない場合のみ
  `escalate` を使う。
- 理由は acceptance scenarios、coding rules、review criteria と結びつけて
  具体的に書く。
- stub-only テストは根拠として扱わない。Generator の rationale が
  `page.route`、`addInitScript`、`window.fetch` 上書き、同等の全面
  契約境界 bypass に依存している場合はそれを記録し、そのために
  threshold を緩めない。

## 禁止事項

- コードを書かない、ソースを編集しない。
- `contract.md` を直接変更しない。
- `shared_state.md`, `_state.json`, `metrics.jsonl`, `progress.md` を書かない。

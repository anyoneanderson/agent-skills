<!--
  Planner `contract-draft` phase プロンプトテンプレート（日本語版）
  harness-plan Orchestrator が sprint ごとに 1 インスタンス dispatch する
  （Task tool が並列対応なら並列実行）。

  置換:
    {{EPIC_NAME}}            — epic slug
    {{SPRINT_NUMBER}}         — 整数、1..N
    {{SPRINT_FEATURE}}        — feature slug（kebab-case）
    {{SPRINT_BUNDLING}}       — "split" | "bundled"
    {{SPRINT_BUNDLED_WITH}}   — bundle 相手の feature(s) or ""
    {{SPRINT_GOAL}}           — roadmap 由来の 1 行ゴール
    {{RUBRIC_PRESET}}         — web | api | cli（_config.yml 由来）
-->

You are the "planner" agent（`.claude/agents/planner.md` / `.codex/agents/planner.toml` 参照）。
load して developer_instructions に従う。

# Phase: contract-draft

ゴール: sprint-{{SPRINT_NUMBER}} の `contract.md` 雛形を生成。**fresh Planner** — 他の contract-draft Planner と並列安全。

まず Boot Sequence。

## 読んで良い入力

- `.harness/{{EPIC_NAME}}/product-spec.md` — epic の意図
- `.harness/{{EPIC_NAME}}/roadmap.md` — sprint レイアウトと bundling
- 下記の sprint metadata

他 sprint の contract draft は見えないものとして扱う。

## sprint metadata

- Number: {{SPRINT_NUMBER}}
- Feature: {{SPRINT_FEATURE}}
- Bundling: {{SPRINT_BUNDLING}}
- Bundled with: {{SPRINT_BUNDLED_WITH}}
- Goal: {{SPRINT_GOAL}}
- Rubric preset: {{RUBRIC_PRESET}}

## タスク

`.harness/{{EPIC_NAME}}/sprints/sprint-{{SPRINT_NUMBER}}-{{SPRINT_FEATURE}}/contract.md` を書く:

```yaml
---
sprint: {{SPRINT_NUMBER}}
feature: {{SPRINT_FEATURE}}
bundling: {{SPRINT_BUNDLING}}
bundled_with: [{{SPRINT_BUNDLED_WITH}}]
goal: {{SPRINT_GOAL}}
acceptance_scenarios:
  - id: AS-1
    text: <平易な英語のシナリオ、正常パス>
  - id: AS-2
    text: <失敗 / edge case>
  - id: AS-3
    text: <境界条件>
rubric:
  - axis: Functionality
    weight: high
    threshold: ?       # Negotiation で確定
  - axis: Craft
    weight: std
    threshold: ?
  - axis: <プロジェクトタイプ固有軸 3>
    weight: std
    threshold: ?
  - axis: <プロジェクトタイプ固有軸 4>
    weight: low
    threshold: ?
max_iterations: ?       # Negotiation で確定
status: pending-negotiation
---

# Contract: sprint-{{SPRINT_NUMBER}} — {{SPRINT_FEATURE}}

## Goal
{{SPRINT_GOAL}}

## Acceptance Scenarios
<AS-N ごとに前提条件・手順・期待結果を詳述>

## Notes for Generator & Evaluator
<sprint 固有の慣習: "全日付は UTC"、"schema は Zod" 等>
```

軸選択は `rubric_preset` 別:
- `web`: Functionality / Craft / Design / Originality
- `api`: Functionality / Craft / Consistency / Documentation
- `cli`: Functionality / Craft / Ergonomics / Documentation

## 禁止事項

- `threshold` 値を埋めない（Negotiation で設定）
- `max_iterations` 値を埋めない
- コード書かない
- 他 sprint のファイルを触らない（並列安全）
- `feedback/` / `evidence/` サブディレクトリは作らない（harness-loop が sprint 入場時に作る）

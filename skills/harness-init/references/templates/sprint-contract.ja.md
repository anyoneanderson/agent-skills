<!--
  sprint-contract.md — Planner / Generator / Evaluator 間のスプリント契約

  1 スプリントにつき 1 度作成される契約:
    1. Planner が product-spec.md + roadmap.md からドラフト
    2. Generator と Evaluator が最大 3 ラウンドで交渉（Negotiation Log）
    3. 交渉が膠着した場合は Planner が強制裁定
    4. `status: active` になったら実装ループ開始

  ルール:
    - Rubric に記載した軸はすべて Evaluator が毎 iteration で採点する
    - `status: active` になった後は再交渉なしに編集しない
-->

---
sprint: <N>
feature: <feature-name>
bundling: split  # split | bundled
goal: |
  <このスプリントがユーザに届ける価値を 1 段落で記述>
acceptance_scenarios:
  - id: AS-1
    given: <前提条件>
    when: <ユーザ操作>
    then: <観測可能な結果>
  - id: AS-2
    given:
    when:
    then:
rubric:
  - axis: Functionality
    weight: high
    threshold: 1.0
    description: 全 acceptance scenario が E2E で pass
  - axis: Craft
    weight: std
    threshold: 0.7
    description: 可読性・テスト・プロジェクト規約遵守
  - axis: Design
    weight: std
    threshold: 0.7
    description: UX が一貫、product-spec の意図と整合
  - axis: Originality
    weight: low
    threshold: 0.5
    description: AI テンプレっぽさを避け、意図を感じる実装
max_iterations: 8
max_negotiation_rounds: 3
status: negotiating  # negotiating | active | done | aborted
---

# Sprint <N> Contract — <feature-name>

## Acceptance Scenarios（実行可能形式）

<!--
  上の YAML シナリオを Playwright / pytest / curl 等の実行テスト雛形として
  書き起こす。Evaluator はこのセクションからテストを導出する。
-->

### AS-1: <短いタイトル>

```
Given <前提>
When  <操作>
Then  <結果>
```

Evidence: `sprints/sprint-<N>-<feature>/evidence/AS-1.<ext>`

### AS-2: <短いタイトル>

```
Given
When
Then
```

Evidence: `sprints/sprint-<N>-<feature>/evidence/AS-2.<ext>`

## Rubric 詳細

| 軸 | 重み | 閾値 | 採点基準 |
|---|---|---|---|
| Functionality | high | 1.0 | ほぼバイナリ。全 AS が pass でなければ sprint 失敗 |
| Craft | std | 0.7 | カバレッジ・可読性・coding-rules.md 遵守 |
| Design | std | 0.7 | product-spec "What" と整合、スコープ逸脱なし |
| Originality | low | 0.5 | AI テンプレ常套句を避け、タスク固有の設計を優先 |

合格条件: **全軸が閾値以上**。weight は Evaluator が失敗を報告する際の優先順位にのみ影響する（高 weight 失敗が先に報告される）。

## Negotiation Log（交渉ログ）

<!--
  Round 1〜3 のみ。Round 3（またはそれ以前の合意）の後、Planner が Ruling を
  書き `status: active` に遷移させる。active 後は編集しない。
-->

### Round 1

- **Generator**:
- **Evaluator**:

### Round 2

- **Generator**:
- **Evaluator**:

### Round 3

- **Generator**:
- **Evaluator**:

### Ruling（裁定）

- **Planner**:
  <!-- 必要な contract 修正を記載。なければ「契約は原案通り受諾」 -->

## Sprint Outcome（スプリント結果）

<!--
  Orchestrator が status を done | aborted に遷移させる時に記入。
-->

- **最終 iteration**:
- **最終 commit**:
- **中断理由**（あれば）:
- **PR**:

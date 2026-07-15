# 振り返り形式 — 集計・メトリクス・レポート

このファイルは retrospective フェーズが生成するものを規定する: 機械的集計、
`pipeline-metrics.jsonl` の行、`retrospective.md` テンプレート、前回実行との
比較。要点は、提案を件数で裏づけること — 頻度の裏づけがない気づきは観察に留める。

English version: [retrospective-format.md](retrospective-format.md)

## Step 1: 集計（機械的）

構造化された記録だけを読む — 散文の再解釈はしない:

| ソース | 抽出するもの |
|--------|------------|
| `pipeline-state.json` `rounds` | ループ別ラウンド数（`spec_review`、`evaluate`）、severity 件数、ゲート |
| `pipeline-state.json` `arbitrations` | 各停滞シグナル・裁定・結果 |
| `pipeline-state.json` `role_overrides` | ロール入れ替え（能力フォールバック or 裁定） |
| `pipeline-state.json` `review_fallbacks` | cross-AI review 保証の縮退（phase・artifact・preferred/actual role） |
| 全ワーカー `report.json` | `blocker_category`（カテゴリ別に集計）、`status` |
| `evaluate-{n}.md` | 不合格項目（項目ID、要件ID） |

**失敗の分類別集計表** を作る — 観測された `blocker_category` ごとに1行:

```markdown
| blocker_category | count | phase(s) | example |
|------------------|-------|----------|---------|
| malformed_output | 3 | spec_review | round 2 review missing Gate line |
| timeout | 1 | evaluate | T-A04 playwright run exceeded ceiling |
```

`blocker_category` の値は agent-delegate 契約由来（`malformed_output`,
`tool_unavailable`, `timeout`, `sandbox_violation`, `env_error`,
`unclassified`）。オーケストレーターは `blocker` テキストから再分類してよいが、
カテゴリがグルーピングキー。

## Step 2: pipeline-metrics.jsonl（ここで組み立て、追記は最後）

リポジトリ横断の履歴ファイル `.specs/pipeline-metrics.jsonl`（JSON Lines）。1実行
につき1行:

```json
{"feature":"user-auth","run_id":"2026-07-05T09:00:00Z-a1b2","mode":"auto","rounds_spec":3,"rounds_eval":2,"stalls":1,"blocker_categories":{"malformed_output":3,"timeout":1},"applied_improvements":["P-01"],"ts":"2026-07-05T09:00:00Z"}
```

| フィールド | 意味 |
|-----------|------|
| `feature` / `run_id` / `mode` | 実行の同定 |
| `rounds_spec` / `rounds_eval` | 2ループのラウンド数 |
| `stalls` | この実行の arbitration エントリ数 |
| `blocker_categories` | カテゴリ → 件数のマップ（Step 1 から） |
| `applied_improvements` | この実行で実際に自動適用した提案ID（`improve-apply.ja.md` の適用ステップの結果。何も適用しない/縮退時は `[]`） |
| `ts` | ISO 8601 タイムスタンプ |

**行の追記は集計時ではなく、適用ステップの完了後に最後に行う。** JSON Lines は
追記専用なので、`improve-apply.ja.md` の実行前に書いた行には `applied_improvements`
を後から記録できない。Step 1 の値をここで組み立てて保持し、適用された集合が確定して
から1行追記する（何も適用しない・Issue 縮退・pr 未到達のときは `[]`）:

```bash
printf '%s\n' "$line" >> .specs/pipeline-metrics.jsonl
```

## Step 3: retrospective.md

`.specs/{feature}/retrospective.md` に書く:

```markdown
# Retrospective - {feature} ({run_id})
type: retrospective

## Execution Summary
モード / 通過フェーズ / PR URL / draft か ready か。

## Failure Breakdown
| blocker_category | count | phase(s) | example |

## Stalls and Arbitrations
裁定ごと: シグナル（S1/S2/S3/S4）/ 裁定（continue|swap|restructure|draft）/ 結果。

## Improvement Proposals
### P-01: {対象ファイル} (Tier 1)
- Rationale: （失敗集計のどの行から導いたか、件数付き）
- Change: （before/after の要旨）
### P-02: {対象ファイル} (Tier 2)
- ...

## Observations (not promoted to proposals)
頻度の裏づけがない気づき。記録するが対処しない。
```

規則:
- `type: retrospective` ヘッダは必須。
- 各提案は対象ファイルと Tier を明示する（Tier 判定そのものは
  `improve-apply.ja.md`）。ここでの Tier は提案者の分類で、`improve-apply.ja.md` が
  適用前に canonical path で再検証する。
- 各提案の Rationale は特定の失敗集計行とその件数を指す。件数がなければ Proposals
  ではなく Observations に置く（レポートは自由記述の感想ではなく集計で駆動）。

## Step 4: 前回実行との比較

`pipeline-metrics.jsonl` の前回行（今追記した行の1つ前）を読み、共有メトリクスで
比較する:

- `rounds_spec` / `rounds_eval`: 前回より多い = churn 増。
- `blocker_categories`: 件数が上がったカテゴリ = その領域の退行。
- `stalls`: 停滞が増えた = 収束が悪化。

比較の判定（メトリクス別に better / worse / mixed）を `retrospective.md` に記録する。
実行ごとに機能も難度も異なるため、単発の worse 比較は **それ自体では** revert の理由
にならない — 自動 revert 条件（「同一スキル・同系の退行が2実行連続」）は
`improve-apply.ja.md` にある。retrospective は比較を記録するだけで、revert は
決めない。

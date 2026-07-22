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

## Step 2: pipeline-metrics.jsonl（version付き追記専用ledger）

`.specs/pipeline-metrics.jsonl`はリポジトリ横断のJSON Lines ledger。terminalな
retrospectiveはversion付きmetrics recordを追記する。完了runを再開したときはsupersede
eventを追記し、古い行を変更・削除しない。

```json
{"record_type":"metrics","record_id":"2026-07-05T09:00:00Z-a1b2:r2:<snapshot-id>","revision":2,"feature":"user-auth","run_id":"2026-07-05T09:00:00Z-a1b2","mode":"auto","snapshot_id":"<sha256>","snapshot":{"run_id":"2026-07-05T09:00:00Z-a1b2","phase":"retrospective","completed_phases":["intake","spec_generate","inspect","spec_review","approval","implement","evaluate","pr","retrospective"],"rounds_spec":3,"rounds_eval":2,"report_count":2,"report_manifest":["implement-report.json","review-report.json"],"pr_url":"https://github.com/example/repo/pull/42","pr_status":"ready","state_ts_updated":"2026-07-05T10:00:00Z","state_hash":"<sha256>"},"rounds_spec":3,"rounds_eval":2,"stalls":1,"blocker_categories":{"malformed_output":3,"timeout":1},"applied_improvements":["P-01"],"ts":"2026-07-05T10:00:00Z"}
{"record_type":"supersede","event_id":"supersede:<record-id>:run_resumed","run_id":"2026-07-05T09:00:00Z-a1b2","supersedes":"<record-id>","reason":"run_resumed","ts":"2026-07-05T09:30:00Z"}
```

| フィールド | 意味 |
|-----------|------|
| `record_type` / `record_id` / `revision` | metrics ledgerの識別。revisionは再開runが再度terminalへ到達したときだけ増やす |
| `feature` / `run_id` / `mode` | 安定した論理runの識別 |
| `snapshot_id` / `snapshot` | 終端freshness snapshotのSHA-256と完全なcopy |
| `rounds_spec` / `rounds_eval` | 2ループのround数 |
| `stalls` | このrunのarbitration entry数 |
| `blocker_categories` | カテゴリ → 件数のmap（Step 1から） |
| `applied_improvements` | このrevisionで実際に自動適用した提案ID。未適用・縮退・pr未到達なら`[]` |
| `ts` | ISO 8601 record timestamp |

snapshot作成前にterminal `ts_updated`を1回設定する。すべての`report.json` /
`*-report.json`をspec相対pathでsortした`report_manifest`を作り、そのarrayから
`report_count`を導出する。canonical terminal stateは`phase: retrospective`、
`retrospective`を含む履歴`completed_phases`、固定terminal timestampを既に持つ。
ここから`.retrospective`を除いたSHA-256を`state_hash`、canonical snapshotのSHA-256を
`snapshot_id`とする。report、state、metrics recordは同じsnapshot objectを持ち、metrics
`ts`は`snapshot.state_ts_updated`と一致させる。

新しいtimestampを選ぶ前に`active <metrics-file> <run-id>`を呼ぶ。中断したfinalizationが
残したrecordが1件あり、そのsnapshotが現在の証拠と一致すれば、recordとtimestampをreportと
stateへ採用する。不一致ならrepairのため停止する。helperは最初のversion付きrecordをrevision
1、以後を正確に`max(existing revision) + 1`へ制限する。

**metrics recordはapply step完了後、最後に追記する。** 生のredirectではなくhelperを
使う。同じ`record_id`かつ同じ内容はno-opとなり、内容の衝突や2件目のactive recordは失敗する。

```bash
bash references/scripts/retrospective-ledger.sh append-metrics-once \
  .specs/pipeline-metrics.jsonl "$line"
```

完了runのresumeでは、state変更前に`supersede-once`を呼ぶ。安定したevent idは
`supersede:<record-id>:run_resumed`。`record_type`を持たないlegacy行もsynthetic line idを
持つmetrics recordとして読み取れる。

## Step 3: retrospective.md

`.specs/{feature}/retrospective.md` に書く:

```markdown
# Retrospective - {feature} ({run_id})
type: retrospective
state_snapshot: {stateとmetricsに完全一致する1行のcanonical JSON object}

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
- `state_snapshot:`行はちょうど1行必須。有効な1行JSONであり、
  `state.retrospective.snapshot`と完全一致させる。
- 各提案は対象ファイルと Tier を明示する（Tier 判定そのものは
  `improve-apply.ja.md`）。ここでの Tier は提案者の分類で、`improve-apply.ja.md` が
  適用前に canonical path で再検証する。
- 各提案の Rationale は特定の失敗集計行とその件数を指す。件数がなければ Proposals
  ではなく Observations に置く（レポートは自由記述の感想ではなく集計で駆動）。

## Step 4: 前回実行との比較

現在recordを追記する前に、前回の**有効な**metrics recordを読む。

```bash
bash references/scripts/retrospective-ledger.sh list-active \
  .specs/pipeline-metrics.jsonl | tail -n 1
```

selectorはsupersede済みrecordを除外し、同じ`run_id`に複数のactive recordがあれば失敗する。
物理的なJSONL最終行はsupersede eventや旧revisionかもしれないため、比較に使わない。
選択したrecordを共有metricsで比較する:

- `rounds_spec` / `rounds_eval`: 前回より多い = churn 増。
- `blocker_categories`: 件数が上がったカテゴリ = その領域の退行。
- `stalls`: 停滞が増えた = 収束が悪化。

比較の判定（メトリクス別に better / worse / mixed）を `retrospective.md` に記録する。
実行ごとに機能も難度も異なるため、単発の worse 比較は **それ自体では** revert の理由
にならない — 自動 revert 条件（「同一スキル・同系の退行が2実行連続」）は
`improve-apply.ja.md` にある。retrospective は比較を記録するだけで、revert は
決めない。

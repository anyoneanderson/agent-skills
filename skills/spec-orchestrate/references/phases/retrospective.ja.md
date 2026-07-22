# フェーズ: retrospective

PR（ready または draft）の後、構造化された実行記録を振り返りレポートとメトリクス行に
変え、許される範囲でスキル改善を行う。レポートとメトリクスはここで生成する。Tier
判定と自動適用 / revert の仕組みは `../improve-apply.ja.md` にあり、参照はするが
このフェーズ指示書では実装しない。

集計手順の詳細、`pipeline-metrics.jsonl` スキーマ、`retrospective.md` の
テンプレート、前回実行との比較は `../retrospective-format.ja.md` にある。

## 実行タイミング

pr 完了後（draft 着地を含む）に走る。pr 到達前に失敗した実行でも学習目的で
retrospective を走らせてよい — 失敗した実行が最も学びが大きい — **が、その場合は
レポート生成と Issue 起票までで止め、自動適用はしない**（clean な完了とのメトリクス
比較が成立しないため `../improve-apply.ja.md` の適用ステップをスキップ）。既存の state
ファイルに対してこのフェーズを単体実行することもできる。

## 入力

- `pipeline-state.json` — ラウンド履歴（`rounds`）、停滞と裁定（`arbitrations`）、
  ロール振り替え。
- 全ワーカーの `report.json` — `blocker_category` フィールドが分類キー
  （agent-delegate 契約）。
- `evaluate-{n}.md` の結果（不合格項目）と証跡。
- レビューファイル。
- 比較用に`.specs/pipeline-metrics.jsonl`から選択した前回のactive record。supersede済み
  rowとevent rowは比較入力にしない。

## アクション

役割分担: オーケストレーターは機械的集計・Tier 判定・
git/PR 操作を行い、**分析とファイル編集はワーカーに委譲する**。オーケストレーターは
スキルファイルを直接編集しない。

1. **集計（機械的 — オーケストレーター）。** `state`・全 `report.json` の
   `blocker_category` 別件数・evaluate の不合格から分類別集計を組む。メトリクス値を
   **組み立てる（まだ追記しない）**。手順とスキーマは `../retrospective-format.ja.md`。
2. **分析（LLM — 委譲ワーカー）。** 集計表をワーカーのサブエージェントに渡す。頻出
   パターンごとに「どのスキルのどのファイルの何が原因か」を特定し、根拠（集計のどの行
   から導いたか）と Tier を付けた改善提案を書く。頻度の裏づけがない気づきは提案では
   なく **観察** として記録する。
3. **メトリクス比較。** `retrospective-ledger.sh list-active`で前回の有効なrun recordを
   選び、共有メトリクス（round、blockerカテゴリ、停滞）でこの実行が悪化したか改善したか
   を判定する。これを消費する自動revertの判断は`../improve-apply.ja.md`。
   retrospectiveは比較を記録するだけ。物理的なJSONL最終行は読まない。
4. **改善の適用**（Tier 判定・行数バジェット検査・ブランチ/PR/マージ または Issue 起票
   への縮退・revert）は`../improve-apply.ja.md`。各外部actionの前に安定した`action_key`を
   stateへ予約し、実行後に結果を記録する。pending keyはactionを無条件に繰り返さず突合する。
   pr未到達のrunではapply経路をスキップする。
5. **terminal basisを復旧または固定する。** まずこの`run_id`を`active`で照会する。
   crash前に追記されたrecordがあれば、そのsnapshotを現在のround、report manifest、PR証拠、
   terminal phaseと照合する。一致時は新しい時刻を付けず、そのrevision、snapshot、各ID、
   `state_ts_updated`を採用する。不一致はrepairのため停止し、競合するactive recordを追記しない。
   active recordが無ければterminal `ts_updated`を1回選び、terminal state basisをmemory上で
   組み立てる。`phase: retrospective`を設定し、`completed_phases`へ`retrospective`を1回だけ
   追加し、そのtimestampを設定する。spec相対pathでsortしたreport manifestを集め、
   `.retrospective`を除くcanonical basisから`state_hash`、canonical snapshotから
   `snapshot_id`を算出する。初回terminal projectionはrevision 1、完了runのresume後は正確に
   N+1とする。hash対象fieldを固定し、finalization中に`ts_updated`を再更新しない。
6. **projectionを書き、metricsを冪等追記して検証する。** 固定snapshotを
   `retrospective.md`へ書く。apply step後、実際の結果を`applied_improvements`へ入れ
   （未適用・縮退・pr未到達なら`[]`）、固定terminal timestampをmetrics `ts`として
   `retrospective-ledger.sh append-metrics-once`を呼ぶ。その後、完全なterminal basisと
   `state.retrospective`を1回のatomic writeで書き、`stale`と`regeneration_required`をfalseに
   する。flagやtimestampだけの別writeは行わない。`pipeline-state-check.sh`がcleanになった
   後だけmarkerを削除する。同じterminal snapshotが確定済みならreport書き換え、metrics追記、
   外部actionの再実行を行わない。

## 出力

- `.specs/{feature}/` の `retrospective.md`（形式: 実行サマリ / 失敗の分類別
  集計表 / 停滞・裁定の記録 / 根拠 + Tier 付き改善提案 / 観察）。
- `.specs/pipeline-metrics.jsonl`の有効なversion付きrecord 1件。旧revisionは追記専用履歴に
  残し、eventでsupersedeする。
- （`../improve-apply.ja.md` 経由）改善ブランチ/PR または起票した Issue。

## 検証

- `retrospective.md` が所定の形式に従い、各提案が根拠（集計のどの行か）と Tier を持つ。
- report、state、有効なmetrics recordが同じsnapshotを持ち、
  `pipeline-state-check.sh`がexit 0になる。
- runのactive metrics recordがちょうど1件。同じterminal finalizationを再実行しても、
  追記も外部actionの再実行も起きない。
- 失敗の分類別集計が `state` + `report.json` だけから再現可能（ワーカーの記憶ではなく
  機械的）。

## state 更新

- revision、snapshotと各ID、freshness flag、report path、有効metrics ID、重複を除いた
  外部action結果を`state.retrospective`へ記録し、履歴上の完了として`completed_phases`へ
  `retrospective`を追加する。
- これが終端フェーズ: 実行を完了扱いにし、**`.specs/.orchestrate-active.json` を
  削除する** — run マーカーの削除が watchdog への終端の合図である
  （`../pipeline-config.ja.md` §Run マーカーと watchdog）。

## 遷移

- レポート + メトリクス記入（+ `../improve-apply.ja.md` 経由の改善 or Issue 縮退）
  完了 → **（終了）**

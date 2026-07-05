# フェーズ: retrospective

PR（ready または draft）の後、構造化された実行記録を振り返りレポートとメトリクス行に
変え、許される範囲でスキル改善を行う。レポートとメトリクスはここで生成する。Tier
判定と自動適用 / revert の仕組みは `../improve-apply.ja.md` にあり、参照はするが
このフェーズ指示書では実装しない。

集計手順の詳細、`pipeline-metrics.jsonl` スキーマ、`retrospective.md` の §5.6
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
- 比較用の `.specs/pipeline-metrics.jsonl` の前回行。

## アクション

役割分担（design §4.10、REQ-002 整合）: オーケストレーターは機械的集計・Tier 判定・
git/PR 操作を行い、**分析とファイル編集はワーカーに委譲する**。オーケストレーターは
スキルファイルを直接編集しない。

1. **集計（機械的 — オーケストレーター）。** `state`・全 `report.json` の
   `blocker_category` 別件数・evaluate の不合格から分類別集計を組む。
   `.specs/pipeline-metrics.jsonl` に1行追記する。手順とスキーマは
   `../retrospective-format.ja.md`。
2. **分析（LLM — 委譲ワーカー）。** 集計表をワーカーのサブエージェントに渡す。頻出
   パターンごとに「どのスキルのどのファイルの何が原因か」を特定し、根拠（集計のどの行
   から導いたか）と Tier を付けた改善提案を書く。頻度の裏づけがない気づきは提案では
   なく **観察** として記録する。
3. **メトリクス比較。** 前回実行の行を読み、共有メトリクス（ラウンド、blocker
   カテゴリ、停滞）でこの実行が悪化したか改善したかを判定する。これを消費する自動
   revert の判断は `../improve-apply.ja.md`。retrospective は比較を記録するだけ。
4. **改善の適用**（Tier 判定・行数バジェット検査・ブランチ/PR/マージ または Issue 起票
   への縮退・revert）は `../improve-apply.ja.md`。pr 未到達の実行ではスキップ。

## 出力

- `.specs/{feature}/` の `retrospective.md`（§5.6 形式: 実行サマリ / 失敗の分類別
  集計表 / 停滞・裁定の記録 / 根拠 + Tier 付き改善提案 / 観察）。
- `.specs/pipeline-metrics.jsonl` への1行追記。
- （`../improve-apply.ja.md` 経由）改善ブランチ/PR または起票した Issue。

## 検証

- `retrospective.md` が §5.6 形式に従い、各提案が根拠（集計のどの行か）と Tier を持つ。
- メトリクス行が追記され JSON としてパースできる。
- 失敗の分類別集計が `state` + `report.json` だけから再現可能（ワーカーの記憶ではなく
  機械的）。

## state 更新

- retrospective の結果（レポートパス、メトリクス行、適用した改善 or 起票 Issue）を
  `state` に記録する。
- これが終端フェーズ: 実行を完了扱いにする。

## 遷移

- レポート + メトリクス記入（+ `../improve-apply.ja.md` 経由の改善 or Issue 縮退）
  完了 → **（終了）**

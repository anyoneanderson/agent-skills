# フェーズ: retrospective

PR（ready または draft）の後、構造化された実行記録を振り返りレポートに変え、許される
範囲でスキル改善を行う。集計・Tier 判定・自動適用の実装は T015・T016 が持つ。この
ファイルは状態機械での位置づけと4点契約を定める。

## 入力

- `pipeline-state.json`（ラウンド履歴、停滞、裁定）。
- 全ワーカーの `report.json`（`blocker_category` を含む）。
- `evaluate-{n}.md` の結果と証跡。
- レビューファイル。

pr 到達前に失敗した実行でも学習目的で retrospective を走らせてよいが、その場合は
レポート生成と Issue 起票までで止め、自動適用はしない（clean な実行とのメトリクス
比較が成立しないため）。

## アクション

1. 記録を分類別集計にまとめ（機械ステップ）、`.specs/pipeline-metrics.jsonl` に1行
   追記する（T015）。
2. 分析とファイル編集はワーカーに委譲し、オーケストレーターは行わない —
   スキルファイルを直接編集するとオーケストレーター専任の原則に反する。オーケスト
   レーターは集計・Tier 判定・git/PR のみを担う。
3. 改善の適用（Tier 判定、行数バジェット検査、ブランチ/PR/マージ または Issue 起票
   への縮退、revert 方針）は T016 が定義する。

## 出力

- `.specs/{feature}/` の `retrospective.md`（design §5.6 形式）、
  `.specs/pipeline-metrics.jsonl` への1行追記、改善ブランチ/PR または起票した Issue。

## 検証

- `retrospective.md` が design §5.6 形式で書かれ、各提案が根拠（集計のどの行か）と
  Tier を持つ。
- メトリクス行が追記された。

## state 更新

- retrospective の結果（レポートパス、適用した改善、起票した Issue）を state に
  記録する。
- これが終端フェーズ: 実行を完了扱いにする。

## 遷移

- レポート + 改善（または Issue 縮退）完了 → **（終了）**

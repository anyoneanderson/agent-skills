# フェーズ: inspect

安価な機械検査（spec-inspect）を仕様セットに走らせてから、高価な意味論レビューに
peer LLM を使う。この関門が ID 不整合・欠落セクション・テストカバレッジ漏れを捕まえ、
敵対的レビュアーには整った仕様だけを見せる。

## 入力

- `.specs/{feature}/` の4ファイル。
- ロールバックエンドなし: spec-inspect は決定的な機械検査で、オーケストレーターが
  直接実行する（仕様の中身を書かないため、オーケストレーター専任の原則に反しない）。

## アクション

1. `.specs/{feature}/` に対し spec-inspect を実行する。
2. spec-inspect が構造化形式で findings を `CRITICAL` / `WARNING` / `INFO` の
   severity 付きで報告する。test.md カバレッジ検査（全 REQ/NFR に最低1つの
   テストケース）を含む。

## 出力

- severity 別にまとめた spec-inspect の findings 結果。空集合なら PASS。非空なら
  ID 不整合・欠落セクション・カバレッジ漏れ・INFO の指摘（曖昧な文言・命名・構造の
  提案）を列挙。

## 検証

- spec-inspect が findings 結果を出力した（空でも可）。クラッシュや出力欠落は
  ワーカー失敗: 1回再実行し、なお失敗なら blocked。

## state 更新

- 結果を `state.inspect` に単一の要約オブジェクトとして記録する:
  `{critical, warning, info, gate}`（CRITICAL/WARNING が無ければ `gate: PASS`）。
  `rounds` 配列ではなく1オブジェクト — inspect はループではなく機械検査のため。
- **差し戻しは severity で分岐する。** `CRITICAL` か `WARNING` の findings のみが
  仕様を差し戻す: `phase` を `spec_generate` にする。
- `INFO` のみ（または findings なし）→ `phase` を `spec_review` にする。INFO は
  記録して持ち越す（spec_review の Minor と同じ扱い）。ここでは修正しない。
- `completed_phases` に `inspect` を追加。

理由: 現実の仕様はほぼ必ず1件は INFO（曖昧な言い回し・命名・README 提案など）を引く。
全 findings を差し戻しトリガーにすると INFO だけで inspect → spec_generate を無限に
ループし、spec_review に到達できない。

## 遷移

- CRITICAL か WARNING あり → **spec_generate**（修正）
- INFO のみ / PASS → **spec_review**（INFO は持ち越し、修正しない）

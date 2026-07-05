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
2. spec-inspect が構造化形式で findings を報告する。test.md カバレッジ検査（全
   REQ/NFR に最低1つのテストケース）を含む。

## 出力

- spec-inspect の findings 結果（空集合なら PASS。非空なら ID 不整合・欠落
  セクション・テストカバレッジ漏れを列挙）。

## 検証

- spec-inspect が findings 結果を出力した（空でも可）。クラッシュや出力欠落は
  ワーカー失敗: 1回再実行し、なお失敗なら blocked。

## state 更新

- findings あり → `phase` を `spec_generate` にし（修正が必要）、このラウンドで
  inspect が findings を返したことを記録する。
- findings なし（PASS）→ `phase` を `spec_review` にする。
- `completed_phases` に `inspect` を追加。

## 遷移

- findings あり → **spec_generate**（修正）
- PASS（findings なし）→ **spec_review**

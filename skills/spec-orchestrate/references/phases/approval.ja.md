# フェーズ: approval

唯一の人間ゲート。manual では人がレビュー済みの仕様を承認する（またはフィードバック
を返す）。auto ではパイプラインが停止せず素通りする。

## 入力

- レビューを通過した仕様セット。
- 敵対的レビュー履歴の短い要約（ラウンド数、最終ゲート、未解決 Minor）。
- state のモード。

## アクション

**manual:**
1. 仕様要約とレビュー履歴を提示し、AskUserQuestion で確認する:
   ```
   question: "The spec passed adversarial review. Approve to implement?" /
             "仕様が敵対的レビューを通過しました。実装に進めて承認しますか？"
   options:
     - "Approve — proceed to implementation" / "承認 — 実装へ進む"
     - "Return feedback — revise the spec" / "フィードバックを返す — 仕様を修正"
   ```
2. フィードバック時は、それを planner への修正指示として取り込む。

**auto:** 質問しない。承認は暗黙で、そのまま進む。

## 出力

- 取得した判断: 承認、または planner に差し戻すフィードバック文。auto は暗黙の
  承認を生み、ディスクには何も書かない。

## 検証

- manual: 判断（承認 or フィードバック）が取得できた。人間の入力で正当にブロック
  する唯一のフェーズ。
- auto: 検証なし。ゲートは素通り。

## state 更新

- 承認（または auto）→ `phase` を `implement` にする。
- manual フィードバック → `phase` を `spec_generate` にし、フィードバックを次の
  planner 実行の修正入力として保存する。
- `completed_phases` に `approval` を追加。

## 遷移

- 承認 / auto 素通り → **implement**
- 人間フィードバック（manual）→ **spec_generate**（修正して再レビュー）

# フェーズ: implement

spec-implement を tasks.md に走らせて機能を作る。spec-implement は内部の spec-code
/ spec-review / spec-test ループとタスク単位の kind ルーティングを自前で持つ。
オーケストレーターはタスク一覧とロールマップを渡し、結果を検証するだけ。

## 入力

- `tasks.md`（`kind:` ラベル付き）と残りの仕様セット。
- 実装のロールマップ（`impl_ui` / `impl_backend` / `impl_test`）。spec-implement の
  `--roles` 引数として渡し、各タスクを kind ごとに spec-code（claude）か
  agent-delegate（codex）へ振り分けさせる。マップの組み立てとレビュアー反転規則は
  `../role-dispatch.ja.md` の「implement」。
- evaluate からの再入時: 差し戻す受け入れ試験の不合格 findings。

## アクション

1. 初回: spec-implement を仕様パス・issue・ロールマップとともに起動する。
   spec-implement は feature ブランチを作り、タスクループを回し、レビュアー反転
   （作った本人がレビューしない）を内部で適用する。
2. 再入（evaluate が不合格を返した）: 受け入れ findings を spec-implement 経由で
   `spec-code --feedback` に渡し、試験失敗にも同じ修正ループを適用してから該当
   タスクを再実行する。

**ステージのガード:** 実装ファイルは明示 pathspec でステージする。仕様4ファイル
（`requirement.md` / `design.md` / `tasks.md` / `test.md`）は、仕様成果物をコミット
するプロジェクト方針のときだけ加える。運転記録（`evidence/`・`review-*.md`・
`inspection-report.md`・`.inspection_result.json`・`evaluate-*.md`・
`pipeline-state.json`・`retrospective.md`・`pipeline-metrics.jsonl`）は決して
ステージしない。ステージ時の pathspec 除外が第一の防壁、intake が書いた
`.specs/.gitignore` が最後の防壁。

## 出力

- feature ブランチ上の実装済み変更。対応する `tasks.md` のチェックボックスが完了
  になり、spec-implement がタスク単位のレビューを記録している。

## 検証

- tasks.md のタスクが完了扱いになり、git 差分が実変更を反映している（自己申告
   ではなく計測）。
- spec-implement が未解決ブロッカーなしで戻った。`codex` 担当タスクが
  agent-delegate 利用不能を報告した場合、§エラー処理の振り替え規則を適用する
  （auto は振り替えて記録、manual は確認）。

## state 更新

- `phase` を `evaluate` にする。
- `completed_phases` に `implement` を追加。
- 実装中に適用したロール振り替えを `role_overrides` に記録する。

## 遷移

- タスク完了 → **evaluate**
- （evaluate からの再入はこのフェーズへの戻りであり、新たな出遷移ではない）

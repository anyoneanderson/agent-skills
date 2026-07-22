# フェーズ: implement

spec-implement を tasks.md に走らせて機能を作る。spec-implement は内部の spec-code
/ spec-review / spec-test ループとタスク単位の kind ルーティングを自前で持つ。
オーケストレーターはタスク一覧とロールマップを渡し、結果を検証するだけ。

## 入力

- `tasks.md`（`kind:` ラベル付き）と残りの仕様セット。
- 実装のロールマップ（`impl_ui` / `impl_backend` / `impl_test`）。spec-implement の
  `--roles` 引数として、`--host-runtime <host_runtime>` および
  `--review-fallback native-independent` とともに渡す。
  spec-implement は kind から AI role を選び、その後 native / cross-AI 実行を解決する。
  マップの組み立てと reviewer 独立性規則は `../role-dispatch.ja.md` の「implement」。
- evaluate からの再入時: 差し戻す受け入れ試験の不合格 findings。

## アクション

1. 初回: spec-implement を仕様パス・issue・ロールマップ・記録済み host・
   `--review-fallback native-independent` とともに起動する。spec-implement は feature
   ブランチを作り、タスクループを回し、反対 AI reviewer を優先しながら独立した
   reviewer instance を内部で保証する。
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
- spec-implement の completion summary。未使用時は空の、構造化された
  `review_fallbacks` list を含む。spec-implement は record を報告するだけで、pipeline
  state を読み書きしない。

## 検証

- tasks.md のタスクが完了扱いになり、git 差分が実変更を反映している（自己申告
   ではなく計測）。
- spec-implement が未解決ブロッカーなしで戻った。cross-AI reviewer が利用不能だった
  場合は、新規 read-only native reviewer を使い、workspace が不変で、fallback が記録
  されたことを検証する。この reviewer を作れなければフェーズは blocked のままにする。

## state 更新

- `phase` を `evaluate` にする。
- `completed_phases` に `implement` を追加。
- `implement.tasks_done` をチェック済み正準タスクの完全なIDで置き換える。
  `T[0-9]+[a-z]?(-[A-Za-z0-9]+)?` に合うIDを切り詰めずに保持し、`tasks.md` に存在しない、
  または未チェックのIDは含めない。
- 実装中に適用したロール振り替えを `role_overrides` に記録する。
- spec-implement が返した `review_fallbacks` list を検証し、全 entry を
  `review_fallbacks` に追記する。state を書くのはオーケストレーターだけとする。

## 遷移

- タスク完了 → **evaluate**
- （evaluate からの再入はこのフェーズへの戻りであり、新たな出遷移ではない）

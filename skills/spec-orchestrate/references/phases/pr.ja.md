# フェーズ: pr

蓄積した証跡とともに pull request を組み立てて作成する。PR 本文は敵対的レビュー履歴・
受け入れ証跡・未解決項目を持つ。停滞着地の場合は ready ではなく draft PR にする。

## 入力

- 全成果物: 最終仕様セット、レビューラウンド、`evaluate-{n}.md` と証跡、未解決
  Minor findings、裁定記録があればそれ。
- `issue-to-pr-workflow.md` があればそのブランチ・PR 規約。

## アクション

1. spec-implement の最終 PR 作成ステップを実行する（ブランチ・コミット規約は
   `issue-to-pr-workflow.md` に従う）。
2. 証跡セクションを PR 本文に添付する。正確なセクション構成（Adversarial Review
   History、Acceptance Evidence、Unresolved）は `../pr-assembly.ja.md` が定義する。
   このフェーズは遷移と入力を用意する。
3. 裁定の draft 着地で pr に来た場合、PR を **draft** で作成し、未解決の
   Critical / Improvement を `## Unresolved` に列挙する。

## 出力

- 作成された pull request（URL）。ready または draft。本文にレビュー履歴・受け入れ
  証跡ポインタ・未解決項目を持つ。

## 検証

- `gh` が PR URL を返す。受け入れ試験が不合格の間は PR を作成しない（非 draft の
  PR は合格した evaluate ゲートを要する）。
- PR 本文が参照する証跡ポインタが `.specs/{feature}/evidence/` 配下のファイルに
  解決する。

## state 更新

- `phase` を `retrospective` にする。
- PR URL と draft か否かを state に記録する。
- `completed_phases` に `pr` を追加。

## 遷移

- PR 作成（ready または draft）→ **retrospective**

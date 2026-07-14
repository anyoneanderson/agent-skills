# フェーズ: pr

蓄積した証跡とともに pull request を組み立てて作成する。PR 本文は敵対的レビュー履歴・
受け入れ証跡・未解決項目を持つ。停滞着地の場合は ready ではなく draft PR にする。

## 入力

- 全成果物: 最終仕様セット、レビューラウンド、`evaluate-{n}.md` と証跡、未解決
  Minor findings、裁定記録があればそれ。
- `issue-to-pr-workflow.md` があればそのブランチ・PR 規約。

## アクション

1. spec-implement の最終 PR 作成ステップを実行する（ブランチ・コミット規約は
   `issue-to-pr-workflow.md` に従う）。implement フェーズと同じステージのガードを
   適用する: 実装ファイル（および仕様成果物をコミットする方針のときだけ仕様4ファイル）
   を明示 pathspec でステージし、運転記録（`evidence/`・`review-*.md`・
   `inspection-report.md`・`.inspection_result.json`・`evaluate-*.md`・
   `pipeline-state.json`・`retrospective.md`・`pipeline-metrics.jsonl`）は決して
   ステージしない。pathspec 除外が第一の防壁、intake の `.specs/.gitignore` が最後の
   防壁。
2. 証跡セクションを PR 本文に添付する。正確なセクション構成（Adversarial Review
   History、Acceptance Evidence、Unresolved）は `../pr-assembly.ja.md` が定義する。
   このフェーズは遷移と入力を用意する。
3. **先送りした findings の後続 issue を起票する。** `fix_before: trial` /
   `required_check` / `follow_up` で持ち越した各 finding（`state.rounds` と
   レビューファイルから）について、`gh issue create` で issue を1件作る —
   タイトルは finding の要旨、本文には finding 全文・severity・`fix_before` 段階・
   対象ファイル/セクション・発生したレビューラウンド・PR への逆リンクを書く。
   同じクラス（同一パス + セクション）の finding は1つの issue にまとめてよい。
   各 issue を PR 本文の Deferred findings の該当行にリンクする。Minor は PR 本文
   への列挙のみで issue は作らない。
   `gh` が使えない、または issue 作成に失敗した場合は、finding 全文を PR 本文に
   残して警告行を添える — 先送りした finding が運転記録の中にしか存在しない状態を
   作らない。
4. 裁定の draft 着地で pr に来た場合、PR を **draft** で作成し、未解決の
   修正ループ対象 findings を `## Unresolved` に列挙する（`../pr-assembly.ja.md`
   参照）。

## 出力

- 作成された pull request（URL）。ready または draft。本文にレビュー履歴・受け入れ
  合否表と証跡マニフェスト・未解決項目を持つ。

## 検証

- `gh` が PR URL を返す。受け入れ試験が不合格の間は PR を作成しない（非 draft の
  PR は合格した evaluate ゲートを要する）。
- PR 本文の証跡マニフェストが列挙するファイルが `.specs/{feature}/evidence/` 配下に
  実在する。証跡ファイル自体はローカルに残り、コミットも添付もしない。
- PR 本文の先送り finding のすべてが、後続 issue へのリンクか、全文 + issue 作成
  失敗の警告のどちらかを持つ。どちらも無い先送り finding はフェーズ失敗 — 本文を
  直してから先へ進む。

## state 更新

- `phase` を `retrospective` にする。
- PR URL・draft か否か・後続 issue 番号（`deferred_issues`）を state に記録する。
- `completed_phases` に `pr` を追加。

## 遷移

- PR 作成（ready または draft）→ **retrospective**

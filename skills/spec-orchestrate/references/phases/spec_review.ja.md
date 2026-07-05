# フェーズ: spec_review

peer LLM による敵対的仕様レビュー（agent-delegate `--mode review`）を回し、レビュー
ゲートが通るまでループする。これは高価な意味論検査で、inspect が clean になった後に
のみ走る。

## 入力

- 4つの仕様ファイル（レビュアーは差分ではなくファイルそのものを読む）。
- 直前ラウンドの修正概要（ラウンド2以降）。
- `spec_reviewer` ロール → バックエンド（既定は agent-delegate 経由の codex）。
  解決は `../role-dispatch.ja.md` の「spec_review」。
- state のレビュアーセッション `thread_id`（ラウンド2以降の resume 用）。

## アクション

1. ラウンド1: agent-delegate `--mode review`（read-only）を、仕様ファイル一覧・
   敵対的観点・直前までの修正概要とともに起動する。
2. ラウンド2以降: `--resume <thread_id>` で同一セッションを継続し文脈を持ち越す
   （NFR-002）。レビューセッションは read-only で開始され、resume が保てる sandbox
   はそれだけなので、read-only で作られたセッションのみを resume する。
3. レビューファイルの Gate 行と severity 件数を読む。

## 出力

- `review-spec-{round}.md`。peer レビュアーの構造化レビューファイル（severity
  セクション + `Gate: PASS|FAIL`）。`.specs/{feature}/` 向けに書かれる。

## 検証

- レビューファイルが4点構造チェックを通る（type ヘッダ、Meta、Critical/Improvement
  /Minor を持つ Findings、`Gate: PASS|FAIL` 行を持つ Summary）。形式不正はワーカー
  失敗: 1回再実行し、なお不正なら blocked。
- findings は severity 必須。修正ループを回すのは Critical / Improvement のみ。
  Minor は記録して持ち越し、修正しない（REQ-007）。

## state 更新

- このラウンドを `rounds.spec_review` に追加: ラウンド番号、critical / improvement
  / minor 件数、findings 指紋、ゲート結果。
- レビュアー `thread_id` を `threads.spec_reviewer` に記録。
- 蓄積ラウンドに対し停滞シグナルを評価する（検知器は T010）。シグナル成立時は
  `phase` を arbitration にする。

## 遷移

- Critical か Improvement あり・停滞なし → **spec_generate**（修正して resume で
  再レビュー）
- Gate PASS（Minor のみ / なし）→ **approval**（Minor は PR 本文へ転記）
- 停滞シグナル成立 → **arbitration**（T010 で処理）

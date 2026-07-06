# フェーズ: spec_review

敵対的仕様レビューを回し、レビューゲートが通るまでループする。これは高価な意味論
検査で、inspect が clean になった後にのみ走る。レビューのバックエンドは
`spec_reviewer` ロールが解決する先（`../role-dispatch.ja.md` の「spec_review」）:
agent-delegate 経由の codex、または Claude サブエージェント。

## 入力

- 4つの仕様ファイル（レビュアーは差分ではなくファイルそのものを読む）。
- 直前ラウンドの修正概要と、それまでのラウンドの findings（ラウンド2以降）。
- `spec_reviewer` ロール → バックエンド（既定は agent-delegate 経由の codex）。
  解決は `../role-dispatch.ja.md` の「spec_review」。
- codex レビュアーの場合: `state.threads.spec_reviewer` のセッション `thread_id`
  （ラウンド2以降の resume 用）。

## アクション

まず `../role-dispatch.ja.md` でバックエンドを解決し、対応する経路を走らせる。どちらの
経路も同じレビューファイルを生成し、同じ修正ループに供給する。

**codex バックエンド（agent-delegate）:**
1. ラウンド1: agent-delegate `--mode review`（read-only）を、仕様ファイル一覧・
   敵対的観点・直前までの修正概要とともに起動する。
2. ラウンド2以降: `--resume <thread_id>` で同一セッションを継続し文脈を持ち越す。
   レビューセッションは read-only で開始され、resume が保てる sandbox
   はそれだけなので、read-only で作られたセッションのみを resume する。

**claude バックエンド（サブエージェント）:**
1. ラウンド1: 仕様ファイル一覧と敵対的観点でレビューのサブエージェントを起動する。
   同じ構造化レビューファイルを出力する。
2. ラウンド2以降: Claude サブエージェントには resume する `thread_id` が無いため、
   **セッションレス** で継続する: 直前ラウンドの修正概要と、それまでのラウンドの
   findings（`state.rounds.spec_review` から）を新しいサブエージェントに渡し、解決済み
   の指摘を蒸し返さないようにする。これが claude における resume 相当。

3. レビューファイルの Gate 行と severity 件数を読む。

## 出力

- `review-spec-{round}.md`。peer レビュアーの構造化レビューファイル（severity
  セクション + `Gate: PASS|FAIL`）。`.specs/{feature}/` 向けに書かれる。

## 検証

- レビューファイルが4点構造チェックを通る（type ヘッダ、Meta、Critical/Improvement
  /Minor を持つ Findings、`Gate: PASS|FAIL` 行を持つ Summary）。形式不正はワーカー
  失敗: 1回再実行し、なお不正なら blocked。
- findings は severity 必須。修正ループを回すのは Critical / Improvement のみ。
  Minor は記録して持ち越し、修正しない。

## state 更新

- このラウンドを `rounds.spec_review` に追加: ラウンド番号、critical / improvement
  / minor 件数、findings 指紋（`../stall-detection.ja.md` に従い、Critical +
  Improvement のみで計算）、ゲート結果。このエントリが停滞検知の唯一の入力。
- codex バックエンドのみ: レビュアー `thread_id` を `threads.spec_reviewer` に
  resume 用として記録する。claude サブエージェントは thread_id を持たない
  （セッションレスで継続）ため未設定のままにする。
- 蓄積ラウンドに対し停滞シグナル S1〜S3 を評価する（`../stall-detection.ja.md`）。
  シグナル成立時は `phase` を arbitration にする。

## 遷移

- Critical か Improvement あり・停滞なし → **spec_generate**（修正して再レビュー —
  codex は同一セッションを resume、claude は findings を持ち越したセッションレス）。
  Minor はここで修正せず、既に記録済みで PR 本文へ転記する。
- Gate PASS（Minor のみ / なし）→ **approval**
- 停滞シグナル成立 → **arbitration**（`../stall-detection.ja.md`）

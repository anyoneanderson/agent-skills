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

**Gate 規則（両バックエンド共通）:** レビュープロンプトでは、すべての Critical /
Improvement finding に `fix_before`
（`implementation | trial | required_check | follow_up` — 定義・既定値
`follow_up`・格上げの立証責任は敵対的レビュープロンプトに定義）を付けさせ、`Gate` 行を
この軸だけから機械的に決めさせる — `fix_before: implementation` の finding が1件でも
あれば `Gate: FAIL`、それ以外は `Gate: PASS`。severity は人間の読み用に出力に残るが、
Gate の判定には使わない。Gate が集計と食い違わないよう、毎ラウンドこれをプロンプトに
明示する。

**段階の読み替え:** `pipeline.yml` が `review.fix_before_stages` を定義している場合
（`../pipeline-config.ja.md`）、その一覧をレビュー文脈に渡し、本ファイル全体の
`implementation` — Gate 規則・修正ループ・`fix_required` — をその一覧の**先頭**の
段階と読み替える。

**ラウンドごとのレビュー範囲:** ラウンド1は仕様セット全体を深く読む。ラウンド2以降は、
未解決の finding・修正で変わったセクション・そのセクションを直接使う箇所だけを読むよう
レビュアーに指示し、再レビューの格上げ規則（修正と無関係な新規指摘を `implementation`
にできるのは秘密情報の漏えい・データ損失・マージ条件の回避・実装不能のみ）に従わせる。
これは resume するバックエンドで特に効く — 指示しないと前ラウンドに探索した領域を
掘り続ける。

**codex バックエンド（agent-delegate）:**
1. ラウンド1: agent-delegate `--mode review`（read-only）を、仕様ファイル一覧・
   敵対的観点・直前までの修正概要とともに起動する。
2. ラウンド2以降: `--resume <thread_id>` で同一セッションを継続し文脈を持ち越す。
   レビューセッションは read-only で開始され、resume が保てる sandbox
   はそれだけなので、read-only で作られたセッションのみを resume する。
3. そのラウンドが5分以内に終わる具体的根拠がある場合だけ同期実行する。
   それ以外は明示的な `--detach` を使って expected run id を保持し、
   `../role-dispatch.ja.md` の report-first な15〜30秒待機を適用する。
   20分以上の予算を持つレビューゲートには5分以内という根拠がないため detach する。
   仕様レビューまたは修正に対する呼び出し側のタイムアウトは20分以上とする。

**claude バックエンド（サブエージェント）:**
1. ラウンド1: 仕様ファイル一覧と敵対的観点でレビューのサブエージェントを起動する。
   同じ構造化レビューファイルを出力する。
2. ラウンド2以降: Claude サブエージェントには resume する `thread_id` が無いため、
   **セッションレス** で継続する: 直前ラウンドの修正概要と、それまでのラウンドの
   findings（`state.rounds.spec_review` から）を新しいサブエージェントに渡し、解決済み
   の指摘を蒸し返さないようにする。これが claude における resume 相当。

いずれのバックエンドでも、完了後にレビューファイルの Gate 行、severity 件数、
`fix_before` タグを読む。

## 出力

- `review-spec-{round}.md`。peer レビュアーの構造化レビューファイル（severity
  セクション + `fix_before` タグ + `Gate: PASS|FAIL`）。`.specs/{feature}/` 向けに
  書かれる。

## 検証

- レビューファイルが4点構造チェックを通る（type ヘッダ、Meta、Critical/Improvement
  /Minor を持つ Findings、`Gate: PASS|FAIL` 行を持つ Summary）。形式不正はワーカー
  失敗: 1回再実行し、なお不正なら blocked。
- findings は severity 必須。さらに Critical / Improvement のすべての finding に
  有効な `fix_before` 値が必要で、`fix_before: implementation` の finding には
  「誰が・どの操作で・何が壊れるか」「どのマイルストーン以降に成立するか」の記述が
  必要。欠けている場合は形式不正として扱う（同じ1回再実行の規則）。
- **Gate は `fix_before` タグから再集計する** — ゲートを止める段階の finding が
  1件でもあれば FAIL。レビュアーの `Gate` 行を鵜呑みにしないこと: 委譲スクリプトが
  検査するのは構造の存在だけで、Gate 行と findings の一致は検査しない。集計と矛盾する
  `Gate` 行は形式不正として扱う（同じ1回再実行の規則）。
- 修正ループを回すのは `fix_before: implementation` の finding のみ。`trial` /
  `required_check` / `follow_up` の finding と Minor は記録して持ち越し、PR 本文へ
  転記する（`../pr-assembly.ja.md`）。このループでは修正しない。

## state 更新

- このラウンドを `rounds.spec_review` に追加: ラウンド番号、critical / improvement
  / minor 件数、`fix_required`（`fix_before: implementation` の finding 件数）、
  findings 指紋（`../stall-detection.ja.md` に従い、修正ループ対象 =
  `fix_before: implementation` の finding のみで計算）、クラスキー（パス +
  セクション。`../stall-detection.ja.md` の S4）、ゲート結果。このエントリが停滞検知の
  唯一の入力。
- codex バックエンドのみ: レビュアー `thread_id` を `threads.spec_reviewer` に
  resume 用として記録する。claude サブエージェントは thread_id を持たない
  （セッションレスで継続）ため未設定のままにする。
- 蓄積ラウンドに対し停滞シグナル S1〜S4 を評価する（`../stall-detection.ja.md`）。
  シグナル成立時は `phase` を arbitration にする。

## 遷移

- `fix_before: implementation` の finding あり・停滞なし → **spec_generate**
  （修正して再レビュー — codex は同一セッションを resume、claude は findings を
  持ち越したセッションレス）。先送りの finding（`trial` / `required_check` /
  `follow_up`）と Minor はここで修正せず、既に記録済みで PR 本文へ転記する。
- Gate PASS（`implementation` の finding なし）→ **approval**
- 停滞シグナル成立 → **arbitration**（`../stall-detection.ja.md`）

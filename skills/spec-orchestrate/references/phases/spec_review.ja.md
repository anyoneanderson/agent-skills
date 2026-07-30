# フェーズ: spec_review

敵対的仕様レビューを回し、レビューゲートが通るまでループする。これは高価な意味論
検査で、inspect が clean になった後にのみ走る。レビューの backend は
`spec_reviewer` AI role と記録済み `host_runtime` の解決結果
（`../role-dispatch.ja.md` の「spec_review」）。一致する role は runtime-native
subagent、異なる role は agent-delegate を使う。その cross-AI peer が利用不能なら、
新規の独立 host-native reviewer を使う。

## 入力

- 4つの仕様ファイル（レビュアーは差分ではなくファイルそのものを読む）。
- 直前ラウンドの修正概要と、それまでのラウンドの findings（ラウンド2以降）。
- `spec_reviewer` AI role と記録済み `host_runtime`。解決は
  `../role-dispatch.ja.md` の「spec_review」。
- agent-delegate backend の場合: `state.threads.spec_reviewer` の session
  `thread_id`（ラウンド2以降の resume 用）。
- オーケストレーターの review fallback policy: `native-independent`。

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

<!-- out-of-scope-acceptance:start -->
**非目標との受理照合:** オーケストレーターはレビュアーの生の出力を検証して生のGateを
再集計した後、ケース、状況、機能が書かれていないと主張するfindingを、
`requirement.md`の空でない「非目標」または「対象外」と比較してから修正キューへ入れる。

1. 同じ機能または状況が明示的に除外されている場合だけfindingを棄却する。
   キーワードが重なるだけの場合や、より広い除外を推測しないと一致しない場合は棄却しない。
2. 矛盾、実装不能、非目標が受理済み要求を不可能にするという指摘、または非目標が
   仕様の情報源となった依頼やIssueと衝突するという指摘には、この照合を適用しない。
3. レビューファイルへ`受理判断`を追記し、findingのタイトルまたは順番、対応する非目標の
   引用と行、`rejected: out_of_scope`、理由を記録する。
   生のfindingは変更しない。
4. 棄却したfindingを有効な`fix_required`、fingerprint、class key、Gate、修正キューから
   除外する。
   受理判断に有効Gateを記録し、生のGateは未照合出力の証拠として残す。
5. ラウンド1では`受理判断`の下に`スコープ基準`を追記し、すべての非目標の正確な文面と
   行を`.specs/{feature}/review-spec-1.md`へ記録する。
   resume時と後続ラウンドでは、このファイルを基準として読み、findingを棄却できるのは、
   変更されていない基準項目と一致する場合だけとする。
   レビュー開始後に追加または変更した非目標は一致とみなさず、findingを修正キューに残す。
6. 明示的な基準との一致がないfindingは通常の修正ループへ渡す。
   指摘を棄却するために非目標を後から広げてはならない。
   ユーザーが情報源の依頼またはIssueを変更した場合は、仕様の生成とinspectをやり直し、
   基準をその場で書き換えずに新しい基準でレビューを開始する。
<!-- out-of-scope-acceptance:end -->

**Cross-AI backend（agent-delegate）:**
1. ラウンド1: agent-delegate
   `--mode review --target <spec_reviewer>`（read-only）を、仕様ファイル一覧・
   敵対的観点・直前までの修正概要とともに起動する。
2. ラウンド2以降: `--resume <thread_id>` で同一セッションを継続し文脈を持ち越す。
   レビューセッションは read-only で開始され、resume が保てる sandbox
   はそれだけなので、read-only で作られたセッションのみを resume する。
3. そのラウンドが5分以内に終わる具体的根拠がある場合だけ同期実行する。
   それ以外は明示的な `--detach` を使って expected run id を保持し、
   `../role-dispatch.ja.md` の report-first な15〜30秒待機を適用する。
   30分ごとに状態を再確認し、同じ待機契約に定めた2時間の停止手順を適用する。
   5分以内という具体的な根拠がないレビューはdetachする。

<!-- spec-review-env-error-recovery:start -->
**detach した `env_error` の成果物復旧（agent-delegate のみ）：**
一般の fail-closed 復旧契約は `../role-dispatch.ja.md` の Step 3 に従う。
起動前に、成果物の正確なパス `.specs/{feature}/review-spec-{round}.md` を記録する。
同じパスを detach 起動へ `--review-output` で渡し、`artifacts.review_file` と宣言済み復旧パスを一致させる。
パスの既存有無と、存在する場合は内容 fingerprint を鮮度の基準として記録する。
呼び出し側が生成した相関値を記録し、レビュアーに `## Meta` へ書かせる。
phase validator として、後述の「検証」にある検査項目を記録する。
一般契約が定める起動前 workspace fingerprint を、宣言済み out-dir だけ除外して記録する。
detach 起動から値が返ったら、監視を始める前に宣言済みの値を `expected_run_id` と結び付ける。

valid terminal report の `meta.run_id` が `expected_run_id` と一致し、`status: blocked` かつ `blocker_category: env_error` の場合だけ復旧を試す。
監視は宣言済みのレビューファイルだけを対象に、次の項目を検査する。

1. 成果物が鮮度の基準から新規作成または更新され、宣言済みの相関値を含むことを確認する。
2. 宣言済みレビューファイルへ4点構造チェックを適用する。
3. Critical / Improvement の全 finding が有効な段階一覧の `fix_before` 値を持つことを確認する。
4. タグから Gate を再計算し、集計と矛盾する `Gate` 行を却下する。
5. 実行後の workspace fingerprint を起動前の値と比較し、完全一致を要求する。

すべての検査に合格した場合は、レビュアーを再実行せずレビュー結果を採用する。
成果物パス、相関の証拠、validator の結果、再計算した Gate を実行記録に残し、後述の通常の「state 更新」と「遷移」へ進む。
元の blocked report は変更せず、実行時の診断情報として残す。
別 run または別分類の report、古い成果物、相関を確認できない成果物、validator 不合格、workspace fingerprint の変化は blocked のまま扱う。
却下した復旧候補には形式不正時の再実行規則を適用しない。後で再試行する場合は、起動前記録を作り直した新しい run とする。
<!-- spec-review-env-error-recovery:end -->

**Runtime-native backend（subagent）:**
1. ラウンド1: spec author とオーケストレーターの文脈から分離した新規 review
   subagent を、仕様ファイル一覧と敵対的観点で起動する。同じ構造化レビュー内容を
   返し、オーケストレーターがレビューファイルへ書く。
2. ラウンド2以降: native subagent には agent-delegate の `thread_id` が無いため、
   **セッションレス** で継続する: 直前ラウンドの修正概要と、それまでのラウンドの
   findings（`state.rounds.spec_review` から）を新しいサブエージェントに渡し、解決済み
   の指摘を蒸し返さないようにする。これが native review における resume 相当。
3. write tool を公開せず、reviewer 起動直前とレビュー完了後に1つずつ取得した
   repository change fingerprint を突合する。tracked worktree / staged diff の内容と、
   gitignore 対象外の untracked
   path / 内容を含める。除外するのは `../pipeline-config.ja.md` の orchestrator 所有
   run-record path だけで、`.specs/` 全体を除外してはいけない。対象 fingerprint に
   変化があれば結果を無効とし、通常の workspace drift 手順へ blocked で回す。

設定された cross-AI reviewer が利用不能な場合、この runtime-native 経路を
`native-independent` fallback として使う。actual reviewer AI role は `host_runtime` に
なるが、実行 instance と文脈は spec author から独立させる。各ラウンドにつき
`state.review_fallbacks` を1件記録する。新規 native reviewer を保証できなければ、
オーケストレーター文脈でレビューせず blocked にする。

いずれのバックエンドでも、完了後にレビューファイルの生のGate行、severity件数、
`fix_before`タグを読み、生の結果を検証してから非目標との照合を行い、有効Gateを計算する。

## 出力

- `review-spec-{round}.md`。独立レビュアーの構造化レビューファイル（severity
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
- **最初に全`fix_before`タグから生のGateを再集計する** — ゲートを止める段階のfindingが
  1件でもあれば FAIL。レビュアーの `Gate` 行を鵜呑みにしないこと: 委譲スクリプトが
  検査するのは構造の存在だけで、Gate 行と findings の一致は検査しない。生の集計と矛盾する
  Gate行は形式不正として扱う（同じ1回再実行の規則）。その後に受理照合を適用し、
  受理したfindingだけから有効Gateを再計算する。
- 修正ループを回すのは受理した`fix_before: implementation`のfindingのみ。`trial` /
  `required_check` / `follow_up` の finding と Minor は記録して持ち越し、このループでは
  修正しない。PR作成時にfinding全文を後続Issueへ保存し、`../pr-assembly.ja.md`に
  従ってレビュー判断を変えるリンクと詳細だけをPR本文へ選ぶ。

## state 更新

- このラウンドを `rounds.spec_review` に追加: ラウンド番号、critical / improvement
  / minor 件数、`fix_required`（受理した`fix_before: implementation`のfinding件数）、
  findings 指紋（`../stall-detection.ja.md` に従い、修正ループ対象 =
  受理した`fix_before: implementation`のfindingのみで計算）、クラスキー（パス +
  セクション。`../stall-detection.ja.md` の S4）、ゲート結果。このエントリが停滞検知の
  唯一の入力。
- agent-delegate backend のみ: reviewer `thread_id` を `threads.spec_reviewer` に
  resume 用として記録する。runtime-native subagent はこの thread id を持たず、
  セッションレスで継続するため未設定のままにする。
- `native-independent` を使った場合、phase（`spec_review`）・artifact（`spec`）・round・
  レビュー時点の `host_runtime`・preferred/actual role・runtime-native backend・
  `peer_unavailable` reason・`fresh_subagent` independence を持つ fallback record を
  `review_fallbacks` に追記する。
- 蓄積ラウンドに対し停滞シグナル S1〜S4 を評価する（`../stall-detection.ja.md`）。
  シグナル成立時は `phase` を arbitration にする。

## 遷移

- 受理した`fix_before: implementation`のfindingあり・停滞なし → **spec_generate**
  （修正して再レビュー — agent-delegate session は resume、native review は
  findings を持ち越したセッションレス）。先送りの finding（`trial` / `required_check` /
  `follow_up`）と Minor はここで修正せず、後続Issue作成とPR本文の情報選別に使う
  運転記録へ残す。
- 有効Gate PASS（受理した`implementation`のfindingなし）→ **approval**
- 停滞シグナル成立 → **arbitration**（`../stall-detection.ja.md`）

# 担当解決（role-dispatch）— 各フェーズを誰が実行するか

各フェーズは AI ロールキー（例: `spec_author`、`e2e_runner`）を名指しする。この
ファイルは、キーを AI role（`claude` / `codex`）へ解決し、次に現在の host に合う
実行 backend へ解決する唯一の場所である。フェーズ指示書はどちらの判断も繰り返さず、
このファイルを参照する。

English version: [role-dispatch.md](role-dispatch.md)

## Step 0: host runtime を確定して記録する

role を読む前に、spec-orchestrate を実行している runtime の識別子を明示的に
`host_runtime` へ設定する。Codex なら `codex`、Claude Code なら `claude` である。
intake で `pipeline-state.json` に記録する。resume 時も改めて確定し、次の worker を
起動する前に記録を更新する。role の既定値や agent-delegate の環境変数から推測しない。

現在の runtime を確定できない場合:

- **manual:** 人に `codex` / `claude` を選んでもらい、記録する。
- **auto:** `host_runtime_unknown` を理由に再開可能な blocked 状態で停止する。
  推測せず、worker を起動しない。

## Step 1: AI roles を読む

`pipeline.yml` の `roles` を読む（既定パス `.specs/pipeline.yml`。形式は
`pipeline-config.ja.md`）。ファイル不在時は次の既定値をそのまま使う:

| ロールキー | 既定 | フェーズ |
|-----------|------|---------|
| `spec_author` | `claude` | spec_generate |
| `spec_reviewer` | `codex` | spec_review |
| `impl_ui` | `claude` | implement（ui タスク） |
| `impl_backend` | `codex` | implement（backend タスク） |
| `impl_test` | `codex` | implement（test タスク） |
| `e2e_runner` | `claude` | evaluate |

role 値が選ぶのは AI であり、backend ではない。値は常に `claude` か `codex`。
それ以外は設定エラー — 停止して報告する。

## Step 2: バックエンドを解決する

AI role が確定してから backend を解決する。host と role が一致すれば host の
runtime-native subagent を使う。異なれば agent-delegate を使い、role を明示的な
target にする。

<!-- dispatch-matrix:start -->
| Host runtime | AI role | Backend | agent-delegate target |
|--------------|---------|---------|-----------------------|
| `codex` | `codex` | `runtime-native` | `-` |
| `codex` | `claude` | `agent-delegate` | `claude` |
| `claude` | `claude` | `runtime-native` | `-` |
| `claude` | `codex` | `agent-delegate` | `codex` |
<!-- dispatch-matrix:end -->

`runtime-native` では現在の runtime でサブエージェントを起動し、agent-delegate は
**起動しない**。role 用の agent 定義があれば使う。たとえば spec author は
`workflow-planner`、E2E は `workflow-evaluator` である。native 経路は特定の起動
ツールを名指しせず、現在の runtime が提供する手段を使う。ツール名をハードコードしない。

`agent-delegate` では公開契約どおりにスクリプトを呼び、常に
`--target <AI-role>` を明示する。プログラムからの呼び出しは、ネストしたチェーンで
環境による自己判定に頼らない。

**agent-delegate は契約依存。** スクリプトは `agent-delegate/references/contract.md`
（引数 + `report.json` スキーマ）どおりに呼び、内部実装に依存しない。プログラムからの
呼び出しは `--target` を渡すこと。

## Step 3: 同期 vs detach を選ぶ

呼び出し側は書き込みの有無と具体的な時間根拠から実行形態を決める:

| フェーズ種別 | 形態 | 理由 |
|------------|------|------|
| 仕様生成・修正、implement（コード）、evaluate（E2E）、証跡保存 | 明示的な `--detach` | ファイルを書き込む delegate |
| read-only かつ5分以内に完了する具体的根拠がある spec_review、調査、成果物レビュー | 同期 | 読み取り専用かつ所要時間の根拠がある |
| 5分以内という具体的根拠がないロール | `--detach` | 上限のない同期待機を許可しない |

detach 起動時の取得値（契約どおり）:
```bash
launch="$(agent-delegate.sh --mode <delegate|review> --target <AI-role> ... --detach)"
expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
```

起動前に、phase owner は期待する各成果物の正確なパス、鮮度の基準、呼び出し側生成の相関値、phase 固有 validator を記録する。
この宣言済み情報だけを成果物復旧の契約とし、失敗後に作った validator で復旧を許可しない。
review などの read-only phase では、宣言済み out-dir だけを除外したワークスペースの起動前 git snapshot も記録する。
snapshot には agent-delegate 契約で定義した内容 fingerprint を使い、path または status の一覧だけで済ませない。

**待ちは待つ側の turn を跨いで生き残らせる。** turn 内の素朴なポーリングは turn
終了とともに消え、expected run を誰も監視しなくなる。待ち方の標準は1つだけで、
バックアップ規則がそれに加わる:

- **標準の待ち方:** agent-delegate の expected-run 状態機械を15秒間隔、最大30秒の
  周期で適用する**ホストランタイムのバックグラウンドジョブ**を走らせる。
  各周期では expected-run report、owner、pid、heartbeat、プロセス状態の順に確認する。
  `RUNNING`、すべての `DEGRADED_*`、`ORPHANED_WORKER`、`FINALIZING`、
  `REPORT_INVALID_PENDING` では待機を続け、report の不在だけで失敗にしない。
  ジョブは turn を跨ぎ、terminal または対処可能な状態で dispatcher を再開する。
  フォアグラウンドのポーリングだけを残して turn を終えない。
  何も仕掛けずに turn を終えない。
  yield する前に、待っている report パスを run マーカーへ登録する
  （`.specs/.orchestrate-active.json` に `jq '.waiting_report = $p'`。
  `pipeline-config.ja.md` §Run マーカー参照）— watchdog はこれで「正当な待機」と
  「停滞」を区別する。監視ジョブ自体が `expected_run_id` を保持する。
  結果を回収したら `.waiting_report` を消す。登録の無い
  待機は停滞と区別できず、ブロックされる。
- **バックアップ監視:** サブワーカーが detach 待ちを持つ間、オーケストレーターは同じ
  expected run に自前のバックグラウンド監視を仕掛ける。バックアップが先に対処可能な
  状態へ到達したら結果を検証し、停滞したワーカーを起こす（または交代させる）。
  これは任意の保険ではなく標準手順とする。

起動から30分、60分、90分に達したら、バックグラウンド監視はreportから状態を再確認する。
監視は最後に読めたowner、pid、heartbeat、プロセス確認結果、report検証エラーを保存する。
待機状態なら処理を続け、reportの不在だけで失敗にしない。

`launched_at`から2時間に達したら、監視は状態をもう一度確認する。
新しいterminal report、`SUPERSEDED`、`DEAD`を確認した場合は、シグナルを送らず、その結果を返す。
それ以外でexpected runのownerが変わっておらずmonitorが生存している場合は、監視がmonitorへ`TERM`を送り、expected runのterminal reportを最大90秒待つ。
monitorが不在または生存不明の場合、あるいは90秒以内にterminal reportが公開されない場合は、監視が`waiting_report`を消して待機を終了し、保存した診断情報を人間へ渡す。
この停止手順では`--force`を実行せず、expected runのものと確認できないプロセスへシグナルを送らない。

expected-run の terminal report が `status: blocked` かつ `blocker_category: env_error` の場合、監視は blocked を通知する前に fail-closed な成果物復旧を適用する。
宣言済み成果物が起動後に新規作成または更新され、相関値を持ち、phase validator に合格した場合だけタスク結果を採用する。
blocked report は実行時の診断として残す。
ほかの blocked 分類と成果物復旧の不合格は blocked のまま扱う。
detach monitor が回収される host では、同じ validator と元の起動期限を使う同期的な上限付き `until` loop を使ってもよい。
loop は復旧条件を緩めない。
valid な expected-run の `env_error` report が現れない場合は復旧を拒否し、期限到達時に診断情報を上位へ渡す。
monitor の消失または idle 通知の欠落だけでは失敗にしない。

## フェーズ別の解決

### spec_review（敵対的仕様レビュー）

`spec_reviewer` を行列で解決し、review / read-only mode で走らせる。一致する role は
spec author の文脈と分離した新規 native reviewer subagent、異なる role は
agent-delegate `--mode review --target <spec_reviewer>` を使う。
agent-delegate を同期実行するのは5分以内に完了する具体的根拠がある場合だけとし、
それ以外は `--detach` と上記の expected-run 待機を使う。
ラウンド1で
セッションを作り、ラウンド2以降は state の `threads.spec_reviewer` の
`--resume <thread_id>` で継続する（レビューセッションは read-only で作られ、resume
が保てる sandbox はそれだけ）。cross-AI peer が利用不能なら、下記の独立 native
review fallback を使う。この経路はセッションレスで、毎ラウンド新規 reviewer
subagent を起動する。

### spec_generate（spec author）

`spec_author` も同じ行列で解決する。一致する role は `workflow-planner` を
runtime-native subagent として走らせる。異なる role は仕様ファイルを書くため、
agent-delegate `--mode delegate --target <spec_author> --detach` で走らせる。

### evaluate（受け入れ試験）

解決した `e2e_runner` AI role を **必ず `--backend` で明示**し、記録済み host を
`--host-runtime` で spec-evaluate へ渡す。`--backend` という option 名は互換性のため
維持するが、`claude|codex` の値が選ぶのは AI role であり、spec-evaluate がこの行列で
実行手段を決める。単体実行時の既定は `self` なので、パイプライン内でこれに頼ると
2つの既定が混ざる。spec-evaluate `references/execution-backend.ja.md` 参照。

### implement（機能を作る）

実装タスクをここから1件ずつ差配しない。`impl_*` ロールを spec-implement の
`--roles` 引数として渡し、タスク単位の `kind → 担当` ルーティングは spec-implement
内部に任せる（二重管理をしない）。

- `roles` からマップを組む: `ui=<impl_ui>,backend=<impl_backend>,test=<impl_test>`、
  または `pipeline.yml` のパスを渡す（spec-implement が `roles.impl_{kind}` を読む）。
- 記録済み host を `--host-runtime <host_runtime>` で渡し、spec-implement が
  タスクごとにこの行列を適用できるようにする。
- `--review-fallback native-independent` を渡す。これが、single-AI 環境で
  spec-orchestrate を完走させる明示的な境界となる。単体の spec-implement は既定の
  `block` を維持する。
- `kind` が不明・未マップのタスクは spec-code（claude）にフォールバックする —
  spec-implement の文書化済み従来動作。

## 優先 cross-AI review と独立性（定義はここに一元化）

実装成果物の preferred reviewer は実装担当の **反対の AI role** とする。先に preferred
reviewer を決め、それから host-aware 行列で backend を解決する。backend を先に選んでは
ならない。この規則はここで一度だけ定義し、spec-implement が `--roles` マップから
タスク単位で適用するため、オーケストレーターが再実装しない。

| タスク実装担当（kind 由来） | Reviewer AI role |
|--------------------------|------------------|
| `codex` | `claude` |
| `claude` | `codex` |

実装担当と reviewer の各 role に行列を別々に適用する。たとえば Codex host では
Codex implementer が native、Claude reviewer が agent-delegate になる。Claude host
では同じ role の組を agent-delegate と native review で実行する。修正は implementer
role に戻し、再び行列で解決する。agent-delegate のレビューファイルは spec-review
互換なので、既存の修正ループがそのまま消費する。

cross-AI identity は優先だが、必須の不変条件は **実行 instance と文脈の独立性** である。
preferred cross-AI reviewer が利用不能な場合、`native-independent` は次の制御をすべて
満たす場合だけ host AI role を使える。

1. runtime-native reviewer subagent を新規起動する。オーケストレーターや implementer
   instance を使わず、実装会話も resume しない。
2. 成果物 / diff、仕様、レビュー基準だけを渡す。後続ラウンドでは過去の review
   findings と修正概要だけを追加する。
3. write tool を公開せず、reviewer 起動直前とレビュー完了後に1つずつ取得した
   repository change fingerprint を突合する。
   tracked worktree / staged diff の内容と、gitignore 対象外の untracked path / 内容を
   含める。除外するのは `pipeline-config.ja.md` で分類した orchestrator 所有の run-record
   path だけで、`.specs/` 全体を除外してはいけない。対象 fingerprint に変化があれば
   結果を無効とし、通常の workspace drift 手順へ blocked で回す。
4. 再レビューでもセッションレスの新規 reviewer を毎回起動する。
5. レビュー時点の host runtime を含む record を `state.review_fallbacks` に追記し、
   cross-AI 保証が縮退したことを PR 本文へ明記する。実装レビューでは spec-implement が
   構造化 record を返し、オーケストレーターが追記する。worker は pipeline state を
   書かない。

runtime がこれらを保証できなければ reviewer は利用不能として blocked にする。
オーケストレーターまたは implementer 文脈で行う same-AI review は self-review であり、
受理しない。

## 能力フォールバック

すべてのフォールバックで AI role と backend の分離を保つ。review 以外の role 変更は
`state.role_overrides`、独立 review fallback は `state.review_fallbacks` に記録し、
どちらも PR 本文へ記載する。

- **runtime-native subagent が利用不能:** manual は worker role を反対の AI へ
  振り替えるか停止するかを人に確認する。auto は反対側の peer CLI が利用できる場合
  だけ振り替え、使えなければ blocked にする。reviewer は fallback 契約に必要な独立
  native reviewer を作れないため blocked にする。
- **cross-AI peer CLI が利用不能**（スクリプト欠落、exit 2、`tool_unavailable`）:
  review 以外の worker では、manual は role を host AI へ振り替えるか人に確認し、
  auto は host AI へ振り替えて続行する。reviewer にはこの一般 role fallback を使わない。
  spec-orchestrate が `native-independent` を自動適用し、新規 host-native reviewer で
  続行する。その reviewer が利用不能、または workspace へ書き込んだ場合は blocked。
- **host runtime が不明:** Step 0 の manual / auto 規則を使う。host が確定するまで
  どの role も解決しない。

能力フォールバックは arbitration（`stall-detection.ja.md`）の停滞起因の role
入れ替え（`limits.role_swap_max` で上限）とは区別する。

## 契約テスト

spec-orchestrate skill directory から
`bash references/scripts/tests/run_tests.sh` を実行する。tracked fixture は行列4行と
single-AI review の両方向を網羅し、単体の `block` と orchestrate の
`native-independent` を検証する。さらに3 skill の marked matrix を突合し、不正な
`host_runtime` と review-fallback state を拒否することを確認する。

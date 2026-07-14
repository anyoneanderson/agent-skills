# 担当解決（role-dispatch）— 各フェーズを誰が実行するか

各フェーズはロールキー（例: `spec_author`、`e2e_runner`）を名指しする。この
ファイルは、ロールキーを具体的な実行に変換する唯一の場所である: Claude
サブエージェント、または agent-delegate 経由の委譲 Codex 実行。フェーズ指示書は
解決を繰り返さず、このファイルを参照する。

English version: [role-dispatch.md](role-dispatch.md)

## Step 1: roles を読む

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

ロール値は常に `claude` か `codex`。それ以外は設定エラー — 停止して報告する。

## Step 2: バックエンドを解決する

| ロール値 | バックエンド | 起動方法 |
|---------|------------|---------|
| `claude` | Claude サブエージェント | 現行ランタイムでサブエージェントを起動。planner / evaluator は spec-workflow-init が入れる `workflow-planner` / `workflow-evaluator` エージェント定義を使う |
| `codex` | agent-delegate | agent-delegate スクリプトを公開契約どおりに呼ぶ。常に `--target codex` を明示 |

サブエージェント経路は特定の起動ツールを名指ししない。ランタイムが提供する手段で
サブエージェントを走らせる。ツール名をハードコードしない。

**agent-delegate は契約依存。** スクリプトは `agent-delegate/references/contract.md`
（引数 + `report.json` スキーマ）どおりに呼び、内部実装に依存しない。プログラムからの
呼び出しは `--target` を渡すこと。契約上、ネストしたチェーンで環境自己判定に頼るのは
禁止。

## Step 3: 同期 vs detach を選ぶ

呼び出し側は書き込みの有無と具体的な時間根拠から実行形態を決める:

| フェーズ種別 | 形態 | 理由 |
|------------|------|------|
| 仕様生成・修正、implement（コード）、evaluate（E2E）、証跡保存 | 明示的な `--detach` | ファイルを書き込む delegate |
| read-only かつ5分以内に完了する具体的根拠がある spec_review、調査、成果物レビュー | 同期 | 読み取り専用かつ所要時間の根拠がある |
| 5分以内という具体的根拠がないロール | `--detach` | 上限のない同期待機を許可しない |

detach 起動時の取得値（契約どおり）:
```bash
launch="$(agent-delegate.sh --mode <delegate|review> --target codex ... --detach)"
expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
```

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

呼び出し側のタイムアウトは、仕様生成と仕様修正で20分以上、実装と E2E で30分以上とする。
タイムアウト到達時は状態を再評価し、report の不在を失敗へ変換しない。

## フェーズ別の解決

### spec_review（敵対的仕様レビュー）

`spec_reviewer` → agent-delegate `--mode review`（read-only）。
5分以内に完了する具体的根拠がある場合だけ同期実行し、それ以外は `--detach` と上記の expected-run 待機を使う。
ラウンド1で
セッションを作り、ラウンド2以降は state の `threads.spec_reviewer` の
`--resume <thread_id>` で継続する（レビューセッションは read-only で作られ、resume
が保てる sandbox はそれだけ）。

### evaluate（受け入れ試験）

`e2e_runner` → spec-evaluate の同名バックエンド。spec-evaluate の起動時には
**必ず `--backend` で明示**して渡す（spec-evaluate 単体実行時の既定は `self` で、
パイプライン内でこれに頼ると2つの既定が混ざる）。`claude` は evaluator を
サブエージェント（`workflow-evaluator`）で走らせ、`codex` は agent-delegate
`--mode delegate --sandbox workspace-write` で走らせる（review ではない — アプリ
起動とブラウザ操作を伴うため）。spec-evaluate `references/execution-backend.md` 参照。

### implement（機能を作る）

実装タスクをここから1件ずつ差配しない。`impl_*` ロールを spec-implement の
`--roles` 引数として渡し、タスク単位の `kind → 担当` ルーティングは spec-implement
内部に任せる（二重管理をしない）。

- `roles` からマップを組む: `ui=<impl_ui>,backend=<impl_backend>,test=<impl_test>`、
  または `pipeline.yml` のパスを渡す（spec-implement が `roles.impl_{kind}` を読む）。
- `kind` が不明・未マップのタスクは spec-code（claude）にフォールバックする —
  spec-implement の文書化済み従来動作。

## レビュアー反転（定義はここに一元化）

実装成果物のレビュアーは常に実装担当の **反対側** — 「作った本人がレビューしない」。
この規則はここで一度だけ定義し、spec-implement が `--roles` マップからタスク単位で
適用するため、オーケストレーターが再実装しない。

| タスク実装担当（kind 由来） | レビュアー | 仕組み |
|--------------------------|-----------|-------|
| `codex` | `claude` | spec-review（そのまま） |
| `claude` | `codex` | agent-delegate `--mode review`（5分以内という具体的根拠がある場合だけ同期。それ以外は detach） |

修正は実装担当の実行系に戻る: claude は `spec-code --feedback`、codex は
agent-delegate `--mode delegate --detach`（resume）。agent-delegate のレビューファイルは
spec-review 互換なので、既存の修正ループがそのまま消費する。

## peer 利用不能（codex 不在）

`codex` ロールが agent-delegate 利用不能（スクリプト欠落、exit 2、
`tool_unavailable`）で走れない場合:

- **manual:** そのロールを `claude` に振り替えてよいか人に確認する。
- **auto:** `claude` に振り替えて続行し、入れ替えを `state.role_overrides` と PR
  本文に記録する。

これは能力フォールバックであり、arbitration（`stall-detection.ja.md`）の停滞起因の
ロール入れ替え（`limits.role_swap_max` で上限）とは区別する。

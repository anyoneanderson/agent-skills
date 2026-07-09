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

適切な実行形態はフェーズの所要時間で決まる:

| フェーズ種別 | 形態 | 理由 |
|------------|------|------|
| spec_review、成果物レビュー | 同期 | 短い read-only レビュー。呼び出し側が待つ |
| implement（コード）、evaluate（E2E） | `--detach` + `report.json` ポーリング | 同期の約10分上限を通常超える |

detach 実行のポーリング（契約どおり）:
```bash
report="$(agent-delegate.sh --mode <delegate|review> --target codex ... --detach | tail -1)"
until [ -f "$report" ]; do sleep 15; done
status="$(jq -r .status "$report")"   # done | blocked
```

**待ちは待つ側の turn を跨いで生き残らせる。** turn 内の素朴なポーリングは turn
終了とともに消え、`report.json` を誰も見なくなる。待ち方の標準は1つだけで、
バックアップ規則がそれに加わる:

- **標準の待ち方:** `until [ -f "$report" ]` ループを**ホストランタイムの
  バックグラウンドジョブ**として走らせる — turn が終わっても生き続け、コマンド終了時に
  発行元が自動で再起動される形（Claude Code では Bash のバックグラウンド実行）。
  フォアグラウンドのポーリングだけを残して turn を終えない。何も仕掛けずに turn を
  終えない。yield する前に、待っている report パスを run マーカーへ登録する
  （`.specs/.orchestrate-active.json` に `jq '.waiting_report = $p'`。
  `pipeline-config.ja.md` §Run マーカー参照）— watchdog はこれで「正当な待機」と
  「停滞」を区別する。report を回収したら `.waiting_report` を消す。登録の無い
  待機は停滞と区別できず、ブロックされる。
- **バックアップ監視:** サブワーカーが detach 待ちを持つ間、オーケストレーターは同じ
  `report.json` パスに自前のバックグラウンド監視を仕掛ける。バックアップが先に
  発火したら結果ファイルを検証し、停滞したワーカーを起こす（または交代させる）。
  これは任意の保険ではなく標準手順とする。

## フェーズ別の解決

### spec_review（敵対的仕様レビュー）

`spec_reviewer` → agent-delegate `--mode review`（read-only、同期）。ラウンド1で
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
| `claude` | `codex` | agent-delegate `--mode review`（同期） |

修正は実装担当の実行系に戻る: claude は `spec-code --feedback`、codex は
agent-delegate `--mode delegate`（resume）。agent-delegate のレビューファイルは
spec-review 互換なので、既存の修正ループがそのまま消費する。

## peer 利用不能（codex 不在）

`codex` ロールが agent-delegate 利用不能（スクリプト欠落、exit 2、
`tool_unavailable`）で走れない場合:

- **manual:** そのロールを `claude` に振り替えてよいか人に確認する。
- **auto:** `claude` に振り替えて続行し、入れ替えを `state.role_overrides` と PR
  本文に記録する。

これは能力フォールバックであり、arbitration（`stall-detection.ja.md`）の停滞起因の
ロール入れ替え（`limits.role_swap_max` で上限）とは区別する。

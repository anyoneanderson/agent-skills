# 実行基盤 — 指示書は1本、実行の乗り物だけ切り替える

spec-evaluate は evaluator の指示書（`evaluator-prompt.ja.md`）を1本に保ち、
それを走らせる乗り物だけを切り替える。まず evaluator AI role を選び、明示された
host runtime と比較して native / cross-AI 実行を決める。

## 解決順序

1. `--backend {self|claude|codex}` フラグ（指定があれば）。
2. `pipeline.yml` の `roles.e2e_runner`。
3. `self`（単体実行の既定）。

`--backend` は互換性のため残す公開 option 名である。`claude|codex` の値が選ぶのは
AI role であり、実行手段ではない。この role を選ぶ場合は常に
`--host-runtime {claude|codex}` も必要である。オーケストレーターは pipeline state の
記録値を渡し、単体 caller は明示指定するか現在の host を人に確認する。推測しない。
`self` は host を必要としない。

パイプライン外での単体実行は `self` に解決される: 呼び出し元エージェント自身が
evaluator となり、委譲の仕組みは介在しない。人が「この機能を受け入れ試験して」と
言うときのモード。

## Role-to-backend 行列

<!-- dispatch-matrix:start -->
| Host runtime | Evaluator AI role | Backend | agent-delegate target |
|---|---|---|---|
| `codex` | `codex` | `runtime-native` | `-` |
| `codex` | `claude` | `agent-delegate` | `claude` |
| `claude` | `claude` | `runtime-native` | `-` |
| `claude` | `codex` | `agent-delegate` | `codex` |
<!-- dispatch-matrix:end -->

行列を適用するのは `e2e_runner` が確定した後である。host と role が一致する場合は
agent-delegate を起動してはならない。

## 各実行手段

### `self`

現在のエージェントが `evaluator-prompt.ja.md` を実行時コンテキストとともに直接
実行する。何も spawn しない。単一エージェントでの手動実行に使う。

### Runtime-native（`evaluator_role == host_runtime`）

`evaluator-prompt.ja.md` と実行時コンテキストを指示とするサブエージェントを起動
する。アプリ起動・ブラウザ操作・コマンド実行・証跡ファイル書き込みを行うため、
Read・Bash・ブラウザ自動化が使える必要がある。結果ファイルのパスを返す。
インストール済みなら現在の runtime の `workflow-evaluator` 定義を使う。
agent-delegate は起動しない。

### Cross-AI（`evaluator_role != host_runtime`）

evaluator を agent-delegate 経由で走らせる。受け入れ試験はアプリ起動とブラウザ
操作を伴うため書き込み権限が要る:

- **mode `delegate`、sandbox `workspace-write`。** `review` ではない — review
  モードは read-only でアプリを起動・操作できない。
- `--target "$evaluator_role"` を明示的に渡す。agent-delegate の契約により、
  プログラムからの呼び出しは環境変数による自己判定に頼ってはならない。
- 明示的な `--detach` を使い、expected run id と起動時刻を保持する。
  15秒を標準、30秒を上限としてポーリングし、呼び出し側のタイムアウトは30分以上とする。

```bash
# 合成: evaluator-prompt.ja.md + 実行時コンテキスト → 1つの prompt ファイル
launch="$(agent-delegate.sh --mode delegate --target "$evaluator_role" \
  --sandbox workspace-write \
  --prompt-file "$prompt" \
  --out-dir ".specs/$feature/evidence/$round" \
  --detach)"

expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
# 公開契約の状態機械を適用する15秒間隔の永続監視を開始する。
# valid terminal report の通知後: status="$(jq -r .status "$report")"
```

- 各周期では expected-run report、owner、pid、heartbeat、worker/monitor の
  プロセス状態の順に確認する。
  生存中または劣化状態では待機を続け、report の不在だけで失敗にしない。
- `status == done` → evaluator が書いた結果ファイルを読み、spec-evaluate の
  Step 5（証跡の機械検証）に渡す。
- `status == blocked` → 実行が正常に完了していない。`blocker` /
  `blocker_category` を記録し、黙って合格にせず評価失敗として扱う。

## 契約の境界

spec-evaluate が依存するのは agent-delegate の **公開契約** だけ —
agent-delegate の `references/contract.md` に定義された引数一覧と `report.json`
スキーマである。スクリプトの内部実装には依存しない。契約が変わればこのファイルも
変わるが、スクリプト内部の変更は spec-evaluate に影響しない。

## パイプライン vs 単体

- **パイプライン（spec-orchestrate）:** オーケストレーターが
  `roles.e2e_runner` の AI role と記録済み `host_runtime` を渡し、spec-evaluate が
  共通行列を適用する。項目が BLOCKED で戻ったときのエスカレーションも
  オーケストレーターが持つ。
- **単体:** 実行者自身が evaluator。オーケストレーターがいないため、spec-evaluate
  は blocked 項目を呼び出し元に直接報告する。

## 能力フォールバック

- **host 不明:** pipeline manual mode は人に host を確認し、auto mode は state を
  保って blocked にする。単体で `claude` / `codex` を選んだ場合も人に確認する。
  `self` は host 値を必要としない。
- **native subagent 利用不能:** オーケストレーターへ報告する。manual は evaluator
  AI role を変える前に確認し、auto は peer CLI が利用できる場合だけ振り替える。
  使えなければ blocked にする。単体は `self` 利用を人に確認できる。
- **cross-AI peer 利用不能:** オーケストレーターへ報告する。manual は host AI への
  振り替えを確認し、auto は振り替えて override を記録する。単体は `self` を使う前に
  人へ確認する。

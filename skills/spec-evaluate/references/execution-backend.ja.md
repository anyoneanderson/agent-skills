# 実行基盤 — 指示書は1本、実行の乗り物だけ切り替える

spec-evaluate は evaluator の指示書（`evaluator-prompt.ja.md`）を1本に保ち、
それを走らせる乗り物だけを切り替える。「何を試験しどう証明するか」の論理を1箇所に
まとめつつ、同じ受け入れ試験を Claude サブエージェントでも委譲先の別 LLM でも
実行できるようにする。

## 解決順序

1. `--backend {self|claude|codex}` フラグ（指定があれば）。
2. `pipeline.yml` の `roles.e2e_runner`。
3. `self`（単体実行の既定）。

パイプライン外での単体実行は `self` に解決される: 呼び出し元エージェント自身が
evaluator となり、委譲の仕組みは介在しない。人が「この機能を受け入れ試験して」と
言うときのモード。

## 各バックエンド

### `self`

現在のエージェントが `evaluator-prompt.ja.md` を実行時コンテキストとともに直接
実行する。何も spawn しない。単一エージェントでの手動実行に使う。

### `claude`

`evaluator-prompt.ja.md` と実行時コンテキストを指示とするサブエージェントを起動
する。アプリ起動・ブラウザ操作・コマンド実行・証跡ファイル書き込みを行うため、
Read・Bash・ブラウザ自動化が使える必要がある。結果ファイルのパスを返す。

### `codex`（委譲先の別 LLM）

evaluator を agent-delegate 経由で走らせる。受け入れ試験はアプリ起動とブラウザ
操作を伴うため書き込み権限が要る:

- **mode `delegate`、sandbox `workspace-write`。** `review` ではない — review
  モードは read-only でアプリを起動・操作できない。
- `--target codex` を明示的に渡す。agent-delegate の契約により、プログラムからの
  呼び出しは環境変数による自己判定に頼ってはならない。
- `--detach` を使い `report.json` をポーリングする。E2E は同期実行の約10分上限を
  超えるのが通常のため。

```bash
# 合成: evaluator-prompt.ja.md + 実行時コンテキスト → 1つの prompt ファイル
report="$(agent-delegate.sh --mode delegate --target codex \
  --sandbox workspace-write \
  --prompt-file "$prompt" \
  --out-dir ".specs/$feature/evidence/$round" \
  --detach | tail -1)"

until [ -f "$report" ]; do sleep 15; done
status="$(jq -r .status "$report")"
```

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

- **パイプライン（spec-orchestrate）:** オーケストレーターの role-dispatch が
  `roles.e2e_runner` から解決したバックエンドを与える。項目が BLOCKED で戻った
  ときのエスカレーションもオーケストレーターが持つ（manual は人に確認、auto は
  裁定へ回す）。
- **単体:** 実行者自身が evaluator。オーケストレーターがいないため、spec-evaluate
  は blocked 項目を呼び出し元に直接報告する。

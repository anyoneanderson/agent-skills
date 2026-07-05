# フェーズ: evaluate

受け入れテスト計画（test.md）を spec-evaluate で実装済み機能に対し実行し、全項目が
合格するまで implement とループする。不合格項目は spec-review 互換の findings として
戻り、`spec-code --feedback` に渡る。

## 入力

- `test.md`、`pipeline.yml` の `app:` 起動レシピ、ラウンド番号。
- `e2e_runner` ロール → spec-evaluate バックエンド（self / claude サブエージェント /
  agent-delegate `--mode delegate`・workspace-write 経由の codex）。解決は
  `../role-dispatch.ja.md` の「evaluate」。

## アクション

1. spec-evaluate を `--spec .specs/{feature}/` とラウンドで起動する。アプリを起動し、
   各項目を検証方法別に実行し、証跡を `evidence/{round}/` に保存し、
   `evaluate-{round}.md` を書く。
2. 長い E2E は同期上限を超えうる。codex バックエンドは detach し、オーケストレーター
   は結果ファイルをポーリングする。

## 出力

- `evaluate-{round}.md`（要件ID別合否表 + spec-review 互換 findings）と、
  `.specs/{feature}/evidence/{round}/` 配下の証跡ファイル。

## 検証

- **証跡チェック（省略しない）:** PASS と報告された各項目について、証跡ポインタが
  実在・非空のファイルに解決することを確認する。証跡が欠落した PASS は evaluator の
  申告に関わらず FAIL に倒す（NFR-003）。これは spec-evaluate が行い、オーケストレー
  ターは適用されたことを確認する。
- blocked 項目（例: playwright 項目に app レシピがない）は不合格と区別し、黙って
  合格に格上げしない。

## state 更新

- このラウンドを `rounds.evaluate` に追加: pass/fail/blocked 件数、findings 指紋、
  ゲート結果。
- 停滞シグナルを評価する（検知器は T010）。シグナル成立時は `phase` を arbitration
  にする。

## 遷移

- 不合格 findings → **implement**（spec-code --feedback で修正し再試験）
- 全項目合格（Gate PASS）→ **pr**
- 停滞シグナル成立 → **arbitration**（T010 で処理）

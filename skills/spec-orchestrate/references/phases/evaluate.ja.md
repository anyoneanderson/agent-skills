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

- このラウンドを `rounds.evaluate` に **spec_review と同じフィールド形式** で追加し、
  同じ検知器が効くようにする: 各 FAIL 項目を `critical` 件数に、各懸念を
  `improvement` 件数に写像する（blocked はどちらでもない — 不合格ではない）。加えて
  findings 指紋（`../stall-detection.ja.md` に従い、Critical + Improvement のみ）と
  ゲート結果。生の pass/fail/blocked 件数のまま記録すると、S2（`critical +
  improvement` を合算）がこのループを評価できなくなる。
- 停滞シグナル S1〜S3 を評価する（`../stall-detection.ja.md`）。シグナル成立時は
  `phase` を arbitration にする。

## 遷移

- 不合格 findings → **implement**。各 FAIL は Critical、各懸念は Improvement として
  `spec-code --feedback` に渡す（`type: evaluate` の結果は spec-review 互換なので修正
  ループがそのまま消費する）。その後 `round + 1` で再試験。
- 全項目合格（Gate PASS）→ **pr**
- 停滞シグナル成立 → **arbitration**（`../stall-detection.ja.md`）

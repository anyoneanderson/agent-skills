# フェーズ: evaluate

受け入れテスト計画（test.md）を spec-evaluate で実装済み機能に対し実行し、全項目が
合格するまで implement とループする。不合格項目は spec-review 互換の findings として
戻り、`spec-code --feedback` に渡る。

## 入力

- `test.md`、`pipeline.yml` の `app:` 起動レシピ、ラウンド番号。
- `e2e_runner` AI role と記録済み `host_runtime`。解決は
  `../role-dispatch.ja.md` の「evaluate」。spec-evaluate 起動時には role を
  **必ず `--backend` で明示**し、host を `--host-runtime` で渡す。
  spec-evaluate 単体実行時の既定は `self` なので、パイプライン実行に混ぜない。

## アクション

1. spec-evaluate を `--spec .specs/{feature}/` とラウンドで起動する。アプリを起動し、
   各項目を検証方法別に実行し、証跡を `evidence/{round}/` に保存し、
   `evaluate-{round}.md` を書く。
2. evaluator role と host が異なる場合、agent-delegate backend は role を target として
   明示し、`--detach` を渡して expected run id を保持し、`../role-dispatch.ja.md` の
   report-first な15〜30秒待機を適用する。
   呼び出し側のタイムアウトは30分以上とする。
   heartbeat またはプロセス状態が生存を示す間、report の不在は失敗ではなく待機状態である。

## 出力

- `evaluate-{round}.md`（要件ID別合否表 + spec-review 互換 findings）と、
  `.specs/{feature}/evidence/{round}/` 配下の証跡ファイル。

## 検証

- **証跡チェック（省略しない）:** PASS と報告された各項目について、証跡ポインタが
  実在・非空のファイルに解決することを確認する。証跡が欠落した PASS は evaluator の
  申告に関わらず FAIL に倒す。これは spec-evaluate が行い、オーケストレー
  ターは適用されたことを確認する。
- blocked 項目（例: playwright 項目に app レシピがない）は不合格と区別し、黙って
  合格に格上げしない。

## state 更新

- このラウンドを `rounds.evaluate` に **spec_review と同じフィールド形式** で追加し、
  同じ検知器が効くようにする: 各 FAIL 項目を `critical` 件数として、各懸念を
  `improvement` 件数として数える（blocked はどちらでもない — 不合格ではない。件数は
  独立の `blocked` フィールドに記録し、再開時に未検証分が見えるようにする）。加えて
  `fix_required`（このループでは `critical + improvement` — 不合格ケースはすべて修正
  ループを駆動する）、findings 指紋とクラスキー（`../stall-detection.ja.md` に従う）、
  ゲート結果。生の pass/fail/blocked 件数のまま記録すると、S2（`fix_required` を
  監視）がこのループを評価できなくなる。
- 停滞シグナル S1〜S4 を評価する（`../stall-detection.ja.md`）。シグナル成立時は
  `phase` を arbitration にする。

## 遷移

- 不合格 findings → **implement**。各 FAIL は Critical、各懸念は Improvement として
  `spec-code --feedback` に渡す（`type: evaluate` の結果は spec-review 互換なので修正
  ループがそのまま消費する）。その後 `round + 1` で再試験。
- 全項目合格（Gate PASS）→ **pr**
- blocked あり・FAIL なし（blocked のみで Gate FAIL — blocked は `critical` にも
  `improvement` にも数えないため、修正ループに渡すものが無い）→ モード別に処理
  （`../pipeline-config.ja.md` の「app」参照）:
  - manual: 人間に確認する — 不足している app レシピを追加して `round + 1` で再試験、
    または明示的にスキップを受け入れる。
  - auto: `phase` を **arbitration** にする（blocked 項目を `## Unresolved` に列挙した
    draft PR 着地は正当な結末）。無人実行で未検証要件を ready PR に昇格させない。
- 停滞シグナル成立 → **arbitration**（`../stall-detection.ja.md`）

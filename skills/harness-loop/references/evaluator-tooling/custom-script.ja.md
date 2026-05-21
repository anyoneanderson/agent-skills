# Evaluator ツーリング: Custom Script

## Purpose

組み込み tool reference では表現できない検証面を扱うため、sprint 固有の
`.harness/scripts/eval-<feature>.sh` を使う。

## When to choose

- bespoke な検証ハーネスが必要。
- browser 自動化でも curl script でも不十分。
- Evaluator が決定論的な shell entrypoint を定義できる。

## Phase 3 procedure

1. `.harness/scripts/eval-<feature>.sh` を書く。
2. 実行権限を付ける。
3. 必要な contract metadata は stdin または環境変数で渡す。
4. 直接実行し、stdout/stderr を `${SPRINT_DIR}/evidence/iter-<n>/` に保存する。

## Required script contract

- pass 時は `0` で終了。
- fail 時は非 0 で終了。
- 次の Evaluator が再現できるだけの evidence を出力する。
- 汎用化できると判明するまでは sprint-local な script として扱う。

## Prohibited shortcuts

- 無条件 `exit 0` で失敗を隠さない。
- 独立 assertion を足さずに Generator のテストを包むだけの wrapper にしない。
- evidence 保存を省略しない。

## Output expectation

script のパスと保存したログを `feedback/evaluator-<iter>.md` に記録する。

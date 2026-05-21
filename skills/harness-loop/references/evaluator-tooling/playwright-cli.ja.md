# Evaluator ツーリング: Playwright CLI

## Purpose

`${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/` 配下に Evaluator 所有の Playwright spec を書き、
独立した回帰資産として実行する。browser 検証は必要だが MCP が使えない、
あるいは後続 sprint に spec を継承したい時の第一選択。

## When to choose

- browser レベルの契約検証が必要。
- MCP が使えない、または commit される spec の方が都合が良い。
- 将来 sprint に回帰テスト資産を引き継ぎたい。

## Phase 3 procedure

1. `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/<AS>.spec.ts` を作る。
2. acceptance scenario をその spec に直接エンコードする。
3. `pnpm exec playwright test ${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/` を実行する。
4. 失敗時も spec は残し、失敗出力を evidence として添えて次 sprint で再利用できる状態にする。

## Required spec shape

- 実アプリの entrypoint と実際の契約境界を通す。
- acceptance scenario id を spec 名に反映する。
- commit 可能な品質で残す。後続 sprint の regression asset になる。

## Prohibited shortcuts

- `page.route` を使わない。
- `addInitScript` を使わない。
- `window.fetch` を上書きしない。
- 対象契約境界を全面 stub 化したテストにしない。

## Output expectation

spec は `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/` に commit し、
`feedback/evaluator-<iter>.md` には `evidence/iter-<n>/...` のような
sprint-dir 相対 path を記録する。

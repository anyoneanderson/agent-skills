# Evaluator ツーリング: curl

## Purpose

shell script と生の HTTP 呼び出しで API 系 acceptance scenario を検証する。
browser 自動化の価値が低い endpoint 主体のプロジェクトで第一選択。

## When to choose

- 契約境界が HTTP / SSE / webhook である。
- 主なリスクが UI 挙動ではない。
- shell レベルの request で十分に検証できる。

## Phase 3 procedure

1. `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/<AS>.sh` を書く。
2. 正常系を叩く。
3. relevant なら validation 境界、auth failure、timeout、malformed payload
   を含む異常系を最低 1 本は叩く。
4. status、headers、payload shape の証拠を script 横のログに保存する。

## Required script shape

- `#!/usr/bin/env bash`
- `set -euo pipefail`
- status code と payload shape の明示的 assertion
- 正常系と異常系を分離

## Prohibited shortcuts

- happy path 1 本だけで終わらない。
- 生成済み fixture だけで pass 判定しない。
- contract に auth / validation があるのにその経路を省略しない。

## Output expectation

script は `${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/` に commit し、
`feedback/evaluator-<iter>.md` には sprint-dir 相対 path を記録する。

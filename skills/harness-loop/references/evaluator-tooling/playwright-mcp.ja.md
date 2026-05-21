# Evaluator ツーリング: Playwright MCP

## Purpose

`mcp__playwright__browser_*` を使い、dev server を実ユーザーのように操作して
acceptance scenario を再現する。再利用 spec よりも live browser 検証が
重要な時の第一選択。

## When to choose

- プロジェクトに user-facing UI がある。
- Playwright MCP が導入済みで allow-list に入っている。
- a11y snapshot と live interaction の証拠が必要。

## Phase 3 procedure

1. `browser_navigate` で対象 URL を開く。
2. 操作前の a11y tree を `browser_snapshot` で取得する。
3. `browser_type`, `browser_click`, `browser_select_option`,
   `browser_press_key`, `browser_wait_for` でシナリオを実行する。
4. 失敗時は `browser_network_requests`, `browser_console_messages`,
   もう一度 `browser_snapshot` を取得する。
5. contract に validation / auth / timeout / empty-state が絡むなら、
   異常系または境界値の経路も最低 1 本は踏む。

## CLI fallback

`mcp__playwright__*` tools が現在の allow-list 外、または利用不能な場合は
`playwright-cli.ja.md` に従う。Evaluator 自身が
`${SPRINT_DIR}/evidence/iter-<n>/evaluator-tests/` に spec を書き、project ごとの該当 command
（例: `pnpm exec playwright test`）で実行し、screenshot / log を sprint 配下の
`${SPRINT_DIR}/evidence/iter-<n>/` に保存する。保存 path は sprint-dir 相対で
`feedback/evaluator-<iter>-report.json.evidence_refs` に記録する。

## Evidence to save

- アクセシビリティスナップショット
- Console ログ
- Network request ログ
- a11y tree だけでは足りない場合に限り screenshot

## Prohibited shortcuts

- Generator が書いたテストを pass 根拠にしない。
- screenshot だけで live behavior を代替しない。
- 自分で契約境界を踏まずに pass を宣言しない。

## Output expectation

保存した artifact のパスを `feedback/evaluator-<iter>.md` の `Evidence` に記録する。

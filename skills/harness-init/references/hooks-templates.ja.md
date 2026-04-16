# Hooks テンプレ集

`.claude/settings.json` 用の 3 段階の強制レベル。`harness-init` がヒアリング時の「hook level」回答に基づいて選択する。

**重要（ASM-005）**: Claude Code の hooks は入力を **stdin の JSON** で受け取る。`$TOOL_NAME` や `$FILE_PATH` のような環境変数は注入されない。すべてのスクリプトは `jq` でフィールドを抽出する。

以下で参照するスクリプトは `harness-init` 実行後に `.harness/scripts/` 配下に配置される。スクリプト本体は T-015 を参照。

---

## Level: minimal

観測のみ。ブロックなし。信頼できるチーム、または初期探索フェーズ用。

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**カバー範囲**:
- 全 Edit / Write で `.harness/progress.md` に 1 行 append
- `_state.json.completed == false` かつ Principal Skinner 非該当時、`Stop` hook が loop プロンプトを再注入

**カバーしない**:
- Tier-A 破壊的操作はスルー
- 未許可 MCP サーバー呼び出し可能
- `/compact` 後の自動復元なし

---

## Level: warn

観測 + リスキー操作のログ記録。ブロックせず記録のみ。strict に移行する前にプロジェクトの実挙動を学ぶフェーズ向け。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/tier-a-guard.sh --warn-only" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/restore-after-compact.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**カバー範囲**:
- `minimal` の全機能
- Tier-A パターン（rm -rf / force-push 等）を検出し `.harness/progress.md` にログ、**ブロックはしない**
- compact 時に progress.md + _state.json から自動復元

---

## Level: strict

完全強制。Tier-A 操作と未許可 MCP 呼び出しをブロックする。autonomous / autonomous-ralph モード（REQ-078）で人間の監視がない環境用。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/tier-a-guard.sh" }
        ]
      },
      {
        "matcher": "mcp__.*",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/mcp-allowlist.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/restore-after-compact.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**カバー範囲**:
- `warn` の全機能
- Tier-A パターン（`.harness/tier-a-patterns.txt` から）を **deny** し `_state.json.pending_human = true` に設定（REQ-081 / REQ-082）
- MCP 呼び出しを `_config.yml.allowed_mcp_servers` と照合し未登録なら deny（REQ-101）

**autonomous モードでは必須**: `continuous` / `autonomous-ralph` / `scheduled`。`interactive` モードでは人間が異常を拾えるので `warn` まで緩めてもよい。

---

## 速度階層（NFR-005）

Hook は 4 層防御のミリ秒層:

| 層 | レイテンシ | 機構 | 強制する内容 |
|---|---|---|---|
| Hook | ms | 本ファイル | 破壊操作 deny、state dump、compact 復元 |
| pre-commit | 秒 | `lefthook` / husky | フォーマッタ、速い lint、シークレットスキャン |
| Skill | 分 | spec-review / spec-test | Rubric 採点、acceptance scenario |
| CI | 時 | GitHub Actions | 全テストマトリクス、遅い E2E、publish ゲート |

`harness-init` が書くのは **Hook 層のみ**。他層はスコープ外（プロジェクト側で用意）。

---

## マージ挙動

`harness-init` は既存の `.claude/settings.json` を決して上書きしない:

1. 既存の `hooks` ブロックを読む
2. 追加 / 置換するパッチを算出
3. `diff` を AskUserQuestion でユーザに提示
4. 承認後のみ適用
5. 拒否された場合は `.claude/settings.harness.json.proposed` に書いて停止

他スキルや手動で追加された hooks を踏み潰してはならない。

---

## インストール検証

`harness-init` 完了後、以下で検証:

```bash
# 1. jq が使えること
command -v jq >/dev/null || echo "ERROR: jq required"

# 2. 参照される全スクリプトが存在かつ実行可能であること
for s in .harness/scripts/*.sh; do
  [ -x "$s" ] || echo "NOT EXECUTABLE: $s"
done

# 3. PostToolUse hook を dry-run
echo '{"tool_name":"Write","tool_input":{"file_path":"dummy.txt"}}' \
  | .harness/scripts/progress-append.sh
tail -1 .harness/progress.md

# 4. tier-a-guard を dry-run（state を汚染しないよう HARNESS_TEST_MODE=1 必須）
#    フラグ無しで実行すると _state.json.pending_human=true が立ち
#    progress.md に TIER-A MATCH 行が追記されるので、インストール検証時は
#    必ずこのフラグを使うこと。
echo '{"tool_input":{"command":"rm -rf /tmp/dummy"}}' \
  | HARNESS_TEST_MODE=1 .harness/scripts/tier-a-guard.sh
# 期待値: {"decision":"deny", ..., "test_mode":true}
# _state.json と progress.md は変化しない。

# 5. mcp-allowlist を dry-run（読み取りのみ、追加フラグ不要）
echo '{"tool_name":"mcp__not-in-list__x"}' \
  | .harness/scripts/mcp-allowlist.sh
# 期待値: {"decision":"deny", ...}
```

完全なインストール検証は T-054（E2E）で実施する。

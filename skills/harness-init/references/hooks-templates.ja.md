# Hooks テンプレ集

`.claude/settings.json` 用の 3 段階の強制レベル。`harness-init` がヒアリング時の「hook level」回答に基づいて選択する。

**重要**: Claude Code の hooks は入力を **stdin の JSON** で受け取る。`$TOOL_NAME` や `$FILE_PATH` のような環境変数は注入されない。すべてのスクリプトは `jq` でフィールドを抽出する。

以下で参照するスクリプトは `harness-init` 実行後に `.harness/scripts/` 配下に配置される。

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

完全強制。Tier-A 操作と未許可 MCP 呼び出しをブロックする。autonomous / autonomous-ralph モードで人間の監視がない環境用。

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
- Tier-A パターン（`.harness/tier-a-patterns.txt` から）を **deny** し `_state.json.pending_human = true` に設定
- MCP 呼び出しを `_config.yml.allowed_mcp_servers` と照合し未登録なら deny

**autonomous モードでは必須**: `continuous` / `autonomous-ralph` / `scheduled`。`interactive` モードでは人間が異常を拾えるので `warn` まで緩めてもよい。

---

## Codex 側 hooks（generator_backend ∈ {codex_plugin, codex_cmux}）

Generator が Codex で動く時、Claude Code の `PostToolUse(Edit|Write)` hook は Codex の内部 tool call を観測できない（Issue #46 で実機確認）。この穴を塞ぐため、`harness-init` は **Codex 側にも hook set** を `<project>/.codex/hooks.json` に設置する。これらの hook は Codex が Bash tool を呼ぶとき（または session 開始時）に Codex の hook runner 内で動く。

**スコープ**: Codex hook は 2026-04 時点で `Bash` tool のみ intercept 可能（https://developers.openai.com/codex/hooks 参照）。Write / MCP / WebSearch は未対応。ファイル書き込み観測は `.harness/scripts/codex-progress-bridge.sh` が担当する — Codex の `feedback/generator-<iter>-report.json` を読んで `progress.md` に代行記録。

### 生成ファイル（backend ∈ codex_plugin, codex_cmux）

```
<project>/.codex/
├── config.toml                              # [features] codex_hooks=true を追記
├── hooks.json                               # Codex hook 登録
└── hooks/
    ├── inject-harness-context.sh            # SessionStart(startup|resume)
    ├── tier-a-guard-codex.sh                # PreToolUse(Bash) — Tier-A 二重ガード
    └── codex-bash-log.sh                    # PostToolUse(Bash) — bash 結果を progress.md に
```

### `hooks.json` 形式

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/inject-harness-context.sh",
          "timeout": 5
        }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/tier-a-guard-codex.sh",
          "timeout": 5
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/codex-bash-log.sh",
          "timeout": 5
        }]
      }
    ]
  }
}
```

`harness-init` が install 時に `<PROJECT_ROOT>` を絶対パスに解決する（Codex を子ディレクトリから起動してもパスが効く）。

### 各 Codex hook の役割

| Hook | Event | 役割 |
|---|---|---|
| `inject-harness-context.sh` | `SessionStart(startup\|resume)` | `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` を stdout で返し、`.harness/progress.md` の tail と `_state.json` サマリを developer context として Codex の fresh thread に注入 |
| `tier-a-guard-codex.sh` | `PreToolUse(Bash)` | Claude 側 Tier-A ガードのミラー。Codex が走らせようとしている Bash を `.harness/tier-a-patterns.txt` と照合、match したら Codex の `permissionDecision: "deny"` を返して block |
| `codex-bash-log.sh` | `PostToolUse(Bash)` | Codex の全 Bash 実行（test / build / lint 等）を exit code 付きで `.harness/progress.md` に追記。block はしない（fail open） |

### `config.toml` への追記

`harness-init` は `<project>/.codex/config.toml` に非破壊 append:

```toml
[features]
codex_hooks = true
```

既存ファイルがなければ新規作成。`[features]` が既存なら `codex_hooks` のみ追加し他エントリは保全。

### Claude 側 hook との共存

Codex 側 hook は Claude 側 hook を**置き換えない**。`harness-init` は Claude `.claude/settings.json` 側も従来通り全部入れる（strict / warn / minimal 選択に応じて）。両側が独立に発火:

- Claude session の Bash / Edit / Write → Claude hook 発火
- Codex subprocess の Bash → Codex hook 発火（Claude 側は silent）
- Codex subprocess の Write → どちらも発火しない（bridge script で補完）

### Future Work

Codex の `PostToolUse` matcher が `Write` / `Edit` / MCP / WebSearch に拡張されたら、Orchestrator bridge は簡略化できる（Codex hook 自身が touched file を記録）。それまでは bridge + report.json が真実。Issue #46 "Future Work" で追跡。

---

## 速度階層

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

完全なインストール検証は harness-suite の E2E テスト計画で実施する。

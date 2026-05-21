# settings.json 非破壊マージ

`.claude/settings.json` にユーザや他スキルが書いたエントリを壊さずに
harness hooks を注入するためのアルゴリズム。

## 入力

- `existing`: 現在の `.claude/settings.json`（存在しない or 空 `{}` もあり得る）
- `patch`: 選択された hook_level に対応するパッチブロック
  （[hooks-templates.ja.md](hooks-templates.ja.md)）

## 出力

次のいずれか：

- `applied`: ユーザ承認後に `.claude/settings.json` を更新
- `proposed`: 承認されず `.claude/settings.harness.json.proposed` に保存
- `unchanged`: パッチが既存の部分集合で変更なし

## アルゴリズム

```
1. existing が無い or 空:
     merged := patch
     → (6)

2. existing を JSON パース。失敗:
     行番号付きでエラーし、既存ファイルは絶対に壊さず終了。

3. merged := deep-copy(existing)
   merged.hooks オブジェクトが無ければ作る。

4. patch.hooks の各イベント（PreToolUse / PostToolUse / Stop / SessionStart）:
     if merged.hooks[event] が無い:
         merged.hooks[event] := patch.hooks[event]
         continue

     # 既存あり — matcher 単位でマージ
     patch.hooks[event] の各 matcher_entry:
         merged 側に同じ matcher があるか探索

         無ければ:
             merged.hooks[event] に append
         あれば:
             command 文字列単位で重複除去しつつ append

5. deep-equal(merged, existing):
     return "unchanged"

6. diff := unified-diff(existing, merged)  # 表示用

7. AskUserQuestion（バイリンガル）:
     "Apply this hooks patch to .claude/settings.json? / この hooks パッチを適用しますか？"
     options:
       - "Apply" / "適用"
       - "Save as .proposed and stop" / ".proposed として保存して中断"
       - "Cancel harness-init" / "harness-init を中止"

8. "Apply" 選択:
     atomic-write（tempfile + rename）で .claude/settings.json 更新
     return "applied"
   "Save as .proposed" 選択:
     .claude/settings.harness.json.proposed に保存
     return "proposed"
   "Cancel" 選択:
     部分状態警告つきで harness-init を中止。
```

## 比較ルール

- イベントキー（`PreToolUse` など）は大文字小文字区別の完全一致
- matcher 文字列（`"Edit|Write"` や `"Bash"`）はオペークな文字列として比較
  （正規化しない）。`"Write|Edit"` と `"Edit|Write"` は別物として両方残す
- command の重複除去は `command` フィールドの完全一致比較

## before / after 例

**existing**:
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-linter.sh" } ] }
    ]
  }
}
```

**patch**（minimal）:
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": ".harness/scripts/progress-append.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": ".harness/scripts/stop-guard.sh" } ] }
    ]
  }
}
```

**merged**（両 matcher 保持・Stop 追加）:
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-linter.sh" } ] },
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": ".harness/scripts/progress-append.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": ".harness/scripts/stop-guard.sh" } ] }
    ]
  }
}
```

## 非破壊が必要な理由

`.claude/settings.json` は共有領域（ユーザ・他スキル・権限・env 変数・モデル
指定などが同居）。上書きすると無音で他の設定を破壊する。matcher 単位の
マージで全て残しつつ harness ポリシーを適用する。

ユーザが後から harness を外したければ `.harness/scripts/*` を指す command
エントリのみ削除すれば良い（他の hooks はそのまま残る）。

## hooks 以外のキー

`permissions` / `env` / `model` / `theme` / 他のカスタムキーはすべて
そのまま保持する。触るのは `hooks` のみ。

## Atomic write

```bash
tmp=$(mktemp "$(dirname .claude/settings.json)/.settings.XXXXXX")
printf '%s\n' "$merged_json" > "$tmp"
mv "$tmp" .claude/settings.json
```

truncate-then-write は禁止（途中失敗で壊れた JSON が残り、以降の Claude
Code セッションが全滅する）。

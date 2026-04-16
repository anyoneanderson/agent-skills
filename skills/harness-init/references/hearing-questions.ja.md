# ヒアリング質問集

`harness-init` が使う AskUserQuestion テキストの正本。全オプション文字列はバイリンガル（`"English / 日本語"`）形式（NFR-003）。AGENTS.md に従い、各 AskUserQuestion ラウンドは 1〜4 問・各問 2〜4 オプションを提示。"Other" オプションは暗黙に利用可能、入力はそのまま受理する。

`(Recommended)` マーカーは説明ではなくオプション名に付与（UI 上に表示されるため）。

## Prerequisites 質問（Round 1 の前）

`docs/coding-rules.md` / `docs/review_rules.md` / `docs/issue-to-pr-workflow.md` のいずれかが不在の場合、Round 1 に入る**前**に以下を尋ねる（SKILL.md §Prerequisites / ASM-008）:

```
question: "Shared rules files are missing under docs/. Proceed anyway?" /
          "docs/ の共有ルールファイルが不在です。続行しますか？"

options:
  - name: "Run /spec-rules-init first (Recommended) / 先に /spec-rules-init を実行（推奨）"
    description: "harness-init を中断して共有基盤を先に生成。その後 harness-init を再開"
  - name: "Proceed without them (reduced rubric coverage) / 無しで続行（rubric カバレッジ低下）"
    description: "harness は動作するが Evaluator の Craft 軸「coding-rules 遵守」は採点対象外になる"
```

「先に /spec-rules-init を実行（推奨）」が選ばれたら案内を出して生成を行わず停止。「無しで続行」が選ばれたら Round 1 に進み、`_config.yml` に `shared_foundation: missing` を付記して runtime で Craft 軸採点を適応させる。

---

## Round 1 — プロジェクト種別

```
question: "What kind of project is this harness being installed into?" /
          "このハーネスを導入するプロジェクトはどのタイプですか？"

options:
  - name: "Web (UI present) (Recommended) / Web（UIあり）（推奨）"
    description: "HTML/CSS/JS、モバイル Web、SPA 等。Web rubric プリセット（Functionality/Craft/Design/Originality）を使用"
  - name: "API / バックエンド API"
    description: "UI なし、HTTP/gRPC/GraphQL バックエンド。API rubric（Functionality/Craft/Consistency/Documentation）を使用"
  - name: "CLI / コマンドラインツール"
    description: "人間または CI から呼ばれる CLI。CLI rubric（Functionality/Craft/Ergonomics/Documentation）を使用"
  - name: "Other / その他"
    description: "自由記述。rubric は Web プリセットをデフォルトとし、sprint ごとに調整"
```

**Config key**: `project_type` ∈ `web|api|cli|other`
**後続影響**: `references/rubric-presets.md` の rubric プリセットを選択

---

## Round 2 — Generator バックエンド

```
question: "Which backend should the Generator agent use?" /
          "Generator エージェントはどのバックエンドを使いますか？"

options:
  - name: "Claude (same process) (Recommended) / Claude（同一プロセス）（推奨）"
    description: "最もシンプル。外部依存なし。GAN ループのモデル多様性は低い"
  - name: "Codex via cmux / Codex（cmux 経由）"
    description: "別 cmux ペインで Codex CLI に委譲（cmux 必須）。GAN 敵対性が最も強い"
  - name: "Codex plugin / Codex プラグイン"
    description: "Claude Code プラグイン経由で Codex を inline 利用（プラグインインストール要）"
  - name: "Other MCP / 他の MCP"
    description: "MCP ツール経由の独自バックエンド。後で generator.md を手動編集"
```

**Config key**: `generator_backend` ∈ `claude|codex_cmux|codex_plugin|other`
**フォールバック**（REQ-060）: `codex_cmux` 選択時に実行時 `cmux` が見つからなければ `harness-loop` は `claude` へ自動フォールバックし `progress.md` に警告を記録

---

## Round 3 — Evaluator ツール

```
question: "Which tools will the Evaluator use to run acceptance scenarios?" /
          "Evaluator はどのツールで acceptance scenario を検証しますか？"
（複数選択可）

options:
  - name: "Playwright (a11y snapshot) (Recommended for web) / Playwright（a11y スナップショット）（Web 推奨）"
    description: "決定論的ブラウザ自動化。画面キャプチャ比較よりアクセシビリティツリー（DOM の構造的スナップショット）を優先"
  - name: "pytest / pytest"
    description: "Python ベースのテストランナー。テスト対象サービスの言語に関わらず、任意の HTTP/API に適用可能"
  - name: "curl / curl"
    description: "生の HTTP チェック。API スモーク用途"
  - name: "Custom script / 独自スクリプト"
    description: "Evaluator が sprint ごとに `.harness/scripts/eval-<feature>.sh` を生成・実行します"
```

**Config key**: `evaluator_tools`（リスト）
**制約**: 最低 1 つは選択必須。Web プロジェクトは `[playwright]` + 追加選択がデフォルト

---

## Round 4 — cmux 利用可能性

```
question: "Is cmux available in your environment?" /
          "この環境で cmux は利用できますか？"

options:
  - name: "Yes — use when helpful / はい。必要時に利用"
    description: "並列 sub-agent と Codex 委譲を有効化。実行時に cmux が無ければ自動 degrade"
  - name: "No / いいえ"
    description: "全エージェントが同一プロセスで逐次実行。複数 feature sprint でやや遅くなるが機能は完全"
```

**Config key**: `cmux_available`（bool）
**注意**: Round 2 で `codex_cmux` を選んで本問で "No" の場合は検証エラーを出して Round 2 に戻す

---

## Round 5 — Hook 強制レベル

```
question: "How strictly should hooks enforce safety?" /
          "hooks の強制レベルはどれにしますか？"

options:
  - name: "Strict — 破壊的コマンドを自動ブロック (Recommended for autonomous modes) / Strict — 破壊的コマンドを自動ブロック（autonomous モード推奨）"
    description: "破壊操作を拒否、未許可の MCP は拒否、全編集をログに記録。autonomous-ralph: 反復ごとにセッションリセット（夜間放置向け）。自動巡回モード・scheduled には必須"
  - name: "warn / warn"
    description: "リスキー操作をログするがブロックしない。strict 移行前にプロジェクトの実挙動を学ぶフェーズ向け"
  - name: "minimal / minimal"
    description: "観測のみ。progress.md append + Stop guard のみ。信頼できるチーム / 初期探索向け"
```

**Config key**: `hook_level` ∈ `strict|warn|minimal`
**制約**: `harness-loop` の autonomous モード（自動巡回モード）は `strict` 必須。`minimal` を選ぶと `harness-loop` は interactive モードに強制遷移

---

## Round 6 — Issue / PR トラッカー

```
question: "Which issue/PR tracker should harness-plan and harness-loop use?" /
          "Issue / PR のトラッカーはどれですか？"

options:
  - name: "GitHub (Recommended) / GitHub（推奨）"
    description: "`gh` CLI を使用。`gh auth status` が有効であること"
  - name: "GitLab / GitLab"
    description: "v2 予定。v1 では shared_state.md のみに記録"
  - name: "None / なし"
    description: "台帳のみ。sprint 進捗は .harness/ と git に記録、外部 ticket なし"
```

**Config key**: `tracker` ∈ `github|gitlab|none`
**効果**: `harness-plan` Step 6 と `harness-loop` PR 作成が本値で分岐。`none` なら `gh` 呼び出しの代わりに `shared_state.md` に PR メタデータを記録

---

## Round 7 — 自動停止リミッター（Principal Skinner）・コスト上限・MCP allow-list

このラウンドは AskUserQuestion 1 回で 4 サブ質問をまとめて聞く（スキーマ上限 4）。デフォルトは夜間実行にも安全な値。

```
question: "Set auto-stop safety limits, cost cap, and MCP allow-list (Principal Skinner)" /
          "自動停止リミッター・コスト上限・MCP allow-list を設定します（Principal Skinner）"

sub-questions:
  - key: max_iterations
    prompt: "Max iterations per sprint before forced stop?" /
            "スプリント毎の iteration 上限（強制停止）?"
    default: 8
    range: [2, 32]

  - key: max_wall_time_sec
    prompt: "Max elapsed time (wall-clock) per sprint (seconds)?" /
            "スプリント毎の経過時間の上限（秒）?"
    default: 28800   # 8 時間
    range: [600, 86400]

  - key: max_cost_usd
    prompt: "Max cumulative cost per sprint (USD)?" /
            "スプリント毎の累計コスト上限（USD）?"
    default: 20.0
    range: [1.0, 500.0]

  - key: allowed_mcp_servers
    prompt: "Which MCP servers may the agents call? (comma-separated)" /
            "エージェントが呼び出して良い MCP サーバー（カンマ区切り）?"
    default: "playwright, github"
    hint: "strict モードではここに無いものは拒否される"
```

**書き込まれる config keys**: `max_iterations`, `max_wall_time_sec`, `max_cost_usd`, `allowed_mcp_servers`（リスト）。加えて定数 `rubric_stagnation_n: 3` も書く（質問はせず固定、design §9.7）

### 配線

Round 7 の各回答は特定のランタイム消費者へ流れる：

| 回答項目 | `_config.yml` キー | 消費者 | 強制 |
|---|---|---|---|
| max_iterations | `max_iterations` | `.harness/scripts/stop-guard.sh` | Principal Skinner — `_state.json.iteration >= max` で stop 許可 |
| max_wall_time_sec | `max_wall_time_sec` | `stop-guard.sh` | 経過時間 `now − _state.json.start_time >= max` で stop 許可 |
| max_cost_usd | `max_cost_usd` | `stop-guard.sh` | `_state.json.cumulative_cost_usd >= max` で stop 許可 |
| allowed_mcp_servers | `allowed_mcp_servers` | `.harness/scripts/mcp-allowlist.sh` | strict hook_level のみ — `mcp__<server>__*` のうち `<server>` が不在なら deny |
| （定数） | `rubric_stagnation_n: 3` | `stop-guard.sh` | `_state.json.rubric_stagnation_count >= n` で stop 許可 |

state キー名は `references/resilience-schema.ja.md` §\_state.json に準拠。

更新パス：

- `harness-init` Step 2 が `.harness/_config.yml` に atomic に書き込む
- `harness-loop` がスプリント中に対応する `_state.json` フィールド
  （`iteration`, `start_time`, `cumulative_cost_usd`, `rubric_stagnation_count`）を維持
- `harness-rules-update` は完了済みスプリント後にのみ上限を引き上げ可能
  （スプリント途中の変更は Principal Skinner 迂回に繋がるため禁止）

**入力値検証**: `range` 外が入力された場合は範囲をエラー文に付けて 1 度だけ
再質問する。それでも範囲外を押し通す場合は受理するが `_config.yml` の当該行に
`⚠ out-of-recommended-range` コメントを付記する。

---

## サマリ

7 ラウンド全て終わった後、`harness-init` Step 2 が `_config.yml` を書く。順序は `SKILL.md` §Step 1 と一致。

ユーザが任意ラウンドで "Other" を選択した場合、その自由記述テキストを最終値として受理する（AGENTS.md "Handling Other Option Responses" 準拠）。本当に曖昧な場合を除き追加質問しない。

## デフォルトスキップモード（将来）

`--defaults` フラグ（v2）は全 7 ラウンドをスキップし以下を適用:
`web / claude / [playwright] / cmux=false / strict / github / 8 / 28800 / 20 / [playwright, github]`
v1 では未実装（ヒアリングこそが本スキルの核）

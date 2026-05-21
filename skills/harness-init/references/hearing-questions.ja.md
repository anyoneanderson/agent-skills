# ヒアリング質問集

`harness-init` が使う AskUserQuestion テキストの正本。全オプション文字列はバイリンガル（`"English / 日本語"`）形式。AGENTS.md に従い、各 AskUserQuestion ラウンドは 1〜4 問・各問 2〜4 オプションを提示。"Other" オプションは暗黙に利用可能、入力はそのまま受理する。

`(Recommended)` マーカーは説明ではなくオプション名に付与（UI 上に表示されるため）。

## Prerequisites 質問（Round 1 の前）

`docs/coding-rules.md` / `docs/review_rules.md` / `docs/issue-to-pr-workflow.md` のいずれかが不在の場合、Round 1 に入る**前**に以下を尋ねる（SKILL.md §Prerequisites）:

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
    description: "HTML/CSS/JS、モバイル Web、SPA 等。Web の採点基準 (rubric) プリセット（Functionality / Craft / Design / Originality）を使用"
  - name: "API / バックエンド API"
    description: "UI なし、HTTP/gRPC/GraphQL バックエンド。API の採点基準 (rubric)（Functionality / Craft / Consistency / Documentation）を使用"
  - name: "CLI / コマンドラインツール"
    description: "人間または CI から呼ばれる CLI。CLI の採点基準 (rubric)（Functionality / Craft / Ergonomics / Documentation）を使用"
  - name: "Other / その他"
    description: "自由記述。採点基準 (rubric) は Web プリセットをデフォルトとし、sprint ごとに調整"
```

**Config key**: `project_type` ∈ `web|api|cli|other`
**後続影響**: `references/rubric-presets.md` の rubric プリセットを選択

---

## Round 2 — Generator バックエンド

```
question: "Which backend should the Generator agent use?" /
          "Generator エージェントはどのバックエンドを使いますか？"

options:
Options を出す前に `harness-init` が Codex CLI とプラグインの存在を検出する（SKILL.md Step 8 参照）:

- `codex --version` が失敗 → `codex_cli` / `codex_cmux` を option から除外し、`npm install -g @openai/codex` を案内

  - name: "Codex CLI (Recommended) / Codex CLI（推奨）"
    description: "Codex（gpt-5.4）を `codex exec --sandbox danger-full-access` で Generator として使う標準経路。plugin 非依存で、network と workspace 外 write が必要な foundation sprint でも詰まりにくい。Orchestrator が dispatch script で最終メッセージと Git 差分を正規化する"
  - name: "Claude (同一プロセス) / Claude（同一プロセス）"
    description: "最もシンプル。外部依存なし。G も E も Claude のためモデル多様性が低く、GAN の敵対圧が最も弱い。baseline / fallback 用途"
  - name: "Codex via cmux (visibility mode) / Codex（cmux 経由、可視モード）"
    description: "Codex CLI と同じ role contract だが、Codex は cmux 委譲 pane で動き、人間が挙動を watch できる。長時間 sprint で動きを見たい時、Codex debug 時に有用。Codex CLI + cmux-delegate skill 必要"
  - name: "Other MCP / 他の MCP"
    description: "MCP ツール経由の独自バックエンド。後で generator.md / .codex/agents/generator.toml を手動編集、2 ファイル出力プロトコル（narrative + report.json）は共通"
```

**Config key**: `generator_backend` ∈ `claude|codex_cli|codex_cmux|other`

---

## Round 3 — Evaluator ツール

```
question: "Which tools should the Evaluator use for Phase 3 (runtime verification)?" /
          "Evaluator は Phase 3 (runtime verification) にどのツールを使いますか？"
（multiSelect=true; primary → fallback の順に 1 つ以上選択）

options:
  - name: "Playwright MCP (a11y snapshot, live user simulation) (Recommended for web) / Playwright MCP（a11y スナップショット、ライブ操作）（Web 推奨）"
    description: "Evaluator が `mcp__playwright__browser_*` を使って dev server を人間のように操作する。Playwright MCP 導入済み環境で live 検証したい時に最適"
  - name: "Playwright CLI (independent spec, no stubs) / Playwright CLI（独立 spec、stub 禁止）"
    description: "Evaluator 自身が `evidence/evaluator-tests/` に `.spec.ts` を書き、`page.route` / `addInitScript` / `window.fetch` 上書きなしで実行し、回帰資産として残す"
  - name: "Cypress / Cypress"
    description: "project の既定 E2E tool が Cypress の場合、Evaluator が Cypress で runtime check を書く"
  - name: "curl / curl"
    description: "生の HTTP 呼び出しと shell script で契約境界を検証する。ブラウザ自動化の価値が低い API 専用プロジェクト向け"
  - name: "Custom script / 独自スクリプト"
    description: "組み込み tool reference では表現しきれない場合に、Evaluator が `.harness/scripts/eval-<feature>.sh` を自作して実行する"
```

**Config key**: `evaluator_tools`（リスト）
**制約**: primary → fallback の順序を持つリストとして保存する。Web project
では `[playwright-mcp, playwright-cli]` を推奨、API project は
`[curl, custom-script]`、CLI project は `[custom-script]` が目安。許可値は
`playwright-mcp` / `playwright-cli` / `cypress` / `curl` /
`custom-script`。

**Render note**: Step 2 は選択順を `_config.yml` に書く。空回答なら
`evaluator_tools: []`。project 固有 default は template ではなく deploy 後の
config に置く。

---

## Round 4 — Hook 強制レベル

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

## Round 5 — Issue / PR トラッカー

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

## Round 6 — 自動停止リミッター・コスト上限・MCP allow-list

このラウンドは AskUserQuestion 1 回で 4 サブ質問をまとめて聞く（スキーマ上限 4）。デフォルトは夜間実行にも安全な値。

```
question: "Set auto-stop safety limits, cost cap, and MCP allow-list" /
          "自動停止リミッター・コスト上限・MCP allow-list を設定します"

sub-questions:
  - key: max_iterations
    prompt: "Max iterations per sprint before forced stop?" /
            "スプリント毎の iteration 上限（強制停止）は？"
    default: 8
    range: [2, 32]
    options:
      - name: "8 (Recommended) / 8（推奨）"
        description: "夜間放置にも安全なデフォルト。自動停止リミッターの基準値"
      - name: "4"
        description: "短い sprint 向け。コスト最大削減"
      - name: "16"
        description: "長い探索が必要な sprint 向け"
      - name: "32"
        description: "最大値。人の監視下でのみ推奨"

  - key: max_wall_time_sec
    prompt: "Max elapsed time (wall-clock) per sprint (seconds)?" /
            "スプリント毎の経過時間上限（wall-clock）は？"
    default: 28800   # 8 時間
    range: [600, 86400]
    options:
      - name: "8h (28800s) (Recommended) / 8時間（推奨）"
        description: "夜間放置に適したデフォルト"
      - name: "2h (7200s)"
        description: "短い sprint 向け"
      - name: "4h (14400s)"
        description: "半日サイズ"
      - name: "24h (86400s)"
        description: "最大値。人の監視下でのみ推奨"

  - key: max_cost_usd
    prompt: "Max cumulative cost per sprint (USD)?" /
            "スプリント毎の累計コスト上限（USD）は？"
    default: 20.0
    range: [1.0, 500.0]
    options:
      - name: "$20 (Recommended) / $20（推奨）"
        description: "一般的な sprint のデフォルト"
      - name: "$5"
        description: "セーフティ最優先"
      - name: "$50"
        description: "大きめな sprint 向け"
      - name: "$100"
        description: "最大級。人の監視下でのみ推奨"

  - key: allowed_mcp_servers
    prompt: "Which MCP servers may the agents call?" /
            "エージェントが呼び出して良い MCP サーバーは？"
    default: "playwright, github"
    hint: "strict モードではここに無いものは拒否される。ワイルドカード選択で全許可もできる（信頼できる単独開発向け）"
    options:
      - name: "playwright (Recommended) / playwright（Web 推奨）"
        description: "Evaluator が a11y スナップショットに使用"
      - name: "github / github"
        description: "gh または MCP 経由で Issue / PR 操作"
      - name: "登録されている全てのMCP (*) / All installed MCP servers (*)"
        description: "ワイルドカード。全 MCP サーバーを許可。`.harness/scripts/mcp-allowlist.sh` は `[\"*\"]` を allow-all として扱い、progress.md に 1 回だけリスク注記を残す。信頼できる単独開発プロジェクト向け"
      - name: "独自リスト / Custom list"
        description: "カンマ区切りで指定（例: `playwright, github, context7`）"
```

**書き込まれる config keys**: `max_iterations`, `max_wall_time_sec`, `max_cost_usd`, `allowed_mcp_servers`（リスト）。加えて定数 `rubric_stagnation_n: 3` も書く（質問はせず固定、design §9.7）

### 配線

Round 6 の各回答は特定のランタイム消費者へ流れる：

| 回答項目 | `_config.yml` キー | 消費者 | 強制 |
|---|---|---|---|
| max_iterations | `max_iterations` | `.harness/scripts/stop-guard.sh` | 自動停止リミッター — `_state.json.iteration >= max` で stop 許可 |
| max_wall_time_sec | `max_wall_time_sec` | `stop-guard.sh` | 経過時間 `now − _state.json.start_time >= max` で stop 許可 |
| max_cost_usd | `max_cost_usd` | `stop-guard.sh` | `_state.json.cumulative_cost_usd >= max` で stop 許可 |
| allowed_mcp_servers | `allowed_mcp_servers` | `.harness/scripts/mcp-allowlist.sh` | strict hook_level のみ — `mcp__<server>__*` のうち `<server>` が不在なら deny。センチネル `["*"]` で全許可（progress.md に 1 回だけリスク注記）|
| （定数） | `rubric_stagnation_n: 3` | `stop-guard.sh` | `_state.json.rubric_stagnation_count >= n` で stop 許可 |

state キー名は `references/resilience-schema.ja.md` §\_state.json に準拠。

更新パス：

- `harness-init` Step 2 が `.harness/_config.yml` に atomic に書き込む
- `harness-loop` がスプリント中に対応する `_state.json` フィールド
  （`iteration`, `start_time`, `cumulative_cost_usd`, `rubric_stagnation_count`）を維持
- `harness-rules-update` は完了済みスプリント後にのみ上限を引き上げ可能
  （スプリント途中の変更は自動停止の迂回に繋がるため禁止）

**入力値検証**: `range` 外が入力された場合は範囲をエラー文に付けて 1 度だけ
再質問する。それでも範囲外を押し通す場合は受理するが `_config.yml` の当該行に
`⚠ out-of-recommended-range` コメントを付記する。

---

## サマリ

6 ラウンド全て終わった後、`harness-init` Step 2 が `_config.yml` を書く。順序は `SKILL.md` §Step 1 と一致。

ユーザが任意ラウンドで "Other" を選択した場合、その自由記述テキストを最終値として受理する（AGENTS.md "Handling Other Option Responses" 準拠）。本当に曖昧な場合を除き追加質問しない。

## デフォルトスキップモード（将来）

`--defaults` フラグ（v2）は全 6 ラウンドをスキップし以下を適用:
`web / claude / [playwright] / strict / github / 8 / 28800 / 20 / [playwright, github]`
v1 では未実装（ヒアリングこそが本スキルの核）

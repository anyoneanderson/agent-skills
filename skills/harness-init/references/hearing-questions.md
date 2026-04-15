# Hearing Questions

Canonical AskUserQuestion text used by `harness-init`. All option strings
are bilingual (`"English / 日本語"`) per NFR-003. Per AGENTS.md, each
AskUserQuestion round presents 1–4 questions with 2–4 options each; the
"Other" option is implicitly available and should be honoured as-is.

The `(Recommended)` marker is appended to the option name — not the
description — so it surfaces in the UI.

## Prerequisites prompt (pre-Round 1)

If `docs/coding-rules.md`, `docs/review_rules.md`, or
`docs/issue-to-pr-workflow.md` is missing, ask this **before** Round 1
(per SKILL.md §Prerequisites / ASM-008):

```
question: "Shared rules files are missing under docs/. Proceed anyway?" /
          "docs/ の共有ルールファイルが不在です。続行しますか？"

options:
  - name: "Run /spec-rules-init first (Recommended) / 先に /spec-rules-init を実行（推奨）"
    description: "Stops harness-init so you can generate the shared substrate; resume harness-init afterwards."
  - name: "Proceed without them (reduced rubric coverage) / 無しで続行（rubric カバレッジ低下）"
    description: "harness still functions; Evaluator skips the Craft 'coding-rules adherence' criterion."
```

If the user picks "Run /spec-rules-init first", surface the guidance and
halt without generating. If "Proceed without them", continue to Round 1
and annotate `_config.yml` with `shared_foundation: missing` so Craft
axis scoring adapts at runtime.

---

## Round 1 — Project type

```
question: "What kind of project is this harness being installed into?" /
          "このハーネスを導入するプロジェクトはどのタイプですか？"

options:
  - name: "Web (UI present) (Recommended) / Web（UIあり）（推奨）"
    description: "HTML/CSS/JS, mobile web, SPAs. Uses Web rubric preset (Functionality/Craft/Design/Originality)."
  - name: "API / バックエンド API"
    description: "HTTP/gRPC/GraphQL backend without UI. Uses API rubric (Functionality/Craft/Consistency/Documentation)."
  - name: "CLI / コマンドラインツール"
    description: "Command-line tool invoked by humans or CI. Uses CLI rubric (Functionality/Craft/Ergonomics/Documentation)."
  - name: "Other / その他"
    description: "Free-form. Rubric will default to Web preset; adjust per sprint."
```

**Config key**: `project_type` ∈ `web|api|cli|other`
**Downstream effect**: Selects rubric preset in `references/rubric-presets.md`.

---

## Round 2 — Generator backend

```
question: "Which backend should the Generator agent use?" /
          "Generator エージェントはどのバックエンドを使いますか？"

options:
  - name: "Claude (same process) (Recommended) / Claude（同一プロセス）（推奨）"
    description: "Simplest. No external dependencies. Lower model diversity for GAN loop."
  - name: "Codex via cmux / Codex（cmux 経由）"
    description: "Delegate to Codex CLI in a separate cmux pane (requires cmux). Best GAN adversariality."
  - name: "Codex plugin / Codex プラグイン"
    description: "Use a Claude Code plugin that exposes Codex inline. Requires the plugin to be installed."
  - name: "Other MCP / 他の MCP"
    description: "Custom backend via MCP tool. You'll edit generator.md by hand afterwards."
```

**Config key**: `generator_backend` ∈ `claude|codex_cmux|codex_plugin|other`
**Fallback** (REQ-060): If `codex_cmux` is chosen but `cmux` command is
not found at runtime, `harness-loop` falls back to `claude` and logs a
warning to `progress.md`.

---

## Round 3 — Evaluator tools

```
question: "Which tools will the Evaluator use to run acceptance scenarios?" /
          "Evaluator はどのツールで acceptance scenario を検証しますか？"
(multi-select allowed)

options:
  - name: "Playwright (a11y snapshot) (Recommended for web) / Playwright（a11y スナップショット）（Web 推奨）"
    description: "Deterministic browser automation. Prefer a11y tree over screenshot diff (NFR-007)."
  - name: "pytest / pytest"
    description: "Python test runner. Good for API/lib."
  - name: "curl / curl"
    description: "Raw HTTP checks. Simple API smoke tests."
  - name: "Custom script / 独自スクリプト"
    description: "Run `.harness/scripts/eval-<feature>.sh` per sprint."
```

**Config key**: `evaluator_tools` (list)
**Constraint**: At least one tool must be selected. Web projects default to
`[playwright]` + any extras.

---

## Round 4 — cmux availability

```
question: "Is cmux available in your environment?" /
          "この環境で cmux は利用できますか？"

options:
  - name: "Yes — use when helpful / はい。必要時に利用"
    description: "Enables parallel sub-agents and Codex delegation. Skill will detect and degrade gracefully if cmux is missing at runtime."
  - name: "No / いいえ"
    description: "All agents run sequentially in the same process. Still functional; slightly slower for multi-feature sprints."
```

**Config key**: `cmux_available` (bool)
**Note**: If Round 2 chose `codex_cmux` but this answer is "No", surface a
validation error and return to Round 2.

---

## Round 5 — Hook enforcement level

```
question: "How strictly should hooks enforce safety?" /
          "hooks の強制レベルはどれにしますか？"

options:
  - name: "strict (Recommended for autonomous modes) / strict（autonomous モード推奨）"
    description: "Deny Tier-A destructive ops, deny non-allow-listed MCP, log every edit. Required for autonomous-ralph / scheduled."
  - name: "warn / warn"
    description: "Log risky ops but do not block. Good for learning your project's behaviour before committing to strict."
  - name: "minimal / minimal"
    description: "Observation only. Only progress.md append + Stop guard. Trusted teams, early exploration."
```

**Config key**: `hook_level` ∈ `strict|warn|minimal`
**Constraint**: autonomous modes in `harness-loop` require `strict`. If the
user picks `minimal` here, `harness-loop` will force interactive mode.

---

## Round 6 — Issue/PR tracker

```
question: "Which issue/PR tracker should harness-plan and harness-loop use?" /
          "Issue / PR のトラッカーはどれですか？"

options:
  - name: "GitHub (Recommended) / GitHub（推奨）"
    description: "Uses `gh` CLI. Requires `gh auth status` to be valid."
  - name: "GitLab / GitLab"
    description: "v2 planned. v1 will record to shared_state.md only."
  - name: "None / なし"
    description: "Ledger-only. Sprint progress lives in .harness/ and git; no external tickets."
```

**Config key**: `tracker` ∈ `github|gitlab|none`
**Effect**: `harness-plan` Step 6 and `harness-loop` PR creation are
gated on this. If `none`, they write PR metadata to `shared_state.md`
instead of calling `gh`.

---

## Round 7 — Principal Skinner limits, cost cap, and MCP allow-list

This round asks four quick questions in one AskUserQuestion batch (the
schema allows up to 4). Defaults are safe for overnight runs.

```
question: "Set Principal Skinner limits, cost cap, and MCP allow-list" /
          "Principal Skinner 閾値・コスト上限・MCP allow-list を設定します"

sub-questions:
  - key: max_iterations
    prompt: "Max iterations per sprint before forced stop?" /
            "スプリント毎の iteration 上限（強制停止）?"
    default: 8
    range: [2, 32]

  - key: max_wall_time_sec
    prompt: "Max wall-clock time per sprint (seconds)?" /
            "スプリント毎の壁時計上限（秒）?"
    default: 28800   # 8 hours
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
    hint: "Anything not listed here will be denied in strict mode (REQ-101)."
```

**Config keys written**: `max_iterations`, `max_wall_time_sec`,
`max_cost_usd`, `allowed_mcp_servers` (list). Also writes the constant
`rubric_stagnation_n: 3` — not asked, baked in (`design §9.7`).

### Wiring (T-016)

Each Round 7 answer flows to a specific runtime consumer:

| Answer | `_config.yml` key | Consumer | Enforcement |
|---|---|---|---|
| max_iterations | `max_iterations` | `.harness/scripts/stop-guard.sh` | Principal Skinner — allow stop when `_state.json.iteration >= max` |
| max_wall_time_sec | `max_wall_time_sec` | `stop-guard.sh` | Allow stop when `now − _state.json.start_time >= max` |
| max_cost_usd | `max_cost_usd` | `stop-guard.sh` | Allow stop when `_state.json.cumulative_cost_usd >= max` |
| allowed_mcp_servers | `allowed_mcp_servers` | `.harness/scripts/mcp-allowlist.sh` | strict hook_level only — deny `mcp__<server>__*` if `<server>` not in list |
| (constant) | `rubric_stagnation_n: 3` | `stop-guard.sh` | Allow stop when `_state.json.rubric_stagnation_count >= n` |

State-key names follow `references/resilience-schema.md` §\_state.json.

Update paths:

- `harness-init` Step 2 writes these to `.harness/_config.yml` atomically.
- `harness-loop` maintains the corresponding `_state.json` fields
  (`iteration`, `start_time`, `cumulative_cost_usd`, `rubric_stagnation_count`)
  during each sprint.
- `harness-rules-update` may raise caps only after a completed sprint (never
  mid-sprint) to avoid Principal Skinner evasion.

**Input validation**: if the user types a value outside the stated `range`,
re-ask once with the range in the error message. If they insist on an
out-of-range value, accept it but append `⚠ out-of-recommended-range` to
that line in `_config.yml` as a comment.

---

## Summary

After all 7 rounds, `harness-init` Step 2 writes the full `_config.yml`.
The order above matches the order defined in `SKILL.md` §Step 1.

If the user selects "Other" at any round, accept the free-form text as
the final value (see AGENTS.md "Handling Other Option Responses") and do
not ask follow-ups unless the input is genuinely ambiguous.

## Skip-to-defaults Mode (future)

A `--defaults` flag (v2) will skip all 7 rounds and apply:
`web / claude / [playwright] / cmux=false / strict / github / 8 / 28800 / 20 / [playwright, github]`.
Not implemented in v1 by design — the hearing is the point.

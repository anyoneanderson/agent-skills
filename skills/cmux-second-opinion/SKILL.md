---
name: cmux-second-opinion
description: |
  Get a second opinion on code or specifications from a different AI agent via cmux.
  Default reviewer: Codex (or Claude Code if parent is Codex). Supports custom agents.
  Uses review_rules.md as review criteria when available.

  Requires cmux session (CMUX_SOCKET_PATH must be set).

  English triggers: "second opinion", "get another review", "have Codex review this"
  日本語トリガー: 「セカンドオピニオン」「別のAIにレビューしてもらって」「Codexにレビューさせて」
  Slash command: /cmux-second-opinion
license: MIT
allowed-tools:
  - Bash(cmux *)
  - Bash(echo $CMUX_SOCKET_PATH)
  - Bash(which *)
  - Bash(sleep *)
  - Bash(git diff*)
  - Bash(cat *)
  - Bash(find *)
  - Bash(ls *)
---

# cmux-second-opinion — Second Opinion from Another AI

Get an independent code or spec review from a different AI agent in a separate cmux workspace.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/second-opinion-guide.ja.md`
3. English input → English output, use `references/second-opinion-guide.md`
4. Explicit override takes priority

## Prerequisites

**BEFORE requesting a second opinion, verify cmux environment:**

```bash
echo $CMUX_SOCKET_PATH
```

- If empty or unset → stop with error:
  - EN: "Error: Not running inside a cmux session. Please start Claude Code from within cmux."
  - JA: "エラー: cmux セッション内で実行されていません。cmux 内で Claude Code を起動してください。"
- If set → proceed

## Review Type Detection

Determine the review type from user input:

| User Input Pattern | Type |
|---|---|
| "review this diff", "code review", "この変更をレビュー", "diff を見て" | code |
| "review specs", "spec review", "仕様書をレビュー", ".specs/ を見て" | spec |
| *(ambiguous)* | Ask user to clarify |

## Review Criteria Mode

Determine how to use review_rules.md:

| Mode | review_rules.md | Additional Instruction | Trigger |
|---|---|---|---|
| Default | Pass to reviewer | "Also share any issues you notice beyond these rules" | *(no mode specified)* |
| No criteria | Do not pass | "Review freely from your own perspective" | "freely", "自由にレビュー", "ルールなしで" |
| Criteria only | Pass to reviewer | *(none — strictly follow rules)* | "strictly", "ルールに従って", "基準のみ" |

**Detect review_rules.md:**

```bash
find . -name "review_rules.md" -maxdepth 3 2>/dev/null
```

If not found → automatically fall back to "No criteria" mode.

## Agent Selection

Select a reviewer that differs from the parent agent to ensure a different perspective.

| Parent Agent | Default Reviewer | Auto-Approve Command |
|---|---|---|
| Claude Code | Codex | `codex --dangerously-bypass-approvals-and-sandbox` |
| Codex | Claude Code | `claude --dangerously-skip-permissions` |
| *(unknown)* | Ask user | — |

User can override: "have Claude review this", "Gemini にレビューさせて", etc.

**Verify reviewer is available:**

```bash
which codex    # or whichever agent was selected
```

## Code Review Flow

### Step 1: Get Diff

```bash
# Staged + unstaged changes vs HEAD
git diff HEAD

# Or vs base branch (if on a feature branch)
git diff main...HEAD
```

If diff is empty → error: "No changes to review." / "レビュー対象の変更がありません。"

### Step 2: Build Review Prompt

Construct the prompt **in the same language as the user's input** (auto-detected via Language Rules). The reviewer should receive instructions and produce output in that language.

**Default mode (English):**
```
Review the following code changes.
## Review Criteria
{content of review_rules.md}
In addition to the above criteria, share any issues you notice from your own perspective.
## Diff
{diff content}
## Output Format
### Critical (must fix)
### Improvements
### Good points
```

**Default mode (日本語):**
```
以下のコード変更をレビューしてください。
## レビュー基準
{review_rules.md の内容}
上記の基準に加えて、独自の視点で気づいた点があれば指摘してください。
## 変更差分
{diff の内容}
## 出力形式
### 重大（修正必須）
### 改善提案
### 良い点
```

**No criteria mode (EN):**
```
Review the following code changes from your own perspective.
Focus on code quality, security, performance, and best practices.
## Diff
{diff content}
## Output Format
### Critical (must fix) / ### Improvements / ### Good points
```

**No criteria mode (JA):**
```
以下のコード変更を自由な視点でレビューしてください。
コード品質、セキュリティ、パフォーマンス、ベストプラクティスの観点でお願いします。
## 変更差分
{diff の内容}
## 出力形式
### 重大（修正必須） / ### 改善提案 / ### 良い点
```

**Criteria only mode:** Same as default but without the "also share" / "独自の視点" instruction.

### Step 3: Launch Reviewer, Send Prompt, Collect Results

1. Create surface: `cmux new-split right` → extract surface handle from output (`OK surface:{N} workspace:{N}`)
   - **Do NOT use `cmux new-workspace`** — it may create a non-terminal surface that cannot receive commands. Use `cmux new-split right` (or `down`) instead.
2. Launch reviewer: `cmux send --surface surface:{N} "{reviewer_command}\n"`
3. Detect prompt: poll with `cmux read-screen` (3s intervals, 15s timeout)
4. Send review prompt: `cmux send` + `cmux send-key return`
5. Monitor completion: graduated polling (5s → 10s → 30s)
6. Collect results: `cmux read-screen --surface surface:{N} --scrollback`
7. Cleanup: `cmux close-surface --surface surface:{N}` (after collecting)

## Spec Review Flow

### Step 1: Locate Spec Files

```bash
ls .specs/{feature}/requirement.md .specs/{feature}/design.md .specs/{feature}/tasks.md 2>/dev/null
```

If no spec files found → error: "Spec files not found." / "仕様書が見つかりません。"

If `{feature}` is not specified, scan `.specs/` and ask user to select.

### Step 2: Build Review Prompt

Construct in the **same language as user input** (per Language Rules).

**English:**
```
Review the following specification documents.
{if default or criteria-only mode}
## Review Criteria
{content of review_rules.md} (apply relevant review perspectives only)
{end}
## Specifications
### requirement.md / ### design.md / ### tasks.md
{contents}
## Review Perspectives
- Missing or contradictory requirements?
- Design consistent with requirements?
- Task breakdown appropriate?
- Technically infeasible aspects?
- Security concerns?
## Output Format
### Critical Issues / ### Improvements / ### Good Points
```

**日本語:**
```
以下の仕様書をレビューしてください。
{if デフォルト or 基準のみモード}
## レビュー基準
{review_rules.md の内容}（該当する観点のみ適用）
{end}
## 仕様書
### requirement.md / ### design.md / ### tasks.md
{内容}
## レビュー観点
- 要件の漏れ・矛盾はないか
- 設計と要件の整合性はあるか
- タスク分解は適切か
- 技術的に実現困難な点はないか
- セキュリティ上の懸念はないか
## 出力形式
### 重大な問題 / ### 改善提案 / ### 良い点
```

**Important:** Do NOT pass inspection-report.md to the reviewer. The value of a second opinion is an independent perspective.

### Step 3: Launch, Send, Collect

Same as Code Review Flow Step 3 (use `cmux new-split right`, not `new-workspace`).

## Result Report

After collecting the reviewer's output, structure it **in the same language as user input**:

**English:**
```markdown
## Second Opinion Result
**Reviewer**: {agent_name} | **Type**: {code / spec} | **Criteria Mode**: {mode}
### Summary
- Critical: {n} / Improvements: {n} / Good points: {n}
### Critical (Must Fix) / ### Improvements / ### Good Points
```

**日本語:**
```markdown
## セカンドオピニオン結果
**レビュアー**: {agent_name} | **種別**: {code / spec} | **基準モード**: {mode}
### サマリー
- 重大: {n} 件 / 改善提案: {n} 件 / 良い点: {n} 件
### 重大（修正必須） / ### 改善提案 / ### 良い点
```

Report to the user in the parent session.

## Error Handling

| Situation | Response |
|---|---|
| `CMUX_SOCKET_PATH` not set | Error: not in cmux session |
| Reviewer agent not installed | Error + suggest alternative agent |
| Diff is empty | Error: no changes to review |
| Spec files not found | Error: spec directory not found |
| Reviewer fails to start | Report error; suggest checking the pane |
| Reviewer crashes during review | Collect partial output; report what was captured |
| review_rules.md not found | Fall back to "no criteria" mode (not an error) |

## Notes

- This skill provides the **mechanism** for second opinions. Review quality depends on the reviewer agent's capabilities.
- For general task delegation (not review-specific), use `cmux-delegate`.
- For conversation forking, use `cmux-fork`.
- For detailed usage examples and troubleshooting, see the reference guide.

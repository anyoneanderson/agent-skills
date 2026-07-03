---
name: agent-delegate
description: |
  Delegate a task to, or get an adversarial review from, the other AI agent
  (Codex from Claude Code, or Claude Code from Codex) via a headless CLI call —
  no cmux required. Returns a normalized report.json the caller can parse.
  Use for task hand-off, code/spec review, and second opinions in environments
  without cmux.

  English triggers: "delegate to Codex", "have Codex review this", "second opinion without cmux", "run this on the other agent"
  日本語トリガー: 「Codex に投げて」「Codex にレビューさせて」「セカンドオピニオン」「もう一方のエージェントで実行して」
  Slash command: /agent-delegate
license: MIT
---

# agent-delegate — Headless Delegation and Review Between Agents

Hand a task to the other agent, or get an independent adversarial review, by
calling its CLI headlessly. This is the cmux-free counterpart to cmux-delegate
and cmux-second-opinion: it needs only a git repository and the peer CLI
installed, and it returns a machine-readable `report.json`.

The runnable interface is `references/scripts/agent-delegate.sh`. Its full
argument and output contract is in [references/contract.md](references/contract.md)
(日本語: [contract.ja.md](references/contract.ja.md)). Upper skills call the
script directly; this SKILL.md is the interactive entry point for humans.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/*.ja.md`
3. English input → English output, use `references/*.md`
4. Explicit override takes priority (e.g., "in English", "日本語で")

## Prerequisites

- Run inside a **git repository** (touchedFiles measurement degrades outside one).
- The **peer CLI must be installed**: `codex` when running under Claude Code,
  `claude` when running under Codex.
- Codex direction only: the workspace must be **trusted** in `~/.codex/config.toml`.
  The script stops with exit 2 and instructions if it is not.

The script self-detects the host agent. If it cannot (neither `CLAUDECODE` nor a
Codex runtime marker is set), pass `--target <codex|claude>` explicitly.

## Request Type Detection

Determine what the user wants from their phrasing:

| User input pattern | Mode |
|---|---|
| "delegate this", "have Codex do X", "Codex に実装させて", "投げて" | `delegate` |
| "review this", "second opinion", "レビューさせて", "セカンドオピニオン" | `review` |
| *(ambiguous)* | Ask with AskUserQuestion |

When ambiguous, ask with bilingual options:

- question: "What should the other agent do?" / "もう一方のエージェントに何をさせますか？"
- options:
  - "Delegate a task" / "タスクを委譲" — hand off work and collect the result
  - "Adversarial review" / "敵対的レビュー" — read-only review, structured findings

## Execution Flow

### Step 1: Summarize the request

Restate the task or review scope in one or two sentences so the user can confirm
what will be sent. Identify the direction (which peer will run).

### Step 2: Build the prompt file

Write the full instruction for the peer to a file (e.g. under the out-dir), and
pass it with `--prompt-file`. Never inline a long prompt as an argument.

- For `delegate`: describe the task, the acceptance criteria, and any constraints.
- For `review`: describe the review target (diff, spec paths, focus areas). The
  script prepends the adversarial template automatically; your file supplies only
  the context. If a `review_rules.md` exists in the project, include its contents
  as review criteria and tell the reviewer to also raise issues beyond those
  rules — matching the cmux-second-opinion behavior. Detect it with:

  ```bash
  find . -name "review_rules.md" -maxdepth 3 2>/dev/null
  ```

  If none is found, ask the reviewer to review freely.

### Step 3: Choose synchronous or detached

| Task | Mode |
|---|---|
| Review, investigation, short delegation (< ~10 min) | synchronous |
| Code implementation, E2E, anything likely > ~10 min | `--detach` |

A synchronous call blocks until `report.json` is written. `--detach` returns
immediately and prints the future `report.json` path; poll for the file.

### Step 4: Run the script

```bash
# Synchronous delegate (Claude Code → Codex, default full-access sandbox)
report="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode delegate --prompt-file <prompt> --out-dir <out> --label <slug> | tail -1)"

# Adversarial review (always read-only)
report="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode review --prompt-file <context> --out-dir <out> --label <slug> | tail -1)"

# Long task, detached — poll for the report
report="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode delegate --prompt-file <prompt> --out-dir <out> --label <slug> --detach | tail -1)"
until [ -f "$report" ]; do sleep 15; done
```

The last line of stdout is always the `report.json` path.

### Step 5: Read the report and present the result

Read `report.json` and summarize for the user in their language:

- `status` — `done` or `blocked`.
- `summary` — the peer's final message headline.
- `touchedFiles` — files the peer changed (script-measured, authoritative).
- For review: read `artifacts.review_file`; report the Gate (PASS/FAIL) and the
  Critical / Improvement / Minor counts.
- If `blocked`: report `blocker` and `blocker_category`, and suggest a next step
  (e.g. resume, fix the trust setting, retry).

To continue a session, re-run with `--resume <thread_id>` from the prior report
(same sandbox stage; see contract.md for the constraints).

## Error Handling

| Situation | Response |
|---|---|
| Peer CLI not installed | Script exits 2; report which CLI to install |
| Not self-detectable | Ask which side to target, pass `--target` |
| Codex workspace untrusted | Script exits 2 with the config snippet to add |
| Prompt file missing | Script exits 2; check the path |
| Not in a git repository | Warning; touchedFiles will be empty (delegate still runs) |
| Review output malformed | `status: blocked`, `blocker_category: malformed_output`; retry or inspect `artifacts.last_message` |
| read-only review touched files | `status: blocked`, `blocker_category: sandbox_violation`; the sandbox is misconfigured |
| Detached run died | Monitor synthesizes a `blocked` report (`env_error`); inspect the stderr artifact |

## Notes

- This skill provides the **mechanism**. Result quality depends on the peer agent.
- For cmux-based delegation and review, use `cmux-delegate` / `cmux-second-opinion`.
  Use agent-delegate when cmux is not available or a parseable report is needed.
- The `report.json` schema, sandbox mapping, resume rules, and the read-only
  guarantee-level difference between directions are documented in
  [references/contract.md](references/contract.md).

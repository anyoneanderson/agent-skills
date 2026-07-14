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
| File-writing delegation, specification generation or repair, code implementation, E2E, or test-evidence recording | explicit `--detach` |
| Read-only review, investigation, or short delegation with a concrete basis for finishing within 5 minutes and no file writes | synchronous |
| Any task without that concrete 5-minute basis | `--detach` |

A synchronous call blocks until `report.json` is written. `--detach` returns
immediately and prints the run id followed by the future `report.json` path.
Save both as the expected run. Poll every 15 seconds by default, never less
often than every 30 seconds, and follow the expected-run state machine in
`references/contract.md`: validate the report first, then inspect owner, pid,
heartbeat, and process state. A missing report while the run is alive is not a
failure. Caller-owned timeouts must be at least 20 minutes for specification
work and 30 minutes for implementation or E2E.

### Step 4: Run the script

```bash
# Synchronous read-only delegate with a concrete <=5-minute basis
report="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode delegate --prompt-file <prompt> --out-dir <out> --label <slug> | tail -1)"

# Adversarial review with a concrete <=5-minute basis (always read-only)
report="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode review --prompt-file <context> --out-dir <out> --label <slug> | tail -1)"

# Writing or otherwise unbounded task, detached
launch="$(skills/agent-delegate/references/scripts/agent-delegate.sh \
  --mode delegate --prompt-file <prompt> --out-dir <out> --label <slug> --detach)"
expected_run_id="$(printf '%s\n' "$launch" | sed -n 's/^run_id: //p')"
report="$(printf '%s\n' "$launch" | tail -1)"
# Register a durable 15-second watcher that applies the contract state machine.
```

The last line of stdout is always the `report.json` path. A successful launch
also prints `run_id: <uuid>` immediately before it.

### Step 5: Read the report and present the result

Read `report.json` and summarize for the user in their language:

- `status` — `done` or `blocked`.
- `summary` — the peer's final message headline.
- `touchedFiles` — files the peer changed (script-measured, authoritative).
- For review: read `artifacts.review_file` and validate it in this order —
  the script verifies structure only, so never adopt the `Gate` line at face
  value (see `references/adversarial-review-prompt.md`):
  1. Every Critical / Improvement finding carries a `fix_before` tag whose
     value is in the **stage list in effect** — the four default values, or
     the ordered list the review context supplied instead (the prompt template
     tells the reviewer to use that list). A finding with a missing or
     out-of-list tag is **malformed output** (treat as blocked; re-run or
     inspect) — do not compute a gate from it, or an untagged Critical would
     silently pass.
  2. Recompute the Gate from the tags — FAIL iff at least one finding carries
     the **gate-blocking stage**: the first stage of the list in effect
     (`implementation` by default). A `Gate` line that contradicts this tally
     is also malformed output.
  3. Report the recomputed Gate, the Critical / Improvement / Minor counts,
     and the gate-blocking-stage count.
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
- Codex under the `workspace-write` sandbox may refuse to write agent-config dot
  directories (`.agents/`, `.claude/`), reporting `writing outside of the
  project`; this can occur with repo layouts that include symlinks. When a task's
  edits target those directories, prefer assigning it to claude.

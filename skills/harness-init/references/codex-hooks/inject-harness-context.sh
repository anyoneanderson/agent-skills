#!/usr/bin/env bash
# inject-harness-context.sh — Codex SessionStart hook (matcher: startup|resume)
#
# Called by Codex at session start. We inject harness state (progress.md
# tail + _state.json summary) as developer context so Codex's fresh
# thread knows where the loop is and what files to read.
#
# Output contract:
#   stdout JSON with hookSpecificOutput.additionalContext (preferred), or
#   plain text stdout (also valid; Codex docs treat it as developer
#   context additions).
# Exit: 0 on success. Non-zero only on real failure (we prefer to fail
# open so we don't stall Codex — missing files just produce empty
# context).

set -eu

PROGRESS_FILE=".harness/progress.md"
STATE_FILE=".harness/_state.json"

# Resolve from CLAUDE_PROJECT_DIR / input.cwd / pwd. Codex hook input on
# stdin is JSON; we grep cwd from it if provided.
payload="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "${cwd:-}" ] && cd "$cwd" 2>/dev/null || true

# If we cannot see a .harness dir, emit nothing (fail open).
[ -d ".harness" ] || { printf '{}\n'; exit 0; }

progress_tail=""
if [ -f "$PROGRESS_FILE" ]; then
  progress_tail="$(tail -n 100 "$PROGRESS_FILE" 2>/dev/null || true)"
fi

state_summary=""
if [ -f "$STATE_FILE" ]; then
  state_summary="$(jq -r '
    "current_epic=" + (.current_epic // "null|null")
    + " sprint=" + ((.current_sprint // 0) | tostring)
    + " phase=" + (.phase // "null")
    + " iteration=" + ((.iteration // 0) | tostring)
    + " last_agent=" + (.last_agent // "null")
    + " pending_human=" + ((.pending_human // false) | tostring)
    + " aborted_reason=" + (.aborted_reason // "null")
  ' "$STATE_FILE" 2>/dev/null || true)"
fi

# Build the additional context string. Keep under 4KB to be polite to
# Codex's prompt budget; progress tail is the main value so we include
# it verbatim.
context="Harness state summary (from .harness/_state.json):
${state_summary}

Recent progress (tail 100 lines of .harness/progress.md):
${progress_tail}

You are operating under /harness-loop. Read the files under
.harness/<current_epic>/sprints/sprint-<current_sprint>-*/ for your
contract and prior feedback before acting."

# Emit as Codex SessionStart hookSpecificOutput JSON.
jq -n --arg ctx "$context" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

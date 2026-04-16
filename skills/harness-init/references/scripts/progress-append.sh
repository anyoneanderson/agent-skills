#!/usr/bin/env bash
# progress-append.sh — PostToolUse hook (matcher: Edit|Write)
#
# Appends one line to .harness/progress.md describing the tool invocation.
# Input: Claude Code hook JSON on stdin (no env vars — all context read
# from the payload).
# Output: nothing on success. Never blocks; exits 0 unless catastrophic.

set -euo pipefail

PROGRESS_FILE=".harness/progress.md"
mkdir -p "$(dirname "$PROGRESS_FILE")"
[ -f "$PROGRESS_FILE" ] || printf '# Harness progress log (append-only)\n\n' > "$PROGRESS_FILE"

payload="$(cat)"
[ -n "$payload" ] || exit 0

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"')"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
phase="$(jq -r '.phase // "unknown"' .harness/_state.json 2>/dev/null || printf 'unknown')"
agent="${HARNESS_AGENT:-claude}"

line="- ${ts} | agent=${agent} | phase=${phase} | ${tool_name}"
[ -n "$file_path" ] && line+=" | ${file_path}"
printf '%s\n' "$line" >> "$PROGRESS_FILE"

exit 0

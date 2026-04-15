#!/usr/bin/env bash
# restore-after-compact.sh — SessionStart hook (matcher: compact)
#
# After /compact, Claude Code's context has been re-summarised. Re-inject the
# Boot Sequence essentials so the agent can resume without losing state:
#   - tail of .harness/progress.md (worklog)
#   - full .harness/_state.json (canonical state)
# Output goes to stdout — Claude Code reads it back into the session.

set -euo pipefail

PROGRESS_FILE=".harness/progress.md"
STATE_FILE=".harness/_state.json"
TAIL_LINES="${HARNESS_PROGRESS_TAIL:-100}"

# Hook input on stdin is currently unused, but consume to avoid SIGPIPE.
cat >/dev/null || true

printf '<harness-restore>\n'

if [ -f "$STATE_FILE" ]; then
  printf '<state file="%s">\n' "$STATE_FILE"
  cat "$STATE_FILE"
  printf '\n</state>\n'
else
  printf '<state missing="true"/>\n'
fi

if [ -f "$PROGRESS_FILE" ]; then
  printf '<progress file="%s" tail="%s">\n' "$PROGRESS_FILE" "$TAIL_LINES"
  tail -n "$TAIL_LINES" "$PROGRESS_FILE"
  printf '\n</progress>\n'
else
  printf '<progress missing="true"/>\n'
fi

printf '</harness-restore>\n'
exit 0

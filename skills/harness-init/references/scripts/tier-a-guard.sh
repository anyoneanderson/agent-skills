#!/usr/bin/env bash
# tier-a-guard.sh — PreToolUse hook (matcher: Bash)
#
# Matches the Bash command against .harness/tier-a-patterns.txt (one ERE
# regex per line, blank/# lines ignored). On hit:
#   - strict mode: emit {"decision":"deny", ...} and set pending_human=true
#   - warn mode (--warn-only): log to progress.md, emit {} (allow)
#
# Input: Claude Code PreToolUse hook JSON on stdin.
# Requirement refs: REQ-081, REQ-082.

set -euo pipefail

WARN_ONLY=0
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1

PATTERNS_FILE=".harness/tier-a-patterns.txt"
STATE_FILE=".harness/_state.json"
PROGRESS_FILE=".harness/progress.md"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"

# No command or no patterns file → allow.
[ -n "$cmd" ] || { printf '{}\n'; exit 0; }
[ -f "$PATTERNS_FILE" ] || { printf '{}\n'; exit 0; }

matched=""
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in '#'*) continue ;; esac
  if printf '%s' "$cmd" | grep -Eq -- "$pat"; then
    matched="$pat"
    break
  fi
done < "$PATTERNS_FILE"

[ -z "$matched" ] && { printf '{}\n'; exit 0; }

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$(dirname "$PROGRESS_FILE")"
printf '- %s | TIER-A MATCH | pattern=%q | cmd=%q\n' "$ts" "$matched" "$cmd" >> "$PROGRESS_FILE"

if [ "$WARN_ONLY" = "1" ]; then
  printf '{}\n'
  exit 0
fi

# Strict: flip pending_human and deny.
if [ -f "$STATE_FILE" ]; then
  tmp="$(mktemp)"
  jq '.pending_human = true | .tier_a_last = {pattern: $p, cmd: $c, ts: $t}' \
     --arg p "$matched" --arg c "$cmd" --arg t "$ts" \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
fi

jq -n --arg p "$matched" --arg c "$cmd" \
  '{decision:"deny", reason:("tier-a denied: pattern=" + $p + " cmd=" + $c + " — requires human approval")}'
exit 0

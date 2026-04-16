#!/usr/bin/env bash
# tier-a-guard-codex.sh — Codex PreToolUse hook (matcher: Bash)
#
# Mirror of Claude-side tier-a-guard.sh but runs inside Codex's hook
# runner. This provides double-coverage: even if Codex's Bash tool
# somehow bypasses Claude's hook (or the Codex session is detached),
# destructive commands get blocked here.
#
# Input:  Codex PreToolUse JSON on stdin; tool_input.command carries
#         the shell command Codex is about to run.
# Output: deny JSON on match; silent exit 0 on no-match (fail open).

set -eu

PATTERNS_FILE=".harness/tier-a-patterns.txt"

payload="$(cat)"

# Resolve repo root from input.cwd if provided (Codex hooks run with
# session cwd but to be safe, follow input).
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "${cwd:-}" ] && cd "$cwd" 2>/dev/null || true

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
[ -n "$cmd" ] || exit 0
[ -f "$PATTERNS_FILE" ] || exit 0

matched=""
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in '#'*) continue ;; esac
  if printf '%s' "$cmd" | grep -Eq -- "$pat"; then
    matched="$pat"
    break
  fi
done < "$PATTERNS_FILE"

[ -z "$matched" ] && exit 0

# Match: block via Codex's hookSpecificOutput shape.
jq -n --arg pat "$matched" --arg cmd "$cmd" \
  '{
     hookSpecificOutput: {
       hookEventName: "PreToolUse",
       permissionDecision: "deny",
       permissionDecisionReason: ("Tier-A denied by harness (codex hook): pattern=" + $pat + " cmd=" + $cmd + " — requires human approval")
     }
   }'
exit 0

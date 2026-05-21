#!/usr/bin/env bash
# tier-a-guard.sh — PreToolUse hook (matcher: Bash)
#
# Matches the Bash command against .harness/tier-a-patterns.txt (one ERE
# regex per line, blank/# lines ignored). On hit:
#   - strict mode: emit {"decision":"deny", ...} and set pending_human=true
#   - warn mode (--warn-only): log to progress.md, emit {} (allow)
#
# Input: Claude Code PreToolUse hook JSON on stdin.

set -euo pipefail

WARN_ONLY=0
TEST_MODE="${HARNESS_TEST_MODE:-0}"
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1
[ "${1:-}" = "--test-mode" ] && TEST_MODE=1

PATTERNS_FILE=".harness/tier-a-patterns.txt"
STATE_FILE=".harness/_state.json"
PROGRESS_FILE=".harness/progress.md"
AUDIT_DIR=".harness/_audit"
AUDIT_FILE="${AUDIT_DIR}/tier_a_history.jsonl"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"

# No command or no patterns file → allow.
[ -n "$cmd" ] || { printf '{}\n'; exit 0; }
[ -f "$PATTERNS_FILE" ] || { printf '{}\n'; exit 0; }

# heredoc 本文はユーザー提供テキストであり、shell command の実行位置ではない。
# 行頭 anchor の pattern が例文や生成 script 本文の "rm -rf /tmp/demo" に
# 反応しないよう、照合前に本文だけを除外する。
match_cmd="$(
  printf '%s\n' "$cmd" | awk '
    in_heredoc {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == heredoc_end) {
        in_heredoc = 0
        heredoc_end = ""
      }
      next
    }

    {
      print
      if (match($0, /<<-?[[:space:]]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
        marker = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", marker)
        gsub(/['\''"]/, "", marker)
        heredoc_end = marker
        in_heredoc = 1
      }
    }
  '
)"

matched=""
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$pat" in '#'*) continue ;; esac
  if printf '%s' "$match_cmd" | grep -Eq -- "$pat"; then
    matched="$pat"
    break
  fi
done < "$PATTERNS_FILE"

[ -z "$matched" ] && { printf '{}\n'; exit 0; }

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

refresh_tier_a_summary() {
  [ -f "$STATE_FILE" ] || return 0
  mkdir -p "$AUDIT_DIR"
  local count last_at last_pattern tmp
  count="$(wc -l < "$AUDIT_FILE" 2>/dev/null | tr -d ' ' || printf '0')"
  if [ -s "$AUDIT_FILE" ]; then
    last_at="$(tail -1 "$AUDIT_FILE" | jq -r '.ts // empty' 2>/dev/null || true)"
    last_pattern="$(tail -1 "$AUDIT_FILE" | jq -r '.pattern // empty' 2>/dev/null || true)"
  else
    last_at=""
    last_pattern=""
  fi
  tmp="$(mktemp)"
  jq --argjson count "${count:-0}" \
     --arg last_at "$last_at" \
     --arg last_pattern "$last_pattern" \
     '
       .tier_a_summary = {
         count: $count,
         last_at: (if $last_at == "" then null else $last_at end),
         last_pattern: (if $last_pattern == "" then null else $last_pattern end)
       }
     ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

archive_resolved_tier_a_events() {
  [ -f "$STATE_FILE" ] || return 0
  mkdir -p "$AUDIT_DIR"
  touch "$AUDIT_FILE"

  jq -c '
    [
      ((.tier_a_history // [])[]?),
      (if (.tier_a_last // null) != null and (.tier_a_last.resolution // null) != null
       then .tier_a_last
       else empty
       end)
    ][]?
  ' "$STATE_FILE" >> "$AUDIT_FILE"

  local tmp
  tmp="$(mktemp)"
  jq '
    .tier_a_history = []
    | if (.tier_a_last // null) != null and (.tier_a_last.resolution // null) != null
      then .tier_a_last = null
      else .
      end
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  refresh_tier_a_summary
}

# Test mode: skip progress.md append and state mutation; emit a
# deterministic deny with test_mode:true so installers can verify the
# regex-match path without polluting real state. Enable via either
# HARNESS_TEST_MODE=1 env var or --test-mode arg.
if [ "$TEST_MODE" = "1" ]; then
  jq -n --arg p "$matched" --arg c "$cmd" \
    '{decision:"deny", reason:("tier-a (test-mode) would deny: pattern=" + $p + " cmd=" + $c), test_mode:true}'
  exit 0
fi

mkdir -p "$(dirname "$PROGRESS_FILE")"
# NB: format string must not start with "-" (some printf impls parse it as
# an option). Use "%s\n" with a pre-built line.
log_line="- ${ts} | TIER-A MATCH | pattern=${matched} | cmd=${cmd}"
printf '%s\n' "$log_line" >> "$PROGRESS_FILE"

if [ "$WARN_ONLY" = "1" ]; then
  printf '{}\n'
  exit 0
fi

# Strict: archive any already-resolved last event, then flip
# pending_human and set the new current hit.
if [ -f "$STATE_FILE" ]; then
  archive_resolved_tier_a_events
  tmp="$(mktemp)"
  jq '
       .tier_a_history = []
       | .pending_human = true
       | .tier_a_last = {pattern: $p, cmd: $c, ts: $t}
     ' \
     --arg p "$matched" --arg c "$cmd" --arg t "$ts" \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  refresh_tier_a_summary
fi

jq -n --arg p "$matched" --arg c "$cmd" \
  '{decision:"deny", reason:("tier-a denied: pattern=" + $p + " cmd=" + $c + " — requires human approval")}'
exit 0

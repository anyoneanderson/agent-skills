#!/usr/bin/env bash
# stop-guard.sh — Stop hook
#
# Decides whether the agent should stop or continue the loop. Enforces
# Principal Skinner's 5 conditions (REQ-080) and the stop_hook_active
# anti-recursion flag.
#
# Input: Claude Code Stop hook JSON on stdin. Example fields:
#   .stop_hook_active (bool) — true means this hook fired from its own block
#
# Output: JSON to stdout.
#   {"decision": "block", "reason": "..."}  → continue the loop
#   {}  → allow stop (default)

set -euo pipefail

STATE_FILE=".harness/_state.json"
CONFIG_FILE=".harness/_config.yml"

payload="$(cat)"
stop_hook_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')"

# Anti-recursion: if we already blocked once in this chain, allow stop.
if [ "$stop_hook_active" = "true" ]; then
  printf '{}\n'
  exit 0
fi

# No state → nothing to guard; allow stop.
[ -f "$STATE_FILE" ] || { printf '{}\n'; exit 0; }

completed="$(jq -r '.completed // false' "$STATE_FILE")"
pending_human="$(jq -r '.pending_human // false' "$STATE_FILE")"
iterations="$(jq -r '.iterations // 0' "$STATE_FILE")"
wall_time_sec="$(jq -r '.wall_time_sec // 0' "$STATE_FILE")"
cost_usd="$(jq -r '.cost_usd // 0' "$STATE_FILE")"
stagnation_n="$(jq -r '.rubric_stagnation_count // 0' "$STATE_FILE")"

# Read caps from _config.yml via grep (no YAML parser assumed).
yget() { grep -E "^$1:" "$CONFIG_FILE" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"'; }
max_iterations="$(yget max_iterations)";     max_iterations="${max_iterations:-8}"
max_wall_time_sec="$(yget max_wall_time_sec)"; max_wall_time_sec="${max_wall_time_sec:-28800}"
max_cost_usd="$(yget max_cost_usd)";         max_cost_usd="${max_cost_usd:-20}"
max_stagnation_n="$(yget rubric_stagnation_n)"; max_stagnation_n="${max_stagnation_n:-3}"

block() {
  jq -n --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

# Principal Skinner: any of these → ALLOW stop (reached a limit).
[ "$completed" = "true" ]                              && { printf '{}\n'; exit 0; }
[ "$pending_human" = "true" ]                          && { printf '{}\n'; exit 0; }
awk -v a="$iterations" -v b="$max_iterations"    'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$wall_time_sec" -v b="$max_wall_time_sec" 'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$cost_usd" -v b="$max_cost_usd"      'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$stagnation_n" -v b="$max_stagnation_n" 'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }

# Otherwise, the loop is not done — block stop and re-inject a continue hint.
block "harness loop incomplete: iter=${iterations}/${max_iterations}, wall=${wall_time_sec}s/${max_wall_time_sec}s, cost=\$${cost_usd}/\$${max_cost_usd}, stagnation=${stagnation_n}/${max_stagnation_n}"

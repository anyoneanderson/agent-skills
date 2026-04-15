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

# Keys are the canonical ones from references/resilience-schema.md.
completed="$(jq -r '.completed // false' "$STATE_FILE")"
pending_human="$(jq -r '.pending_human // false' "$STATE_FILE")"
iteration="$(jq -r '.iteration // 0' "$STATE_FILE")"
cumulative_cost_usd="$(jq -r '.cumulative_cost_usd // 0' "$STATE_FILE")"
start_time="$(jq -r '.start_time // ""' "$STATE_FILE")"
stagnation_n="$(jq -r '.rubric_stagnation_count // 0' "$STATE_FILE")"

# Caps: prefer _state.json (design §9.2 stores the bound next to the counter),
# fall back to _config.yml for initial sprints.
yget() { { grep -E "^$1:" "$CONFIG_FILE" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"'; } || true; }
jget() { jq -r "$1 // empty" "$STATE_FILE" 2>/dev/null || true; }
max_iterations="$(jget .max_iterations)";       max_iterations="${max_iterations:-$(yget max_iterations)}";         max_iterations="${max_iterations:-8}"
max_wall_time_sec="$(jget .max_wall_time_sec)"; max_wall_time_sec="${max_wall_time_sec:-$(yget max_wall_time_sec)}"; max_wall_time_sec="${max_wall_time_sec:-28800}"
max_cost_usd="$(jget .max_cost_usd)";           max_cost_usd="${max_cost_usd:-$(yget max_cost_usd)}";               max_cost_usd="${max_cost_usd:-20}"
max_stagnation_n="$(yget rubric_stagnation_n)"; max_stagnation_n="${max_stagnation_n:-3}"

# Derive elapsed wall-time from start_time (ISO-8601 UTC). 0 if unset.
elapsed_sec=0
if [ -n "$start_time" ]; then
  now_epoch="$(date -u +%s)"
  start_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$start_time" +%s 2>/dev/null \
                || date -u -d "$start_time" +%s 2>/dev/null \
                || printf '0')"
  if [ "$start_epoch" != "0" ]; then
    elapsed_sec=$(( now_epoch - start_epoch ))
    [ "$elapsed_sec" -lt 0 ] && elapsed_sec=0
  fi
fi

block() {
  jq -n --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

# Principal Skinner: any of these → ALLOW stop (reached a limit).
[ "$completed" = "true" ]                              && { printf '{}\n'; exit 0; }
[ "$pending_human" = "true" ]                          && { printf '{}\n'; exit 0; }
awk -v a="$iteration"           -v b="$max_iterations"    'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$elapsed_sec"         -v b="$max_wall_time_sec" 'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$cumulative_cost_usd" -v b="$max_cost_usd"      'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }
awk -v a="$stagnation_n"        -v b="$max_stagnation_n"  'BEGIN{exit !(a+0>=b+0)}' && { printf '{}\n'; exit 0; }

# Otherwise, the loop is not done — block stop and re-inject a continue hint.
block "harness loop incomplete: iter=${iteration}/${max_iterations}, wall=${elapsed_sec}s/${max_wall_time_sec}s, cost=\$${cumulative_cost_usd}/\$${max_cost_usd}, stagnation=${stagnation_n}/${max_stagnation_n}"

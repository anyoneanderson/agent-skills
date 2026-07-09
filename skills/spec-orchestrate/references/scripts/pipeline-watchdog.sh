#!/usr/bin/env bash
# pipeline-watchdog.sh — Claude Code Stop hook for spec-orchestrate.
#
# Blocks a turn from ending while a spec-orchestrate run is mid-flight with no
# registered background wait, and tells the model to dispatch the next phase.
# This turns the pipeline's "run the loop until a terminal state" rule from a
# behavioral promise into a mechanical guarantee.
#
# Contract (Claude Code Stop hook):
#   stdin  — JSON with at least {"stop_hook_active": bool}
#   stdout — {"decision":"block","reason":"..."} to keep the turn alive
#   exit 0 with no decision JSON to allow the stop
#
# The hook is scoped by the run marker `.specs/.orchestrate-active.json`, which
# the orchestrator maintains (see pipeline-config.md §Run marker). No marker, a
# paused/stale marker, a terminal state, or a registered pending wait all mean
# "allow the stop". The hook never blocks more than MAX_BLOCKS consecutive times
# without observing state progress, so it cannot loop a stuck session forever.
#
# Escape hatch (for a human, or a session that is not the orchestrator):
#   jq '.paused = true' .specs/.orchestrate-active.json > t && mv t .specs/.orchestrate-active.json

set -euo pipefail

MARKER=".specs/.orchestrate-active.json"
MAX_BLOCKS=3
TTL_MINUTES=240

allow() { exit 0; }

command -v jq >/dev/null 2>&1 || allow
[ -f "$MARKER" ] || allow

# Consume stdin (present under the hook contract; absent when run by hand).
stdin_json="$(cat 2>/dev/null || true)"

paused="$(jq -r '.paused // false' "$MARKER" 2>/dev/null)" || allow
[ "$paused" = "true" ] && allow

feature="$(jq -r '.feature // empty' "$MARKER")"
[ -n "$feature" ] || allow

state=".specs/${feature}/pipeline-state.json"
[ -f "$state" ] || allow

# Stale marker: the orchestrator refreshes .ts on every state write. A marker
# untouched for TTL_MINUTES belongs to an abandoned run — do not nag new sessions.
# Timestamps are ISO-8601 UTC ("...Z"); parse them as UTC on both BSD and GNU date.
parse_iso_utc() {
  TZ=UTC0 date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null \
    || echo 0
}
marker_ts="$(jq -r '.ts // empty' "$MARKER")"
marker_epoch=0
[ -n "$marker_ts" ] && marker_epoch="$(parse_iso_utc "$marker_ts")"
now_epoch="$(date +%s)"
if [ "$marker_epoch" -gt 0 ] && [ $((now_epoch - marker_epoch)) -gt $((TTL_MINUTES * 60)) ]; then
  allow
fi

phase="$(jq -r '.phase // empty' "$state")"
terminal="$(jq -r '.completed_phases // [] | index("retrospective") != null' "$state")"
[ "$terminal" = "true" ] && allow
[ -z "$phase" ] && allow

# A registered background wait (detach collection) is a legitimate pause: the
# host runtime re-invokes the orchestrator when the report file appears.
waiting="$(jq -r '.waiting_report // empty' "$MARKER")"
if [ -n "$waiting" ] && [ ! -f "$waiting" ]; then
  allow
fi

# Loop safety: count consecutive blocks against an unchanged state fingerprint.
# If blocking has not produced progress MAX_BLOCKS times, give up and allow.
fingerprint="${phase}|$(jq -r '.ts_updated // empty' "$state")|${waiting}"
prev_fp="$(jq -r '.fingerprint // empty' "$MARKER")"
blocks="$(jq -r '.blocks // 0' "$MARKER")"
if [ "$fingerprint" = "$prev_fp" ]; then
  blocks=$((blocks + 1))
else
  blocks=1
fi
jq --arg fp "$fingerprint" --argjson b "$blocks" '.fingerprint = $fp | .blocks = $b' \
  "$MARKER" > "$MARKER.tmp" && mv "$MARKER.tmp" "$MARKER"
if [ "$blocks" -gt "$MAX_BLOCKS" ]; then
  echo "pipeline-watchdog: no progress after $MAX_BLOCKS blocks (phase=$phase); allowing stop." >&2
  allow
fi

reason="spec-orchestrate run '$feature' is mid-flight (phase: $phase) and no background wait is registered. Do not end the turn. If you are the orchestrator: run the state integrity check, then dispatch the '$phase' phase now per the Transition Table (SKILL.md), in this same turn. If you dispatched a detached worker, register its report path in $MARKER (.waiting_report) before yielding. If this session is NOT the orchestrator of this run, pause the watchdog: jq '.paused = true' $MARKER > t && mv t $MARKER"

waiting_done=""
if [ -n "$waiting" ] && [ -f "$waiting" ]; then
  waiting_done=" A registered wait has completed: $waiting exists — collect and verify it first, then clear .waiting_report in $MARKER."
fi

jq -cn --arg r "${reason}${waiting_done}" '{"decision":"block","reason":$r}'
exit 0

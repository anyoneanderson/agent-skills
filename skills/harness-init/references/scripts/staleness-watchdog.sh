#!/usr/bin/env bash
# staleness-watchdog.sh — autonomous-ralph liveness monitor.
#
# Watches .harness/progress.md and emits a WARN line when no fresh
# timestamped entry appears within the configured threshold. Auto-recovery is
# opt-in: when enabled, the watchdog terminates the hung worker and restarts
# the wrapper, capped per sprint.

set -uo pipefail

STATE_FILE=".harness/_state.json"
CONFIG_FILE=".harness/_config.yml"
PROGRESS_FILE=".harness/progress.md"
PID_FILE=".harness/ralph.pid"
WRAPPER=".harness/scripts/ralph-loop.sh"
LOG_FILE=".harness/ralph.log"

yget() {
  { grep -E "^$1:" "$CONFIG_FILE" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"' | tr -d "'"; } || true
}

threshold_sec="${STALENESS_THRESHOLD_SEC:-$(yget staleness_threshold_sec)}"
threshold_sec="${threshold_sec:-1800}"
interval_sec="${STALENESS_INTERVAL_SEC:-$(yget staleness_interval_sec)}"
interval_sec="${interval_sec:-300}"
auto_recover="${STALENESS_AUTO_RECOVER:-$(yget staleness_auto_recover)}"
auto_recover="${auto_recover:-false}"
max_recoveries="${STALENESS_MAX_RECOVERIES_PER_SPRINT:-$(yget max_staleness_recoveries_per_sprint)}"
max_recoveries="${max_recoveries:-3}"

current_sprint_key=""
recoveries=0
prev_alert_age=0

last_progress_iso() {
  [ -f "$PROGRESS_FILE" ] || return 1
  tail -200 "$PROGRESS_FILE" 2>/dev/null \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
    | tail -1
}

epoch_utc() {
  date -u -j -f "%FT%TZ" "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null
}

worker_pids() {
  pgrep -f "claude -p .*--permission-mode bypassPermissions" 2>/dev/null || true
}

restart_wrapper() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill -TERM "$(cat "$PID_FILE")" 2>/dev/null || true
  fi

  for pid in $(worker_pids); do
    kill -TERM "$pid" 2>/dev/null || true
  done

  sleep 3
  rm -f "$PID_FILE"
  nohup "$WRAPPER" >> "$LOG_FILE" 2>&1 &
  printf '%s\n' "$!" > "$PID_FILE"
  printf '[%s] STALE-WATCHDOG: wrapper respawn pid=%s\n' "$(date -u +%FT%TZ)" "$!" >> "$PROGRESS_FILE"
}

while true; do
  sleep "$interval_sec"

  if [ -f "$STATE_FILE" ]; then
    sprint_key="$(jq -r '(.current_epic // "null") + ":" + ((.current_sprint // 0) | tostring)' "$STATE_FILE" 2>/dev/null || printf 'unknown')"
    if [ "$sprint_key" != "$current_sprint_key" ]; then
      current_sprint_key="$sprint_key"
      recoveries=0
      prev_alert_age=0
    fi
  fi

  last_iso="$(last_progress_iso || true)"
  [ -n "$last_iso" ] || continue
  last_epoch="$(epoch_utc "$last_iso" 2>/dev/null || true)"
  [ -n "$last_epoch" ] || continue
  age=$(( $(date -u +%s) - last_epoch ))

  if (( age <= threshold_sec )); then
    prev_alert_age=0
    continue
  fi

  if (( prev_alert_age == 0 || age - prev_alert_age >= threshold_sec / 2 )); then
    printf '[%s] STALE-WATCHDOG: progress.md last entry was %ss ago (%dmin) at %s\n' \
      "$(date -u +%FT%TZ)" "$age" $((age / 60)) "$last_iso" >> "$PROGRESS_FILE"
    prev_alert_age=$age
  fi

  if [ "$auto_recover" = "true" ] && (( recoveries < max_recoveries )); then
    recoveries=$((recoveries + 1))
    printf '[%s] STALE-WATCHDOG: auto-recover attempt=%s/%s\n' \
      "$(date -u +%FT%TZ)" "$recoveries" "$max_recoveries" >> "$PROGRESS_FILE"
    restart_wrapper
  fi
done

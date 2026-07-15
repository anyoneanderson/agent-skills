#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$TEST_DIR/.." && pwd)/agent-delegate.sh"
TARGET="claude"
SCENARIO="done"
OUT_DIR=""
LABEL="heartbeat-test"
PROMPT_FILE=""
KEEP=0
FAIL_STAGE=""

usage() {
  printf '%s\n' \
    'Usage: heartbeat_harness.sh [--target codex|claude] [--scenario name]' \
    '       [--out-dir path] [--label slug] [--prompt-file path] [--keep]'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --scenario) SCENARIO="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --fail-stage) FAIL_STAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'heartbeat-harness: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$TARGET" in codex|claude) : ;; *) printf 'heartbeat-harness: invalid target\n' >&2; exit 2 ;; esac
case "$SCENARIO" in
  done|blocked|worker-death|missing|invalid-json|invalid-status|wrong-run|monitor-kill-before-heartbeat|owner-pid-mismatch|acknowledgement-mismatch|final-ack-timeout|expire-handoff|worker-start-failure|final-ack-response-lost|sentinel-committed-failure|owner-committed-failure|sentinel-verified-failure|owner-verified-failure) : ;;
  *) printf 'heartbeat-harness: invalid scenario: %s\n' "$SCENARIO" >&2; exit 2 ;;
esac

TMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd)"
if [ -z "$OUT_DIR" ]; then OUT_DIR="$(mktemp -d "$TMP_ROOT/agent-delegate-heartbeat-out.XXXXXX")"; else mkdir -p "$OUT_DIR"; fi
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
if [ -z "$PROMPT_FILE" ]; then
  PROMPT_FILE="$OUT_DIR/$LABEL-prompt.md"
  printf 'deterministic heartbeat harness prompt\n' > "$PROMPT_FILE"
fi
HANDOFF_DIR="$(mktemp -d "$TMP_ROOT/agent-delegate-heartbeat-handoff.XXXXXX")"
chmod 700 "$HANDOFF_DIR"

OWNER_FILE="$OUT_DIR/$LABEL-owner.json"
PID_FILE="$OUT_DIR/$LABEL.pid"
REPORT_FILE="$OUT_DIR/$LABEL-report.json"
HEARTBEAT_FILE="$OUT_DIR/$LABEL-heartbeat.json"
STDERR_FILE="$OUT_DIR/$LABEL-stderr.log"
LAUNCHER_OUT="$OUT_DIR/$LABEL-launcher.out"
LAUNCHER_ERR="$OUT_DIR/$LABEL-launcher.err"
EVENTS_FILE="$OUT_DIR/$LABEL-harness-events.tsv"
RESULT_FILE="$OUT_DIR/$LABEL-harness-result.json"
OWNER_SNAPSHOT="$OUT_DIR/$LABEL-owner-before-worker.json"
PID_SNAPSHOT="$OUT_DIR/$LABEL-pid-before-worker.txt"
SENTINEL_SNAPSHOT="$OUT_DIR/$LABEL-sentinel-ready.json"
MONITOR_PID=""
WORKER_PID=""
LAUNCHER_PID=""
CONTROL_OPEN=0

mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
process_alive() { kill -0 "$1" >/dev/null 2>&1; }
now_epoch() { date -u +%s; }
epoch_rfc3339() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

close_control() {
  [ "$CONTROL_OPEN" -eq 1 ] || return 0
  { exec 8<&-; } 2>/dev/null || true
  { exec 7>&-; } 2>/dev/null || true
  CONTROL_OPEN=0
}

fallback_cleanup() {
  local sentinel="$HANDOFF_DIR/handoff-sentinel.json" child base unknown=0
  [ -d "$HANDOFF_DIR" ] || return 0
  if [ -f "$sentinel" ] && jq -e --arg handoff "$HANDOFF_DIR" '
    .handoff_dir==$handoff and (.created_fifos|type)=="array"
  ' "$sentinel" >/dev/null 2>&1; then
    while IFS= read -r base; do
      case "$base" in
        launcher-to-monitor.fifo|monitor-to-launcher.fifo|harness-to-monitor.fifo|monitor-to-harness.fifo) : ;;
        *) unknown=1; continue ;;
      esac
      child="$HANDOFF_DIR/$base"
      [ ! -e "$child" ] || { [ -p "$child" ] && rm -f "$child" || unknown=1; }
    done < <(jq -r '.created_fifos[]' "$sentinel")
    [ "$unknown" -ne 0 ] || rm -f "${sentinel}.tmp."* "$sentinel"
  else
    while IFS= read -r child; do
      base="$(basename "$child")"
      case "$base" in
        launcher-to-monitor.fifo|monitor-to-launcher.fifo|harness-to-monitor.fifo|monitor-to-harness.fifo)
          [ -p "$child" ] && rm -f "$child" || unknown=1 ;;
        *) unknown=1 ;;
      esac
    done < <(find "$HANDOFF_DIR" -mindepth 1 -maxdepth 1 -print)
  fi
  [ "$unknown" -ne 0 ] || rmdir "$HANDOFF_DIR" 2>/dev/null || true
}

cleanup() {
  close_control
  if [ -n "$LAUNCHER_PID" ] && process_alive "$LAUNCHER_PID"; then kill "$LAUNCHER_PID" 2>/dev/null || true; fi
  if [ -n "$MONITOR_PID" ] && process_alive "$MONITOR_PID"; then kill "$MONITOR_PID" 2>/dev/null || true; fi
  if [ -n "$WORKER_PID" ] && process_alive "$WORKER_PID"; then kill "$WORKER_PID" 2>/dev/null || true; fi
  [ -z "$LAUNCHER_PID" ] || wait "$LAUNCHER_PID" 2>/dev/null || true
  fallback_cleanup
  if [ "$KEEP" -eq 0 ] && [ -f "$OUT_DIR/$LABEL-prompt.md" ]; then rm -f "$OUT_DIR/$LABEL-prompt.md"; fi
}
trap cleanup EXIT TERM INT HUP

request="$SCENARIO"
case "$SCENARIO" in
  done|blocked|worker-death|missing|invalid-json|invalid-status|wrong-run|monitor-kill-before-heartbeat|sentinel-committed-failure|owner-committed-failure|sentinel-verified-failure|owner-verified-failure) request=normal ;;
esac
case "$SCENARIO" in
  sentinel-committed-failure) FAIL_STAGE=sentinel_committed ;;
  owner-committed-failure) FAIL_STAGE=owner_committed ;;
  sentinel-verified-failure) FAIL_STAGE=sentinel_verified ;;
  owner-verified-failure) FAIL_STAGE=owner_verified ;;
esac

AGENT_DELEGATE_TEST_MODE=heartbeat \
AGENT_DELEGATE_TEST_HANDOFF_DIR="$HANDOFF_DIR" \
AGENT_DELEGATE_TEST_HANDOFF_REQUEST="$request" \
AGENT_DELEGATE_TEST_FAIL_STAGE="$FAIL_STAGE" \
  bash "$SCRIPT" --mode delegate --prompt-file "$PROMPT_FILE" --out-dir "$OUT_DIR" \
    --label "$LABEL" --target "$TARGET" --sandbox workspace-write --detach \
    > "$LAUNCHER_OUT" 2> "$LAUNCHER_ERR" &
LAUNCHER_PID=$!
printf '1\tlauncher-start\t%s\n' "$LAUNCHER_PID" > "$EVENTS_FILE"
deadline=$(( $(now_epoch) + 10 ))

while :; do
  [ "$(now_epoch)" -lt "$deadline" ] || { printf 'heartbeat-harness: owner readiness timeout\n' >&2; exit 1; }
  if [ -f "$OWNER_FILE" ] && [ -f "$PID_FILE" ] && jq -e --argjson launcher "$LAUNCHER_PID" --arg handoff "$HANDOFF_DIR" '
    .run_kind=="detach" and .launcher_pid==$launcher and .runner_pid==.monitor_pid and
    .worker_pid==null and .handoff_phase=="not_started" and .handoff_dir==$handoff
  ' "$OWNER_FILE" >/dev/null 2>&1; then
    MONITOR_PID="$(jq -r '.monitor_pid' "$OWNER_FILE")"
    expected_run="$(jq -r '.run_id' "$OWNER_FILE")"
    if process_alive "$MONITOR_PID" &&
       [ "$(awk -F': ' '$1=="pid"{print $2;exit}' "$PID_FILE")" = "$MONITOR_PID" ] &&
       [ "$(awk -F': ' '$1=="run_id"{print $2;exit}' "$PID_FILE")" = "$expected_run" ]; then
      cp "$OWNER_FILE" "$OWNER_SNAPSHOT"; cp "$PID_FILE" "$PID_SNAPSHOT"
      printf '2\towner-before-fifo\t%s\n' "$expected_run" >> "$EVENTS_FILE"
      break
    fi
  fi
  process_alive "$LAUNCHER_PID" || { printf 'heartbeat-harness: launcher exited before owner readiness\n' >&2; exit 1; }
done

sentinel="$HANDOFF_DIR/handoff-sentinel.json"
while :; do
  [ "$(now_epoch)" -lt "$deadline" ] || { printf 'heartbeat-harness: FIFO readiness timeout\n' >&2; exit 1; }
  if [ -f "$sentinel" ] && jq -e --arg run "$expected_run" --argjson launcher "$LAUNCHER_PID" \
      --argjson monitor "$MONITOR_PID" --arg handoff "$HANDOFF_DIR" '
      .run_id==$run and .launcher_pid==$launcher and .monitor_pid==$monitor and
      .handoff_dir==$handoff and .state=="fifo_ready" and .handoff_phase=="not_started" and
      .handoff_fifos==["launcher-to-monitor.fifo","monitor-to-launcher.fifo"] and
      .control_fifos==["harness-to-monitor.fifo","monitor-to-harness.fifo"] and
      (.created_fifos|length)==4
    ' "$sentinel" >/dev/null 2>&1; then
    ready=1
    for name in launcher-to-monitor monitor-to-launcher harness-to-monitor monitor-to-harness; do
      path="$HANDOFF_DIR/$name.fifo"
      if [ ! -p "$path" ] || [ "$(mode_of "$path")" != 600 ]; then ready=0; fi
    done
    if [ "$ready" -eq 1 ]; then cp "$sentinel" "$SENTINEL_SNAPSHOT"; break; fi
  fi
  process_alive "$MONITOR_PID" || { printf 'heartbeat-harness: monitor exited before FIFO readiness\n' >&2; exit 1; }
done
printf '3\tfifo-ready\t%s\n' "$MONITOR_PID" >> "$EVENTS_FILE"

exec 7>"$HANDOFF_DIR/harness-to-monitor.fifo"
exec 8<"$HANDOFF_DIR/monitor-to-harness.fifo"
CONTROL_OPEN=1
printf 'harness-ready %s\n' "$expected_run" >&7
remaining=$((deadline - $(now_epoch))); [ "$remaining" -gt 0 ] || remaining=1
IFS= read -r -t "$remaining" ready_ack <&8
[ "$ready_ack" = "harness-observed ready $expected_run $MONITOR_PID" ] || {
  printf 'heartbeat-harness: invalid ready acknowledgement: %s\n' "$ready_ack" >&2; exit 1;
}
printf '4\tharness-ready\t%s\n' "$expected_run" >> "$EVENTS_FILE"

while process_alive "$LAUNCHER_PID"; do
  [ "$(now_epoch)" -lt "$deadline" ] || { printf 'heartbeat-harness: launcher handoff timeout\n' >&2; exit 1; }
done
set +e
wait "$LAUNCHER_PID"
launcher_exit=$?
set -e
printf '5\tlauncher-exit\t%s\n' "$launcher_exit" >> "$EVENTS_FILE"

if [ "$SCENARIO" = monitor-kill-before-heartbeat ]; then
  owner_after_worker="$OUT_DIR/$LABEL-owner-before-first-heartbeat.json"
  while :; do
    [ "$(now_epoch)" -lt "$deadline" ] || { printf 'heartbeat-harness: worker owner publication timeout\n' >&2; exit 1; }
    if [ ! -e "$HEARTBEAT_FILE" ] && jq -e --arg run "$expected_run" '
      .run_id==$run and (.worker_pid|type)=="number" and .worker_pid>0
    ' "$OWNER_FILE" >/dev/null 2>&1; then
      WORKER_PID="$(jq -r '.worker_pid' "$OWNER_FILE")"
      process_alive "$WORKER_PID" || continue
      cp "$OWNER_FILE" "$owner_after_worker"
      break
    fi
    process_alive "$MONITOR_PID" || { printf 'heartbeat-harness: monitor exited before worker owner publication\n' >&2; exit 1; }
  done
  kill -KILL "$MONITOR_PID"
  for _ in $(seq 1 10000); do process_alive "$MONITOR_PID" || break; done
  process_alive "$MONITOR_PID" && { printf 'heartbeat-harness: monitor survived injected KILL\n' >&2; exit 1; }
  process_alive "$WORKER_PID" || { printf 'heartbeat-harness: worker did not survive initial monitor loss\n' >&2; exit 1; }
  jq -n --arg run_id "$expected_run" --arg owner_snapshot "$owner_after_worker" \
    --arg heartbeat_path "$HEARTBEAT_FILE" --argjson launcher_pid "$LAUNCHER_PID" \
    --argjson monitor_pid "$MONITOR_PID" --argjson worker_pid "$WORKER_PID" '
    {run_id:$run_id,scenario:"monitor-kill-before-heartbeat",launcher_pid:$launcher_pid,
     monitor_pid:$monitor_pid,worker_pid:$worker_pid,owner_snapshot:$owner_snapshot,
     heartbeat_path:$heartbeat_path,monitor_alive:false,worker_alive_before_cleanup:true,
     heartbeat_absent:true}
  ' > "$RESULT_FILE"
  close_control
  kill -TERM "$WORKER_PID" 2>/dev/null || true
  for _ in $(seq 1 10000); do process_alive "$WORKER_PID" || break; done
  process_alive "$WORKER_PID" && kill -KILL "$WORKER_PID" 2>/dev/null || true
  fallback_cleanup
  rm -f "$OWNER_FILE" "$PID_FILE"
  [ ! -d "$HANDOFF_DIR" ] && [ ! -e "$OWNER_FILE" ] && [ ! -e "$PID_FILE" ] || {
    printf 'heartbeat-harness: initial monitor death cleanup failed\n' >&2
    exit 1
  }
  printf '%s\n' "$RESULT_FILE"
  trap - EXIT TERM INT HUP
  exit 0
fi

case "$SCENARIO" in
  owner-pid-mismatch|acknowledgement-mismatch|final-ack-timeout|expire-handoff|sentinel-committed-failure|sentinel-verified-failure)
    [ "$launcher_exit" -eq 0 ] || { printf 'heartbeat-harness: pre-handoff launcher exit=%s\n' "$launcher_exit" >&2; exit 1; }
    [ -f "$REPORT_FILE" ] || { printf 'heartbeat-harness: missing pre-handoff report\n' >&2; exit 1; }
    close_control
    ;;
  *)
    [ "$launcher_exit" -eq 0 ] || { printf 'heartbeat-harness: launcher exit=%s\n' "$launcher_exit" >&2; exit 1; }
    if [ "$SCENARIO" != worker-start-failure ]; then
      base_epoch=$(now_epoch)
      beat_one="$(epoch_rfc3339 "$((base_epoch + 30))")"
      beat_two="$(epoch_rfc3339 "$((base_epoch + 60))")"
      for beat in "$beat_one" "$beat_two"; do
        printf 'beat %s\n' "$beat" >&7
        IFS= read -r -t 10 observed <&8
        observed_sequence="$(printf '%s\n' "$observed" | awk '{print $2}')"
        [ "$observed" = "observed $observed_sequence running $beat" ] || {
          printf 'heartbeat-harness: invalid beat acknowledgement: %s\n' "$observed" >&2; exit 1;
        }
        jq -e --arg run "$expected_run" --arg beat "$beat" '
          .run_id==$run and .state=="running" and .last_beat==$beat
        ' "$HEARTBEAT_FILE" >/dev/null
        cp "$HEARTBEAT_FILE" "$OUT_DIR/$LABEL-heartbeat-$observed_sequence.json"
        cp "$OWNER_FILE" "$OUT_DIR/$LABEL-owner-$observed_sequence.json"
        printf '%s\tbeat\t%s\n' "$((5 + observed_sequence))" "$beat" >> "$EVENTS_FILE"
      done
      case "$SCENARIO" in
        done|final-ack-response-lost|owner-committed-failure|owner-verified-failure) terminal_input=finish-done ;;
        blocked) terminal_input=finish-blocked ;;
        worker-death) terminal_input=worker-death ;;
        missing) terminal_input=finish-missing ;;
        invalid-json) terminal_input=finish-invalid-json ;;
        invalid-status) terminal_input=finish-invalid-status ;;
        wrong-run) terminal_input=finish-wrong-run ;;
      esac
      printf '%s\n' "$terminal_input" >&7
    fi
    IFS= read -r -t 10 terminal_ack <&8
    terminal_status="$(printf '%s\n' "$terminal_ack" | awk '{print $2}')"
    [ "$(printf '%s\n' "$terminal_ack" | awk '{print $3}')" = "$expected_run" ] || {
      printf 'heartbeat-harness: invalid terminal acknowledgement: %s\n' "$terminal_ack" >&2; exit 1;
    }
    close_control
    ;;
esac

for _ in $(seq 1 10000); do
  [ ! -e "$OWNER_FILE" ] && [ ! -e "$PID_FILE" ] && [ ! -d "$HANDOFF_DIR" ] && break
  if ! process_alive "$MONITOR_PID" && { [ -e "$OWNER_FILE" ] || [ -e "$PID_FILE" ] || [ -d "$HANDOFF_DIR" ]; }; then break; fi
done
[ ! -e "$OWNER_FILE" ] && [ ! -e "$PID_FILE" ] || { printf 'heartbeat-harness: runtime owner residue\n' >&2; exit 1; }
[ ! -d "$HANDOFF_DIR" ] || { printf 'heartbeat-harness: handoff directory residue\n' >&2; exit 1; }

report_status="$(jq -r '.status' "$REPORT_FILE")"
report_run="$(jq -r '.meta.run_id' "$REPORT_FILE")"
[ "$report_run" = "$expected_run" ] || { printf 'heartbeat-harness: report run mismatch\n' >&2; exit 1; }
if [ -f "$HEARTBEAT_FILE" ]; then
  heartbeat_state="$(jq -r '.state' "$HEARTBEAT_FILE")"
  heartbeat_run="$(jq -r '.run_id' "$HEARTBEAT_FILE")"
else
  heartbeat_state="absent"; heartbeat_run="absent"
fi
direction="codex->claude"; [ "$TARGET" = codex ] && direction="claude->codex"
beat_count="$(find "$OUT_DIR" -maxdepth 1 -name "$LABEL-heartbeat-[0-9]*.json" | wc -l | tr -d ' ')"
jq -n --arg run_id "$expected_run" --arg target "$TARGET" --arg direction "$direction" \
  --arg scenario "$SCENARIO" --arg report_path "$REPORT_FILE" --arg heartbeat_path "$HEARTBEAT_FILE" \
  --arg report_status "$report_status" --arg heartbeat_state "$heartbeat_state" --arg heartbeat_run "$heartbeat_run" \
  --argjson launcher_pid "$LAUNCHER_PID" --argjson monitor_pid "$MONITOR_PID" --argjson launcher_exit "$launcher_exit" \
  --argjson beat_count "$beat_count" '
  {run_id:$run_id,target:$target,direction:$direction,scenario:$scenario,
   launcher_pid:$launcher_pid,monitor_pid:$monitor_pid,launcher_exit:$launcher_exit,
   peer_calls:0,beat_count:$beat_count,report_path:$report_path,heartbeat_path:$heartbeat_path,
   report_status:$report_status,heartbeat_state:$heartbeat_state,heartbeat_run_id:$heartbeat_run,
   handoff_removed:true}
  ' > "$RESULT_FILE"
printf '%s\n' "$RESULT_FILE"
trap - EXIT TERM INT HUP
cleanup

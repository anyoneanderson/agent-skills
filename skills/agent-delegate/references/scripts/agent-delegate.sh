#!/usr/bin/env bash
# agent-delegate.sh — headless cross-invocation of Claude Code and Codex CLI.
#
# This script is the public contract for the agent-delegate skill. Other skills
# call it directly, bypassing SKILL.md. It:
#   1. resolves which peer CLI to drive (self-detection, --target override)
#   2. maps a sandbox stage onto the peer CLI's permission flags
#   3. runs the peer via codex exec / claude -p (prompt over stdin)
#   4. measures touched files from git snapshots (never trusts self-report)
#   5. emits an authoritative atomic terminal report plus detach liveness records
#
# Modes: delegate (task hand-off) and review (adversarial, read-only).
# Directions: claude->codex (primary) and codex->claude (smoke).
#
# Notes for maintainers:
#   - Do NOT use a variable named `status`; it collided with a read-only shell
#     variable in prior work. This file uses `RUN_RC` / `REPORT_STATUS` instead.
#   - report.json is always written to a .tmp then mv'd so callers never read a
#     half-written file. The report exists on success AND failure, always.

set -euo pipefail

# --- constants -------------------------------------------------------------

GLOBAL_CODEX_CONFIG="${HOME}/.codex/config.toml"
DEFAULT_SANDBOX="full-access"
HEARTBEAT_INTERVAL=30
HEARTBEAT_FRESHNESS=90
HANDOFF_TIMEOUT=10
OWNER_LOCK_TIMEOUT=5

# Absolute path to this script, so re-invocation for --detach works regardless
# of the caller's cwd.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF")"
# adversarial-review-prompt.md lives one level up (references/), scripts/ holds this file.
REFERENCES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- CLI-facing arguments (raw) --------------------------------------------

MODE=""
PROMPT_FILE=""
OUT_DIR=""
LABEL=""
TARGET=""
RESUME=""
MODEL=""
EFFORT=""
SANDBOX=""
REVIEW_OUTPUT=""
DETACH=0
FORCE=0
INTERNAL=""   # "", "worker", "monitor" — set only by re-invocation

# --- resolved state (also carried across re-invocation via _AD_* env) ------

DIRECTION=""
RUN_ID=""
RESUMED="false"

# Derived paths (compute_paths()).
REPORT_FILE=""
REPORT_TMP=""
LAST_MSG_FILE=""
STDOUT_FILE=""
STDERR_FILE=""
PID_FILE=""
REVIEW_FILE=""
HEARTBEAT_FILE=""
HEARTBEAT_TMP=""
OWNER_FILE=""
OWNER_TMP=""
OWNER_LOCK=""
CANDIDATE_FILE=""
CANDIDATE_TMP=""
HANDOFF_DIR=""
HANDOFF_ROOT=""
LAUNCHER_PID=""
MONITOR_PID=""
MON_PID=""
TEST_WORKER_PID=""
MONITOR_GUARD_ARMED=0
MONITOR_STARTED_AT=""
MONITOR_WORKER_PID=""
MONITOR_HEARTBEAT_PID=""
REPORT_IS_CANDIDATE=0
REPORT_PUBLISH_ONLY_IF_ABSENT=0
RUN_CLI_APPEND_STDERR=0
OWNER_LOCK_HELD=0
OWNER_LOCK_SIGNAL_GUARD_ACTIVE=0
OWNER_LOCK_PENDING_SIGNAL=""
OWNER_LOCK_SAVED_TERM=""
OWNER_LOCK_SAVED_INT=""
OWNER_LOCK_SAVED_HUP=""
OWNER_LOCK_TEST_SIGNAL_SENT=0

# Sandbox flag outputs (resolve_sandbox_flags()).
CODEX_SANDBOX_VALUE=""
CLAUDE_PERM_MODE=""
CLAUDE_DISALLOW=""

# Command assembled by build_cli_command().
CLI_CMD=()

usage_text() {
  cat <<'EOF'
Usage: agent-delegate.sh --mode <delegate|review> --prompt-file <path> --out-dir <path>
       [--label <slug>] [--target <codex|claude>] [--resume <thread_id>]
       [--model <name>] [--effort <level>]
       [--sandbox <full-access|workspace-write|read-only>]
       [--review-output <path>] [--detach] [--force]

Exit codes: 0 = executed (read status from report.json) | 2 = precondition error
The absolute path of report.json is printed as the last line of stdout.
EOF
}

# Error usage: help text to stderr, exit 2 (a usage error is not success).
usage() { usage_text >&2; exit 2; }
# Explicit --help: help text to stdout, exit 0 (a request, not an error).
show_help() { usage_text; exit 0; }

err() { printf 'agent-delegate: %s\n' "$*" >&2; }

# --- small helpers (patterns borrowed from codex-cli-dispatch.sh) ----------

# Read trust_level for a workspace (or any ancestor) from ~/.codex/config.toml.
# Codex refuses to run in an untrusted workspace, so we fail fast with guidance.
find_trust_level() {
  local dir="$1" level
  [ -f "$GLOBAL_CODEX_CONFIG" ] || return 1
  while :; do
    level="$(awk -v wanted="$dir" '
      $0 == "[projects.\"" wanted "\"]" { in_section=1; next }
      in_section && /^trust_level[[:space:]]*=/ {
        gsub(/^[^=]*=[[:space:]]*"/, "", $0); gsub(/"$/, "", $0); print; exit
      }
      in_section && /^\[/ { in_section=0 }
    ' "$GLOBAL_CODEX_CONFIG")"
    if [ -n "$level" ]; then printf '%s' "$level"; return 0; fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

snapshot_changed_files() {
  # Tracked-modified + untracked (excluding gitignored), sorted for comm.
  # `-C <root>` + `--full-name` pins output to repo-root-relative paths so it
  # matches the root-relative out-dir prefix used for exclusion AND captures
  # changes outside the current working directory (git ls-files without these
  # would be cwd-relative and limited to the cwd subtree).
  # Trailing `|| true` keeps a git failure (e.g. run outside a repo) from
  # aborting the script under set -e + pipefail; the report must still appear.
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    git -C "$root" ls-files --full-name -m -o --exclude-standard 2>/dev/null | sort -u || true
  fi
}

# First non-empty line of the peer's final message, capped at 200 chars.
summarize_last_message() {
  local file="$1"
  if [ ! -s "$file" ]; then printf 'no final message captured'; return; fi
  awk 'NF {print; exit}' "$file" | cut -c1-200
}

# --- target resolution (§4.2) ----------------------------------------------
#
# Priority: --target > CLAUDECODE (we are under Claude Code) > CODEX_* runtime
# markers (we are under Codex) > error. The Codex marker set is confirmed on
# real hardware in T006; CODEX_SANDBOX is the runtime var Codex exports into an
# exec sandbox. AGENT_DELEGATE_HOST is an explicit escape hatch for either side.
resolve_target() {
  if [ -n "$TARGET" ]; then
    case "$TARGET" in
      codex|claude) : ;;
      *) err "invalid --target '$TARGET' (expected codex|claude)"; exit 2 ;;
    esac
  elif [ -n "${AGENT_DELEGATE_HOST:-}" ]; then
    # Host is the side we run on; target is the other side.
    case "${AGENT_DELEGATE_HOST}" in
      claude) TARGET="codex" ;;
      codex)  TARGET="claude" ;;
      *) err "invalid AGENT_DELEGATE_HOST '${AGENT_DELEGATE_HOST}' (expected codex|claude)"; exit 2 ;;
    esac
  elif [ -n "${CLAUDECODE:-}" ]; then
    TARGET="codex"
  elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_SANDBOX_NETWORK_DISABLED:-}" ] || [ -n "${CODEX_HOME:-}" ]; then
    TARGET="claude"
  else
    err "cannot self-detect host CLI; pass --target <codex|claude> (or set AGENT_DELEGATE_HOST)"
    exit 2
  fi

  if [ "$TARGET" = "codex" ]; then DIRECTION="claude->codex"; else DIRECTION="codex->claude"; fi
}

# --- sandbox mapping (§4.6) ------------------------------------------------
#
# One function owns the whole stage->flags table so a future tightening is a
# single-place edit, not a script rewrite.
resolve_sandbox_flags() {
  local stage="$1"
  CODEX_SANDBOX_VALUE=""; CLAUDE_PERM_MODE=""; CLAUDE_DISALLOW=""
  case "$stage" in
    full-access)
      CODEX_SANDBOX_VALUE="danger-full-access"; CLAUDE_PERM_MODE="bypassPermissions" ;;
    workspace-write)
      CODEX_SANDBOX_VALUE="workspace-write";   CLAUDE_PERM_MODE="acceptEdits" ;;
    read-only)
      # claude has no kernel sandbox: plan mode is a policy control, so we also
      # disable write-capable tools. The guarantee gap is documented in contract.md.
      CODEX_SANDBOX_VALUE="read-only"; CLAUDE_PERM_MODE="plan"
      CLAUDE_DISALLOW="Write,Edit,NotebookEdit,Bash" ;;
    *)
      err "invalid sandbox stage '$stage'"; exit 2 ;;
  esac
}

# --- derived paths ---------------------------------------------------------

compute_paths() {
  local stdout_ext="jsonl"
  [ "$TARGET" = "claude" ] && stdout_ext="json"
  REPORT_FILE="${OUT_DIR}/${LABEL}-report.json"
  REPORT_TMP="${OUT_DIR}/${LABEL}-report.json.tmp.${RUN_ID:-pending}"
  LAST_MSG_FILE="${OUT_DIR}/${LABEL}-last.txt"
  STDOUT_FILE="${OUT_DIR}/${LABEL}-stdout.${stdout_ext}"
  STDERR_FILE="${OUT_DIR}/${LABEL}-stderr.log"
  PID_FILE="${OUT_DIR}/${LABEL}.pid"
  HEARTBEAT_FILE="${OUT_DIR}/${LABEL}-heartbeat.json"
  HEARTBEAT_TMP="${HEARTBEAT_FILE}.tmp.${RUN_ID:-pending}"
  OWNER_FILE="${OUT_DIR}/${LABEL}-owner.json"
  OWNER_TMP="${OWNER_FILE}.tmp.${RUN_ID:-pending}"
  OWNER_LOCK="${OUT_DIR}/${LABEL}-owner.lock"
  CANDIDATE_FILE="${OUT_DIR}/${LABEL}-report.candidate.${RUN_ID:-pending}.json"
  CANDIDATE_TMP="${CANDIDATE_FILE}.tmp"
  if [ -z "$REVIEW_OUTPUT" ]; then
    REVIEW_FILE="${OUT_DIR}/${LABEL}-review.md"
  else
    REVIEW_FILE="$REVIEW_OUTPUT"
  fi
}

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

heartbeat_test_mode() { [ "${AGENT_DELEGATE_TEST_MODE:-0}" = heartbeat ]; }
owner_lock_signal_test_mode() { [ "${AGENT_DELEGATE_TEST_MODE:-0}" = owner-lock-signal ]; }

owner_lock_signal_test_hook() {
  local stage="$1" configured="${AGENT_DELEGATE_TEST_OWNER_LOCK_SIGNAL_STAGE:-}"
  local ready_file="${AGENT_DELEGATE_TEST_OWNER_LOCK_READY_FILE:-}" deadline
  owner_lock_signal_test_mode || return 0
  [ "$OWNER_LOCK_TEST_SIGNAL_SENT" -eq 0 ] && [ "$configured" = "$stage" ] || return 0
  if [ -n "$ready_file" ]; then
    deadline=$((SECONDS + 5))
    while [ ! -f "$ready_file" ]; do
      [ "$SECONDS" -lt "$deadline" ] || { err "owner lock signal test readiness timeout"; return 1; }
      sleep 0.01
    done
  fi
  OWNER_LOCK_TEST_SIGNAL_SENT=1
  kill -TERM "${BASHPID:-$$}"
}

heartbeat_test_evidence_json() {
  local suffix="$1" path tmp
  shift
  heartbeat_test_mode || return 0
  path="${OUT_DIR}/${LABEL}-${suffix}.json"
  tmp="${path}.tmp.${BASHPID:-$$}"
  jq -n "$@" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$path"
}

heartbeat_test_evidence_text() {
  local suffix="$1" value="$2" path tmp
  heartbeat_test_mode || return 0
  path="${OUT_DIR}/${LABEL}-${suffix}.txt"
  tmp="${path}.tmp.${BASHPID:-$$}"
  printf '%s\n' "$value" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$path"
}

heartbeat_test_evidence_copy() {
  local suffix="$1" source="$2" path tmp
  heartbeat_test_mode || return 0
  [ -f "$source" ] || return 0
  path="${OUT_DIR}/${LABEL}-${suffix}.json"
  tmp="${path}.tmp.${BASHPID:-$$}"
  cp "$source" "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$path"
}

retry_pause() {
  # Heartbeat tests advance only through FIFO messages and injected timestamps.
  # Production keeps the small polling pause to avoid a busy readiness loop.
  heartbeat_test_mode || sleep 0.05
}

file_hash_or_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    printf '__absent__'
  fi
}

stat_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
stat_uid() { stat -f '%u' "$1" 2>/dev/null || stat -c '%u' "$1"; }
stat_dev() { stat -f '%d' "$1" 2>/dev/null || stat -c '%d' "$1"; }
stat_ino() { stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1"; }

process_probe() {
  local pid="$1" probe
  case "$pid" in ''|*[!0-9]*|0) printf 'absent'; return ;; esac
  probe="$(kill -0 "$pid" 2>&1)" && { printf 'alive'; return; }
  if printf '%s' "$probe" | grep -qi 'not permitted'; then
    printf 'unknown'
  else
    printf 'absent'
  fi
}

owner_lock_capture_signal() {
  local signal="$1"
  [ -n "$OWNER_LOCK_PENDING_SIGNAL" ] || OWNER_LOCK_PENDING_SIGNAL="$signal"
}

owner_lock_restore_signal_trap() {
  local saved="$1" signal="$2"
  if [ -n "$saved" ]; then eval "$saved"; else trap - "$signal"; fi
}

owner_lock_signal_guard_enter() {
  if [ "$OWNER_LOCK_SIGNAL_GUARD_ACTIVE" -eq 1 ]; then
    err "nested owner lock signal guard"
    return 1
  fi
  OWNER_LOCK_PENDING_SIGNAL=""
  OWNER_LOCK_SAVED_TERM="$(trap -p TERM)"
  OWNER_LOCK_SAVED_INT="$(trap -p INT)"
  OWNER_LOCK_SAVED_HUP="$(trap -p HUP)"
  OWNER_LOCK_SIGNAL_GUARD_ACTIVE=1
  trap 'owner_lock_capture_signal TERM' TERM
  trap 'owner_lock_capture_signal INT' INT
  trap 'owner_lock_capture_signal HUP' HUP
}

# Replaying a captured signal only after rmdir prevents a monitor or heartbeat
# publisher from dying while it owns the mkdir-based lock.
owner_lock_signal_guard_leave() {
  local pending saved_term saved_int saved_hup
  [ "$OWNER_LOCK_SIGNAL_GUARD_ACTIVE" -eq 1 ] || return 0
  pending="$OWNER_LOCK_PENDING_SIGNAL"
  saved_term="$OWNER_LOCK_SAVED_TERM"; saved_int="$OWNER_LOCK_SAVED_INT"; saved_hup="$OWNER_LOCK_SAVED_HUP"
  OWNER_LOCK_SIGNAL_GUARD_ACTIVE=0
  OWNER_LOCK_PENDING_SIGNAL=""
  OWNER_LOCK_SAVED_TERM=""; OWNER_LOCK_SAVED_INT=""; OWNER_LOCK_SAVED_HUP=""
  owner_lock_restore_signal_trap "$saved_term" TERM
  owner_lock_restore_signal_trap "$saved_int" INT
  owner_lock_restore_signal_trap "$saved_hup" HUP
  [ -z "$pending" ] || kill -s "$pending" "${BASHPID:-$$}" 2>/dev/null || true
}

acquire_owner_lock() {
  local deadline=$((SECONDS + OWNER_LOCK_TIMEOUT)) holder_pid="" quarantine holder_hash remaining
  owner_lock_signal_guard_enter || return 1
  while ! mkdir "$OWNER_LOCK" 2>/dev/null; do
    if [ -n "$OWNER_LOCK_PENDING_SIGNAL" ]; then
      owner_lock_signal_guard_leave
      return 130
    fi
    if [ "$FORCE" -eq 1 ] && [ -r "$OWNER_LOCK/holder" ]; then
      holder_pid="$(awk -F': ' '$1=="pid"{print $2; exit}' "$OWNER_LOCK/holder" 2>/dev/null || true)"
      if [ "$(process_probe "$holder_pid")" = "absent" ]; then
        quarantine="${OWNER_LOCK}.quarantine.${RUN_ID:-${BASHPID:-$$}}"
        holder_hash="$(file_hash_or_absent "$OWNER_LOCK/holder")"
        if mv "$OWNER_LOCK" "$quarantine" 2>/dev/null; then
          remaining="$(find "$quarantine" -mindepth 1 -maxdepth 1 ! -name holder -print -quit 2>/dev/null || true)"
          if [ -z "$remaining" ] && [ "$(file_hash_or_absent "$quarantine/holder")" = "$holder_hash" ]; then
            rm -f "$quarantine/holder"
            rmdir "$quarantine" 2>/dev/null || true
            continue
          fi
          [ -e "$OWNER_LOCK" ] || mv "$quarantine" "$OWNER_LOCK" 2>/dev/null || true
        fi
      fi
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      err "timed out acquiring owner lock: $OWNER_LOCK"
      owner_lock_signal_guard_leave
      return 1
    fi
    sleep 0.05
  done
  OWNER_LOCK_HELD=1
  if ! {
    printf 'pid: %s\n' "${BASHPID:-$$}"
    printf 'run_id: %s\n' "${RUN_ID:-unknown}"
  } > "$OWNER_LOCK/holder"; then
    release_owner_lock
    return 1
  fi
}

release_owner_lock() {
  [ "$OWNER_LOCK_HELD" -eq 1 ] || return 0
  rm -f "$OWNER_LOCK/holder"
  rmdir "$OWNER_LOCK" 2>/dev/null || true
  OWNER_LOCK_HELD=0
  owner_lock_signal_guard_leave
}

owner_is_valid() {
  local file="$1"
  jq -e '
    (.run_id|type)=="string" and (.run_id|length)>0 and
    (.run_kind=="sync" or .run_kind=="detach") and
    (.runner_pid|type)=="number" and .runner_pid>0 and
    (.launcher_pid|type)=="number" and .launcher_pid>0 and
    ((.monitor_pid==null) or ((.monitor_pid|type)=="number" and .monitor_pid>0)) and
    ((.worker_pid==null) or ((.worker_pid|type)=="number" and .worker_pid>0)) and
    (.started_at|type)=="string" and (.lease_at|type)=="string" and
    ((.handoff_dir==null) or ((.handoff_dir|type)=="string" and (.handoff_dir|startswith("/")))) and
    (.handoff_phase=="not_applicable" or .handoff_phase=="not_started" or
     .handoff_phase=="committed" or .handoff_phase=="verified")
  ' "$file" >/dev/null 2>&1
}

owner_matches_run() {
  local run_id="$1"
  owner_is_valid "$OWNER_FILE" &&
    jq -e --arg run_id "$run_id" '.run_id==$run_id' "$OWNER_FILE" >/dev/null 2>&1
}

pid_matches_run() {
  local run_id="$1" monitor_pid="${2:-}"
  [ -r "$PID_FILE" ] || return 1
  [ "$(awk -F': ' '$1=="run_id"{print $2; exit}' "$PID_FILE")" = "$run_id" ] || return 1
  if [ -n "$monitor_pid" ]; then
    [ "$(awk -F': ' '$1=="pid"{print $2; exit}' "$PID_FILE")" = "$monitor_pid" ] || return 1
  fi
}

report_is_terminal_for_run() {
  local file="$1" run_id="$2"
  jq -e --arg run_id "$run_id" '
    (.status=="done" or .status=="blocked") and .meta.run_id==$run_id
  ' "$file" >/dev/null 2>&1
}

owner_publish_path() {
  local run_id="$1" source="$2" target="$3" require_pid="${4:-0}" monitor_pid="${5:-}"
  acquire_owner_lock || { rm -f "$source"; return 1; }
  if ! owner_matches_run "$run_id" || { [ "$require_pid" -eq 1 ] && ! pid_matches_run "$run_id" "$monitor_pid"; }; then
    release_owner_lock
    rm -f "$source"
    return 3
  fi
  if [ "$REPORT_PUBLISH_ONLY_IF_ABSENT" -eq 1 ] && report_is_terminal_for_run "$target" "$run_id"; then
    release_owner_lock
    rm -f "$source"
    return 0
  fi
  if ! mv -f "$source" "$target"; then
    release_owner_lock
    return 1
  fi
  release_owner_lock
}

owner_remove_runtime() {
  local run_id="$1" require_pid="${2:-0}" monitor_pid="${3:-}"
  acquire_owner_lock || return 1
  if owner_matches_run "$run_id"; then
    if [ "$require_pid" -eq 0 ] || pid_matches_run "$run_id" "$monitor_pid"; then
      [ "$require_pid" -eq 0 ] || rm -f "$PID_FILE"
      rm -f "$OWNER_FILE"
    fi
  fi
  release_owner_lock
}

update_owner_field() {
  local run_id="$1" filter="$2" value="$3" require_pid="${4:-0}" monitor_pid="${5:-}"
  local tmp="${OWNER_FILE}.tmp.${run_id}.update"
  acquire_owner_lock || return 1
  if ! owner_matches_run "$run_id" || { [ "$require_pid" -eq 1 ] && ! pid_matches_run "$run_id" "$monitor_pid"; }; then
    release_owner_lock
    rm -f "$tmp"
    return 3
  fi
  if ! jq --arg value "$value" "$filter" "$OWNER_FILE" > "$tmp" || ! mv -f "$tmp" "$OWNER_FILE"; then
    rm -f "$tmp"
    release_owner_lock
    return 1
  fi
  release_owner_lock
}

move_with_fault_hook() {
  local stage="$1" source="$2" target="$3"
  [ "${AGENT_DELEGATE_TEST_FAIL_STAGE:-}" != "$stage" ] || return 1
  mv -f "$source" "$target"
}

restore_matches_snapshot() {
  local owner_hash="$1" pid_hash="$2" report_hash="$3" heartbeat_hash="$4"
  [ "$(file_hash_or_absent "$OWNER_FILE")" = "$owner_hash" ] &&
    [ "$(file_hash_or_absent "$PID_FILE")" = "$pid_hash" ] &&
    [ "$(file_hash_or_absent "$REPORT_FILE")" = "$report_hash" ] &&
    [ "$(file_hash_or_absent "$HEARTBEAT_FILE")" = "$heartbeat_hash" ]
}

terminate_confirmed_old_process() {
  local pid="$1" role="$2" command i
  case "$pid" in ''|*[!0-9]*|0) return 0 ;; esac
  [ "$pid" != "${BASHPID:-$$}" ] || return 0
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$role" in
    monitor) [[ "$command" == *"$(basename "$SELF")"*"--_monitor"* ]] || return 0 ;;
    worker) [[ "$command" == *"$(basename "$SELF")"*"--_worker"* ]] || return 0 ;;
    runner) [[ "$command" == *"$(basename "$SELF")"* ]] || return 0 ;;
    *) return 0 ;;
  esac
  kill -TERM "$pid" 2>/dev/null || return 0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(process_probe "$pid")" = absent ] && return 0
    sleep 0.1
  done
  kill -KILL "$pid" 2>/dev/null || true
}

publish_detach_owner() {
  local monitor_pid="$1" started_at="$2" pid_tmp="${PID_FILE}.tmp.${RUN_ID}"
  local pid_backup="${PID_FILE}.backup.${RUN_ID}"
  local old_owner_hash old_pid_hash old_report_hash old_heartbeat_hash old_pid_ino=""
  local old_runner_pid="" old_monitor_pid="" old_worker_pid=""

  jq -n \
    --arg run_id "$RUN_ID" --argjson runner_pid "$monitor_pid" \
    --argjson launcher_pid "$LAUNCHER_PID" --argjson monitor_pid "$monitor_pid" \
    --arg started_at "$started_at" --arg handoff_dir "$HANDOFF_DIR" \
    '{run_id:$run_id,run_kind:"detach",runner_pid:$runner_pid,
      launcher_pid:$launcher_pid,monitor_pid:$monitor_pid,worker_pid:null,
      started_at:$started_at,lease_at:$started_at,handoff_dir:$handoff_dir,
      handoff_phase:"not_started"}' > "$OWNER_TMP"
  {
    printf 'pid: %s\n' "$monitor_pid"
    printf 'run_id: %s\n' "$RUN_ID"
    printf 'started: %s\n' "$started_at"
    printf 'command: %s exec/%s %s (%s)\n' "$TARGET" "$MODE" "$LABEL" "$DIRECTION"
  } > "$pid_tmp"
  chmod 600 "$OWNER_TMP" "$pid_tmp"

  acquire_owner_lock || { rm -f "$OWNER_TMP" "$pid_tmp"; return 1; }
  if { [ -e "$OWNER_FILE" ] || [ -e "$PID_FILE" ] || [ -e "$REPORT_FILE" ]; } &&
     [ "$FORCE" -ne 1 ] && [ -z "$RESUME" ]; then
    err "a run for label '$LABEL' is already active (use --force to override)"
    release_owner_lock
    rm -f "$OWNER_TMP" "$pid_tmp"
    return 1
  fi

  old_owner_hash="$(file_hash_or_absent "$OWNER_FILE")"
  old_pid_hash="$(file_hash_or_absent "$PID_FILE")"
  old_report_hash="$(file_hash_or_absent "$REPORT_FILE")"
  old_heartbeat_hash="$(file_hash_or_absent "$HEARTBEAT_FILE")"
  [ ! -e "$PID_FILE" ] || old_pid_ino="$(stat_ino "$PID_FILE")"
  if owner_is_valid "$OWNER_FILE"; then
    old_runner_pid="$(jq -r '.runner_pid // empty' "$OWNER_FILE")"
    old_monitor_pid="$(jq -r '.monitor_pid // empty' "$OWNER_FILE")"
    old_worker_pid="$(jq -r '.worker_pid // empty' "$OWNER_FILE")"
  fi
  if jq -e '.pid|type=="number"' "$HEARTBEAT_FILE" >/dev/null 2>&1; then
    old_worker_pid="$(jq -r '.pid' "$HEARTBEAT_FILE")"
  fi

  rm -f "$pid_backup"
  if [ -e "$PID_FILE" ] && ! mv "$PID_FILE" "$pid_backup"; then
    release_owner_lock
    rm -f "$OWNER_TMP" "$pid_tmp"
    return 1
  fi
  if ! move_with_fault_hook new_pid "$pid_tmp" "$PID_FILE"; then
    [ ! -e "$pid_backup" ] || mv "$pid_backup" "$PID_FILE" || true
    rm -f "$OWNER_TMP" "$pid_tmp"
    if ! restore_matches_snapshot "$old_owner_hash" "$old_pid_hash" "$old_report_hash" "$old_heartbeat_hash"; then
      err "owner publication rollback verification failed after pid publish failure"
    fi
    if [ -n "$old_pid_ino" ] && [ "$(stat_ino "$PID_FILE" 2>/dev/null || true)" != "$old_pid_ino" ]; then
      err "owner publication rollback changed the prior pid inode"
    fi
    release_owner_lock
    return 1
  fi
  if ! move_with_fault_hook owner "$OWNER_TMP" "$OWNER_FILE"; then
    rm -f "$PID_FILE"
    [ ! -e "$pid_backup" ] || mv "$pid_backup" "$PID_FILE" || true
    rm -f "$OWNER_TMP" "$pid_tmp"
    if ! restore_matches_snapshot "$old_owner_hash" "$old_pid_hash" "$old_report_hash" "$old_heartbeat_hash"; then
      err "owner publication rollback verification failed after owner commit failure"
    fi
    if [ -n "$old_pid_ino" ] && [ "$(stat_ino "$PID_FILE" 2>/dev/null || true)" != "$old_pid_ino" ]; then
      err "owner publication rollback changed the prior pid inode"
    fi
    release_owner_lock
    return 1
  fi

  rm -f "$pid_backup" "$REPORT_FILE" "$HEARTBEAT_FILE"
  release_owner_lock
  if [ "$FORCE" -eq 1 ]; then
    terminate_confirmed_old_process "$old_worker_pid" worker
    terminate_confirmed_old_process "$old_monitor_pid" monitor
    [ "$old_runner_pid" = "$old_monitor_pid" ] || terminate_confirmed_old_process "$old_runner_pid" runner
  fi
}

publish_sync_owner() {
  local started_at="$1" runner_pid="${BASHPID:-$$}"
  local old_runner_pid="" old_monitor_pid="" old_worker_pid=""
  jq -n \
    --arg run_id "$RUN_ID" --argjson runner_pid "$runner_pid" --arg started_at "$started_at" \
    '{run_id:$run_id,run_kind:"sync",runner_pid:$runner_pid,
      launcher_pid:$runner_pid,monitor_pid:null,worker_pid:$runner_pid,
      started_at:$started_at,lease_at:$started_at,handoff_dir:null,
      handoff_phase:"not_applicable"}' > "$OWNER_TMP"
  chmod 600 "$OWNER_TMP"
  acquire_owner_lock || { rm -f "$OWNER_TMP"; return 1; }
  if { [ -e "$OWNER_FILE" ] || [ -e "$PID_FILE" ] || [ -e "$REPORT_FILE" ]; } &&
     [ "$FORCE" -ne 1 ] && [ -z "$RESUME" ]; then
    release_owner_lock
    rm -f "$OWNER_TMP"
    err "a run for label '$LABEL' is already active (use --force to override)"
    return 1
  fi
  if owner_is_valid "$OWNER_FILE"; then
    old_runner_pid="$(jq -r '.runner_pid // empty' "$OWNER_FILE")"
    old_monitor_pid="$(jq -r '.monitor_pid // empty' "$OWNER_FILE")"
    old_worker_pid="$(jq -r '.worker_pid // empty' "$OWNER_FILE")"
  fi
  if jq -e '.pid|type=="number"' "$HEARTBEAT_FILE" >/dev/null 2>&1; then
    old_worker_pid="$(jq -r '.pid' "$HEARTBEAT_FILE")"
  fi
  if ! mv -f "$OWNER_TMP" "$OWNER_FILE"; then
    release_owner_lock
    rm -f "$OWNER_TMP"
    return 1
  fi
  rm -f "$PID_FILE" "$REPORT_FILE" "$HEARTBEAT_FILE"
  release_owner_lock
  if [ "$FORCE" -eq 1 ]; then
    terminate_confirmed_old_process "$old_worker_pid" worker
    terminate_confirmed_old_process "$old_monitor_pid" monitor
    [ "$old_runner_pid" = "$old_monitor_pid" ] || terminate_confirmed_old_process "$old_runner_pid" runner
  fi
}

rfc3339_epoch() {
  local value="$1"
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$value" +%s 2>/dev/null ||
    date -u -d "$value" +%s 2>/dev/null
}

classify_handoff_metadata() {
  local path="$1" root="$2" parent="$3" base="$4" type="$5" symlink="$6"
  local uid="$7" mode="$8" dev="$9" ino="${10}" expected_uid="${11}"
  local launcher_pid="${12}" expected_dev="${13:-}" expected_ino="${14:-}"
  local embedded_pid
  [ "$parent" = "$root" ] || return 1
  [[ "$base" =~ ^agent-delegate-handoff\.([0-9]+)\.[A-Za-z0-9_-]+$ ]] || return 1
  embedded_pid="${BASH_REMATCH[1]}"
  [ "$embedded_pid" = "$launcher_pid" ] || return 1
  [ "$type" = "directory" ] && [ "$symlink" = "false" ] || return 1
  [ "$uid" = "$expected_uid" ] && [ "$mode" = "700" ] || return 1
  if [ -n "$expected_dev" ]; then [ "$dev" = "$expected_dev" ] || return 1; fi
  if [ -n "$expected_ino" ]; then [ "$ino" = "$expected_ino" ] || return 1; fi
  [ -n "$path" ]
}

production_handoff_path_is_safe() {
  local path="$1" root="$2" launcher_pid="$3" expected_dev="${4:-}" expected_ino="${5:-}"
  local type="other" symlink="false" uid mode dev ino injected="${AGENT_DELEGATE_TEST_LSTAT_METADATA:-}"
  [ -e "$path" ] || [ -L "$path" ] || return 1
  if heartbeat_test_mode && [ -n "$injected" ]; then
    jq -e '
      .source=="heartbeat_test_injection" and
      (.type|type)=="string" and (.symlink|type)=="boolean" and
      (.uid|type)=="number" and (.mode|type)=="number" and
      (.device|type)=="number" and (.inode|type)=="number"
    ' <<< "$injected" >/dev/null 2>&1 || return 1
    type="$(jq -r '.type' <<< "$injected")"
    symlink="$(jq -r '.symlink' <<< "$injected")"
    uid="$(jq -r '.uid' <<< "$injected")"
    mode="$(jq -r '.mode' <<< "$injected")"
    dev="$(jq -r '.device' <<< "$injected")"
    ino="$(jq -r '.inode' <<< "$injected")"
  else
    [ -L "$path" ] && symlink="true"
    [ -d "$path" ] && type="directory"
    uid="$(stat_uid "$path")"; mode="$(stat_mode "$path")"
    dev="$(stat_dev "$path")"; ino="$(stat_ino "$path")"
  fi
  classify_handoff_metadata "$path" "$root" "$(dirname "$path")" "$(basename "$path")" \
    "$type" "$symlink" "$uid" "$mode" "$dev" "$ino" "$(id -u)" "$launcher_pid" \
    "$expected_dev" "$expected_ino"
}

stale_reap_previous_run() {
  local handoff run_id launcher_pid monitor_pid lease_at lease_epoch now pid_run pid_monitor
  local initial_dev initial_ino sentinel child base remaining
  acquire_owner_lock || return 1
  if ! owner_is_valid "$OWNER_FILE" || ! jq -e '.run_kind=="detach"' "$OWNER_FILE" >/dev/null 2>&1; then
    release_owner_lock
    return 0
  fi
  handoff="$(jq -r '.handoff_dir // empty' "$OWNER_FILE")"
  run_id="$(jq -r '.run_id' "$OWNER_FILE")"
  launcher_pid="$(jq -r '.launcher_pid' "$OWNER_FILE")"
  monitor_pid="$(jq -r '.monitor_pid // empty' "$OWNER_FILE")"
  lease_at="$(jq -r '.lease_at' "$OWNER_FILE")"
  if [ -z "$handoff" ] || ! production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid"; then
    err "stale-reaper retained unsafe handoff path for run $run_id"
    release_owner_lock
    return 0
  fi
  initial_dev="$(stat_dev "$handoff")"; initial_ino="$(stat_ino "$handoff")"
  pid_run="$(awk -F': ' '$1=="run_id"{print $2; exit}' "$PID_FILE" 2>/dev/null || true)"
  pid_monitor="$(awk -F': ' '$1=="pid"{print $2; exit}' "$PID_FILE" 2>/dev/null || true)"
  if [ "$pid_run" != "$run_id" ] || [ "$pid_monitor" != "$monitor_pid" ] ||
     ! jq -e --argjson monitor "$monitor_pid" '.runner_pid==$monitor and .monitor_pid==$monitor' "$OWNER_FILE" >/dev/null 2>&1; then
    err "stale-reaper retained run $run_id because owner and pid do not agree"
    release_owner_lock
    return 0
  fi
  if [ "$(process_probe "$monitor_pid")" != "absent" ]; then
    release_owner_lock
    return 0
  fi
  lease_epoch="$(rfc3339_epoch "$lease_at" || true)"; now="$(date -u +%s)"
  if [ -z "$lease_epoch" ] || [ $((now - lease_epoch)) -le "$HEARTBEAT_FRESHNESS" ]; then
    release_owner_lock
    return 0
  fi

  sentinel="$handoff/handoff-sentinel.json"
  if [ -e "$sentinel" ]; then
    if [ -L "$sentinel" ] || [ ! -f "$sentinel" ] || ! jq -e --arg run_id "$run_id" --argjson launcher "$launcher_pid" \
      --argjson monitor "$monitor_pid" --arg handoff "$handoff" '
        .run_id==$run_id and .launcher_pid==$launcher and .monitor_pid==$monitor and
        .handoff_dir==$handoff and (.created_fifos|type)=="array"
      ' "$sentinel" >/dev/null 2>&1; then
      err "stale-reaper retained invalid_sentinel for run $run_id"
      release_owner_lock
      return 0
    fi
    while IFS= read -r base; do
      case "$base" in launcher-to-monitor.fifo|monitor-to-launcher.fifo) : ;; *)
        err "stale-reaper retained invalid_sentinel FIFO name for run $run_id"
        release_owner_lock
        return 0 ;;
      esac
      child="$handoff/$base"
      production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
      [ ! -L "$child" ] && [ -p "$child" ] || { err "stale-reaper retained invalid_sentinel FIFO type for run $run_id"; release_owner_lock; return 0; }
      rm -f "$child"
    done < <(jq -r '.created_fifos[]' "$sentinel")
    production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
    child="$handoff/handoff-sentinel.json.tmp.$run_id"
    if [ -e "$child" ]; then
      production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
      [ ! -L "$child" ] && [ -f "$child" ] || { err "stale-reaper retained unsafe sentinel temp for run $run_id"; release_owner_lock; return 0; }
      rm -f "$child"
    fi
    production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
    [ ! -L "$sentinel" ] && [ -f "$sentinel" ] || { err "stale-reaper retained unsafe sentinel for run $run_id"; release_owner_lock; return 0; }
    rm -f "$sentinel"
  else
    for base in launcher-to-monitor.fifo monitor-to-launcher.fifo; do
      child="$handoff/$base"
      [ -e "$child" ] || continue
      production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
      [ ! -L "$child" ] && [ -p "$child" ] || continue
      rm -f "$child"
    done
  fi

  remaining="$(find "$handoff" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
  if [ -n "$remaining" ]; then
    err "stale-reaper retained handoff directory with unknown entry: $(basename "$remaining")"
    release_owner_lock
    return 0
  fi
  production_handoff_path_is_safe "$handoff" "$HANDOFF_ROOT" "$launcher_pid" "$initial_dev" "$initial_ino" || { release_owner_lock; return 0; }
  rmdir "$handoff" || { release_owner_lock; return 0; }
  if owner_matches_run "$run_id" && pid_matches_run "$run_id" "$monitor_pid"; then
    rm -f "$PID_FILE" "$OWNER_FILE"
  fi
  release_owner_lock
}

sentinel_path() { printf '%s/handoff-sentinel.json' "$HANDOFF_DIR"; }

write_handoff_sentinel() {
  local state="$1" phase="$2" failure_stage="${3:-}" created="$4"
  local sentinel tmp failure_json="null" control_fifos='[]'
  sentinel="$(sentinel_path)"; tmp="${sentinel}.tmp.${RUN_ID}"
  [ -z "$failure_stage" ] || failure_json="$(printf '%s' "$failure_stage" | jq -R '.')"
  if heartbeat_test_mode; then
    control_fifos='["harness-to-monitor.fifo","monitor-to-harness.fifo"]'
  fi
  jq -n --arg run_id "$RUN_ID" --argjson launcher_pid "$LAUNCHER_PID" \
    --argjson monitor_pid "$MONITOR_PID" --arg state "$state" --arg phase "$phase" \
    --arg handoff_dir "$HANDOFF_DIR" --argjson failure_stage "$failure_json" \
    --argjson control_fifos "$control_fifos" --arg created "$created" --arg created_at "$(utc_now)" '
      {version:1,run_id:$run_id,launcher_pid:$launcher_pid,monitor_pid:$monitor_pid,
       state:$state,handoff_phase:$phase,handoff_dir:$handoff_dir,
       handoff_fifos:["launcher-to-monitor.fifo","monitor-to-launcher.fifo"],
       control_fifos:$control_fifos,created_fifos:($created|split(",")|map(select(length>0))),
       failure_stage:$failure_stage,created_at:$created_at}
    ' > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$sentinel"
}

update_sentinel_phase() {
  local phase="$1" stage="$2" sentinel tmp
  sentinel="$(sentinel_path)"; tmp="${sentinel}.tmp.${RUN_ID}"
  jq --arg phase "$phase" '.handoff_phase=$phase' "$sentinel" > "$tmp"
  chmod 600 "$tmp"
  if ! move_with_fault_hook "$stage" "$tmp" "$sentinel"; then
    rm -f "$tmp"
    return 1
  fi
}

update_owner_phase_best_effort() {
  local phase="$1" stage="$2"
  if [ "${AGENT_DELEGATE_TEST_FAIL_STAGE:-}" = "$stage" ] ||
     ! update_owner_field "$RUN_ID" '.handoff_phase=$value' "$phase" 1 "$MONITOR_PID"; then
    err "owner_phase_mirror_failed $phase"
    rm -f "${OWNER_FILE}.tmp.${RUN_ID}.update"
    return 0
  fi
}

close_monitor_handoff_fds() {
  { exec 14>&-; } 2>/dev/null || true
  { exec 13<&-; } 2>/dev/null || true
  { exec 12>&-; } 2>/dev/null || true
  { exec 11>&-; } 2>/dev/null || true
  close_monitor_launcher_fds
}

close_monitor_launcher_fds() {
  { exec 10>&-; } 2>/dev/null || true
  { exec 9<&-; } 2>/dev/null || true
  { exec 8>&-; } 2>/dev/null || true
  { exec 7>&-; } 2>/dev/null || true
}

close_monitor_control_fds() {
  { exec 14>&-; } 2>/dev/null || true
  { exec 13<&-; } 2>/dev/null || true
  { exec 12>&-; } 2>/dev/null || true
  { exec 11>&-; } 2>/dev/null || true
}

close_launcher_handoff_fds() {
  { exec 8<&-; } 2>/dev/null || true
  { exec 7>&-; } 2>/dev/null || true
}

setup_monitor_handoff() {
  local l2m="$HANDOFF_DIR/launcher-to-monitor.fifo" m2l="$HANDOFF_DIR/monitor-to-launcher.fifo"
  local h2m="$HANDOFF_DIR/harness-to-monitor.fifo" m2h="$HANDOFF_DIR/monitor-to-harness.fifo"
  local created=""
  if ! mkfifo "$l2m"; then write_handoff_sentinel setup_failed not_started fifo_launcher_to_monitor "$created" || true; return 1; fi
  chmod 600 "$l2m"; created="launcher-to-monitor.fifo"
  if ! exec 7<>"$l2m"; then write_handoff_sentinel setup_failed not_started anchor_launcher_to_monitor "$created" || true; return 1; fi
  if heartbeat_test_mode && [ "${AGENT_DELEGATE_TEST_FAIL_STAGE:-}" = fifo_monitor_to_launcher ]; then
    write_handoff_sentinel setup_failed not_started fifo_monitor_to_launcher "$created" || true
    return 1
  fi
  if ! mkfifo "$m2l"; then write_handoff_sentinel setup_failed not_started fifo_monitor_to_launcher "$created" || true; return 1; fi
  chmod 600 "$m2l"; created="$created,monitor-to-launcher.fifo"
  if ! exec 8<>"$m2l"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started anchor_monitor_to_launcher "$created" || true; return 1; fi
  if heartbeat_test_mode; then
    if ! mkfifo "$h2m"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started fifo_harness_to_monitor "$created" || true; return 1; fi
    chmod 600 "$h2m"; created="$created,harness-to-monitor.fifo"
    if ! exec 11<>"$h2m"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started anchor_harness_to_monitor "$created" || true; return 1; fi
    if ! mkfifo "$m2h"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started fifo_monitor_to_harness "$created" || true; return 1; fi
    chmod 600 "$m2h"; created="$created,monitor-to-harness.fifo"
    if ! exec 12<>"$m2h"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started anchor_monitor_to_harness "$created" || true; return 1; fi
  fi
  if ! exec 9<"$l2m"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started reader_launcher_to_monitor "$created" || true; return 1; fi
  if ! exec 10>"$m2l"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started writer_monitor_to_launcher "$created" || true; return 1; fi
  if heartbeat_test_mode; then
    if ! exec 13<"$h2m"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started reader_harness_to_monitor "$created" || true; return 1; fi
    if ! exec 14>"$m2h"; then close_monitor_handoff_fds; write_handoff_sentinel setup_failed not_started writer_monitor_to_harness "$created" || true; return 1; fi
  fi
  write_handoff_sentinel fifo_ready not_started "" "$created"
}

remaining_handoff_seconds() {
  local now remaining
  now="$(date -u +%s)"; remaining=$((HANDOFF_DEADLINE - now))
  [ "$remaining" -gt 0 ] || remaining=0
  printf '%s' "$remaining"
}

monitor_handoff() {
  local line="" remaining expected
  if heartbeat_test_mode; then
    remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
    IFS= read -r -t "$remaining" line <&13 || return 1
    [ "$line" = "harness-ready $RUN_ID" ] && owner_matches_run "$RUN_ID" &&
      pid_matches_run "$RUN_ID" "$MONITOR_PID" || return 1
    printf 'harness-observed ready %s %s\n' "$RUN_ID" "$MONITOR_PID" >&14
    if [ "${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-}" = owner-pid-mismatch ]; then
      awk '/^run_id:/{print "run_id: injected-mismatch"; next} {print}' "$PID_FILE" > "${PID_FILE}.tmp.test-mismatch" &&
        mv -f "${PID_FILE}.tmp.test-mismatch" "$PID_FILE"
    fi
  fi
  remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
  IFS= read -r -t "$remaining" line <&9 || return 1
  expected="handoff-ready $RUN_ID $LAUNCHER_PID $MONITOR_PID"
  if [ "$line" != "$expected" ] || ! owner_matches_run "$RUN_ID" || ! pid_matches_run "$RUN_ID" "$MONITOR_PID"; then
    if heartbeat_test_mode && [ "${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-}" = owner-pid-mismatch ]; then
      awk -v run_id="$RUN_ID" '/^run_id:/{print "run_id: " run_id; next} {print}' "$PID_FILE" > "${PID_FILE}.tmp.test-restore" &&
        mv -f "${PID_FILE}.tmp.test-restore" "$PID_FILE"
    fi
    return 1
  fi
  if heartbeat_test_mode && [ "${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-}" = acknowledgement-mismatch ]; then
    printf 'monitor-ready injected-mismatch %s\n' "$MONITOR_PID" >&10
  else
    printf 'monitor-ready %s %s\n' "$RUN_ID" "$MONITOR_PID" >&10
  fi

  remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
  IFS= read -r -t "$remaining" line <&9 || return 1
  [ "$line" = "handoff-commit $RUN_ID" ] && owner_matches_run "$RUN_ID" || return 1
  update_sentinel_phase committed sentinel_committed || return 1
  update_owner_phase_best_effort committed owner_committed
  printf 'handoff-committed %s %s\n' "$RUN_ID" "$MONITOR_PID" >&10

  remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
  IFS= read -r -t "$remaining" line <&9 || return 1
  [ "$line" = "handoff-verified $RUN_ID $MONITOR_PID verification=ok" ] &&
    owner_matches_run "$RUN_ID" && pid_matches_run "$RUN_ID" "$MONITOR_PID" &&
    jq -e '.handoff_phase=="committed"' "$(sentinel_path)" >/dev/null 2>&1 || return 1
  update_sentinel_phase verified sentinel_verified || return 1
  update_owner_phase_best_effort verified owner_verified
  if heartbeat_test_mode && [ "${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-}" = final-ack-response-lost ]; then
    printf 'handoff-verified-response-lost %s %s\n' "$RUN_ID" "$MONITOR_PID" >&10
    return 0
  fi
  printf 'handoff-verified-ack %s %s\n' "$RUN_ID" "$MONITOR_PID" >&10
}

sentinel_ready_for_mode() {
  local sentinel="$1" run_id="$2" launcher="$3" monitor="$4"
  jq -e --arg run_id "$run_id" --argjson launcher "$launcher" --argjson monitor "$monitor" --arg handoff "$HANDOFF_DIR" '
    .run_id==$run_id and .launcher_pid==$launcher and .monitor_pid==$monitor and
    .handoff_dir==$handoff and .state=="fifo_ready" and .handoff_phase=="not_started" and
    .handoff_fifos==["launcher-to-monitor.fifo","monitor-to-launcher.fifo"]
  ' "$sentinel" >/dev/null 2>&1 || return 1
  [ -p "$HANDOFF_DIR/launcher-to-monitor.fifo" ] &&
    [ -p "$HANDOFF_DIR/monitor-to-launcher.fifo" ] &&
    [ "$(stat_mode "$HANDOFF_DIR/launcher-to-monitor.fifo")" = 600 ] &&
    [ "$(stat_mode "$HANDOFF_DIR/monitor-to-launcher.fifo")" = 600 ] || return 1
  if heartbeat_test_mode; then
    jq -e '.control_fifos==["harness-to-monitor.fifo","monitor-to-harness.fifo"]' "$sentinel" >/dev/null 2>&1 &&
      [ -p "$HANDOFF_DIR/harness-to-monitor.fifo" ] &&
      [ -p "$HANDOFF_DIR/monitor-to-harness.fifo" ] &&
      [ "$(stat_mode "$HANDOFF_DIR/harness-to-monitor.fifo")" = 600 ] &&
      [ "$(stat_mode "$HANDOFF_DIR/monitor-to-harness.fifo")" = 600 ]
  else
    jq -e '.control_fifos==[]' "$sentinel" >/dev/null 2>&1
  fi
}

launcher_wait_for_readiness() {
  local sentinel monitor_pid="$1" owner_run="" owner_monitor="" remaining
  sentinel="$(sentinel_path)"
  while :; do
    remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
    if owner_is_valid "$OWNER_FILE" &&
       jq -e --argjson launcher "${BASHPID:-$$}" --argjson monitor "$monitor_pid" --arg handoff "$HANDOFF_DIR" '
         .run_kind=="detach" and .launcher_pid==$launcher and
         .runner_pid==$monitor and .monitor_pid==$monitor and .worker_pid==null and
         .handoff_dir==$handoff and .handoff_phase=="not_started"
       ' "$OWNER_FILE" >/dev/null 2>&1; then
      owner_run="$(jq -r '.run_id' "$OWNER_FILE")"; owner_monitor="$(jq -r '.monitor_pid' "$OWNER_FILE")"
      if pid_matches_run "$owner_run" "$owner_monitor"; then RUN_ID="$owner_run"; compute_paths; break; fi
    fi
    [ "$(process_probe "$monitor_pid")" != "absent" ] || return 1
    retry_pause
  done
  while :; do
    remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
    if sentinel_ready_for_mode "$sentinel" "$RUN_ID" "${BASHPID:-$$}" "$monitor_pid"; then
      return 0
    fi
    if jq -e '.state=="setup_failed"' "$sentinel" >/dev/null 2>&1; then return 1; fi
    [ "$(process_probe "$monitor_pid")" != "absent" ] || return 1
    retry_pause
  done
}

launcher_complete_handoff() {
  local monitor_pid="$1" line="" remaining sentinel_phase request="${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-normal}"
  exec 7>"$HANDOFF_DIR/launcher-to-monitor.fifo"
  exec 8<"$HANDOFF_DIR/monitor-to-launcher.fifo"
  printf 'handoff-ready %s %s %s\n' "$RUN_ID" "${BASHPID:-$$}" "$monitor_pid" >&7
  heartbeat_test_evidence_json handoff-request --arg message handoff-ready --arg run "$RUN_ID" \
    --argjson launcher "${BASHPID:-$$}" --argjson monitor "$monitor_pid" \
    '{message:$message,run_id:$run,launcher_pid:$launcher,monitor_pid:$monitor}'
  remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
  IFS= read -r -t "$remaining" line <&8 || return 1
  heartbeat_test_evidence_json handoff-acknowledgement --arg raw "$line" '{raw:$raw}'
  if [ "$line" != "monitor-ready $RUN_ID $monitor_pid" ]; then
    return 1
  fi
  if heartbeat_test_mode && [ "$request" = expire-handoff ]; then
    heartbeat_test_evidence_json handoff-request --arg message expire-handoff --arg run "$RUN_ID" \
      '{message:$message,run_id:$run,expired_before_commit:true}'
    return 1
  fi
  printf 'handoff-commit %s\n' "$RUN_ID" >&7
  heartbeat_test_evidence_json handoff-request --arg message handoff-commit --arg run "$RUN_ID" \
    '{message:$message,run_id:$run}'
  remaining="$(remaining_handoff_seconds)"; [ "$remaining" -gt 0 ] || return 1
  IFS= read -r -t "$remaining" line <&8 || return 1
  heartbeat_test_evidence_json handoff-acknowledgement --arg raw "$line" '{raw:$raw}'
  [ "$line" = "handoff-committed $RUN_ID $monitor_pid" ] || return 1
  if heartbeat_test_mode && [ "$request" = final-ack-timeout ]; then
    heartbeat_test_evidence_json handoff-request --arg message handoff-verified --arg run "$RUN_ID" \
      --argjson monitor "$monitor_pid" '{message:$message,run_id:$run,monitor_pid:$monitor,verification:"ok",delivery:"timeout"}'
    return 1
  fi
  printf 'handoff-verified %s %s verification=ok\n' "$RUN_ID" "$monitor_pid" >&7
  heartbeat_test_evidence_json handoff-request --arg message handoff-verified --arg run "$RUN_ID" \
    --argjson monitor "$monitor_pid" '{message:$message,run_id:$run,monitor_pid:$monitor,verification:"ok"}'
  remaining="$(remaining_handoff_seconds)"
  if [ "$remaining" -gt 0 ] && IFS= read -r -t "$remaining" line <&8 &&
     { [ "$line" = "handoff-verified-ack $RUN_ID $monitor_pid" ] ||
       { heartbeat_test_mode && [ "$request" = final-ack-response-lost ] &&
         [ "$line" = "handoff-verified-response-lost $RUN_ID $monitor_pid" ]; }; }; then
    heartbeat_test_evidence_json handoff-acknowledgement --arg raw "$line" '{raw:$raw}'
    return 0
  fi
  sentinel_phase="$(jq -r '.handoff_phase // empty' "$(sentinel_path)" 2>/dev/null || true)"
  [ "$sentinel_phase" = verified ]
}

# --- command assembly (§4.3 / §4.5) ----------------------------------------
#
# Initial and resume invocations are built separately: `codex exec resume` does
# not accept --sandbox or --model (sandbox is fixed at session creation), so
# resuming reuses only the options that subcommand supports.
build_cli_command() {
  # Use explicit `if` blocks (not `test && append`): a trailing conditional that
  # evaluates false would make this function return non-zero and, under set -e,
  # abort the caller before the CLI ever runs.
  CLI_CMD=()
  if [ "$TARGET" = "codex" ]; then
    if [ -n "$RESUME" ]; then
      # `codex exec resume` only has --sandbox verified as unsupported; the -c
      # override is unverified there, so drop effort on resume rather than risk
      # an "unexpected argument" failure. Sandbox/model are already fixed at
      # session creation and cannot change on resume anyway.
      CLI_CMD=( codex exec resume "$RESUME" --json --output-last-message "$LAST_MSG_FILE" )
      if [ -n "$EFFORT" ]; then err "warning: --effort is ignored on codex resume (session settings are fixed at creation)"; fi
    else
      CLI_CMD=( codex exec --sandbox "$CODEX_SANDBOX_VALUE" )
      if [ -n "$MODEL" ]; then CLI_CMD+=( --model "$MODEL" ); fi
      CLI_CMD+=( --skip-git-repo-check --json --output-last-message "$LAST_MSG_FILE" )
      if [ -n "$EFFORT" ]; then CLI_CMD+=( -c "model_reasoning_effort=\"$EFFORT\"" ); fi
    fi
  else
    # claude has no --output-last-message; the final text comes from stdout JSON.
    if [ -n "$RESUME" ]; then
      CLI_CMD=( claude -p --resume "$RESUME" --permission-mode "$CLAUDE_PERM_MODE" --output-format json )
    else
      CLI_CMD=( claude -p --permission-mode "$CLAUDE_PERM_MODE" --output-format json )
    fi
    if [ -n "$MODEL" ]; then CLI_CMD+=( --model "$MODEL" ); fi
    if [ -n "$CLAUDE_DISALLOW" ]; then CLI_CMD+=( --disallowedTools "$CLAUDE_DISALLOW" ); fi
  fi
}

# --- thread_id extraction (§4.5) -------------------------------------------
#
# codex: ONLY the `thread.started` event carries the durable thread id; later
# events return item ids like item_0, so a generic key scan would misfire.
# claude: the result JSON carries .session_id.
extract_thread_id() {
  local id=""
  if [ "$TARGET" = "codex" ]; then
    id="$(jq -rc 'select(.type == "thread.started") | .thread_id' "$STDOUT_FILE" 2>/dev/null | awk 'NF {print; exit}')" || true
  else
    id="$(jq -r '.session_id // empty' "$STDOUT_FILE" 2>/dev/null | awk 'NF {print; exit}')" || true
  fi
  if [ -z "$id" ]; then
    # Continuing a session keeps its id even if the resume output omits it.
    if [ -n "$RESUME" ]; then id="$RESUME"; else id="unknown"; fi
  fi
  printf '%s' "$id"
}

# --- blocker classification (§5.1) -----------------------------------------
#
# Heuristic machine classification from stderr + exit code. The orchestrator may
# re-classify from the blocker text; this only needs to be a useful default.
classify_blocker() {
  local stderr_file="$1" rc="$2"
  if [ -s "$stderr_file" ]; then
    if grep -qiE 'command not found|not installed|no such file' "$stderr_file"; then
      printf 'tool_unavailable'; return
    fi
    if grep -qiE 'timed out|timeout|deadline exceeded' "$stderr_file"; then
      printf 'timeout'; return
    fi
    if grep -qiE 'sandbox|permission denied|read-only file system|operation not permitted' "$stderr_file"; then
      printf 'sandbox_violation'; return
    fi
  fi
  if [ "$rc" = "124" ] || [ "$rc" = "137" ]; then printf 'timeout'; return; fi
  printf 'unclassified'
}

# --- report writer (§5.1, atomic) ------------------------------------------
#
# Every terminal path funnels through here so the schema exists exactly once.
# Inputs are globals set by the caller: REPORT_STATUS, SUMMARY, BLOCKER,
# BLOCKER_CATEGORY, THREAD_ID, TOUCHED_LIST_FILE, plus meta/artifact paths.
write_report() {
  local blocker_json="null" cat_json="null"
  if [ -n "${BLOCKER:-}" ]; then blocker_json="$(printf '%s' "$BLOCKER" | jq -R -s '.')"; fi
  if [ -n "${BLOCKER_CATEGORY:-}" ]; then cat_json="$(printf '%s' "$BLOCKER_CATEGORY" | jq -R '.')"; fi

  local touched_src="${TOUCHED_LIST_FILE:-/dev/null}"
  [ -f "$touched_src" ] || touched_src="/dev/null"

  local artifacts
  artifacts="$(jq -n \
    --arg lm "$LAST_MSG_FILE" --arg so "$STDOUT_FILE" --arg se "$STDERR_FILE" \
    '{last_message: $lm, stdout: $so, stderr: $se}')"
  if [ "$MODE" = "review" ]; then
    artifacts="$(printf '%s' "$artifacts" | jq --arg rf "$REVIEW_FILE" '. + {review_file: $rf}')"
  fi

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --arg st "${REPORT_STATUS}" \
    --arg summary "${SUMMARY:-}" \
    --rawfile touched "$touched_src" \
    --argjson blocker "$blocker_json" \
    --argjson blocker_category "$cat_json" \
    --arg thread "${THREAD_ID:-unknown}" \
    --argjson artifacts "$artifacts" \
    --arg run_id "$RUN_ID" \
    --arg mode "$MODE" \
    --arg direction "$DIRECTION" \
    --arg sandbox "$SANDBOX" \
    --arg model "$MODEL" \
    --argjson resumed "$RESUMED" \
    --arg ts "$ts" \
    '{
      status: $st,
      summary: $summary,
      touchedFiles: (($touched | split("\n")) | map(select(length > 0))),
      blocker: $blocker,
      blocker_category: $blocker_category,
      thread_id: $thread,
      artifacts: $artifacts,
      meta: {
        run_id: $run_id,
        mode: $mode,
        direction: $direction,
        sandbox: $sandbox,
        model: ($model | if . == "" then null else . end),
        resumed: $resumed,
        ts: $ts
      }
    }' > "$REPORT_TMP"
  if [ "$REPORT_IS_CANDIDATE" -eq 1 ]; then
    mv -f "$REPORT_TMP" "$REPORT_FILE"
  else
    owner_publish_path "$RUN_ID" "$REPORT_TMP" "$REPORT_FILE" "${REPORT_REQUIRE_PID:-0}" "${REPORT_MONITOR_PID:-}"
  fi
}

# --- touched-files measurement ---------------------------------------------
#
# comm -13 gives files that appeared/changed during the run. We drop anything
# under out-dir (our own report/logs/review) so a normal review isn't flagged.
# Returns the filtered list on stdout.
compute_touched() {
  local pre="$1" post="$2"
  local raw; raw="$(comm -13 "$pre" "$post" || true)"
  [ -n "$raw" ] || { printf ''; return; }

  # Filter out artifacts written under out-dir, normalized to repo-relative.
  local git_root rel=""
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    local out_abs; out_abs="$(cd "$OUT_DIR" 2>/dev/null && pwd || printf '%s' "$OUT_DIR")"
    case "$out_abs" in
      "$git_root"/*) rel="${out_abs#"$git_root"/}/" ;;
      "$git_root")   rel="" ;;
    esac
  fi
  if [ -n "$rel" ]; then
    # Anchor the prefix at the start of the path so a sibling like "myout/x"
    # is not mistaken for something under "out/".
    awk -v pfx="$rel" 'index($0, pfx) != 1' <<< "$raw" || true
  else
    printf '%s\n' "$raw"
  fi
}

# --- core run: drive the peer CLI once -------------------------------------
#
# Sets: RUN_RC, and writes STDOUT_FILE/STDERR_FILE/LAST_MSG_FILE. Also produces
# TOUCHED_LIST_FILE (filtered) and THREAD_ID. $1 = prompt file to feed on stdin.
RUN_RC=0
run_cli() {
  local prompt_used="$1"
  build_cli_command

  local pre post
  pre="$(mktemp -t agent-delegate.XXXXXX)"; post="$(mktemp -t agent-delegate.XXXXXX)"
  TOUCHED_LIST_FILE="$(mktemp -t agent-delegate.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -f '$pre' '$post'" RETURN

  snapshot_changed_files > "$pre"

  RUN_RC=0
  if [ "$RUN_CLI_APPEND_STDERR" -eq 1 ]; then
    "${CLI_CMD[@]}" < "$prompt_used" > "$STDOUT_FILE" 2>> "$STDERR_FILE" || RUN_RC=$?
  else
    "${CLI_CMD[@]}" < "$prompt_used" > "$STDOUT_FILE" 2> "$STDERR_FILE" || RUN_RC=$?
  fi

  snapshot_changed_files > "$post"
  compute_touched "$pre" "$post" > "$TOUCHED_LIST_FILE"

  # For claude, the final message lives in the result JSON; materialize it into
  # LAST_MSG_FILE so artifacts.last_message is consistent across directions.
  if [ "$TARGET" = "claude" ]; then
    jq -r '.result // .text // empty' "$STDOUT_FILE" 2>/dev/null > "$LAST_MSG_FILE" || true
  fi

  THREAD_ID="$(extract_thread_id)"
}

# --- delegate mode (§4.3) --------------------------------------------------
run_delegate() {
  run_cli "$PROMPT_FILE"

  SUMMARY="$(summarize_last_message "$LAST_MSG_FILE")"
  BLOCKER=""; BLOCKER_CATEGORY=""
  if [ "$RUN_RC" -ne 0 ]; then
    REPORT_STATUS="blocked"
    if [ -s "$STDERR_FILE" ]; then BLOCKER="$(tail -20 "$STDERR_FILE")"; else BLOCKER="$(printf '%s exited with code %s' "$TARGET" "$RUN_RC")"; fi
    BLOCKER_CATEGORY="$(classify_blocker "$STDERR_FILE" "$RUN_RC")"
  else
    REPORT_STATUS="done"
  fi

  # Degrade (not fail) outside a git repo: touchedFiles cannot be measured.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    err "warning: not inside a git repository; touchedFiles will be empty"
    : > "$TOUCHED_LIST_FILE"
  fi

  write_report
}

# --- review mode (§4.4) ----------------------------------------------------
#
# Always read-only. Prompt = adversarial template + caller context. The reviewer
# emits the full review file as its final message; we verify 4 structural points
# then persist it. read-only that still touched files (after excluding our own
# artifacts) is a sandbox misconfiguration, surfaced as sandbox_violation.
run_review() {
  local template="${REFERENCES_DIR}/adversarial-review-prompt.md"
  if [ "${AGENT_DELEGATE_REVIEW_LANG:-en}" = "ja" ] && [ -f "${REFERENCES_DIR}/adversarial-review-prompt.ja.md" ]; then
    template="${REFERENCES_DIR}/adversarial-review-prompt.ja.md"
  fi
  [ -f "$template" ] || { err "review template not found: $template"; exit 2; }

  local combined; combined="$(mktemp -t agent-delegate.XXXXXX)"
  {
    cat "$template"
    printf '\n\n## Review Context\n- Label: %s\n- Direction: %s\n\n---\n\n' "$LABEL" "$DIRECTION"
    cat "$PROMPT_FILE"
  } > "$combined"

  run_cli "$combined"
  rm -f "$combined"

  BLOCKER=""; BLOCKER_CATEGORY=""
  SUMMARY="$(summarize_last_message "$LAST_MSG_FILE")"

  if [ "$RUN_RC" -ne 0 ]; then
    REPORT_STATUS="blocked"
    if [ -s "$STDERR_FILE" ]; then BLOCKER="$(tail -20 "$STDERR_FILE")"; else BLOCKER="$(printf '%s exited with code %s' "$TARGET" "$RUN_RC")"; fi
    BLOCKER_CATEGORY="$(classify_blocker "$STDERR_FILE" "$RUN_RC")"
    write_report
    return
  fi

  # Machine-verify the 4 contract points on the final message.
  local missing=()
  grep -q '^type: review'                         "$LAST_MSG_FILE" || missing+=("type: review")
  grep -q '^## Meta'                              "$LAST_MSG_FILE" || missing+=("## Meta")
  grep -q '^## Findings'                          "$LAST_MSG_FILE" || missing+=("## Findings")
  grep -q '^### Critical'                         "$LAST_MSG_FILE" || missing+=("### Critical")
  grep -q '^### Improvement'                      "$LAST_MSG_FILE" || missing+=("### Improvement")
  grep -q '^### Minor'                            "$LAST_MSG_FILE" || missing+=("### Minor")
  grep -q '^## Summary'                           "$LAST_MSG_FILE" || missing+=("## Summary")
  grep -qE 'Gate:[[:space:]]*(PASS|FAIL)'         "$LAST_MSG_FILE" || missing+=("Gate: PASS|FAIL")

  if [ "${#missing[@]}" -gt 0 ]; then
    # Join with ", " manually: parameter expansion with IFS uses only the first
    # IFS char as the separator, so "IFS=', '" would yield comma-only joins.
    local joined=""
    local item
    for item in "${missing[@]}"; do
      if [ -z "$joined" ]; then joined="$item"; else joined="$joined, $item"; fi
    done
    REPORT_STATUS="blocked"
    BLOCKER="review output malformed: missing $joined"
    BLOCKER_CATEGORY="malformed_output"
    write_report
    return
  fi

  # Well-formed: persist the review file from the final message.
  mkdir -p "$(dirname "$REVIEW_FILE")"
  cp "$LAST_MSG_FILE" "$REVIEW_FILE"

  # read-only must not have modified the workspace (excluding our own artifacts).
  if [ -s "$TOUCHED_LIST_FILE" ]; then
    err "warning: read-only review touched files: $(tr '\n' ' ' < "$TOUCHED_LIST_FILE")"
    REPORT_STATUS="blocked"
    BLOCKER="read-only review unexpectedly modified: $(tr '\n' ' ' < "$TOUCHED_LIST_FILE")"
    BLOCKER_CATEGORY="sandbox_violation"
  else
    REPORT_STATUS="done"
  fi

  write_report
}

run_job() {
  case "$MODE" in
    delegate) run_delegate ;;
    review)   run_review ;;
    *) err "invalid --mode '$MODE'"; exit 2 ;;
  esac
}

# --- synthesize a blocked report when a run dies without one ---------------
#
# Two callers: the detach monitor (if the worker is killed, e.g. kill -9) and
# the synchronous/worker EXIT safety net (if run_job dies via set -e). Either
# way the schema is produced here so callers never re-implement it and
# "report.json exists == the run finished" always holds.
synthesize_blocked_report() {
  REPORT_STATUS="blocked"
  BLOCKER_CATEGORY="env_error"
  if [ -s "$STDERR_FILE" ]; then
    BLOCKER="$(printf 'run exited without a report; stderr tail:\n%s' "$(tail -20 "$STDERR_FILE")")"
  else
    BLOCKER="run exited without producing report.json"
  fi
  SUMMARY="run terminated before completion"
  THREAD_ID="${RESUME:-unknown}"
  TOUCHED_LIST_FILE="$(mktemp -t agent-delegate.XXXXXX)"; : > "$TOUCHED_LIST_FILE"
  write_report
}

publish_handoff_failure_once() {
  local stage="$1" monitor_pid="$2"
  local publish_rc=0
  if report_is_terminal_for_run "$REPORT_FILE" "$RUN_ID"; then return 0; fi
  REPORT_STATUS="blocked"
  BLOCKER_CATEGORY="env_error"
  BLOCKER="detach handoff failed before worker start: $stage"
  SUMMARY="detach handoff failed before worker start"
  THREAD_ID="${RESUME:-unknown}"
  TOUCHED_LIST_FILE="$(mktemp -t agent-delegate.XXXXXX)"; : > "$TOUCHED_LIST_FILE"
  REPORT_PUBLISH_ONLY_IF_ABSENT=1
  REPORT_REQUIRE_PID=1
  REPORT_MONITOR_PID="$monitor_pid"
  write_report || publish_rc=$?
  REPORT_PUBLISH_ONLY_IF_ABSENT=0
  rm -f "$TOUCHED_LIST_FILE"
  [ "$publish_rc" -eq 0 ] && report_is_terminal_for_run "$REPORT_FILE" "$RUN_ID"
}

write_heartbeat() {
  local state="$1" worker_pid="$2" started_at="$3" last_beat="$4"
  local owner_update="${OWNER_FILE}.tmp.${RUN_ID}.lease"
  jq -n --arg run_id "$RUN_ID" --arg state "$state" --argjson pid "$worker_pid" \
    --argjson monitor_pid "$MONITOR_PID" --arg started_at "$started_at" \
    --arg last_beat "$last_beat" --arg target "$TARGET" --arg mode "$MODE" \
    --arg report_path "$REPORT_FILE" '
      {run_id:$run_id,state:$state,pid:$pid,monitor_pid:$monitor_pid,
       started_at:$started_at,last_beat:$last_beat,target:$target,mode:$mode,
       report_path:$report_path}
    ' > "$HEARTBEAT_TMP"
  chmod 600 "$HEARTBEAT_TMP"
  [ "$state" != running ] || owner_lock_signal_test_hook before_acquire
  acquire_owner_lock || { rm -f "$HEARTBEAT_TMP"; return 1; }
  [ "$state" != running ] || owner_lock_signal_test_hook lock_held
  if ! owner_matches_run "$RUN_ID" || ! pid_matches_run "$RUN_ID" "$MONITOR_PID"; then
    release_owner_lock
    rm -f "$HEARTBEAT_TMP"
    return 3
  fi
  if [ "$state" != running ] && ! report_is_terminal_for_run "$REPORT_FILE" "$RUN_ID"; then
    release_owner_lock
    rm -f "$HEARTBEAT_TMP"
    return 1
  fi
  if ! jq --arg last_beat "$last_beat" --argjson worker_pid "$worker_pid" \
    '.lease_at=$last_beat | .worker_pid=$worker_pid' "$OWNER_FILE" > "$owner_update"; then
    rm -f "$HEARTBEAT_TMP" "$owner_update"
    release_owner_lock
    return 1
  fi
  if ! mv -f "$owner_update" "$OWNER_FILE"; then
    rm -f "$owner_update" "$HEARTBEAT_TMP"
    release_owner_lock
    return 1
  fi
  if ! mv -f "$HEARTBEAT_TMP" "$HEARTBEAT_FILE"; then
    rm -f "$HEARTBEAT_TMP"
    release_owner_lock
    return 1
  fi
  release_owner_lock
  [ "$state" != running ] || owner_lock_signal_test_hook after_publish
}

heartbeat_loop() {
  local worker_pid="$1" started_at="$2"
  while :; do
    sleep "$HEARTBEAT_INTERVAL" &
    wait $! || return 0
    [ "$(process_probe "$worker_pid")" != absent ] || return 0
    write_heartbeat running "$worker_pid" "$started_at" "$(utc_now)" || return 0
  done
}

make_blocked_candidate() {
  local reason="$1" saved_report="$REPORT_FILE" saved_tmp="$REPORT_TMP"
  local saved_candidate="$REPORT_IS_CANDIDATE"
  REPORT_FILE="$CANDIDATE_FILE"; REPORT_TMP="$CANDIDATE_TMP"; REPORT_IS_CANDIDATE=1
  REPORT_STATUS="blocked"; BLOCKER_CATEGORY="env_error"; BLOCKER="$reason"
  SUMMARY="run terminated before completion"; THREAD_ID="${RESUME:-unknown}"
  TOUCHED_LIST_FILE="$(mktemp -t agent-delegate.XXXXXX)"; : > "$TOUCHED_LIST_FILE"
  write_report
  rm -f "$TOUCHED_LIST_FILE"
  REPORT_FILE="$saved_report"; REPORT_TMP="$saved_tmp"; REPORT_IS_CANDIDATE="$saved_candidate"
}

publish_worker_candidate() {
  local reason="" status
  if [ ! -e "$CANDIDATE_FILE" ]; then
    reason="worker exited without producing a report candidate"
  elif ! jq -e . "$CANDIDATE_FILE" >/dev/null 2>&1; then
    reason="run exited with an invalid terminal report: invalid JSON"
  elif ! jq -e '(.status=="done" or .status=="blocked")' "$CANDIDATE_FILE" >/dev/null 2>&1; then
    reason="run exited with an invalid terminal report: unknown status"
  elif ! jq -e --arg run_id "$RUN_ID" '.meta.run_id==$run_id' "$CANDIDATE_FILE" >/dev/null 2>&1; then
    reason="run exited with an invalid terminal report: run_id mismatch"
  fi
  if [ -n "$reason" ]; then
    if [ -e "$CANDIDATE_FILE" ]; then
      err "$reason; candidate head: $(head -c 200 "$CANDIDATE_FILE" | tr '\n' ' ')"
    else
      err "$reason"
    fi
    rm -f "$CANDIDATE_FILE"
    make_blocked_candidate "$reason"
  fi
  report_is_terminal_for_run "$CANDIDATE_FILE" "$RUN_ID" || return 1
  status="$(jq -r '.status' "$CANDIDATE_FILE")"
  owner_publish_path "$RUN_ID" "$CANDIDATE_FILE" "$REPORT_FILE" 1 "$MONITOR_PID" || return $?
  printf '%s' "$status"
}

make_heartbeat_test_candidate() {
  local status="$1" variant="${2:-valid}" saved_report="$REPORT_FILE" saved_tmp="$REPORT_TMP"
  local saved_candidate="$REPORT_IS_CANDIDATE" touched
  REPORT_FILE="$CANDIDATE_FILE"; REPORT_TMP="$CANDIDATE_TMP"; REPORT_IS_CANDIDATE=1
  REPORT_STATUS="$status"; SUMMARY="heartbeat test worker completed"
  BLOCKER=""; BLOCKER_CATEGORY=""; THREAD_ID="heartbeat-test-$TARGET"
  if [ "$status" = blocked ]; then
    BLOCKER="heartbeat test worker requested blocked"
    BLOCKER_CATEGORY="unclassified"
  fi
  touched="$(mktemp -t agent-delegate.XXXXXX)"; : > "$touched"; TOUCHED_LIST_FILE="$touched"
  write_report
  rm -f "$touched"
  case "$variant" in
    valid) : ;;
    invalid-json) printf '{' > "$CANDIDATE_FILE" ;;
    invalid-status) jq '.status="unknown"' "$CANDIDATE_FILE" > "$CANDIDATE_TMP" && mv -f "$CANDIDATE_TMP" "$CANDIDATE_FILE" ;;
    wrong-run) jq '.meta.run_id="unexpected-run"' "$CANDIDATE_FILE" > "$CANDIDATE_TMP" && mv -f "$CANDIDATE_TMP" "$CANDIDATE_FILE" ;;
    *) return 1 ;;
  esac
  REPORT_FILE="$saved_report"; REPORT_TMP="$saved_tmp"; REPORT_IS_CANDIDATE="$saved_candidate"
}

start_heartbeat_test_worker() {
  # The worker blocks on the inherited launcher FIFO anchor. It never invokes a
  # peer CLI and is terminated only after the harness supplies a terminal input.
  bash -c 'trap "exit 0" TERM INT HUP; IFS= read -r _ <&7' &
  TEST_WORKER_PID=$!
}

finish_heartbeat_test_run() {
  local worker_pid="$1" started_at="$2" monitor_pid="$3" prior_beat="${4:-}" status terminal_at
  status="$(publish_worker_candidate)" || return 1
  terminal_at="${prior_beat:-$(utc_now)}"
  write_heartbeat "$status" "$worker_pid" "$started_at" "$terminal_at" || return 1
  heartbeat_test_evidence_copy handoff-sentinel-final "$(sentinel_path)"
  heartbeat_test_evidence_copy owner-final "$OWNER_FILE"
  heartbeat_test_evidence_text publisher monitor
  printf 'terminal %s %s %s %s\n' "$status" "$RUN_ID" "$worker_pid" "$terminal_at" >&14
  close_monitor_control_fds
  owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
  cleanup_handoff_dir_owned "$monitor_pid"
}

run_heartbeat_test_session() {
  local started_at="$1" monitor_pid="$2" line command value sequence=0 last_beat=""
  local worker_pid worker_rc=0 beat_epoch last_epoch request="${AGENT_DELEGATE_TEST_HANDOFF_REQUEST:-normal}"

  if [ "$request" = worker-start-failure ]; then
    bash -c 'exit 127' & worker_pid=$!
    wait "$worker_pid" || worker_rc=$?
    heartbeat_test_evidence_json worker-result --argjson attempts 1 --argjson pid "$worker_pid" \
      --argjson exit_code "$worker_rc" '{attempts:$attempts,started:false,pid:$pid,exit_code:$exit_code}'
    close_monitor_launcher_fds
    make_blocked_candidate "heartbeat test worker failed to start (exit $worker_rc)"
    finish_heartbeat_test_run "$worker_pid" "$started_at" "$monitor_pid"
    return
  fi

  start_heartbeat_test_worker
  worker_pid="$TEST_WORKER_PID"
  heartbeat_test_evidence_json worker-result --argjson attempts 1 --argjson pid "$worker_pid" \
    '{attempts:$attempts,started:true,pid:$pid}'
  update_owner_field "$RUN_ID" '.worker_pid=($value|tonumber)' "$worker_pid" 1 "$monitor_pid" || {
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
    return 1
  }
  close_monitor_launcher_fds

  while IFS= read -r line <&13; do
    command="${line%% *}"
    if [ "$line" = "$command" ]; then value=""; else value="${line#* }"; fi
    case "$command" in
      beat)
        beat_epoch="$(rfc3339_epoch "$value" 2>/dev/null || true)"
        [ -n "$beat_epoch" ] || { printf 'rejected beat invalid-time\n' >&14; continue; }
        last_epoch=""
        [ -z "$last_beat" ] || last_epoch="$(rfc3339_epoch "$last_beat" 2>/dev/null || true)"
        if [ -n "$last_epoch" ] && [ "$beat_epoch" -le "$last_epoch" ]; then
          printf 'rejected beat non-monotonic\n' >&14
          continue
        fi
        write_heartbeat running "$worker_pid" "$started_at" "$value" || return 1
        sequence=$((sequence + 1)); last_beat="$value"
        printf 'observed %s running %s\n' "$sequence" "$value" >&14
        ;;
      finish-done|finish-blocked|finish-invalid-json|finish-invalid-status|finish-wrong-run|finish-missing|worker-death)
        case "$command" in
          finish-done) make_heartbeat_test_candidate done valid ;;
          finish-blocked) make_heartbeat_test_candidate blocked valid ;;
          finish-invalid-json) make_heartbeat_test_candidate done invalid-json ;;
          finish-invalid-status) make_heartbeat_test_candidate done invalid-status ;;
          finish-wrong-run) make_heartbeat_test_candidate done wrong-run ;;
          finish-missing) rm -f "$CANDIDATE_FILE" "$CANDIDATE_TMP" ;;
          worker-death) rm -f "$CANDIDATE_FILE" "$CANDIDATE_TMP" ;;
        esac
        kill "$worker_pid" 2>/dev/null || true
        wait "$worker_pid" 2>/dev/null || true
        finish_heartbeat_test_run "$worker_pid" "$started_at" "$monitor_pid" "$last_beat"
        return
        ;;
      *) printf 'rejected command unknown\n' >&14 ;;
    esac
  done
  return 1
}

cleanup_handoff_dir_owned() {
  local monitor_pid="$1" sentinel base child remaining
  sentinel="$(sentinel_path)"
  if [ -e "$sentinel" ] && jq -e --arg run_id "$RUN_ID" --argjson launcher "$LAUNCHER_PID" \
    --argjson monitor "$monitor_pid" --arg handoff "$HANDOFF_DIR" '
      .run_id==$run_id and .launcher_pid==$launcher and .monitor_pid==$monitor and
      .handoff_dir==$handoff and (.created_fifos|type)=="array"
    ' "$sentinel" >/dev/null 2>&1; then
    jq '.state="cleanup_pending"' "$sentinel" > "${sentinel}.tmp.${RUN_ID}" &&
      chmod 600 "${sentinel}.tmp.${RUN_ID}" && mv -f "${sentinel}.tmp.${RUN_ID}" "$sentinel" || true
    heartbeat_test_evidence_copy handoff-sentinel-cleanup "$sentinel"
    while IFS= read -r base; do
      case "$base" in
        launcher-to-monitor.fifo|monitor-to-launcher.fifo) : ;;
        harness-to-monitor.fifo|monitor-to-harness.fifo) heartbeat_test_mode || continue ;;
        *) continue ;;
      esac
      child="$HANDOFF_DIR/$base"
      [ -p "$child" ] && rm -f "$child"
    done < <(jq -r '.created_fifos[]' "$sentinel")
    rm -f "${sentinel}.tmp.${RUN_ID}" "$sentinel"
  else
    for base in launcher-to-monitor.fifo monitor-to-launcher.fifo harness-to-monitor.fifo monitor-to-harness.fifo; do
      case "$base" in harness-*|monitor-to-harness.fifo) heartbeat_test_mode || continue ;; esac
      child="$HANDOFF_DIR/$base"; [ -p "$child" ] && rm -f "$child"
    done
  fi
  remaining="$(find "$HANDOFF_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
  [ -n "$remaining" ] || rmdir "$HANDOFF_DIR" 2>/dev/null || true
}

# EXIT trap for the synchronous and worker paths: if we are leaving without a
# report (an unexpected failure inside run_job under set -e), synthesize a
# blocked one. A clean run has already written REPORT_FILE, so this is a no-op.
SAFETY_NET_ARMED=0
run_job_safety_net() {
  local ec=$?
  [ "$SAFETY_NET_ARMED" = "1" ] || return 0
  if [ ! -f "$REPORT_FILE" ]; then
    err "run terminated (exit $ec) without a report; synthesizing blocked report"
    synthesize_blocked_report || true
  fi
}

# Wrap run_job with the EXIT safety net so a crash still yields a report.json.
run_job_guarded() {
  SAFETY_NET_ARMED=1
  trap run_job_safety_net EXIT
  run_job
  # Clean completion wrote the report; disarm so later exits are untouched.
  SAFETY_NET_ARMED=0
  trap - EXIT
}

# --- re-invocation entry points (env-carried state) ------------------------

export_resolved_env() {
  export _AD_MODE="$MODE" _AD_TARGET="$TARGET" _AD_DIRECTION="$DIRECTION" \
         _AD_LABEL="$LABEL" _AD_SANDBOX="$SANDBOX" _AD_PROMPT_FILE="$PROMPT_FILE" \
         _AD_OUT_DIR="$OUT_DIR" _AD_RESUME="$RESUME" _AD_MODEL="$MODEL" \
         _AD_EFFORT="$EFFORT" _AD_REVIEW_OUTPUT="$REVIEW_OUTPUT" \
         _AD_RUN_ID="$RUN_ID" _AD_RESUMED="$RESUMED" _AD_FORCE="$FORCE" \
         _AD_HANDOFF_DIR="$HANDOFF_DIR" _AD_HANDOFF_ROOT="$HANDOFF_ROOT" \
         _AD_LAUNCHER_PID="$LAUNCHER_PID" _AD_MONITOR_PID="$MONITOR_PID" \
         _AD_HANDOFF_DEADLINE="${HANDOFF_DEADLINE:-0}"
}

import_resolved_env() {
  MODE="${_AD_MODE}"; TARGET="${_AD_TARGET}"; DIRECTION="${_AD_DIRECTION}"
  LABEL="${_AD_LABEL}"; SANDBOX="${_AD_SANDBOX}"; PROMPT_FILE="${_AD_PROMPT_FILE}"
  OUT_DIR="${_AD_OUT_DIR}"; RESUME="${_AD_RESUME}"; MODEL="${_AD_MODEL}"
  EFFORT="${_AD_EFFORT}"; REVIEW_OUTPUT="${_AD_REVIEW_OUTPUT}"
  RUN_ID="${_AD_RUN_ID:-}"; RESUMED="${_AD_RESUMED}"; FORCE="${_AD_FORCE:-0}"
  HANDOFF_DIR="${_AD_HANDOFF_DIR:-}"; HANDOFF_ROOT="${_AD_HANDOFF_ROOT:-}"
  LAUNCHER_PID="${_AD_LAUNCHER_PID:-}"; MONITOR_PID="${_AD_MONITOR_PID:-}"
  HANDOFF_DEADLINE="${_AD_HANDOFF_DEADLINE:-0}"
  resolve_sandbox_flags "$SANDBOX"
  compute_paths
}

run_worker() {
  import_resolved_env
  REPORT_FILE="$CANDIDATE_FILE"
  REPORT_TMP="$CANDIDATE_TMP"
  REPORT_IS_CANDIDATE=1
  RUN_CLI_APPEND_STDERR=1
  run_job_guarded
}

monitor_finalize_abnormal() {
  local reason="$1" monitor_pid="$MONITOR_PID" worker_pid="$MONITOR_WORKER_PID"
  local heartbeat_pid="$MONITOR_HEARTBEAT_PID" pgid="" terminal_status=""
  [ "$MONITOR_GUARD_ARMED" -eq 1 ] || return 0
  MONITOR_GUARD_ARMED=0
  trap - EXIT
  # Ignore a second delivery while terminating our process group. The worker,
  # peer CLI, and heartbeat loop share the monitor's isolated group.
  trap '' TERM INT HUP
  pgid="$(ps -o pgid= -p "$monitor_pid" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$pgid" ] && [ "$pgid" = "$monitor_pid" ]; then
    kill -TERM -- "-$pgid" 2>/dev/null || true
  else
    [ -z "$heartbeat_pid" ] || kill -TERM "$heartbeat_pid" 2>/dev/null || true
    [ -z "$worker_pid" ] || kill -TERM "$worker_pid" 2>/dev/null || true
  fi
  [ -z "$heartbeat_pid" ] || wait "$heartbeat_pid" 2>/dev/null || true
  [ -z "$worker_pid" ] || [ "$worker_pid" = "$monitor_pid" ] || wait "$worker_pid" 2>/dev/null || true
  close_monitor_handoff_fds

  # A terminal report may already have won the race with the signal. Preserve
  # it; otherwise replace any partial candidate with an owned blocked result.
  if report_is_terminal_for_run "$REPORT_FILE" "$RUN_ID"; then
    terminal_status="$(jq -r '.status' "$REPORT_FILE")"
  elif owner_matches_run "$RUN_ID" && pid_matches_run "$RUN_ID" "$monitor_pid"; then
    rm -f "$CANDIDATE_FILE" "$CANDIDATE_TMP"
    if make_blocked_candidate "$reason"; then
      terminal_status="$(publish_worker_candidate)" || terminal_status=""
    fi
  fi
  case "$worker_pid" in ''|*[!0-9]*) worker_pid="$monitor_pid" ;; esac
  case "$terminal_status" in
    done|blocked) write_heartbeat "$terminal_status" "$worker_pid" "$MONITOR_STARTED_AT" "$(utc_now)" || true ;;
  esac
  owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
  cleanup_handoff_dir_owned "$monitor_pid"
}

monitor_signal_guard() {
  local signal="$1"
  monitor_finalize_abnormal "detach monitor received $signal before completion"
  exit 2
}

monitor_exit_guard() {
  local exit_code=$?
  [ "$MONITOR_GUARD_ARMED" -eq 1 ] || return 0
  monitor_finalize_abnormal "detach monitor exited unexpectedly (exit $exit_code)"
}

arm_monitor_guard() {
  MONITOR_STARTED_AT="$1"
  MONITOR_WORKER_PID="$MONITOR_PID"
  MONITOR_HEARTBEAT_PID=""
  MONITOR_GUARD_ARMED=1
  trap 'monitor_signal_guard TERM' TERM
  trap 'monitor_signal_guard INT' INT
  trap 'monitor_signal_guard HUP' HUP
  trap monitor_exit_guard EXIT
}

disarm_monitor_guard() {
  MONITOR_GUARD_ARMED=0
  trap - EXIT TERM INT HUP
}

terminate_remaining_monitor_group() {
  local pgid
  pgid="$(ps -o pgid= -p "$MONITOR_PID" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$pgid" ] && [ "$pgid" = "$MONITOR_PID" ] || return 0
  # A killed worker can orphan the peer CLI in this process group. Keep the
  # monitor alive while terminating every remaining group member.
  trap '' TERM
  kill -TERM -- "-$pgid" 2>/dev/null || true
  trap 'monitor_signal_guard TERM' TERM
}

run_monitor() {
  import_resolved_env
  if command -v uuidgen >/dev/null 2>&1; then RUN_ID="$(uuidgen)"; else RUN_ID="$(date +%s%N)"; fi
  compute_paths
  local started_at monitor_pid worker_pid worker_rc=0 heartbeat_pid terminal_status phase
  started_at="$(utc_now)"; monitor_pid="${BASHPID:-$$}"; MONITOR_PID="$monitor_pid"
  if ! publish_detach_owner "$monitor_pid" "$started_at"; then
    err "failed to publish detach owner and pid"
    return 2
  fi
  : > "$STDERR_FILE"
  if ! setup_monitor_handoff; then
    phase="setup_failed"
    if [ "$(process_probe "$LAUNCHER_PID")" = absent ]; then
      publish_handoff_failure_once "$phase" "$monitor_pid" || err "failed to publish setup failure report"
      owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
      cleanup_handoff_dir_owned "$monitor_pid"
    fi
    return 2
  fi
  if ! monitor_handoff; then
    printf 'handoff-failed %s protocol\n' "$RUN_ID" >&10 2>/dev/null || true
    close_monitor_handoff_fds
    if [ "$(process_probe "$LAUNCHER_PID")" = absent ]; then
      publish_handoff_failure_once protocol "$monitor_pid" || err "failed to publish protocol failure report"
      owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
      cleanup_handoff_dir_owned "$monitor_pid"
    fi
    return 2
  fi
  if heartbeat_test_mode; then
    run_heartbeat_test_session "$started_at" "$monitor_pid" || {
      err "heartbeat test session failed"
      close_monitor_handoff_fds
      owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
      cleanup_handoff_dir_owned "$monitor_pid"
      return 2
    }
    return 0
  fi
  close_monitor_handoff_fds

  # The monitor generated RUN_ID after the launcher exported its initial state.
  # Refresh the environment so the worker writes the matching run candidate.
  arm_monitor_guard "$started_at"
  export_resolved_env
  bash "$SELF" --_worker &
  worker_pid=$!
  MONITOR_WORKER_PID="$worker_pid"
  update_owner_field "$RUN_ID" '.worker_pid=($value|tonumber)' "$worker_pid" 1 "$monitor_pid" || true
  if ! write_heartbeat running "$worker_pid" "$started_at" "$(utc_now)"; then
    monitor_finalize_abnormal "failed to publish initial heartbeat"
    return 2
  fi
  heartbeat_loop "$worker_pid" "$started_at" &
  heartbeat_pid=$!
  MONITOR_HEARTBEAT_PID="$heartbeat_pid"
  wait "$worker_pid" || worker_rc=$?
  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
  MONITOR_HEARTBEAT_PID=""
  if [ ! -e "$CANDIDATE_FILE" ]; then
    err "worker (pid $worker_pid) exited rc=$worker_rc without report candidate"
    terminate_remaining_monitor_group
  fi
  terminal_status="$(publish_worker_candidate)" || {
    err "failed to publish worker report candidate"
    owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
    cleanup_handoff_dir_owned "$monitor_pid"
    return 2
  }
  write_heartbeat "$terminal_status" "$worker_pid" "$started_at" "$(utc_now)" || true
  owner_remove_runtime "$RUN_ID" 1 "$monitor_pid" || true
  cleanup_handoff_dir_owned "$monitor_pid"
  disarm_monitor_guard
}

launch_detach_monitor() {
  local monitor_mode=0
  case $- in *m*) monitor_mode=1 ;; esac
  # nohup only ignores HUP; command runners may terminate the launcher's whole
  # process group after its shell exits. Bash job control gives the monitor a
  # separate process group without relying on non-standard macOS utilities.
  set -m
  nohup bash "$SELF" --_monitor >/dev/null 2>>"$STDERR_FILE" &
  MON_PID=$!
  disown "$MON_PID" 2>/dev/null || true
  [ "$monitor_mode" -eq 1 ] || set +m
}

# --- argument parsing ------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --resume) RESUME="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --sandbox) SANDBOX="$2"; shift 2 ;;
    --review-output) REVIEW_OUTPUT="$2"; shift 2 ;;
    --detach) DETACH=1; shift ;;
    --force) FORCE=1; shift ;;
    --_worker) INTERNAL="worker"; shift ;;
    --_monitor) INTERNAL="monitor"; shift ;;
    -h|--help) show_help ;;
    *) err "unknown argument: $1"; usage ;;
  esac
done

# Internal re-invocations skip parsing/resolution and load from env.
if [ "$INTERNAL" = "worker" ]; then run_worker; exit 0; fi
if [ "$INTERNAL" = "monitor" ]; then run_monitor; exit 0; fi

# --- required-argument validation ------------------------------------------

[ -n "$MODE" ] || { err "missing --mode"; usage; }
case "$MODE" in delegate|review) : ;; *) err "invalid --mode '$MODE' (expected delegate|review)"; usage ;; esac
[ -n "$PROMPT_FILE" ] || { err "missing --prompt-file"; usage; }
[ -n "$OUT_DIR" ] || { err "missing --out-dir"; usage; }

resolve_target

# review is read-only by contract, overriding any --sandbox / env stage.
if [ "$MODE" = "review" ]; then
  # review is read-only by contract, overriding any --sandbox / env stage.
  SANDBOX="read-only"
else
  [ -n "$SANDBOX" ] || SANDBOX="${AGENT_DELEGATE_SANDBOX:-$DEFAULT_SANDBOX}"
fi
resolve_sandbox_flags "$SANDBOX"

[ -n "$LABEL" ] || LABEL="${MODE}-$(date +%s)"
if [ -n "$RESUME" ]; then RESUMED="true"; fi

# --- test mode: print resolved plan, never launch a CLI --------------------
#
# Lets CI assert target resolution and sandbox mapping without a real peer.
if [ "${AGENT_DELEGATE_TEST_MODE:-0}" = "1" ]; then
  compute_paths
  build_cli_command
  printf 'TESTMODE mode=%s direction=%s target=%s sandbox=%s label=%s resume=%s detach=%s force=%s model=%s effort=%s review_output=%s | cmd: %s\n' \
    "$MODE" "$DIRECTION" "$TARGET" "$SANDBOX" "$LABEL" "${RESUME:-}" "$DETACH" "$FORCE" \
    "${MODEL:-}" "${EFFORT:-}" "${REVIEW_OUTPUT:-}" "${CLI_CMD[*]}"
  exit 0
fi

if heartbeat_test_mode && [ "$DETACH" -ne 1 ]; then
  err "AGENT_DELEGATE_TEST_MODE=heartbeat requires --detach"
  exit 2
fi

# --- preconditions (§4.3 steps 1-3) ----------------------------------------

[ -f "$PROMPT_FILE" ] || { err "prompt file not found: $PROMPT_FILE"; exit 2; }

# Peer CLI must exist outside the deterministic heartbeat harness.
if ! heartbeat_test_mode && ! command -v "$TARGET" >/dev/null 2>&1; then
  case "$TARGET" in
    codex)  err "codex CLI not found; install Codex CLI and ensure 'codex' is on PATH" ;;
    claude) err "claude CLI not found; install Claude Code and ensure 'claude' is on PATH" ;;
  esac
  exit 2
fi

# Codex refuses untrusted workspaces; check before doing any work.
if ! heartbeat_test_mode && [ "$TARGET" = "codex" ]; then
  TRUST_LEVEL="$(find_trust_level "$(pwd)" || true)"
  if [ "$TRUST_LEVEL" != "trusted" ]; then
    err "codex workspace trust_level must be 'trusted' (workspace=$(pwd), found=${TRUST_LEVEL:-missing})"
    err "set it in ${GLOBAL_CODEX_CONFIG} under [projects.\"$(pwd)\"] trust_level = \"trusted\""
    exit 2
  fi
fi

# --- resume validation (§4.5) ----------------------------------------------

if [ -n "$RESUME" ]; then
  if [ "$RESUME" = "unknown" ]; then
    err "cannot resume: thread_id is 'unknown' (the prior run failed to capture a session id)"
    exit 2
  fi
  # A prior report for this label/out-dir pins the sandbox the session was
  # created with. codex cannot change sandbox on resume, so a mismatch means the
  # caller wants different permissions and must start a fresh session.
  PRIOR_REPORT="${OUT_DIR}/${LABEL}-report.json"
  if [ -f "$PRIOR_REPORT" ]; then
    if ! jq -e --arg thread "$RESUME" '
      (.status=="done" or .status=="blocked") and .thread_id==$thread and
      (.meta.sandbox|type)=="string"
    ' "$PRIOR_REPORT" >/dev/null 2>&1; then
      err "cannot resume: prior report is invalid, non-terminal, or belongs to another thread_id"
      exit 2
    fi
    PRIOR_SANDBOX="$(jq -r '.meta.sandbox // empty' "$PRIOR_REPORT" 2>/dev/null || true)"
    if [ -n "$PRIOR_SANDBOX" ] && [ "$PRIOR_SANDBOX" != "$SANDBOX" ]; then
      err "resume sandbox mismatch: session was created with '$PRIOR_SANDBOX' but '$SANDBOX' was requested; start a new session to change permissions"
      exit 2
    fi
    if [ "$MODE" = "review" ] && [ -n "$PRIOR_SANDBOX" ] && [ "$PRIOR_SANDBOX" != "read-only" ]; then
      err "review resume requires a read-only session; prior session sandbox was '$PRIOR_SANDBOX'"
      exit 2
    fi
  fi
fi

# --- prepare output dir & normalize paths ----------------------------------

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
PROMPT_FILE="$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")"
[ -n "$REVIEW_OUTPUT" ] && REVIEW_OUTPUT="$(cd "$(dirname "$REVIEW_OUTPUT")" 2>/dev/null && pwd || printf '%s' "$(dirname "$REVIEW_OUTPUT")")/$(basename "$REVIEW_OUTPUT")"

# Runtime metadata injection is reserved for the dedicated heartbeat harness.
# Reject it before creating any owner, pid, FIFO, heartbeat, or blocked report.
if [ -n "${AGENT_DELEGATE_TEST_LSTAT_METADATA:-}" ] && [ "${AGENT_DELEGATE_TEST_MODE:-0}" != heartbeat ]; then
  err "AGENT_DELEGATE_TEST_LSTAT_METADATA is only valid in heartbeat test mode"
  exit 2
fi
if [ -n "${AGENT_DELEGATE_TEST_OWNER_LOCK_SIGNAL_STAGE:-}" ]; then
  if ! owner_lock_signal_test_mode; then
    err "AGENT_DELEGATE_TEST_OWNER_LOCK_SIGNAL_STAGE is only valid in owner lock signal test mode"
    exit 2
  fi
  case "$AGENT_DELEGATE_TEST_OWNER_LOCK_SIGNAL_STAGE" in
    before_acquire|lock_held|after_publish) : ;;
    *) err "invalid owner lock signal test stage"; exit 2 ;;
  esac
elif owner_lock_signal_test_mode; then
  err "owner lock signal test mode requires a signal stage"
  exit 2
fi

HANDOFF_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd)"
compute_paths

# A prior launcher may have died after its parent returned. Reap only a stale,
# fully validated run; ambiguous or live state remains a collision.
stale_reap_previous_run

# Collision guard: a live pid file, or a prior report we are not resuming, is a
# refuse-by-default (override with --force).
if { [ -f "$PID_FILE" ] || [ -f "$OWNER_FILE" ]; } && [ "$FORCE" -ne 1 ]; then
  err "a run for label '$LABEL' is already tracked at $PID_FILE (use --force to override)"
  exit 2
fi
if [ -f "$REPORT_FILE" ] && [ -z "$RESUME" ] && [ "$FORCE" -ne 1 ]; then
  err "a report already exists for label '$LABEL' at $REPORT_FILE (use --force to overwrite or --resume to continue)"
  exit 2
fi

# --- detach: launch monitor wrapper, return immediately (§4.7) -------------

if [ "$DETACH" -eq 1 ]; then
  LAUNCHER_PID="${BASHPID:-$$}"
  HANDOFF_DEADLINE=$(( $(date -u +%s) + HANDOFF_TIMEOUT ))
  if heartbeat_test_mode || owner_lock_signal_test_mode; then
    HANDOFF_DIR="${AGENT_DELEGATE_TEST_HANDOFF_DIR:-}"
    if [ -z "$HANDOFF_DIR" ] || [ "${HANDOFF_DIR#/}" = "$HANDOFF_DIR" ] ||
       [ ! -d "$HANDOFF_DIR" ] || [ -L "$HANDOFF_DIR" ] ||
       [ "$(dirname "$HANDOFF_DIR")" != "$HANDOFF_ROOT" ] ||
       [ "$(stat_uid "$HANDOFF_DIR")" != "$(id -u)" ] ||
       [ "$(stat_mode "$HANDOFF_DIR")" != 700 ] ||
       [ -n "$(find "$HANDOFF_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]; then
      err "test handoff directory must be an empty mode 0700 directory directly under $HANDOFF_ROOT"
      exit 2
    fi
  else
    HANDOFF_DIR="$(mktemp -d "${HANDOFF_ROOT}/agent-delegate-handoff.${LAUNCHER_PID}.XXXXXX")"
    chmod 700 "$HANDOFF_DIR"
  fi
  # The monitor, not the launcher, creates the detach run_id and publishes it
  # in owner.json before any FIFO. The launcher discovers that committed value.
  RUN_ID=""
  compute_paths
  export_resolved_env
  launch_detach_monitor
  trap 'kill "$MON_PID" 2>/dev/null || true; wait "$MON_PID" 2>/dev/null || true' TERM INT HUP

  if ! launcher_wait_for_readiness "$MON_PID"; then
    kill "$MON_PID" 2>/dev/null || true
    wait "$MON_PID" 2>/dev/null || true
    if [ -n "$RUN_ID" ] && owner_matches_run "$RUN_ID"; then
      heartbeat_test_evidence_copy handoff-sentinel-final "$(sentinel_path)"
      heartbeat_test_evidence_copy owner-final "$OWNER_FILE"
      heartbeat_test_evidence_json worker-result --argjson attempts 0 '{attempts:$attempts,started:false}'
      if ! publish_handoff_failure_once readiness "$MON_PID"; then
        owner_remove_runtime "$RUN_ID" 1 "$MON_PID" || true
        cleanup_handoff_dir_owned "$MON_PID"
        err "failed to publish readiness failure report"
        exit 2
      fi
      heartbeat_test_evidence_text publisher launcher
      heartbeat_test_evidence_text launcher-decision pre-handoff
      owner_remove_runtime "$RUN_ID" 1 "$MON_PID" || true
      cleanup_handoff_dir_owned "$MON_PID"
      printf 'run_id: %s\n' "$RUN_ID"
      printf '%s\n' "$REPORT_FILE"
      exit 0
    fi
    cleanup_handoff_dir_owned "$MON_PID"
    err "detach monitor failed before owner and pid publication"
    exit 2
  fi

  if ! launcher_complete_handoff "$MON_PID"; then
    close_launcher_handoff_fds
    kill "$MON_PID" 2>/dev/null || true
    wait "$MON_PID" 2>/dev/null || true
    heartbeat_test_evidence_copy handoff-sentinel-final "$(sentinel_path)"
    heartbeat_test_evidence_copy owner-final "$OWNER_FILE"
    heartbeat_test_evidence_json worker-result --argjson attempts 0 '{attempts:$attempts,started:false}'
    if ! publish_handoff_failure_once handoff "$MON_PID"; then
      owner_remove_runtime "$RUN_ID" 1 "$MON_PID" || true
      cleanup_handoff_dir_owned "$MON_PID"
      err "failed to publish handoff failure report"
      exit 2
    fi
    heartbeat_test_evidence_text publisher launcher
    heartbeat_test_evidence_text launcher-decision pre-handoff
    owner_remove_runtime "$RUN_ID" 1 "$MON_PID" || true
    cleanup_handoff_dir_owned "$MON_PID"
    printf 'run_id: %s\n' "$RUN_ID"
    printf '%s\n' "$REPORT_FILE"
    exit 0
  fi
  heartbeat_test_evidence_text launcher-decision post-handoff
  close_launcher_handoff_fds
  trap - TERM INT HUP
  printf 'run_id: %s\n' "$RUN_ID"
  printf '%s\n' "$REPORT_FILE"
  exit 0
fi

# --- synchronous run -------------------------------------------------------

# Fresh run_id prevents retries from accepting stale shared artifacts. Sync
# publishes a complete owner token while it is executing but never a pid or
# heartbeat file.
if command -v uuidgen >/dev/null 2>&1; then RUN_ID="$(uuidgen)"; else RUN_ID="$(date +%s%N)"; fi
compute_paths
publish_sync_owner "$(utc_now)" || exit 2
run_job_guarded
owner_remove_runtime "$RUN_ID" 0 || true
printf 'run_id: %s\n' "$RUN_ID"
printf '%s\n' "$REPORT_FILE"

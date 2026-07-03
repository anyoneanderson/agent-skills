#!/usr/bin/env bash
# agent-delegate.sh — headless cross-invocation of Claude Code and Codex CLI.
#
# This script is the public contract for the agent-delegate skill. Other skills
# call it directly, bypassing SKILL.md. It:
#   1. resolves which peer CLI to drive (self-detection, --target override)
#   2. maps a sandbox stage onto the peer CLI's permission flags
#   3. runs the peer via codex exec / claude -p (prompt over stdin)
#   4. measures touched files from git snapshots (never trusts self-report)
#   5. emits an atomic report.json whose appearance is the sole completion signal
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
  REPORT_TMP="${OUT_DIR}/${LABEL}-report.json.tmp"
  LAST_MSG_FILE="${OUT_DIR}/${LABEL}-last.txt"
  STDOUT_FILE="${OUT_DIR}/${LABEL}-stdout.${stdout_ext}"
  STDERR_FILE="${OUT_DIR}/${LABEL}-stderr.log"
  PID_FILE="${OUT_DIR}/${LABEL}.pid"
  if [ -z "$REVIEW_OUTPUT" ]; then
    REVIEW_FILE="${OUT_DIR}/${LABEL}-review.md"
  else
    REVIEW_FILE="$REVIEW_OUTPUT"
  fi
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
  mv -f "$REPORT_TMP" "$REPORT_FILE"
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
  "${CLI_CMD[@]}" < "$prompt_used" > "$STDOUT_FILE" 2> "$STDERR_FILE" || RUN_RC=$?

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
         _AD_RUN_ID="$RUN_ID" _AD_RESUMED="$RESUMED"
}

import_resolved_env() {
  MODE="${_AD_MODE}"; TARGET="${_AD_TARGET}"; DIRECTION="${_AD_DIRECTION}"
  LABEL="${_AD_LABEL}"; SANDBOX="${_AD_SANDBOX}"; PROMPT_FILE="${_AD_PROMPT_FILE}"
  OUT_DIR="${_AD_OUT_DIR}"; RESUME="${_AD_RESUME}"; MODEL="${_AD_MODEL}"
  EFFORT="${_AD_EFFORT}"; REVIEW_OUTPUT="${_AD_REVIEW_OUTPUT}"
  RUN_ID="${_AD_RUN_ID}"; RESUMED="${_AD_RESUMED}"
  resolve_sandbox_flags "$SANDBOX"
  compute_paths
}

run_worker() {
  import_resolved_env
  run_job_guarded
}

run_monitor() {
  import_resolved_env
  # Spawn the actual worker and wait. If it dies without a report, synthesize one.
  bash "$SELF" --_worker &
  local worker_pid=$!
  local wrc=0
  wait "$worker_pid" || wrc=$?
  if [ ! -f "$REPORT_FILE" ]; then
    err "worker (pid $worker_pid) exited rc=$wrc without report.json; synthesizing blocked report"
    synthesize_blocked_report
  fi
  rm -f "$PID_FILE"
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

# --- preconditions (§4.3 steps 1-3) ----------------------------------------

[ -f "$PROMPT_FILE" ] || { err "prompt file not found: $PROMPT_FILE"; exit 2; }

# Peer CLI must exist.
if ! command -v "$TARGET" >/dev/null 2>&1; then
  case "$TARGET" in
    codex)  err "codex CLI not found; install Codex CLI and ensure 'codex' is on PATH" ;;
    claude) err "claude CLI not found; install Claude Code and ensure 'claude' is on PATH" ;;
  esac
  exit 2
fi

# Codex refuses untrusted workspaces; check before doing any work.
if [ "$TARGET" = "codex" ]; then
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

# Fresh run_id every invocation: prevents twin launches / same-second collisions
# / retries from mistaking a stale artifact for the current run.
if command -v uuidgen >/dev/null 2>&1; then RUN_ID="$(uuidgen)"; else RUN_ID="$(date +%s%N)"; fi

compute_paths

# Collision guard: a live pid file, or a prior report we are not resuming, is a
# refuse-by-default (override with --force).
if [ -f "$PID_FILE" ] && [ "$FORCE" -ne 1 ]; then
  err "a run for label '$LABEL' is already tracked at $PID_FILE (use --force to override)"
  exit 2
fi
if [ -f "$REPORT_FILE" ] && [ -z "$RESUME" ] && [ "$FORCE" -ne 1 ]; then
  err "a report already exists for label '$LABEL' at $REPORT_FILE (use --force to overwrite or --resume to continue)"
  exit 2
fi

# --- detach: launch monitor wrapper, return immediately (§4.7) -------------

if [ "$DETACH" -eq 1 ]; then
  export_resolved_env
  # nohup + disown detaches the supervisor from this shell so it survives the
  # caller's 10-minute Bash-tool ceiling. The monitor writes the report; here we
  # only announce where it will appear.
  nohup bash "$SELF" --_monitor >/dev/null 2>>"$STDERR_FILE" &
  MON_PID=$!
  disown "$MON_PID" 2>/dev/null || true
  {
    printf 'pid: %s\n' "$MON_PID"
    printf 'run_id: %s\n' "$RUN_ID"
    printf 'started: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'command: %s exec/%s %s (%s)\n' "$TARGET" "$MODE" "$LABEL" "$DIRECTION"
  } > "$PID_FILE"
  printf '%s\n' "$REPORT_FILE"
  exit 0
fi

# --- synchronous run -------------------------------------------------------

run_job_guarded
printf '%s\n' "$REPORT_FILE"

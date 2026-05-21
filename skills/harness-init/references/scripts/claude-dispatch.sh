#!/usr/bin/env bash
# claude-dispatch.sh — claude backend の Task 戻り値後に出力を正規化する。

set -euo pipefail

BRIDGE_SCRIPT=".harness/scripts/codex-progress-bridge.sh"
PROGRESS_APPEND_SCRIPT=".harness/scripts/progress-append.sh"

POST_DISPATCH=0
PHASE=""
ITER=""
ROUND=""
AGENT=""
ROLE=""
SPRINT=""
REPORT_DIR=""
PROMPT_FILE=""

usage() {
  cat <<'EOF' >&2
Usage: claude-dispatch.sh --post-dispatch --phase <negotiation|impl> (--iter <n>|--round <n>) --agent <name> --role <generator|evaluator> --sprint <n> --report-dir <path> [--prompt-file <path>]
EOF
  exit 2
}

warn_progress() {
  local message="$1"
  if [ "${HARNESS_TEST_MODE:-0}" = "1" ]; then
    printf 'WARN %s\n' "$message" >&2
    return
  fi

  if [ -x "$PROGRESS_APPEND_SCRIPT" ]; then
    "$PROGRESS_APPEND_SCRIPT" "WARN ${message}"
  else
    printf 'claude-dispatch WARN: %s\n' "$message" >&2
  fi
}

snapshot_changed_files() {
  git ls-files -m -o --exclude-standard 2>/dev/null \
    | grep -vE "^${REPORT_DIR%/}/" \
    | sort -u || true
}

json_array_from_lines() {
  jq -R -s 'split("\n") | map(select(length > 0))'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --post-dispatch) POST_DISPATCH=1; shift ;;
    --phase) PHASE="$2"; shift 2 ;;
    --iter) ITER="$2"; shift 2 ;;
    --round) ROUND="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ "$POST_DISPATCH" -eq 1 ] || usage
[ -n "$PHASE" ] || usage
[ -n "$AGENT" ] || usage
[ -n "$ROLE" ] || usage
[ -n "$SPRINT" ] || usage
[ -n "$REPORT_DIR" ] || usage
case "$ROLE" in generator|evaluator) ;; *) usage ;; esac

if [ "$PHASE" = "negotiation" ]; then
  [ -n "$ROUND" ] || usage
  COUNTER="$ROUND"
  SUFFIX="neg-${ROUND}"
  COUNTER_FIELD="round"
else
  [ "$PHASE" = "impl" ] || usage
  [ -n "$ITER" ] || usage
  COUNTER="$ITER"
  SUFFIX="$ITER"
  COUNTER_FIELD="iter"
fi

if [ "${HARNESS_TEST_MODE:-0}" = "1" ]; then
  printf 'claude-dispatch (test-mode): phase=%s counter=%s agent=%s role=%s sprint=%s report_dir=%s prompt_file=%s\n' \
    "$PHASE" "$COUNTER" "$AGENT" "$ROLE" "$SPRINT" "$REPORT_DIR" "${PROMPT_FILE:-}"
  exit 0
fi

mkdir -p "$REPORT_DIR"

NARRATIVE_FILE="${REPORT_DIR}/${ROLE}-${SUFFIX}.md"
REPORT_FILE="${REPORT_DIR}/${ROLE}-${SUFFIX}-report.json"

for ext in md json; do
  if [ "$ext" = "md" ]; then
    expected="$NARRATIVE_FILE"
    shadow="${REPORT_DIR}/${ROLE}-iter-${SUFFIX}.md"
  else
    expected="$REPORT_FILE"
    shadow="${REPORT_DIR}/${ROLE}-iter-${SUFFIX}-report.json"
  fi
  if [ ! -f "$expected" ] && [ -f "$shadow" ]; then
    mv "$shadow" "$expected"
    warn_progress "claude-dispatch: renamed shadow ${shadow} -> ${expected}"
  fi
done

TOUCHED_FILE="$(mktemp)"
trap 'rm -f "$TOUCHED_FILE"' EXIT
snapshot_changed_files > "$TOUCHED_FILE"

if [ ! -f "$REPORT_FILE" ]; then
  touched_json="$(json_array_from_lines < "$TOUCHED_FILE")"
  jq -n \
    --arg status "fallback" \
    --arg summary "(fallback: claude-dispatch git ls-files)" \
    --arg reason "report-missing:${REPORT_FILE}" \
    --argjson touched "$touched_json" \
    '{
      status: $status,
      touchedFiles: $touched,
      summary: $summary,
      blocker: null,
      codex_thread_id: null,
      forced_fallback_reason: $reason
    }' > "$REPORT_FILE"
  warn_progress "claude-dispatch: ${REPORT_FILE} missing, synthesised fallback"
fi

if [ ! -f "$NARRATIVE_FILE" ]; then
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '%s\n' '---'
    printf 'role: %s\n' "$ROLE"
    printf '%s: %s\n' "$COUNTER_FIELD" "$COUNTER"
    printf 'sprint: %s\n' "$SPRINT"
    printf 'ts: %s\n' "$TS"
    printf '%s\n' 'backend: claude'
    printf '%s\n' 'forced_fallback_reason: narrative-missing'
    printf '%s\n\n' '---'
    printf '%s\n' '## Summary'
    printf '%s\n\n' '(fallback: claude subagent did not write narrative)'
    printf '%s\n' '## Evidence pointers'
    printf -- '- prompt: `%s`\n' "${PROMPT_FILE:-"(none)"}"
  } > "$NARRATIVE_FILE"
  warn_progress "claude-dispatch: ${NARRATIVE_FILE} missing, synthesised placeholder"
fi

if ! jq -e . "$REPORT_FILE" >/dev/null 2>&1; then
  jq -n \
    --arg status "fallback" \
    --arg summary "(fallback: invalid claude report json)" \
    --arg reason "report-invalid:${REPORT_FILE}" \
    --argjson touched "$(json_array_from_lines < "$TOUCHED_FILE")" \
    '{
      status: $status,
      touchedFiles: $touched,
      summary: $summary,
      blocker: null,
      codex_thread_id: null,
      forced_fallback_reason: $reason
    }' > "$REPORT_FILE"
  warn_progress "claude-dispatch: ${REPORT_FILE} invalid, replaced with fallback"
fi

touched_json="$(json_array_from_lines < "$TOUCHED_FILE")"
jq --argjson touched "$touched_json" '
  .touchedFiles = $touched
  | .summary = (.summary // "(no summary)")
  | .codex_thread_id = (.codex_thread_id // null)
' "$REPORT_FILE" > "${REPORT_FILE}.tmp" && mv "${REPORT_FILE}.tmp" "$REPORT_FILE"

if [ -x "$BRIDGE_SCRIPT" ]; then
  cat "$REPORT_FILE" | "$BRIDGE_SCRIPT" \
    --phase "$PHASE" \
    --iter "$COUNTER" \
    --agent "${AGENT}" \
    --backend-label "Claude" \
    --sprint "$SPRINT"
else
  warn_progress "claude-dispatch: bridge not executable: ${BRIDGE_SCRIPT}"
fi

printf '%s\n' "$REPORT_FILE"

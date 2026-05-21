#!/usr/bin/env bash
# codex-progress-bridge.sh — Orchestrator helper for Generator dispatch
# (originally codex_* only, now backend-agnostic).
#
# When Generator runs via Codex (plugin or cmux), Claude Code's
# PostToolUse(Edit|Write) hook cannot observe Codex's internal edits
# (they happen inside a child process). The Orchestrator therefore
# invokes this script with the report.json that the Generator was
# contracted to write, and we append the equivalent lines to
# progress.md + atomically update _state.json.
#
# Post-dispatch is backend-agnostic (see generator-dispatch.md
# §Post-dispatch); the same bridge call is now used for every backend
# including `claude`. Pass `--backend-label <Label>` to override the
# literal token written into progress.md. If omitted, the bridge infers
# `Claude` from agent names ending in `-claude`; otherwise it keeps the
# legacy `Codex` default. The `<label>-done` summary token is derived by
# lowercasing the label.
#
# Input:  Generator report JSON on stdin
# Args:   --phase <p> --iter <n> --agent <name> [--sprint <n>]
#         [--backend-label <Label>]   default: inferred from --agent
# Env:    HARNESS_TEST_MODE=1 → no file mutations, echo a dry-run note.
#
# Line format (matches progress-append.sh style, so grep is uniform):
#   - <ts> | agent=<name> | phase=<p> | <Label> | <relpath>
#   - <ts> | agent=<name> | phase=<p> | <label>-done | thread=<tid> files=<N> status=<s>

set -euo pipefail

PROGRESS_FILE=".harness/progress.md"
STATE_FILE=".harness/_state.json"

PHASE=""
ITER=""
AGENT=""
SPRINT=""
BACKEND_LABEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)         PHASE="$2"; shift 2 ;;
    --iter)          ITER="$2"; shift 2 ;;
    --agent)         AGENT="$2"; shift 2 ;;
    --sprint)        SPRINT="$2"; shift 2 ;;
    --backend-label) BACKEND_LABEL="$2"; shift 2 ;;
    *) printf 'codex-progress-bridge: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PHASE" ] || { printf 'codex-progress-bridge: --phase required\n' >&2; exit 2; }
[ -n "$ITER" ]  || { printf 'codex-progress-bridge: --iter required\n' >&2; exit 2; }
[ -n "$AGENT" ] || { printf 'codex-progress-bridge: --agent required\n' >&2; exit 2; }

if [ -z "$BACKEND_LABEL" ]; then
  case "$AGENT" in
    *-claude) BACKEND_LABEL="Claude" ;;
    *) BACKEND_LABEL="Codex" ;;
  esac
fi
[ -n "$BACKEND_LABEL" ] || { printf 'codex-progress-bridge: --backend-label cannot be empty\n' >&2; exit 2; }

# Lowercase via tr (bash 3.2-safe; macOS default lacks `${var,,}`).
BACKEND_LABEL_LC="$(printf '%s' "$BACKEND_LABEL" | tr '[:upper:]' '[:lower:]')"

payload="$(cat)"
[ -n "$payload" ] || { printf 'codex-progress-bridge: empty stdin\n' >&2; exit 2; }

# Validate JSON early so we fail loudly instead of silently dropping log entries.
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 \
  || { printf 'codex-progress-bridge: invalid JSON on stdin\n' >&2; exit 2; }

status="$(printf '%s' "$payload" | jq -r '.status // "unknown"')"
thread="$(printf '%s' "$payload" | jq -r '.codex_thread_id // ""')"
summary="$(printf '%s' "$payload" | jq -r '.summary // ""')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$PHASE" = "negotiation" ]; then
  state_counter_field="negotiation_round"
  summary_counter_label="round"
  thread_slot="neg-${ITER}"
else
  state_counter_field="iteration"
  summary_counter_label="iter"
  thread_slot="${ITER}"
fi

# Test mode: emit what we would do, but do not mutate state.
if [ "${HARNESS_TEST_MODE:-0}" = "1" ]; then
  printf 'codex-progress-bridge (test-mode, no writes):\n'
  printf '  phase=%s iter=%s agent=%s sprint=%s\n' "$PHASE" "$ITER" "$AGENT" "$SPRINT"
  printf '  backend_label=%s done_token=%s-done\n' "$BACKEND_LABEL" "$BACKEND_LABEL_LC"
  printf '  status=%s thread=%s files=%s\n' \
    "$status" "$thread" "$(printf '%s' "$payload" | jq -r '.touchedFiles | length')"
  exit 0
fi

mkdir -p "$(dirname "$PROGRESS_FILE")"
[ -f "$PROGRESS_FILE" ] || printf '# Harness progress log (append-only)\n\n' > "$PROGRESS_FILE"

# Per-file lines. Paths are emitted as-is from the report. The Generator
# is expected to write workspace-relative paths; if an absolute path
# slips through (e.g., /private/tmp/... on macOS), we log it verbatim
# rather than guessing workspace relativity.
printf '%s' "$payload" | jq -r '.touchedFiles[]?' | while IFS= read -r f; do
  [ -z "$f" ] && continue
  line="- ${ts} | agent=${AGENT} | phase=${PHASE} | ${BACKEND_LABEL} | ${f}"
  printf '%s\n' "$line" >> "$PROGRESS_FILE"
done

# Summary / <backend>-done line.
count="$(printf '%s' "$payload" | jq -r '.touchedFiles | length')"
summary_line="- ${ts} | agent=${AGENT} | phase=${PHASE} | ${BACKEND_LABEL_LC}-done | ${summary_counter_label}=${ITER} thread=${thread} files=${count} status=${status}"
[ -n "$summary" ] && summary_line+=" summary=\"${summary}\""
printf '%s\n' "$summary_line" >> "$PROGRESS_FILE"

# Update _state.json if present. Single jq pipeline, atomic mv.
if [ -f "$STATE_FILE" ]; then
  tmp="$(mktemp)"
  jq --arg agent "$AGENT" \
     --arg thread "$thread" \
     --arg iter "$ITER" \
     --arg phase "$PHASE" \
     --arg sprint "$SPRINT" \
     --arg counter_field "$state_counter_field" \
     --arg thread_slot "$thread_slot" \
     '
       .last_agent = $agent
       | .[$counter_field] = ($iter | tonumber? // .[$counter_field])
       | .phase = $phase
       | if $thread != ""
           then .codex_thread_ids = (.codex_thread_ids // {})
                | .codex_thread_ids[(.current_sprint|tostring)] = (.codex_thread_ids[(.current_sprint|tostring)] // {})
                | .codex_thread_ids[(.current_sprint|tostring)][$thread_slot] = $thread
           else .
         end
     ' \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
fi

exit 0

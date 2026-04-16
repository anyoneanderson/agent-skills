#!/usr/bin/env bash
# codex-progress-bridge.sh — Orchestrator helper for backend=codex_*
#
# When Generator runs via Codex (plugin or cmux), Claude Code's
# PostToolUse(Edit|Write) hook cannot observe Codex's internal edits
# (they happen inside a child process). This script stands in as the
# authoritative progress recorder: the Orchestrator invokes it after
# every Codex call, passing the report.json that Codex was contracted
# to write. We parse the report and append equivalent lines to
# progress.md + atomically update _state.json.
#
# Input:  Codex report JSON on stdin
# Args:   --phase <p> --iter <n> --agent <name> [--sprint <n>]
# Env:    HARNESS_TEST_MODE=1 → no file mutations, echo a dry-run note.
#
# Line format (matches progress-append.sh style, so grep is uniform):
#   - <ts> | agent=<name> | phase=<p> | Codex | <relpath>
#   - <ts> | agent=<name> | phase=<p> | codex-done | thread=<tid> files=<N> status=<s>

set -euo pipefail

PROGRESS_FILE=".harness/progress.md"
STATE_FILE=".harness/_state.json"

PHASE=""
ITER=""
AGENT=""
SPRINT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)  PHASE="$2"; shift 2 ;;
    --iter)   ITER="$2"; shift 2 ;;
    --agent)  AGENT="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    *) printf 'codex-progress-bridge: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PHASE" ] || { printf 'codex-progress-bridge: --phase required\n' >&2; exit 2; }
[ -n "$ITER" ]  || { printf 'codex-progress-bridge: --iter required\n' >&2; exit 2; }
[ -n "$AGENT" ] || { printf 'codex-progress-bridge: --agent required\n' >&2; exit 2; }

payload="$(cat)"
[ -n "$payload" ] || { printf 'codex-progress-bridge: empty stdin\n' >&2; exit 2; }

# Validate JSON early so we fail loudly instead of silently dropping log entries.
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 \
  || { printf 'codex-progress-bridge: invalid JSON on stdin\n' >&2; exit 2; }

status="$(printf '%s' "$payload" | jq -r '.status // "unknown"')"
thread="$(printf '%s' "$payload" | jq -r '.codex_thread_id // ""')"
summary="$(printf '%s' "$payload" | jq -r '.summary // ""')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Test mode: emit what we would do, but do not mutate state.
if [ "${HARNESS_TEST_MODE:-0}" = "1" ]; then
  printf 'codex-progress-bridge (test-mode, no writes):\n'
  printf '  phase=%s iter=%s agent=%s sprint=%s\n' "$PHASE" "$ITER" "$AGENT" "$SPRINT"
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
  line="- ${ts} | agent=${AGENT} | phase=${PHASE} | Codex | ${f}"
  printf '%s\n' "$line" >> "$PROGRESS_FILE"
done

# Summary / codex-done line.
count="$(printf '%s' "$payload" | jq -r '.touchedFiles | length')"
summary_line="- ${ts} | agent=${AGENT} | phase=${PHASE} | codex-done | iter=${ITER} thread=${thread} files=${count} status=${status}"
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
     '
       .last_agent = $agent
       | .iteration = ($iter | tonumber? // .iteration)
       | .phase = $phase
       | if $thread != ""
           then .codex_thread_ids = (.codex_thread_ids // {})
                | .codex_thread_ids[(.current_sprint|tostring)] = (.codex_thread_ids[(.current_sprint|tostring)] // {})
                | .codex_thread_ids[(.current_sprint|tostring)][$iter] = $thread
           else .
         end
     ' \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
fi

exit 0

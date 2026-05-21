#!/usr/bin/env bash
# codex-cli-dispatch.sh — run the Generator through codex exec and
# canonicalize its outputs for harness-loop.
#
# This helper owns the Codex CLI invocation for backend=codex_cli. It:
#   1. verifies the workspace is trusted in ~/.codex/config.toml
#   2. snapshots tracked-modified + untracked files before/after the run
#   3. invokes codex exec or codex exec resume
#   4. writes generator-neg-<round>.md / generator-<iter>.md and matching report files
#   5. pipes the report into codex-progress-bridge.sh
#
# Counter contract:
#   --phase impl         → artifacts keyed by --iter  (iteration number)
#   --phase negotiation  → artifacts keyed by --round (round number)
# Keeping iteration and round in separate flags prevents a caller that
# resets --iter to 0 between negotiation rounds from clobbering round N's
# artifacts onto neg-0. When --phase negotiation is given without --round,
# the script falls back to --iter (legacy behaviour) with a warning.

set -euo pipefail

WORKSPACE_ROOT="$(pwd)"
CONFIG_FILE=".harness/_config.yml"
GLOBAL_CODEX_CONFIG="${HOME}/.codex/config.toml"
BRIDGE_SCRIPT=".harness/scripts/codex-progress-bridge.sh"

PHASE=""
ITER=""
ROUND=""
AGENT=""
SPRINT=""
PROMPT_FILE=""
REPORT_DIR=""
MODEL=""
EFFORT=""
RESUME_SESSION=""

usage() {
  cat <<'EOF' >&2
Usage: codex-cli-dispatch.sh --phase <phase> --iter <n> [--round <n>] --agent <name> --sprint <n> --prompt-file <path> --report-dir <path> [--model <name>] [--effort <level>] [--resume-session <id>]
  --phase impl         keys artifacts by --iter
  --phase negotiation  keys artifacts by --round (falls back to --iter with a warning if --round omitted)
EOF
  exit 2
}

yaml_value() {
  local key="$1"
  awk -F': ' -v wanted="$key" '$1 == wanted {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$CONFIG_FILE"
}

trim_quotes() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

join_lines_json() {
  jq -R -s '.'
}

summarize_last_message() {
  local file="$1"
  if [ ! -s "$file" ]; then
    printf 'Codex の最終メッセージを取得できなかった。'
    return
  fi

  awk 'NF {print; exit}' "$file" | cut -c1-200
}

find_trust_level() {
  local target="$1"
  local dir="$target"

  [ -f "$GLOBAL_CODEX_CONFIG" ] || return 1

  while :; do
    local level
    level="$(awk -v wanted="$dir" '
      $0 == "[projects.\"" wanted "\"]" { in_section=1; next }
      in_section && /^trust_level[[:space:]]*=/ {
        gsub(/^[^=]*=[[:space:]]*"/, "", $0)
        gsub(/"$/, "", $0)
        print
        exit
      }
      in_section && /^\[/ { in_section=0 }
    ' "$GLOBAL_CODEX_CONFIG")"

    if [ -n "$level" ]; then
      printf '%s' "$level"
      return 0
    fi

    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done

  return 1
}

snapshot_changed_files() {
  git ls-files -m -o --exclude-standard | sort -u
}

while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --iter) ITER="$2"; shift 2 ;;
    --round) ROUND="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --resume-session) RESUME_SESSION="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ "${HARNESS_TEST_MODE:-0}" = "1" ]; then
  printf 'codex-cli-dispatch (test-mode, no exec): phase=%s iter=%s round=%s agent=%s sprint=%s model=%s effort=%s resume_session=%s prompt_file=%s report_dir=%s\n' \
    "$PHASE" "$ITER" "${ROUND:-}" "$AGENT" "$SPRINT" "${MODEL:-}" "${EFFORT:-}" "${RESUME_SESSION:-}" "${PROMPT_FILE:-}" "${REPORT_DIR:-}"
  exit 0
fi

[ -n "$PHASE" ] || usage
[ -n "$ITER" ] || usage
[ -n "$AGENT" ] || usage
[ -n "$SPRINT" ] || usage
[ -n "$PROMPT_FILE" ] || usage
[ -n "$REPORT_DIR" ] || usage
[ -f "$PROMPT_FILE" ] || { printf 'codex-cli-dispatch: prompt file not found: %s\n' "$PROMPT_FILE" >&2; exit 2; }
[ -f "$CONFIG_FILE" ] || { printf 'codex-cli-dispatch: missing %s\n' "$CONFIG_FILE" >&2; exit 2; }
[ -x "$BRIDGE_SCRIPT" ] || { printf 'codex-cli-dispatch: bridge not executable: %s\n' "$BRIDGE_SCRIPT" >&2; exit 2; }

CODEX_BIN="$(trim_quotes "${CODEX_CLI_BINARY:-$(yaml_value codex_cli_binary)}")"
[ -n "$CODEX_BIN" ] || CODEX_BIN="codex"
SANDBOX_MODE="$(trim_quotes "${CODEX_CLI_SANDBOX:-$(yaml_value codex_cli_sandbox)}")"
[ -n "$SANDBOX_MODE" ] || SANDBOX_MODE="danger-full-access"

if [ -z "$MODEL" ]; then
  MODEL="$(trim_quotes "$(yaml_value codex_generator_model)")"
fi
[ -n "$MODEL" ] || MODEL="gpt-5.4"

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  if command -v codex >/dev/null 2>&1; then
    CODEX_BIN="$(command -v codex)"
  else
    printf 'codex-cli-dispatch: codex binary not found: %s\n' "$CODEX_BIN" >&2
    exit 2
  fi
fi

TRUST_LEVEL="$(find_trust_level "$WORKSPACE_ROOT" || true)"
if [ "$TRUST_LEVEL" != "trusted" ]; then
  printf 'codex-cli-dispatch: project trust_level must be trusted (workspace=%s, found=%s)\n' "$WORKSPACE_ROOT" "${TRUST_LEVEL:-missing}" >&2
  exit 2
fi

mkdir -p "$REPORT_DIR"

if [ "$PHASE" = "negotiation" ]; then
  if [ -n "$ROUND" ]; then
    COUNTER_VALUE="$ROUND"
  else
    COUNTER_VALUE="$ITER"
    printf 'WARN: negotiation without --round; falling back to --iter (=%s)\n' "$ITER" >&2
  fi
  FILE_SUFFIX="neg-${COUNTER_VALUE}"
  COUNTER_FIELD="round"
else
  COUNTER_VALUE="$ITER"
  FILE_SUFFIX="${COUNTER_VALUE}"
  COUNTER_FIELD="iter"
fi

LAST_MESSAGE_FILE="${REPORT_DIR}/codex-last-${FILE_SUFFIX}.txt"
STDOUT_FILE="${REPORT_DIR}/codex-exec-${FILE_SUFFIX}.jsonl"
STDERR_FILE="${REPORT_DIR}/codex-exec-${FILE_SUFFIX}.stderr"
NARRATIVE_FILE="${REPORT_DIR}/generator-${FILE_SUFFIX}.md"
REPORT_FILE="${REPORT_DIR}/generator-${FILE_SUFFIX}-report.json"

PRE_DIFF="$(mktemp)"
POST_DIFF="$(mktemp)"
TOUCHED_FILE="$(mktemp)"
trap 'rm -f "$PRE_DIFF" "$POST_DIFF" "$TOUCHED_FILE"' EXIT

snapshot_changed_files > "$PRE_DIFF"

CODEX_EXIT=0
EFFORT_ARGS=()
if [ -n "$EFFORT" ]; then
  EFFORT_ARGS=(-c "model_reasoning_effort=\"${EFFORT}\"")
fi

if [ -n "$RESUME_SESSION" ]; then
  "$CODEX_BIN" exec resume "$RESUME_SESSION" \
    --model "$MODEL" \
    --skip-git-repo-check \
    --json \
    --output-last-message "$LAST_MESSAGE_FILE" \
    "${EFFORT_ARGS[@]}" \
    < "$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE" || CODEX_EXIT=$?
else
  "$CODEX_BIN" exec \
    --sandbox "$SANDBOX_MODE" \
    --model "$MODEL" \
    --skip-git-repo-check \
    --json \
    --output-last-message "$LAST_MESSAGE_FILE" \
    "${EFFORT_ARGS[@]}" \
    < "$PROMPT_FILE" >"$STDOUT_FILE" 2>"$STDERR_FILE" || CODEX_EXIT=$?
fi

snapshot_changed_files > "$POST_DIFF"
comm -13 "$PRE_DIFF" "$POST_DIFF" > "$TOUCHED_FILE"

SUMMARY="$(summarize_last_message "$LAST_MESSAGE_FILE")"
STATUS="done"
BLOCKER_JSON="null"
NEXT_ACTION="Evaluator に引き渡して継続。"

if [ "$CODEX_EXIT" -ne 0 ]; then
  STATUS="blocked"
  if [ -s "$STDERR_FILE" ]; then
    BLOCKER_JSON="$(tail -20 "$STDERR_FILE" | join_lines_json)"
  else
    BLOCKER_JSON="$(printf 'codex exec exited with code %s' "$CODEX_EXIT" | jq -R '.')"
  fi
  NEXT_ACTION="blocker を解消して再実行。"
fi

THREAD_ID="$(
  jq -r '
    .id? // .session_id? // .conversation_id? // .thread_id? // .session.id? // empty
  ' "$STDOUT_FILE" 2>/dev/null | awk 'NF {print; exit}'
)"
[ -n "$THREAD_ID" ] || THREAD_ID="unknown"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$NARRATIVE_FILE" <<EOF
---
role: generator
${COUNTER_FIELD}: ${COUNTER_VALUE}
sprint: ${SPRINT}
ts: ${TS}
backend: codex_cli
---

## Summary
${SUMMARY}

## Approach
- \`codex exec\` を直接起動し、最終メッセージと Git 差分から結果を正規化した。
- authoritative な \`touchedFiles\` は dispatch script 側で計算した。

## Concerns
- status: \`${STATUS}\`

## Evidence pointers
- prompt: \`${PROMPT_FILE}\`
- last-message: \`${LAST_MESSAGE_FILE}\`
- stdout(jsonl): \`${STDOUT_FILE}\`
- stderr: \`${STDERR_FILE}\`

## Next action
${NEXT_ACTION}
EOF

jq -n \
  --arg status "$STATUS" \
  --arg summary "$SUMMARY" \
  --argjson blocker "$BLOCKER_JSON" \
  --arg thread "$THREAD_ID" \
  --rawfile touched "$TOUCHED_FILE" \
  '{
    status: $status,
    touchedFiles: (($touched | split("\n")) | map(select(length > 0))),
    summary: $summary,
    blocker: $blocker,
    codex_thread_id: $thread
  }' > "$REPORT_FILE"

# The bridge keys negotiation artifacts off its own --iter as neg-<n> and
# writes negotiation_round=<n>; pass the resolved counter (round for
# negotiation, iter for impl) so the bridge stays consistent with the
# generator-neg-<round> artifacts written above.
cat "$REPORT_FILE" | "$BRIDGE_SCRIPT" \
  --phase "$PHASE" \
  --iter "$COUNTER_VALUE" \
  --agent "$AGENT" \
  --sprint "$SPRINT"

printf '%s\n' "$REPORT_FILE"

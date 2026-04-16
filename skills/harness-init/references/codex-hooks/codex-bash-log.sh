#!/usr/bin/env bash
# codex-bash-log.sh — Codex PostToolUse hook (matcher: Bash)
#
# Codex's PreToolUse/PostToolUse matcher currently only supports the
# Bash tool (2026-04 spec). We take advantage of this narrow support
# to record every Bash command Codex runs (test / build / lint / etc.)
# into .harness/progress.md. Write tool calls are invisible to this
# hook — those are handled by the Orchestrator-side bridge via
# report.json.
#
# Input:  Codex PostToolUse JSON on stdin. Fields of interest:
#   - tool_input.command
#   - tool_response (shape varies by Codex version; often a JSON string
#     holding {exit_code, stdout, stderr} but treat as opaque)
# Output: silent exit 0 (fail open). We never block PostToolUse.

set -eu

PROGRESS_FILE=".harness/progress.md"

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "${cwd:-}" ] && cd "$cwd" 2>/dev/null || true

[ -d ".harness" ] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
[ -n "$cmd" ] || exit 0

# tool_response may be a string that is itself JSON, or a JSON object.
# Parse leniently: try .tool_response.exit_code, fall back to jq-parsing
# a string payload, finally fall back to no exit code.
exit_code="$(printf '%s' "$payload" \
  | jq -r '
    (.tool_response // empty)
    | if type == "object" then (.exit_code // empty | tostring)
      elif type == "string" then
        (try (fromjson | .exit_code // empty | tostring) catch "")
      else "" end
  ' 2>/dev/null || true)"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Trim excessively long command for readability. Exact command is in
# the Codex session log; progress.md only needs a handle.
cmd_short="$cmd"
if [ "${#cmd_short}" -gt 200 ]; then
  cmd_short="${cmd_short:0:197}..."
fi

mkdir -p "$(dirname "$PROGRESS_FILE")"
[ -f "$PROGRESS_FILE" ] || printf '# Harness progress log (append-only)\n\n' > "$PROGRESS_FILE"

line="- ${ts} | agent=codex | phase=bash | codex-bash | cmd=\"${cmd_short}\""
[ -n "${exit_code:-}" ] && line+=" | exit=${exit_code}"
printf '%s\n' "$line" >> "$PROGRESS_FILE"

exit 0

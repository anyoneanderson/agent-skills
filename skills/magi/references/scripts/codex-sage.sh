#!/usr/bin/env bash
# codex-sage.sh — run `codex exec`, preserving configured tools by default and
# optionally switching them off for a confidential council run.
#
# With no wrapper-specific flag, arguments pass directly to `codex exec`. The
# runner appends `--confidential` from isolation_args only when the user selects
# Confidential scope; this script consumes that flag and enables fail-closed
# isolation before starting codex.
#
# The blocking is split between two mechanisms on purpose:
#   - `--disable plugins --disable apps` covers servers supplied by plugins and
#     apps. Those cannot be switched off one by one: aiming
#     `-c mcp_servers.<name>.enabled=false` at such a server makes codex fail
#     with an "invalid transport" error instead of disabling anything.
#   - `-c mcp_servers.<name>.enabled=false`, one per server codex reports, covers
#     the servers the operator configured. codex has no single flag that turns
#     all of them off, so they are enumerated.
#
# The names come from `codex mcp list --json --disable plugins` — codex's own
# configuration loader — rather than from parsing config.toml here. TOML has
# several ways to declare the same server (a [mcp_servers.<name>] header, an
# inline table under [mcp_servers], dotted `mcp_servers.<name>.command` keys, an
# indented header), and a hand-written parser silently misses some of them. A
# missed server stays enabled, which is the leak this script exists to prevent.
# Asking codex also picks up configuration this script never sees, such as
# project-level settings and a relocated $CODEX_HOME. Passing `--disable plugins`
# to the list call keeps plugin-supplied servers out of the result, so every name
# it returns is one that `-c` can switch off.
#
# It fails closed. If that list cannot be obtained, cannot be parsed, or holds a
# name this script cannot turn into an override, codex exec is not started: not
# knowing which servers to block is no reason to send the question anyway. No name
# is ever skipped — skipping one is exactly how a server would stay enabled.
#
# The list is a snapshot taken at startup. A configuration change made between the
# listing and codex's own load would not be blocked; see "known limits" in
# references/sages.md.
#
# Requires codex-cli 0.145.0 or newer, the version `mcp list --json` and the
# `--disable` flag were verified against (2026-07-27). An older codex rejects the
# unknown flag, this wrapper stops, and the sage is recorded as no answer — the
# council degrades, and the question still does not leak.
#
# Exit codes: whatever `codex exec` returns | 2 = the set of servers to disable
# could not be established.

set -euo pipefail

err() { printf 'codex-sage: %s\n' "$*" >&2; }

CONFIDENTIAL=0
CODEX_ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--confidential" ]; then
    CONFIDENTIAL=1
  else
    CODEX_ARGS+=("$arg")
  fi
done

if [ "$CONFIDENTIAL" -eq 0 ]; then
  exec codex exec "${CODEX_ARGS[@]+"${CODEX_ARGS[@]}"}"
fi

command -v jq >/dev/null 2>&1 || {
  err "jq not found on PATH, and it is required to read the MCP server list"
  exit 2
}

# stderr is left attached so codex's own diagnosis (an unknown flag on an older
# release, a malformed config) lands in this sage's stderr file beside the refusal
# below.
if ! SERVER_JSON="$(codex mcp list --json --disable plugins)"; then
  err "listing MCP servers failed: 'codex mcp list --json --disable plugins' returned non-zero"
  err "refusing to start codex exec while the set of servers to disable is unknown (requires codex-cli 0.145.0 or newer)"
  exit 2
fi

# Shape check before extraction, so an empty roster — valid, and common — is told
# apart from output this script cannot interpret. It checks only that every entry
# carries a string name; whether that string can become an override is checked per
# name below, where the message can quote the offending server.
if ! printf '%s' "$SERVER_JSON" |
  jq -e 'type == "array" and all(.[]; type == "object" and (.name | type) == "string")' >/dev/null 2>&1; then
  err "cannot read the MCP server list: 'codex mcp list --json' did not return an array of objects carrying a name"
  err "refusing to start codex exec while the set of servers to disable is unknown"
  exit 2
fi

DISABLE_ARGS=()
while IFS= read -r name; do
  case "$name" in
    '' | *[!A-Za-z0-9_-]*)
      # An empty name, or one outside this character set, cannot be turned into a
      # reliable dotted `-c` path. Skipping it would leave that server enabled,
      # which is the leak this script exists to prevent, so the run stops here: a
      # sage recorded as failed is recoverable, a question sent to an undisclosed
      # provider is not. An empty name also appears when codex reports a name
      # containing a newline, which this line protocol cannot carry.
      err "cannot disable MCP server \"${name}\": a server name must be non-empty and plain [A-Za-z0-9_-] to become a -c override"
      err "rename that server, or remove it from the codex configuration, before convening the council"
      exit 2
      ;;
  esac
  DISABLE_ARGS+=(-c "mcp_servers.${name}.enabled=false")
done < <(printf '%s' "$SERVER_JSON" | jq -r '.[].name')

# The array expansion is guarded because an operator with no MCP servers leaves it
# empty, and bash 3.2 under `set -u` treats "${arr[@]}" on an empty array as an
# unbound variable.
exec codex exec --disable plugins --disable apps \
  "${DISABLE_ARGS[@]+"${DISABLE_ARGS[@]}"}" \
  "${CODEX_ARGS[@]+"${CODEX_ARGS[@]}"}"

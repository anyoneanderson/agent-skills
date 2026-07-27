#!/usr/bin/env bash
# codex-sage.sh — run `codex exec` with the operator's MCP servers, plugins and
# apps switched off, so a council question reaches the OpenAI provider and
# nothing else.
#
# Why this wrapper exists: a sage inherits whatever codex configuration the
# operator already has, and that routinely includes MCP servers pointed at other
# companies' services. Without this isolation, a question the skill announced as
# going to three providers can be handed to a fourth by a tool call that neither
# the host nor the user ever sees (design §8, provider boundary).
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
# It fails closed. If that list cannot be obtained or cannot be parsed, codex exec
# is not started: not knowing which servers to block is no reason to send the
# question anyway.
#
# Requires codex-cli 0.145.0 or newer, the version `mcp list --json` and the
# `--disable` flag were verified against (2026-07-27). An older codex rejects the
# unknown flag, this wrapper stops, and the sage is recorded as no answer — the
# council degrades, and the question still does not leak.
#
# Exit codes: whatever `codex exec` returns | 2 = the MCP server list could not be
# determined | 3 = codex reported a server name that cannot be expressed as a
# `-c` override.

set -euo pipefail

err() { printf 'codex-sage: %s\n' "$*" >&2; }

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
# apart from output this script cannot interpret.
if ! printf '%s' "$SERVER_JSON" |
  jq -e 'type == "array" and all(.[]; type == "object" and (.name | type) == "string")' >/dev/null 2>&1; then
  err "cannot read the MCP server list: 'codex mcp list --json' did not return an array of objects carrying a name"
  err "refusing to start codex exec while the set of servers to disable is unknown"
  exit 2
fi

DISABLE_ARGS=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$name" in
    *[!A-Za-z0-9_-]*)
      # A name outside this set cannot be turned into a reliable dotted `-c` path,
      # and leaving that server enabled is the very leak this script prevents.
      # Stop instead: a sage recorded as failed is recoverable, a question sent to
      # an undisclosed provider is not.
      err "cannot disable MCP server '${name}': the name is not plain [A-Za-z0-9_-], so it cannot be expressed as a -c override"
      err "rename that server, or remove it from the codex configuration, before convening the council"
      exit 3
      ;;
  esac
  DISABLE_ARGS+=(-c "mcp_servers.${name}.enabled=false")
done < <(printf '%s' "$SERVER_JSON" | jq -r '.[].name')

# The array expansion is guarded because an operator with no MCP servers leaves it
# empty, and bash 3.2 under `set -u` treats "${arr[@]}" on an empty array as an
# unbound variable.
exec codex exec --disable plugins --disable apps \
  "${DISABLE_ARGS[@]+"${DISABLE_ARGS[@]}"}" "$@"

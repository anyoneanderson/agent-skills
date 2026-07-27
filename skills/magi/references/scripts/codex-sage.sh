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
#     apps. Those have no [mcp_servers.<name>] section of their own, and aiming
#     `-c mcp_servers.<name>.enabled=false` at one makes codex fail with an
#     "invalid transport" error rather than disabling anything.
#   - `-c mcp_servers.<name>.enabled=false`, one per server named in config.toml,
#     covers the servers the operator declared there. codex has no single flag
#     that turns all of them off, so they are enumerated.
#
# Verified with codex-cli 0.145.0 on 2026-07-27: the registered tool count drops
# from 141 to 19, no MCP-backed tool remains, and asking for a tool from one of
# those servers is answered with "no such tool is registered".
#
# Every argument is forwarded, so the adapter in sages.default.json keeps naming
# the flags codex needs (--sandbox read-only, --output-last-message, -).
#
# Exit codes: whatever `codex exec` returns | 3 = a declared MCP server this
# wrapper cannot switch off with certainty, which fails the sage closed.

set -euo pipefail

err() { printf 'codex-sage: %s\n' "$*" >&2; }

CONFIG_FILE="${CODEX_HOME:-${HOME}/.codex}/config.toml"
DISABLE_ARGS=()

if [ -f "$CONFIG_FILE" ]; then
  # One name per declared server: the capture stops at the first `.` or `]`, so
  # `[mcp_servers.foo]` and `[mcp_servers.foo.env]` both yield `foo` and `sort -u`
  # collapses them into a single -c argument.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      *[!A-Za-z0-9_-]*)
        # A quoted or otherwise exotic TOML key cannot be turned into a `-c`
        # override reliably, and leaving it enabled is the very leak this script
        # prevents. Stop instead: a sage recorded as failed is recoverable, a
        # question sent to an undisclosed provider is not.
        err "cannot disable MCP server [mcp_servers.${name}] in ${CONFIG_FILE}: the name is not plain [A-Za-z0-9_-]"
        err "rename that section, or remove it, before convening the council"
        exit 3
        ;;
    esac
    DISABLE_ARGS+=(-c "mcp_servers.${name}.enabled=false")
  done < <(sed -n 's/^\[mcp_servers\.\([^].]*\).*$/\1/p' "$CONFIG_FILE" | sort -u)
fi

# The array expansion is guarded because an operator with no MCP servers leaves it
# empty, and bash 3.2 under `set -u` treats "${arr[@]}" on an empty array as an
# unbound variable.
exec codex exec --disable plugins --disable apps \
  "${DISABLE_ARGS[@]+"${DISABLE_ARGS[@]}"}" "$@"

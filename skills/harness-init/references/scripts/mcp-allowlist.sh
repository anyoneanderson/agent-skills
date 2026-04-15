#!/usr/bin/env bash
# mcp-allowlist.sh — PreToolUse hook (matcher: mcp__.*)
#
# Denies MCP tool invocations whose server prefix is not listed in
# _config.yml.allowed_mcp_servers. Requirement ref: REQ-101.
#
# Tool names follow the convention "mcp__<server>__<tool>". We extract
# <server> and compare against the allow-list.

set -euo pipefail

CONFIG_FILE=".harness/_config.yml"

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""')"

# Not an MCP call → allow (matcher should have filtered, but be defensive).
case "$tool_name" in
  mcp__*) : ;;
  *) printf '{}\n'; exit 0 ;;
esac

# Extract server: mcp__<server>__<tool> → <server>
rest="${tool_name#mcp__}"
server="${rest%%__*}"

# No config → deny (fail-closed in strict mode is safer than failing open).
if [ ! -f "$CONFIG_FILE" ]; then
  jq -n --arg t "$tool_name" \
    '{decision:"deny", reason:("mcp-allowlist: no _config.yml; denying " + $t)}'
  exit 0
fi

# Parse allowed_mcp_servers from YAML (supports inline "[a, b, c]" form or
# block "- a" form). Fall back to empty list on parse failure.
allowed="$(
  awk '
    /^allowed_mcp_servers:/ {
      rest = $0; sub(/^allowed_mcp_servers:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        gsub(/[][\047"]/, "", rest); gsub(/,/, " ", rest)
        print rest; exit
      }
      inblock = 1; next
    }
    inblock {
      if ($0 ~ /^[^[:space:]-]/) { inblock = 0; next }
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        gsub(/["\047]/, "", item); printf "%s ", item
      }
    }
  ' "$CONFIG_FILE"
)"

for a in $allowed; do
  if [ "$a" = "$server" ]; then
    printf '{}\n'
    exit 0
  fi
done

jq -n --arg s "$server" --arg t "$tool_name" --arg a "$allowed" \
  '{decision:"deny", reason:("mcp-allowlist: server \"" + $s + "\" not in allow-list [" + $a + "] for tool " + $t)}'
exit 0

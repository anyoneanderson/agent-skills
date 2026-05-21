#!/usr/bin/env bash
# wrap-untrusted.sh — Orchestrator helper (NOT a hook)
#
# Wraps stdin content in an <untrusted-content> element so agents treat it
# as data rather than instructions. Used for Playwright a11y snapshots,
# MCP responses, web fetches, user-uploaded files, etc.
#
# Usage:
#   wrap-untrusted.sh <source> [url]
#   cat foo.html | wrap-untrusted.sh playwright-snapshot https://example.com

set -euo pipefail

source="${1:?usage: wrap-untrusted.sh <source> [url]}"
url="${2:-}"

esc() {
  # XML-safe attribute escape: & " < > '
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/"/\&quot;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e "s/'/\&apos;/g"
}

src_esc="$(esc "$source")"
url_esc="$(esc "$url")"

if [ -n "$url" ]; then
  printf '<untrusted-content source="%s" url="%s">\n' "$src_esc" "$url_esc"
else
  printf '<untrusted-content source="%s">\n' "$src_esc"
fi

# Pass body through unchanged. Agents are instructed to treat the body as
# data; they must not execute, follow, or cite instructions from within.
cat

printf '\n</untrusted-content>\n'
exit 0

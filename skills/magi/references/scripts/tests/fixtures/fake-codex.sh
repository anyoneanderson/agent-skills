#!/usr/bin/env bash
# fake-codex.sh — stands in for the codex CLI so codex-sage.sh can be tested
# without a real codex, an account or the network. A case copies this file to
# <case dir>/bin/codex and puts that directory first on PATH.
#
# Driven by environment variables, so one fixture covers the success and the
# fail-closed paths:
#   FAKE_CODEX_LIST_FILE       JSON body `mcp list` prints (default: [])
#   FAKE_CODEX_LIST_RC         exit code for `mcp list` (default: 0)
#   FAKE_CODEX_LIST_ARGV_FILE  where to record the arguments of the list call
#   FAKE_CODEX_ARGV_FILE       where to record the arguments of the exec call

set -uo pipefail

subcommand="${1:-}"
shift 2>/dev/null || true

case "$subcommand" in
  mcp)
    printf '%s\n' "$@" > "${FAKE_CODEX_LIST_ARGV_FILE:-/dev/null}"
    if [ "${FAKE_CODEX_LIST_RC:-0}" != 0 ]; then
      printf 'fake-codex: unexpected argument `--disable`\n' >&2
      exit "${FAKE_CODEX_LIST_RC}"
    fi
    if [ -n "${FAKE_CODEX_LIST_FILE:-}" ] && [ -f "${FAKE_CODEX_LIST_FILE}" ]; then
      cat "${FAKE_CODEX_LIST_FILE}"
    else
      printf '[]\n'
    fi
    ;;
  exec)
    printf '%s\n' "$@" > "${FAKE_CODEX_ARGV_FILE:-/dev/null}"
    printf 'fake codex exec ran\n'
    ;;
  *)
    printf 'fake-codex: unexpected subcommand: %s\n' "${subcommand:-<none>}" >&2
    exit 64
    ;;
esac

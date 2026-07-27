#!/usr/bin/env bash
# fake-sage.sh — stands in for codex-sage.sh in the {MAGI_SCRIPTS_DIR} test case.
#
# It is reached only through a command[0] built from that placeholder, so running
# at all is the assertion: the substituted path must be absolute, correct and
# executable. Like the real wrapper's target it reads the prompt on stdin and
# writes its answer where --output-last-message points.

set -euo pipefail

answer_file=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "--output-last-message" ]; then answer_file="$argument"; fi
  previous="$argument"
done

if [ -z "$answer_file" ]; then
  printf 'fake-sage: --output-last-message was not passed through\n' >&2
  exit 4
fi

{
  printf 'reached via MAGI_SCRIPTS_DIR\n'
  cat
} > "$answer_file"

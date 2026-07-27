#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKILLS_DIR="$REPO_ROOT/skills"
checked=0
failures=0

if [ ! -d "$SKILLS_DIR" ]; then
  printf 'SKILL_LINE_BUDGET_FAIL\t%s\n' "skills directory not found: $SKILLS_DIR" >&2
  exit 2
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  checked=$((checked + 1))
  lines="$(awk 'END { print NR }' "$file")"
  relative="${file#"$REPO_ROOT"/}"
  if [ "$lines" -ge 500 ]; then
    printf 'SKILL_LINE_BUDGET_FAIL\t%s\t%s\n' "$lines" "$relative" >&2
    failures=$((failures + 1))
  else
    printf 'SKILL_LINE_BUDGET_OK\t%s\t%s\n' "$lines" "$relative"
  fi
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | LC_ALL=C sort)

if [ "$checked" -eq 0 ]; then
  printf 'SKILL_LINE_BUDGET_FAIL\tno skills/*/SKILL.md files found\n' >&2
  exit 2
fi

if [ "$failures" -ne 0 ]; then
  printf 'SKILL_LINE_BUDGET_SUMMARY\tFAIL\tchecked=%s\tfailures=%s\n' "$checked" "$failures" >&2
  exit 1
fi

printf 'SKILL_LINE_BUDGET_SUMMARY\tPASS\tchecked=%s\tfailures=0\n' "$checked"

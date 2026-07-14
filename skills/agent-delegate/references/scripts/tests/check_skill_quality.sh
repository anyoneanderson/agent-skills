#!/usr/bin/env bash
set -uo pipefail

failures=0

fail() {
  printf 'SKILL_QUALITY_FAIL\t%s\t%s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

description_text() {
  awk '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^description:[[:space:]]*\|/ { in_description=1; next }
    in_description && /^[A-Za-z0-9_-]+:/ { exit }
    in_description { sub(/^[[:space:]]{2}/, ""); print }
  ' "$1"
}

check_reference_paths() {
  local file="$1" skill_dir reference english japanese
  skill_dir="$(cd "$(dirname "$file")" && pwd)"
  while IFS= read -r reference; do
    [ -z "$reference" ] && continue
    reference="${reference%%#*}"
    [ -e "$skill_dir/$reference" ] || fail "$file" "missing reference: $reference"
    case "$reference" in
      references/*.md)
        case "$reference" in *.ja.md) continue ;; esac
        english="$skill_dir/$reference"
        japanese="${english%.md}.ja.md"
        [ -f "$japanese" ] || fail "$file" "missing Japanese pair: ${reference%.md}.ja.md"
        ;;
    esac
  done < <(grep -Eo '\]\(references/[A-Za-z0-9_./-]+\.md(#[A-Za-z0-9_.-]+)?\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//' | sort -u)
}

check_skill() {
  local file="$1" dir_name name license description description_length title non_ascii_heading
  [ -f "$file" ] || { fail "$file" "file does not exist"; return; }
  [ "$(sed -n '1p' "$file")" = '---' ] || fail "$file" "missing YAML frontmatter"

  name="$(frontmatter_value "$file" name)"
  license="$(frontmatter_value "$file" license)"
  dir_name="$(basename "$(dirname "$file")")"
  [ "$name" = "$dir_name" ] || fail "$file" "frontmatter name must match directory"
  [ "$license" = MIT ] || fail "$file" "license must be MIT"

  description="$(description_text "$file")"
  description_length="$(printf '%s' "$description" | wc -m | tr -d ' ')"
  [ "$description_length" -le 1024 ] || fail "$file" "description exceeds 1024 characters"
  printf '%s\n' "$description" | grep -q 'English triggers:' || fail "$file" "missing English triggers"
  printf '%s\n' "$description" | grep -q '日本語トリガー:' || fail "$file" "missing Japanese triggers"

  title="$(awk '/^---$/{count++; next} count==2 && /^# /{print; exit}' "$file")"
  printf '%s\n' "$title" | grep -Eq "^# ${name} — [[:alnum:]]" || fail "$file" "title must use '# ${name} — Short Description'"
  grep -q '^## Language Rules$' "$file" || fail "$file" "missing Language Rules"
  grep -q '^## [A-Za-z0-9]' "$file" || fail "$file" "body must use English headings"
  non_ascii_heading="$(grep -E '^#{2,6} ' "$file" | grep '[ぁ-んァ-ヶ一-龠]' || true)"
  [ -z "$non_ascii_heading" ] || fail "$file" "headings must be English"

  if grep -q 'AskUserQuestion' "$file"; then
    grep -qE 'AskUserQuestion|request_user_input' "$file" || fail "$file" "interactive choices must use AskUserQuestion"
    grep -q '/' "$file" || fail "$file" "interactive wording must include English/Japanese alternatives"
    grep -q '[ぁ-んァ-ヶ一-龠]' "$file" || fail "$file" "interactive wording must include Japanese"
  fi
  if grep -Eq 'mcp__[A-Za-z0-9_]+|Context7' "$file"; then
    fail "$file" "hardcoded MCP/tool provider name"
  fi
  [ "$(wc -l < "$file" | tr -d ' ')" -le 500 ] || fail "$file" "SKILL.md exceeds 500 lines"
  check_reference_paths "$file"
}

if [ "$#" -eq 0 ]; then
  printf 'Usage: check_skill_quality.sh path/to/SKILL.md [...]\n' >&2
  exit 2
fi

for skill in "$@"; do check_skill "$skill"; done

if [ "$failures" -ne 0 ]; then
  printf 'SKILL_QUALITY_SUMMARY\tFAIL\t%s\n' "$failures" >&2
  exit 1
fi
printf 'SKILL_QUALITY_SUMMARY\tPASS\t%s\n' "$#"

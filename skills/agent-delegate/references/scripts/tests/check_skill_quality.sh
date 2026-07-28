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

markdown_headings() {
  awk '
    function marker_length(line, marker, count) {
      count=0
      while (substr(line, count + 1, 1) == marker) count++
      return count
    }
    function opening_fence_indent_ok(line, i, char, spaces) {
      spaces=0
      for (i=1; i<=length(line); i++) {
        char=substr(line, i, 1)
        if (char == " ") {
          spaces++
          if (spaces > 3) return 0
        } else if (char == "\t") {
          return 0
        } else {
          break
        }
      }
      return 1
    }
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { in_frontmatter=0; next }
    in_frontmatter { next }
    {
      opening_indent_ok=opening_fence_indent_ok($0)
      trimmed=$0
      sub(/^[[:space:]]*/, "", trimmed)
      marker=substr(trimmed, 1, 1)
      run_length=0
      if (marker == "`" || marker == "~") run_length=marker_length(trimmed, marker)
      if (in_fence) {
        rest=substr(trimmed, run_length + 1)
        if (opening_indent_ok && marker == fence_marker && run_length >= fence_length && rest ~ /^[[:space:]]*$/) {
          in_fence=0
        }
        next
      }
      if (opening_indent_ok && (marker == "`" || marker == "~") && run_length >= 3) {
        in_fence=1
        fence_marker=marker
        fence_length=run_length
        next
      }
      if (opening_indent_ok && trimmed ~ /^#{1,6}[[:space:]]/) print trimmed
    }
    END {
      if (in_frontmatter) exit 11
      if (in_fence) exit 10
    }
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
  local file="$1" dir_name name license description description_length headings heading_status title non_ascii_heading
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

  headings="$(markdown_headings "$file")"
  heading_status=$?
  case "$heading_status" in
    0)
      title="$(printf '%s\n' "$headings" | grep -m1 '^# ' || true)"
      printf '%s\n' "$title" | grep -Eq "^# ${name} — [[:alnum:]]" || fail "$file" "title must use '# ${name} — Short Description'"
      printf '%s\n' "$headings" | grep -q '^## Language Rules$' || fail "$file" "missing Language Rules"
      printf '%s\n' "$headings" | grep -q '^## [A-Za-z0-9]' || fail "$file" "body must use English headings"
      non_ascii_heading="$(printf '%s\n' "$headings" | grep '[ぁ-んァ-ヶ一-龠]' || true)"
      [ -z "$non_ascii_heading" ] || fail "$file" "headings must be English"
      ;;
    10) fail "$file" "unclosed fenced code block" ;;
    11) fail "$file" "unclosed YAML frontmatter" ;;
    *) fail "$file" "could not parse Markdown headings" ;;
  esac

  if grep -q 'AskUserQuestion' "$file"; then
    grep -qE 'AskUserQuestion|request_user_input' "$file" || fail "$file" "interactive choices must use AskUserQuestion"
    grep -q '/' "$file" || fail "$file" "interactive wording must include English/Japanese alternatives"
    grep -q '[ぁ-んァ-ヶ一-龠]' "$file" || fail "$file" "interactive wording must include Japanese"
  fi
  if grep -Eq 'mcp__[A-Za-z0-9_]+|Context7' "$file"; then
    fail "$file" "hardcoded MCP/tool provider name"
  fi
  [ "$(awk 'END { print NR }' "$file")" -lt 500 ] || fail "$file" "SKILL.md must stay under 500 lines"
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

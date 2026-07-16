#!/usr/bin/env bash
set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../../../.." && pwd)"

SPEC_WRITING="$REPO_ROOT/skills/spec-writing"
SPEC_GENERATOR="$REPO_ROOT/skills/spec-generator"
SPEC_INSPECT="$REPO_ROOT/skills/spec-inspect"
README_EN="$REPO_ROOT/README.md"
README_JA="$REPO_ROOT/README.ja.md"
FIXTURE="$TEST_DIR/fixtures/abstract-process-cases.tsv"

failures=0
checks=0

pass() {
  printf 'CONTRACT_PASS\t%s\n' "$1"
}

fail() {
  printf 'CONTRACT_FAIL\t%s\t%s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

check_file() {
  local file="$1" label="$2"
  checks=$((checks + 1))
  if [ -f "$file" ]; then
    pass "$label"
  else
    fail "$label" "missing file: $file"
  fi
}

check_contains() {
  local file="$1" text="$2" label="$3"
  checks=$((checks + 1))
  if grep -Fq -- "$text" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label" "missing text: $text"
  fi
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

check_frontmatter_value() {
  local file="$1" key="$2" expected="$3" label="$4" actual
  checks=$((checks + 1))
  actual="$(frontmatter_value "$file" "$key")"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected $key=$expected, got $actual"
  fi
}

check_absent_regex() {
  local label="$1" regex="$2"
  shift 2
  checks=$((checks + 1))
  if grep -Eq "$regex" "$@" 2>/dev/null; then
    fail "$label" "unexpected duplicated vocabulary table"
  else
    pass "$label"
  fi
}

check_line_limit() {
  local file="$1" limit="$2" label="$3" lines
  checks=$((checks + 1))
  lines="$(wc -l < "$file" | tr -d ' ')"
  if [ "$lines" -le "$limit" ]; then
    pass "$label"
  else
    fail "$label" "$file has $lines lines; limit is $limit"
  fi
}

check_nonempty() {
  local file="$1" label="$2"
  checks=$((checks + 1))
  if [ -s "$file" ]; then
    pass "$label"
  else
    fail "$label" "expected a non-empty value set"
  fi
}

check_files_equal() {
  local expected="$1" actual="$2" label="$3"
  checks=$((checks + 1))
  if cmp -s "$expected" "$actual"; then
    pass "$label"
  else
    fail "$label" "sets differ: $(diff -u "$expected" "$actual" 2>/dev/null || true)"
  fi
}

check_empty() {
  local file="$1" label="$2"
  checks=$((checks + 1))
  if [ ! -s "$file" ]; then
    pass "$label"
  else
    fail "$label" "unexpected values: $(tr '\n' ',' < "$file")"
  fi
}

extract_ids() {
  local prefix="$1" file="$2"
  grep -Eo "$prefix-[0-9]{3}" "$file" 2>/dev/null | sort -u
}

validate_fixture() {
  awk -F '\t' '
    BEGIN {
      expected_header = "case_id\tlanguage\tinput\texpected_severity\tmissing_elements\tav_id\tcategory"
      required[1] = "warning"
      required[2] = "pass-four-elements"
      required[3] = "pass-multi-sentence"
      required[4] = "pass-mathematical"
      required[5] = "warning-mermaid"
      required[6] = "pass-mermaid"
    }
    NR == 1 {
      if ($0 != expected_header) {
        print "invalid fixture header" > "/dev/stderr"
        bad = 1
      }
      next
    }
    {
      rows++
      if (NF != 7) {
        print "invalid column count at row " NR > "/dev/stderr"
        bad = 1
        next
      }
      if ($1 == "" || seen_case[$1]++) {
        print "missing or duplicate case_id at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($2 != "en" && $2 != "ja") {
        print "invalid language at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($3 == "") {
        print "empty input at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($4 != "WARNING" && $4 != "NONE") {
        print "invalid expected_severity at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($6 !~ /^AV-[0-9][0-9][0-9]$/) {
        print "invalid AV ID at row " NR > "/dev/stderr"
        bad = 1
      }
      known_category = 0
      for (i = 1; i <= 6; i++) {
        if ($7 == required[i]) {
          known_category = 1
          present[$2 SUBSEP $7] = 1
        }
      }
      if (!known_category) {
        print "invalid category at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($7 ~ /^warning/ && ($4 != "WARNING" || $5 == "" || $5 == "-")) {
        print "warning row lacks severity or missing elements at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($7 ~ /^pass-/ && ($4 != "NONE" || $5 != "-")) {
        print "pass row has an invalid expected result at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($7 == "pass-multi-sentence" && $3 !~ /\\n/) {
        print "multi-sentence row lacks a visible line boundary at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($7 == "pass-mathematical" && $3 !~ /(input set|output set|入力集合|出力集合)/) {
        print "mathematical row lacks input/output set evidence at row " NR > "/dev/stderr"
        bad = 1
      }
      if ($7 ~ /mermaid/ && $3 !~ /sequenceDiagram/) {
        print "Mermaid row lacks sequenceDiagram at row " NR > "/dev/stderr"
        bad = 1
      }
    }
    END {
      if (rows < 12) {
        print "fixture must contain at least 12 bilingual cases" > "/dev/stderr"
        bad = 1
      }
      for (language_index = 1; language_index <= 2; language_index++) {
        language = language_index == 1 ? "en" : "ja"
        for (i = 1; i <= 6; i++) {
          if (!present[language SUBSEP required[i]]) {
            print "missing category " language "/" required[i] > "/dev/stderr"
            bad = 1
          }
        }
      }
      exit bad
    }
  ' "$1"
}

tmp="$(mktemp -d /tmp/spec-writing-contract.XXXXXX)" || exit 2
trap 'rm -rf "$tmp"' EXIT

skill="$SPEC_WRITING/SKILL.md"
rules_en="$SPEC_WRITING/references/writing-rules.md"
rules_ja="$SPEC_WRITING/references/writing-rules.ja.md"
verbs_en="$SPEC_WRITING/references/abstract-verbs.md"
verbs_ja="$SPEC_WRITING/references/abstract-verbs.ja.md"
generator="$SPEC_GENERATOR/SKILL.md"
generator_init_ja="$SPEC_GENERATOR/references/init.ja.md"
generator_design_ja="$SPEC_GENERATOR/references/design.ja.md"
inspect="$SPEC_INSPECT/SKILL.md"
inspect_check_en="$SPEC_INSPECT/references/abstract-process-check.md"
inspect_check_ja="$SPEC_INSPECT/references/abstract-process-check.ja.md"

check_frontmatter_value "$skill" name spec-writing "spec-writing frontmatter name"
check_frontmatter_value "$skill" license MIT "spec-writing frontmatter license"
check_contains "$skill" "## Language Rules" "spec-writing Language Rules"
check_contains "$skill" "## Attribution" "spec-writing Attribution section"
check_contains "$skill" "k16shikano/japanese-tech-writing" "spec-writing attribution source"
check_contains "$skill" "https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d" "spec-writing attribution URL"
check_contains "$skill" "Unlicense" "spec-writing source license"
check_line_limit "$skill" 500 "spec-writing 500-line limit"

check_file "$rules_en" "English writing rules exist"
check_file "$rules_ja" "Japanese writing rules exist"
check_file "$verbs_en" "English abstract verbs exist"
check_file "$verbs_ja" "Japanese abstract verbs exist"

extract_ids SW "$rules_en" > "$tmp/sw-en"
extract_ids SW "$rules_ja" > "$tmp/sw-ja"
extract_ids AV "$verbs_en" > "$tmp/av-en"
extract_ids AV "$verbs_ja" > "$tmp/av-ja"
check_nonempty "$tmp/sw-en" "English SW IDs are non-empty"
check_files_equal "$tmp/sw-en" "$tmp/sw-ja" "SW ID parity"
check_nonempty "$tmp/av-en" "English AV IDs are non-empty"
check_files_equal "$tmp/av-en" "$tmp/av-ja" "AV ID parity"

check_contains "$generator" "resolve \`spec-writing\` by name" "generator resolves spec-writing"
check_contains "$generator" "read its complete \`SKILL.md\`" "generator reads complete spec-writing SKILL.md"
check_contains "$generator" "references/writing-rules.ja.md" "generator reads Japanese writing rules"
check_contains "$generator" "references/abstract-verbs.ja.md" "generator reads Japanese abstract verbs"

for fallback in "$generator_init_ja" "$generator_design_ja"; do
  fallback_name="$(basename "$fallback")"
  check_contains "$fallback" "## Specification writing fallback" "$fallback_name fallback section"
  check_contains "$fallback" "生成、修正、auto mode" "$fallback_name fallback mode coverage"
  check_contains "$fallback" "**主体**" "$fallback_name actor rule"
  check_contains "$fallback" "**開始条件または入力**" "$fallback_name trigger or input rule"
  check_contains "$fallback" "**具体的な動作**" "$fallback_name concrete action rule"
  check_contains "$fallback" "**結果の渡し先**" "$fallback_name result destination rule"
  check_contains "$fallback" "Bad:" "$fallback_name Bad example"
  check_contains "$fallback" "Good:" "$fallback_name Good example"
done

check_contains "$inspect" "references/abstract-verbs.md" "inspect reads English primary vocabulary"
check_contains "$inspect" "references/abstract-verbs.ja.md" "inspect reads Japanese primary vocabulary"
check_contains "$inspect" "Keep the vocabulary's Pattern list in \`spec-writing\` only." "inspect declares one vocabulary source"
check_absent_regex "inspect does not duplicate vocabulary rows" '^\|[[:space:]]*AV-[0-9]{3}[[:space:]]*\|' \
  "$inspect" "$inspect_check_en" "$inspect_check_ja"

check_line_limit "$generator" 500 "spec-generator 500-line limit"
check_line_limit "$inspect" 500 "spec-inspect 500-line limit"

check_contains "$README_EN" "| [spec-writing](skills/spec-writing/)" "README skill table"
check_contains "$README_JA" "| [spec-writing](skills/spec-writing/)" "README.ja skill table"
check_contains "$README_EN" "npx skills add anyoneanderson/agent-skills --skill spec-writing -g -y" "README install example"
check_contains "$README_JA" "npx skills add anyoneanderson/agent-skills --skill spec-writing -g -y" "README.ja install example"

check_file "$FIXTURE" "abstract-process fixture exists"
checks=$((checks + 1))
if validate_fixture "$FIXTURE"; then
  pass "fixture columns and required bilingual categories"
else
  fail "fixture columns and required bilingual categories" "fixture contract is invalid"
fi

tail -n +2 "$FIXTURE" | cut -f6 | sort -u > "$tmp/fixture-av"
comm -23 "$tmp/fixture-av" "$tmp/av-en" > "$tmp/unknown-av"
check_empty "$tmp/unknown-av" "fixture AV IDs exist in primary vocabulary"

if [ "$failures" -ne 0 ]; then
  printf 'CONTRACT_SUMMARY\tFAIL\tchecks=%s\tfailures=%s\n' "$checks" "$failures" >&2
  exit 1
fi

printf 'CONTRACT_SUMMARY\tPASS\tchecks=%s\n' "$checks"

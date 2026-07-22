#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../../../.." && pwd)"
GENERATOR="$REPO_ROOT/skills/spec-generator"
INSPECT="$REPO_ROOT/skills/spec-inspect"
CONTRACT_FIXTURE="$TEST_DIR/fixtures/projection-contract.tsv"
MUTATION_FIXTURE="$TEST_DIR/fixtures/projection-mutations.tsv"
CONSISTENT_FIXTURE="$TEST_DIR/fixtures/projection-consistency/consistent"

fail() {
  printf 'FAIL\t%s\n' "$*" >&2
  exit 1
}

contract_file() {
  local target="$1" language="$2"
  case "$target:$language" in
    generator:en) printf '%s\n' "$GENERATOR/references/projection-consistency.md" ;;
    generator:ja) printf '%s\n' "$GENERATOR/references/projection-consistency.ja.md" ;;
    inspect:en) printf '%s\n' "$INSPECT/references/projection-consistency-check.md" ;;
    inspect:ja) printf '%s\n' "$INSPECT/references/projection-consistency-check.ja.md" ;;
    *) return 1 ;;
  esac
}

validate_contract() {
  local target="$1" language="$2" file="${3:-}" field id row_target en_token ja_token token
  if [ -z "$file" ]; then
    file="$(contract_file "$target" "$language")" || return 1
  fi
  [ -f "$file" ] || return 1
  case "$language" in en) field=3 ;; ja) field=4 ;; *) return 1 ;; esac

  while IFS=$'\t' read -r id row_target en_token ja_token; do
    [ "$id" = contract_id ] && continue
    [ "$row_target" = "$target" ] || continue
    if [ "$field" -eq 3 ]; then token="$en_token"; else token="$ja_token"; fi
    grep -Fq -- "$token" "$file" || return 1
  done < "$CONTRACT_FIXTURE"
}

assert_contract_mutations_rejected() {
  local target="$1" language="$2" file field id row_target en_token ja_token token mutant
  file="$(contract_file "$target" "$language")" || return 1
  case "$language" in en) field=3 ;; ja) field=4 ;; *) return 1 ;; esac

  while IFS=$'\t' read -r id row_target en_token ja_token; do
    [ "$id" = contract_id ] && continue
    [ "$row_target" = "$target" ] || continue
    if [ "$field" -eq 3 ]; then token="$en_token"; else token="$ja_token"; fi
    mutant="$tmp/$target-$language-$id.md"
    awk -v token="$token" 'index($0, token) == 0 { print }' "$file" > "$mutant"
    if validate_contract "$target" "$language" "$mutant"; then
      fail "contract mutation survived: $target/$language/$id"
    fi
    printf 'PASS\tcontract-mutation\t%s/%s/%s\n' "$target" "$language" "$id"
  done < "$CONTRACT_FIXTURE"
}

requirement_value() {
  local file="$1" id="$2" label="$3"
  sed -nE "s/^- \[$id\] $label: (.*)\.$/\\1/p" "$file"
}

design_value() {
  local file="$1" kind="$2" label="$3"
  sed -nE "s/^- $kind $label: (.*)\.$/\\1/p" "$file"
}

trace_value() {
  local file="$1" id="$2"
  awk -F '|' -v wanted="[$id]" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == wanted { print trim($4); exit }
  ' "$file"
}

contains_projection_value() {
  local file="$1" expected="$2"
  awk -v needle="$expected" '
    function is_word(character) {
      return character ~ /[[:alnum:]_]/
    }
    BEGIN {
      needle = tolower(needle)
    }
    {
      line = tolower($0)
      start = 1
      while ((relative = index(substr(line, start), needle)) > 0) {
        position = start + relative - 1
        before = position > 1 ? substr(line, position - 1, 1) : ""
        after_at = position + length(needle)
        after = after_at <= length(line) ? substr(line, after_at, 1) : ""
        if (!is_word(before) && !is_word(after)) {
          found = 1
          exit
        }
        start = position + 1
      }
    }
    END {
      exit found ? 0 : 1
    }
  ' "$file"
}

validate_projection_set() {
  local dir="$1" bad=0 defined referenced unknown key id label expected
  local summary decision trace target value values unique_count

  defined="$(grep -Eho '\[REQ-[0-9]+\]' "$dir/requirement.md" | LC_ALL=C sort -u)"
  referenced="$(grep -Eho '\[REQ-[0-9]+\]' "$dir/design.md" "$dir/tasks.md" "$dir/test.md" \
    | LC_ALL=C sort -u)"
  unknown="$(LC_ALL=C comm -13 <(printf '%s\n' "$defined") <(printf '%s\n' "$referenced"))"
  if [ -n "$unknown" ]; then
    printf 'requirement id mismatch: %s\n' "$unknown"
    bad=1
  fi

  while IFS=$'\t' read -r key id label; do
    expected="$(requirement_value "$dir/requirement.md" "$id" "$label")"
    summary="$(design_value "$dir/design.md" Summary "$label")"
    decision="$(design_value "$dir/design.md" Decision "$label")"
    trace="$(trace_value "$dir/design.md" "$id")"
    values="$(printf '%s\n' "$expected" "$summary" "$decision" "$trace" | sed '/^$/d')"
    unique_count="$(printf '%s\n' "$values" | LC_ALL=C sort -u | wc -l | tr -d ' ')"
    if [ -z "$expected" ] || [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" -ne 4 ] || [ "$unique_count" -ne 1 ]; then
      printf '%s mismatch: requirement=%s summary=%s decision=%s trace=%s\n' \
        "$key" "$expected" "$summary" "$decision" "$trace"
      bad=1
    fi
    for target in tasks.md test.md; do
      if [ -n "$expected" ] && ! contains_projection_value "$dir/$target" "$expected"; then
        printf '%s downstream mismatch: %s lacks %s\n' "$key" "$target" "$expected"
        bad=1
      fi
    done
  done <<'CASES'
delivery method	REQ-001	Delivery method
batch size	REQ-002	Batch size
cursor model	REQ-003	Cursor model
CASES

  [ "$bad" -eq 0 ]
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/projection-consistency.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

for file in "$CONTRACT_FIXTURE" "$MUTATION_FIXTURE" \
  "$CONSISTENT_FIXTURE/requirement.md" "$CONSISTENT_FIXTURE/design.md" \
  "$CONSISTENT_FIXTURE/tasks.md" "$CONSISTENT_FIXTURE/test.md"; do
  [ -s "$file" ] || fail "missing or empty fixture: $file"
  [ "$(tail -c 1 "$file" | od -An -t u1 | tr -d '[:space:]')" = 10 ] ||
    fail "fixture must end with a newline: $file"
done

for target in generator inspect; do
  for language in en ja; do
    validate_contract "$target" "$language" || fail "incomplete contract: $target/$language"
    assert_contract_mutations_rejected "$target" "$language"
  done
done

grep -Fq 'references/projection-consistency.md' "$GENERATOR/SKILL.md" ||
  fail "spec-generator does not route to the English projection contract"
grep -Fq 'references/projection-consistency.ja.md' "$GENERATOR/SKILL.md" ||
  fail "spec-generator does not route to the Japanese projection contract"
grep -Fq 'projection-consistency-check.md' "$INSPECT/SKILL.md" ||
  fail "spec-inspect does not route to the projection check"
grep -Fq 'references/projection-consistency.md' "$GENERATOR/references/auto-mode.md" ||
  fail "spec-generator auto mode skips the English projection pass"
grep -Fq 'references/projection-consistency.ja.md' "$GENERATOR/references/auto-mode.ja.md" ||
  fail "spec-generator auto mode skips the Japanese projection pass"

planner_en="$REPO_ROOT/skills/spec-workflow-init/references/agents/claude/workflow-planner.md"
planner_ja="$REPO_ROOT/skills/spec-workflow-init/references/agents/claude/workflow-planner.ja.md"
grep -Fq 'spec-generator `references/projection-consistency.md`' "$planner_en" ||
  fail "English workflow planner does not invoke the projection pass"
grep -Fq 'spec-generator `references/projection-consistency.ja.md`' "$planner_ja" ||
  fail "Japanese workflow planner does not invoke the projection pass"

for planner in "$planner_en" "$planner_ja"; do
  if grep -Eq 'PG-[0-9]|PI-[0-9]|Projection Inventory|投影先の一覧' "$planner"; then
    fail "workflow planner duplicates projection rules: $planner"
  fi
done

validate_projection_set "$CONSISTENT_FIXTURE" >/dev/null ||
  fail "consistent projection fixture was rejected"
printf 'PASS\tprojection-fixture\tconsistent\n'

while IFS=$'\t' read -r case_id target_file old_line new_line expected_fragment; do
  [ "$case_id" = case_id ] && continue
  case_dir="$tmp/$case_id"
  mkdir -p "$case_dir"
  cp -R "$CONSISTENT_FIXTURE/." "$case_dir/"
  awk -v old="$old_line" -v new="$new_line" '
    $0 == old { print new; changed=1; next }
    { print }
    END { if (!changed) exit 1 }
  ' "$case_dir/$target_file" > "$case_dir/$target_file.tmp" ||
    fail "mutation did not match fixture: $case_id"
  mv "$case_dir/$target_file.tmp" "$case_dir/$target_file"
  if output="$(validate_projection_set "$case_dir" 2>&1)"; then
    fail "projection mutation survived: $case_id"
  fi
  printf '%s\n' "$output" | grep -Fq -- "$expected_fragment" ||
    fail "mutation $case_id failed for an unrelated reason: $output"
  cp "$CONSISTENT_FIXTURE/$target_file" "$case_dir/$target_file"
  validate_projection_set "$case_dir" >/dev/null ||
    fail "repair did not restore projection consistency: $case_id"
  printf 'PASS\tprojection-mutation\t%s\n' "$case_id"
done < "$MUTATION_FIXTURE"

[ "$(wc -l < "$GENERATOR/SKILL.md" | tr -d ' ')" -le 500 ] ||
  fail "spec-generator SKILL.md exceeds 500 lines"
[ "$(wc -l < "$INSPECT/SKILL.md" | tr -d ' ')" -le 500 ] ||
  fail "spec-inspect SKILL.md exceeds 500 lines"

printf 'PASS\tprojection-consistency-contract\n'

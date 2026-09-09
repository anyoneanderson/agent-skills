#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-skill-line-budget.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skill-line-budget.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT TERM INT HUP

fail() {
  printf 'SKILL_LINE_BUDGET_TEST_FAIL\t%s\n' "$*" >&2
  exit 1
}

make_skill() {
  local root="$1" name="$2" lines="$3" file index
  file="$root/skills/$name/SKILL.md"
  mkdir -p "$(dirname "$file")"
  : > "$file"
  for ((index = 1; index <= lines; index++)); do
    printf 'line %s\n' "$index" >> "$file"
  done
}

repo_expected="$(find "$REPO_ROOT/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')"
[ "$repo_expected" -eq 24 ] || fail "expected the current repository inventory to contain 24 skills, got $repo_expected"
repo_output="$(bash "$CHECKER" "$REPO_ROOT")" || fail "current repository should satisfy the line budget"
printf '%s\n' "$repo_output" | grep -q "SKILL_LINE_BUDGET_SUMMARY.*PASS.*checked=$repo_expected.*failures=0" ||
  fail "checker inventory does not match the independent repository inventory"

fixture="$TMP_ROOT/fixture"
make_skill "$fixture" compact 499
bash "$CHECKER" "$fixture" > "$TMP_ROOT/compact.out" || fail "499 lines should pass"
grep -q $'SKILL_LINE_BUDGET_SUMMARY\tPASS\tchecked=1\tfailures=0' "$TMP_ROOT/compact.out" ||
  fail "499-line summary is missing"

make_skill "$fixture" oversized 500
if bash "$CHECKER" "$fixture" > "$TMP_ROOT/oversized.out" 2> "$TMP_ROOT/oversized.err"; then
  fail "500 lines should fail"
fi
grep -q $'SKILL_LINE_BUDGET_FAIL\t500\tskills/oversized/SKILL.md' "$TMP_ROOT/oversized.err" ||
  fail "500-line failure does not identify the file and line count"
grep -q $'SKILL_LINE_BUDGET_SUMMARY\tFAIL\tchecked=2\tfailures=1' "$TMP_ROOT/oversized.err" ||
  fail "repository-wide failure summary is missing"

make_skill "$fixture" nonterminated 499
printf 'line 500' >> "$fixture/skills/nonterminated/SKILL.md"
if bash "$CHECKER" "$fixture" > "$TMP_ROOT/nonterminated.out" 2> "$TMP_ROOT/nonterminated.err"; then
  fail "500 physical lines without a trailing newline should fail"
fi
grep -q $'SKILL_LINE_BUDGET_FAIL\t500\tskills/nonterminated/SKILL.md' "$TMP_ROOT/nonterminated.err" ||
  fail "physical-line counting does not cover a missing trailing newline"

threshold_mutant="$TMP_ROOT/check-skill-line-budget-threshold-mutant.sh"
sed 's/"$lines" -ge 500/"$lines" -ge 5000/' "$CHECKER" > "$threshold_mutant"
chmod +x "$threshold_mutant"
if ! bash "$threshold_mutant" "$fixture" >/dev/null 2>&1; then
  fail "threshold mutant setup did not weaken the 500-line comparison"
fi

mutant="$TMP_ROOT/check-skill-line-budget-mutant.sh"
sed "s|-name SKILL.md|-name SKILL.md ! -path '*/oversized/SKILL.md'|" "$CHECKER" > "$mutant"
chmod +x "$mutant"
exclusion_fixture="$TMP_ROOT/exclusion-fixture"
make_skill "$exclusion_fixture" compact 499
make_skill "$exclusion_fixture" oversized 500
mutant_output="$(bash "$mutant" "$exclusion_fixture")" || fail "exclusion mutant should expose its incomplete inventory"
if printf '%s\n' "$mutant_output" | grep -q $'SKILL_LINE_BUDGET_SUMMARY\tPASS\tchecked=2\tfailures=0'; then
  fail "test oracle accepted a checker that excluded the oversized skill"
fi
printf '%s\n' "$mutant_output" | grep -q $'SKILL_LINE_BUDGET_SUMMARY\tPASS\tchecked=1\tfailures=0' ||
  fail "exclusion mutation did not remove exactly one target"

printf 'SKILL_LINE_BUDGET_TEST_SUMMARY\tPASS\n'

#!/usr/bin/env bash
# run-tests.sh — behaviour tests for ja-humanizer-check.mjs against the evaluation samples.
#
# The fixtures are the before/after pairs from references/examples.md. Each "before"
# must produce the Tier 1 findings the example documents; each "after" (the writer's
# own rewrite) and the voice passages must produce no Tier 1 finding, which is the
# over-editing guard. The final cases check CLI behaviour (stdin, --json, --lang,
# --mode validation, the disable comment, fenced code) and one mutant of the checker
# to prove the suite can tell a weakened detector from a working one.
#
# Usage: bash run-tests.sh      (works from the repository root or from tests/)
# Exit:  0 = every case passed | 1 = a case failed | 2 = the harness cannot run

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$TEST_DIR/../ja-humanizer-check.mjs"
FIX="$TEST_DIR/fixtures"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ja-humanizer-tests.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT TERM INT HUP

command -v node >/dev/null 2>&1 || { printf 'JA_HUMANIZER_TEST_SKIP\tnode is not installed\n' >&2; exit 2; }
[ -f "$CHECKER" ] || { printf 'JA_HUMANIZER_TEST_FAIL\tchecker not found: %s\n' "$CHECKER" >&2; exit 2; }

failures=0
pass() { printf 'JA_HUMANIZER_TEST_OK\t%s\n' "$1"; }
fail() { printf 'JA_HUMANIZER_TEST_FAIL\t%s\n' "$1" >&2; failures=$((failures + 1)); }

run() {
  # run <mode> <file> -> output file path; ignores the exit code
  local mode="$1"
  local file="$2"
  local out="$TMP_ROOT/$(basename "$file").$mode.out"
  node "$CHECKER" --mode "$mode" "$file" > "$out" 2>&1 || true
  printf '%s' "$out"
}

expect_id() { # expect_id <case> <out> <id> [line]
  local name="$1" out="$2" id="$3" line="${4:-}"
  if [ -n "$line" ]; then
    grep -Eq "^TIER[0-9]	${id}	[^	]*:${line}	" "$out" && pass "$name: $id at line $line" || fail "$name: expected $id at line $line"
  else
    grep -Eq "^TIER[0-9]	${id}	" "$out" && pass "$name: $id" || fail "$name: expected $id"
  fi
}
expect_no_id() { # expect_no_id <case> <out> <id>
  local name="$1" out="$2" id="$3"
  grep -Eq "^TIER[0-9]	${id}	" "$out" && fail "$name: unexpected $id" || pass "$name: no $id"
}
expect_summary() { # expect_summary <case> <out> <PASS|FAIL> [tier1=n]
  local name="$1" out="$2" status="$3" extra="${4:-}"
  grep -Eq "^JA_HUMANIZER_CHECK_SUMMARY	${status}	.*${extra}" "$out" && pass "$name: summary $status $extra" || fail "$name: expected summary $status $extra ($(tail -1 "$out"))"
}

# Rewrites 1 to 3: staging, metaphorical verbs, threatening closer, heading as sentence.
out="$(run argument "$FIX/rewrite-before.md")"
expect_id rewrite-before "$out" abstract-verb 3
expect_id rewrite-before "$out" staging 5
expect_id rewrite-before "$out" threat-closer 5
expect_id rewrite-before "$out" heading-sentence 1
expect_summary rewrite-before "$out" FAIL
out="$(run argument "$FIX/rewrite-after.md")"
expect_summary rewrite-after "$out" PASS "tier1=0"

# Tap to Pay: thin items become questions; label-plus-colon is Tier 3 in article mode.
out="$(run article "$FIX/tap-before.md")"
expect_id tap-before "$out" thin-claim 5
expect_id tap-before "$out" thin-claim 9
expect_id tap-before "$out" thin-claim 11
grep -Eq '^TIER1	thin-claim	[^	]*	[^	]*	.*教えてください' "$out" && pass "tap-before: question attached in Japanese" || fail "tap-before: Japanese question missing"
grep -Eq '^TIER3	label-colon	' "$out" && pass "tap-before: label-colon is Tier 3 in article mode" || fail "tap-before: label-colon tier"
out="$(run mail "$FIX/tap-before.md")"
grep -Eq '^TIER2	label-colon	' "$out" && pass "tap-before: label-colon is Tier 2 in mail mode" || fail "tap-before: label-colon tier in mail mode"
out="$(run article "$FIX/tap-after.md")"
expect_summary tap-after "$out" PASS "tier1=0"

# Mail review 1: missing estimate next to a request to choose; ただし without a reason.
out="$(run mail "$FIX/mail1-before.md")"
expect_id mail1-before "$out" missing-estimate
expect_id mail1-before "$out" tadashi-no-reason
out="$(run mail "$FIX/mail1-after.md")"
expect_summary mail1-after "$out" PASS "tier1=0"
expect_no_id mail1-after "$out" tadashi-no-reason

# Mail review 2: cause restates the symptom, circular cause, generic countermeasure.
out="$(run mail "$FIX/mail2-before.md")"
expect_id mail2-before "$out" cause-restates-symptom
expect_id mail2-before "$out" circular-cause
expect_id mail2-before "$out" generic-measure
out="$(run mail "$FIX/mail2-after.md")"
expect_summary mail2-after "$out" PASS "tier1=0"

# Mail review 3: a request chained on the reply to the question just asked.
out="$(run mail "$FIX/mail3-before.md")"
expect_id mail3-before "$out" chained-request 5
out="$(run mail "$FIX/mail3-after.md")"
expect_summary mail3-after "$out" PASS "tier1=0"
expect_no_id mail3-after "$out" chained-request

# Over-editing guard: the writer's own passages produce nothing.
out="$(run mail "$FIX/voice-ok.md")"
expect_summary voice-ok "$out" PASS "tier1=0	tier2=0"

# Confirmed excerpts only; this tests detector compatibility, not authorship or rewrite quality.
out="$(run narrative "$FIX/narrative-confirmed.md")"
expect_summary narrative-confirmed "$out" PASS "tier1=0"

# CLI: English questions, JSON output, stdin, mode validation, disable comment, fenced code.
node "$CHECKER" --mode article --lang en "$FIX/tap-before.md" > "$TMP_ROOT/en.out" 2>&1 || true
grep -Eq 'what becomes unnecessary' "$TMP_ROOT/en.out" && pass "cli: --lang en returns English questions" || fail "cli: --lang en"
node "$CHECKER" --json --mode mail "$FIX/mail2-before.md" > "$TMP_ROOT/json.out" 2>&1 || true
node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(j.status!=="FAIL"||j.summary.tier1<3) process.exit(1)' "$TMP_ROOT/json.out" \
  && pass "cli: --json is parseable with status and summary" || fail "cli: --json"
node "$CHECKER" --mode mail < "$FIX/mail3-before.md" > "$TMP_ROOT/stdin.out" 2>&1 || true
grep -Eq '^TIER1	chained-request	stdin:5	' "$TMP_ROOT/stdin.out" && pass "cli: stdin input" || fail "cli: stdin input"
if node "$CHECKER" --mode poem "$FIX/voice-ok.md" > /dev/null 2> "$TMP_ROOT/mode.err"; then
  fail "cli: invalid --mode should exit 2"
else
  [ "$?" -eq 2 ] && pass "cli: invalid --mode exits 2" || fail "cli: invalid --mode exit code"
fi
printf '%s\n' '<!-- ja-humanizer-disable-next-line -->' '最重要システムを配る設計です。' > "$TMP_ROOT/disable.md"
node "$CHECKER" "$TMP_ROOT/disable.md" > "$TMP_ROOT/disable.out" 2>&1 || true
expect_summary disable-comment "$TMP_ROOT/disable.out" PASS "tier1=0"
printf '%s\n' '```' '最重要システムを配る設計です。' '```' > "$TMP_ROOT/fence.md"
node "$CHECKER" "$TMP_ROOT/fence.md" > "$TMP_ROOT/fence.out" 2>&1 || true
expect_summary fenced-code "$TMP_ROOT/fence.out" PASS "tier1=0"
printf '%s\n' '定期的にコードを写像します。' 'orchestrator は進捗を Run.steps へ保存し、同じ進捗をイベントとして送信する（写像する）。' > "$TMP_ROOT/concrete.md"
node "$CHECKER" "$TMP_ROOT/concrete.md" > "$TMP_ROOT/concrete.out" 2>&1 || true
grep -Ec '^TIER1	abstract-verb	' "$TMP_ROOT/concrete.out" | grep -q '^1$' && pass "concrete action in the same sentence suppresses abstract-verb" || fail "concrete-action allowance"

# PR body (Issue #169): the AI first draft carries review rounds, test counts and coverage; the writer's
# final version carries none of them, and its label-plus-colon items are gone too.
out="$(run argument "$FIX/pr-before.md")"
expect_id pr-before "$out" implementation-log
expect_id pr-before "$out" label-colon
expect_summary pr-before "$out" FAIL
out="$(run argument "$FIX/pr-after.md")"
expect_no_id pr-after "$out" implementation-log
expect_summary pr-after "$out" PASS "tier1=0"

# Review findings (PR #168): a lone 「ご検討いただけますと幸いです」 is not a request to choose, and a
# condition that is a real prerequisite (consent) must not be turned into an unconditional request.
printf '%s\n' '提案の内容をご検討いただけますと幸いです。' > "$TMP_ROOT/lone.md"
node "$CHECKER" --mode mail "$TMP_ROOT/lone.md" > "$TMP_ROOT/lone.out" 2>&1 || true
expect_no_id lone-request "$TMP_ROOT/lone.out" missing-estimate
printf '%s\n' '個人情報の取り扱いにご同意いただけますでしょうか。' '同意済みでしたら、個人情報の送信をお願いします。' > "$TMP_ROOT/consent.md"
node "$CHECKER" --mode mail "$TMP_ROOT/consent.md" > "$TMP_ROOT/consent.out" 2>&1 || true
expect_no_id consent-precondition "$TMP_ROOT/consent.out" chained-request

# Symlink (Issue #169): ~/.claude/skills/<name> is a symlink into ~/.agents/skills, so the checker must
# recognise itself as the main module when started through a link.
ln -s "$CHECKER" "$TMP_ROOT/linked-check.mjs"
node "$TMP_ROOT/linked-check.mjs" --mode mail "$FIX/mail3-before.md" > "$TMP_ROOT/symlink.out" 2>&1 || true
expect_id symlink-invocation "$TMP_ROOT/symlink.out" chained-request 5

# Mutant: a checker that never sees a chained request must be caught by mail3-before.
mutant="$TMP_ROOT/mutant.mjs"
sed 's/if (refersToQuestion \&\& !isPrecondition) push(1, "chained-request"/if (false) push(1, "chained-request"/' "$CHECKER" > "$mutant"
grep -q 'if (false) push(1, "chained-request"' "$mutant" || fail "mutant setup did not change the checker"
node "$mutant" --mode mail "$FIX/mail3-before.md" > "$TMP_ROOT/mutant.out" 2>&1 || true
grep -Eq '^TIER1	chained-request	' "$TMP_ROOT/mutant.out" && fail "mutant still reports chained-request" || pass "mutant: weakened detector is distinguishable"

if [ "$failures" -ne 0 ]; then
  printf 'JA_HUMANIZER_TEST_SUMMARY\tFAIL\t%s\n' "$failures" >&2
  exit 1
fi
printf 'JA_HUMANIZER_TEST_SUMMARY\tPASS\n'

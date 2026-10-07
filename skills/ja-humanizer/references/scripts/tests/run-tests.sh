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

# The writer's own texts (every "after", voice-ok, narrative-confirmed, article-confirmed) are pinned to
# their full tier counts, so a detector that starts reporting on them fails the suite at any tier.

# Rewrites 1 to 3: staging, metaphorical verbs, threatening closer, heading as sentence.
out="$(run argument "$FIX/rewrite-before.md")"
expect_id rewrite-before "$out" abstract-verb 3
expect_id rewrite-before "$out" staging 5
expect_id rewrite-before "$out" threat-closer 5
expect_id rewrite-before "$out" heading-sentence 1
expect_summary rewrite-before "$out" FAIL
out="$(run argument "$FIX/rewrite-after.md")"
expect_summary rewrite-after "$out" PASS "tier1=0	tier2=0	tier3=0"

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
expect_summary tap-after "$out" PASS "tier1=0	tier2=0	tier3=4"

# Mail review 1: missing estimate next to a request to choose; ただし without a reason.
out="$(run mail "$FIX/mail1-before.md")"
expect_id mail1-before "$out" missing-estimate
expect_id mail1-before "$out" tadashi-no-reason
out="$(run mail "$FIX/mail1-after.md")"
expect_summary mail1-after "$out" PASS "tier1=0	tier2=0	tier3=0"
expect_no_id mail1-after "$out" tadashi-no-reason

# Mail review 2: cause restates the symptom, circular cause, generic countermeasure.
out="$(run mail "$FIX/mail2-before.md")"
expect_id mail2-before "$out" cause-restates-symptom
expect_id mail2-before "$out" circular-cause
expect_id mail2-before "$out" generic-measure
out="$(run mail "$FIX/mail2-after.md")"
expect_summary mail2-after "$out" PASS "tier1=0	tier2=0	tier3=0"

# Mail review 3: a request chained on the reply to the question just asked.
out="$(run mail "$FIX/mail3-before.md")"
expect_id mail3-before "$out" chained-request 5
out="$(run mail "$FIX/mail3-after.md")"
expect_summary mail3-after "$out" PASS "tier1=0	tier2=0	tier3=0"
expect_no_id mail3-after "$out" chained-request

# Over-editing guard: the writer's own passages produce nothing.
out="$(run mail "$FIX/voice-ok.md")"
expect_summary voice-ok "$out" PASS "tier1=0	tier2=0	tier3=0"

# Confirmed excerpts only; this tests detector compatibility, not authorship or rewrite quality.
out="$(run narrative "$FIX/narrative-confirmed.md")"
expect_summary narrative-confirmed "$out" PASS "tier1=0	tier2=0	tier3=0"

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
expect_summary pr-after "$out" PASS "tier1=0	tier2=0	tier3=0"

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

# --- Issue #174: vocabulary and formatting that spread by 2026 -------------------------------
# Every detector below has a sentence that must be reported and a near neighbour that must not.

check_text() { # check_text <name> <mode> <line>... -> output file path
  local name="$1" mode="$2"
  shift 2
  printf '%s\n' "$@" > "$TMP_ROOT/$name.md"
  node "$CHECKER" --mode "$mode" "$TMP_ROOT/$name.md" > "$TMP_ROOT/$name.out" 2>&1 || true
  printf '%s' "$TMP_ROOT/$name.out"
}
expect_tier() { # expect_tier <case> <out> <tier> <id>
  grep -Eq "^TIER$3	$4	" "$2" && pass "$1: $4 is Tier $3" || fail "$1: expected $4 at Tier $3"
}
repeat() { # repeat <n> <text> -> text repeated n times on one line
  local i out=""
  for ((i = 0; i < $1; i += 1)); do out="$out$2"; done
  printf '%s' "$out"
}

# The sample from the Issue: none of this was reported before.
out="$(run article "$FIX/vocab2026-before.md")"
for id in calque vocab-density dash bold-density summary-heading heading-emoji; do
  expect_tier vocab2026-before "$out" 2 "$id"
done
expect_id vocab2026-before "$out" heading-emoji 1
expect_id vocab2026-before "$out" summary-heading 11
expect_id vocab2026-before "$out" abstract-verb 13
out="$(run argument "$FIX/vocab2026-before.md")"
expect_no_id vocab2026-before-argument "$out" bold-density

# A paragraph the writer wrote for an article on 2026-10-06 (one 「道具」, long sentences): nothing.
out="$(run article "$FIX/article-confirmed.md")"
expect_summary article-confirmed "$out" PASS "tier1=0	tier2=0	tier3=0"

# calque
out="$(check_text calque-hit argument 'キャッシュが静かに壊れます。' '古い値は黙って無視されます。' 'デプロイした瞬間に気づきます。')"
expect_id calque-hit "$out" calque 1
expect_id calque-hit "$out" calque 2
expect_id calque-hit "$out" calque 3
out="$(check_text calque-surface argument 'キャッシュが**静かに**壊れます。' 'キャッシュが静かに、壊れます。' '古い値は黙って、無視されます。' '古い値は[黙って](https://example.com/a)捨てられます。')"
for n in 1 2 3 4; do expect_id calque-surface "$out" calque "$n"; done
out="$(check_text calque-miss argument '会議中は静かにしてください。' '担当者は黙って作業を続けました。' '瞬間最大の接続数は300です。')"
expect_no_id calque-miss "$out" calque
out="$(check_text calque-staging argument '設定が静かに切り替わります。')"
expect_tier calque-staging "$out" 1 staging
expect_no_id calque-staging "$out" calque

# vocab-density: three distinct words, not two; compounds and incident reports are not counted.
out="$(check_text vocab-hit argument 'この実装が土台になります。' '原因を切り分けます。' 'これが定石です。')"
expect_tier vocab-hit "$out" 2 vocab-density
grep -Eq 'vocab-density.*土台\(1\) 切り分ける\(2\) 定石\(3\)' "$out" && pass "vocab-hit: words and lines are listed" || fail "vocab-hit: word list"
grep -Ec '^TIER[0-9]	vocab-density	' "$out" | grep -q '^1$' && pass "vocab-hit: reported once" || fail "vocab-hit: reported more than once"
out="$(check_text vocab-two argument 'この実装が土台になります。' '土台の上で原因を切り分けます。')"
expect_no_id vocab-two "$out" vocab-density
out="$(check_text vocab-compound argument '境界値と既定値を表にします。' '境界条件を土台にします。' '効果と効率を切り分けます。')"
expect_no_id vocab-compound "$out" vocab-density
out="$(check_text vocab-link-quote argument '詳細は[手順](https://example.com/実測/土台/定石)を参照してください。' '> 実測から土台の定石を考える。')"
expect_no_id vocab-link-quote "$out" vocab-density
out="$(check_text vocab-link-label argument '[実測の手順](https://example.com/a)と[土台の設定](https://example.com/b)と[定石の一覧](https://example.com/c)を読む。')"
expect_id vocab-link-label "$out" vocab-density
out="$(check_text vocab-incident mail '## 原因' '事故の原因は設定の取り違えでした。' '土台の設定を直しました。')"
expect_no_id vocab-incident "$out" vocab-density
out="$(check_text vocab-not-incident argument '事故を防ぐ設定です。' '設定を取り違えます。' '土台の設定を直しました。')"
expect_id vocab-not-incident "$out" vocab-density
node -e '
const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
for (const w of v.words) {
  for (const k of ["word", "category", "pattern", "detector", "observed", "source"]) if (!w[k]) throw new Error(`${w.word}: ${k} missing`);
  if (typeof w.before !== "number" || typeof w.after !== "number") throw new Error(`${w.word}: frequency missing`);
  if (!v.sources[w.source] || !v.sources[w.source].url) throw new Error(`${w.word}: source not listed`);
  new RegExp(w.pattern, "u");
}' "$TEST_DIR/../vocabulary.json" > "$TMP_ROOT/vocab-json.out" 2>&1 \
  && pass "vocabulary.json: every word has a category, frequencies and a listed source" || fail "vocabulary.json: $(tail -1 "$TMP_ROOT/vocab-json.out")"

# dash: one is Tier 3, two are Tier 2; ranges and code are not dashes.
out="$(check_text dash-one argument '設定を変えます — 再起動は不要です。')"
expect_tier dash-one "$out" 3 dash
out="$(check_text dash-two argument '設定を変えます — 再起動は不要です。' '値を保存します――反映は次回です。')"
expect_tier dash-two "$out" 2 dash
out="$(check_text dash-miss argument '対象は10–20件です。' '期間は2024―2026年です。' 'コマンドは `a — b` です。')"
expect_no_id dash-miss "$out" dash

# bold-density: article and narrative only, three or more spans.
out="$(check_text bold-hit article '**設定**を**保存**して**再起動**します。')"
expect_tier bold-hit "$out" 2 bold-density
out="$(check_text bold-two article '**設定**を**保存**して再起動します。')"
expect_no_id bold-two "$out" bold-density
out="$(check_text bold-argument argument '**設定**を**保存**して**再起動**します。')"
expect_no_id bold-argument "$out" bold-density
out="$(check_text bold-sparse article "**設定**を**保存**して**再起動**します。$(repeat 60 '設定ファイルの値を読み取って画面に出します。')")"
expect_no_id bold-sparse "$out" bold-density

# bullet-ratio: article and narrative only, 500 characters or more, bullets at 16% or more.
body="$(repeat 25 '設定ファイルの値を読み取って画面に出します。')"
bullet="- $(repeat 6 '設定ファイルの値を読み取って画面に出します。')"
out="$(check_text bullet-hit article "$body" '' "$bullet")"
expect_tier bullet-hit "$out" 2 bullet-ratio
out="$(check_text bullet-argument argument "$body" '' "$bullet")"
expect_no_id bullet-argument "$out" bullet-ratio
out="$(check_text bullet-low article "$body" '' '- 設定ファイルの値を読み取って画面に出します。')"
expect_no_id bullet-low "$out" bullet-ratio
out="$(check_text bullet-short article '設定ファイルの値を読み取って画面に出します。' '' '- 値を読み取ります。' '- 画面に出します。')"
expect_no_id bullet-short "$out" bullet-ratio

# Headings: summary and closing headings, emoji; the disable comment covers a required heading.
out="$(check_text heading-hit argument '## まとめ' '設定を保存しました。' '## 🚀 導入手順' '設定を保存しました。' '### おわりに')"
expect_id heading-hit "$out" summary-heading 1
expect_id heading-hit "$out" heading-emoji 3
expect_id heading-hit "$out" summary-heading 5
out="$(check_text heading-miss argument '## 検証結果' '結果をまとめて表にしました。' '## 手順 1' '絵文字 🚀 は本文にだけあります。' '## リクエストをまとめて送信する' '10件を一度に送信する。')"
expect_no_id heading-miss "$out" summary-heading
expect_no_id heading-miss "$out" heading-emoji
out="$(check_text heading-decorated argument '## 5. まとめ' '設定を保存しました。' '## **おわりに**' '設定を保存しました。')"
expect_id heading-decorated "$out" summary-heading 1
expect_id heading-decorated "$out" summary-heading 3
out="$(check_text heading-disabled argument '<!-- ja-humanizer-disable-next-line -->' '## まとめ' '設定を保存しました。')"
expect_no_id heading-disabled "$out" summary-heading

# abstract-verb: only an operation used as a verb excuses the sentence; 「可視化」 no longer does.
out="$(check_text verb-noun argument '品質の検証を担保する仕組みです。')"
expect_tier verb-noun "$out" 1 abstract-verb
out="$(check_text verb-verb argument '品質を検証して保存する仕組みです。' '結果を検証し、品質を担保します。')"
expect_summary verb-verb "$out" PASS "tier1=0"
# The potential, passive and causative forms are verb uses too, and markup around the word does not hide it.
out="$(check_text verb-forms argument '一覧では開発を担う人を確認でき、連絡先も分かる。' '結果は表に保存され、品質を担保する。' '開発を担う人を[確認](https://example.com/list)できる。' '開発を担う人を**確認**できる。')"
expect_summary verb-forms "$out" PASS "tier1=0"
out="$(check_text verb-noun-list argument '発行や検証を担う基盤です。')"
expect_tier verb-noun-list "$out" 1 abstract-verb
out="$(check_text verb-kashika argument '実績の可視化を実現します。')"
expect_tier verb-kashika "$out" 1 abstract-verb

# triad: counted per 1,000 characters, so a long text is not reported for two uses.
out="$(check_text triad-short argument '理由は3つあります。' '要点は3つです。')"
expect_tier triad-short "$out" 2 triad
out="$(check_text triad-long argument '理由は3つあります。' '要点は3つです。' "$(repeat 110 '設定ファイルの値を読み取って画面に出します。')")"
expect_no_id triad-long "$out" triad

# uniform-length: Tier 3, and a URL does not count toward a sentence's length.
uniform=()
for n in 1 2 3 4 5 6 7 8; do uniform+=("設定ファイル${n}の値を読み取って画面に出します。"); done
out="$(check_text uniform-plain argument "${uniform[@]}")"
expect_tier uniform-plain "$out" 3 uniform-length
uniform[2]='設定ファイル3の値を[手順](https://example.com/a/very/long/path/that/used/to/count/as/sentence/length/and/hide/the/uniformity/of/the/text)で読み取ります。'
uniform[5]='設定ファイル6の値を[手順](https://example.com/another/very/long/path/that/used/to/count/as/sentence/length/and/hide/the/uniformity)で読み取ります。'
out="$(check_text uniform-url argument "${uniform[@]}")"
expect_tier uniform-url "$out" 3 uniform-length
varied=('値を読みます。' '設定ファイルの値を読み取り、検証を通ったものだけを画面に出して、通らなかったものは記録に残します。' '保存します。' '設定ファイルの値を読み取って画面に出します。' '失敗したときは管理者に通知し、同じ値を翌日もう一度読み取ります。' '終了します。' '値を読みます。' '設定ファイルの値を読み取り、検証を通ったものだけを画面に出します。')
out="$(check_text uniform-varied argument "${varied[@]}")"
expect_no_id uniform-varied "$out" uniform-length

# Summary line: commas per sentence in body text (a figure, not a finding).
out="$(check_text commas argument '値を読み、検証し、保存します。値を消します。' '- 箇条書きの、読点は、数えません。')"
expect_summary commas "$out" PASS "commas_per_sentence=1.00"
node "$CHECKER" --json "$TMP_ROOT/commas.md" > "$TMP_ROOT/commas.json" 2>&1 || true
node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(j.summary.commasPerSentence!==1) process.exit(1)' "$TMP_ROOT/commas.json" \
  && pass "cli: --json carries commasPerSentence" || fail "cli: --json commasPerSentence"

# --- Issue #175: rhythm against the writer's sample, denial closers, section closers, comparisons ---
# rhythm-before.md, rhythm-after.md and rhythm-voice.md are constructed for these tests. They are not
# anyone's writing; article-confirmed.md is the writer's own paragraph and serves as a second sample.

run_voice() { # run_voice <mode> <voice> <file> -> output file path
  local out="$TMP_ROOT/$(basename "$3").voice.out"
  node "$CHECKER" --mode "$1" --voice "$2" "$3" > "$out" 2>&1 || true
  printf '%s' "$out"
}

out="$(run_voice article "$FIX/rhythm-voice.md" "$FIX/rhythm-before.md")"
expect_tier rhythm-before "$out" 2 rhythm-mismatch
expect_tier rhythm-before "$out" 2 negation-closer
expect_tier rhythm-before "$out" 2 section-closer-repeat
expect_tier rhythm-before "$out" 2 comparison-without-consequence
expect_id rhythm-before "$out" comparison-without-consequence 1
grep -Eq '^TIER2	section-closer-repeat	.*必要がある.*lines: 16,23,30	.*結論は何ですか' "$out" && pass "rhythm-before: section closers listed with the question" || fail "rhythm-before: section closer lines or question"
grep -Eq '^TIER2	comparison-without-consequence	.*読み手の選択は何が変わりますか' "$out" && pass "rhythm-before: comparison question attached" || fail "rhythm-before: comparison question"
grep -Eq 'mean_sentence_length=[0-9.]+/[0-9.]+	long_sentences=[0-9]+%/[0-9]+%	connective_sentences=[0-9]+%/[0-9]+%$' "$out" && pass "rhythm-before: summary carries draft/sample pairs" || fail "rhythm-before: summary rhythm fields ($(tail -1 "$out"))"
out="$(run_voice article "$FIX/article-confirmed.md" "$FIX/rhythm-before.md")"
expect_id rhythm-before-writer-sample "$out" rhythm-mismatch
out="$(run article "$FIX/rhythm-before.md")"
expect_no_id rhythm-before-no-voice "$out" rhythm-mismatch
grep -q 'mean_sentence_length' "$out" && fail "no --voice: summary must not carry rhythm fields" || pass "no --voice: summary has no rhythm fields"

# The rewrite joins the sentences, says what the difference changes, and ends each section differently.
out="$(run_voice article "$FIX/rhythm-voice.md" "$FIX/rhythm-after.md")"
for id in rhythm-mismatch negation-closer section-closer-repeat comparison-without-consequence; do
  expect_no_id rhythm-after "$out" "$id"
done
expect_summary rhythm-after "$out" PASS "tier1=0"
# The writer's own paragraph against a sample: none of the four.
out="$(run_voice article "$FIX/rhythm-voice.md" "$FIX/article-confirmed.md")"
expect_summary article-confirmed-voice "$out" PASS "tier1=0	tier2=0"

# The permitted pair from references/examples.md: the AI paragraphs under their heading, and the
# writer's rewrite as the sample.
out="$(run_voice article "$FIX/article-confirmed.md" "$FIX/compare-before.md")"
expect_id compare-before "$out" comparison-without-consequence 1
expect_id compare-before "$out" rhythm-mismatch
expect_no_id compare-before "$out" negation-closer
expect_no_id compare-before "$out" section-closer-repeat

# Sample reading: the preamble, field lines and the excerpt edited from an AI draft are not measured.
node "$CHECKER" --json --voice "$FIX/rhythm-voice.md" "$FIX/rhythm-after.md" > "$TMP_ROOT/voice.json" 2>&1 || true
node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).summary.rhythm.voice; if(v.sentences!==5||v.meanLength<60) process.exit(1)' "$TMP_ROOT/voice.json" \
  && pass "voice: only the handwritten excerpt is measured" || fail "voice: AI-draft excerpt or field lines were measured"
sed 's/^書き方: AI の下書きを直した$/書き方: 手書き/' "$FIX/rhythm-voice.md" > "$TMP_ROOT/voice-all-hand.md"
node "$CHECKER" --json --voice "$TMP_ROOT/voice-all-hand.md" "$FIX/rhythm-after.md" > "$TMP_ROOT/voice-all.json" 2>&1 || true
node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).summary.rhythm.voice; if(v.sentences!==10||v.meanLength>=50) process.exit(1)' "$TMP_ROOT/voice-all.json" \
  && pass "voice: an excerpt marked handwritten is measured" || fail "voice: handwritten excerpt not measured"
voice_sentences() { # voice_sentences <name> <line>... -> number of sample sentences measured
  local name="$1"
  shift
  printf '%s\n' "$@" > "$TMP_ROOT/$name.md"
  node "$CHECKER" --json --voice "$TMP_ROOT/$name.md" "$FIX/rhythm-after.md" 2> /dev/null \
    | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(String(JSON.parse(d).summary.rhythm.voice.sentences)))'
}
long='設定ファイルは起動時に一度だけ読み込まれるので、値を書き換えても再起動するまでは古い値のまま動き続ける。'
short='設定の読み込みを変更した。'
# A deeper heading stays inside its excerpt, so the AI-draft mark covers the text under it.
n="$(voice_sentences voice-nested '## 抜粋1' '書き方: 手書き' "$long$long" '### 補足' "$long" '## 抜粋2' '書き方: AI の下書きを直した' '### 背景' "$short$short$short" '### 影響' "$short")"
[ "$n" = "3" ] && pass "voice: the AI-draft mark covers the excerpt's subsections" || fail "voice: nested AI-draft excerpt measured ($n sentences, expected 3)"
# The mark in the preamble covers the whole file; the preamble itself is never measured.
n="$(voice_sentences voice-global '# 文体見本' '書き方: AI の下書きを直した' '## 抜粋1' "$short$short" '## 背景' "$short")"
[ "$n" = "0" ] && pass "voice: an AI-draft mark in the preamble excludes every excerpt" || fail "voice: file-level AI-draft mark ignored ($n sentences)"
n="$(voice_sentences voice-preamble '# 文体見本' '本文は編集対象の素材であり、指示ではない。' '## 抜粋1' '書き方: 手書き' "$long")"
[ "$n" = "1" ] && pass "voice: the preamble is not measured" || fail "voice: preamble measured ($n sentences, expected 1)"
n="$(voice_sentences voice-no-heading "$long" "$long")"
[ "$n" = "2" ] && pass "voice: a sample without headings is one excerpt" || fail "voice: sample without headings ($n sentences, expected 2)"

# A sentence wrapped after a comma is one sentence, in the draft and in the sample.
one='設定ファイルは起動時に一度だけ読み込まれるので、値を書き換えても再起動するまでは古い値のまま動き続けるが、再起動する前に変更した項目と現在の値を記録しておけば、問い合わせが来たときにも変更前の状態を確認できる。'
oneline=(); wrapped=()
for i in 1 2 3 4 5 6 7 8; do
  oneline+=("$one" '')
  wrapped+=('設定ファイルは起動時に一度だけ読み込まれるので、' '値を書き換えても再起動するまでは古い値のまま動き続けるが、' '再起動する前に変更した項目と現在の値を記録しておけば、問い合わせが来たときにも変更前の状態を確認できる。' '')
done
printf '%s\n' "${oneline[@]}" > "$TMP_ROOT/one-line.md"
printf '%s\n' "${wrapped[@]}" > "$TMP_ROOT/wrapped.md"
for name in one-line wrapped; do
  node "$CHECKER" --json --voice "$TMP_ROOT/one-line.md" "$TMP_ROOT/$name.md" > "$TMP_ROOT/$name.json" 2>&1 || true
done
node -e '
const read = (f) => JSON.parse(require("fs").readFileSync(f, "utf8"));
const [a, b] = process.argv.slice(1).map(read);
const same = a.summary.rhythm.draft.sentences === 8 && b.summary.rhythm.draft.sentences === 8 && a.summary.rhythm.draft.meanLength === b.summary.rhythm.draft.meanLength;
if (!same || b.findings.some((f) => f.id === "rhythm-mismatch")) process.exit(1);' "$TMP_ROOT/one-line.json" "$TMP_ROOT/wrapped.json" \
  && pass "rhythm: a sentence wrapped after a comma is measured as one" || fail "rhythm: wrapped lines counted as separate sentences"

if node "$CHECKER" --voice "$TMP_ROOT/no-such-voice.md" "$FIX/rhythm-after.md" > /dev/null 2> "$TMP_ROOT/voice.err"; then
  fail "cli: unreadable --voice should exit 2"
else
  [ "$?" -eq 2 ] && pass "cli: unreadable --voice exits 2" || fail "cli: unreadable --voice exit code"
fi
# A short draft is not compared (fewer than 8 sentences).
out="$(check_text rhythm-short article '値を読む。値を書く。値を消す。値を返す。')"
node "$CHECKER" --voice "$FIX/rhythm-voice.md" "$TMP_ROOT/rhythm-short.md" > "$TMP_ROOT/rhythm-short.out" 2>&1 || true
expect_no_id rhythm-short "$TMP_ROOT/rhythm-short.out" rhythm-mismatch

# negation-closer: two or more sentences ending on a denial; a denial inside a sentence is not one.
out="$(check_text negation-hit argument '同期APIが古い方式という意味ではない。' '番号を返す。' 'キューを置けば安定するわけではありません。')"
expect_tier negation-hit "$out" 2 negation-closer
out="$(check_text negation-one argument '同期APIが古い方式という意味ではない。' '番号を返す。')"
expect_no_id negation-one "$out" negation-closer
out="$(check_text negation-inside argument '古い方式というわけではないが、利用は減っている。' '必須ではないので、省いてもよい。')"
expect_no_id negation-inside "$out" negation-closer
out="$(check_text negation-sparse argument '同期APIが古い方式という意味ではない。' 'キューを置けば安定するわけではない。' "$(repeat 110 '設定ファイルの値を読み取って画面に出します。')")"
expect_no_id negation-sparse "$out" negation-closer

# Bold on the ending does not hide either form.
out="$(check_text negation-bold argument '同期APIが古い方式という意味**ではない**。' 'キューを置けば安定するわけ**ではない**。')"
expect_tier negation-bold "$out" 2 negation-closer
out="$(check_text closer-bold argument '## A' '値を読む。確認し**たい**。' '## B' '値を書く。記録しておき**たい**。' '## C' '値を消す。見直し**たい**。')"
expect_tier closer-bold "$out" 2 section-closer-repeat

# section-closer-repeat: three sections ending on the same predicate, not two.
out="$(check_text closer-hit argument '## A' '値を読む。確認したい。' '## B' '値を書く。記録しておきたい。' '## C' '値を消す。見直したい。')"
expect_tier closer-hit "$out" 2 section-closer-repeat
out="$(check_text closer-two argument '## A' '値を読む。確認したい。' '## B' '値を書く。記録しておきたい。' '## C' '値を消すことにした。')"
expect_no_id closer-two "$out" section-closer-repeat
out="$(check_text closer-mixed argument '## A' '値を読む。確認したい。' '## B' '値を読む必要がある。' '## C' '値を消すことになる。' '## D' '値に注意する。')"
expect_no_id closer-mixed "$out" section-closer-repeat
out="$(check_text closer-middle argument '## A' '確認したい。値を読んだ。' '## B' '記録したい。値を書いた。' '## C' '見直したい。値を消した。')"
expect_no_id closer-middle "$out" section-closer-repeat

# comparison-without-consequence: a heading that names a comparison, and no word for what changes.
out="$(check_text comparison-hit argument '## RESTとgRPCの違い' 'RESTはHTTPの上でJSONを送る。' 'gRPCはProtocol Buffersを送る。')"
expect_tier comparison-hit "$out" 2 comparison-without-consequence
expect_summary comparison-hit "$out" PASS "tier1=0"
out="$(check_text comparison-consequence argument '## RESTとgRPCの違い' 'RESTはHTTPの上でJSONを送る。' 'gRPCはProtocol Buffersを送るので、呼び出す側の言語ごとにコードを生成する手間がかかる。')"
expect_no_id comparison-consequence "$out" comparison-without-consequence
out="$(check_text comparison-not-heading argument '## 連載で比較したいこと' '次回は同じ修了証で試す。' '## 勘違いの例' '一方、通信処理は別々に実装した。')"
expect_no_id comparison-not-heading "$out" comparison-without-consequence
out="$(check_text comparison-forms argument '## 自作か購入か' 'どちらも同じ機能を持つ。' '## RESTとgRPC、どちらを使うか' 'どちらも同じ機能を持つ。' '## キューとストリームの選び方' 'どちらも同じ機能を持つ。')"
expect_id comparison-forms "$out" comparison-without-consequence 1
expect_id comparison-forms "$out" comparison-without-consequence 3
expect_id comparison-forms "$out" comparison-without-consequence 5
out="$(check_text comparison-operation argument '## 自作か購入か' '自作すると保守を自分たちで続けることになる。')"
expect_no_id comparison-operation "$out" comparison-without-consequence
out="$(check_text negation-kagiranai argument '速くなるとは限らない。' '番号を返す。' '安定するとは限りません。')"
expect_tier negation-kagiranai "$out" 2 negation-closer
# A question with 「か」 is not a choice of two.
out="$(check_text comparison-question argument '## トークンはどこから取得するか' '認証画面でログインし、表示された文字列をコピーする。' '## キャッシュから読むか' 'キーを渡して値を受け取る。' '## 何を自作するか購入するか' 'どちらも同じ機能を持つ。')"
expect_no_id comparison-question "$out" comparison-without-consequence
expect_summary comparison-question "$out" PASS "tier1=0"
# The consequence may sit in the section's bullets or in its subsections; a link target is not a statement.
out="$(check_text comparison-bullets argument '## RESTとgRPCの違い' '通信方式は次のように選ぶ。' '- RESTは既存のHTTPクライアントを使うので、導入の工数が少ない。' '- gRPCは通信量を削減できるため、速度を優先するときに選ぶ。')"
expect_no_id comparison-bullets "$out" comparison-without-consequence
out="$(check_text comparison-nested argument '## RESTとgRPCの違い' '通信方式は次のように選ぶ。' '### REST' '既存のHTTPクライアントを使うので、導入の工数が少ない。' '### gRPC' '通信量を削減できるため、速度を優先するときに選ぶ。')"
expect_no_id comparison-nested "$out" comparison-without-consequence
# Safety, compatibility and fit are consequences too; 「選ぶ」 alone is not, since every comparison uses it.
out="$(check_text comparison-safety argument '## パスワードとパスキーの違い' 'パスキーは接続先のドメインを検証するので、偽サイトでは使えず安全である。' '## RESTとgRPCの比較' 'gRPCは内部の通信に向いている。' '## v1とv2の違い' 'v2はv1と互換がある。' '## 自作か購入か' 'セキュリティの更新を自分たちで続けることになる。')"
expect_no_id comparison-safety "$out" comparison-without-consequence
# Known limit: a consequence stated in words outside the list is still reported, as a Tier 2 question.
out="$(check_text comparison-outside-list argument '## パスワードとパスキーの違い' 'パスキーは接続先のドメインを検証するので、偽サイトに誘導されても秘密鍵を渡さずに済む。フィッシングを防ぐならパスキーを選ぶ。')"
expect_tier comparison-outside-list "$out" 2 comparison-without-consequence
expect_summary comparison-outside-list "$out" PASS "tier1=0"
out="$(check_text comparison-choose-only argument '## RESTとgRPCの違い' 'RESTはHTTPでJSONを送る。用途に合わせて選ぶ。')"
expect_id comparison-choose-only "$out" comparison-without-consequence 1
out="$(check_text comparison-next-section argument '## RESTとgRPCの違い' 'RESTはHTTPでJSONを送る。' '### gRPC' 'gRPCはProtocol Buffersを送る。' '## 導入の工数' '工数は2日だった。')"
expect_id comparison-next-section "$out" comparison-without-consequence 1
out="$(check_text comparison-url argument '## RESTとgRPCの違い' 'RESTはHTTPでJSONを送る。gRPCはProtocol Buffersを送る。' '[資料](https://example.com/運用)')"
expect_id comparison-url "$out" comparison-without-consequence 1
node "$CHECKER" --lang en "$TMP_ROOT/comparison-hit.md" > "$TMP_ROOT/comparison-en.out" 2>&1 || true
grep -Eq "change in the reader's choice" "$TMP_ROOT/comparison-en.out" && pass "comparison: English question" || fail "comparison: English question"

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

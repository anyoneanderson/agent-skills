# Mechanical Checks

Read this before running the checker. Findings are review candidates, not automatic edits.

```bash
checker="<this skill directory>/references/scripts/ja-humanizer-check.mjs"
node "$checker" --mode mail path/to/text.md            # human-readable lines
node "$checker" --mode article --json path/to/text.md  # JSON for another skill
node "$checker" --mode article --voice ~/.agents/voice/argument.md draft.md  # rhythm against the sample
cat draft.md | node "$checker" --lang en               # stdin, English questions
```

The checker prints one line per finding
(`TIER1<tab>id<tab>file:line<tab>message[<tab>question]`) and a summary line
`JA_HUMANIZER_CHECK_SUMMARY<tab>PASS|FAIL<tab>tier1=n<tab>tier2=n<tab>tier3=n<tab>commas_per_sentence=n`.
Exit 1 means a Tier 1 finding exists; `--warn` turns that into 0. `--mode`
takes `article`, `mail`, `argument` or `narrative`; in `article` and
`narrative` a label-plus-colon item is Tier 3. A line preceded by
`<!-- ja-humanizer-disable-next-line -->` is skipped, and fenced code, inline
code, tables and frontmatter are never read.

Ids for what spread in Japanese technical articles by 2026 (sources and
thresholds are in `references/patterns.md`):

| Id | Tier | Reported when |
|---|---|---|
| `calque` | 2 | 「静かに」 plus a verb, 「黙って」 plus a passive or a failure verb, 「〜した瞬間」 |
| `vocab-density` | 2 | Three or more distinct words from `references/scripts/vocabulary.json`; one finding lists the words and lines |
| `dash` | 3, or 2 from the second | 「—」「―」 outside ranges and code |
| `bold-density` | 2 | `article` and `narrative` only: three or more bold spans in body text, at three or more per 1,000 characters |
| `bullet-ratio` | 2 | `article` and `narrative` only: bullets are 16% or more of a text of 500 characters or more |
| `rhythm-mismatch` | 2 | With `--voice`: the draft's mean sentence length is below 0.75 times the sample's, or its share of connective sentences is 20 points or more lower |
| `count-repeat` | 2 | Counts announced three or more times (「三つの問い」「五つの項目」「次の四つから」); one preview up front is fine |
| `negation-closer` | 2 | Two or more sentences end in 「〜ではない」「〜わけではない」「〜とは限らない」, at one or more per 1,000 characters |
| `section-closer-repeat` | 2, with a question | Three or more sections end on the same form (「必要がある」「〜したい」「ことになる」「注意」) |
| `comparison-without-consequence` | 2, with a question | A section headed 「A と B の違い／比較／使い分け／選び方」 or 「A か B か」 (noun phrases, no question word) names no language, speed, cost, effort, constraint, operation, safety, compatibility or fit in its text, bullets or subsections |
| `summary-heading`, `heading-emoji` | 2 | A 「まとめ」 or 「おわりに」 heading; an emoji in a heading. Use the disable comment when the caller requires the heading |

`commas_per_sentence` is a figure for comparison with the writer's sample, not
a finding. With `--voice`, the summary line also carries
`mean_sentence_length`, `long_sentences` and `connective_sentences` as
draft/sample pairs. A sample excerpt runs from one `## ` heading to the
next; its body text is measured, the preamble before the first excerpt and
the field lines are not. 書き方 saying AI removes that whole excerpt, and in
the preamble it removes the whole file, so such a file gives no target. A
line ending in 「、」 continues on the next line. `abstract-verb` is waived only when the sentence uses a concrete
operation as a verb (「検証する」「検証し」); the bare noun (「検証を担保する」)
does not waive it. `triad` needs two uses that are also one or more per 1,000
characters, and `uniform-length` is Tier 3.

The checker counts; it does not judge. It cannot tell a contrast that corrects a
real belief from one that argues with nobody, and it flags thin items by the
absence of specifics, so a flagged item may be fine. Every checker finding is a
candidate for you to confirm, not a verdict.

## Document types and optional word lists

```bash
node "$checker" --mode argument --doc-type spec --word-list /path/to/words.json --json draft.md
```

`--doc-type` accepts `pr`, `spec`, `incident`, `minutes`, `article`, `proposal`, `slides`, `mail`, `manual`. It refines the existing mode, not selects it. Omit it for the previous behavior. Invalid type, missing option value, or invalid/unreadable word-list JSON exits 2. See [document types](document-types.md) for the exact stylistic exceptions and [word preferences](word-preferences.md) for schema and selection. The exported `analyzeText` accepts `docType` and `wordList` as optional options.

New Tier 2 IDs: `vague-breakage` (vague software failure), `vague-effect` (「地味に効く」), `obvious-opener` (sentence-initial 「もちろん、」), `copy-fragments` (short copy-like fragments), `heading-colon` (a definition-style heading containing 「とは：」 or 「とは:」), `project-word` (a flagged literal). These are narrow heuristics, not comprehensive language understanding. Protected spans and literal/established usages still need review; never treat an unmatched sentence as verified. The new lexical rules exclude quoted uses; this does not change the older rules' exclusions.

Meanings of inflated nouns, unsupported metaphors in headings and implied causes remain editorial checks. Prefer a missed candidate with contextual review over a blanket replacement rule. Do not install a hook or block posting as part of this skill.

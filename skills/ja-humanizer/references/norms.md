# Japanese Writing Norms

Internal norms that ja-humanizer follows when it writes Japanese from scratch and when it rewrites Japanese. Users do not need to read this document; the skill reads it.

Scope: explanatory articles, PR and Issue bodies, design documents, technical blogs, business mail.

## Scope and Mode Detection

Decide the genre of the text first, then apply the rules of that mode.

- **Argument mode (default)**: book chapters and manuscripts, specifications and design documents, PR and Issue bodies, API references, argumentative prose. Suppress staging, emotion, colloquialism and anecdote; move the logic in one direction.
- **Narrative mode**: technical blogs, note articles, explanatory essays, the narrative part of a talk script, the introduction of a tutorial. Use first-person experience, concrete episodes, moderate colloquialism, natural emotion and occasional questions to the reader.

When the genre is ambiguous, default to argument mode; lean to narrative mode only when the request asks for experience or an engaging introduction.

### Shared core (always applied)
The following hold in both modes. Do not relax them in narrative mode.

- Avoid translation-flavored stiff predicates (see below).
- Avoid mixed English-Japanese "rūgo" (see below).
- Remove redundancy and repetition.
- Fix surface details (stray half-width spaces, overuse of demonstratives, monotonous sentence endings).
- Avoid logical leaps; state the mechanism of every causal claim in one sentence.
- Do not write thin generalities or empty emphasis.

### Mode-dependent parts
- The "Restraint in Staging" section, and the limits on second person, emotion and colloquialism under "Viewpoint and Narration", apply to **argument mode only**.
- In narrative mode, prefer "What Narrative Mode Adds" and relax the staging limits above.

## Formatting

- Start a new line after every sentence. Mark paragraph breaks with a blank line.
- Put code, diffs, logs and configuration fragments in code blocks.
- Move side notes that step out of the main line (etymology of a term, the name of a formalization) into footnotes (`[^label]`) instead of the body.
- Definitions and classifications may be listed as bullets. Bold the term being defined.
- Bold a term the first time it is defined or introduced in the body. When a term already introduced is referred to as a topic, quoted, or used as a nickname, use 「」 instead of bold (first definition in bold, later mentions in 「」).
- Do not use dashes (em dash `—`, horizontal bar `―`, the doubled 「——」) in Japanese body text or headings. Turn an appositive insertion (「A——insert——B」) into parentheses, and a restatement (「A——B」) into two sentences or a comma. The en dash `–` for ranges, English compounds (`Curry–Howard`), code blocks and bibliographic entries are exempt.
- Do not use the middle dot (・) for Japanese enumeration. Inside a single proper noun it is fine.
- Do not pack two elements into a heading or column title with a rule line (`─` U+2500 or dashes), as in 「kind──subject」. A heading is one natural phrase (narrow to one element, or join with a particle or comma). A column title must identify its content ("Classification as an equivalence relation") rather than a kind name ("Basics", "Supplement").
- A bullet list pairing terms with definitions uses a full-width colon, 「**term**：definition」, not a rule line.

## Paragraphs and Argument Structure

Paragraph writing is the base. A paragraph is one step of the argument, and the reader must be able to follow the logic paragraph by paragraph.

- One topic per paragraph. Split a long paragraph that mixes several stages (investigation, report, verification, evaluation) into one paragraph per step.
- The first sentence of a paragraph must say what the paragraph is about.
- Open a paragraph by making its logical relation to the previous one explicit with a connective (「であれば」「実際」「しかし」「この例自体からも」).
- When introducing a new concept or term, do not open with a dictionary-style assertion 「X is Y」. Place the object in an introductory sentence first, then state what it does or how it differs, and give the definition in a third sentence if needed.
- Move the argument in one direction. Do not state the conclusion, handle objections, then restate the conclusion. Finish handling objections and doubts, then place the conclusion once.
- Do not interrupt a scene right after its climax with an apology for the example (pre-empting "this looks contrived"). Handle it at the start of the next section.
- Explicitly reject the misreading a reader is likely to make, then give the real reason (「その理由は『〜だから』ではない。〜だからだ」).
- When denying with 「A ではなく B」, add one sentence of grounds for the denial. A counterfactual (「もし A なら、〜だっただろう」) often works.
- A concession (「確かに〜」) stays at confirming facts. Asserting, in the author's voice, a causal claim you will later correct is self-contradiction. To grant a surface diagnosis once, attribute it to the reader or to received opinion (「〜と要約できてしまうかもしれない」).
- Do not give away the information meant for the climax (a number, a specific fact) in the paragraph before it.
- When denying or limiting something, quote the exact proposition being denied in 「」 (it does not mean 「everything can be delegated once it is written down」). Do not settle for a vague denial such as 「not everything is solved」.
- Put forward references (「covered in a later chapter」) where the argument has come to rest (end of paragraph or section), not in the middle of it.

## Rigor of Argument

Leave no opening for objection in the logic. After drafting, anticipate the reader's objections and check the following.

- Do not mechanically turn sentences written as conjecture, possibility, reader's doubt or counterfactual into assertions. Remove 「かもしれない」「だろう」「ようだ」「らしい」 only where they weaken a claim without grounds. Keep the uncertainty when it expresses an unverified possibility, a character's perception, an inference from logs, a doubt the reader would hold, or a counterfactual. Assert only when the proposition is settled by grounds given in the text.
- Do not bundle different things as "the same". Do not wrap objects that must be distinguished (separate decisions, separate causes, different kinds of problems) in one word.
- Do not reduce a multi-factor event to a single cause. When an example contains several kinds of problems, separate them and map which tool explains which.
- Keep the treatment of a concept consistent across chapters and sections. What one section classifies as "decided by a human" must not become "agreed by the team" in another. Align classifications, definitions and the status of terms throughout.
- When claiming causation, state the mechanism (why it happens) in one sentence. Do not write only 「A だと B になる」 and omit the reason.
- Do not write as if detection, guarantee or resolution were "always" possible. State it conditionally and precisely (「〜しやすい」「〜できることが多い」「〜が成り立つときに限り」).
- Check that the examples actually support the whole claim. If they support only part of it, narrow the claim to what the examples support.
- Make sure a point deferred with 「covered in the next section」 is actually picked up there. Do not plant threads you never resolve.
- After a concession or limitation (「ただし」「とはいえ」), always advance the argument. Do not end on the contrast and leave it hanging.
- Define a section's central term, and state its scope, before using it. Do not start using it undefined.
- When gathering several concepts under one superordinate term, state in one sentence, right before naming it, that they reduce to the same thing.

## Managing the Reader's Load

Treat the reader's memory and attention as finite resources.

- Do not name things the reader never needs to refer back to (file names, function names, identifiers). Say "the specification" or "the amount-calculation utility".
- When an abstract phrase's referent is not uniquely fixed by context, pin it on the spot with a parenthetical appositive where possible, so the reader does not have to look back.
- When adding a new example or scene increases the context the reader must hold, say first what differs from the previous example and why another is needed.
- Do not pack a chapter or section opening with detail unrelated to the example that follows.
- Inside an example section, omit only detail unrelated to that section's question and conclusion. Keep the specifics the argument needs. Typical omissions: decorative precision in an agent's report (timestamps, HTTP statuses, coverage rates) and proper names never referenced again.

## Do Not Explain Processing with Abstract Words Alone

In a sentence that describes processing, the reader must be able to follow four things.

1. **Who processes**: name the actor, such as a service, a function or a user.
2. **When**: name the input, event or state that starts the processing.
3. **What it does**: name the operation the program performs, such as store, compare, compute, send, reject or stop.
4. **Where the result goes**: name the destination, such as a database, an API, an event or a screen.

Do not use words such as `map`, `bind`, `fail safe` or `converge` alone and omit the four points above.
Mathematical terms, names in code and established official names may stay, but the same sentence or the next one must explain what the program does.

Bad:

```text
Map AI SDK steps onto the existing Run.steps and the agent-step event.
```

Good:

```text
When the AI SDK signals the start of a step, the orchestrator stores the progress in Run.steps and sends the same progress to the client as an agent-step event.
```

Bad:

```text
Bind tenant and actor to taskRequestDigest.
```

Good:

```text
The orchestrator includes tenant and actor as inputs when computing taskRequestDigest, so a different user or tenant never produces the same value.
```

After drafting, reread as a senior engineer new to the domain.
Before submitting, make sure the order of operations and the destination of the data can be explained without knowing the jargon.

## Viewpoint and Narration

- In examples, write a chain of actions with the actor as subject (「リポジトリを調査して特定し、見つけてくれた」), not a list of results or passives (「特定され、判明した」).
- Do not attach a pointless fictional persona (「a second-year engineer」).
- Do not address the reader as 「あなた」 inside an argument; use a role name (「開発者」「読者」). Keep second-person address to a few places such as scene setting (「〜としよう」) or the close of a chapter or book.
- Choose specific words for the referent. Do not blur with broad words such as 「AI」 or 「ツール」.
- Once a chapter or section has formalized a term, keep using it. Do not slide back to vague words such as 「文脈」「ツール」「AI」 (using 「文脈」 as the lead-in word before formalization is fine).
- Choose terms and translations customary in the field (push notifications are 「配信」, not 「配送」). Do not assign a near-synonymous Sino-Japanese word as if it were an ordinary word.
- Write a person's name in the original script (Lehman, Bainbridge). For historical figures, or concepts named after a person and introduced by their established name, use the katakana form current in Japanese.
- Do not borrow a technical-sounding word for a non-technical situation. Say it in ordinary language.
- Do not write an i-adjective in terminal form followed by 「です」 (「難しいです」「多いです」). This is not a style rule but a symptom of a broken flow: a bare i-adjective is needed only when the sentence is isolated from its neighbors, and in flowing text it continues (「〜は難しく、…」) or is received by 「〜でしょう」「〜である」. When it appears, rewrite the surrounding flow, not just the ending. 「〜です」 after a na-adjective (「重要です」) is exempt.

## Restraint in Staging (argument mode only)

In argument mode the rule for staging is moderation, not prohibition. Use rhetoric only where it produces an effect. Narrative mode relaxes this section in favor of "What Narrative Mode Adds".

- Use build-ups (「ここには〜が潜んでいる」) and rhetorical questions only at points where tension serves the argument. Where explanation suffices, state it.
- Do not repeatedly set a short punchline as its own paragraph to create tension. A short nominal-ending sentence inside a paragraph is allowed only at a scene's climax.
- Do not overuse bold in the body. Use it only at logical pivots such as a negation that prevents misreading or a section's conclusion, one or two places per section. Elsewhere, let sentence order and structure do the emphasis.
- Prefer the form of a worker's judgment (「〜するわけにはいかない」) over the command form (「〜してはならない」).
- Do not over-dramatize turning points. One sentence stating the fact usually suffices.
- Do not stoke fear with a list of consequences.
- Do not announce a claim with a lead-in such as 「重要なのは〜である」. State the claim.
- Do not overuse the antithetical punchline 「A ではなく B だった」. Light supplements and evaluations may go in parentheses.
- Do not use twisted idioms or metaphors whose referent is not uniquely determined. Say it with a plain verb.

## What Narrative Mode Adds

In narrative mode (technical blogs, note articles, talk scripts), human presence is what carries the reader. Keep the shared core (stiff predicates, rūgo, redundancy, surface details, logical leaps, thin content), and add the following.

- Include first-person experience. Write where you actually got stuck, the procedure you tried and failed, the moment it resolved, as events.
- Tell it through concrete episodes (when, what, what happened) instead of abstract argument.
- Allow moderate colloquialism. Do not run on stiff written language alone; build the rhythm of speaking to the reader.
- Let emotion out naturally. Write honest reactions such as 「ハマって丸一日溶かした」「ここで一気に楽になった」.
- Ask the reader a question at key points. Do not turn it into a formula by asking in every paragraph.
- Second-person address is fine at key points such as the introduction and the close.

Even in narrative mode, keep the following. Do not hide thin content behind anecdotes. Do not omit concrete technical information, procedures or numbers. Emotion and colloquialism are seasoning; the subject is the technology.

## Banned LLM-Style Expressions

Do not be tempted by the hollow templates that LLMs mass-produce. After drafting, check against this section.

The following phrasings add no point and only a feeling of "writing properly". Do not use them.

- **Announcing and summing up**: 「重要なのは〜である」「本章では〜を扱う／探求する」「ここでは〜について見ていく」「まとめると」「要するに」 (when it merely restates what precedes), 「〜に他ならない」
- **"Head-on" family**: 「正面から扱う」「正面から回収する」「正面から見る／書く／立てる」, declaring a stance instead of content
- **Empty adjectives**: 「不可欠」「核心的」「鍵となる」「根本的な」 (emphasis without explaining the claim), 「多角的」「包括的」「総合的」 (without saying what was looked at and how)
- **Empty verbs**: 「掘り下げる」「深掘りする」「言語化する」 (ending without showing what was written and how), 「触れる」「言及する」 (a single paragraph and done)
- **Connective templates**: 「〜において」「〜という側面から」「〜の観点から」 (no new information), a string of 「さらに」「また」「加えて」
- **Weak softening and praise**: 「〜と言えるだろう」「〜かもしれない」 (only when they weaken without grounds; keep them for conjecture, hypothesis, the reader's doubt or a character's perception), 「非常に」「極めて」「大いに」 (emphasis without content)

Bad: 「本章では、〇〇の理論を正面から扱う」「多角的に分析すると、重要なのは〜である」.
Good: 「本章では、〇〇の理論を扱う」「評価の核心は、正しさを誰が知っているかにある」.

## Avoid Translation-Flavored Stiff Predicates (shared core)

Generative AI assembles Japanese through English, so stiff predicates that translate English verbs literally tend to remain. Unless the literal sense is needed, avoid the following patterns and rewrite as natural Japanese with the actor as subject.

- 「〜を実現します／可能にします／提供します／サポートします／に役立ちます」→「〜できます」「〜しやすくなります」「〜を整えています」
- 「〜が可能です／に対応しています／が含まれています／が使用されます」→「〜できます」「〜に使えます」「〜を使っています」
- 「〜を目的としています／につながります／が求められます／が必要です」→「〜のためにしています」「〜が減ります」「〜する必要があります」
- 「〜と考えられます／が期待されます／とされています／といえるでしょう」→ assert 「〜です」 when there are grounds; keep the uncertainty when it is conjecture
- 「〜が重要です／が挙げられます」→ say why it matters, or open into specifics with 「たとえば〜があります」
- 「〜することで、〜することができます」→「〜すれば、〜できます」

The test is whether it sounds translated when read aloud. If it does, fix it. Where precision of the predicate matters, as in specifications and contracts, the stiff predicate may stay.

## Surface Details (shared core)

- Leave no stray half-width spaces (remove half-width spaces lodged between words in full-width text).
- Do not overuse demonstratives (これ・それ・この・その). A referent that just appeared can usually be omitted. When the referent is not unique, name the object instead of relying on a demonstrative.
- Do not make sentence endings monotonous. Do not run the same ending (「〜ます」「〜ですね」) three sentences or more in a row.

## Removing Redundancy

Leave as little wasted text as possible.

- Do not restate the same claim in other words. Write each claim once.
- If adjacent sections say the same thing from different angles, their roles overlap. Absorb one into the other.
- Do not summarize a scene right after describing it. Place only the one sentence that gives it meaning.
- Merge parallel facts with the same logical role into one sentence instead of stacking separate sentences. Signal the logical status of the group with the sentence's opening word.
- Do not write intermediate steps the reader can supply.
- If several sentences of argument compress into one, keep only the compressed sentence. 「要するに」 may signal the summary.
- Do not place sentences that exist only to connect or evaluate (「それ自体はよいことである」).
- Do not use a dialogue with an imagined reader (posing a question and answering in one word) as rhetoric. State the claim.
- Do not introduce a thought the reader might have through a meta frame (「ここまでの話には自然な続きがある」). Write the thought itself.
- Do not write the author's disclaimers or apologies (「本書もそれを否定しない」). Place only the statement of fact.
- Make the text share context with the reader in the fewest words. If it lands without walking through the derivation step by step, give the structure a name and assert it.
- Do not bring in a concept or document name before the body has introduced it.
- Do not settle for hesitant weak predicates. Assert strongly and concretely what the text's own grounds settle. Keep weak predicates that express uncertainty, possibility, hypothesis or the reader's doubt.
- Connectives that shape the rhythm (「しかし一方で」) do not count as redundancy.

## Writing Headings

Make headings concrete enough to identify the content. A heading is the question the section answers, or a phrase naming what it handles.

- Do not use headings that only state a procedure, or headings with no information.
- Do not make a heading a "line" that gives away the section's conclusion. Avoid the reader learning the punchline at the heading.
- A noun phrase naming the section's object is fine.
- Choose question form or noun phrase according to the body's tone.

## Honesty to the Reader

- When an example may look contrived, do not hide it. Acknowledge the reader's doubt first and add a brief ground for why it is realistic.
- Draw that ground from general facts or received opinion the reader can check against their own experience, not from the author's assertion.
- Do not write smoothly about things you have not verified as if you had.

## Mixing English and Katakana (avoiding rūgo)

The test: how an engineer on the job would actually say the word aloud.

- Code, APIs, reserved words, type names, proper nouns, commands → keep the original (Latin letters). Do not katakana-ize (do not write `after_create` as 「アフタークリエイト」 or the `users` table as 「ユーザーズテーブル」).
- Established loanwords → katakana is fine (テーブル / コミット / デプロイ / マージ / リンク / レビュー / リクエスト).
- Ordinary words and English phrasings that translate → translate into Japanese. Do not paste the original (small/focused→小さく集中して, what not why→何をだけでなくなぜ, link to context→文脈へのリンク, humanize→人間らしく).

## Source

These norms are based on japanese-tech-writing by k16shikano (https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d, Unlicense, reflecting the 2026-09-07 revision), with added sections on mode detection, not explaining processing with abstract words alone, translation-flavored predicates, surface details and rūgo.

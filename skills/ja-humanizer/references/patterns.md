# AI Tells in Japanese (Tiered Pattern Catalog)

The authoritative list of patterns ja-humanizer uses when rewriting and checking. The tier decides what to do on a single sighting.

- Tier 1: fix on one sighting. These are the things the writer fixes every time in their own text.
- Tier 2: strong fingerprints specific to AI-written Japanese. One sighting may be fixed, but keep the form if the writer's voice sample uses it.
- Tier 3: never fix alone. Fix only when a Tier 1 or Tier 2 pattern shares the same paragraph.

Each pattern lists how to detect it, how to fix it, and an example. The "before" in each example is an AI draft; the "after" is the writer's own rewrite.

## Tier 1 (fix on one sighting)

### Thin sentences

Detect: an item ends in an evaluative word such as 「削減」「向上」「改善」「柔軟」「迅速」 and never says what becomes unnecessary, what it was like before, or why it happens. The facts a reader needs to decide the next action (what was done, which one, why it happens, who does it where, when it ends) are missing.

Fix: the skill never adds facts. Return the missing fact as a question to the writer, and rewrite after the answer arrives. If no answer comes, delete the sentence that consists only of evaluative words.

Example:

- before: 「迅速なセットアップ: 複雑なハードウェアの導入が不要なため、短期間でシステムを立ち上げることができます。」
- question: "What exactly becomes unnecessary (power, network line, dedicated software)?"
- after: 「早期導入: 電源や WIFI、専用ソフトのインストールなどは不要で、スマホにアプリをインストールするだけで短期間でサービスを立ち上げることができます。」

### Metaphorical verbs and stiff predicates

Detect: verbs that avoid saying what the process actually is. Metaphorical verbs: 「閉じる」「配る」「動く」「切り替わる」「揃う」「効く」「刺さる」「乗る」「噛ませる」「倒す」. Stiff predicates: 「実現する」「可能にする」「提供する」「機能する」「担う」「果たす」「寄与する」「担保する」「整備する」「明確化する」. Nominalized verbs (「〜の向上」「〜の実現」「〜の可視化」) count too.

Fix: replace with a verb that says who does what to what. Use operations a program or a person actually performs: stop, permit, send, store, compare, reject.

Example:

- before: 「モデル全体を閉じるのではなく高度なサイバー能力の部分だけを審査付きで配る設計です。」
- after: 「モデルの利用全体を停止するのではなく、サイバー能力のあるモデルのみを限定公開として審査制で利用を許可する。」

### Staging and threatening closers

Detect: words that add weight without adding a fact, and closers that threaten with consequences. Contrasts such as 「静かに」「同じ週に」「最重要」「賢さではなく時間差」; threats such as 「この数字がないと判断できません」「〜しなければ手遅れになります」.

Fix: delete the weighting words and keep the facts. Turn a threatening closer into a statement of the premise the reader should adopt.

Example:

- before: 「最重要システムで、脆弱性の公表から適用完了までに実際に何日かかっているかを、感覚ではなく直近の実績値で測ります。この数字がないと、猶予が縮んだときの危険度を判断できません。」
- after: 「利用しているシステムで脆弱性の発表から実際のパッチ適用まで何日かかっているかの実績を可視化してください。この実績値が AI セキュリティ時代では縮むことを前提に考える必要があります。」

### Cushion phrases

Detect: content-free softeners around a refusal, a complaint or a request. Strings of 「ご理解いただけますと幸いです」「大変恐縮ですが」「お手数をおかけしますが」「差し支えなければ」. Bad news pushed to the end of the paragraph.

Fix: state the conclusion first and briefly. Add emotion or confidence directly in one sentence. Write the measure as your own action with one sentence of reason.

Example:

- before: 「大変恐縮ですが、諸般の事情により、今回のご提案については一旦保留とさせていただければと存じます。ご理解いただけますと幸いです。」
- after: 「今回の件を受けまして、入金をいただくまでは保留とさせていただきたいと思います。」

### Requests chained on the other party's reply

Detect: a request whose condition depends on the recipient's answer, as in 「〜でしたら、〜をお願いできますでしょうか」, so the next request starts only after a reply. It costs one extra round trip.

Fix: ask everything you can ask now. Make the conditional request an independent paragraph and ask unconditionally; state the condition separately as information for the recipient.

Example:

- before: 「上記時間帯に実施いただいているようでしたらマーチャントパスワードが起因しているため、ソニーペイメント様にも合わせて調査依頼をお願いできますでしょうか。」
- after: 「「K03」エラーはマーチャントパスワードに起因するエラーですので、パスワードが正しく設定されていないことが想定されます。（中略）また、ソニーペイメント様にも合わせて調査依頼を出していただければ幸いです。」

### A cause that only restates the symptom

Detect: the vocabulary of the cause section is almost the same as the description of events, with no new fact. 「設定が適用されていないことが原因」 merely restates 「登録できてしまった」. 「要件を満たさない実装が根本原因」 is the definition of a bug and therefore circular.

Fix: ask for the timeline of when, who, not knowing what, did what. When the answer arrives, write it as a mechanism.

Example:

- before: 「管理画面での設定が会員画面の登録時に適用されていないことが原因でした。」
- after: 「当初の要件定義には分類制御が無く、その後追加でご要望をいただきました。管理画面の担当者は本仕様を考慮して開発しましたが、フロント画面の担当者が本要件を考慮せず開発したことが原因です。」

### Countermeasures made of generic words only

Detect: a recurrence-prevention or improvement plan consisting only of 「徹底」「こまめに」「共有」「意識」「強化」, without naming which step of the cause it closes.

Fix: name the step that corresponds one-to-one to the cause. If the step is unknown, ask.

Example:

- before: 「要件定義書のこまめな更新、社内での要件共有を徹底することで再発を防止できると考えております。」
- after: 「要件変更に対する要件定義書の迅速な更新、及び仕様変更が発生した場合の社内エンジニアへの周知を徹底します。」

## Tier 2 (strong Japanese-specific fingerprints)

One sighting may be fixed. Keep the form if the writer's voice sample uses it. In explanatory articles the writer may use label-plus-colon bullets themselves; treat it as Tier 3 there.

| Pattern | Detect | Fix |
|---|---|---|
| Label-plus-colon bullets | Items open with a bold label and a colon, 「**速度:** 処理速度が向上」 | If the label carries no information, drop it and keep the body. If it does, turn the item into a sentence |
| Forced triads | Three reasons, three points, three decisions, always three | Use the number the content needs. One or four is fine |
| することができます | 「変更することができます」 | 「変更できます」 |
| Summary section and expectation closers | A 「まとめ」 section that restates the body; endings in 「〜が期待されます」「今後の展開が注目されます」「〜と言えるでしょう」 | Delete the summary section; end on the last concrete fact |
| Template openers | 「近年、〜が注目されています」「本記事では〜を解説します」「〜をご存じでしょうか」 | Delete the opener and start with the point |
| Stock evaluative phrases | 「浮き彫りにしており」「重要な示唆を与えている」「注目に値する」「画期的な」「多面的な」「包括的な」 | Write concretely what was seen and why it drew attention |
| Empty adverbs | 「静かに」「確実に」「大きく」「本質的に」「シンプルに」「適切に」「柔軟に」「明確に」 | Delete. If something must remain, replace with a number or a condition |
| Over-explicit subjects | Every sentence opens with 「このツールは」「この記事では」「私は」 | Write the subject once when it repeats |
| Uniform endings and sentence length | 「です」「ます」「できます」 three or more in a row; every sentence 40 to 60 characters | Vary endings and mix lengths. With a voice sample, match its distribution |
| Mechanical connectives | 「まず」「次に」「最後に」「そのうえで」「あわせて」「なお」 placed in every paragraph | Keep only words that show a logical relation; delete those that only show order |
| Contrast as weighting | 「A ではなく B」「A だけでなく B」 where nobody claimed A | Keep only when it corrects a belief the reader actually holds; otherwise write B directly |
| Translation-flavored function words | 「〜において」「〜の観点から」「〜という側面から」 | Delete or rewrite as a concrete condition |
| Headings as sentences | A heading written as a sentence, 「同じ週に、Google と Anthropic も同じ方向へ動いた」 | Make it a noun phrase (「Google と Anthropic も同様の方針へ」) |

## Tier 3 (never fix alone)

Fix only when a Tier 1 or Tier 2 pattern shares the paragraph. People use these on purpose, and one alone is not evidence of AI.

| Pattern | Note |
|---|---|
| Bold | Allowed for a first definition and for a fact that changes the reader's decision. Judge by the label-plus-colon form, not by count |
| Bullet lists as such | Appropriate for procedures, options and checklists |
| Numbered headings | Sometimes used for easy reference |
| 「〜ですね」「〜かもしれない」 | Usually natural as conjecture or tone |
| Long sentences | Do not fix while subject and causation hold. Keep them if the writer's sample has long sentences |
| A single full-width dash | Fix when two or more appear, or when combined with other tells |
| A single 「これにより」 | Fix when it repeats |
| Uniform politeness | In mail it is set by the relationship. Follow the sample when there is one |

## When Not to Act

- Inside a quotation, a title, a proper noun, or a passage discussing the phrase itself, leave the pattern word alone.
- Keep any form found in the writer's voice sample. The sample overrides the rules for vocabulary, sentence endings and attitude toward the reader. The norms override the sample for sentence length and argument structure.
- When the improvement would be small, adjust only the wording. Do not break a sentence that is already natural to satisfy a rule.
- Do not touch code, paths, commands, frontmatter, link targets, or the inside of table cells.
- Do not add a fact, number, proper noun or citation that is not in the source. Ask instead.

## Question Types

When the skill finds a Tier 1 "thin sentence", "cause that restates the symptom" or "countermeasure of generic words", it returns the matching question from the five below. Questions are written in the caller's language.

| Missing | Question |
|---|---|
| What was done | "What did you actually check before reaching this conclusion?" |
| Which one | "What does 'the existing logic' cover, and since when has it been in use?" |
| Why it happens | "In one sentence, what is the mechanism that makes this happen?" |
| Who does it where | "Who performs this check, in which environment? Is there anything you are asking the other party to do?" |
| When it ends | "Is there an estimated number of days or a deadline? The recipient needs it to choose." |

If a question goes unanswered, delete the sentence or strip the evaluative words and keep only the facts. Never fill the gap by guessing.

## Source

The Tier 2 fingerprints draw on the classifications in blader/humanizer v3 (MIT), gonta223/humanizer-ja (MIT) and sahksas/human-writing-ja, minus the items that misfire in Japanese (em dashes, hyphens, quotation marks). Tier 1 was extracted from the writer's own editing records.

# Wording Choices Before Drafting

Read this catalog before writing or rewriting Japanese, together with the norms and patterns. Choose words from the supplied facts at the first draft; do not first invent a vague metaphor and then try to explain it. These are usage distinctions, not a banned-word list or evidence that a person or model authored a text. The examples below are synthetic teaching material, not approved voice samples.

## How to Choose

1. Identify the actor, action, object, condition and result that the material actually supplies. Use those words in the sentence; do not fill missing slots by guessing.
2. If a listed phrase hides a supplied fact, write the fact directly. A different vague phrase such as 「良い影響がある」 does not explain the change.
3. If the material is broad, preserve its breadth, uncertainty and meaningful emphasis. Do not turn 「不具合がある」 into a claim about data integrity, missing logs, notifications, a cause, a responsible team or a guaranteed failure. Keep a supplied unresolved state; ask separately only when its meaning prevents a correct sentence.
4. Keep literal uses, quotations, titles, names, identifiers, discussed phrases and established technical terms. The writer's approved voice still determines vocabulary and rhythm; a current explicit preference overrides an older sample. Neither a sample nor a word list supplies facts about the topic.
5. Judge the sentence again in its paragraph. Preserve negation, scope, timing, permission, obligation, confidence and who acts on whom. No new cause or consequence may be added to make a replacement sound convincing.

These limits apply to replacing a word or phrase. They do not forbid the writer's own reasoning in `argument` mode: an inference that follows from the supplied facts may be written as the writer's inference.

## Metaphors and Their Referents

The replacement column is conditional on the stated material. It is not a search-and-replace table.

| Candidate use | Material and a grounded sentence | Preserve | Do not infer |
|---|---|---|---|
| 「設定が壊れる」 | Material: after updating, the saved setting returns to its initial value. Write 「更新後、保存した設定値が初期値に戻ります。」 | 「落として時計が壊れた」; an exact quoted fault description | Data loss, corruption, a cause or permanence merely from 「壊れる」 |
| 「データが静かに壊れる」「黙って失敗する」 | Material says only that the change went unnoticed: retain that meaning with 「気づかないうちに」 and the known state. Say 「通知を出さずに」 only if notification behavior is supplied | A person quietly listening; 「静かな部屋」; the literal operation described by a named component | No logging, no error response or no notification from lack of awareness alone |
| 「対象外に倒す」「安全側に倒す」 | Material: an expired request is rejected. Write 「有効期限を過ぎた依頼は拒否します。」 | 「椅子を倒す」; a defined engineering term where its precise meaning is needed | The condition for rejection, or that the choice guarantees safety |
| 「この変更が地味に効く」 | Material: the change removes the need to re-enter an address. Write 「この変更で住所を入力し直す必要がなくなります。」 If the supplied text also conveys a modest personal impression, keep that impression without inventing its magnitude | 「薬が効く」「キャッシュが効く」 when the established meaning is clear | A performance gain, a percentage or an assurance that every user benefits |
| 「例外を握る」「情報を握る」 | Material: the function catches the exception and returns an empty list. Describe those two operations directly. For information, name the supplied possession, access or decision authority | 「ハンドルを握る」; an exact quotation | Catching, suppressing, storing and controlling access are not interchangeable |
| 「業務の解像度を上げる」 | Material: staff list who approves each application. Write 「申請ごとの承認担当者を一覧にします。」 | Image resolution; a defined measurement | Listing, understanding, deciding and making more detailed are not the same action |
| 「操作の手触りがよい」「使い心地がよい」 | Material: the author could save without changing screens. State that experience. If only a personal impression was supplied, retain it as an impression | A fabric's texture; a supported first-person impression in narrative mode | Objective speed, fewer steps, broad user satisfaction or a personal experience not supplied |

If 「壊れる」 is the only description supplied, use a broad alternative such as 「不具合が起きる」 only when it expresses the same state. Otherwise preserve the supplied description and ask what happens. Do not label an unknown failure as an integrity problem just to remove the word. When drafting from known facts, use the facts and omit the metaphor entirely.

## Names That Overstate the Role

Choose the name that describes the established role. A technical term is not wrong because it also appears in this table.

| Candidate use | Use when supported | Preserve |
|---|---|---|
| A routine instruction called 「契約」 | 「ルール」「手順」「取り決め」 according to what was actually agreed | A business contract, API contract, or defined formal contract |
| An ordinary list called 「台帳」 | 「一覧」「記録」, with its actual contents | An accounting or administrative ledger; an established product label |
| An ordinary check called 「ゲート」 | 「確認」「チェック」 and what is checked | A defined quality gate, logic gate or actual named gate |
| A source draft called 「正本」 | 「原文」「参照する資料」「比較の基準」 according to its actual role | A legally distinguished original; a formally designated authoritative copy |
| Vague 「閉包」「収斂」「回帰」 | Describe what ended, agreed or changed only when the material establishes it | Mathematical closure/convergence, a programming closure, statistical regression, and established domain terminology |

Do not add uniqueness or authority when changing 「正本」 to another phrase. If the material explicitly says a source is the sole authority, retain that restriction. Do not replace an actual formal name, even when a shorter generic word exists.

## Nominalization and Translated Terms

- Prefer a verb when a noun phrase adds no meaning: 「設定の変更を実施する」 can become 「設定を変更する」 if the same actor and action remain. Keep nominal forms needed by a specification or an established document label.
- Do not turn permission into ability: 「変更してよい」 is not 「変更できる」. A statement of possibility, a requirement and a completed action need different endings.
- Keep ordinary business verbs such as 「確認する」「保存する」「停止する」. Replacing 「確認する」 with 「見る」 can lose verification; 「結果の確かめ」 can be less natural than 「結果を確認する」. Do not force native-Japanese words or kanji compounds.
- Keep familiar katakana terms such as 「バージョン」「デフォルト」「チェック」. Do not change them to 「版」「既定」「点検」 just to sound formal. Keep established expressions such as 「修正版」「設備の点検」 and actual UI labels.
- When a literal translation refers to a known technical object, use its established name: a Git branch is 「ブランチ」 rather than a tree's 「枝」. Preserve a literal tree branch, an identifier named `branch`, and an actual label. Establish the referent before choosing terminology.
- 「シナジー」「包括的」「品質が向上する」 need the supported effect or scope. Numbers are not mandatory: removing a screen transition or a repeated entry explains a benefit without a measured percentage. Do not invent figures or list unstated effects to fill the sentence.

## Phrasing to Review in Context

- An opening 「もちろん、」 may answer a real question or affirm a condition. Keep that function. Remove an empty anticipatory concession, leaving the supported statement and adding no new reason.
- Short fragments such as 「資料を、全員へ。」 may suit a requested slide or slogan. In ordinary explanatory prose, write the supplied action and recipient; if no action is supplied, do not invent a delivery method.
- A heading such as 「判断の羅針盤」 needs the topic or decision described in the body. A heading with a colon is a review candidate, not a defect in a URL, title or required template.
- A parenthesis that only restates a phrase can be removed. Keep definitions, qualifications, translations needed by the reader and facts that occur only there.

## Preferences and Evidence

A project word list or a writer's current request expresses a local preference; it is not a claim that the word is universally unnatural. Treat allow entries as wording exceptions and flag entries as review candidates, never as permission to change facts or protected content. Do not silently save generated phrases as the writer's preferences.

Keep this catalog separate from `scripts/vocabulary.json`. That file records evidence for the density detector, including observed usage and sources. A useful editing example or preference can belong here without being added to the frequency-based list. Word occurrence alone cannot establish authorship.

## Sources and License

Usage distinctions adapted from [yomiyasu v3.4.1](https://github.com/nanaism/yomiyasu/tree/3979c750b5e1fe9892bd47bb354f0fb51d534ff2), specifically [slop-catalog.md](https://github.com/nanaism/yomiyasu/blob/3979c750b5e1fe9892bd47bb354f0fb51d534ff2/skills/yomiyasu/references/slop-catalog.md), [calques.md](https://github.com/nanaism/yomiyasu/blob/3979c750b5e1fe9892bd47bb354f0fb51d534ff2/skills/yomiyasu/references/calques.md) and [rephrase-test.md](https://github.com/nanaism/yomiyasu/blob/3979c750b5e1fe9892bd47bb354f0fb51d534ff2/skills/yomiyasu/references/rephrase-test.md). Examples and integration instructions here were written for ja-humanizer. The source's full license notice follows.

```text
MIT License

Copyright (c) 2026 nanaism

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

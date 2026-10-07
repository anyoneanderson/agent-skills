# Editorial Evaluation

Use this when changing or evaluating ja-humanizer. The checker is a pattern finder;
its PASS is not an editorial verdict. Evaluate meaning and the writer's voice as
well as script output. Keep these cases out of the voice sample being tested.

## Review cases

These are constructed evaluation inputs, not the writer's voice samples. Ask the
agent to check each passage in narrative mode. Keep the expected behavior hidden
from an independent evaluator until its response is recorded.

| Case | Input | Expected behavior |
|---|---|---|
| Unsupported conclusion after an example | 「この例では、申込書に必要な添付書類の名前を書き足しました。文章を書く仕事の正体は、事実を足すことだったのです。」 | Identify the leap from one edit to writing in general. Keep the concrete edit; remove or narrow the conclusion. A script PASS does not resolve it. |
| Abstract closing sentence | 「担当者が下書きの金額を見積書と照合します。この工程は、その境界を文章の作業に引くためのものです。」 | Keep the checking action. Remove the closing sentence, which does not explain what boundary or action it adds. |
| Natural repeated endings | 「私は申込書を確認します。次に、添付書類の名前を見ます。足りない書類があれば、申込者に連絡します。」 | Preserve the sequence. A uniform-endings finding alone does not justify a fragment, inversion or nominal ending. |
| Useful inference | 「書類名を追記した版では、確認の電話が5件から1件に減りました。この試行では、書類名の明記が確認の手間を減らした可能性があります。」 | Preserve the limited, uncertain inference. Do not remove every conclusion after an example or turn this into a universal causal claim. |
| Human-side words | 「とりあえず手元で動かしてみたら、思ったより簡単でした！設定ファイルは3行で済む。もっと早く試せばよかったと思う。」 | Leave it as it is. In narrative mode, 「とりあえず」, 「〜と思う」, exclamation marks and mixed styles are not deleted or unified. Do not add impressions that are not in the material. |
| Denial closer | 「キューは受け付けた依頼を順番に並べ、ワーカーが1件ずつ処理します。これは処理が速くなるという意味ではありません。」 (nothing in the text suggests the reader thinks it gets faster) | Write the place in the contextual-reading table as a contrast row with "denies a view nobody holds; cut", then delete the second sentence. Keep the first. |
| Section verdict | A draft in which three sections in a row end on 「〜を確認しておく必要がある。」 | Write three section-closer rows in the table, and do not merely rephrase the caution. When the material holds no verdict from the writer, ask "What is the conclusion you want the reader to take from this section?" and do not make one up. |
| A section ending only on reservations | For a write job, supply only 「検索画面はブラウザから操作できることを確認した。自動取得は試していない。利用の可否は調べていない。」 and ask for one section of an investigation report | Do not deliver denial closers such as 「動作確認済みとは扱いません」 or 「利用可否は確認していません」. The reason things were left unchecked and the verdict on what to do are not in the material, so do not make them up; ask for the reason and the verdict, naming the section. Keep the confirmed fact. |
| A reservation to keep | 「ログでは要求の直後に処理が止まっています。接続の失敗が原因のようです。」 | The cause is an inference that is not settled, so keep the reservation. Do not turn it into a settled fact such as 「接続の失敗が原因です」. |
| A reservation to remove | 「この定数には値 3 を代入しています。この定数の値は 3 のようです。」 | The value is settled by the material, so delete the redundant second sentence or drop the hedge. Do not keep it merely because its ending is a conjecture. |

Also try a write request with only these facts: an application requires a name and
email address. Ask for a short personal blog introduction but supply no personal
experience. The agent should explain the facts or ask for an experience only when
needed; it must not invent being criticized by a colleague or discovering a fix.

For sample selection, provide an article labeled partly edited by its writer and
ask for likely handwritten excerpts. The output should quote candidates and
explain uncertainty. It must not claim authorship is proven or install the
candidates as approved samples. Preserve a separately approved long passage
unchanged; length alone is not a defect.

## Comparing revisions or models

Use the same source material, audience, length guidance and approved excerpts for
each run. Record the exact model, effective instructions and skill revision. A
comparison of skill revisions keeps the model fixed; a comparison of models keeps
the skill fixed. Do not infer a model effect from changing both at once.

Use several topics not included in the voice samples. Hide model labels during the
writer's reading where practical. Record unsupported additions, lost meaning,
unwanted phrasing, over-editing and time to an acceptable draft separately from
script counts. Do not claim that one model has no writing habits or always writes
better from one sample. If no comparison was run, call a model switch a proposed
trial, not a measured improvement.

## Article Revision Case

The following passages are revision exercises, not approved voice examples.

Task: review the input below in narrative mode, preserve supported meaning, and do not invent facts. Run it without the confirmed excerpts above as voice references. For independent evaluation, provide only the task and input, then consult the criteria after recording the output.

```text
AI 臭を消す作業の実体は、言い回しの置き換えもですが、事実の追加という文章のコンテンツの補強をやる作業になります。

文体見本は語彙、語尾、文長、読み手への態度を決め、規範が勝つのは論証の構造や機構の無い原因のように、意味か論理が合わなくなる箇所だけにしています。
```

Evaluation criteria: narrow the first claim to what an editing example can support; describe missing information directly. In the second, explain which wording follows the sample and which contradictions or missing explanations need correction. Do not preserve these sentences merely because they were once labeled after-text. An exact target sentence or zero detector findings is not the acceptance criterion.

If a writer rejects a metaphor such as 「空振り」, record that preference for that writer and context. Do not infer that the word is absent from Japanese or always indicates a particular model. Contextual review can address an unclear metaphor without adding a blanket detector.

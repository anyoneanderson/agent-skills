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

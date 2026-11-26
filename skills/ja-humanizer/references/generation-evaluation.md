# Generation Evaluation

Use generation from the same material, not only rewrite pairs, to evaluate this skill. Keep the model, effective instructions, material, audience, length and voice samples fixed. Do not show expected verdicts in the generation prompt. Preserve output before assessing it; do not turn outputs into approved voice samples.

## Reusable cases

Use [the exact prompt](evaluation/generation-203/prompt.txt) for four independent deliverables: incident report, manual, slide and mail. The ambiguous restart statement is intentional. Check the following after generation:

| Case | Check |
|---|---|
| Incident | Describe the value reverting after update directly; retain uncertainty; do not invent missing logs, cause or guarantee. Ask about the ambiguous restart statement rather than choosing one meaning. |
| Manual | Retain three numbered steps, the administrator-only permission and the disabled button condition. Repeated polite endings are allowed. |
| Slide | Retain a short heading and three bullets, the pre-send correction condition and the unmeasured/undecided values. Do not invent time savings. |
| Mail | Retain greeting, closing, sender and recipient; request checking and reporting corrections. Do not invent an amount, deadline or attachment. Assess verbosity and added requests separately. |

Also try a writer-approved sample on a different topic in a separate run. Keep literal physical breakage, technical terms, quotations and source-supported nonnumeric benefits as negative controls. Check source-only broad failure descriptions without forcing a narrower cause. Record unwanted wording, unsupported additions, lost conditions, over-editing and human editing effort separately from lint counts. Only the writer can measure their own preference and editing time.

## Recorded trial, 2026-11-25

[Manifest](evaluation/generation-203/manifest.json) records file hashes of both tested snapshots and runtime details. The [base output](evaluation/generation-203/base.md) and [candidate output](evaluation/generation-203/candidate.md) are synthetic evaluation artifacts, not authored/approved voice examples. Both CLI runs completed successfully and invoked their snapshot's checker. Same GPT-6.2 Sol model and medium reasoning, one run per variant containing four cases, no voice samples or word preferences. Candidate is the recorded work-in-progress snapshot; later protected-span fixes and slides rhythm clarification were not rerun through generation, because these cases contain neither protected spans nor a voice target.

Agent review of the saved outputs found both variants preserved the key facts, permissions and formats and asked about the ambiguous restart statement. Neither introduced the targeted vague metaphors in these four cases. The candidate used consistent request endings in the manual; the baseline mixed request and explanatory endings. Both are understandable. The baseline mail added a request for preferred corrected wording; the candidate requested a reply to the email and used more formal thanks. These are observable wording differences, not measured quality gains.

No clear improvement in prose quality is established by this small trial. The writer has not rated the outputs or measured editing time. Voice preservation, automatic skill selection and repeated-run consistency are not tested by this explicit invocation with no voice sample. Deterministic checker tests separately establish detection/profile behavior; they do not prove better prose.

# Abstract Verb Vocabulary

This table is the primary source for English abstract-process candidates. A `Pattern` match selects text for inspection; it does not create a warning by itself. Suppress a warning when the same sentence, list item, paragraph, or adjacent sequence-diagram messages provide the `Required evidence`.

| ID | Pattern | Ambiguity | Required evidence | Bad example | Rewritten example |
|---|---|---|---|---|---|
| AV-001 | `map` | The term alone does not distinguish an in-memory transformation from persistence or event delivery. | Identify the actor, trigger or source input, exact transform, store, or send action, and every result destination. A defined mathematical mapping may instead state its input set, transformation rule, and output set. | Map the AI SDK step to `Run.steps` and the `agent-step` event. | When the AI SDK reports that a step started, the orchestrator stores the progress in `Run.steps` and sends the same progress to the client in an `agent-step` event. |
| AV-002 | `bind` | The term alone does not say whether values are associated, hashed, validated, or used for authorization. | Identify the actor, input or trigger, concrete association or calculation, and the field, record, message, or consumer that receives the result. | Bind the tenant and actor to `taskRequestDigest`. | When the orchestrator receives a task request, it includes the tenant and actor in the digest input, calculates the digest, and sends `taskRequestDigest` with the request to the execution queue. |
| AV-003 | `fail safe` | The term alone does not identify the failure, rejected operation, returned result, or recorded evidence. | Identify the actor, failure condition, reject, stop, or fallback action, and the caller, log, state, or response that receives the result. | If policy lookup fails, fail safe. | If the policy service times out, the authorization gateway rejects the request, returns a retryable error to the caller, and writes the reason to the audit log. |
| AV-004 | `converge` | The term alone does not define what is compared, the target state, the stored progress, or the stopping condition. | Identify the actor, iteration trigger, comparison or update action, target state, result destination, and stopping condition. | Converge the review findings. | After each reviewer response, the orchestrator compares open finding IDs with accepted fixes, writes unresolved IDs to `review-state.json`, and stops when none remain or three rounds finish. |

## Inspection Notes

- Do not warn only because a pattern appears.
- Accept evidence distributed across nearby prose or adjacent sequence-diagram messages when the relationship is unambiguous.
- Ignore a pattern that occurs only in a code block, log, configuration example, or identifier.
- Accept a mathematical use when the input, transformation rule, and output are defined.
- If a rewrite would require behavior that the specification does not establish, use named placeholders for the missing elements instead of inventing values.

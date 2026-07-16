# Abstract Process Description Check

Run this check as Check 18 after loading all specification files. Use `spec-writing/references/abstract-verbs.md` as the only source of abstract-process patterns; do not maintain a second pattern list in `spec-inspect`.

## Inputs

- `requirement.md`, `design.md`, and `tasks.md`.
- `test.md` when present.
- The English abstract-verb table selected from `spec-writing`.

## Candidate Selection

1. Scan prose, tables, list items, and Mermaid messages in each specification file.
2. Select a line when it matches a `Pattern` from the vocabulary table.
3. Exclude ordinary code blocks, logs, configuration examples, and identifiers that only happen to contain a pattern.
4. Keep Mermaid `sequenceDiagram` messages in scope. Treat an adjacent `Note` as context for the message.
5. A pattern match is only a candidate. Never create a finding from the match alone.

## Evidence Window

For each candidate, inspect the same line, the containing list item or paragraph, and the immediately preceding and following sentences. For a sequence diagram, inspect the candidate message and its adjacent messages or notes.

Collect the four process elements defined by `spec-writing`:

1. The actor that performs the process.
2. The trigger, state, event, or input that starts it.
3. The observable action, such as storing, comparing, calculating, sending, rejecting, or stopping.
4. The destination or consumer of the result.

Also apply the candidate row's `Required evidence`. Accept evidence split across the window when it identifies one process unambiguously. Accept a mathematical operation when its input, transformation rule, and output are defined.

## Warning Decision

Create a WARNING only when at least one process element is missing and an implementer cannot determine the concrete behavior unambiguously. Do not warn when nearby text supplies the evidence. Deduplicate findings by file and line even when the same sentence appears in both quoted and ordinary text.

## Finding Contract

Record each finding in the existing report format:

```text
ID: WARNING-{seq}
Title: Abstract process description: {pattern}
File: {filename}
Line: {line_number}
Description: "{quoted text}" does not identify {missing_elements}
Suggestion: {rewrite containing the actor, trigger or input, observable action, and destination}
Source rule: {AV-XXX}
```

List only absent elements in `missing_elements`. Preserve behavior established by the specifications. When a value cannot be determined, use a named placeholder in square brackets instead of inventing an actor, trigger, action, or destination.

## Vocabulary Errors

If `spec-writing`, the selected vocabulary file, a required column, or a stable ID cannot be read, do not embed or infer a replacement pattern list. Add one WARNING stating that the abstract-process check could not run, identify the missing or malformed source, and continue Checks 1 through 17.

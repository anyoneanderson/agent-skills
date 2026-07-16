---
name: spec-writing
description: |
  Write and revise requirements, designs, task plans, and test plans with
  concrete process descriptions, traceable reasoning, and audience-appropriate
  detail. Provides a stable abstract-verb vocabulary for specification checks.

  English triggers: "write a clear specification", "revise this design", "apply spec-writing"
  日本語トリガー: 「読みやすい仕様書を書く」「設計書を推敲」「spec-writingを適用」
license: MIT
---

# spec-writing — Concrete Specification Writing

Apply compact writing rules that let readers follow a process without guessing what the system does or where its output goes.

## Language Rules

1. Auto-detect the requested output language and write in that language.
2. For English output, read [writing-rules.md](references/writing-rules.md) and [abstract-verbs.md](references/abstract-verbs.md).
3. For Japanese output, read [writing-rules.ja.md](references/writing-rules.ja.md) and [abstract-verbs.ja.md](references/abstract-verbs.ja.md).
4. An explicit language override takes priority over automatic detection.
5. Load one language pair only. Do not combine language-specific rules across pairs.

## Scope

Use this skill to generate or revise requirements, designs, task plans, test plans, and related specification reports.

The skill provides two contracts:

- `writing-rules*` defines shared `SW-*` rules for process descriptions, audience separation, reasoning, and sequence diagrams.
- `abstract-verbs*` is the primary source for stable `AV-*` candidate patterns and the evidence required to make each use concrete.

## Execution Flow

### Step 1: Identify the document and audience

1. Determine whether the output is a requirement, design, task plan, test plan, or a revision of one.
2. Identify the readers of each section before drafting it.
3. Keep an overview understandable with general system names. Put types, functions, events, and storage identifiers in implementation-facing sections.

### Step 2: Load the writing contract

1. Read the writing rules and abstract-verb vocabulary selected by the Language Rules.
2. Treat `SW-*` and `AV-*` IDs as stable identifiers when explaining or reporting a rewrite.
3. Apply the rules before generating new text and before changing existing text.

### Step 3: Write observable processes

For every process description, make these elements traceable in the same sentence, list item, paragraph, or adjacent sequence-diagram messages:

1. The actor that performs the process.
2. The trigger, state, event, or input that starts it.
3. The observable action, such as storing, comparing, calculating, sending, rejecting, or stopping.
4. The destination or consumer of the result.

Do not force all four elements into one sentence when nearby text identifies them unambiguously. Do not invent an actor, trigger, action, or destination that the source requirements do not establish; use a visible placeholder or record the unresolved decision instead.

### Step 4: Apply audience and reasoning rules

1. Apply every common `SW-*` rule in the selected writing reference.
2. Apply language-specific rules from that reference when present.
3. State the mechanism behind a causal claim.
4. Remove unsupported certainty, hedging, intensifiers, previews, summaries, and generic praise that add no requirement or design information.
5. In a sequence diagram, name the data in each message and show the receiver's next observable action in an adjacent message or note.

### Step 5: Self-check before delivery

1. Search the draft for every `Pattern` in the selected abstract-verb table.
2. For each match, inspect nearby text for all four process elements and the row's `Required evidence`.
3. Keep the term when the surrounding text makes the operation unambiguous, including a defined mathematical operation.
4. Rewrite an underspecified use with concrete actions and destinations.
5. Confirm that overview sections remain readable without implementation identifiers and that implementation-facing sections retain identifiers needed to build the system.
6. Confirm that every sequence-diagram message names its payload and the receiver's subsequent action.

## Error Handling

| Situation | Action |
|---|---|
| A selected reference file is missing | Name the missing file and stop before generating or revising the specification. |
| An abstract-verb table has missing columns or duplicate IDs | Apply the available writing rules, report that the vocabulary self-check could not run, and do not infer replacement rows. |
| The source does not determine one of the four process elements | Preserve the uncertainty with a named placeholder or unresolved decision; do not fabricate behavior. |
| The term describes a defined mathematical operation | Keep the term when its input, transformation rule, and output are explicit. |

## Attribution

This skill distills specification-focused rules from `k16shikano/japanese-tech-writing`, published at https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d under the Unlicense. This skill's repository license remains MIT.

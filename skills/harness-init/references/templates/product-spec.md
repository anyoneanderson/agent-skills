<!--
  product-spec.md — Harness Engineering Product Specification Template

  This file is the SINGLE human-in-the-loop artifact for the /harness series.
  The Planner agent reads this file (plus any hints from the human during
  /harness-plan) and derives the roadmap, sprint contracts, and per-sprint
  acceptance rubrics from it.

  RULES:
    1. Describe WHAT to build and WHY — never HOW.
    2. No technology names, library picks, data-model shapes, or file paths.
    3. If you catch yourself writing "use React" or "store in Postgres",
       move that item to Constraints (only if it is a hard external mandate)
       or delete it.
    4. Keep each section short. Ambiguity here propagates into every sprint.
    5. Remove this comment block before committing.
-->

# Product Spec: <epic-name>

## Why

<!--
  The problem, pain, or opportunity. 1–3 sentences.
  Answer: "If we do nothing, what stays broken?"
-->

-

## What

<!--
  The user-observable outcome. Describe behavior, not implementation.
  Bullet the capabilities a user / external system will gain.
  Resist the urge to list screens or endpoints — describe value.
-->

-

## Out of Scope

<!--
  Things that look related but are explicitly NOT part of this epic.
  Protect the Planner from drifting into adjacent features.
-->

-

## Constraints

<!--
  Non-negotiable external requirements: compliance, deadlines, integrations
  we cannot avoid, or technology we must use (only if truly mandated).
  If a constraint is just a preference, it does not belong here.
-->

-

## Success Signals (optional)

<!--
  How will we know the epic is delivered?
  Prefer outcome metrics ("users can sign up in under 30 seconds") over
  output metrics ("3 PRs merged"). These feed into per-sprint rubrics.
-->

-

# Pipeline Config Template — .specs/pipeline.yml

This file defines the default `.specs/pipeline.yml` that spec-workflow-init
writes, and the rules for writing it. `pipeline.yml` is the role-assignment and
app-launch config that spec-orchestrate reads; its full schema lives in
spec-orchestrate `references/pipeline-config.md`.

日本語版: [pipeline-yml-template.ja.md](pipeline-yml-template.ja.md)

## Generation Rules

1. If `.specs/pipeline.yml` already exists, **do not overwrite it**. Report the
   existing path and move on (same idempotency rule as the workflow file).
2. If the `.specs/` directory does not exist, create it first.
3. Write the template below verbatim. It is complete on its own — no dialogue or
   project-specific questions are needed. A project tunes it by editing the file.

## Template

Write exactly this content to `.specs/pipeline.yml`:

```yaml
# .specs/pipeline.yml — spec-orchestrate role assignments and app launch recipe.
# Unlike run records, this is a config file you SHOULD commit (it is not matched
# by the run-record patterns in .specs/.gitignore). Reassign work by editing the
# role values below — e.g. set every role to `claude` for a light-touch run.

roles:
  spec_author: claude       # writes requirement / design / tasks / test.md
  spec_reviewer: codex      # adversarial review of the generated spec
  impl_ui: claude           # builds user-facing screens and components
  impl_backend: codex       # builds APIs, business logic, data access
  impl_test: codex          # writes test code and fixtures
  e2e_runner: claude        # runs the acceptance test plan (spec-evaluate)

# app: launch recipe for acceptance tests. Required ONLY when test.md has a
# playwright case. Uncomment and fill in when you need it.
# app:
#   start: "npm run dev"          # command that starts the app
#   url: "http://localhost:3000"  # base URL the evaluator drives
#   ready_pattern: "ready in"     # log line that means the app is up
#   stop: "auto"                  # auto = kill the launched process; else a stop command
#   auth: none                    # none, or a references path describing the auth steps

limits:
  role_swap_max: 1          # max arbitration owner-swaps before landing a draft

# improve: retrospective auto-improvement. Enable when you want the pipeline to
# apply its own learnings; leave it unset and improvements degrade to filing an
# Issue instead.
# improve:
#   skills_repo: "~/path/to/agent-skills"
#   auto_apply: true
#   line_budget: 300
```

## Values Explained

- **roles** — each value is `claude` or `codex`. The six keys cover spec
  authoring, spec review, the three implementation kinds (`ui` / `backend` /
  `test`), and the end-to-end acceptance runner. Editing a value reassigns that
  work; no other change is needed.
- **app** — the launch recipe spec-evaluate uses to drive `playwright` cases.
  Shipped fully commented because most projects have no UI cases at first;
  spec-orchestrate treats an absent `app` as "no launch recipe".
- **limits.role_swap_max** — the arbitration owner-swap cap (default 1).
- **improve** — the retrospective self-improvement block. Shipped commented;
  when unset, retrospective improvements degrade to filing an Issue.

## awk-Read Compatibility

spec-orchestrate reads a role without a YAML parser, using an awk idiom that
keys off the flat `roles:` block (see `pipeline-config.md`):

```bash
awk '/^roles:/{f=1;next} f&&/^[a-z]/{exit} f&&/spec_reviewer:/{print $2}' "$pipeline"
```

The template stays compatible with it:

- Role lines are indented and carry the value as the second whitespace field, so
  `print $2` returns the value even with a trailing `#` comment.
- Per-key notes are **trailing** comments on the same line, never comment lines
  that repeat a `role_key:` token (which the pattern would match by mistake).
- The block ends at the next unindented key. `app:` is commented out, so the awk
  reads on to the unindented `limits:` and exits there — after all six roles are
  read.

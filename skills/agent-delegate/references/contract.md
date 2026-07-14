# agent-delegate — Script Contract

This document is the public interface for `references/scripts/agent-delegate.sh`.
Other skills and automation depend on this contract and call the script
directly, without going through `SKILL.md`. The script's current implementation
is authoritative; this document tracks it. Any change to the arguments or the
`report.json` schema is a contract change and must be reflected here.

日本語版: [contract.ja.md](contract.ja.md)

## Invocation

```bash
agent-delegate.sh --mode <delegate|review> --prompt-file <path> --out-dir <path> [options]
```

The prompt is passed on **stdin** (read from `--prompt-file`), never as a
command-line argument, to avoid escaping and length limits.

### Arguments

| Flag | Required | Default | Meaning |
|---|---|---|---|
| `--mode <delegate\|review>` | yes | — | `delegate` hands a task to the peer; `review` runs an adversarial read-only review |
| `--prompt-file <path>` | yes | — | File whose contents are fed to the peer on stdin |
| `--out-dir <path>` | yes | — | Directory for all artifacts (report, logs, review file) |
| `--label <slug>` | no | `<mode>-<epoch>` | Prefix for every artifact filename |
| `--target <codex\|claude>` | no | auto-detected | Which peer CLI to drive (see Target Resolution) |
| `--resume <thread_id>` | no | — | Continue a prior session (see Resume) |
| `--model <name>` | no | CLI default | Model passed to the peer (ignored on codex resume) |
| `--effort <level>` | no | — | Reasoning effort; codex only, ignored on codex resume |
| `--sandbox <stage>` | no | `full-access` | `full-access` / `workspace-write` / `read-only`; ignored in review mode (always read-only) |
| `--review-output <path>` | no | `<out-dir>/<label>-review.md` | Where the generated review file is written (review mode) |
| `--detach` | no | off | Run detached and return immediately (see Detach) |
| `--force` | no | off | Overwrite an existing pid/report for the same label |
| `-h`, `--help` | — | — | Print usage to stdout and exit 0 |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | The script ran to a terminal state. Read `status` from `report.json` to learn whether the run succeeded (`done`) or failed (`blocked`). |
| `2` | Precondition error before or instead of running the peer: bad arguments, unresolvable target, peer CLI missing, codex workspace untrusted, resume validation failure. No `report.json` is written for exit 2. |

### stdout contract

The **last line of stdout** is the absolute path of `report.json`. Callers only
need that line; everything else on stdout/stderr is diagnostic. In `--detach`
mode the same path is printed immediately, before the file exists.

## Target resolution

The script drives the *other* agent's CLI. It decides which one in this order:

1. `--target <codex|claude>` if given.
2. `AGENT_DELEGATE_HOST` env (`claude` → target codex, `codex` → target claude).
3. `CLAUDECODE` env set → running under Claude Code → target **codex**.
4. A Codex runtime marker (`CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED`, or `CODEX_HOME`) → target **claude**.
5. Otherwise: exit 2 asking for `--target`.

The resolved direction (`claude->codex` or `codex->claude`) is recorded in
`report.json` under `meta.direction`.

**Nested-chain caveat.** In an agent chain (e.g. Claude Code → `codex exec` →
this script), the parent's `CLAUDECODE` / `CODEX_*` variables are inherited by
the child shell, so env-based self-detection is unreliable. **Programmatic
callers (other skills, pipelines) must always pass `--target` explicitly.**
Self-detection is a convenience for single-agent interactive use only.

Measured runtime markers (2026-07-03, codex-cli 0.142.5): a Codex exec shell has
`CODEX_SANDBOX` (e.g. `seatbelt`), `CODEX_SANDBOX_NETWORK_DISABLED=1`, and
`CODEX_THREAD_ID` injected into its environment.

## Sandbox stages

Priority: `--sandbox` flag > `AGENT_DELEGATE_SANDBOX` env > default `full-access`.
Review mode ignores all of this and is always `read-only`.

| Stage | codex exec | claude -p |
|---|---|---|
| `full-access` | `--sandbox danger-full-access` | `--permission-mode bypassPermissions` |
| `workspace-write` | `--sandbox workspace-write` | `--permission-mode acceptEdits` |
| `read-only` | `--sandbox read-only` | `--permission-mode plan` + `--disallowedTools Write,Edit,NotebookEdit,Bash` |

**Guarantee levels differ by direction.** For the codex direction, `read-only`
is a kernel-level filesystem sandbox. For the claude direction, `plan` is a
policy-level control and the disallowed tools are an application-level block —
there is no OS-enforced write barrier. Treat codex `read-only` as a hard
guarantee and claude `read-only` as best-effort policy.

## report.json schema

Written atomically (to a `.tmp`, then `mv`). Its existence — on success **and**
failure — is the sole completion signal.

```json
{
  "status": "done | blocked",
  "summary": "first non-empty line of the peer's final message (<=200 chars)",
  "touchedFiles": ["path/relative/to/repo/root.ts"],
  "blocker": null,
  "blocker_category": null,
  "thread_id": "abc-123 | unknown",
  "artifacts": {
    "last_message": "<out-dir>/<label>-last.txt",
    "stdout": "<out-dir>/<label>-stdout.jsonl | .json",
    "stderr": "<out-dir>/<label>-stderr.log",
    "review_file": "<out-dir>/<label>-review.md"
  },
  "meta": {
    "run_id": "uuid or nanosecond timestamp",
    "mode": "delegate | review",
    "direction": "claude->codex | codex->claude",
    "sandbox": "full-access | workspace-write | read-only",
    "model": "gpt-5.4 | null",
    "resumed": false,
    "ts": "2026-07-03T00:00:00Z"
  }
}
```

- `touchedFiles` is measured by the script from git snapshots
  (`git ls-files --full-name -m -o --exclude-standard` before/after, relative to
  the repository root), never from the peer's self-report. The script's own
  artifacts under `--out-dir` are excluded. Outside a git repository it is empty
  and a warning is emitted (status still `done` for delegate).
- `blocker` is the last 20 lines of the peer's stderr on failure, else `null`.
- `artifacts.review_file` is present only in review mode.

### blocker_category

Machine classification of a failure (`null` on success). The orchestrator may
re-classify from the `blocker` text.

| Category | Meaning |
|---|---|
| `malformed_output` | Review output failed the 4-point structural check (see Review mode) |
| `tool_unavailable` | Peer CLI missing / not installed (stderr matched) |
| `timeout` | Peer timed out (stderr matched, or exit code 124/137) |
| `sandbox_violation` | A `read-only` review modified files after excluding our own artifacts |
| `env_error` | The run exited without producing a report; synthesized by the synchronous/worker safety net or the detach monitor |
| `unclassified` | Non-zero exit with no matching pattern |

## Review mode

- Always `read-only`. The reviewer cannot write files, so it emits the full
  structured review file (format verified below) as its **final message**, and
  the script persists that message to `--review-output`.
- The prompt sent to the peer is `adversarial-review-prompt.md` (or `.ja.md`
  when `AGENT_DELEGATE_REVIEW_LANG=ja`) followed by the caller's `--prompt-file`
  (the review context: diff, spec paths, perspectives).
- The final message is verified for four structural points. Any missing point →
  `status: blocked`, `blocker_category: malformed_output`, with the missing
  points listed in `blocker`:
  1. a `type: review` header line,
  2. a `## Meta` section,
  3. a `## Findings` section with `### Critical`, `### Improvement`, and `### Minor`,
  4. a `## Summary` section with a `Gate: PASS|FAIL` line.
- If the read-only run still modified files (after excluding our artifacts):
  `status: blocked`, `blocker_category: sandbox_violation`.
- The review file format (severity sections + per-finding `fix_before` tags +
  gate) is stable and machine-parsable; downstream tooling can consume it
  as-is. The Gate is derived from `fix_before` alone — FAIL iff at least one
  finding is tagged `fix_before: implementation`
  (see `adversarial-review-prompt.md`).
- The structural check verifies **presence** only; it does not validate
  `fix_before` values or that the `Gate` line matches the findings. Consumers
  MUST first verify every Critical / Improvement finding carries a `fix_before`
  value from the stage list in effect — the four defaults, or the ordered list
  the caller supplied in the review context (a missing or out-of-list tag is
  malformed output — never compute a gate from it) — then recompute the Gate
  from the tags (FAIL iff any finding carries the first, gate-blocking stage)
  and fail closed on a mismatch.

## Resume

`--resume <thread_id>` continues a prior session.

- `thread_id` source: codex = the `thread.started` event's `.thread_id` only
  (later events carry `item_*` ids and are ignored); claude = `.session_id` from
  the result JSON. On failure to capture, `thread_id` is `"unknown"`.
- `--resume unknown` → exit 2.
- codex resume uses `codex exec resume <id> --json --output-last-message <file>`
  only. It does **not** accept `--sandbox`, `--model`, or `-c` (reasoning
  effort); the sandbox/model are fixed at session creation. `--effort` on a
  codex resume is ignored with a warning.
- The script compares the requested sandbox against `meta.sandbox` of the prior
  report at `<out-dir>/<label>-report.json`. A mismatch → exit 2 (start a new
  session to change permissions). A review resume additionally requires the
  prior session to have been `read-only`.

## Detach

`--detach` runs the peer under an OS-detached supervisor so the caller is not
bound by the ~10-minute Bash-tool ceiling.

- Preconditions (arguments, peer CLI presence, codex trust) are checked
  synchronously; failures still exit 2 before detaching.
- On success the script launches a monitor wrapper via `nohup ... & disown`,
  writes a pid file `<out-dir>/<label>.pid` (pid, run_id, start time, command
  summary), prints the future `report.json` path, and exits 0 immediately.
- The monitor writes `report.json` atomically when the peer finishes. If the
  peer is killed and never writes one, the monitor synthesizes a `blocked`
  report (`blocker_category: env_error`) itself, so callers never re-implement
  the schema.

### Polling (recommended for callers)

Wait only for `report.json` to appear; do not parse the pid file or logs.

```bash
report="$(agent-delegate.sh --mode delegate ... --detach | tail -1)"
until [ -f "$report" ]; do sleep 15; done
status="$(jq -r .status "$report")"
```

### Sync vs detach

- Short tasks (review, investigation) → synchronous (no `--detach`).
- Long tasks (code implementation, E2E) that may exceed ~10 minutes → `--detach`.
- A Claude Code caller may instead wrap the synchronous form in its own
  background-execution feature.

## Environment variables

| Variable | Effect |
|---|---|
| `AGENT_DELEGATE_SANDBOX` | Default sandbox stage when `--sandbox` is omitted |
| `AGENT_DELEGATE_HOST` | Force host side (`claude`/`codex`) for target resolution |
| `AGENT_DELEGATE_REVIEW_LANG` | `ja` selects the Japanese review template |
| `AGENT_DELEGATE_TEST_MODE` | `1` = resolve arguments, print the plan line, and exit 0 without launching any CLI (for CI) |

## Error messages

All errors are printed to stderr, prefixed `agent-delegate:`. Representative
precondition errors (all exit 2):

- `missing --mode` / `missing --prompt-file` / `missing --out-dir`
- `invalid --mode '<x>' (expected delegate|review)`
- `invalid --target '<x>' (expected codex|claude)`
- `cannot self-detect host CLI; pass --target <codex|claude> (or set AGENT_DELEGATE_HOST)`
- `prompt file not found: <path>`
- `codex CLI not found; install Codex CLI and ensure 'codex' is on PATH`
- `codex workspace trust_level must be 'trusted' (workspace=<dir>, found=<level>)`
- `cannot resume: thread_id is 'unknown' ...`
- `resume sandbox mismatch: session was created with '<a>' but '<b>' was requested; ...`
- `review resume requires a read-only session; prior session sandbox was '<x>'`
- `a run for label '<label>' is already tracked at <pid> (use --force to override)`
- `a report already exists for label '<label>' at <path> (use --force to overwrite or --resume to continue)`

Warnings (non-fatal, stderr) include running outside a git repo, `--effort`
ignored on codex resume, and a read-only review that touched files.

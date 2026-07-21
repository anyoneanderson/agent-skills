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

Every successful launch prints the resolved run id before the report path:

```text
run_id: 19235118-80D0-4DCD-94E0-2E38C42AB5F2
/absolute/out/label-report.json
```

The **last line of stdout remains the absolute path of `report.json`**. Existing
callers that use only the last line remain compatible. Detached callers must
also save the `run_id:` value as the expected run and record the local time at
which the launcher returns. The report path can refer to a file that does not
exist yet.

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

Written atomically (to a `.tmp`, then `mv`). A valid terminal report for the
expected run is the authoritative completion result, except that an eligible
`blocked` / `env_error` report can retain diagnostic authority while the caller
adopts a task result through Artifact recovery below. During a detached run,
the absence of `report.json` is not a failure signal; use the heartbeat and
process state described below while waiting.

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

### Artifact recovery after `env_error`

A valid terminal report for the expected run remains the authoritative runtime
diagnostic. A `blocked` report with `blocker_category: env_error` means the
runner could not publish its normal completion result; it does not prove that a
task artifact already written by that run is invalid. The caller must attempt
artifact recovery before converting this one category to task failure. Monitor,
pid, and heartbeat state are auxiliary during that decision and cannot veto an
artifact that passes the checks below.

Recovery is fail-closed and is available only when all of these conditions hold:

1. **Eligibility.** The report is valid, `meta.run_id` matches the launcher's
   expected run id, `status` is `blocked`, and `blocker_category` is exactly
   `env_error`. Every other blocked category remains blocked.
2. **Predeclared provenance.** Before launch, the caller records the exact
   artifact path, its expected schema or validator, a correlation value, and
   whether the path existed (or its content fingerprint). The recovered file
   must be the path declared by `artifacts.review_file` or that pre-launch task
   contract, must be new or changed since launch, and must contain the expected
   label, correlation value, or equivalent run-specific evidence. A pre-existing,
   foreign, or wrong-run file is rejected.
3. **Mode-specific validation.** A review artifact must pass the four structural
   checks from review mode, every Critical and Improvement finding must carry a
   valid `fix_before`, and the caller must recompute Gate. The caller must also
   compare its pre-launch and post-run git snapshots, excluding the declared
   out-dir, to prove the read-only run did not modify the workspace. This
   snapshot is a content-level fingerprint of tracked worktree and staged diffs,
   plus every non-ignored untracked path and its content; a path or status list
   is insufficient because it cannot detect a second edit to an already-dirty
   file. An `env_error` report's synthesized empty `touchedFiles` is not that proof. A
   delegate artifact must pass the task-specific validator and completion
   criteria registered before launch. File existence, `last_message`, stdout,
   or `touchedFiles` alone is never sufficient.
4. **Recorded adoption.** The caller records the recovered artifact path,
   correlation evidence, validator result, and, for review, the recomputed Gate.
   It may then continue from the recovered task result while retaining the
   original blocked report as a runtime diagnostic. It does not rewrite the
   report to `done`. If any check fails, the result remains blocked.

The durable waiter checks a declared artifact before surfacing an eligible
`env_error` as failure. On hosts that reap detached monitors, a caller may use a
synchronous bounded `until` loop that applies the same artifact validator. The
loop is only a waiting mechanism: adoption still requires conditions 1 through
4, including a valid expected-run `env_error` report. If no such report appears
by the deadline measured from the original `launched_at`, the caller rejects recovery and
escalates with diagnostics. Monitor disappearance or the absence of an idle
notification alone is not a failure and does not reset the deadline.

## Detached runtime records

Detached runs publish local runtime records next to the report. These records
are diagnostic and ownership data; they do not add fields to `report.json`.

### Heartbeat

The monitor atomically replaces `<out-dir>/<label>-heartbeat.json` every 30
seconds while the worker runs. A heartbeat is fresh when its `last_beat` is no
more than 90 seconds old.

```json
{
  "run_id": "19235118-80D0-4DCD-94E0-2E38C42AB5F2",
  "state": "running | done | blocked",
  "pid": 303,
  "monitor_pid": 202,
  "started_at": "2026-07-14T00:00:00Z",
  "last_beat": "2026-07-14T00:00:30Z",
  "target": "codex | claude",
  "mode": "delegate | review",
  "report_path": "/absolute/out/label-report.json"
}
```

`pid` is the Bash worker PID. `monitor_pid` is the detached monitor PID and
matches the leading `pid:` in `<out-dir>/<label>.pid`. `started_at` and
`last_beat` are UTC RFC 3339 values. The monitor publishes `done` or `blocked`
only after it has published a valid terminal report with the same run id, then
stops updating the heartbeat. A terminal heartbeat is retained until the next
run with the same label takes ownership.

### Owner and handoff

`<out-dir>/<label>-owner.json` is the ownership token for the shared report,
heartbeat, and pid paths. `<out-dir>/<label>-owner.lock/` serializes ownership
changes and lease updates:

```json
{
  "run_id": "19235118-80D0-4DCD-94E0-2E38C42AB5F2",
  "run_kind": "detach",
  "runner_pid": 202,
  "launcher_pid": 101,
  "monitor_pid": 202,
  "worker_pid": 303,
  "started_at": "2026-07-14T00:00:00Z",
  "lease_at": "2026-07-14T00:00:30Z",
  "handoff_dir": "/tmp/agent-delegate-handoff.101.random",
  "handoff_phase": "verified"
}
```

`run_kind` is `sync` or `detach`; the PID and handoff fields are nullable where
the corresponding process or handoff does not exist. `handoff_phase` is one of
`not_applicable`, `not_started`, `committed`, or `verified`. For detached runs,
the owner value is a diagnostic mirror: the durable `handoff_phase` in
`<handoff_dir>/handoff-sentinel.json` decides whether the worker may start.
The monitor publishes the complete owner and pid before creating the handoff
FIFOs. Each heartbeat publication updates `lease_at` under the same owner lock.
The launcher accepts the owner's `run_id` as the expected run only after owner
and pid contain that same run id and monitor PID. It prints that value; callers
must not derive the expected run from the sentinel.

On the next launch for the same label, the preflight stale reaper examines a
valid owner whose lease is more than 90 seconds old. A synchronous owner is
removed only when it has the required null monitor and handoff fields, its
runner, launcher, and worker PIDs are identical, no pid path exists, and the
runner process is absent.

A detached owner requires an absent monitor and, when the pid path exists, a
matching run id and monitor PID. If the handoff directory is already absent,
the reaper validates that the stored absolute path is directly below the
configured root and that its basename contains the expected launcher PID before
removing the owner and optional pid record. An existing handoff must be a
non-symlink mode-0700 directory owned by the current user with an unchanged
device/inode. When a sentinel exists, its JSON identity must also match. Only
enumerated FIFOs, matching temporary files, and the sentinel may be removed;
unknown or mismatched content is retained and diagnosed rather than removed.

During a `--force` takeover of a stale detached owner, the reaper stops the old
monitor process group before removing its owner record. It signals the group
only when the stored monitor PID differs from the current process group and the
group still contains an `agent-delegate`, `codex`, or `claude` process. The
reaper sends `TERM`, waits up to one second, then sends `KILL` if the group still
exists. The terminal report and terminal heartbeat are retained.

If the stale reaper cannot acquire the owner lock within its timeout, the new
launch exits 2 before starting a peer and does not write `report.json`.

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
  finding carries the gate-blocking stage: the first stage of the list in
  effect, which is `implementation` with the default list
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
bound by the host command's execution limit.

- Preconditions (arguments, peer CLI presence, codex trust) are checked
  synchronously; failures still exit 2 before detaching.
- On success the script launches a monitor in an isolated process group. The
  monitor publishes owner and pid records, completes the durable handoff, and
  only then may start one worker. The launcher prints the run id and future
  report path and exits 0.
- The monitor writes `report.json` atomically when the peer finishes. If the
  peer is killed and never writes one, the monitor synthesizes a `blocked`
  report (`blocker_category: env_error`) itself, so callers never re-implement
  the schema.
- If the monitor receives `TERM`, `INT`, or `HUP`, or exits unexpectedly, it
  stops the worker process group before finalization. It promotes an unpublished
  review candidate to `done` only when the candidate belongs to the expected
  run, is a blocker-free `review` result with empty `touchedFiles`, declares the
  expected artifact paths, contains a structurally valid review, and that review
  is byte-identical to the same run's final message. Missing, malformed, stale,
  wrong-run, delegate-mode, or otherwise unverified candidates are discarded and
  replaced with `blocked` / `env_error`.

### Polling and expected-run state

Save `expected_run_id`, `report_path`, and `launched_at` from the detached
launch. Poll every 15 seconds by default and never less often than every 30
seconds. At each poll, inspect the expected run in this order:

1. Read the report. Finish only for valid JSON whose `status` is `done` or
   `blocked` and whose `meta.run_id` equals `expected_run_id`.
2. Read owner and pid. If the owner has moved to another run, return
   `SUPERSEDED`. Before the first heartbeat, use a non-null `worker_pid` from
   the expected-run owner as the worker identity.
3. Read the heartbeat. Keep the last valid heartbeat if a replacement is
   temporarily unreadable.
4. Probe the worker and monitor PIDs. After a valid heartbeat, its worker PID
   must agree with the expected-run owner. A permission error is unknown, not
   absent.
5. For `DEATH_CANDIDATE`, wait 30 seconds and begin the next poll by checking
   the report again.

| Observation | Caller state |
|---|---|
| expected-run report is valid `done` / `blocked` | `TERMINAL_DONE` / `TERMINAL_BLOCKED` |
| owner belongs to another run | `SUPERSEDED` |
| monitor absent, expected-run worker PID published and worker alive or unknown | `ORPHANED_WORKER` |
| worker absent, monitor alive or unknown | `FINALIZING` |
| monitor absent and worker absent, or monitor absent before any worker PID was published | `DEATH_CANDIDATE`; after 30 seconds, `DEAD` |
| report exists but JSON, status, or run id is invalid while processes remain | `REPORT_INVALID_PENDING` |
| heartbeat not generated, worker PID either unpublished or published with worker alive or unknown, monitor alive or unknown, launch age at most 90 seconds | `STARTING` |
| heartbeat not generated after 90 seconds, worker PID either unpublished or published with worker alive or unknown, monitor alive or unknown | `DEGRADED_NO_HEARTBEAT` |
| heartbeat temporarily unreadable, processes alive or unknown | `DEGRADED_UNREADABLE` |
| fresh heartbeat, processes alive or unknown | `RUNNING` |
| heartbeat older than 90 seconds, processes alive or unknown | `DEGRADED_STALE` |

State selection uses this priority: valid terminal report, owner moved to
another run, worker/monitor disappearance combination, invalid report, then
heartbeat generation and freshness. Thus an invalid report with both processes
absent enters `DEATH_CANDIDATE` and becomes `DEAD` after 30 seconds; it does not
remain `REPORT_INVALID_PENDING`.

Terminal report validation has priority over every heartbeat and PID state.
A terminal heartbeat never substitutes for an invalid or missing report.
`RUNNING`, every `DEGRADED_*` state, `ORPHANED_WORKER`, `FINALIZING`, and
`REPORT_INVALID_PENDING` are waiting states, not failures.

If the monitor disappears before the first heartbeat, the caller probes the
expected-run owner's `worker_pid` when that field is non-null. If no worker PID
was published, the caller records `worker_pid_unpublished` and treats the worker
as absent for this state selection because it has no expected-run process
identity that it can safely probe. A published PID whose probe returns a
permission error remains unknown and therefore never proves death.

### Detached wait budget and controlled stop

Measure the detached wait from `launched_at`; a fresh heartbeat does not reset
this elapsed runtime. At 30 minutes, and again at 60 and 90 minutes, the caller
re-reads the report, owner, pid, heartbeat, and process state and records the
observed state. A valid waiting state continues after each re-evaluation.

At 2 hours, the caller performs one final report-first state evaluation:

1. Return a newly observed terminal, `SUPERSEDED`, or `DEAD` state without
   sending a signal.
2. If the expected-run owner still matches and its monitor is alive, send
   `TERM` to that monitor. The monitor terminates the worker and peer, publishes
   an expected-run terminal report and terminal heartbeat, and removes runtime
   owner records. A fully completed review may be published as `done` only under
   the fail-closed candidate checks above; every other interrupted run is
   published as `blocked` / `env_error`.
3. Continue report-first polling for up to 90 seconds. Accept a valid terminal
   report if it appears.
4. If the monitor is absent or unknown at the 2-hour limit, or no terminal
   report appears during the 90-second grace period, stop the caller's wait and
   escalate to a human with the run id, last owner, pid, heartbeat, process
   probes, and report-validation error.

The 2-hour value limits peer work; controlled termination may extend caller
wall time to 2 hours plus 90 seconds. The caller never invokes `--force` or
signals an unidentified process as part of this timeout path.

### Sync vs detach

- A delegate that writes files, generates or repairs specifications, implements
  code, or records test evidence uses explicit `--detach` by default.
- Synchronous execution is limited to a review, investigation, or short
  delegate that is read-only and has a concrete basis for completing within
  5 minutes.
- If a task writes anything or lacks that time basis, use `--detach`.
- Every detached caller uses the 30-minute re-evaluation and 2-hour controlled
  stop above, including specification work, review, implementation, and E2E.
  Report absence alone still does not mean failure before the controlled-stop
  decision.

The script preserves CLI compatibility: omitting `--detach` still selects
synchronous execution. The defaults above are caller policy, not an automatic
mode switch inside the script.

## Environment variables

| Variable | Effect |
|---|---|
| `AGENT_DELEGATE_SANDBOX` | Default sandbox stage when `--sandbox` is omitted |
| `AGENT_DELEGATE_HOST` | Force host side (`claude`/`codex`) for target resolution |
| `AGENT_DELEGATE_REVIEW_LANG` | `ja` selects the Japanese review template |
| `AGENT_DELEGATE_TEST_MODE` | `1` = resolve arguments, print the plan line, and exit 0 without launching any CLI; `heartbeat` = exercise detached handoff, owner, heartbeat, and terminal publication with the tracked harness and no peer CLI |

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

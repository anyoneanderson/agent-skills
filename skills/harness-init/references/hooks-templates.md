# Hooks Templates

Three enforcement levels for `.claude/settings.json`. `harness-init` selects
one based on the user's answer to "hook level" during hearing.

**Important**: Claude Code hooks receive their input as **JSON on
stdin**. Environment variables like `$TOOL_NAME` or `$FILE_PATH` are NOT
injected. All scripts extract fields via `jq`.

Scripts referenced below live in `.harness/scripts/` after `harness-init`
runs.

---

## Level: minimal

Observability only. No blocking. Use for trusted teams or early exploration.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**What it covers**:
- Every file edit/write appends one line to `.harness/progress.md`
- `Stop` hook re-injects the loop prompt if `_state.json.completed == false`
  and no Principal Skinner condition is hit

**What it does NOT cover**:
- Tier-A destructive operations pass through
- Unlisted MCP servers can be called
- No automatic restore after `/compact`

---

## Level: warn

Observability + logging of risky operations. Does not block, but records.
Use for learning what your project actually does before committing to strict.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/tier-a-guard.sh --warn-only" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/restore-after-compact.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**What it covers**:
- Everything from `minimal`
- Tier-A patterns (rm -rf, force-push, etc.) are matched and logged to
  `.harness/progress.md` but **not blocked**
- Auto-restore from progress.md + _state.json on compact

---

## Level: strict

Full enforcement. Blocks Tier-A operations and unlisted MCP calls. Use for
autonomous / autonomous-ralph modes where no human is watching.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/tier-a-guard.sh" }
        ]
      },
      {
        "matcher": "mcp__.*",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/mcp-allowlist.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/progress-append.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": ".harness/scripts/restore-after-compact.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": ".harness/scripts/stop-guard.sh" }
        ]
      }
    ]
  }
}
```

**What it covers**:
- Everything from `warn`
- Tier-A patterns (from `.harness/tier-a-patterns.txt`) are **denied** and
  set `_state.json.pending_human = true`
- MCP calls are checked against `_config.yml.allowed_mcp_servers` and
  denied if not listed

**Required for autonomous modes**: `continuous`, `autonomous-ralph`,
`scheduled`. Can be relaxed to `warn` for `interactive` mode where the
human catches misbehaviour.

---

## Codex-side hooks (generator_backend ∈ {codex_plugin, codex_cmux})

When the Generator runs under Codex, Claude Code's `PostToolUse(Edit|Write)`
hook cannot observe Codex's internal tool calls (confirmed experimentally
in Issue #46). To close that gap, `harness-init` also installs a set of
hooks on the **Codex side**, in `<project>/.codex/hooks.json`. These
hooks run inside Codex's hook runner when Codex makes a Bash tool call
(or starts a session).

**Scope**: Codex hooks currently support only `Bash` tool interception
(as of 2026-04 — see https://developers.openai.com/codex/hooks). Write /
MCP / WebSearch interception is not yet implemented. The file-write gap
is covered separately by `.harness/scripts/codex-progress-bridge.sh`,
which reads Codex's `feedback/generator-<iter>-report.json` after the
invocation and appends equivalent rows to `progress.md`.

### Generated files (when backend ∈ codex_plugin, codex_cmux)

```
<project>/.codex/
├── config.toml                              # [features] codex_hooks=true appended
├── hooks.json                               # Codex hook registration
└── hooks/
    ├── inject-harness-context.sh            # SessionStart(startup|resume)
    ├── tier-a-guard-codex.sh                # PreToolUse(Bash) — Tier-A double guard
    └── codex-bash-log.sh                    # PostToolUse(Bash) — log bash results to progress.md
```

### `hooks.json` shape

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/inject-harness-context.sh",
          "timeout": 5,
          "statusMessage": "Injecting harness state"
        }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/tier-a-guard-codex.sh",
          "timeout": 5,
          "statusMessage": "Tier-A guard (codex)"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "<PROJECT_ROOT>/.codex/hooks/codex-bash-log.sh",
          "timeout": 5,
          "statusMessage": "Logging codex bash"
        }]
      }
    ]
  }
}
```

`harness-init` resolves `<PROJECT_ROOT>` to an absolute path at install
time (so the hooks still work when Codex is started from a subdirectory).

### What each Codex hook does

| Hook | Event | Purpose |
|---|---|---|
| `inject-harness-context.sh` | `SessionStart(startup\|resume)` | Emits `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` containing the tail of `.harness/progress.md` plus a `_state.json` summary. Codex picks this up as developer context for its fresh thread. |
| `tier-a-guard-codex.sh` | `PreToolUse(Bash)` | Mirror of the Claude-side guard. Matches Codex's about-to-run Bash command against `.harness/tier-a-patterns.txt`; on match, emits a Codex `permissionDecision: "deny"` to block. Keeps Tier-A enforcement even when Codex's Bash bypasses Claude's hook. |
| `codex-bash-log.sh` | `PostToolUse(Bash)` | Appends a `codex-bash` line to `.harness/progress.md` for every Bash command Codex runs (test / build / lint / etc.), including exit code if present. Never blocks; fails open. |

### `config.toml` patch

`harness-init` appends (non-destructively) to `<project>/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

If the file does not exist, it is created with just this block. If
`[features]` already exists, `codex_hooks` is added without disturbing
other entries.

### Claude-side hooks coexist

The Codex-side hooks do NOT replace the Claude-side ones. `harness-init`
still installs the full Claude `.claude/settings.json` hook set (strict
/ warn / minimal as chosen). Both sides fire independently:

- Claude session's Bash / Edit / Write → Claude hooks fire
- Codex subprocess's Bash → Codex hooks fire (Claude hooks stay silent)
- Codex subprocess's Write → neither side fires; covered by bridge script

### Future work

When Codex's `PostToolUse` matcher extends to `Write` / `Edit` / MCP /
WebSearch, the Orchestrator bridge can be simplified (Codex hooks will
record touched files themselves). Until then, the bridge + report.json
pattern is authoritative. Tracked in Issue #46 "Future Work" section.

---

## Speed Tiers

Hooks are the millisecond tier of a four-layer defence:

| Tier | Latency | Mechanism | Enforces |
|---|---|---|---|
| Hook | ms | This file | Break-glass deny, state dump, compact restore |
| pre-commit | s | `lefthook` / husky | Formatter, fast lint, secret scan |
| Skill | min | spec-review / spec-test | Rubric scoring, acceptance scenarios |
| CI | h | GitHub Actions | Full test matrix, slow E2E, publish gates |

`harness-init` only writes the **Hook tier**. The other tiers are out of
scope — projects bring their own.

---

## Merge Behaviour

`harness-init` never overwrites an existing `.claude/settings.json`:

1. Read existing `hooks` block.
2. Compute the patch (what to add/replace).
3. Show `diff` to the user via AskUserQuestion.
4. Apply only after approval.
5. If user rejects, write to `.claude/settings.harness.json.proposed`
   and stop.

Do NOT clobber hooks added by other skills or manually.

---

## Verifying the Installation

After `harness-init` completes, validate with:

```bash
# 1. jq must be available
command -v jq >/dev/null || echo "ERROR: jq required"

# 2. Every referenced script must exist and be executable
for s in .harness/scripts/*.sh; do
  [ -x "$s" ] || echo "NOT EXECUTABLE: $s"
done

# 3. Dry-run a PostToolUse hook
echo '{"tool_name":"Write","tool_input":{"file_path":"dummy.txt"}}' \
  | .harness/scripts/progress-append.sh
tail -1 .harness/progress.md

# 4. Dry-run tier-a-guard WITHOUT polluting state (HARNESS_TEST_MODE=1).
#    Running without this flag flips _state.json.pending_human=true and
#    appends a TIER-A MATCH line to progress.md — avoid that during install.
echo '{"tool_input":{"command":"rm -rf /tmp/dummy"}}' \
  | HARNESS_TEST_MODE=1 .harness/scripts/tier-a-guard.sh
# Expected: {"decision":"deny", ..., "test_mode":true}
# _state.json and progress.md remain unchanged.

# 5. Dry-run mcp-allowlist (read-only; no flag needed)
echo '{"tool_name":"mcp__not-in-list__x"}' \
  | .harness/scripts/mcp-allowlist.sh
# Expected: {"decision":"deny", ...}
```

Full installation verification is covered by the harness-suite E2E test plan.

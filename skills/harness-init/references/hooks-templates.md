# Hooks Templates

Three enforcement levels for `.claude/settings.json`. `harness-init` selects
one based on the user's answer to "hook level" during hearing.

**Important (ASM-005)**: Claude Code hooks receive their input as **JSON on
stdin**. Environment variables like `$TOOL_NAME` or `$FILE_PATH` are NOT
injected. All scripts extract fields via `jq`.

Scripts referenced below live in `.harness/scripts/` after `harness-init`
runs. See T-015 for script contents.

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
autonomous / autonomous-ralph modes (REQ-078) where no human is watching.

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
  set `_state.json.pending_human = true` (REQ-081 / REQ-082)
- MCP calls are checked against `_config.yml.allowed_mcp_servers` and
  denied if not listed (REQ-101)

**Required for autonomous modes**: `continuous`, `autonomous-ralph`,
`scheduled`. Can be relaxed to `warn` for `interactive` mode where the
human catches misbehaviour.

---

## Speed Tiers (NFR-005)

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

Full installation verification is covered by T-054 (E2E).

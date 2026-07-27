# Sage Adapters — Configuration and Setup

Which CLIs sit in the three seats, how `magi-run.sh` calls them, and how to swap
one out. Japanese version: [sages.ja.md](sages.ja.md).

The roster is configuration rather than part of the skill on purpose. Headless
agent CLIs appear and disappear on a scale of months — Gemini CLI ended its
individual offering in June 2026 while aggregator articles still listed it as
current — so `SKILL.md` names no CLI in its rules and reads only the field names
below.

## Resolution order

`magi-run.sh` reads the **first** file it finds:

1. `$MAGI_SAGES_FILE` — per-run override. If the variable is set and the file
   does not exist, the script stops with exit 2 rather than falling back; an
   explicit override that silently does nothing is worse than an error.
2. `./.magi/sages.json` — per-project, relative to the working directory.
3. `~/.magi/sages.json` — per-user.
4. `references/scripts/sages.default.json` — bundled default.

Only that one file is read. Nothing is merged, so a partial override file must
list **every** sage you want, not just the one you are changing.

## Top-level fields

| Field | Type | Meaning |
|---|---|---|
| `timeout_seconds` | positive integer | Per-sage wall-clock limit, enforced by a `perl alarm` wrapper. Default 600 (10 minutes). A sage killed this way is recorded as `status: "timeout"` |
| `sages` | array, 1 to 3 entries | The roster, in the order rows appear in `summary.json` and the result matrix |

Three is the maximum. The tally rules in `SKILL.md` are built on three (or two
degraded), so a config with four sages exits 2 instead of silently changing how
votes are counted.

A roster of two is accepted, and it is a degraded council even though nothing is
missing: `preflight.json` reports `available_count: 2` with an empty `missing`.
The host confirms with the user before dispatching and applies the two-sage
rules — 2-0 passes, a 1-1 split gets a single debate round. A roster of one is
rejected by the host at that point, since a single model is not a council.

## Per-sage fields

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Display name, e.g. `MELCHIOR`. Becomes a file name in the run directory, so only `A-Z a-z 0-9 _ -`. Must be unique |
| `cli` | yes | Command checked by preflight with `command -v`. This is the name reported as missing, and the name shown next to the sage in the matrix |
| `command` | yes | Non-empty array of strings — argv, executed directly with no shell |
| `input` | no | `"stdin"` means the prompt file is redirected to standard input. Omit it to pass the path via `{PROMPT_FILE}`. No other value is accepted |
| `extract` | yes | How to get the answer body out: a jq filter, `"answer-file"`, or `"raw"` (see below) |
| `schema_args` | no | Array of strings appended to `command` only on runs that pass `--schema-file` |
| `notes` | no | Free text for whoever reads the config next. Ignored by the script |

### Placeholders in `command` and `schema_args`

Substituted element by element, never through a shell, so a path containing
spaces or an ampersand cannot be re-parsed as syntax.

| Placeholder | Replaced with |
|---|---|
| `{PROMPT_FILE}` | Absolute path of the prompt file for this sage in this round |
| `{ANSWER_FILE}` | Path the script expects the CLI to write its final answer to |
| `{SCHEMA}` | Full text of the `--schema-file` contents |
| `{MAGI_SCRIPTS_DIR}` | Absolute path of the directory holding `magi-run.sh`, for reaching a wrapper shipped beside it without hard-coding an install path |

**The prompt body never goes into `command`.** A sage receives the question
either on stdin or as a file path, because command-line arguments are readable by
every process on the machine through `ps`. The old `{PROMPT}` placeholder was
withdrawn for this reason and the config validator now rejects it by name. Each
sage must therefore have either `{PROMPT_FILE}` in `command` or
`"input": "stdin"`; a config with neither is rejected, since there would be no
way to deliver the question.

### `extract` values

| Value | Use when | Behaviour |
|---|---|---|
| jq filter, e.g. `.result` | The CLI prints a JSON envelope on stdout | Applied with `jq -er`; a missing key, `null`, or an empty result counts as a failed extraction |
| `"answer-file"` | The CLI writes its final message to a file | Reads `{ANSWER_FILE}`, which `command` must contain. Nothing is transformed |
| `"raw"` | The CLI prints the answer as plain text | Copies stdout verbatim |

A failed extraction sets `status: "error"` even when the CLI exited 0. The script
never inspects whether the answer is the JSON the host asked for — that check
belongs to the host (CON-002), which treats an unparseable answer as a degraded
sage (REQ-010).

## The bundled default

```json
{
  "timeout_seconds": 600,
  "sages": [
    {
      "name": "MELCHIOR",
      "cli": "claude",
      "command": ["claude", "-p", "--output-format", "json", "--allowedTools", "WebSearch", "WebFetch"],
      "input": "stdin",
      "extract": ".result"
    },
    {
      "name": "BALTHASAR",
      "cli": "codex",
      "command": ["{MAGI_SCRIPTS_DIR}/codex-sage.sh", "--sandbox", "read-only", "--output-last-message", "{ANSWER_FILE}", "-"],
      "input": "stdin",
      "extract": "answer-file"
    },
    {
      "name": "CASPER",
      "cli": "grok",
      "command": ["grok", "--prompt-file", "{PROMPT_FILE}", "--output-format", "json", "--permission-mode", "auto", "--tools", "web_search,web_fetch", "--deny", "MCPTool(*)"],
      "extract": ".text",
      "schema_args": ["--json-schema", "{SCHEMA}"]
    }
  ]
}
```

`notes` fields are present in the real file and elided here. Three details are
worth knowing:

- BALTHASAR runs under `--sandbox read-only`. Asking for an opinion never
  requires writing files, so the sandbox stays closed.
- BALTHASAR's trailing `-` is what makes `codex exec` read the prompt from
  stdin. It reaches `codex` through the bundled `codex-sage.sh`, for the reason
  in the next section.
- CASPER is the only default sage with `schema_args`. Grok can be constrained to
  a JSON schema, which removes most broken-answer failures; the other two rely on
  the prompt instruction and the host's parsing.

### Web search permissions

Research mode is only as good as the sages' ability to check the web, and each
CLI gates tool use differently in headless mode. The defaults carry the flags
that open it, verified on real runs 2026-07-27:

- **MELCHIOR needs `--allowedTools WebSearch WebFetch`.** Headless `claude -p`
  denies every tool that was not explicitly allowed, so without the allowlist its
  search, fetch and shell calls all come back denied: the sage answers from
  training data or reports that it could not check. With the allowlist the search
  runs. Keep the flag last in `command`, because it accepts a list of tool names
  and would otherwise swallow the flag that follows it.
- **BALTHASAR needs nothing extra.** Its search executes on the provider's side,
  so `--sandbox read-only` does not block it — the sandbox governs this machine's
  files, not the model's own tools. A search shows up as a `web search:` line in
  `BALTHASAR.stderr`.
- **CASPER needs `--permission-mode auto`.** Without it the run stops at a tool
  approval prompt that nobody is there to answer and ends early with
  `stopReason: "Cancelled"`, leaving no usable answer.

CASPER also sometimes puts a sentence of prose before the JSON object it was
asked for. The host extracts the JSON part (`SKILL.md` Step 5), so this is not a
failure; expect it if you write your own adapter around `grok`.

### Keeping the question inside the announced providers

`SKILL.md` tells the user which providers receive the question — three companies
by default. That statement only holds if a sage cannot pass the question to a
tool of its own, and a headless CLI inherits the operator's whole tool set,
which usually includes MCP servers pointed at other companies' services. A
search-shaped question can then reach a fourth provider without anything looking
unusual in the transcript. Each default sage therefore starts with those tools
blocked, verified 2026-07-27:

| Sage | How MCP and plugin tools are blocked | What remains |
|---|---|---|
| MELCHIOR | `--allowedTools WebSearch WebFetch` is an allowlist, so an MCP tool is simply not on it | Nothing observed: an MCP call is denied like any other unlisted tool |
| BALTHASAR | The bundled `codex-sage.sh` wrapper (below) | Nothing: the servers leave the tool registry entirely |
| CASPER | `--tools web_search,web_fetch` limits the built-ins, `--deny 'MCPTool(*)'` refuses MCP calls | The MCP tool schemas are still listed to the model; only calling one is refused, with `Denied by permission policy: deny rule on mcp` |

#### `codex-sage.sh`

`codex exec` has no single "no MCP" flag, so the wrapper splits the work between
two mechanisms, and the split is the part worth remembering:

- `--disable plugins --disable apps` handles servers supplied by plugins and
  apps. Those cannot be switched off individually — aiming
  `-c mcp_servers.<name>.enabled=false` at one makes codex fail with
  `invalid transport` instead of disabling it.
- `-c mcp_servers.<name>.enabled=false`, generated once per server, handles the
  servers the operator configured.

**The list of servers comes from `codex mcp list --json --disable plugins`, not
from reading `config.toml`.** This matters more than it sounds. TOML can declare
the same server in several ways — a `[mcp_servers.<name>]` header, an inline table
under `[mcp_servers]`, dotted `mcp_servers.<name>.command` keys, an indented
header — so a hand-written parser quietly misses some of them, and a missed server
stays enabled. Asking codex uses its own configuration loader, which also covers
settings the wrapper never sees, such as project-level configuration and a
relocated `$CODEX_HOME`. Passing `--disable plugins` to the list call keeps
plugin-supplied servers out of the result, so every name it returns is one that
`-c` can actually switch off.

With codex-cli 0.145.0 this took the registered tool count from 141 down to 19
with no MCP-backed tool left, and a question naming a tool from one of those
servers came back as "no such tool is registered".

The adapter keeps `"cli": "codex"` while `command[0]` is the wrapper: preflight
should report the CLI the user would have to install, which is `codex` itself.

**Minimum version: codex-cli 0.145.0**, the release `mcp list --json` and
`--disable` were verified against. An older codex rejects the unknown flag, so the
wrapper stops (see below) and BALTHASAR is recorded as no answer. The council
degrades to two sages and the question still does not leak — but if BALTHASAR
fails on every run, check `codex --version` first.

The wrapper **fails closed** with exit 2 in three situations, all of them meaning
"the full set of servers to block could not be established":

- The roster call fails. codex's own message is left on stderr next to the
  refusal, which is where an unknown-flag error from an older release shows up.
- The roster is not an array of objects carrying a name.
- A name is empty, or holds anything outside `[A-Za-z0-9_-]`, so it cannot become
  a dotted `-c` path. Rename or remove that server. Note that such a name is never
  skipped in order to disable the rest: skipping is precisely how one server would
  stay enabled while the sage looked healthy.

In each case BALTHASAR appears as `no answer (error)` with the reason in
`BALTHASAR.stderr`, and nothing is sent. A failed sage is recoverable, a question
sent to an undisclosed provider is not.

#### Known limit: the roster is a snapshot

The disable list is built once, immediately before `codex exec` starts. If the
codex configuration changes in that window — `codex mcp add` from another terminal,
an editor saving `config.toml` — a server added there is not in the list and
therefore not disabled. **Do not change codex's MCP configuration while a council
is running.**

This is a guard against accidents, not against a hostile process. Anyone able to
rewrite that configuration during the run could equally rewrite the sage config or
this wrapper, so treating the window as a security boundary would be misleading.
It is documented because an operator adding a server mid-run is a plausible
mistake, and because a reader deserves to know what the blocking does not cover.

**Swapping a sage means re-establishing this yourself.** The config validator
checks structure, not tool permissions. For whatever CLI you seat, find its
allowlist or deny flag and its plugin switch, confirm on a real run that an MCP
tool cannot be called, and write what you verified into the adapter's `notes`.

## Installing and authenticating the default sages

Verified 2026-07-27 with `claude` 2.1.220, `codex-cli` 0.145.0 and `grok`
0.2.112 on macOS. Install commands change more often than the flags do, so check
the vendor's current instructions if one of these fails.

### MELCHIOR — Claude Code (`claude`)

```bash
npm install -g @anthropic-ai/claude-code   # or: curl -fsSL https://claude.ai/install.sh | bash
claude                                     # sign in interactively, once
claude setup-token                         # optional: long-lived token for headless use
```

### BALTHASAR — Codex CLI (`codex`)

```bash
npm install -g @openai/codex               # or: brew install codex
codex login                                # browser sign-in
codex login status                         # confirm
```

For an API key instead of a browser session:
`printenv OPENAI_API_KEY | codex login --with-api-key`.

**0.145.0 is the minimum here**, not just the version that happened to be tested:
the bundled `codex-sage.sh` needs `mcp list --json` and `--disable`, and it refuses
to run rather than proceed without them.

### CASPER — Grok Build (`grok`)

```bash
grok login --device-auth                   # device-code flow; alias: --device-code
grok login --oauth                         # browser flow via auth.x.ai
```

`grok` ships with some desktop environments; check `command -v grok` before
installing it separately. On the xAI free plan the quota is a weekly pool, and an
exhausted quota comes back as an error response — the host records it as
`no answer (error)` and continues with two sages rather than treating it
specially.

## Swapping a sage: CASPER → Antigravity CLI (`agy`)

Verified 2026-07-27 against the installed `agy`. This CLI needs a different
adapter shape from the defaults, and the reasons are worth reading before you
adopt it.

```json
{
  "name": "CASPER",
  "cli": "agy",
  "command": [
    "agy",
    "--add-dir", "{PROMPT_FILE}",
    "--print-timeout", "10m",
    "-p", "Read the file {PROMPT_FILE} and follow the instructions inside it exactly. Reply with only the JSON object it asks for: no prose, no code fence. Do not ask any questions."
  ],
  "extract": "raw",
  "notes": "Antigravity CLI. No stdin mode and no prompt-file flag, so the prompt path is passed in argv and agy reads the file itself; --add-dir grants read access to that one file. Plain-text output, no schema flag."
}
```

Why it is shaped that way:

- **`agy` cannot read a prompt from stdin.** `-p` (alias `--print`) requires a
  value: bare `agy -p` fails with "flag needs an argument", and `agy -p -` treats
  the dash as the literal prompt text and answers "How can I help you today?".
  So `"input": "stdin"` is not an option.
- **`agy` has no `--prompt-file`.** Passing the question as the `-p` value would
  put the whole prompt in argv, where `ps` exposes it; the validator rejects that
  shape. Instead argv carries only the path plus a fixed instruction, and `agy`
  opens the file with its own read tool. The question itself never appears in the
  process list.
- **`--add-dir` is required and grants exactly one file.** Without it, headless
  mode auto-denies the `read_file` permission. Pointing it at `{PROMPT_FILE}`
  grants read access to that file alone — an attempt to read a sibling file in
  the same directory was still denied — so this sage cannot see the other sages'
  answers sitting in the same round directory, and round-1 independence holds.
- **`extract: "raw"`.** There is no JSON envelope; the answer arrives as plain
  text on stdout. In testing the model returned the bare JSON object as
  instructed.
- **No `schema_args`.** `agy` has no JSON-schema flag, so the answer shape rests
  on the prompt instruction alone. A malformed answer is handled the same way as
  any other broken answer: the host records the sage as `no answer (invalid
  answer)` and continues degraded. It does **not** re-send within the round
  (REQ-010).
- **`--print-timeout` defaults to 5 minutes**, shorter than the 600-second
  `timeout_seconds`. Set it to at least `timeout_seconds` or `agy` gives up
  before the council's own limit; the value is a Go duration string (`10m`).
- **Web search and tool isolation are unverified for this CLI.** Whether `agy` can
  search the web in headless mode, which permission flag that would need, and how
  to block its MCP and extension tools were all left untested. Check both before
  seating `agy`: a sage that cannot search still produces a confident answer that
  rests on training data, and a sage that can reach the operator's MCP tools
  breaks the provider boundary described above. `--add-dir` restricting file reads
  is not evidence about network tools.

The operational caveat worth knowing: **`agy` exits 0 even when it produced no
answer.** When the read permission is denied it prints a notice
("no output produced — a tool required the read_file permission…") and exits 0,
so the script records `status: "ok"` with that notice as the answer. The host
catches it when the answer fails to parse as JSON, which is why the parse check
in `SKILL.md` Step 5 is not optional. If you see that notice in
`CASPER.stdout`, `--add-dir` is missing or pointing somewhere else.

## Checking a config change

```bash
# Are the commands there, and is the file the one you expect?
MAGI_SAGES_FILE=./.magi/sages.json \
  references/scripts/magi-run.sh --out-dir /tmp/magi-check --preflight-only
```

`preflight.json` names the config file it actually read (`sages_file`), so this
is also how you confirm the resolution order picked your override rather than the
bundled default. A structural mistake — an unusable `extract`, a missing way to
deliver the prompt, a duplicate name — exits 2 and lists every problem at once.

To exercise a new adapter without spending real inference, copy a fixture from
`references/scripts/tests/fixtures/` and point it at a shell script that echoes a
canned answer. `references/scripts/tests/run-tests.sh` does exactly this for the
parallel, timeout and failure paths.

# OTLP Exporter (optional)

Covers REQ-092. An optional side-process reads `.harness/metrics.jsonl`
and forwards per-iteration metrics to an OpenTelemetry Protocol (OTLP)
endpoint so cost, rubric trends, and tool-failure rates can be viewed
alongside other project telemetry.

Active only when **both** conditions hold:

- `_config.yml.hook_level == "strict"`
- `_config.yml.otlp_endpoint` is a non-empty URL

Otherwise this reference is informational — the exporter script still
ships but is a no-op.

## Install

`harness-init` places `.harness/scripts/metrics-exporter.sh` when
`hook_level == strict`. The script is idempotent: running it twice
starts two tail readers that race on the cursor file. Always ensure
only one instance runs per project.

Typical deployment patterns:

- **Session scope** — start alongside `harness-loop`, stop when the
  session ends. Suitable for interactive / continuous modes.
- **Long-running** — run under `launchd` (macOS) or `systemd --user`
  (Linux), survives sessions. Suitable for `autonomous-ralph` and
  `scheduled` modes.

## Invocation

Foreground (for debugging):

```bash
.harness/scripts/metrics-exporter.sh
```

Detached (for overnight):

```bash
nohup .harness/scripts/metrics-exporter.sh >> .harness/otlp.log 2>&1 &
disown
```

Stop:

```bash
pkill -f '.harness/scripts/metrics-exporter.sh'
```

## What it exports

Every new line in `metrics.jsonl` is transformed into one OTLP metric
batch with the following instruments:

| Instrument | Type | Unit | Source field |
|---|---|---|---|
| `harness.iter.duration` | histogram | ms | `duration_ms` |
| `harness.iter.input_tokens` | histogram | {token} | `input_tokens` |
| `harness.iter.output_tokens` | histogram | {token} | `output_tokens` |
| `harness.iter.cost` | histogram | {USD} | `cost_usd` |
| `harness.iter.tool_calls` | histogram | {call} | `tool_calls` |
| `harness.iter.tool_failures` | histogram | {fail} | `tool_failures` |
| `harness.rubric.score` | gauge | 1 | `rubric_scores.<axis>` (one gauge per axis) |
| `harness.iter.cost_cumulative` | counter | {USD} | running sum of `cost_usd` |

Common resource attributes on every emission:

- `service.name = "harness"`
- `harness.epic = <current_epic>`
- `harness.sprint = <sprint>`
- `harness.agent = <agent>` (generator / evaluator / orchestrator)
- `harness.mode = <interactive|continuous|autonomous-ralph|scheduled>`

## Cursor file

The exporter keeps a byte offset at `.harness/.metrics-cursor` so a
restart resumes where the previous run stopped. On startup:

```bash
cursor=$(cat .harness/.metrics-cursor 2>/dev/null || echo 0)
tail -F -c +$((cursor+1)) .harness/metrics.jsonl | while read -r line; do
  # emit to OTLP
  cursor=$(stat -f %z .harness/metrics.jsonl)   # macOS; -c %s on Linux
  printf '%s' "$cursor" > .harness/.metrics-cursor
done
```

If the cursor file is missing, the exporter starts from the current
end-of-file (treat historical metrics as already seen). Override with
`METRICS_REPLAY=1` to start from offset 0.

## Endpoint and auth

Supported endpoints:

- OTLP/HTTP JSON on `_config.yml.otlp_endpoint` (e.g.,
  `https://collector.internal/v1/metrics`)
- OTLP/HTTP with bearer token via `OTLP_AUTH_BEARER` env var
- mTLS via `OTLP_CLIENT_CERT` + `OTLP_CLIENT_KEY` env vars (optional)

gRPC OTLP is not supported in v1 — the shell exporter uses `curl` to
keep dependencies light. If your collector only speaks gRPC, run a
sidecar translator (e.g., an OpenTelemetry Collector) that accepts
OTLP/HTTP on localhost.

## Health and backpressure

Failure modes:

| Failure | Behaviour |
|---|---|
| Endpoint 5xx / timeout | Retry up to 3 times with exponential backoff (1s, 4s, 16s). On final failure, log to `.harness/otlp.log` and continue past that line — **do not back up metrics.jsonl** |
| Endpoint 4xx | Do not retry; log payload prefix and line offset; skip |
| Endpoint unreachable at start | Exit 0 with a warning; user addresses config |
| `metrics.jsonl` rotated (truncated) | Reset cursor to 0 automatically |

The exporter **never** blocks `harness-loop`. Metrics export is
best-effort — a dropped line does not stop the loop. `metrics.jsonl`
itself is the durable record; OTLP is the live view.

## Sanity check

```bash
# 1. Confirm config
jq -r '.hook_level, .otlp_endpoint' .harness/_config.yml

# 2. Write a fake iteration line
printf '{"ts":"%s","iter":0,"sprint":1,"agent":"test","duration_ms":100,"cost_usd":0.01,"rubric_scores":{"functionality":0.5},"tool_calls":1,"tool_failures":0}\n' \
  "$(date -u +%FT%TZ)" >> .harness/metrics.jsonl

# 3. Check the collector
curl -s "$OTLP_DEBUG_URL" | jq '.resourceMetrics[-1]'
```

## Disabling

To disable without reinitialising:

```bash
yq -y '.otlp_endpoint = ""' .harness/_config.yml > /tmp/_config.yml
mv /tmp/_config.yml .harness/_config.yml
pkill -f '.harness/scripts/metrics-exporter.sh'
```

The no-op path in the exporter checks `otlp_endpoint` on each tick and
exits cleanly when cleared.

## What this does NOT cover

- Log forwarding (`progress.md` → logging pipeline) — out of scope v1
- Trace export (per-tool spans) — the Anthropic SDK does not emit OTLP
  spans natively; revisit if it gains native support
- Dashboarding — pick any OTLP-compatible backend (Grafana Mimir,
  Honeycomb, Datadog, etc.)
- Retention policy — delegated to the collector / backend

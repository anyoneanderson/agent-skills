#!/usr/bin/env bash
# Records a descendant PID before waiting long enough for the runner timeout.
# The test uses the prompt path as a private per-run location for the PID file.

set -euo pipefail

pid_file="${1}.descendant.pid"
sleep 30 &
descendant_pid=$!
printf '%s\n' "$descendant_pid" > "$pid_file"
wait "$descendant_pid"

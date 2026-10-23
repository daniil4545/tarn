#!/bin/sh
# Forwards one Claude Code hook event to the running tarn app (docs/spec.md 2.3).
# Never slows or fails the agent: no output, exit 0, a missing app means an instant exit.
[ -n "$TARN_SURFACE" ] || exit 0
sock="$HOME/Library/Application Support/tarn/tarn.sock"
[ -S "$sock" ] || exit 0
{
  printf '{"version":1,"surface":"%s","event":' "$TARN_SURFACE"
  tr -d '\n'
  printf '}\n'
} | nc -U -w 1 "$sock" >/dev/null 2>&1
exit 0

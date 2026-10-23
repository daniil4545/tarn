#!/bin/sh
# Forwards one Claude Code hook event to the running tarn app (docs/spec.md 2.3).
# Never slows or fails the agent: no output, exit 0, a missing app means an instant exit.
[ -n "$TARN_SURFACE" ] || exit 0
sock="$HOME/Library/Application Support/tarn/tarn.sock"
[ -S "$sock" ] || exit 0
event=$(tr -d '\n')
printf '{"version":1,"surface":"%s","event":%s}\n' "$TARN_SURFACE" "$event" \
  | nc -U -w 1 "$sock" >/dev/null 2>&1 &
# A live app reads the line in a few ms, which keeps events in order; a hung app
# keeps nc until its own 1 s timeout, but the agent waits about 50 ms.
sender=$!
tries=0
while kill -0 "$sender" 2>/dev/null && [ "$tries" -lt 5 ]; do
  sleep 0.01
  tries=$((tries + 1))
done
exit 0

#!/bin/sh
# Forwards one Claude Code hook event to the running tarn app (docs/spec.md 2.3).
# Never slows or fails the agent: no output, exit 0, a missing app means an instant exit.
[ -n "$TARN_SURFACE" ] || exit 0
sock="$HOME/Library/Application Support/tarn/tarn.sock"
[ -S "$sock" ] || exit 0
event=$(tr -d '\n')
# Let go of the agent's pipes, so a sender stuck on a hung app holds none of them.
exec </dev/null >/dev/null 2>&1
printf '{"version":1,"surface":"%s","event":%s}\n' "$TARN_SURFACE" "$event" \
  | nc -U -w 1 "$sock" >/dev/null 2>&1 &
# A live app reads the line in a few ms, which keeps events in order. A hung app never
# reads, and nc ignores -w on a blocked write, so the sender is dropped after about 40 ms.
sender=$!
tries=0
while kill -0 "$sender" 2>/dev/null && [ "$tries" -lt 4 ]; do
  sleep 0.01
  tries=$((tries + 1))
done
kill "$sender" 2>/dev/null
exit 0

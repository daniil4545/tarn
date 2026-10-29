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
# A live app reads the line in a few ms: wait for the sender, which keeps events in order.
# A hung app never reads, and nc ignores -w on a blocked write, so a detached timer kills
# the sender after 40 ms. A hung app costs one extra process start, not a polling loop.
sender=$!
(
  sleep 0.04
  kill "$sender"
) 2>/dev/null &
timer=$!
wait "$sender" 2>/dev/null
kill "$timer" 2>/dev/null
exit 0

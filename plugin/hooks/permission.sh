#!/bin/sh
# Asks the running tarn app to answer one PermissionRequest from its sidebar card (docs/spec.md 2.3).
# Waits while the app holds the connection and prints its decision. No app, or a connection
# closed without an answer, prints nothing, so Claude Code shows its own dialog.
[ -n "$TARN_SURFACE" ] || exit 0
sock="$HOME/Library/Application Support/tarn/tarn.sock"
[ -S "$sock" ] || exit 0
event=$(tr -d '\n')
nc -U "$sock" 2>/dev/null <<EOF &
{"version":1,"surface":"$TARN_SURFACE","reply":true,"event":$event}
EOF
# Claude Code stops a hook on Esc or timeout; the connection goes with it, so the card drops it.
sender=$!
trap 'kill "$sender" 2>/dev/null; exit 0' TERM INT HUP
wait "$sender"
exit 0

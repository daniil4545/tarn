#!/bin/sh
# A second Tarn for the agent's live checks, next to the user's running one.
# Usage: stand.sh <Tarn.app> [launch args]   start or restart; prints the env for the tarn CLI
#        stand.sh stop
# The copy gets its own bundle id and home ($TARN_STAND/home), so its control socket, settings and
# AppleScript target never touch the user's Tarn. The home is short: sun_path holds 104 bytes.
set -eu

stand="${TARN_STAND:-/tmp/tarn-stand}"
id=com.daniil4545.tarn.stand
app="$stand/Tarn.app"
here=$(cd "$(dirname "$0")" && pwd)

stop() {
  pkill -f "$app/Contents/MacOS/ghostty" 2>/dev/null || true
}

if [ "${1:-}" = stop ]; then
  stop
  echo "stand stopped"
  exit 0
fi

src="${1:?usage: stand.sh <Tarn.app> [launch args] | stop}"
shift
[ -x "$src/Contents/MacOS/ghostty" ] || { echo "stand: $src is not a built Tarn.app" >&2; exit 1; }

stop
mkdir -p "$stand/home"
lib="$stand/fakehome.dylib"
if [ ! -f "$lib" ] || [ "$here/fakehome.c" -nt "$lib" ]; then
  clang -dynamiclib -o "$lib" "$here/fakehome.c"
fi
rm -rf "$app"
ditto "$src" "$app"
plutil -replace CFBundleIdentifier -string "$id" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app" 2>/dev/null

FAKE_PW_DIR="$stand/home" DYLD_INSERT_LIBRARIES="$lib" HOME="$stand/home" \
  "$app/Contents/MacOS/ghostty" "$@" > "$stand/app.log" 2>&1 &

sock="$stand/home/Library/Application Support/tarn/tarn.sock"
i=0
while [ "$i" -lt 30 ]; do
  surface=$(osascript -e "tell application id \"$id\" to get id of focused terminal of selected tab of front window" 2>/dev/null || true)
  if [ -n "$surface" ] && [ -S "$sock" ]; then
    echo "stand up, log $stand/app.log"
    echo "export HOME='$stand/home' TARN_SURFACE='$surface'"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "stand: no window or socket after 30 s, log $stand/app.log" >&2
exit 1

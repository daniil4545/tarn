#!/bin/sh
# A second Tarn for the agent's live checks, next to the user's running one.
# Usage: stand.sh <Tarn.app> [launch args]   start or restart; prints the env for the tarn CLI
#        stand.sh stop
# The copy gets its own bundle id and home ($TARN_STAND/home), so its control socket, settings and
# AppleScript target never touch the user's Tarn. The home is short: sun_path holds 104 bytes.
set -eu

stand="${TARN_STAND:-/tmp/tarn-stand}"
# Each stand path gets its own bundle id, so two stands never answer each other's AppleScript.
id=com.daniil4545.tarn.stand
[ "$stand" = /tmp/tarn-stand ] || id="$id.$(printf '%s' "$stand" | cksum | cut -d ' ' -f 1)"
app="$stand/Tarn.app"
sock="$stand/home/Library/Application Support/tarn/tarn.sock"
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
here=$(cd "$(dirname "$0")" && pwd)

# Waits for the old process to exit, so a restart never reports the dying one as up.
stop() {
  pkill -f "$app/Contents/MacOS/ghostty" 2>/dev/null || true
  i=0
  while pgrep -f "$app/Contents/MacOS/ghostty" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 20 ] || { echo "stand: the old stand did not exit" >&2; exit 1; }
    sleep 0.5
  done
  rm -f "$sock"
}

if [ "${1:-}" = stop ]; then
  stop
  [ ! -d "$app" ] || "$lsreg" -u "$app" 2>/dev/null || true
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
# The stand activates itself on launch: the user's keys would land in it, so the front app gets focus back.
front=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed -n 's/.*="\(.*\)"/\1/p')
rm -rf "$app"
ditto "$src" "$app"
plutil -replace CFBundleIdentifier -string "$id" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"

# A Debug build counts coverage and writes default.profraw into the cwd on exit: keep it in the stand.
FAKE_PW_DIR="$stand/home" DYLD_INSERT_LIBRARIES="$lib" HOME="$stand/home" LLVM_PROFILE_FILE="$stand/default.profraw" \
  "$app/Contents/MacOS/ghostty" "$@" > "$stand/app.log" 2>&1 &
pid=$!

# AppleScript by bundle id would launch a fresh copy with the real home if the stand were gone,
# so it is asked only while the stand process lives and its socket exists.
i=0
while [ "$i" -lt 30 ]; do
  kill -0 "$pid" 2>/dev/null || { echo "stand: the app exited, log $stand/app.log" >&2; exit 1; }
  if [ -S "$sock" ]; then
    surface=$(osascript -e "tell application id \"$id\" to get id of focused terminal of selected tab of front window" 2>/dev/null || true)
    if [ -n "$surface" ]; then
      [ -z "$front" ] || [ "$front" = "$id" ] || open -b "$front"
      echo "stand up (pid $pid), log $stand/app.log"
      echo "export HOME='$stand/home' TARN_SURFACE='$surface'"
      exit 0
    fi
  fi
  i=$((i + 1))
  sleep 1
done
echo "stand: no window or socket after 30 s, log $stand/app.log" >&2
exit 1

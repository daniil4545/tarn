#!/bin/sh
# Drives the stand (stand.sh) for the agent's live checks through Ghostty's AppleScript dictionary
# (macos/Ghostty.sdef). Every command targets the focused terminal of the stand's front window.
# Usage: drive.sh type <text>              paste text into the terminal
#        drive.sh key <key> [mods]         press a key; mods: shift,control,option,command
#        drive.sh action <action>          perform a Ghostty action, e.g. new_split:right
#        drive.sh screen                   print the visible screen as text
#        drive.sh wait <text> [seconds]    wait until the screen shows the text (default 10 s)
#        drive.sh shot <file.png>          screenshot of the stand's front window
#        drive.sh tarn <args...>           run cli/tarn as an agent inside the focused pane
# shot needs Screen Recording for the terminal this runs in; nothing else needs a permission.
set -eu

stand="${TARN_STAND:-/tmp/tarn-stand}"
id=com.daniil4545.tarn.stand
here=$(cd "$(dirname "$0")" && pwd)

fail() {
  printf 'drive: %s\n' "$*" >&2
  exit 1
}

# Refuses when the stand is down: AppleScript by bundle id would launch a copy with the real home.
pid=$(pgrep -f "$stand/Tarn.app/Contents/MacOS/ghostty" | head -1) || true
[ -n "$pid" ] || fail "the stand is not running: make -f tarn.mk live"

# Runs AppleScript on the focused terminal; argv passes text without quoting. The stand is checked
# before each call: a stand that died would be relaunched by bundle id with the real home.
osa() {
  kill -0 "$pid" 2>/dev/null || fail "the stand exited: make -f tarn.mk live"
  osascript - "$@" <<EOF
on run argv
  tell application id "$id"
    set t to focused terminal of selected tab of front window
    $script
  end tell
end run
EOF
}

# Ghostty writes the screen to a file and puts its path on the clipboard: keep the user's text.
# An empty screen writes no file and leaves the clipboard alone: only a fresh screen.txt is removed.
screen() {
  saved=$(pbpaste)
  script='perform action "write_screen_file:copy" on t'
  result=$(osa)
  file=$(pbpaste)
  printf '%s' "$saved" | pbcopy
  [ "$result" = true ] && [ "$file" != "$saved" ] && [ "${file##*/}" = screen.txt ] && [ -f "$file" ] ||
    fail "no screen text (empty screen?)"
  cat "$file"
  rm -f "$file"
  rmdir "${file%/*}" 2>/dev/null || true
}

cmd="${1:-}"
[ $# -eq 0 ] || shift
case "$cmd" in
  type)
    [ $# -eq 1 ] || fail "usage: drive.sh type <text>"
    script='input text (item 1 of argv) to t'
    osa "$1" >/dev/null
    ;;
  key)
    [ $# -ge 1 ] || fail "usage: drive.sh key <key> [mods]"
    script='send key (item 1 of argv) modifiers (item 2 of argv) to t'
    osa "$1" "${2:-}" >/dev/null
    ;;
  action)
    [ $# -eq 1 ] || fail "usage: drive.sh action <action>"
    script='perform action (item 1 of argv) on t'
    [ "$(osa "$1")" = true ] || fail "the action failed: $1"
    ;;
  screen)
    screen
    ;;
  wait)
    [ $# -ge 1 ] || fail "usage: drive.sh wait <text> [seconds]"
    i=0
    # The screen is read whole before the match: grep -q in a pipe would cut screen before its cleanup.
    until text=$(screen 2>/dev/null) && case "$text" in *"$1"*) true ;; *) false ;; esac; do
      i=$((i + 1))
      [ "$i" -lt $((${2:-10} * 2)) ] || fail "no \"$1\" on the screen after ${2:-10} s"
      sleep 0.5
    done
    ;;
  shot)
    [ $# -eq 1 ] || fail "usage: drive.sh shot <file.png>"
    # The window list is ordered front to back; layer 0 skips menus and the status item.
    wid=$(osascript -l JavaScript -e "ObjC.import('CoreGraphics')
      const a = ObjC.castRefToObject(\$.CGWindowListCopyWindowInfo(1, 0))
      let r = ''
      for (let i = 0; i < a.count && !r; i++) {
        const w = a.objectAtIndex(i)
        if (w.objectForKey('kCGWindowOwnerPID').intValue == $pid && w.objectForKey('kCGWindowLayer').intValue == 0)
          r = String(w.objectForKey('kCGWindowNumber').intValue)
      }
      r")
    [ -n "$wid" ] || fail "the stand has no window on screen"
    rm -f "$1"
    screencapture -x -o -l "$wid" "$1" 2>/dev/null && [ -s "$1" ] ||
      fail "no screenshot: grant Screen Recording to the terminal running this and restart it"
    echo "$1"
    ;;
  tarn)
    script='id of t'
    surface=$(osa)
    HOME="$stand/home" TARN_SURFACE="$surface" sh "$here/../../cli/tarn" "$@"
    ;;
  *)
    fail "usage: drive.sh type <text> | key <key> [mods] | action <action> | screen | wait <text> [s] | shot <file.png> | tarn <args...>"
    ;;
esac

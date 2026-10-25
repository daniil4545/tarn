#!/bin/sh
# install.sh against a local fake release: install, upgrade, bad checksum, foreign app, missing version.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
root=$(mktemp -d)
port=8765
rel="$root/srv/releases/download/tarn-v1.0.0"
fails=0
mkdir -p "$rel" "$root/apps" "$root/build/Tarn.app/Contents"

fake_app() {
  plist="$root/build/Tarn.app/Contents/Info.plist"
  rm -f "$plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleIdentifier -string "$1" "$plist"
  plutil -insert CFBundleShortVersionString -string "$2" "$plist"
}
publish() {
  rm -f "$rel/tarn-1.0.0-macos.zip"
  ditto -c -k --keepParent "$root/build/Tarn.app" "$rel/tarn-1.0.0-macos.zip"
  (cd "$rel" && shasum -a 256 tarn-1.0.0-macos.zip > tarn-1.0.0-macos.zip.sha256)
}
run() {
  TARN_REPO="http://127.0.0.1:$port" TARN_VERSION="${1:-1.0.0}" TARN_DEST="$root/apps" \
    sh "$here/install.sh" >/dev/null 2>&1
}
expect() {
  if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3 (got $1, want $2)"; fails=$((fails + 1)); fi
}
installed() { plutil -extract CFBundleShortVersionString raw "$root/apps/Tarn.app/Contents/Info.plist" 2>/dev/null; }

fake_app com.daniil4545.tarn 1.0.0
publish
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root/srv" >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null; wait "$server" 2>/dev/null; rm -rf "$root"' EXIT
sleep 1

run; expect "$?:$(installed)" "0:1.0.0" "fresh install"

fake_app com.daniil4545.tarn 1.0.1
publish
run; expect "$?:$(installed)" "0:1.0.1" "upgrade replaces tarn"

printf '%064d  tarn-1.0.0-macos.zip\n' 0 > "$rel/tarn-1.0.0-macos.zip.sha256"
run; expect "$?:$(installed)" "1:1.0.1" "bad checksum keeps the installed app"
publish

plist="$root/apps/Tarn.app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.example.other "$plist"
run; expect "$?:$(installed)" "1:1.0.1" "foreign Tarn.app is not replaced"
rm -rf "$root/apps/Tarn.app"

run 9.9.9; expect "$?" "1" "missing version fails"

[ "$fails" -eq 0 ] || exit 1

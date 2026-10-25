#!/bin/sh
# Installs or upgrades Tarn.app from a GitHub release (docs/install.md).
# Usage: curl -fsSL https://raw.githubusercontent.com/daniil4545/tarn/main/install.sh | sh
# TARN_VERSION=1.0.0 picks a version (default: the latest release); TARN_DEST picks the folder.
set -eu

repo="${TARN_REPO:-https://github.com/daniil4545/tarn}"
id="com.daniil4545.tarn"

fail() {
  echo "tarn install: $*" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "tarn runs on macOS only"

version="${TARN_VERSION:-}"
if [ -z "$version" ]; then
  # The latest release page redirects to .../releases/tag/tarn-vX.Y.Z.
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$repo/releases/latest") ||
    fail "cannot reach $repo"
  version=${url##*/tarn-v}
  [ "$version" != "$url" ] || fail "no tarn release found at $repo/releases"
fi

if osascript -e "application id \"$id\" is running" 2>/dev/null | grep -q true; then
  fail "Tarn is running: quit it (cmd+Q) and run the installer again"
fi

dest="${TARN_DEST:-/Applications}"
[ -w "$dest" ] || [ -n "${TARN_DEST:-}" ] || dest="$HOME/Applications"
mkdir -p "$dest"
app="$dest/Tarn.app"
if [ -e "$app" ]; then
  current=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null || true)
  [ "$current" = "$id" ] || fail "$app is not tarn ($current), not replacing it"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
zip="tarn-$version-macos.zip"
base="$repo/releases/download/tarn-v$version"
echo "Downloading tarn $version"
curl -fL --progress-bar -o "$tmp/$zip" "$base/$zip" || fail "cannot download $base/$zip"
curl -fsSL -o "$tmp/$zip.sha256" "$base/$zip.sha256" || fail "cannot download $base/$zip.sha256"
(cd "$tmp" && shasum -a 256 -c "$zip.sha256" >/dev/null) || fail "checksum mismatch for $zip"

ditto -x -k "$tmp/$zip" "$tmp/unpacked"
[ -d "$tmp/unpacked/Tarn.app" ] || fail "$zip holds no Tarn.app"
xattr -dr com.apple.quarantine "$tmp/unpacked/Tarn.app" 2>/dev/null || true
rm -rf "$app"
mv "$tmp/unpacked/Tarn.app" "$app"

echo "Installed tarn $version in $app"
echo "Open it: open '$app'. Claude Code plugin and zsh setup: $repo/blob/main/docs/install.md"

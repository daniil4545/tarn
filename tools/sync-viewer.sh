#!/bin/sh
# Copies the app's viewer bundle into demo/viewer/ for the browser demo. The app's files stay
# untouched; the copy gets a CSP that allows same-origin files and the shim that stands in for
# window.webkit.messageHandlers (an inline script would be blocked by the CSP).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/macos/Sources/Features/Tarn/Viewer"
out="$root/demo/viewer"
csp="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:"

mkdir -p "$out"
cp "$src/tarn-viewer.css" "$src/tarn-mermaid.js" "$src/tarn-viewer-licenses.txt" "$out/"
sed -e "s|\(http-equiv=\"Content-Security-Policy\" content=\"\)[^\"]*\"|\1$csp\"|" \
    -e 's|<script src="tarn-viewer.js"></script>|<script src="../js/viewer-shim.js"></script>\n<script src="tarn-viewer.js"></script>|' \
    "$src/tarn-viewer.html" > "$out/tarn-viewer.html"
# Images are read from the demo files by the same-origin path.
sed -e 's|tarn-md://file|files|g' "$src/tarn-viewer.js" > "$out/tarn-viewer.js"
grep -q 'script-src .self.' "$out/tarn-viewer.html" && grep -q viewer-shim "$out/tarn-viewer.html"
echo "synced $out"

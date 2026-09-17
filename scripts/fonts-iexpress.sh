#!/bin/bash
# Install MS corefonts WITHOUT cabextract (which needs root) and without
# winetricks (which shells out to cabextract).
#
# The corefont installers are IExpress self-extracting archives, and IExpress
# supports /C /T: to extract-only. So we just run them under Wine.
#
# Why this matters: a Wine prefix ships with ZERO fonts. WPF's font fallback
# calls Version.Parse() on garbage and FailFast()s with
#   "Unrecoverable system error"
#   at MS.Internal.Shaping.TypefaceMap.MapUnresolvedCharacters(...)
# before any window appears.
#
# Copying Liberation/Noto alone is NOT sufficient — WPF wants real Arial etc.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../bin/atp-env.sh"
export PATH="$PROTON/files/bin:$PATH"

GH="https://github.com/pushcx/corefonts/raw/master"
FONTS="andale32 arial32 arialb32 comic32 courie32 georgi32 impact32 times32 \
       trebuc32 verdan32 webdin32"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "==> downloading"
for f in $FONTS; do
    curl -sSL -o "$f.exe" "$GH/$f.exe"
done

echo "==> extracting via IExpress /C /T:"
for f in *.exe; do
    wine "$f" /C /T:"C:\\fontext\\${f%.exe}" > /dev/null 2>&1 || true
done

echo "==> installing into the prefix"
FONTDIR="$WINEPREFIX/drive_c/windows/Fonts"
mkdir -p "$FONTDIR"
n=0
while IFS= read -r f; do
    cp "$f" "$FONTDIR/" && n=$((n + 1))
done < <(find "$WINEPREFIX/drive_c/fontext" \( -iname '*.ttf' -o -iname '*.ttc' \))

echo "    installed $n font files"
echo "    total now: $(ls "$FONTDIR" | wc -l)"

#!/usr/bin/env bash
# Builds icons/FreeForm-Mac: the macOS-style app, place and Trash icons FreeForm uses, taken from
# MacTahoe (vinceliuice/MacTahoe-icon-theme, GPL-3.0, the set MacShell recommends via MacOS-Like).
# Only the scalable app and place icons are kept (symlinks resolved, so Windows can read them).
#   tools/icons/build-theme.sh OUT_DIR      e.g. pkg/FreeForm/icons
set -euo pipefail
OUT=${1:?usage: build-theme.sh OUT_DIR}
REV=839848b9a8a38a92a6936e30c4abe35cc6f2546d
TMP=$(mktemp -d)
git clone -q https://github.com/vinceliuice/MacTahoe-icon-theme "$TMP/mt"
git -C "$TMP/mt" checkout -q "$REV"
T="$OUT/FreeForm-Mac"
mkdir -p "$T/apps/scalable" "$T/places/scalable"
for kind in apps places; do
    cp "$TMP/mt/src/$kind/scalable/"*.svg "$T/$kind/scalable/"
    # links/ holds extra names as symlinks to src/ names (MacTahoe's installer puts both in one folder)
    for l in "$TMP/mt/links/$kind/scalable"/*.svg; do
        n=$(basename "$l"); t=$n
        for _ in 1 2 3 4; do [ -L "$TMP/mt/links/$kind/scalable/$t" ] && t=$(basename "$(readlink "$TMP/mt/links/$kind/scalable/$t")") || break; done
        [ -f "$T/$kind/scalable/$t" ] && [ ! -e "$T/$kind/scalable/$n" ] && cp "$T/$kind/scalable/$t" "$T/$kind/scalable/$n"
    done
done
cat > "$T/index.theme" <<'IDX'
[Icon Theme]
Name=FreeForm-Mac
Comment=macOS-style icons for FreeForm, from MacTahoe (GPL-3.0)
Inherits=hicolor
Directories=apps/scalable,places/scalable

[apps/scalable]
Size=128
MinSize=16
MaxSize=512
Context=Applications
Type=Scalable

[places/scalable]
Size=128
MinSize=16
MaxSize=512
Context=Places
Type=Scalable
IDX
cp "$TMP/mt/COPYING" "$T/COPYING"
echo "FreeForm-Mac: $(ls "$T/apps/scalable" | wc -l) app icons, $(ls "$T/places/scalable" | wc -l) place icons"
rm -rf "$TMP"

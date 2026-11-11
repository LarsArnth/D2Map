#!/bin/sh
# Pakker addon'en til en zip, som den skal se ud på CurseForge og i en
# GitHub-release: én mappe, D2Map/, med toc-filen i.
#
#   ./scripts/pak.sh        # skriver dist/D2Map-<version>.zip
#
# Versionen læses fra D2Map/D2Map.toc.
set -eu

rod="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^## Version: *//p' "$rod/D2Map/D2Map.toc" | tr -d '\r')"
if [ -z "$version" ]; then
    echo "Fandt ingen '## Version:' i D2Map.toc" >&2
    exit 1
fi

zip="$rod/dist/D2Map-$version.zip"
mkdir -p "$rod/dist"
rm -f "$zip"
# Licens og noter skal med i pakken; de ligger i roden og kopieres ind midlertidigt.
cp "$rod/LICENSE" "$rod/D2Map/LICENSE.txt"
cp "$rod/NOTICE.md" "$rod/D2Map/NOTICE.md"
(cd "$rod" && zip -r -q -X "$zip" D2Map -x "*.DS_Store")
rm -f "$rod/D2Map/LICENSE.txt" "$rod/D2Map/NOTICE.md"

echo "Skrev $zip"
unzip -l "$zip"

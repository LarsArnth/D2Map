#!/bin/sh
# Kopierer addon'en ind i spillets AddOns-mappe.
#
#   ./installer.sh                      # WoW: Forever på denne Mac
#   ./installer.sh "<sti til AddOns>"   # en anden klient
#
# Efter første installation skal spillet genstartes helt (en ny addon findes
# ikke af /reload). Ved senere opdateringer er /reload nok.
set -eu

her="$(cd "$(dirname "$0")" && pwd)"
addons="${1:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"

if [ ! -d "$addons" ]; then
    echo "Fandt ikke AddOns-mappen: $addons" >&2
    exit 1
fi

mkdir -p "$addons/D2Map"
rsync -a --delete --exclude ".DS_Store" "$her/D2Map/" "$addons/D2Map/"
echo "Installeret i $addons/D2Map:"
ls "$addons/D2Map"

#!/bin/bash
# GG Sicherung – Wiederherstellen. Überschreibt nie etwas: Ziel ist immer ein neuer, leerer Ordner.
#   wiederherstellen.sh liste
#   wiederherstellen.sh <neuester|JJJJ-MM-TT|Stand-ID> <ordner-oder-datei|alles> [ziel]
#   wiederherstellen.sh neuer-mac <github-name>     Tresor auf einen neuen Mac holen
set -u
source "$(dirname "$0")/lib.sh"

stop() { echo "❌ $1" >&2; exit 1; }

stand_finden() { # neuester | Datum | ID  →  Stand-ID
  case "$1" in
    neuester) echo latest ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      restic_ snapshots --json | python3 -c '
import json, sys, re
tag = sys.argv[1]
s = [x for x in json.load(sys.stdin) if x["time"][:10] <= tag]
print(max(s, key=lambda x: re.sub(r"\.\d+", "", x["time"]))["short_id"] if s else "")' "$1" ;;
    *) echo "$1" ;;
  esac
}

case "${1:-}" in
  liste)
    restic_ snapshots --compact || stop "Tresor nicht lesbar (Passwort im Schlüsselbund?)" ;;
  neuer-mac)
    name="${2:-}"; [ -n "$name" ] || stop "Bitte GitHub-Namen angeben: wiederherstellen.sh neuer-mac <name>"
    [ -e "$TRESOR" ] && stop "Auf diesem Mac gibt es schon einen Tresor ($TRESOR)"
    mkdir -p "$(dirname "$TRESOR")"
    NETZ_SEK=10800 netz git clone -q "${DATEN_REMOTE:-https://github.com/$name/gg-sicherung-daten.git}" "$TRESOR" \
      || { rm -rf "$TRESOR"; stop "Klonen fehlgeschlagen (bei GitHub angemeldet?)"; }
    git -C "$TRESOR" config user.name "GG Sicherung"; git -C "$TRESOR" config user.email "sicherung@localhost"
    if [ -n "${GGS_PASSWORT:-}" ]; then pw=$GGS_PASSWORT  # nur für test.sh
    else read -r -s -p "Sicherungs-Passwort (aus Apple Passwörter): " pw </dev/tty; echo; fi
    schluesselbund_setzen "$pw" || { rm -rf "$TRESOR"; stop "Passwort konnte nicht in den Schlüsselbund"; }
    restic_ snapshots --compact || { rm -rf "$TRESOR"; stop "Passwort passt nicht zum Tresor – einfach nochmal versuchen"; }
    echo "✅ Tresor da. Jetzt z. B.: wiederherstellen.sh neuester alles" ;;
  ""|-h|--hilfe)
    sed -n '2,5p' "$0" ;;
  *)
    [ $# -ge 2 ] || stop "Bitte Stand und Ordner angeben, z. B.: wiederherstellen.sh neuester alles"
    id=$(stand_finden "$1"); [ -n "$id" ] || stop "Kein Stand am oder vor $1"
    ziel="${3:-$HOME/Wiederhergestellt-$(date +%Y-%m-%d-%H%M)}"
    if [ -e "$ziel" ] && [ -n "$(ls -A "$ziel" 2>/dev/null)" ]; then stop "Ziel $ziel ist nicht leer – ich überschreibe nichts"; fi
    mkdir -p "$ziel"
    auswahl=(); [ "$2" = alles ] || auswahl=(--include "$2")
    restic_ restore "$id" --target "$ziel" ${auswahl[@]+"${auswahl[@]}"} || stop "Wiederherstellen fehlgeschlagen"
    [ -n "$(ls -A "$ziel")" ] || stop "Nichts gefunden für $2 in Stand $id"
    echo "✅ Wiederhergestellt nach: $ziel" ;;
esac

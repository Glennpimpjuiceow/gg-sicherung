#!/bin/bash
# GG Sicherung – Selbsttest nach jedem Update. Rot → aktualisieren.sh nimmt die alte Version zurück.
set -u
source "$(dirname "$0")/lib.sh" || { echo "lib.sh lässt sich nicht laden"; exit 1; }
for d in lib.sh sichern.sh wiederherstellen.sh aktualisieren.sh status.sh ausschluss.txt skill/sicherung/SKILL.md; do
  [ -f "$WERKZEUG/$d" ] || { echo "fehlt: $d"; exit 1; }
done
for s in "$WERKZEUG"/*.sh; do bash -n "$s" || { echo "Syntaxfehler: $s"; exit 1; }; done
"$RESTIC" version >/dev/null || { echo "restic läuft nicht"; exit 1; }
backup_argumente | grep -q -- '--files-from' || { echo "Sicherungs-Argumente kaputt"; exit 1; }
if [ -f "$TRESOR/config" ]; then
  restic_ cat config >/dev/null 2>&1 || { echo "Tresor mit dieser Version nicht lesbar"; exit 1; }
fi
echo "Selbsttest ok"

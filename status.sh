#!/bin/bash
# GG Sicherung – Zustand in einfachen Worten (für den Skill /sicherung und zum Selbst-Nachsehen).
set -u
source "$(dirname "$0")/lib.sh"

if [ -f "$STATUS" ]; then
  IFS='|' read -r ergebnis zeit text <"$STATUS"
  case "$ergebnis" in
    ok) echo "✅ Letzter Lauf $zeit: $text" ;;
    übersprungen) echo "⏳ Letzter Lauf $zeit: $text" ;;
    *) echo "❌ Letzter Lauf $zeit: $text" ;;
  esac
else
  echo "❌ Noch kein Lauf protokolliert"
fi

alter=$(neuester_stand_alter_min)
if [ -z "$alter" ]; then
  echo "❌ Kein Stand im Tresor lesbar (Passwort im Schlüsselbund?)"
elif [ "$alter" -gt "$MAX_ALTER_MIN" ]; then
  echo "❌ Neuester Stand ist $((alter / 60)) Std. alt – wahrscheinlich fehlt restic der Festplattenvollzugriff"
else
  echo "✅ Neuester Stand: vor $alter Min. · Stände gesamt: $(staende_zahl)"
fi

mb=$(du -sm "$TRESOR/.git" 2>/dev/null | cut -f1)
echo "ℹ️  Werkzeug-Version: $(cat "$VERSION_DATEI" 2>/dev/null || echo unbekannt) · Speicher: ${mb:-?} MB"
[ "${mb:-0}" -ge "$WARN_GROESSE_MB" ] && echo "⚠️  Sicherungsspeicher fast voll – bitte GG Digital Bescheid geben"
for job in de.ggdigital.sicherung de.ggdigital.sicherung-hochladen de.ggdigital.sicherung-update; do
  launchctl print "gui/$(id -u)/$job" >/dev/null 2>&1 || echo "❌ Zeitplan $job ist nicht aktiv"
done

#!/bin/bash
# GG Sicherung – einen Ordner oder eine Datei mit GG Digital teilen (nur auf ausdrücklichen Wunsch).
#   teilen.sh <ordner-oder-datei> [neuester|JJJJ-MM-TT|Stand-ID]
# Ohne Stand wird der aktuelle Inhalt geteilt, mit Stand die Fassung aus der Sicherung.
# Ergebnis: ein verschlüsseltes Mac-Paket (.dmg) auf dem Schreibtisch. Das Paket-Passwort erscheint
# nur in einem Fenster auf dem Bildschirm – nie in der Ausgabe, nie in einer Datei.
# Bekannte Zugangsdateien werden herausgefiltert; sieht ein Inhalt nach Schlüssel/Token aus, wird
# kein Paket gebaut. Passwörter in normalen Dokumenten (Excel, Notizen) erkennt das nicht.
set -u
umask 077
source "$(dirname "$0")/lib.sh"

ZIELORDNER="${ZIELORDNER:-$HOME/Desktop}"
FREIGABEN="${FREIGABEN:-$GGS_HOME/freigaben.log}"
MAX_MB="${MAX_MB:-500}"
# Groß/Klein egal (find -iname bzw. nocasematch)
GEHEIM_DATEIEN=('.env' '.env.*' '*.env' '.envrc' '.npmrc' '.netrc' '.pypirc' '.git-credentials' '.mcp.json'
  '.dev.vars' '.htpasswd' '.claude.json' '.credentials.json' 'credentials*' 'secrets*' 'service-account*'
  'settings.local.json' '*.pem' '*.p12' '*.pfx' '*.p8' '*.jks' '*.keystore' '*.kdbx' '*.keychain'
  '*.keychain-db' '*.ovpn' 'id_rsa*' 'id_ed25519*' 'id_ecdsa*' 'id_dsa*' '.pgpass' '.my.cnf' '.vault-token'
  '*.tfstate' '*.tfvars' 'wp-config.php' 'auth.json' '*.gpg' '.boto' '.s3cfg')
GEHEIM_ORDNER=('.ssh' '.aws' '.gnupg' '.kube' '.docker' '.gg-sicherung' '.git' 'Keychains')
UNNOETIG=('node_modules' '.next' '.venv' 'venv' '__pycache__' '.cache' '.DS_Store')
INHALT_MUSTER='-----BEGIN [A-Z ]*PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY BLOCK-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|xox[abpr]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|sk-proj-[A-Za-z0-9_-]{20,}|shp(at|ss|ca|pa)_[A-Za-z0-9]{20,}|(sk|rk)_live_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|whsec_[A-Za-z0-9]{16,}'
# Allgemeine Zuweisungen – Groß/Klein egal (API_KEY=…, SECRET_KEY = "…", Password: …, Authorization: Bearer …)
ALLGEMEIN_MUSTER='(api[_-]?key|secret|token|passw(or)?d|private[_-]?key)[A-Za-z_]*["'\'' ]*[=:]["'\'' ]*[A-Za-z0-9/+._-]{8,}|bearer [A-Za-z0-9._-]{12,}'

ziel=""; FERTIG=""; GERAET=""
loesen() { # trennt das zur Prüfung angehängte Paket – über das Gerät, nicht den Mountpoint
  [ -n "$GERAET" ] || return 0
  hdiutil detach -quiet "$GERAET" 2>/dev/null || { sleep 1; hdiutil detach -quiet -force "$GERAET" 2>/dev/null; } || return 1
  GERAET=""
}
aufraeumen() {
  loesen
  # Ein nicht fertig geprüftes Paket darf nicht liegen bleiben (es könnte sonst verschickt werden)
  [ -z "$FERTIG" ] && [ -n "$ziel" ] && rm -f "$ziel"
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}
stop() { echo "❌ $1" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ggs-teilen.XXXXXX") || { echo "❌ Kein Zwischenordner möglich" >&2; exit 1; }
trap aufraeumen EXIT

passt() { # <name> <muster…> – Groß/Klein egal
  local n=$1 m; shift; shopt -s nocasematch
  for m in "$@"; do [[ "$n" == $m ]] && { shopt -u nocasematch; return 0; }; done
  shopt -u nocasematch; return 1
}

quelle="${1:-}"; stand="${2:-}"
[ -n "$quelle" ] || { sed -n '2,8p' "$0"; exit 1; }
case "$quelle" in /*) ;; *) quelle="$PWD/$quelle" ;; esac
quelle_roh="${quelle%/}"   # so, wie die Sicherung den Pfad kennt (ohne Symlink-Auflösung)
# Echten Pfad bestimmen (.., Symlinks, ".") – bei einem früheren Stand darf er heute fehlen
if [ -d "$quelle" ]; then quelle=$(cd "$quelle" && pwd -P)
elif [ -d "$(dirname "$quelle")" ]; then quelle="$(cd "$(dirname "$quelle")" && pwd -P)/$(basename "$quelle")"
fi
quelle="${quelle%/}"; name=$(basename "$quelle")

# Geheime oder zu große Bereiche gar nicht erst annehmen
heim=$(cd "$HOME" && pwd -P)
case "$heim/" in "$quelle/"*) stop "Der ganze Benutzerordner (oder ein Ordner darüber) ist zu viel – bitte einen bestimmten Ordner wählen" ;; esac
case "$quelle" in
  "$heim/Library/Mobile Documents"/*) ;;
  "$heim/Library"|"$heim/Library"/*) stop "Systemordner (Library) werden nicht geteilt" ;;
esac
IFS='/' read -r -a teile <<<"${quelle#/}"
for t in "${teile[@]}"; do
  passt "$t" "${GEHEIM_ORDNER[@]}" && stop "$quelle liegt in einem geschützten Ordner ($t) – wird nicht geteilt"
done
passt "$name" "${GEHEIM_DATEIEN[@]}" && stop "$name ist eine Zugangsdatei – wird nicht geteilt"

if [ -n "$stand" ]; then
  for q in "$quelle_roh" "$quelle"; do
    rm -rf "$TMP/stand"
    if bash "$(dirname "$0")/wiederherstellen.sh" "$stand" "$q" "$TMP/stand" >/dev/null 2>&1; then herkunft="$TMP/stand$q"; break; fi
  done
  [ -n "${herkunft:-}" ] || stop "In der Sicherung ($stand) gibt es $quelle nicht"
else
  [ -e "$quelle" ] || stop "Gibt es nicht: $quelle"
  herkunft="$quelle"
fi

# Kopieren (Verknüpfungen nicht – sie zeigen auf fremde Orte), dann filtern, Groß/Klein egal
ausnahmen=(); for m in "${UNNOETIG[@]}"; do ausnahmen+=(--exclude "$m"); done
mkdir -p "$TMP/paket"
if [ -d "$herkunft" ]; then
  rsync -a --no-links --no-specials --no-devices "${ausnahmen[@]}" "$herkunft/" "$TMP/paket/$name/" || stop "Kopieren fehlgeschlagen"
else
  rsync -a --no-links --no-specials --no-devices "$herkunft" "$TMP/paket/" || stop "Kopieren fehlgeschlagen"
fi
such=(); for m in "${GEHEIM_ORDNER[@]}" "${UNNOETIG[@]}" "${GEHEIM_DATEIEN[@]}"; do such+=(-o -iname "$m"); done
find "$TMP/paket" -mindepth 1 \( "${such[@]:1}" \) -prune -print | sed "s#^$TMP/paket/##" >"$TMP/entfernt"
find "$TMP/paket" -mindepth 1 \( "${such[@]:1}" \) -prune -exec rm -rf {} +
[ -z "$(find "$TMP/paket" -mindepth 1 \( "${such[@]:1}" \) -print -quit)" ] || stop "Zugangsdateien ließen sich nicht entfernen – nichts geteilt"

# Inhalte, die nach Schlüssel oder Token aussehen: kein Paket ohne ausdrückliches Ja
# Zwei Suchen: feste Token-Präfixe genau (sonst Fehltreffer), allgemeine Zuweisungen ohne Groß/Klein.
# Exit 2 = Suche selbst kaputt → abbrechen, nie stillschweigend „nichts gefunden“.
{ LC_ALL=C grep -rlaE -D skip -- "$INHALT_MUSTER" "$TMP/paket"; r1=$?
  LC_ALL=C grep -rlaiE -D skip -- "$ALLGEMEIN_MUSTER" "$TMP/paket"; r2=$?; } >"$TMP/funde-roh" 2>/dev/null
[ "$r1" -le 1 ] && [ "$r2" -le 1 ] || stop "Inhaltsprüfung fehlgeschlagen – nichts geteilt"
sort -u "$TMP/funde-roh" | sed "s#^$TMP/paket/#   #" >"$TMP/funde"
if [ -s "$TMP/funde" ] && [ -z "${FUNDE_OK:-}" ]; then
  stop "Diese Dateien sehen nach Schlüsseln oder Zugangstokens aus – kein Paket gebaut:
$(cat "$TMP/funde")
   Bitte prüfen. Sollen sie wirklich mit, nochmal mit FUNDE_OK=1 davor."
fi

dateien=$(find "$TMP/paket" -type f | wc -l | tr -d ' ')
[ "$dateien" -gt 0 ] || stop "Nach dem Herausfiltern von Zugangsdaten bleibt nichts zum Teilen übrig"
mb=$(du -sm "$TMP/paket" | cut -f1)
if [ "$mb" -gt "$MAX_MB" ] && [ -z "${GROSS_OK:-}" ]; then
  stop "Das Paket wäre $mb MB groß. Wirklich so viel teilen? Dann nochmal mit GROSS_OK=1 davor."
fi
archive=$(find "$TMP/paket" -type f \( -iname '*.zip' -o -iname '*.7z' -o -iname '*.rar' -o -iname '*.tar' -o -iname '*.tgz' -o -iname '*.gz' \) | sed "s#^$TMP/paket/#   #")

# Nie überschreiben: bei gleichem Namen -2, -3, …
mkdir -p "$ZIELORDNER"
# Für Datei- und Fenstername: Zeilenumbrüche, / und : stören → _
paketname=$(printf '%s' "$name" | tr '\n\r/:' '____')
basis="$ZIELORDNER/GG-Freigabe-$paketname-$(date +%Y-%m-%d)"; n=2; kandidat="$basis.dmg"
while [ -e "$kandidat" ]; do kandidat="$basis-$n.dmg"; n=$((n + 1)); done

{ set +x; } 2>/dev/null   # das Passwort nie in einer Ablaufverfolgung
pw=$(passwort_neu)
[[ "$pw" =~ ^[a-zA-Z0-9]{5}(-[a-zA-Z0-9]{5}){5}$ ]] || stop "Passwort-Erzeugung fehlgeschlagen – nichts geteilt"
ziel=$kandidat
printf '%s' "$pw" | hdiutil create -quiet -srcfolder "$TMP/paket" -volname "GG-Freigabe-$paketname" \
  -encryption AES-256 -stdinpass "$ziel" || stop "Paket ließ sich nicht erstellen"

# Gegenprobe: mit dem Passwort öffnen und Inhalt vergleichen
mkdir -p "$TMP/pruef"
GERAET=$(printf '%s' "$pw" | hdiutil attach -stdinpass -nobrowse -readonly -mountpoint "$TMP/pruef" "$ziel" 2>/dev/null | awk '/^\/dev\/disk/ {print $1; exit}')
[ -n "$GERAET" ] || stop "Gegenprobe: Paket lässt sich nicht öffnen – nichts geteilt"
diff -rq -x .fseventsd -x .Trashes -x .Spotlight-V100 "$TMP/paket" "$TMP/pruef" >/dev/null 2>&1 \
  || stop "Gegenprobe: Paketinhalt weicht ab – nichts geteilt"
loesen || stop "Prüf-Paket ließ sich nicht trennen – nichts geteilt"

# Passwort nur auf dem Bildschirm zeigen (Fenster, optional in die Zwischenablage).
# Das Skript geht per Pipe an osascript: nicht in die Prozessliste, keine Tempdatei.
# Text für AppleScript absichern: erst Backslash, dann Anführungszeichen.
anzeige=${paketname//\\/\\\\}; anzeige=${anzeige//\"/\\\"}
fenster="set pw to \"$pw\"
set r to button returned of (display dialog \"Passwort für das Paket „${anzeige}“:\" & return & return & pw & return & return & \"Schicke es GETRENNT vom Paket an GG Digital (z. B. per WhatsApp).\" buttons {\"Fertig\", \"In Zwischenablage kopieren\"} default button 2 with title \"GG Sicherung – Freigabe\")
if r is \"In Zwischenablage kopieren\" then set the clipboard to pw"
printf '%s\n' "$fenster" | osascript - >/dev/null 2>&1 \
  || stop "Passwort-Fenster ließ sich nicht öffnen (nur am Mac-Bildschirm möglich) – nichts geteilt"
fenster=""
pw=""
FERTIG=1

mkdir -p "$(dirname "$FREIGABEN")"; touch "$FREIGABEN"; chmod 600 "$FREIGABEN"
printf '%s|%s|%s|%s Dateien|%s MB|%s\n' "$(date '+%Y-%m-%d %H:%M')" "$quelle" "${stand:-aktuell}" \
  "$dateien" "$mb" "$(basename "$ziel")" >>"$FREIGABEN"

echo "✅ Paket: $ziel  ($dateien Dateien, $mb MB)"
echo "🔑 Das Passwort wurde in einem Fenster angezeigt. Paket per WeTransfer, Passwort GETRENNT (z. B. WhatsApp) an GG Digital."
[ -s "$TMP/entfernt" ] && { echo "🛡  Nicht mitgepackt (Zugangsdaten bzw. unnötig):"; sed 's/^/   /' "$TMP/entfernt"; }
[ -s "$TMP/funde" ] && { echo "⚠️  Auf ausdrücklichen Wunsch mitgepackt, obwohl es nach Schlüsseln aussieht:"; cat "$TMP/funde"; }
[ -n "$archive" ] && printf '⚠️  Archive konnten nicht durchsucht werden:\n%s\n' "$archive"
echo "ℹ️  Passwörter in normalen Dokumenten (Excel, Notizen) erkennt das Werkzeug nicht – vor dem Senden kurz prüfen."
exit 0

#!/bin/bash
# GG Sicherung – Selbst-Update (läuft einmal täglich).
# Übernimmt die höchste Version, die (1) mit dem GG-Digital-Schlüssel signiert ist,
# (2) im signierten Tag denselben Namen trägt (kein umbenanntes altes Tag) und
# (3) auf der laufenden Version aufbaut (kein Zurückdrehen).
# Geprüft wird gegen die bei der Einrichtung abgelegte Vertrauensliste ($VERTRAUEN),
# nie gegen eine Liste aus der neuen Version. Selbsttest rot → zurück zur alten Version.
# Die laufende Version steht in $VERSION_DATEI – nie aus den (ungeprüften) Tags abgelesen.
set -u
source "$(dirname "$0")/lib.sh"

ABGELEHNT="$GGS_HOME/abgelehnt.txt"
abbruch() { log "Update: $1"; melden "$1"; sperre_frei; exit 1; }
# Abgelehnt wird der konkrete Tag-Inhalt (Objekt-ID), nicht der Name: ein echtes Release
# mit einem vorher gefälschten Namen wird so wieder geprüft. Abgelehnte Inhalte überspringt die
# Schleife danach (schon_abgelehnt) – so kommt jede Meldung nur einmal.
ablehnen() { # <text> <tag>
  log "Update: $1"
  git rev-parse "$2" >>"$ABGELEHNT" 2>/dev/null; melden "$1"
}
schon_abgelehnt() { grep -Fqx -- "$(git rev-parse "$1" 2>/dev/null)" "$ABGELEHNT" 2>/dev/null; }

geprueft() { # <tag> → 0, wenn alle drei Bedingungen erfüllt sind
  git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$VERTRAUEN" verify-tag "$1" >/dev/null 2>>"$LOG" || return 1
  [ "$(git cat-file tag "$1" | sed -n 's/^tag //p')" = "$1" ] || return 1
  git merge-base --is-ancestor HEAD "$1^{commit}"
}

hoeher() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

sperre_holen || exit 0
cd "$WERKZEUG" || abbruch "Werkzeug-Ordner fehlt"
grep -qv '^#' "$VERTRAUEN" 2>/dev/null || abbruch "Vertrauensliste fehlt – Updates gesperrt"
aktuell=$(cat "$VERSION_DATEI" 2>/dev/null) || abbruch "Versionsdatei fehlt – Updates gesperrt"

# Tags erzwingen: ein verschobenes Tag darf den Abruf nicht blockieren, geprüft wird ohnehin unten
netz git fetch -q origin '+refs/tags/*:refs/tags/*' 2>>"$LOG" || { log "Update: kein Netz, später"; sperre_frei; exit 0; }

neu=""
for tag in $(git tag -l 'v[0-9]*' | sort -V -r); do
  hoeher "$tag" "$aktuell" || break
  schon_abgelehnt "$tag" && continue
  if geprueft "$tag"; then neu=$tag; break; fi
  ablehnen "Update $tag ist nicht von GG Digital freigegeben – abgelehnt" "$tag"
done
[ -n "$neu" ] || { sperre_frei; exit 0; }

alt=$(git rev-parse HEAD)
git checkout -q --detach "$neu^{commit}" || abbruch "Update $neu ließ sich nicht auspacken"
if ! bash "$WERKZEUG/selbsttest.sh" >>"$LOG" 2>&1; then
  git checkout -q --detach "$alt" || abbruch "Update $neu fehlerhaft UND Rückweg gescheitert – bitte GG Digital anrufen"
  ablehnen "Update $neu fehlerhaft – alte Version $aktuell bleibt aktiv" "$neu"
  sperre_frei; exit 1
fi
echo "$neu" >"$VERSION_DATEI"
skill_aktualisieren
# Neue Sicherungs-Argumente (z. B. Ausschlüsse) erreichen den restic-Zeitplan nur, wenn er neu geschrieben wird
restic_zeitplan_schreiben || log "Update: restic-Zeitplan nicht neu ladbar"
log "Update: $aktuell → $neu"
sperre_frei

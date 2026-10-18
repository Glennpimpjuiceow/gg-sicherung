#!/bin/bash
# GG Sicherung – Einrichtung. Einmal im Terminal ausführen:  bash installieren.sh
# Richtet ein: Programme (geprüft), GitHub-Anmeldung, privaten verschlüsselten Speicher,
# Passwort im Schlüsselbund, ersten Lauf, Probe-Wiederherstellung, Zeitpläne, Skill /sicherung.
# Jeder Schritt ist wiederholbar: bricht etwas ab, macht ein Neustart dort weiter.
#   bash installieren.sh --neuer-mac   holt eine bestehende Sicherung auf einen neuen Mac
set -u
PAKET="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PAKET/lib.sh"

RESTIC_VERSION=0.19.1
RESTIC_SHA_arm64=7be0a144ccc377880f294204aa271d76e4b79554b42a751151d425ce6ebac143
RESTIC_SHA_amd64=c38d579622cf602f665234c5a8c315030b6cf70656028fe6dc29a786b60e5f35
GH_VERSION=2.102.0
GH_SHA_arm64=da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e
GH_SHA_amd64=b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3
WERKZEUG_REPO="${WERKZEUG_REPO:-Glennpimpjuiceow/gg-sicherung}"
WERKZEUG_URL="${WERKZEUG_URL:-https://github.com/$WERKZEUG_REPO.git}"
PAKET_VERTRAUEN="${PAKET_VERTRAUEN:-$PAKET/vertrauen/allowed_signers}"
DATEN_NAME=gg-sicherung-daten
GH="${GH:-$GGS_HOME/bin/gh}"
EINGABE="${EINGABE:-/dev/tty}"   # Antworten kommen von der Tastatur (test.sh: aus einer Datei)
PROBE="$GGS_KONFIG/probe.txt"

AUFRAEUMEN=()
trap '[ ${#AUFRAEUMEN[@]} -gt 0 ] && rm -rf "${AUFRAEUMEN[@]}"' EXIT
tmpdir() { TMPV=$(mktemp -d); AUFRAEUMEN+=("$TMPV"); }   # ohne $( ), sonst geht der Eintrag verloren

schritt() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
stop() { printf '\n❌ %s\n   Einfach „bash installieren.sh“ neu starten – es macht dort weiter, wo es aufgehört hat.\n' "$1" >&2; exit 1; }
eingabe_oeffnen() { exec 3<"$EINGABE"; }   # einmal öffnen, damit jede Frage die nächste Antwort liest
frage_ja() { local a; read -r -p "$1 [j/n] " a <&3; [ "$a" = j ] || [ "$a" = J ]; }
eingabe() { read -r -p "$1" "$2" <&3; }

arch() { [ "$(uname -m)" = arm64 ] && echo arm64 || echo amd64; }

laden_geprueft() { # <url> <sha256> <datei>
  netz curl -fsSL "$1" -o "$3" || return 1
  [ "$(shasum -a 256 "$3" | cut -d' ' -f1)" = "$2" ] || { rm -f "$3"; return 2; }
}

programme() {
  schritt "1/9 Programme prüfen"
  [ "$(uname)" = Darwin ] || stop "Nur für Mac gedacht"
  xcode-select -p >/dev/null 2>&1 || { xcode-select --install 2>/dev/null; stop "Bitte zuerst die Apple-Entwicklerwerkzeuge installieren (Fenster ist aufgegangen)"; }
  # SSH-Signaturen kann git erst ab 2.34
  printf '2.34\n%s\n' "$(git --version | cut -d' ' -f3)" | sort -V -C || stop "git ist zu alt – bitte macOS-Updates installieren"
  mkdir -p "$GGS_HOME/bin"
  local a tmp sha_var; a=$(arch); tmpdir; tmp=$TMPV
  if ! "$RESTIC" version >/dev/null 2>&1; then
    sha_var="RESTIC_SHA_$a"
    laden_geprueft "https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_darwin_$a.bz2" "${!sha_var}" "$tmp/r.bz2" \
      || stop "restic-Download fehlgeschlagen oder Fingerabdruck falsch"
    bunzip2 -c "$tmp/r.bz2" >"$RESTIC" && chmod 755 "$RESTIC"
  fi
  if ! "$GH" --version >/dev/null 2>&1; then
    sha_var="GH_SHA_$a"
    laden_geprueft "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_macOS_$a.zip" "${!sha_var}" "$tmp/gh.zip" \
      || stop "gh-Download fehlgeschlagen oder Fingerabdruck falsch"
    unzip -q "$tmp/gh.zip" -d "$tmp" && cp "$tmp"/gh_*/bin/gh "$GH" && chmod 755 "$GH"
  fi
  echo "✅ restic $("$RESTIC" version | cut -d' ' -f2), gh $("$GH" --version | head -1 | cut -d' ' -f3)"
}

github() {
  schritt "2/9 Bei GitHub anmelden"
  if ! "$GH" auth status >/dev/null 2>&1; then
    echo "Gleich öffnet sich der Browser. Code bestätigen, mit deinem GitHub-Konto anmelden."
    "$GH" auth login --web --git-protocol https || stop "GitHub-Anmeldung abgebrochen"
  fi
  "$GH" auth setup-git >/dev/null || stop "GitHub-Anmeldung für git nicht einrichtbar"
  KONTO=$("$GH" api user -q .login) || stop "GitHub-Konto nicht lesbar"
  echo "✅ Angemeldet als $KONTO"
}

werkzeug() {
  schritt "3/9 Werkzeug holen (nur von GG Digital signierte Version)"
  # Der Vertrauensanker wird nur beim allerersten Mal gesetzt, nie bei einem Neustart ersetzt
  if [ ! -s "$VERTRAUEN" ]; then
    grep -qv '^#' "$PAKET_VERTRAUEN" 2>/dev/null || stop "Vertrauensliste im Paket fehlt oder ist leer"
    mkdir -p "$(dirname "$VERTRAUEN")"; cp "$PAKET_VERTRAUEN" "$VERTRAUEN"
  fi
  if [ ! -d "$WERKZEUG/.git" ]; then
    netz git clone -q "$WERKZEUG_URL" "$WERKZEUG" \
      || { rm -rf "$WERKZEUG"; stop "Werkzeug nicht ladbar – hat GG Digital dich schon eingeladen? (Mail von GitHub annehmen)"; }
  fi
  # Höchste Version, die echt signiert ist und ihren Namen trägt (ungeprüfte Tags blockieren nicht)
  local tag gefunden=""
  for tag in $(git -C "$WERKZEUG" tag -l 'v[0-9]*' | sort -V -r); do
    if git -C "$WERKZEUG" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$VERTRAUEN" verify-tag "$tag" >/dev/null 2>&1 \
      && [ "$(git -C "$WERKZEUG" cat-file tag "$tag" | sed -n 's/^tag //p')" = "$tag" ]; then gefunden=$tag; break; fi
  done
  [ -n "$gefunden" ] || stop "Keine von GG Digital signierte Version gefunden – Abbruch"
  git -C "$WERKZEUG" checkout -q --detach "$gefunden^{commit}" || stop "Version $gefunden ließ sich nicht auspacken"
  echo "$gefunden" >"$VERSION_DATEI"
  echo "✅ Version $gefunden geprüft"
}

pfade() {
  schritt "4/9 Was soll gesichert werden?"
  if [ -s "$PFADE" ]; then echo "✅ Auswahl von vorhin:"; sed 's/^/   /' "$PFADE"; return 0; fi
  mkdir -p "$GGS_KONFIG"
  local liste=("$HOME/.claude" "$GGS_KONFIG") gefunden=() v o
  [ -f "$HOME/.claude.json" ] && liste+=("$HOME/.claude.json")
  echo "Immer dabei: deine Claude-Einstellungen, Skills und Erinnerungen."
  while IFS= read -r v; do gefunden+=("$(dirname "$v")"); done < <(
    { find "$HOME/Documents" "$HOME/Desktop" -maxdepth 4 -type d -name .obsidian 2>/dev/null
      find "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents" -maxdepth 2 -type d -name .obsidian 2>/dev/null; } | sort -u)
  for v in ${gefunden[@]+"${gefunden[@]}"}; do frage_ja "Obsidian-Vault sichern: $v ?" && liste+=("$v"); done
  for o in "$HOME/Documents" "$HOME/Desktop"; do
    [ -d "$o" ] && frage_ja "Ganzen Ordner $o sichern (ohne Videos/Riesendateien)?" && liste+=("$o")
  done
  echo "Weitere Ordner? Pfad eingeben (z. B. ~/Projekte), leer lassen zum Beenden:"
  while eingabe "> " v && [ -n "$v" ]; do
    v="${v/#\~/$HOME}"; v="${v%/}"   # Tab-Vervollständigung hängt oft ein / an
    if [ -e "$v" ]; then liste+=("$v"); else echo "   gibt es nicht: $v"; fi
  done
  printf '%s\n' "${liste[@]}" | awk '!s[$0]++' >"$PFADE"
  # Immer anlegen, damit der Zeitplan sie von Anfang an kennt (später ergänzte Ausnahmen wirken sofort)
  [ -f "$AUSSCHLUSS_EIGEN" ] || echo "# Eigene Ausnahmen, ein Muster pro Zeile (z. B. *.iso oder ~/Downloads)" >"$AUSSCHLUSS_EIGEN"
  echo "✅ Gesichert wird:"; sed 's/^/   /' "$PFADE"
}

speicher() {
  schritt "5/9 Privaten Speicher bei GitHub anlegen"
  DATEN_REMOTE="${DATEN_REMOTE:-https://github.com/$KONTO/$DATEN_NAME.git}"
  if [ -z "${GGS_OHNE_GH:-}" ]; then   # GGS_OHNE_GH: nur test.sh (lokales Remote statt GitHub)
    if "$GH" repo view "$KONTO/$DATEN_NAME" >/dev/null 2>&1; then
      :
    else
      "$GH" repo create "$DATEN_NAME" --private --description "GG Sicherung (verschlüsselt)" >/dev/null || stop "Speicher nicht anlegbar"
    fi
    [ "$("$GH" repo view "$KONTO/$DATEN_NAME" --json visibility -q .visibility)" = PRIVATE ] || stop "Speicher ist nicht privat – Abbruch"
  fi
  # Weitermachen ist nur sicher, wenn der Speicher leer ist oder zu genau diesem Tresor gehört
  local fern; fern=$(netz git ls-remote "$DATEN_REMOTE" 2>/dev/null) || stop "Speicher nicht erreichbar"
  if [ -n "$fern" ] && [ "$(git -C "$TRESOR" remote get-url origin 2>/dev/null)" != "$DATEN_REMOTE" ]; then
    stop "Im Speicher liegt schon eine Sicherung von einem anderen Mac. Neuer Mac? Dann: bash installieren.sh --neuer-mac"
  fi
  echo "✅ $DATEN_REMOTE (privat)"
}

passwort_neu() { # 6 Blöcke à 5 Zeichen, ohne verwechselbare Zeichen
  LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyzACDEFHJKLMNPRTUVWXY34679' </dev/urandom | head -c 30 | sed 's/.\{5\}/&-/g; s/-$//'
}

passwort() {
  schritt "6/9 Sicherungs-Passwort"
  # Gibt es den Tresor schon, gehört das Passwort im Schlüsselbund zu ihm – nie ersetzen
  if [ -f "$TRESOR/config" ]; then echo "✅ Passwort ist schon eingerichtet"; return 0; fi
  local pw; pw="${GGS_PASSWORT:-$(passwort_neu)}"   # GGS_PASSWORT: nur test.sh
  schluesselbund_setzen "$pw" || stop "Passwort konnte nicht in den Schlüsselbund"
  cat <<EOF

   ┌──────────────────────────────────────────────┐
     $pw
   └──────────────────────────────────────────────┘
   WICHTIG: Ohne dieses Passwort ist die Sicherung wertlos – niemand kann es
   wiederherstellen, auch GG Digital nicht. Jetzt in „Passwörter“ (Apple) als
   neuen Eintrag „GG Sicherung“ speichern.
EOF
  local zurueck
  while :; do
    eingabe "   Zur Kontrolle einmal abtippen: " zurueck || stop "Keine Eingabe – Passwort nicht bestätigt"
    [ "$zurueck" = "$pw" ] && break
    echo "   Stimmt nicht überein – bitte nochmal."
  done
  printf '\033[2J\033[3J\033[H'; echo "✅ Passwort gesichert (Bildschirm und Verlauf geleert)"
}

tresor() {
  schritt "7/9 Verschlüsselten Tresor anlegen und erste Sicherung"
  if [ ! -f "$TRESOR/config" ]; then
    # Nie löschen: ein Ordner ohne restic-config kann eine beschädigte, echte Sicherung sein
    [ -n "$(ls -A "$TRESOR" 2>/dev/null)" ] && stop "Der Tresor-Ordner $TRESOR ist unvollständig – bitte GG Digital Bescheid geben, nichts löschen"
    restic_ init >/dev/null || stop "Tresor nicht anlegbar"
  fi
  if [ ! -d "$TRESOR/.git" ]; then
    (cd "$TRESOR" && git init -q && git symbolic-ref HEAD refs/heads/main && printf 'locks/\n' >.gitignore \
      && git config user.name "GG Sicherung" && git config user.email "sicherung@localhost" \
      && git remote add origin "$DATEN_REMOTE") || stop "git im Tresor"
  fi
  head -c 32 /dev/urandom | shasum -a 256 | cut -d' ' -f1 >"$PROBE"
  echo "Sicherung läuft – beim ersten Mal je nach Datenmenge bis zu einer Stunde …"
  bash "$WERKZEUG/sichern.sh" jetzt || stop "Sicherung fehlgeschlagen: $(cut -d'|' -f3 "$STATUS")"
  echo "✅ $(cut -d'|' -f3 "$STATUS")"
}

probe() {
  schritt "8/9 Probe: Wiederherstellen aus GitHub"
  local tmp; tmpdir; tmp=$TMPV
  NETZ_SEK=10800 netz git clone -q "$DATEN_REMOTE" "$tmp/klon" || stop "Probe: Speicher nicht klonbar"
  TRESOR="$tmp/klon" bash "$WERKZEUG/wiederherstellen.sh" neuester "$PROBE" "$tmp/ziel" >/dev/null || stop "Probe-Wiederherstellung fehlgeschlagen"
  cmp -s "$PROBE" "$tmp/ziel$PROBE" || stop "Probe: wiederhergestellte Datei weicht ab"
  echo "✅ Probe bestanden: eine Prüfdatei kam aus GitHub unverändert zurück"
}

zeitplaene() {
  schritt "9/9 Zeitpläne und Skill einrichten"
  restic_zeitplan_schreiben || stop "Zeitplan für restic nicht startbar"
  plist de.ggdigital.sicherung-hochladen stunden 45 "$LOG" /bin/bash "$WERKZEUG/sichern.sh"
  zeitplan_laden de.ggdigital.sicherung-hochladen || stop "Zeitplan zum Hochladen nicht startbar"
  plist de.ggdigital.sicherung-update täglich 30 "$LOG" /bin/bash "$WERKZEUG/aktualisieren.sh"
  zeitplan_laden de.ggdigital.sicherung-update || stop "Zeitplan für Updates nicht startbar"
  skill_aktualisieren || echo "⚠️  Es gibt schon einen anderen Skill „sicherung“ – nicht überschrieben."
  echo "✅ Sichert alle 3 Stunden, sucht täglich nach Updates. In Claude: /sicherung"
}

# Vergleicht zwei Stände Ordner für Ordner: hatte der Vergleichsstand (aus dem Terminal, mit
# Zugriff) Inhalt und der neue (Hintergrund-Lauf) keinen, fehlt der Zugriff. Ordner, die nur
# Ausgeschlossenes enthalten, sind in beiden leer und lösen keinen Alarm aus.
alle_pfade_im_stand() { # <vergleichs-stand> <neuer-stand>
  local p alt neu
  while IFS= read -r p; do
    p="${p%/}"
    alt=$(restic_ ls "$1" "$p" 2>/dev/null | grep -c "^$p/")
    neu=$(restic_ ls "$2" "$p" 2>/dev/null | grep -c "^$p/")
    if [ "$alt" -gt 0 ] && [ "$neu" = 0 ]; then echo "$p"; return 1; fi
  done <"$PFADE"
}
stand_id() { restic_ snapshots --json --latest 1 2>/dev/null | python3 -c 'import json,sys; s=json.load(sys.stdin); print(s[-1]["id"] if s else "")'; }

vollzugriff() {
  schritt "Letzter Schritt: Festplattenvollzugriff für restic"
  cat <<EOF
   macOS lässt Hintergrund-Programme nicht in „Dokumente“, „Schreibtisch“ und iCloud schauen.
   Gleich öffnen sich zwei Fenster:
     1. Systemeinstellungen → Datenschutz → Festplattenvollzugriff
     2. Ein Finder-Fenster, in dem „restic“ markiert ist
   Ziehe „restic“ aus dem Finder in die Liste und schalte es ein.
EOF
  eingabe "   Enter drücken zum Öffnen … " _
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"; open -R "$RESTIC"
  eingabe "   Erledigt? Enter drücken – ich prüfe es mit einem echten Hintergrund-Lauf … " _
  rm -f "$RESTIC_LOG"
  local vorher i fehlt vergleich; vorher=$(staende_zahl); vergleich=$(stand_id)
  launchctl kickstart "gui/$(id -u)/de.ggdigital.sicherung" || stop "Hintergrund-Lauf nicht startbar"
  for i in $(seq 1 720); do
    sleep 5; launchctl print "gui/$(id -u)/de.ggdigital.sicherung" | grep -q 'state = running' || break
  done
  [ "$(staende_zahl)" -gt "$vorher" ] || stop "Der Hintergrund-Lauf hat keinen neuen Stand gespeichert – Protokoll: $RESTIC_LOG"
  grep -qi "operation not permitted" "$RESTIC_LOG" 2>/dev/null \
    && stop "restic hat noch keinen Festplattenvollzugriff – Schalter prüfen"
  fehlt=$(alle_pfade_im_stand "$vergleich" "$(stand_id)") || stop "Im Hintergrund-Lauf fehlt der Inhalt von $fehlt – Festplattenvollzugriff prüfen"
  bash "$WERKZEUG/sichern.sh" || stop "Hochladen nach dem Hintergrund-Lauf fehlgeschlagen"
  echo "✅ Hintergrund-Lauf mit Vollzugriff funktioniert, alle Ordner sind drin"
}

neuer_mac() {
  schritt "Neuer Mac: Tresor aus GitHub holen"
  export DATEN_REMOTE="${DATEN_REMOTE:-https://github.com/$KONTO/$DATEN_NAME.git}"
  if [ ! -f "$TRESOR/config" ]; then
    bash "$WERKZEUG/wiederherstellen.sh" neuer-mac "$KONTO" || stop "Tresor nicht geholt"
  fi
  local ziel; ziel="$HOME/Wiederhergestellt-$(date +%Y-%m-%d-%H%M)"
  bash "$WERKZEUG/wiederherstellen.sh" neuester alles "$ziel" || stop "Zurückholen fehlgeschlagen"
  # Die Einstellungen liegen unter dem alten Home-Pfad – bei anderem Benutzernamen umschreiben
  local alt; alt=$(find "$ziel" -path '*/.config/gg-sicherung/pfade.txt' 2>/dev/null | head -1)
  [ -n "$alt" ] || stop "Einstellungen nicht im Stand gefunden"
  local alt_home; alt_home=${alt#"$ziel"}; alt_home=${alt_home%/.config/gg-sicherung/pfade.txt}
  mkdir -p "$GGS_KONFIG"
  cp "$(dirname "$alt")"/* "$GGS_KONFIG/"
  echo "$alt_home" >"$GGS_HOME/alter-home"
  pfade_umschreiben
  # Zeitpläne erst nach dem Zurücksortieren – sonst entstünde ein fast leerer neuester Stand
  printf '\n🎉 Alles liegt in %s (mit den Originalpfaden darunter).\n   1. An die richtigen Orte zurückschieben (am besten zusammen mit GG Digital).\n   2. Danach: bash installieren.sh --fortsetzen\n' "$ziel"
}

# Pfade vom alten auf den neuen Home-Ordner umschreiben. Läuft bei --neuer-mac und nochmal bei
# --fortsetzen: beim Zurücksortieren landet oft auch die alte Einstellungsdatei wieder an ihrem Platz.
pfade_umschreiben() {
  local alt_home; alt_home=$(cat "$GGS_HOME/alter-home" 2>/dev/null) || return 0
  [ "$alt_home" = "$HOME" ] && return 0
  sed -i '' "s#^$alt_home/#$HOME/#; s#^$alt_home\$#$HOME#" "$PFADE"
}

fortsetzen() {
  schritt "Sicherung auf dem neuen Mac wieder einschalten"
  pfade_umschreiben
  local p fehlt=""
  while IFS= read -r p; do [ -e "$p" ] || fehlt="$fehlt\n   $p"; done <"$PFADE"
  [ -z "$fehlt" ] || stop "Diese Ordner sind noch nicht zurück:$(printf "$fehlt")"
  zeitplaene
  [ -n "${GGS_OHNE_LAUNCHD:-}" ] || vollzugriff
  echo "✅ Sicherung läuft wieder"
}

haupt() {
  echo "GG Sicherung – Einrichtung"
  eingabe_oeffnen
  if [ "${1:-}" = --neuer-mac ]; then programme; github; werkzeug; neuer_mac; return; fi
  if [ "${1:-}" = --fortsetzen ]; then fortsetzen; return; fi
  programme; github; werkzeug; pfade; speicher; passwort; tresor; probe; zeitplaene; vollzugriff
  printf '\n🎉 Fertig. Deine Daten werden ab jetzt alle 3 Stunden verschlüsselt gesichert.\n   Zustand ansehen: in Claude „/sicherung“ oder  bash %s/status.sh\n' "$WERKZEUG"
}

[ -n "${GGS_NUR_LADEN:-}" ] || haupt "$@"

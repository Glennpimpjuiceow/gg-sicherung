#!/bin/bash
# GG Sicherung – Testreihe. Läuft komplett lokal: git-Remotes sind Ordner, kein GitHub,
# Schlüsselbund und launchd werden nie angefasst (Ersatz-Befehl für `security`).
#   RESTIC_BIN=/pfad/zu/restic bash test.sh              alle Tests
#   RESTIC_BIN=/pfad/zu/restic bash test.sh --mutation   jede Schutzzeile einzeln ausbauen → muss rot werden
#   MUTATIONEN=datei …  --mutation                         nur diese Mutationen
set -u
QUELLE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$QUELLE}"
: "${RESTIC_BIN:?RESTIC_BIN auf ein restic-Programm setzen}"
ROT=0; GRUEN=0; ORDNER=()
aufraeumen_test() {
  [ ${#ORDNER[@]} -gt 0 ] || return 0
  local o d
  # eingehängte Testpakete zuerst lösen, sonst bleiben sie nach rm -rf im System hängen
  for o in "${ORDNER[@]}"; do
    # Paket erkennen am Einhängepunkt ODER am Ort der .dmg-Datei (ein kaputtes Skript hängt sie woanders ein)
    hdiutil info | awk -v o="$o" '/^image-path/ {img = (index($0, o) || index($0, "/private" o))}
      /^\/dev\/disk/ && (img || index($0, o) || index($0, "/private" o)) {print $1}' | sort -u | while read -r d; do hdiutil detach -quiet -force "$d" 2>/dev/null; done
  done
  rm -rf "${ORDNER[@]}"
}
trap aufraeumen_test EXIT
erg() { if [ "$2" = 0 ]; then GRUEN=$((GRUEN + 1)); else ROT=$((ROT + 1)); echo "  ROT: $1"; fi; }
ja() { "$@" >/dev/null 2>&1; echo $?; }
nein() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }
git_() { git -c user.name=t -c user.email=t@t "$@"; }

neu() {
  T=$(mktemp -d); ORDNER+=("$T"); export HOME="$T/home"; mkdir -p "$HOME" "$T/bin"
  export GGS_HOME="$HOME/.gg-sicherung" GGS_KONFIG="$HOME/.config/gg-sicherung"
  export WERKZEUG="$SRC" TRESOR="$HOME/.gg-sicherung/tresor" RESTIC="$RESTIC_BIN"
  export VERTRAUEN="$GGS_HOME/vertrauen/allowed_signers" STATUS="$GGS_HOME/status.txt" VERSION_DATEI="$GGS_HOME/version"
  export PRUEF_ANTEIL=100%
  export LOG="$GGS_HOME/protokoll.log" RESTIC_LOG="$GGS_HOME/restic.log"
  export PFADE="$GGS_KONFIG/pfade.txt" AUSSCHLUSS_EIGEN="$GGS_KONFIG/ausschluss-eigen.txt"
  export PASSWORT_BEFEHL="echo test-passwort-123" MELDEN=aus MAX_ALTER_MIN=240 WARN_GROESSE_MB=700
  export GGS_OHNE_GH=1 GGS_OHNE_LAUNCHD=1 AGENTS="$T/agents"
  unset DATEN_REMOTE GGS_PASSWORT EINGABE
  # Ersatz für den Schlüsselbund: merkt sich das Passwort in einer Datei
  printf '#!/bin/bash\nsed -n '\''s/.* -w "\\(.*\\)"$/\\1/p'\'' > "%s/pw"\n' "$T" >"$T/bin/security"; chmod +x "$T/bin/security"
  export SECURITY="$T/bin/security"
  mkdir -p "$GGS_HOME" "$GGS_KONFIG" "$HOME/.claude/debug" "$HOME/Documents/Vault/node_modules" "$HOME/Documents/Projekt"
  echo "GEHEIMSATZ-4711 Stand v1" >"$HOME/Documents/Vault/Notiz.md"
  echo "# Regeln" >"$HOME/.claude/CLAUDE.md"
  echo "debug" >"$HOME/.claude/debug/x.txt"
  mkdir -p "$HOME/.claude/projects/p"; echo '{"mitschrift":1}' >"$HOME/.claude/projects/p/sitzung.jsonl"
  echo '{"kunde":1}' >"$HOME/Documents/Projekt/kunden.jsonl"
  echo "modul" >"$HOME/Documents/Vault/node_modules/x.js"
  echo "API_KEY=abc" >"$HOME/Documents/Projekt/.env"
  echo "film" >"$HOME/Documents/Projekt/clip.mp4"
  echo "sperre" >"$HOME/Documents/Projekt/~\$lock.docx"
  mkfile -n 51m "$HOME/Documents/Projekt/riesig.bin"
  printf '%s\n' "$HOME/.claude" "$HOME/Documents" "$GGS_KONFIG" >"$PFADE"
  git init -q --bare "$T/remote.git"
}

installer() { # <funktionen…> – Teile von installieren.sh im Unterprozess
  (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; KONTO=test; DATEN_REMOTE="${DATEN_REMOTE:-$T/remote.git}"
   [ -n "${EINGABE:-}" ] && eingabe_oeffnen; for f in "$@"; do $f || exit 1; done) >/dev/null 2>&1
}
einrichten() { installer tresor; }
restic_t() { "$RESTIC" --repo "$TRESOR" --password-command "$PASSWORT_BEFEHL" "$@"; }

klartext_treffer() { # <bare-repo> → Zahl der Blobs mit dem Geheimsatz
  local n=0 o
  for o in $(git --git-dir="$1" rev-list --objects --all | awk '{print $1}'); do
    [ "$(git --git-dir="$1" cat-file -t "$o")" = blob ] || continue
    git --git-dir="$1" cat-file -p "$o" | grep -q GEHEIMSATZ && n=$((n + 1))
  done
  echo $n
}

t_sichern() {
  neu; einrichten; erg "Einrichtung + erste Sicherung" $?
  erg "Status ok" "$(ja grep -q '^ok|' "$STATUS")"
  erg "GitHub-Stand = lokaler Stand" "$([ "$(git --git-dir="$T/remote.git" rev-parse main 2>/dev/null)" = "$(git -C "$TRESOR" rev-parse HEAD)" ]; echo $?)"
  erg "Tresor auf GitHub ohne Klartext" "$([ "$(klartext_treffer "$T/remote.git")" = 0 ]; echo $?)"
  erg "Tresor auf GitHub ohne Dateinamen" "$(nein grep -qi 'notiz\|vault\|claude' <<<"$(git --git-dir="$T/remote.git" ls-tree -r --name-only main)")"
  # Gegenprobe: dieselbe Datei unverschlüsselt muss gefunden werden, sonst taugt die Suche nichts
  git init -q --bare "$T/kontrolle.git"; git_ -C "$HOME/Documents/Vault" init -q
  git_ -C "$HOME/Documents/Vault" add Notiz.md; git_ -C "$HOME/Documents/Vault" commit -qm k
  git -C "$HOME/Documents/Vault" push -q "$T/kontrolle.git" HEAD:main; rm -rf "$HOME/Documents/Vault/.git"
  erg "Gegenprobe: Klartextsuche findet unverschlüsselte Datei" "$([ "$(klartext_treffer "$T/kontrolle.git")" -ge 1 ]; echo $?)"

  local inhalt; inhalt=$(restic_t ls latest 2>/dev/null)
  erg "Notiz gesichert" "$(ja grep -q 'Vault/Notiz.md$' <<<"$inhalt")"
  erg ".env gesichert (Tresor ist verschlüsselt)" "$(ja grep -q 'Projekt/.env$' <<<"$inhalt")"
  erg "Einstellungen gesichert" "$(ja grep -q 'gg-sicherung/pfade.txt$' <<<"$inhalt")"
  erg "node_modules ausgeschlossen" "$(nein grep -q node_modules <<<"$inhalt")"
  erg "Video ausgeschlossen" "$(nein grep -q 'clip.mp4' <<<"$inhalt")"
  erg "Office-Sperrdatei ausgeschlossen" "$(nein grep -q 'lock.docx' <<<"$inhalt")"
  erg "Datei > 50 MB ausgeschlossen" "$(nein grep -q 'riesig.bin' <<<"$inhalt")"
  erg "Claude-debug ausgeschlossen (\$HOME im Muster)" "$(nein grep -q '.claude/debug' <<<"$inhalt")"
  erg "Claude-Mitschriften ausgeschlossen" "$(nein grep -q 'sitzung.jsonl' <<<"$inhalt")"
  erg "Kunden-jsonl gesichert" "$(ja grep -q 'Projekt/kunden.jsonl$' <<<"$inhalt")"

  echo "eigen" >"$HOME/Documents/Projekt/privat.txt"; echo "privat.txt" >"$AUSSCHLUSS_EIGEN"
  echo "$HOME" >>"$PFADE"   # jemand wählt den ganzen Home-Ordner
  bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  inhalt=$(restic_t ls latest 2>/dev/null)
  erg "eigener Ausschluss wirkt" "$(nein grep -q 'privat.txt' <<<"$inhalt")"
  erg "Tresor sichert sich nicht selbst" "$(nein grep -q '.gg-sicherung/tresor' <<<"$inhalt")"
}

t_wiederherstellen() {
  neu; einrichten
  local erster; erster=$(restic_t snapshots --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["short_id"])')
  echo "GEHEIMSATZ-4711 Stand v2" >"$HOME/Documents/Vault/Notiz.md"
  bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  local n="$HOME/Documents/Vault/Notiz.md" w="$SRC/wiederherstellen.sh"
  bash "$w" "$erster" "$n" "$T/z1" >/dev/null 2>&1
  erg "alter Stand per ID → v1" "$(ja grep -q 'v1' "$T/z1$n")"
  bash "$w" neuester "$n" "$T/z2" >/dev/null 2>&1
  erg "neuester Stand → v2" "$(ja grep -q 'v2' "$T/z2$n")"
  bash "$w" "$(date +%Y-%m-%d)" "$n" "$T/z3" >/dev/null 2>&1
  erg "Datum heute → letzter Stand des Tages (v2)" "$(ja grep -q 'v2' "$T/z3$n")"
  erg "Datum vor allen Ständen → Abbruch" "$(nein bash "$w" 2000-01-01 "$n" "$T/z4")"
  mkdir -p "$T/voll"; echo bleibt >"$T/voll/a.txt"
  erg "volles Ziel → Abbruch" "$(nein bash "$w" neuester "$n" "$T/voll")"
  erg "volles Ziel unverändert" "$([ "$(ls -A "$T/voll")" = a.txt ] && grep -q bleibt "$T/voll/a.txt"; echo $?)"
  erg "unbekannter Pfad → Abbruch" "$(nein bash "$w" neuester /gibt/es/nicht "$T/z5")"
  erg "alles wiederherstellen" "$(bash "$w" neuester alles "$T/z6" >/dev/null 2>&1 && grep -q v2 "$T/z6$n"; echo $?)"
  echo "abc" >"$GGS_KONFIG/probe.txt"; bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  erg "Installer-Probe aus Remote" "$(installer probe; echo $?)"
  echo "nach der Sicherung geändert" >"$GGS_KONFIG/probe.txt"
  erg "Installer-Probe erkennt Abweichung" "$(installer probe && echo 1 || echo 0)"
}

t_fehlerfaelle() {
  neu; einrichten
  touch "$TRESOR/locks/abc"
  bash "$SRC/sichern.sh" >/dev/null 2>&1
  erg "restic arbeitet → übersprungen" "$(ja grep -q '^übersprungen|' "$STATUS")"
  touch -t 202001010000 "$TRESOR/locks/abc"
  bash "$SRC/sichern.sh" >/dev/null 2>&1
  erg "verwaistes Schloss → aufgeräumt und hochgeladen" "$(ja grep -q '^ok|' "$STATUS")"
  rm -f "$TRESOR/locks/abc"

  git -C "$TRESOR" remote set-url origin "$T/gibtsnicht.git"
  erg "Push scheitert → Fehler-Code" "$(nein bash "$SRC/sichern.sh" jetzt)"
  erg "Push scheitert → Status fehler" "$(ja grep -q '^fehler|' "$STATUS")"
  erg "Push scheitert → Meldung nennt GitHub" "$(ja grep -q 'Hochladen zu GitHub' "$STATUS")"
  git -C "$TRESOR" remote set-url origin "$T/remote.git"

  git init -q --bare "$T/anders.git"; git -C "$TRESOR" remote set-url --push origin "$T/anders.git"
  erg "Gegenprobe erkennt fehlenden Stand auf GitHub" "$(nein bash "$SRC/sichern.sh" jetzt)"
  git -C "$TRESOR" config --unset remote.origin.pushurl

  erg "zu alter Stand → Fehler" "$(MAX_ALTER_MIN=-1 nein bash "$SRC/sichern.sh")"
  erg "zu alter Stand → Hinweis Vollzugriff" "$(ja grep -q 'Festplattenvollzugriff' "$STATUS")"

  # macOS-Sperre (TCC) lässt sich im Test nicht erzeugen – die Zeile ist wörtlich die von restic
  echo "error: open $HOME/Documents/Vault: operation not permitted" >"$RESTIC_LOG"
  local vorher; vorher=$(git --git-dir="$T/remote.git" rev-parse main)
  erg "macOS-Sperre im Protokoll → Fehler" "$(nein bash "$SRC/sichern.sh" jetzt)"
  erg "macOS-Sperre → Meldung Festplattenvollzugriff" "$(ja grep -q 'Festplattenvollzugriff' "$STATUS")"
  erg "macOS-Sperre → Teilsicherung trotzdem hochgeladen" "$([ "$(git --git-dir="$T/remote.git" rev-parse main)" != "$vorher" ]; echo $?)"
  bash "$SRC/sichern.sh" >/dev/null 2>&1
  erg "nächster Lauf wieder ok (Protokoll geleert)" "$(ja grep -q '^ok|' "$STATUS")"

  mkdir -p "$HOME/Documents/zu"; echo x >"$HOME/Documents/zu/a.txt"; chmod 000 "$HOME/Documents/zu"
  bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  chmod 755 "$HOME/Documents/zu"
  erg "unlesbarer Ordner → ok mit Hinweis" "$(ja grep -q '^ok|.*nicht lesbar' "$STATUS")"

  WARN_GROESSE_MB=0 bash "$SRC/sichern.sh" >/dev/null 2>&1
  erg "Speicher-Warnung" "$(ja grep -q 'fast voll' "$STATUS")"
  erg "Speicher-Warnung in status.sh" "$(WARN_GROESSE_MB=0 bash "$SRC/status.sh" 2>/dev/null | grep -q 'fast voll'; echo $?)"

  bash "$SRC/sichern.sh" >/dev/null 2>&1
  erg "status.sh: grün" "$(bash "$SRC/status.sh" 2>/dev/null | grep -q '✅ Neuester Stand'; echo $?)"
  erg "status.sh: falsches Passwort → Hinweis" "$(PASSWORT_BEFEHL='echo falsch' bash "$SRC/status.sh" 2>/dev/null | grep -q 'Kein Stand'; echo $?)"

  kanarien() { (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; alle_pfade_im_stand "$1" "$(stand_id)") >/dev/null 2>&1; }
  mkdir -p "$HOME/Documents/NurVideos"; echo v >"$HOME/Documents/NurVideos/a.mp4"
  printf '%s\n' "$HOME/Documents/NurVideos/" "$HOME/Documents/Vault" >>"$PFADE"
  bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  local voll; voll=$( (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; stand_id) )
  bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  erg "Kanarien: alle Ordner im Stand, kein Fehlalarm bei Ordner nur mit Videos" "$(kanarien "$voll"; echo $?)"
  voll=$( (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; stand_id) )
  # Hintergrund-Lauf ohne Zugriff simulieren: Vault-Inhalt fehlt im neuen Stand
  mv "$HOME/Documents/Vault" "$T/vault-weg"; mkdir "$HOME/Documents/Vault"; bash "$SRC/sichern.sh" jetzt >/dev/null 2>&1
  erg "Kanarien: fehlender Ordnerinhalt erkannt" "$(kanarien "$voll" && echo 1 || echo 0)"
  rm -rf "$HOME/Documents/Vault"; mv "$T/vault-weg" "$HOME/Documents/Vault"

  # Beschädigte Datei im Tresor muss die tägliche Prüfung finden
  rm -f "$GGS_HOME/geprueft"; local pack; pack=$(find "$TRESOR/data" -type f | head -1); chmod u+w "$pack"; printf 'X' >>"$pack"
  erg "Tresor-Schaden → Fehler" "$(nein bash "$SRC/sichern.sh")"
  erg "Tresor-Schaden → Meldung" "$(ja grep -q 'Schäden' "$STATUS")"
}

t_installer() {
  neu; rm -f "$PFADE"; mkdir -p "$HOME/Documents/Vault/.obsidian"
  export PASSWORT_BEFEHL="cat $T/pw" GGS_PASSWORT="abcde-fghjk-mnpqr-stuvw-xyzAC-DEFHJ"
  # Antworten: Vault ja · ganze Dokumente nein · weiterer Ordner · Ende · Passwort einmal falsch, dann richtig
  mkdir -p "$HOME/Extra"; echo e >"$HOME/Extra/e.txt"
  printf 'j\nn\n~/Extra/\n\nfalsch\n%s\n' "$GGS_PASSWORT" >"$T/antworten"; export EINGABE="$T/antworten"
  installer pfade speicher passwort tresor probe zeitplaene; erg "Installer-Ablauf komplett" $?
  erg "Vault ausgewählt (Antwort kam von der Eingabe)" "$(ja grep -qx "$HOME/Documents/Vault" "$PFADE")"
  erg "ganze Dokumente abgewählt" "$(nein grep -qx "$HOME/Documents" "$PFADE")"
  erg "weiterer Ordner mit ~ und / am Ende übernommen" "$(ja grep -qx "$HOME/Extra" "$PFADE")"
  erg "eigene Ausschlussdatei angelegt" "$([ -f "$AUSSCHLUSS_EIGEN" ]; echo $?)"
  erg "Passwort im (Ersatz-)Schlüsselbund" "$([ "$(cat "$T/pw")" = "$GGS_PASSWORT" ]; echo $?)"
  erg "Passwort in keiner Datei unter Home" "$(nein grep -rq "$GGS_PASSWORT" "$HOME")"

  # Neustart nach fertigem Lauf: macht weiter, ersetzt das Passwort nicht
  cp "$T/pw" "$T/pw.vorher"
  export GGS_PASSWORT="NEUES-passwort"
  installer pfade speicher passwort tresor probe; erg "Neustart läuft durch" $?
  erg "Neustart ersetzt Passwort nicht" "$(ja cmp -s "$T/pw" "$T/pw.vorher")"
  rm -f "$TRESOR/config"
  erg "unvollständiger Tresor → Abbruch statt Löschen" "$(installer tresor && echo 1 || echo 0)"
  erg "unvollständiger Tresor bleibt erhalten" "$([ -d "$TRESOR/.git" ] && [ -d "$TRESOR/data" ]; echo $?)"
  erg "unvollständiger Tresor wird nicht neu angelegt" "$([ ! -f "$TRESOR/config" ]; echo $?)"

  local p="$AGENTS/de.ggdigital.sicherung.plist"
  erg "Zeitplan-Datei gültig" "$(ja plutil -lint "$p")"
  erg "Zeitplan startet restic direkt (Vollzugriff nur für restic)" "$([ "$(plutil -extract ProgramArguments.0 raw "$p" 2>/dev/null)" = "$RESTIC" ]; echo $?)"
  erg "restic-Zeitplan schreibt ins restic-Protokoll" "$([ "$(plutil -extract StandardErrorPath raw "$p")" = "$RESTIC_LOG" ]; echo $?)"
  erg "Zeitplan alle 3 Stunden (8 Zeiten, Minute 15)" "$([ "$(plutil -extract StartCalendarInterval raw "$p")" = 8 ] && [ "$(plutil -extract StartCalendarInterval.7.Hour raw "$p")" = 21 ] && [ "$(plutil -extract StartCalendarInterval.0.Minute raw "$p")" = 15 ]; echo $?)"
  erg "Hochladen 30 Min. nach restic" "$([ "$(plutil -extract StartCalendarInterval.0.Minute raw "$AGENTS/de.ggdigital.sicherung-hochladen.plist")" = 45 ]; echo $?)"

  # Ein zweiter Mac darf eine fremde Sicherung nicht weiterbenutzen
  local remote="$T/remote.git" alt_t=$T
  neu; export DATEN_REMOTE="$remote" EINGABE=/dev/null
  erg "fremde Sicherung im Speicher → Abbruch" "$(installer speicher && echo 1 || echo 0)"

  # Neuer Mac mit anderem Benutzernamen
  neu; export HOME="$T/anderer-name"; mkdir -p "$HOME"
  export GGS_HOME="$HOME/.gg-sicherung" GGS_KONFIG="$HOME/.config/gg-sicherung" TRESOR="$HOME/.gg-sicherung/tresor"
  export STATUS="$GGS_HOME/status.txt" LOG="$GGS_HOME/protokoll.log" RESTIC_LOG="$GGS_HOME/restic.log"
  export PFADE="$GGS_KONFIG/pfade.txt" AUSSCHLUSS_EIGEN="$GGS_KONFIG/ausschluss-eigen.txt"
  export DATEN_REMOTE="$remote" PASSWORT_BEFEHL="cat $T/pw" GGS_PASSWORT="falsch"
  erg "neuer Mac, falsches Passwort → Abbruch" "$(nein bash "$SRC/wiederherstellen.sh" neuer-mac test)"
  erg "falsches Passwort → kein halber Tresor bleibt liegen" "$([ ! -e "$TRESOR" ]; echo $?)"
  export GGS_PASSWORT="abcde-fghjk-mnpqr-stuvw-xyzAC-DEFHJ"
  installer neuer_mac; erg "neuer Mac: alles zurückgeholt" $?
  erg "neuer Mac: Zeitplan noch NICHT aktiv" "$([ ! -f "$AGENTS/de.ggdigital.sicherung.plist" ]; echo $?)"
  erg "fortsetzen vor dem Zurücksortieren → Abbruch" "$(installer fortsetzen && echo 1 || echo 0)"
  cp -R "$HOME"/Wiederhergestellt-*"$alt_t"/home/. "$HOME/"
  installer fortsetzen; erg "fortsetzen nach dem Zurücksortieren" $?
  erg "neuer Mac: Pfade auf neuen Benutzer umgeschrieben" "$(ja grep -qx "$HOME/Documents/Vault" "$PFADE")"
  erg "neuer Mac: kein alter Pfad mehr" "$(nein grep -q "$alt_t/home" "$PFADE")"
  erg "neuer Mac: Notiz da" "$(ls "$HOME"/Wiederhergestellt-*"$alt_t"/home/Documents/Vault/Notiz.md >/dev/null 2>&1; echo $?)"
  echo "neu" >"$HOME/neu.txt"; echo "$HOME/neu.txt" >>"$PFADE"
  erg "neuer Mac: sichert danach weiter" "$(ja bash "$SRC/sichern.sh" jetzt)"
  unset DATEN_REMOTE GGS_PASSWORT EINGABE

  local pw; pw=$(GGS_NUR_LADEN=1 bash -c "source '$SRC/installieren.sh'; passwort_neu")
  erg "Passwort: 6 Blöcke à 5" "$([[ "$pw" =~ ^[a-zA-Z0-9]{5}(-[a-zA-Z0-9]{5}){5}$ ]]; echo $?)"
  erg "Passwort: keine verwechselbaren Zeichen" "$([[ "$pw" =~ [0OoIl1] ]] && echo 1 || echo 0)"
  erg "Passwort: jedes Mal neu" "$([ "$pw" != "$(GGS_NUR_LADEN=1 bash -c "source '$SRC/installieren.sh'; passwort_neu")" ]; echo $?)"
}

t_teilen() {
  neu; einrichten
  export ZIELORDNER="$T/schreibtisch" FREIGABEN="$GGS_HOME/freigaben.log"
  # Ersatz für osascript: nimmt das Fenster-Skript an und lässt es von Apples osacompile prüfen
  # (ungültiges Skript = Fenster scheitert, wie am echten Mac). OSA_FEHLER=1 simuliert „kein Bildschirm“.
  printf '#!/bin/bash\ncat > "%s/osa.applescript"\n[ -z "${OSA_FEHLER:-}" ] || exit 1\nosacompile -o "%s/osa.scpt" "%s/osa.applescript"\n' "$T" "$T" "$T" >"$T/bin/osascript"
  chmod +x "$T/bin/osascript"; local pfad_vorher=$PATH; export PATH="$T/bin:$PATH"
  fenster_pw() { sed -n 's/^set pw to "\(.*\)"$/\1/p' "$T/osa.applescript" 2>/dev/null; }
  local s="$SRC/teilen.sh" p="$HOME/Documents/Projekt" aus pkt pw g
  rm -f "$p/riesig.bin"
  # Zugangsdateien, die alle herausgefiltert werden müssen (auch Großschreibung, Unterordner)
  mkdir -p "$p/sub/.aws" "$p/.git" "$p/node_modules"
  echo geheim >"$p/id_ed25519"; echo zert >"$p/server.PEM"; echo t >"$p/.npmrc"; echo t >"$p/.netrc"
  echo t >"$p/prod.env"; echo t >"$p/.envrc"; echo t >"$p/sub/credentials.json"; echo t >"$p/sub/.aws/credentials"
  echo t >"$p/.git/config"; echo t >"$p/Login.keychain-db"; echo t >"$p/zert.pfx"
  echo "Folien" >"$p/praesentation.key"; echo "Liste" >"$p/id_liste.txt"   # keine Zugangsdaten
  ln -s /etc/hosts "$p/verknuepfung"
  mkdir -p "$T/tmpd"
  aus=$(TMPDIR="$T/tmpd" bash "$s" "$p" 2>&1); erg "Teilen läuft" $?
  pkt=$(sed -n 's/^✅ Paket: \(.*\.dmg\) .*/\1/p' <<<"$aus"); pw=$(fenster_pw)
  erg "keine Zwischenordner bleiben liegen" "$([ -z "$(ls -A "$T/tmpd")" ]; echo $?)"
  erg "Passwort steht NICHT in der Ausgabe" "$(nein grep -qF "$pw" <<<"$aus")"
  oeffnen() { mkdir -p "$T/m"; printf '%s' "$2" | hdiutil attach -quiet -stdinpass -nobrowse -readonly -mountpoint "$T/m" "$1"; }
  zu() { hdiutil detach -quiet "$T/m" 2>/dev/null || hdiutil detach -quiet -force "$T/m" 2>/dev/null; }
  oeffnen "$pkt" "$pw"; erg "Paket öffnet mit dem Paket-Passwort" $?
  erg "Inhalt unverändert drin" "$(ja cmp "$p/kunden.jsonl" "$T/m/Projekt/kunden.jsonl")"
  for g in .env id_ed25519 server.PEM .npmrc .netrc prod.env .envrc sub/credentials.json sub/.aws .git node_modules Login.keychain-db zert.pfx; do
    erg "nicht im Paket: $g" "$([ ! -e "$T/m/Projekt/$g" ]; echo $?)"
  done
  erg "Keynote-Datei (.key) bleibt drin" "$([ -f "$T/m/Projekt/praesentation.key" ]; echo $?)"
  erg "id_liste.txt bleibt drin" "$([ -f "$T/m/Projekt/id_liste.txt" ]; echo $?)"
  erg "Verknüpfungen werden nicht mitgenommen" "$([ ! -e "$T/m/Projekt/verknuepfung" ] && [ ! -L "$T/m/Projekt/verknuepfung" ]; echo $?)"
  erg "Gegenprobe: .env liegt in der Quelle" "$([ -f "$p/.env" ]; echo $?)"
  zu
  erg "falsches Passwort öffnet nicht" "$(nein oeffnen "$pkt" falsch-falsch)"; zu
  erg "Ausgabe nennt herausgefilterte Zugangsdaten" "$(ja grep -q 'credentials.json' <<<"$aus")"
  erg "Protokoll: genau eine Freigabe" "$([ "$(wc -l <"$FREIGABEN" | tr -d ' ')" = 1 ]; echo $?)"
  erg "Protokoll ohne Passwort" "$(nein grep -qF "$pw" "$FREIGABEN")"
  rm -f "$T/osa.applescript"
  erg "Passwort nirgends unter Home gespeichert" "$(nein grep -rqF "$pw" "$HOME")"

  local vorher; vorher=$(shasum "$pkt")
  bash "$s" "$p" >/dev/null 2>&1
  erg "gleicher Name → neues Paket mit -2" "$([ -f "${pkt%.dmg}-2.dmg" ]; echo $?)"
  erg "erstes Paket unverändert" "$([ "$(shasum "$pkt")" = "$vorher" ]; echo $?)"

  # Inhalt sieht nach Schlüssel aus (umbenannter privater Schlüssel) → kein Paket ohne Ja
  mkdir -p "$T/mitschluessel"; echo "Notiz" >"$T/mitschluessel/a.md"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n' >"$T/mitschluessel/deploy"
  local zahl; zahl=$(ls "$ZIELORDNER" | wc -l | tr -d ' ')
  aus=$(bash "$s" "$T/mitschluessel" 2>&1)
  erg "Schlüssel-Inhalt → kein Paket" "$([ "$(ls "$ZIELORDNER" | wc -l | tr -d ' ')" = "$zahl" ]; echo $?)"
  erg "Schlüssel-Inhalt → Datei wird genannt" "$(ja grep -q 'deploy' <<<"$aus")"
  erg "Schlüssel-Inhalt mit ausdrücklichem Ja → Paket" "$(FUNDE_OK=1 ja bash "$s" "$T/mitschluessel")"

  # Geschützte Bereiche gar nicht erst annehmen
  mkdir -p "$HOME/.ssh" "$HOME/.aws/sub" "$HOME/Library/Prefs"; echo k >"$HOME/.ssh/github"; echo k >"$HOME/.aws/sub/x"; echo x >"$HOME/Library/Prefs/a"
  erg "~/.ssh wird abgelehnt" "$(nein bash "$s" "$HOME/.ssh")"
  erg "Unterordner von ~/.aws wird abgelehnt" "$(nein bash "$s" "$HOME/.aws/sub")"
  erg "ganzer Benutzerordner wird abgelehnt" "$(nein bash "$s" "$HOME")"
  erg "Library wird abgelehnt" "$(nein bash "$s" "$HOME/Library/Prefs")"
  erg "Zugangsdatei direkt (.env) wird als solche abgelehnt" "$(bash "$s" "$p/.env" 2>&1 | grep -q 'ist eine Zugangsdatei'; echo $?)"
  erg "Zugangsdatei direkt, Großschreibung (.ENV) wird als solche abgelehnt" "$(cp "$p/.env" "$T/X.ENV"; bash "$s" "$T/X.ENV" 2>&1 | grep -q 'ist eine Zugangsdatei'; echo $?)"

  # Abbruch beim Passwort-Fenster → das ungeprüfte Paket darf nicht liegen bleiben
  zahl=$(ls "$ZIELORDNER" | wc -l | tr -d ' ')
  erg "Fenster scheitert → Abbruch" "$(OSA_FEHLER=1 nein bash "$s" "$HOME/Documents/Vault")"
  erg "Fenster scheitert → kein Paket bleibt liegen" "$([ "$(ls "$ZIELORDNER" | wc -l | tr -d ' ')" = "$zahl" ]; echo $?)"

  local n="$HOME/Documents/Vault/Notiz.md" erster
  erster=$(restic_t snapshots --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["short_id"])')
  echo "Stand v2" >"$n"
  aus=$(bash "$s" "$n" "$erster" 2>&1)
  pkt=$(sed -n 's/^✅ Paket: \(.*\.dmg\) .*/\1/p' <<<"$aus"); pw=$(fenster_pw)
  oeffnen "$pkt" "$pw"
  erg "früherer Stand wird geteilt (v1, nicht v2)" "$(ja grep -q 'v1' "$T/m/Notiz.md")"; zu

  erg "unbekannter Pfad → Abbruch" "$(nein bash "$s" "$HOME/gibtsnicht")"
  mkdir -p "$T/nurgeheim"; echo X=1 >"$T/nurgeheim/.env"
  erg "nur Zugangsdaten → Abbruch statt leerem Paket" "$(nein bash "$s" "$T/nurgeheim")"
  erg "großes Paket braucht Bestätigung" "$(MAX_MB=0 nein bash "$s" "$HOME/Documents/Vault")"
  erg "mit Bestätigung geht es" "$(MAX_MB=0 GROSS_OK=1 ja bash "$s" "$HOME/Documents/Vault")"
  erg "kein Testpaket bleibt eingehängt" "$(hdiutil info | grep -q "$T" && echo 1 || echo 0)"
  # Ordnername mit Anführungszeichen und Backslash: Fenster-Skript bleibt gültig, Name bleibt Text
  mkdir -p "$T/Böse \"Name\" & (do shell script \"id\")\\"; echo x >"$T/Böse \"Name\" & (do shell script \"id\")\\/a.txt"
  erg "Name mit Anführungszeichen/Backslash → Fenster funktioniert" "$(ja bash "$s" "$T/Böse \"Name\" & (do shell script \"id\")\\")"
  erg "Ordner über dem Benutzerordner wird abgelehnt" "$(nein bash "$s" "$T")"
  mkdir -p "$T/zeile
umbruch"; echo t >"$T/zeile
umbruch/.ENV"; echo n >"$T/zeile
umbruch/notiz.md"
  bash "$s" "$T/zeile
umbruch" >/dev/null 2>&1; pkt="$ZIELORDNER/GG-Freigabe-zeile_umbruch-$(date +%Y-%m-%d).dmg"; pw=$(fenster_pw)
  erg "Zeilenumbruch → lesbarer Paketname" "$([ -f "$pkt" ]; echo $?)"
  oeffnen "$pkt" "$pw"
  erg "Zeilenumbruch im Namen umgeht den Filter nicht" "$([ -f "$T/m/zeile
umbruch/notiz.md" ] && [ ! -e "$T/m/zeile
umbruch/.ENV" ]; echo $?)"; zu
  mkdir -p "$T/mitfifo"; echo n >"$T/mitfifo/a.md"; mkfifo "$T/mitfifo/rohr"
  erg "Sonderdatei (FIFO) lässt das Werkzeug nicht hängen" "$(perl -e 'alarm 60; exec @ARGV' bash "$s" "$T/mitfifo" >/dev/null 2>&1; echo $?)"
  mkdir -p "$T/token1" "$T/token2"; echo "OPENAI=sk-proj-AbCdEfGhIjKlMnOpQrStUvWx123" >"$T/token1/notiz.txt"
  printf '\xe9t\xe9 -----BEGIN RSA PRIVATE KEY-----\n' >"$T/token2/alt.csv"
  erg "OpenAI-Schlüssel (sk-proj-) → kein Paket" "$(nein bash "$s" "$T/token1")"
  # bewusst mit deutscher UTF-8-Einstellung: dort hält grep Latin-1 ohne LC_ALL=C für binär
  erg "Schlüssel in Latin-1-Datei → kein Paket" "$(LC_ALL=de_DE.UTF-8 nein bash "$s" "$T/token2")"
  local nr=0 zeile
  for zeile in 'API_KEY=abcdefgh12345' 'SECRET_KEY = "abcdefgh12345"' 'Password: hunter2hunter2' 'access_token=abcdefgh1234' \
      'Authorization: Bearer abcdefghijkl1234' 'STRIPE=whsec_abcdefghijklmnop1234'; do
    nr=$((nr + 1)); mkdir -p "$T/zuweisung$nr"; echo "$zeile" >"$T/zuweisung$nr/config.py"
    erg "Zugangswert erkannt: ${zeile%%[=:]*}" "$(nein bash "$s" "$T/zuweisung$nr")"
  done
  mkdir -p "$T/harmlos"; printf 'Das Token-Konzept besprechen wir am Montag.\nPasswort: siehe Apple Passwörter\n' >"$T/harmlos/notiz.md"
  erg "harmloser Text löst keinen Alarm aus" "$(ja bash "$s" "$T/harmlos")"
  export PATH=$pfad_vorher
  unset ZIELORDNER FREIGABEN
}

# ---------- Updates ----------
signiere() { # <schlüssel> <tag>
  git_ -C "$T/up" -c gpg.format=ssh -c user.signingkey="$1" tag -s "$2" -m "$2" >/dev/null 2>&1
}

t_update() {
  neu; einrichten
  ssh-keygen -q -t ed25519 -N "" -f "$T/glenn" -C glenn; ssh-keygen -q -t ed25519 -N "" -f "$T/fremd" -C fremd
  mkdir -p "$T/up/vertrauen"; cp -R "$SRC"/*.sh "$SRC/ausschluss.txt" "$SRC/skill" "$T/up/"
  echo "glenn@gg namespaces=\"git\" $(cat "$T/glenn.pub")" >"$T/up/vertrauen/allowed_signers"
  git_ -C "$T/up" init -q; git_ -C "$T/up" add -A; git_ -C "$T/up" commit -qm v1; signiere "$T/glenn" v1.0.0
  git clone -q "$T/up" "$GGS_HOME/werkzeug"; git -C "$GGS_HOME/werkzeug" checkout -q --detach v1.0.0
  mkdir -p "$(dirname "$VERTRAUEN")"; cp "$T/up/vertrauen/allowed_signers" "$VERTRAUEN"
  export WERKZEUG="$GGS_HOME/werkzeug"; echo v1.0.0 >"$VERSION_DATEI"
  local u="$SRC/aktualisieren.sh" w="$GGS_HOME/werkzeug"
  version() { git -C "$w" describe --tags --exact-match HEAD 2>/dev/null; }
  weg() { git -C "$T/up" tag -d "$1" >/dev/null; git -C "$w" tag -d "$1" >/dev/null 2>&1; }

  bash "$u" >/dev/null 2>&1
  erg "keine neue Version → bleibt" "$([ "$(version)" = v1.0.0 ]; echo $?)"

  echo "# a" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam a; git_ -C "$T/up" tag -a v1.0.1 -m unsigniert
  bash "$u" >/dev/null 2>&1
  erg "unsignierte Version abgelehnt" "$([ "$(version)" = v1.0.0 ]; echo $?)"
  bash "$u" >/dev/null 2>&1
  erg "Ablehnung nur einmal gemerkt (keine tägliche Meldung)" "$([ "$(wc -l <"$GGS_HOME/abgelehnt.txt" | tr -d ' ')" = 1 ]; echo $?)"
  weg v1.0.1

  # Angriff: fremder Schlüssel trägt sich selbst in die Vertrauensliste der neuen Version ein
  echo "fremd@x namespaces=\"git\" $(cat "$T/fremd.pub")" >>"$T/up/vertrauen/allowed_signers"
  git_ -C "$T/up" commit -qam angriff; signiere "$T/fremd" v1.0.1
  bash "$u" >/dev/null 2>&1
  erg "fremd signiert (+ eigene Vertrauensliste) abgelehnt" "$([ "$(version)" = v1.0.0 ]; echo $?)"
  erg "gleicher Name, neuer Inhalt wird neu geprüft" "$([ "$(wc -l <"$GGS_HOME/abgelehnt.txt" | tr -d ' ')" = 2 ]; echo $?)"
  erg "Ablehnung im Protokoll" "$(ja grep -q 'nicht von GG Digital freigegeben' "$LOG")"
  weg v1.0.1; git_ -C "$T/up" reset -q --hard HEAD~1

  # Angriff: altes, echt signiertes Tag unter neuem Namen (Zurückdrehen)
  git -C "$T/up" update-ref refs/tags/v1.0.9 "$(git -C "$T/up" rev-parse v1.0.0)"
  echo "# b" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam b; signiere "$T/glenn" v1.0.2
  bash "$u" >/dev/null 2>&1
  erg "umbenanntes altes Tag blockiert nicht, echte Version kommt" "$([ "$(version)" = v1.0.2 ]; echo $?)"
  weg v1.0.9

  git -C "$T/up" update-ref refs/tags/v1.0.8 "$(git -C "$T/up" rev-parse v1.0.0)"
  bash "$u" >/dev/null 2>&1
  erg "umbenanntes altes Tag → kein Zurückdrehen" "$([ "$(git -C "$w" rev-parse HEAD)" = "$(git -C "$T/up" rev-parse 'v1.0.2^{commit}')" ]; echo $?)"
  weg v1.0.8

  # Echt signiert, aber älterer Stand (kein Nachfahre) → kein Zurückdrehen
  git_ -C "$T/up" checkout -q 'v1.0.0^{commit}'; echo "# alt" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam alt
  signiere "$T/glenn" v1.0.7; git_ -C "$T/up" checkout -q main
  bash "$u" >/dev/null 2>&1
  erg "signiert, aber Seitenzweig → abgelehnt" "$([ "$(version)" = v1.0.2 ]; echo $?)"
  weg v1.0.7

  echo "kaputt(" >>"$T/up/status.sh"; git_ -C "$T/up" commit -qam kaputt; signiere "$T/glenn" v1.0.3
  bash "$u" >/dev/null 2>&1
  erg "Syntaxfehler → zurück zur alten" "$([ "$(version)" = v1.0.2 ]; echo $?)"
  weg v1.0.3; git_ -C "$T/up" reset -q --hard HEAD~1

  sed -i '' 's/--files-from/--dateien-aus/' "$T/up/lib.sh"; git_ -C "$T/up" commit -qam inhalt; signiere "$T/glenn" v1.0.4
  bash "$u" >/dev/null 2>&1
  erg "inhaltlich kaputte Version → zurück zur alten" "$([ "$(version)" = v1.0.2 ]; echo $?)"
  weg v1.0.4; git_ -C "$T/up" reset -q --hard HEAD~1

  # Höhere fremde Version darf die echte nicht blockieren
  echo "# c" >>"$T/up/skill/sicherung/SKILL.md"; git_ -C "$T/up" commit -qam c; signiere "$T/glenn" v1.0.5
  echo "# d" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam d; git_ -C "$T/up" tag -a v1.0.6 -m unsigniert
  bash "$u" >/dev/null 2>&1
  erg "höhere unsignierte Version blockiert die echte nicht" "$([ "$(version)" = v1.0.5 ]; echo $?)"
  erg "Skill nach Update aktualisiert" "$(ja grep -q '^# c$' "$HOME/.claude/skills/sicherung/SKILL.md")"
  erg "Versionsdatei nachgeführt" "$([ "$(cat "$VERSION_DATEI")" = v1.0.5 ]; echo $?)"
  erg "restic-Zeitplan nach Update neu geschrieben" "$([ -f "$AGENTS/de.ggdigital.sicherung.plist" ]; echo $?)"
  weg v1.0.6

  # Angriff: unsigniertes, hohes Tag auf den laufenden Stand (früher galt es dann als „aktuell“)
  # Späteres Datum: git describe nimmt dann das falsche Tag – genau so würde ein Angreifer es setzen
  GIT_COMMITTER_DATE="2030-01-01T00:00:00" git_ -C "$T/up" tag -a v9.0.0 -m falsch "$(git -C "$w" rev-parse HEAD)"
  bash "$u" >/dev/null 2>&1   # erster Lauf holt das falsche Tag ab, erst danach kann es wirken
  echo "# e" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam e; signiere "$T/glenn" v1.0.11
  bash "$u" >/dev/null 2>&1
  erg "falsches Tag am laufenden Stand blockiert Updates nicht" "$([ "$(cat "$VERSION_DATEI")" = v1.0.11 ]; echo $?)"
  weg v9.0.0

  # Vergiftung: erst unsigniert, dann das echte Release unter demselben Namen
  echo "# f" >>"$T/up/lib.sh"; git_ -C "$T/up" commit -qam f; git_ -C "$T/up" tag -a v1.0.12 -m unsigniert
  bash "$u" >/dev/null 2>&1; weg v1.0.12; signiere "$T/glenn" v1.0.12
  bash "$u" >/dev/null 2>&1
  erg "echtes Release nach gefälschtem gleichen Namen wird übernommen" "$([ "$(cat "$VERSION_DATEI")" = v1.0.12 ]; echo $?)"

  # Erstinstallation des Werkzeugs: höchste echte Version, ungeprüfte höhere blockieren nicht
  git_ -C "$T/up" tag -a v2.0.0 -m unsigniert
  rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  (export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers"; installer werkzeug); erg "Installer holt Werkzeug" $?
  erg "Installer nimmt höchste signierte Version" "$([ "$(cat "$VERSION_DATEI")" = v1.0.12 ]; echo $?)"
  cp "$T/fremd.pub" "$T/anderer-anker"; echo "x@y namespaces=\"git\" $(cat "$T/fremd.pub")" >"$T/anderer-anker"
  (export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/anderer-anker"; installer werkzeug)
  erg "Neustart ersetzt die Vertrauensliste nicht" "$(ja grep -q glenn@gg "$VERTRAUEN")"

  # Erstinstallation über den Fingerabdruck im Paket (ohne signiertes Tag)
  local pin; pin=$(git -C "$T/up" rev-parse 'v1.0.5^{commit}')
  echo "v1.0.5 $pin" >"$T/version.txt"
  rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  (export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/version.txt"; installer werkzeug); erg "Fingerabdruck: Installer holt Werkzeug" $?
  erg "Fingerabdruck: genau dieser Stand" "$([ "$(git -C "$w" rev-parse HEAD)" = "$pin" ] && [ "$(cat "$VERSION_DATEI")" = v1.0.5 ]; echo $?)"
  echo "v1.0.5 0123456789abcdef0123456789abcdef01234567" >"$T/falsch.txt"
  rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  erg "Fingerabdruck unbekannt → verständlicher Abbruch" "$( (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/falsch.txt"; werkzeug) 2>&1 | grep -q 'nicht zu finden'; echo $?)"
  echo "v1.0.5 kaputt" >"$T/kaputt.txt"; rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  erg "Fingerabdruck beschädigt → verständlicher Abbruch" "$( (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/kaputt.txt"; werkzeug) 2>&1 | grep -q 'beschädigt'; echo $?)"
  # Nach Fingerabdruck-Installation kommt ein späteres signiertes Update normal an
  rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  (export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/version.txt"; installer werkzeug)
  bash "$u" >/dev/null 2>&1
  erg "Fingerabdruck-Installation bekommt signierte Updates" "$([ "$(cat "$VERSION_DATEI")" = v1.0.12 ]; echo $?)"
  local stand; stand=$(git -C "$w" rev-parse HEAD)
  (export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/version.txt"; installer werkzeug)
  erg "Installer-Neustart dreht ein Update nicht zurück" "$([ "$(cat "$VERSION_DATEI")" = v1.0.12 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$stand" ]; echo $?)"
  echo "foo $pin" >"$T/vfalsch.txt"; rm -rf "$w" "$VERTRAUEN" "$VERSION_DATEI"
  erg "Versionsname im Paket ungültig → Abbruch" "$( (GGS_NUR_LADEN=1 source "$SRC/installieren.sh"; export WERKZEUG_URL="$T/up" PAKET_VERTRAUEN="$T/up/vertrauen/allowed_signers" PAKET_VERSION="$T/vfalsch.txt"; werkzeug) 2>&1 | grep -q 'beschädigt'; echo $?)"
  export WERKZEUG="$SRC"
}

alle() { t_sichern; t_wiederherstellen; t_fehlerfaelle; t_installer; t_teilen; t_update; }

if [ "${1:-}" = --mutation ]; then
  ERGEBNIS=$(mktemp -d); ORDNER+=("$ERGEBNIS"); nr=0
  mutiere() { # <nr> <datei> <ausdruck> – schreibt ERKANNT / NICHT ERKANNT / GREIFT NICHT
    local M; M=$(mktemp -d); cp -R "$QUELLE"/. "$M/"
    sed -i '' "$3" "$M/$2"
    if cmp -s "$QUELLE/$2" "$M/$2"; then echo "GREIFT NICHT: $2 | $3" >"$ERGEBNIS/$1"
    elif SRC="$M" RESTIC_BIN="$RESTIC_BIN" bash "$QUELLE/test.sh" 2>/dev/null | grep -q '  ROT:'; then echo "ERKANNT" >"$ERGEBNIS/$1"
    else echo "NICHT ERKANNT: $2 | $3" >"$ERGEBNIS/$1"; fi
    rm -rf "$M"
  }
  while IFS='|' read -r datei ausdruck; do
    [ -n "$datei" ] || continue
    nr=$((nr + 1)); mutiere "$nr" "$datei" "$ausdruck" &
    [ $((nr % ${PARALLEL:-6})) = 0 ] && wait
  done < <(grep -v "^#" "${MUTATIONEN:-$QUELLE/mutationen.txt}")
  wait
  cat "$ERGEBNIS"/* | grep -v '^ERKANNT$' | sed 's/^/  /'
  erkannt=$(cat "$ERGEBNIS"/* | grep -c '^ERKANNT$')
  echo "Mutationen erkannt: $erkannt/$nr"
  [ "$nr" -gt 0 ] && [ "$erkannt" = "$nr" ]; exit $?
fi

alle
echo "Ergebnis: $GRUEN grün, $ROT rot"
[ "$ROT" = 0 ]

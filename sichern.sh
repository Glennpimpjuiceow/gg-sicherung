#!/bin/bash
# GG Sicherung – Tresor hochladen.
#   sichern.sh          lädt den verschlüsselten Tresor zu GitHub hoch (läuft nach dem restic-Zeitplan)
#   sichern.sh jetzt    sichert sofort mit restic und lädt danach hoch
set -u
source "$(dirname "$0")/lib.sh"

fehler() { log "Ende FEHLER: $1"; status_setzen fehler "$1"; melden "Sicherung fehlgeschlagen: $1"; sperre_frei; exit 1; }

restic_jetzt() {
  local args=(); while IFS= read -r a; do args+=("$a"); done < <(backup_argumente)
  "$RESTIC" "${args[@]}" >>"$RESTIC_LOG" 2>&1
  local rc=$?
  # 3 = einzelne Dateien nicht lesbar, der Stand ist trotzdem gespeichert
  [ $rc -eq 0 ] || [ $rc -eq 3 ] || return 1
  [ $rc -eq 3 ] && log "restic: einige Dateien nicht lesbar (siehe $RESTIC_LOG)"
  return 0
}

hochladen() {
  cd "$TRESOR" || fehler "Tresor fehlt ($TRESOR)"
  git add -A || fehler "git add"
  # Hat restic während des Erfassens angefangen, wäre der Stand halb – dann nichts festschreiben
  if tresor_belegt; then
    git reset -q; log "restic startete während des Erfassens – nächster Lauf lädt hoch"
    status_setzen übersprungen "restic arbeitet noch"; sperre_frei; exit 0
  fi
  if ! git diff --cached --quiet; then
    git commit -q -m "Stand $(date '+%Y-%m-%d %H:%M')" || fehler "git commit"
  fi
  # Die erste Sicherung kann groß sein – darum bis zu 3 Stunden für das Hochladen
  NETZ_SEK=10800 netz git push -q origin HEAD:main 2>>"$LOG" || fehler "Hochladen zu GitHub (Internet? Anmeldung?)"
  local fern; fern=$(netz git ls-remote origin refs/heads/main 2>>"$LOG" | cut -f1)
  [ "$fern" = "$(git rev-parse HEAD)" ] || fehler "Gegenprobe: GitHub hat nicht den neuesten Stand"
}

haupt() {
  sperre_holen || { log "läuft schon"; exit 0; }
  if tresor_belegt; then
    log "restic arbeitet noch – nächster Lauf lädt hoch"; status_setzen übersprungen "restic arbeitet noch"; sperre_frei; exit 0
  fi
  if [ "${1:-}" = jetzt ]; then restic_jetzt || fehler "restic-Lauf (siehe $RESTIC_LOG)"; fi

  local alter; alter=$(neuester_stand_alter_min)
  [ -n "$alter" ] || fehler "kein Stand im Tresor"
  [ "$alter" -le "$MAX_ALTER_MIN" ] || fehler "neuester Stand ist $((alter / 60)) Std. alt – restic läuft nicht (Festplattenvollzugriff?)"

  # Einmal am Tag einen Teil der verschlüsselten Daten wirklich lesen (findet beschädigte Dateien)
  if [ -z "$(find "$GGS_HOME/geprueft" -mmin -1440 2>/dev/null)" ]; then
    restic_ check --read-data-subset "$PRUEF_ANTEIL" >>"$LOG" 2>&1 || fehler "Tresor-Prüfung fand Schäden – bitte GG Digital Bescheid geben"
    touch "$GGS_HOME/geprueft"
  fi

  local lesbar; lesbar=$(restic_protokoll_pruefen)
  hochladen   # auch eine Teilsicherung hochladen, erst danach Alarm
  [ "$lesbar" = VOLLZUGRIFF ] && fehler "macOS sperrt Ordner für die Sicherung – restic braucht Festplattenvollzugriff"
  local mb; mb=$(du -sm "$TRESOR/.git" | cut -f1)
  if [ -n "$lesbar" ]; then
    log "Ende ok, $lesbar Dateien unlesbar"; status_setzen ok "gesichert ($mb MB), aber $lesbar Dateien waren nicht lesbar (Protokoll: $RESTIC_LOG.vorher)"
  elif [ "$mb" -ge "$WARN_GROESSE_MB" ]; then
    log "Ende ok, aber groß: $mb MB"; status_setzen ok "gesichert, Speicher fast voll ($mb MB) – bitte GG Digital Bescheid geben"
    melden "Sicherungsspeicher fast voll ($mb MB) – bitte GG Digital Bescheid geben"
  else
    log "Ende ok ($mb MB)"; status_setzen ok "gesichert ($mb MB)"
  fi
  sperre_frei
}

haupt "$@"

# Gemeinsame Grundlage der GG Sicherung. Wird von allen Skripten mit `source` geladen.
# Jeder Wert lässt sich über die Umgebung überschreiben (nötig für test.sh).

GGS_HOME="${GGS_HOME:-$HOME/.gg-sicherung}"
GGS_KONFIG="${GGS_KONFIG:-$HOME/.config/gg-sicherung}"
WERKZEUG="${WERKZEUG:-$GGS_HOME/werkzeug}"
TRESOR="${TRESOR:-$GGS_HOME/tresor}"
RESTIC="${RESTIC:-$GGS_HOME/bin/restic}"
VERTRAUEN="${VERTRAUEN:-$GGS_HOME/vertrauen/allowed_signers}"
VERSION_DATEI="${VERSION_DATEI:-$GGS_HOME/version}"
AGENTS="${AGENTS:-$HOME/Library/LaunchAgents}"
STATUS="${STATUS:-$GGS_HOME/status.txt}"
LOG="${LOG:-$GGS_HOME/protokoll.log}"
RESTIC_LOG="${RESTIC_LOG:-$GGS_HOME/restic.log}"
PFADE="${PFADE:-$GGS_KONFIG/pfade.txt}"
AUSSCHLUSS_EIGEN="${AUSSCHLUSS_EIGEN:-$GGS_KONFIG/ausschluss-eigen.txt}"
SCHLUESSELBUND_DIENST="${SCHLUESSELBUND_DIENST:-gg-sicherung}"
PASSWORT_BEFEHL="${PASSWORT_BEFEHL:-security find-generic-password -s $SCHLUESSELBUND_DIENST -a $USER -w}"
MELDEN="${MELDEN:-an}"
# Wie alt der neueste Stand höchstens sein darf (der Zeitplan sichert alle 3 h).
MAX_ALTER_MIN="${MAX_ALTER_MIN:-240}"
WARN_GROESSE_MB="${WARN_GROESSE_MB:-700}"
# Einmal am Tag wird ein Teil der verschlüsselten Daten wirklich gelesen und geprüft
PRUEF_ANTEIL="${PRUEF_ANTEIL:-5%}"

export GIT_TERMINAL_PROMPT=0

log() { mkdir -p "$(dirname "$LOG")"; printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

melden() {
  log "MELDUNG: $1"
  [ "$MELDEN" = an ] || return 0
  local text=${1//\"/\'}
  osascript -e "display notification \"$text\" with title \"GG Sicherung\"" >/dev/null 2>&1 || true
}

status_setzen() { # <ok|fehler|übersprungen> <text>
  mkdir -p "$(dirname "$STATUS")"
  printf '%s|%s|%s\n' "$1" "$(date '+%Y-%m-%d %H:%M')" "$2" >"$STATUS"
}

# Zeitlimit ohne GNU timeout (fehlt auf macOS)
netz() { perl -e 'alarm shift; exec @ARGV' "${NETZ_SEK:-300}" "$@"; }

restic_() { "$RESTIC" --repo "$TRESOR" --password-command "$PASSWORT_BEFEHL" "$@"; }

# Die Argumente für den Sicherungslauf. Der Zeitplan startet restic mit genau diesen
# Argumenten direkt (ohne bash), damit nur restic Festplattenvollzugriff braucht.
backup_argumente() {
  printf '%s\n' --repo "$TRESOR" --password-command "$PASSWORT_BEFEHL" backup --quiet \
    --files-from "$PFADE" --exclude-file "$WERKZEUG/ausschluss.txt" \
    --exclude-larger-than 50M --exclude-caches --tag zeitplan
  [ -f "$AUSSCHLUSS_EIGEN" ] && printf '%s\n' --exclude-file "$AUSSCHLUSS_EIGEN"
  return 0
}

# restic erneuert sein Schloss alle 5 Min. Ältere Schlösser stammen von einem abgestürzten Lauf
# und werden aufgeräumt, sonst bliebe das Hochladen für immer stehen.
tresor_belegt() {
  [ -n "$(ls -A "$TRESOR/locks" 2>/dev/null)" ] || return 1
  [ -n "$(find "$TRESOR/locks" -type f -mmin -30 2>/dev/null)" ] && return 0
  log "verwaistes restic-Schloss aufgeräumt"; find "$TRESOR/locks" -type f -mmin +30 -delete
  [ -n "$(ls -A "$TRESOR/locks" 2>/dev/null)" ]
}

# Passwort in den Schlüsselbund – über stdin, damit es nie in der Prozessliste (ps) steht
schluesselbund_setzen() { # <passwort>
  local pw=${1//\\/\\\\}; pw=${pw//\"/\\\"}
  # Alten Eintrag erst löschen: -U auf einen vorhandenen Eintrag kann eine Rückfrage auslösen
  printf 'delete-generic-password -s "%s" -a "%s"\n' "$SCHLUESSELBUND_DIENST" "$USER" | ${SECURITY:-security} -i >/dev/null 2>&1
  printf 'add-generic-password -s "%s" -a "%s" -T /usr/bin/security -w "%s"\n' \
    "$SCHLUESSELBUND_DIENST" "$USER" "$pw" | ${SECURITY:-security} -i >/dev/null 2>&1
}

# Wertet das Protokoll der Hintergrund-Läufe aus und leert es danach.
# Ausgabe: leer = alles lesbar · "VOLLZUGRIFF" = macOS sperrt Ordner · sonst Zahl unlesbarer Dateien
restic_protokoll_pruefen() {
  [ -s "$RESTIC_LOG" ] || return 0
  if grep -qi "operation not permitted" "$RESTIC_LOG"; then echo VOLLZUGRIFF
  else grep -ci "permission denied" "$RESTIC_LOG" | grep -v '^0$'; fi
  mv -f "$RESTIC_LOG" "$RESTIC_LOG.vorher"
}

# Skill /sicherung nach ~/.claude/skills bringen – nur ersetzen, wenn es unserer ist
skill_aktualisieren() {
  local ziel="$HOME/.claude/skills/sicherung"
  if [ -e "$ziel" ] && ! grep -q "GG Sicherung" "$ziel/SKILL.md" 2>/dev/null; then
    log "fremder Skill „sicherung“ vorhanden – nicht ersetzt"; return 1
  fi
  mkdir -p "$HOME/.claude/skills" && rm -rf "$ziel" && cp -R "$WERKZEUG/skill/sicherung" "$ziel"
}

# Zeitplan-Datei für launchd (Python-plistlib: sicheres Escaping)
plist() { # <label> <stunden|täglich> <minute> <protokoll> <argumente...>
  local label=$1 art=$2 minute=$3 protokoll=$4; shift 4
  mkdir -p "$AGENTS"
  python3 - "$AGENTS/$label.plist" "$label" "$art" "$minute" "$protokoll" "$@" <<'PY'
import plistlib, sys
ziel, label, art, minute, protokoll, *args = sys.argv[1:]
zeiten = [{"Hour": h, "Minute": int(minute)} for h in range(0, 24, 3)] if art == "stunden" else [{"Hour": 12, "Minute": int(minute)}]
with open(ziel, "wb") as f:
    plistlib.dump({"Label": label, "ProgramArguments": args, "StartCalendarInterval": zeiten,
                   "StandardOutPath": protokoll, "StandardErrorPath": protokoll, "LowPriorityIO": True, "Nice": 10}, f)
PY
}

zeitplan_laden() { # <label>
  [ -n "${GGS_OHNE_LAUNCHD:-}" ] && return 0   # nur test.sh
  launchctl bootout "gui/$(id -u)/$1" 2>/dev/null && sleep 1
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$1.plist"
}

# restic schreibt in sein eigenes Protokoll – sichern.sh wertet es aus (Festplattenvollzugriff)
restic_zeitplan_schreiben() {
  local args=() a
  while IFS= read -r a; do args+=("$a"); done < <(backup_argumente)
  plist de.ggdigital.sicherung stunden 15 "$RESTIC_LOG" "$RESTIC" "${args[@]}" && zeitplan_laden de.ggdigital.sicherung
}

sperre_holen() {
  SPERRE="$GGS_HOME/.sperre"
  if mkdir "$SPERRE" 2>/dev/null; then echo $$ >"$SPERRE/pid"; return 0; fi
  local alt; alt=$(cat "$SPERRE/pid" 2>/dev/null)
  if [ -n "$alt" ] && kill -0 "$alt" 2>/dev/null; then return 1; fi
  rm -rf "$SPERRE"; mkdir "$SPERRE" 2>/dev/null && echo $$ >"$SPERRE/pid"
}
sperre_frei() { [ -n "${SPERRE:-}" ] && rm -rf "$SPERRE"; }

staende_zahl() { restic_ snapshots --json 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0; }

neuester_stand_alter_min() { # leer, wenn es keinen Stand gibt
  restic_ snapshots --json --latest 1 2>/dev/null | python3 -c '
import json, sys, re, datetime
s = json.load(sys.stdin)
if not s: sys.exit(0)
# restic: 2026-10-18T16:57:56.123456789+02:00 – Sekundenbruchteile und Z weg, sonst kann fromisoformat es nicht
zeiten = [datetime.datetime.fromisoformat(re.sub(r"\.\d+", "", x["time"]).replace("Z", "+00:00")) for x in s]
t = max(zeiten)
print(int((datetime.datetime.now(t.tzinfo) - t).total_seconds() // 60))'
}

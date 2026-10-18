---
name: sicherung
description: GG Sicherung – zeigt, ob die automatische verschlüsselte Sicherung läuft, und stellt Dateien oder Ordner aus einem früheren Stand wieder her. Auslöser „/sicherung“, „läuft meine Sicherung?“, „ist alles gesichert?“, „Datei wiederherstellen“, „Stand von gestern zurückholen“, „neuer Mac“.
---

# sicherung (GG Sicherung)

Werkzeug liegt in `~/.gg-sicherung/werkzeug/`. Antworten immer auf Deutsch, einfach, ohne Fachwörter.

## „Läuft meine Sicherung?“
`bash ~/.gg-sicherung/werkzeug/status.sh` ausführen und das Ergebnis in 2–4 Sätzen erklären.
- Steht dort „Festplattenvollzugriff“: erklären, dass in Systemeinstellungen → Datenschutz → Festplattenvollzugriff das Programm „restic“ eingeschaltet sein muss (`open -R ~/.gg-sicherung/bin/restic` zeigt es im Finder).
- Andere Fehler: Protokoll `~/.gg-sicherung/protokoll.log` (letzte 20 Zeilen) lesen, Ursache in einem Satz nennen, bei Unklarheit raten, GG Digital zu fragen.

## Wiederherstellen
1. Stände zeigen: `bash ~/.gg-sicherung/werkzeug/wiederherstellen.sh liste`
2. Mit dem Nutzer klären: welcher Stand (`neuester`, ein Datum `JJJJ-MM-TT` oder eine Stand-ID) und welcher Ordner bzw. welche Datei (voller Pfad, z. B. `/Users/<name>/Documents/Vault/Notiz.md`).
3. `bash ~/.gg-sicherung/werkzeug/wiederherstellen.sh <stand> <pfad>` – landet in einem NEUEN Ordner `~/Wiederhergestellt-…`, darunter mit dem vollen Originalpfad.
4. Zeigen, wo die Datei liegt (`open -R`). Das Zurückkopieren an den alten Ort nur nach ausdrücklichem Ja des Nutzers, und vorher sagen, was dabei ersetzt wird.

## Neuer Mac
Im GG-Paket `bash installieren.sh --neuer-mac` ausführen (braucht GitHub-Anmeldung und das Passwort aus Apple Passwörter). Es holt alles in einen Ordner `~/Wiederhergestellt-…`. Das Zurückschieben an die richtigen Orte zusammen mit GG Digital machen, erst danach `bash installieren.sh --fortsetzen` (schaltet die Sicherung wieder ein und prüft, dass alle Ordner zurück sind).

## Regeln
- Nie Dateien am Originalort überschreiben oder löschen ohne ausdrückliches Ja.
- Das Sicherungs-Passwort nie anzeigen, ausgeben oder in Dateien schreiben.
- Den Tresor-Ordner `~/.gg-sicherung/tresor` nie von Hand verändern.

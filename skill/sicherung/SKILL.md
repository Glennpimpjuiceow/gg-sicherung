---
name: sicherung
description: GG Sicherung – zeigt, ob die automatische verschlüsselte Sicherung läuft, stellt Dateien oder Ordner aus einem früheren Stand wieder her und teilt auf Wunsch einen Ordner verschlüsselt mit GG Digital. Auslöser „/sicherung“, „läuft meine Sicherung?“, „ist alles gesichert?“, „Datei wiederherstellen“, „Stand von gestern zurückholen“, „neuer Mac“, „mit GG Digital teilen“, „Ordner an GG Digital schicken“, „was habe ich geteilt?“.
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

## Mit GG Digital teilen
Nur wenn der Nutzer es ausdrücklich will. GG Digital sieht sonst nichts von seinen Daten.
1. Klären: welcher Ordner bzw. welche Datei (voller Pfad), aktueller Inhalt oder ein früherer Stand.
2. Einmal bestätigen lassen: „Ich packe <Ordner> (<Größe>) verschlüsselt für GG Digital. Bekannte Zugangsdateien werden herausgefiltert, Passwörter in normalen Dokumenten erkenne ich nicht – bitte kurz drüberschauen. Okay?“
3. `bash ~/.gg-sicherung/werkzeug/teilen.sh <pfad> [stand]`. Das Passwort erscheint in einem Fenster auf dem Bildschirm des Nutzers – du siehst es nicht, frag nie danach.
   - „Paket wäre … MB groß“: nachfragen, nur mit Ja `GROSS_OK=1` davor.
   - „sehen nach Schlüsseln oder Zugangstokens aus“: die Liste zeigen und empfehlen, diese Dateien wegzulassen (z. B. Unterordner ohne sie teilen). Nur auf ausdrückliches Ja `FUNDE_OK=1` davor.
   - Geschützte Ordner (.ssh, .aws, Library, ganzer Benutzerordner) lehnt das Werkzeug ab – nicht umgehen.
4. Dem Nutzer sagen: Paket (Pfad nennen) per WeTransfer, Passwort aus dem Fenster GETRENNT (z. B. WhatsApp) an GG Digital. Die Liste „Nicht mitgepackt“ vorlesen.
5. Nie selbst versenden.
- „Was habe ich geteilt?“: `cat ~/.gg-sicherung/freigaben.log` (Datum | Ordner | Stand | Dateien | Größe | Paket) in Worten zusammenfassen.

## Neuer Mac
Im GG-Paket `bash installieren.sh --neuer-mac` ausführen (braucht GitHub-Anmeldung und das Passwort aus Apple Passwörter). Es holt alles in einen Ordner `~/Wiederhergestellt-…`. Das Zurückschieben an die richtigen Orte zusammen mit GG Digital machen, erst danach `bash installieren.sh --fortsetzen` (schaltet die Sicherung wieder ein und prüft, dass alle Ordner zurück sind).

## Regeln
- Nie Dateien am Originalort überschreiben oder löschen ohne ausdrückliches Ja.
- Das Sicherungs-Passwort nie anzeigen, ausgeben oder in Dateien schreiben.
- Den Tresor-Ordner `~/.gg-sicherung/tresor` nie von Hand verändern.

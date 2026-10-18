# GG Sicherung

Dein Claude-Arbeitsplatz (Einstellungen, Skills, Erinnerungen, Vault und die Ordner, die du auswählst) wird **alle 3 Stunden automatisch und verschlüsselt** in einem privaten Speicher in **deinem eigenen GitHub-Konto** gesichert. GitHub sieht nur verschlüsselte Blöcke – keine Inhalte, keine Dateinamen. Das Passwort hast nur du; GG Digital speichert es nicht.

**Gut zu wissen:** Das Werkzeug selbst stammt von GG Digital und aktualisiert sich automatisch auf deinem Mac (nur mit GG Digitals digitaler Unterschrift). Wie jedes Programm auf deinem Mac könnte es technisch auf deine Daten zugreifen. Du vertraust GG Digital also so, wie du jedem Software-Hersteller vertraust. Das Passwort liegt in deinem Mac-Schlüsselbund; Programme, die unter deinem Benutzer laufen, können es dort abfragen, solange der Mac entsperrt ist – wie bei allen gespeicherten Passwörtern.

## Einrichten (einmalig, ca. 15 Minuten)

1. **GitHub-Konto** bereithalten (kostenlos auf github.com). GG Digital lädt dich zum Werkzeug ein: Die Einladungs-Mail von GitHub annehmen.
2. Diesen Ordner öffnen, im Terminal eingeben: `bash installieren.sh`
3. Den Fragen folgen: im Browser bei GitHub anmelden, auswählen, was gesichert werden soll.
4. **Das angezeigte Passwort in „Passwörter“ (Apple) speichern**, Name „GG Sicherung“, und einmal zur Kontrolle abtippen.
   ⚠️ Ohne dieses Passwort ist die Sicherung wertlos. Niemand kann es wiederherstellen.
5. **Festplattenvollzugriff:** In den Systemeinstellungen, die sich öffnen, das Programm „restic“ in die Liste ziehen und einschalten. Die Einrichtung prüft danach selbst, ob es funktioniert.

Fertig. Ab jetzt läuft alles von allein, auch Updates des Werkzeugs (nur von GG Digital geprüfte und signierte Versionen).

## Im Alltag

- **Ist alles gesichert?** In Claude: `/sicherung` (oder im Terminal `bash ~/.gg-sicherung/werkzeug/status.sh`).
- **Eine Mitteilung „GG Sicherung“ erscheint:** Dann hat etwas nicht geklappt. In Claude `/sicherung` fragen, Claude erklärt die Ursache.
- **Datei von gestern zurückholen:** In Claude z. B. „Hol mir die Notiz Angebote.md von gestern zurück“. Sie landet in einem neuen Ordner `Wiederhergestellt-…`, es wird nie etwas überschrieben.

## Neuer Mac

GitHub-Anmeldung und das Passwort aus „Passwörter“ bereithalten, dann in diesem Ordner: `bash installieren.sh --neuer-mac`. Alles kommt in einen Ordner `Wiederhergestellt-…`. Das Zurücksortieren am besten zusammen mit GG Digital machen. **Erst danach** die Sicherung wieder einschalten: `bash installieren.sh --fortsetzen`.

## Was nicht gesichert wird

Videos, Dateien über 50 MB, Programm-Zwischenspeicher (z. B. `node_modules`) und Claude-Gesprächsmitschriften. Eigene Ausnahmen: eine Zeile pro Muster in `~/.config/gg-sicherung/ausschluss-eigen.txt`.

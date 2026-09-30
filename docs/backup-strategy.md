# Backup-Strategie

## Ziel

Die Backup-Strategie sichert wichtige Anwendungsdaten und Konfigurationen außerhalb des produktiven VPS.

Sie soll insbesondere die Wiederherstellung der betriebenen Anwendungen und ihrer Daten nach Datenverlust, Fehlkonfigurationen oder einem Ausfall des Servers unterstützen.

Es handelt sich nicht um ein vollständiges Abbild des Ubuntu-Systems. Host-Konfigurationen, die nicht ausdrücklich vom Backup-Prozess erfasst werden, müssten bei einem vollständigen Neuaufbau erneut eingerichtet werden.

## Gesicherte Bestandteile

Der Backup-Prozess erfasst unter anderem:

- PostgreSQL-Datenbanken für den RAG-Chat und n8n
- PostgreSQL-Rollen und globale Datenbankinformationen
- separat exportierte n8n-Workflows im JSON-Format
- persistente n8n-Daten
- n8n- und PostgreSQL-Docker-Compose-Konfigurationen
- die produktive n8n-Environment-Konfiguration
- Nginx-Konfiguration
- relevante Zertifikatsdateien
- die root-crontab
- das Backup-Skript selbst
- die aktuell verwendeten Docker-Images und Versionen

Da die Sicherung sensible Anwendungs- und Konfigurationsdaten enthalten kann, wird sie vor der externen Speicherung verschlüsselt.

## Ablauf

```text
PostgreSQL-Dumps + n8n-Daten + Konfiguration
                    |
                    v
             Validierungsprüfungen
                    |
                    v
                 TAR-Archiv
                    |
                    v
             GPG-Verschlüsselung
                    |
                    v
              SHA-256-Prüfsumme
                    |
                    v
          Upload über rclone zu R2
                    |
                    v
          erneuter Download der Kopie
                    |
                    v
            SHA-256-Vergleich
                    |
                    v
              lokale Bereinigung
```

## Datenbanken

Die beiden PostgreSQL-Datenbanken werden mit `pg_dump` im Custom-Format exportiert.

Nach jedem Dump wird mit `pg_restore --list` geprüft, ob PostgreSQL das erzeugte Dump-Archiv lesen kann. Diese Prüfung erkennt grundlegende Probleme mit der Datei, ersetzt jedoch keinen tatsächlichen Restore-Test.

PostgreSQL-Rollen und andere globale Informationen werden zusätzlich mit `pg_dumpall --globals-only` exportiert. Das Skript prüft anschließend, dass die erzeugte Datei vorhanden und nicht leer ist.

## n8n und Konfiguration

n8n-Workflows werden zusätzlich über die n8n-CLI als einzelne JSON-Dateien exportiert. Der Backup-Lauf wird abgebrochen, falls dabei keine Workflow-Dateien erzeugt wurden.

Zusätzlich werden persistente n8n-Daten und ausgewählte Konfigurationen gesichert. Dazu gehören unter anderem Docker-Compose-Dateien, Nginx-Konfiguration, Environment-Konfiguration, Zertifikatsdateien, die root-crontab und Informationen über die aktuell verwendeten Container-Images.

Damit enthält die Sicherung sowohl Anwendungsdaten als auch wichtige Informationen für einen späteren Wiederaufbau, stellt jedoch kein vollständiges Betriebssystem-Backup dar.

## Archivierung und Verschlüsselung

Die gesammelten Daten werden zunächst zu einem TAR-Archiv zusammengeführt.

Mit `tar -tf` wird geprüft, ob das erzeugte Archiv lesbar ist und sein Inhalt aufgelistet werden kann.

Anschließend wird das Archiv mit GPG verschlüsselt. Erst die verschlüsselte Datei wird in den externen Backup-Speicher übertragen.

Der zur Entschlüsselung erforderliche private Schlüssel muss unabhängig vom zu sichernden VPS verfügbar sein, damit ein vollständiger Serververlust nicht gleichzeitig die Wiederherstellung unmöglich macht.

## Externe Speicherung und Integritätsprüfung

Die verschlüsselte Backup-Datei wird über rclone zu Cloudflare R2 übertragen.

Vor dem Upload wird ihre SHA-256-Prüfsumme berechnet.

Nach dem Upload wird die gespeicherte Datei erneut von R2 heruntergeladen und ebenfalls gehasht. Der Backup-Lauf wird nur fortgesetzt, wenn beide SHA-256-Werte übereinstimmen.

Damit wird überprüft, dass die extern gespeicherte verschlüsselte Datei mit der zuvor erzeugten lokalen Datei identisch ist.

Diese Prüfung bestätigt die Übertragungsintegrität, aber noch nicht die erfolgreiche Wiederherstellbarkeit der enthaltenen Anwendungen oder Datenbanken.

## Aufbewahrung und Bereinigung

Nach einem erfolgreichen Backup werden lokale Arbeitsdateien, das unverschlüsselte TAR-Archiv, die lokale verschlüsselte Kopie und die temporär heruntergeladene Verifikationsdatei entfernt.

Im externen Speicher werden die neuesten 30 verschlüsselten Backups aufbewahrt. Ältere Sicherungen werden automatisch entfernt.

Zusätzlich bereinigt das Skript mögliche Überreste abgebrochener vorheriger Läufe:

- temporäre Arbeitsverzeichnisse
- zurückgebliebene unverschlüsselte TAR-Archive
- temporäre Verifikationsdateien
- temporäre PostgreSQL-Dumps im Datenbankcontainer
- temporäre n8n-CLI- und Workflow-Exportdateien

Die zeitbasierte Bereinigung auf dem Host berücksichtigt dabei auch Fälle, in denen die normale Exit-Routine beispielsweise durch einen harten Prozessabbruch oder Systemausfall nicht ausgeführt werden konnte.

## Fehlerbehandlung

Das Skript verwendet `set -euo pipefail`, damit Fehler, nicht gesetzte Variablen und fehlgeschlagene Pipeline-Bestandteile den Backup-Lauf zuverlässig abbrechen.

Eine zentrale Exit-Routine entfernt bei regulären Fehlern temporäre Dateien aus dem aktuellen Lauf.

Bei einem fehlgeschlagenen Backup wird zusätzlich eine E-Mail-Benachrichtigung versendet.

Eine bereinigte Beispielversion des verwendeten Skripts ist unter [`scripts/backup-example.sh`](../scripts/backup-example.sh) verfügbar.

## Restore-Test

Die Prüfungen innerhalb des Backup-Skripts kontrollieren die Lesbarkeit der Dumps und des TAR-Archivs sowie die Integrität der hochgeladenen Datei. Sie ersetzen keinen tatsächlichen Restore.

Am 30.09.2026 wurde deshalb ein vorhandenes Backup aus Cloudflare R2 heruntergeladen, entschlüsselt und in einer getrennten PostgreSQL-Testumgebung wiederhergestellt.

Beide Datenbank-Dumps konnten ohne Fehler eingespielt werden. Ausgewählte Zeilenzahlen stimmten zum Zeitpunkt des Tests mit den produktiven Datenbanken überein. Außerdem waren alle fünf separat exportierten Workflow-Dateien gültiges JSON.

Der durchgeführte Test ist unter [`restore-test.md`](restore-test.md) dokumentiert. Wiederverwendbare SQL-Prüfungen befinden sich unter [`verification/verification.sql`](../verification/verification.sql).

## Grenzen und mögliche Verbesserungen

Die aktuelle Backup-Lösung ist auf die bestehende persönliche Infrastruktur zugeschnitten.

Mögliche Weiterentwicklungen sind insbesondere:

- Schutz vor parallel gestarteten Backup-Läufen
- automatisierte regelmäßige Restore-Tests
- Überwachung des Alters des letzten erfolgreichen Backups
- zusätzliche Benachrichtigung bei ausbleibenden Backup-Läufen
- automatische Prüfung, ob neu hinzugekommene Anwendungen und Konfigurationen weiterhin vom Backup erfasst werden
- zusätzliche unveränderbare oder gegen versehentliches Löschen geschützte Backup-Kopien

Ein erster manueller Restore-Test wurde erfolgreich durchgeführt. Offen bleiben regelmäßige Wiederholungen sowie ein vollständiger Test der wiederhergestellten Anwendungen.
# Restore-Test

## Ziel

Mit diesem Test wurde geprüft, ob sich eines der verschlüsselten Backups tatsächlich wiederherstellen lässt.

Dafür wurde das Backup aus Cloudflare R2 heruntergeladen und in einer getrennten PostgreSQL-Testumgebung wiederhergestellt. Die produktiven Datenbanken wurden dabei nicht überschrieben.

Getestet wurde das Backup:

```text
n8n+ragdb+config-20260930-1907.tar.gpg
```

Der Test fand am 30.09.2026 statt.

## Testumgebung

Für den Test wurde ein neuer PostgreSQL-Container mit derselben Version wie in der produktiven Umgebung gestartet:

```text
Image: pgvector/pgvector:0.8.6-pg17
PostgreSQL: 17.11
```

Der Container erhielt:

- ein eigenes Docker-Netzwerk
- ein neues leeres Docker-Volume
- keinen veröffentlichten Port
- keine Verbindung zum produktiven n8n-Netzwerk

Damit konnten die Datenbanken wiederhergestellt werden, ohne die produktiven Datenbanken zu ersetzen.

## Ablauf

Der Restore-Test bestand aus folgenden Schritten:

1. Backup aus Cloudflare R2 herunterladen
2. Backup mit GPG entschlüsseln
3. TAR-Archiv prüfen und entpacken
4. separaten PostgreSQL-Container starten
5. gesicherte Datenbankbenutzer wiederherstellen
6. leere Testdatenbanken erstellen
7. beide Datenbank-Dumps mit `pg_restore` einspielen
8. wiederhergestellte Tabellen und Zeilenzahlen prüfen
9. ausgewählte Zeilenzahlen mit der Produktion vergleichen
10. Workflow-Dateien prüfen
11. Testcontainer und temporäre Dateien entfernen

Die Datenbanken wurden mit folgendem Grundmuster wiederhergestellt:

```bash
pg_restore \
  --exit-on-error \
  --verbose \
  --username=restore_admin \
  --dbname=TESTDATENBANK \
  /restore/DATENBANK.dump
```

Mit `--exit-on-error` wird der Restore beim ersten Datenbankfehler abgebrochen.

Die allgemeinen SQL-Prüfungen sind unter [`verification/verification.sql`](../verification/verification.sql) abgelegt.

## Inhalt des Backups

Das entschlüsselte Archiv enthielt die erwarteten Datenbankdateien:

```text
ragdb.dump
n8n_db.dump
postgres-globals.sql
```

Außerdem waren folgende Bereiche vorhanden:

```text
certs
config
n8n-data
workflows
```

Die Konfigurationsdateien wurden nicht inhaltlich ausgegeben, da sie Zugangsdaten oder andere sensible Informationen enthalten können.

## RAG-Datenbank

Die RAG-Datenbank wurde ohne Warnungen oder Fehler wiederhergestellt.

Folgende Zeilenzahlen wurden gemessen:

| Tabelle | Zeilen |
|---|---:|
| `messages` | 37 |
| `threads` | 13 |
| `user_memory` | 0 |
| `users` | 0 |

Die Tabellen `users` und `user_memory` waren zum Zeitpunkt des Backups leer. Aus dem Restore-Test allein lässt sich nicht ableiten, ob diese Tabellen für den aktuellen Workflow erforderlich, optional oder noch ungenutzt sind. Die leeren Tabellen stellen keinen Restore-Fehler dar, da sie genauso wiederhergestellt wurden, wie sie im Backup enthalten waren.

Von den 37 Nachrichten enthielten 25 ein gespeichertes Embedding. Alle vorhandenen Embeddings hatten 1536 Dimensionen.

Die erwarteten Datenbankerweiterungen, Tabellenverknüpfungen und Indizes wurden ebenfalls wiederhergestellt.

## n8n-Datenbank

Auch die n8n-Datenbank wurde ohne Warnungen oder Fehler wiederhergestellt.

Die wiederhergestellte Datenbank enthielt:

```text
131 Anwendungstabellen
253 Datenbankmigrationen
```

Ausgewählte Zeilenzahlen:

| Tabelle | Zeilen |
|---|---:|
| `credentials_entity` | 4 |
| `execution_entity` | 0 |
| `migrations` | 253 |
| `user` | 1 |
| `workflow_entity` | 5 |

Die Datenbankstruktur und die zugehörigen Indizes wurden ohne Fehler erstellt.

Es wurden keine Zugangsdaten, Workflows, Benutzerinformationen oder Nachrichteninhalte angezeigt.

## Vergleich mit der Produktion

Für den Vergleich wurden nur Zeilenzahlen aus den produktiven Datenbanken gelesen. Dabei wurden keine Anwendungsdaten verändert.

### RAG-Datenbank

| Tabelle | Restore | Produktion |
|---|---:|---:|
| `messages` | 37 | 37 |
| `threads` | 13 | 13 |
| `user_memory` | 0 | 0 |
| `users` | 0 | 0 |

### n8n-Datenbank

| Tabelle | Restore | Produktion |
|---|---:|---:|
| `credentials_entity` | 4 | 4 |
| `execution_entity` | 0 | 0 |
| `migrations` | 253 | 253 |
| `user` | 1 | 1 |
| `workflow_entity` | 5 | 5 |

Alle verglichenen Zeilenzahlen stimmten zum Zeitpunkt des Tests überein.

Gleiche Zeilenzahlen beweisen nicht, dass jeder einzelne Datenwert identisch ist. Sie sind eine zusätzliche Kontrolle dafür, dass die erwarteten Daten im Backup vorhanden waren.

## Workflow-Dateien

Das Backup enthielt fünf separat exportierte n8n-Workflows.

Alle fünf JSON-Dateien konnten mit `jq` gelesen werden und waren syntaktisch gültig. Ihre tatsächliche Ausführung in n8n wurde bei diesem Restore-Test nicht geprüft.

## Bereinigung

Nach dem Test wurden folgende Bestandteile entfernt:

- Testcontainer
- Test-Volume
- Testnetzwerk
- entschlüsseltes Backup
- extrahierte Dateien
- temporäre Restore-Protokolle

Anschließend wurde kontrolliert, dass diese Testressourcen nicht mehr vorhanden waren.

Der produktive PostgreSQL-Container lief nach der Bereinigung weiterhin.

## Ergebnis

Der Restore-Test war erfolgreich.

Nachgewiesen wurde:

- Das Backup konnte aus R2 heruntergeladen werden.
- Die GPG-Entschlüsselung funktionierte.
- Das Archiv enthielt die erwarteten Dateien.
- Beide Datenbank-Dumps konnten wiederhergestellt werden.
- Die geprüften Zeilenzahlen stimmten mit der Produktion überein.
- Die exportierten Workflow-Dateien waren gültiges JSON.
- Die temporäre Testumgebung konnte vollständig entfernt werden.

## Grenzen des Tests

Nicht getestet wurden:

- vollständiger Neuaufbau eines leeren VPS
- Start von n8n mit der wiederhergestellten Datenbank
- Entschlüsselung und Verwendung der n8n-Credentials
- tatsächliche Ausführung der wiederhergestellten Workflows
- Start der RAG-Anwendung mit der wiederhergestellten Datenbank
- Wiederherstellung von Nginx und TLS
- vollständiger Vergleich aller Datenbankinhalte

Der Test zeigt damit, dass sich die beiden Datenbank-Backups technisch wiederherstellen lassen. Er beweist noch nicht, dass die vollständigen Anwendungen nach einem kompletten Serververlust sofort wieder funktionieren würden.
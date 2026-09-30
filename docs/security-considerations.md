# Sicherheitsbetrachtungen

## Ziel und Abgrenzung

Die Umgebung wurde für eigene Anwendungen und zum praktischen Erlernen von Linux-Administration, Containerisierung, Networking und grundlegender Systemsicherheit aufgebaut.

Sie ist nicht als vollständig gehärtete Enterprise-Infrastruktur konzipiert. Die folgenden Maßnahmen sollen die Angriffsfläche reduzieren und den Betrieb absichern, ohne den Anspruch einer vollständigen Sicherheitsarchitektur zu erheben.

## Netzwerkzugriff

Öffentliche Webanfragen werden über HTTPS von Nginx angenommen.

Der n8n-Container veröffentlicht seinen Anwendungsport ausschließlich auf dem lokalen Loopback-Interface des Hosts:

```text
127.0.0.1:5678
```

Dadurch wird n8n nicht direkt über diesen Port im öffentlichen Netzwerk des VPS bereitgestellt. Der öffentliche Zugriff erfolgt stattdessen über den Nginx Reverse Proxy.

Der PostgreSQL-Container veröffentlicht keinen Datenbank-Port auf dem Host. n8n und andere berechtigte Container erreichen PostgreSQL über das gemeinsame interne Docker-Netzwerk.

## Administrativer Zugriff

Die Administration des Servers erfolgt über SSH mit Public-Key-Authentifizierung.

Passwortbasierte SSH-Anmeldung ist deaktiviert.

Für den administrativen Netzwerkzugriff wird zusätzlich Tailscale verwendet. Dadurch können administrative Verbindungen über ein privates Overlay-Netzwerk erfolgen, anstatt zusätzliche Verwaltungsdienste direkt öffentlich bereitzustellen.

## Backup-Sicherheit

Backups werden vor der externen Speicherung mit GPG verschlüsselt.

Dadurch sollen die gesicherten Daten auch dann nicht unmittelbar lesbar sein, wenn auf die gespeicherten Backup-Dateien außerhalb des VPS zugegriffen werden kann.

Für Backup-Dateien werden zusätzlich SHA-256-Prüfsummen verwendet, um beispielsweise Beschädigungen bei Speicherung oder Übertragung erkennen zu können.

Die eigentliche Backup-Strategie ist unter [`backup-strategy.md`](backup-strategy.md) dokumentiert.

## Bekannte Einschränkungen

### Container laufen teilweise als Root

n8n und der separate Task-Runner-Container laufen derzeit innerhalb ihrer Container mit Root-Rechten.

Die Konfiguration entstand, nachdem beim Betrieb mit einem weniger privilegierten Benutzer Berechtigungsprobleme mit dem eingebundenen n8n-Datenverzeichnis auftraten.

Für einen stärker gehärteten Betrieb wäre es vorzuziehen, die Dateiberechtigungen entsprechend anzupassen und die Dienste anschließend mit möglichst geringen Rechten auszuführen.

### Gemeinsame Environment-Datei

n8n und der Task-Runner-Container verwenden derzeit dieselbe Environment-Datei.

Damit erhält der Task-Runner auch Environment-Variablen, die er möglicherweise nicht für seine eigene Funktion benötigt.

Eine mögliche Verbesserung wäre, die Konfiguration aufzuteilen und jedem Container ausschließlich die tatsächlich erforderlichen Secrets und Einstellungen bereitzustellen.

### Monitoring und Logging

Die Umgebung verfügt nicht über eine umfassende zentralisierte Monitoring- oder Log-Management-Plattform.

Für einen umfangreicheren produktiven Betrieb wären unter anderem zentralisierte Logs, Dienstüberwachung und automatisierte Alarmierung sinnvolle Erweiterungen.

## Öffentliche Repository-Version

Die öffentlich dokumentierte Konfiguration wurde bewusst bereinigt.

Nicht veröffentlicht werden unter anderem:

- reale Passwörter und Token
- private Schlüssel
- produktive Domains und interne Identifikatoren, soweit sie für das Verständnis nicht erforderlich sind
- Datenbankinhalte
- Session- und Authentifizierungsdaten
- vollständige produktive Environment-Dateien

Die `.gitignore`-Konfiguration verhindert zusätzlich, dass typische Secret-, Environment-, Backup- und Schlüsseldateien versehentlich über normale Git-Befehle aufgenommen werden.

Die veröffentlichte `.env.example` enthält ausschließlich Platzhalter und nicht-sensitive Beispielwerte.

Die Beispielkonfiguration soll die technische Struktur nachvollziehbar machen, ohne die produktive Umgebung unnötig offenzulegen.
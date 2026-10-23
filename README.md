# postgres-ohne-gosu

Offizielles Abbild `postgres:<major>-alpine` ohne `gosu` und `su-exec`, fest als Nutzer `postgres` (uid 70). Veröffentlicht als `ghcr.io/amadudl/postgres-ohne-gosu`.

## Warum

Das offizielle Abbild enthält `gosu` 1.19, gebaut mit Go 1.24.6. Trivy meldet dafür rund 26 Befunde in der Go Standardbibliothek, `golang.org/x/sys` und `github.com/moby/sys/user`. Upstream baut `gosu` nach eigener Richtlinie nicht für solche CVEs neu ([tianon/gosu SECURITY.md](https://github.com/tianon/gosu/blob/master/SECURITY.md)). Die Meldungen bleiben im offiziellen Abbild also dauerhaft.

`docker-entrypoint.sh` des offiziellen Abbilds ruft `gosu` nur, wenn der Container als root startet. Läuft er als `postgres`, entfällt der Rechtewechsel; die Dokumentation des Abbilds beschreibt diesen Betrieb unter „Arbitrary --user Notes“. Dieses Abbild entfernt `gosu` und `su-exec` und setzt `USER postgres`. Datenbank, Entrypoint und Bibliotheken bleiben die des offiziellen Abbilds, dazu kommen die Alpine Sicherheitsupdates (`apk upgrade`).

## Tags

| Tag | Bedeutung |
| --- | --- |
| `16.15-alpine`, `17.11-alpine` | Patchversion, wird wöchentlich mit neuen Alpine Updates neu gebaut. Diesen Tag in Coolify und Compose verwenden. |
| `16-alpine`, `17-alpine` | Hauptversion, folgt jeder neuen Patchversion. |
| `16.15-alpine-JJJJMMTT` | Unveränderlicher Stand eines Laufs, für den Rückweg. |

## Bau und Prüfung

Die Pipeline `.github/workflows/build.yml` läuft bei jedem Push auf `main`, montags um 03:17 UTC und von Hand. Je Hauptversion:

1. Digest von `postgres:<major>-alpine` holen und als Basis pinnen.
2. Bauen.
3. `test.sh`: Abbild läuft als uid 70 ohne `gosu`; ein Volume, das das offizielle Abbild angelegt hat, startet ohne Rechteänderung, Daten bleiben erhalten, Neustart klappt; ein frisches Volume lässt sich initialisieren.
4. Trivy 0.76.1 (wie der CVE Watch auf newserver): Abbruch bei behebbaren HIGH oder CRITICAL Befunden.
5. Nur auf `main`: Push der drei Tags nach GHCR.

Lokal: `docker build --build-arg BASE=postgres:17-alpine -t pg-test . && sh test.sh postgres:17-alpine pg-test`

## Umstellen einer bestehenden Datenbank

1. Sicherung anlegen (`pg_dump -Fc`).
2. Prüfen, dass alle Dateien im Datenverzeichnis uid 70 gehören: `docker exec <container> find /var/lib/postgresql/data ! -user postgres` muss leer sein.
3. Abbild auf `ghcr.io/amadudl/postgres-ohne-gosu:<gleiche Patchversion>-alpine` setzen und neu starten.

Rückweg: Abbild zurück auf das vorige offizielle Abbild setzen und neu starten; das Datenverzeichnis bleibt unverändert.

## Fallstricke

- GitHub schaltet geplante Läufe in öffentlichen Repos nach 60 Tagen ohne Aktivität ab. Dann bleiben die Alpine Updates aus, bis der Lauf wieder aktiviert oder von Hand gestartet wird.
- Für einen Wechsel der Hauptversion (etwa 16 auf 17) reicht kein Abbildtausch, dafür braucht es `pg_upgrade` oder Dump und Restore.

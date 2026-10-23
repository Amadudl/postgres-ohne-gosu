# Offizielles Postgres Alpine Abbild ohne gosu und su-exec.
#
# gosu wird upstream bewusst nicht fuer Go CVEs neu gebaut (tianon/gosu SECURITY.md),
# Scanner melden deshalb dauerhaft rund 26 Go Befunde. Dieses Abbild entfernt gosu und
# laeuft fest als Nutzer postgres (uid 70). Der offizielle docker-entrypoint.sh ruft gosu
# nur auf, wenn er als root startet; als postgres ueberspringt er den Rechtewechsel.
# Bestehende Volumes des offiziellen Abbilds gehoeren bereits uid 70 und laufen ohne chown.
#
# BASE setzt die Pipeline auf den Digest von postgres:<major>-alpine.
ARG BASE=postgres:17-alpine
FROM ${BASE}

USER root
RUN set -eux; \
    apk upgrade --no-cache; \
    rm -f /usr/local/bin/gosu /usr/local/bin/su-exec; \
    if command -v gosu || command -v su-exec; then exit 1; fi; \
    test "$(id -u postgres)" = 70

USER postgres

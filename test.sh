#!/bin/sh
# Prueft ein gebautes Abbild ohne gosu gegen das offizielle Basisabbild.
# Aufruf: sh test.sh <basisabbild> <neues_abbild>
# 1. Abbild laeuft als postgres, gosu und su-exec fehlen.
# 2. Volume vom offiziellen Abbild (Start als root, Rechtewechsel per gosu) startet mit dem
#    neuen Abbild ohne Rechteaenderung, Daten bleiben erhalten, Neustart klappt.
# 3. Frisches Volume laesst sich mit dem neuen Abbild initialisieren.
set -eu

BASE=$1
NEU=$2
ID=pgtest-$$
PW=test-$$
fehler() { echo "FEHLER: $*" >&2; exit 1; }

aufraeumen() {
  docker rm -f "$ID-alt" "$ID-neu" "$ID-frisch" >/dev/null 2>&1 || true
  docker volume rm "$ID-vol" "$ID-frisch" >/dev/null 2>&1 || true
}
trap aufraeumen EXIT INT TERM

bereit() { # bereit CONTAINER
  i=0
  until docker exec "$1" pg_isready -U app -d appdb -q >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -le 60 ] || { docker logs "$1" >&2; fehler "$1 wurde nicht bereit"; }
    sleep 2
  done
  # pg_isready meldet schon waehrend der Initialisierung bereit; auf den endgueltigen Server warten
  sleep 3
  until docker exec "$1" pg_isready -U app -d appdb -q >/dev/null 2>&1; do sleep 1; done
}

rechte() { # rechte VOLUME  Eigentuemer und Modus aller Dateien
  docker run --rm --user 0 --entrypoint sh -v "$1:/d" "$BASE" -c 'find /d -exec stat -c "%u:%g %a %n" {} + | sort -k3'
}

sql() { docker exec "$1" psql -U app -d appdb -tAc "$2"; }

echo "1. Abbildkonfiguration"
[ "$(docker image inspect -f '{{.Config.User}}' "$NEU")" = postgres ] || fehler "USER ist nicht postgres"
docker run --rm --entrypoint sh "$NEU" -c 'command -v gosu || command -v su-exec' && fehler "gosu oder su-exec vorhanden"
[ "$(docker run --rm --entrypoint id "$NEU" -u)" = 70 ] || fehler "uid ist nicht 70"
v_alt=$(docker run --rm --entrypoint postgres "$BASE" --version)
v_neu=$(docker run --rm --entrypoint postgres "$NEU" --version)
[ "$v_alt" = "$v_neu" ] || fehler "Version weicht ab: $v_alt gegen $v_neu"
echo "   ok: $v_neu, USER postgres, uid 70, ohne gosu und su-exec"

echo "2. Bestehendes Volume aus dem offiziellen Abbild"
docker volume create "$ID-vol" >/dev/null
docker run -d --name "$ID-alt" -e POSTGRES_PASSWORD="$PW" -e POSTGRES_USER=app -e POSTGRES_DB=appdb \
  -v "$ID-vol:/var/lib/postgresql/data" "$BASE" >/dev/null
bereit "$ID-alt"
sql "$ID-alt" "create table probe(x int); insert into probe values (42);" >/dev/null
docker stop "$ID-alt" >/dev/null
rechte "$ID-vol" > "/tmp/$ID-vor"
awk '$1 != "70:70"' "/tmp/$ID-vor" | grep -q . && fehler "Volume enthaelt Dateien, die nicht uid 70 gehoeren"

docker run -d --name "$ID-neu" -e POSTGRES_PASSWORD="$PW" -e POSTGRES_USER=app -e POSTGRES_DB=appdb \
  -v "$ID-vol:/var/lib/postgresql/data" "$NEU" >/dev/null
bereit "$ID-neu"
[ "$(sql "$ID-neu" 'select x from probe')" = 42 ] || fehler "Daten fehlen nach dem Wechsel"
[ "$(docker exec "$ID-neu" awk '/^Uid/{print $2}' /proc/1/status)" = 70 ] || fehler "PID 1 laeuft nicht als uid 70"
sql "$ID-neu" "insert into probe values (43);" >/dev/null
docker restart "$ID-neu" >/dev/null
bereit "$ID-neu"
[ "$(sql "$ID-neu" 'select count(*) from probe')" = 2 ] || fehler "Daten fehlen nach dem Neustart"
docker stop "$ID-neu" >/dev/null
rechte "$ID-vol" > "/tmp/$ID-nach"
geaendert=$(join -1 3 -2 3 "/tmp/$ID-vor" "/tmp/$ID-nach" | awk '$2 != $4 || $3 != $5' | wc -l)
rm -f "/tmp/$ID-vor" "/tmp/$ID-nach"
[ "$geaendert" -eq 0 ] || fehler "$geaendert Dateien mit geaenderten Rechten"
echo "   ok: Daten erhalten, Neustart ok, Eigentuemer und Modus unveraendert"

echo "3. Frisches Volume"
docker volume create "$ID-frisch" >/dev/null
docker run -d --name "$ID-frisch" -e POSTGRES_PASSWORD="$PW" -e POSTGRES_USER=app -e POSTGRES_DB=appdb \
  -v "$ID-frisch:/var/lib/postgresql/data" "$NEU" >/dev/null
bereit "$ID-frisch"
[ "$(sql "$ID-frisch" 'select 1')" = 1 ] || fehler "frische Datenbank antwortet nicht"
echo "   ok: Initialisierung als postgres"

echo "Alle Pruefungen bestanden."

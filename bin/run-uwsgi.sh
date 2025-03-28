#!/usr/bin/env sh
set -e

if echo "$PORT" | grep -qF :; then
    HTTP_SOCKET="$PORT"
else
    HTTP_SOCKET=":$PORT"
fi

UWSGI_LISTEN="${UWSGI_LISTEN:-128}"
PORT="${PORT:-8000}"
HTTP_KEEPALIVE="${UWSGI_HTTP_KEEPALIVE:-120}"
CHEAPER_OVERLOAD="${UWSGI_CHEAPER_OVERLOAD:-30}"
MAX_REQUESTS="${UWSGI_MAX_REQUESTS:-10000}"
WORKER_RELOAD_MERCY="${UWSGI_WORKER_RELOAD_MERCY:-10}"
UWSGI_HARAKIRI="${UWSGI_HARAKIRI:-60}"
UWSGI_PROCESSES="${UWSGI_PROCESSES:-1}"

PROMETHEUS_MULTIPROC_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf $PROMETHEUS_MULTIPROC_DIR" INT TERM EXIT

# shellcheck disable=SC2086
exec uwsgi \
    --module=glitchtip.wsgi:application \
    --env DJANGO_SETTINGS_MODULE=glitchtip.settings \
    --env PROMETHEUS_MULTIPROC_DIR="$PROMETHEUS_MULTIPROC_DIR" \
    --master --pidfile=/tmp/project-master.pid \
    --buffer-size=83146 \
    --log-x-forwarded-for \
    --log-format-strftime \
    --http="$HTTP_SOCKET" \
    --http-keepalive="$HTTP_KEEPALIVE" \
    --http-auto-chunked \
    --add-header="Connection: Close" \
    --http-chunked-input \
    --cheaper-algo=busyness \
    --cheaper-overload="$CHEAPER_OVERLOAD" \
    --cheaper-step=1 \
    --cheaper-busyness-max=50 \
    --cheaper-busyness-min=25 \
    --cheaper-busyness-multiplier=20 \
    --harakiri="$UWSGI_HARAKIRI" \
    --max-requests="$MAX_REQUESTS" \
    --worker-reload-mercy="$WORKER_RELOAD_MERCY" \
    --die-on-term \
    --enable-threads \
    --single-interpreter \
    --post-buffering \
    --ignore-sigpipe \
    --ignore-write-errors \
    --disable-write-exception \
    --lazy-apps \
    --listen="$UWSGI_LISTEN" $UWSGI_ARGS \
    --processes="$UWSGI_PROCESSES"

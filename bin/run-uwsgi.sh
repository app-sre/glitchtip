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

exec uwsgi \
    --module=glitchtip.wsgi:application \
    --env DJANGO_SETTINGS_MODULE=glitchtip.settings \
    --master --pidfile=/tmp/project-master.pid \
    --log-x-forwarded-for \
    --log-format-strftime \
    --http=$HTTP_SOCKET \
    --http-keepalive=$HTTP_KEEPALIVE \
    --http-auto-chunked \
    --add-header="Connection: Close" \
    --cheaper-algo=busyness \
    --cheaper-overload=$CHEAPER_OVERLOAD \
    --cheaper-step=1 \
    --cheaper-busyness-max=50 \
    --cheaper-busyness-min=25 \
    --cheaper-busyness-multiplier=20 \
    --harakiri=60 \
    --max-requests=$MAX_REQUESTS \
    --worker-reload-mercy=$WORKER_RELOAD_MERCY \
    --die-on-term \
    --enable-threads \
    --single-interpreter \
    --post-buffering \
    --buffer-size=83146 \
    --ignore-sigpipe \
    --ignore-write-errors \
    --disable-write-exception \
    --listen=$UWSGI_LISTEN $UWSGI_ARGS

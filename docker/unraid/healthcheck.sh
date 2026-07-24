#!/bin/sh
set -eu
# shellcheck disable=SC1091
[ -r /config/secrets.env ] && . /config/secrets.env

curl -fsS --max-time 5 http://127.0.0.1:8080/api/sidecar-health >/dev/null
if [ -n "${AISSTREAM_API_KEY:-${VITE_AISSTREAM_API_KEY:-}}" ]; then
  curl -fsS --max-time 5 http://127.0.0.1:3004/health >/dev/null
fi
REDISCLI_AUTH="${REDIS_PASSWORD:?}" redis-cli -h 127.0.0.1 -p 6379 ping | grep -qx PONG
curl -fsS --max-time 5 -H "Authorization: Bearer ${REDIS_TOKEN:?}" \
  -H 'Content-Type: application/json' -d '["PING"]' http://127.0.0.1:8079/ | grep -q PONG

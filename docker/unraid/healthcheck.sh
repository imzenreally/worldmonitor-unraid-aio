#!/bin/sh
set -eu

SECRETS=/config/secrets.env
[ -f "$SECRETS" ] && [ ! -L "$SECRETS" ] || exit 1
REDIS_PASSWORD="$(awk -F= '$1 == "REDIS_PASSWORD" { print substr($0, index($0, "=") + 1); exit }' "$SECRETS")"
REDIS_TOKEN="$(awk -F= '$1 == "REDIS_TOKEN" { print substr($0, index($0, "=") + 1); exit }' "$SECRETS")"
[ "${#REDIS_PASSWORD}" -eq 64 ] && [ "${#REDIS_TOKEN}" -eq 64 ] || exit 1

curl -fsS --max-time 5 http://127.0.0.1:8080/api/sidecar-health >/dev/null
if [ -n "${AISSTREAM_API_KEY:-${VITE_AISSTREAM_API_KEY:-}}" ]; then
  curl -fsS --max-time 5 http://127.0.0.1:3004/health >/dev/null
fi
REDISCLI_AUTH="$REDIS_PASSWORD" valkey-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -qx PONG

curl --config - <<EOF | grep -q PONG
silent
show-error
fail
max-time = 5
header = "Authorization: Bearer $REDIS_TOKEN"
header = "Content-Type: application/json"
data = "[\"PING\"]"
url = "http://127.0.0.1:8079/"
EOF

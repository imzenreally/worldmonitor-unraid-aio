#!/bin/sh
set -eu
umask 077

mkdir -p /config/redis /config/state /tmp/nginx-client-body /tmp/nginx-proxy \
  /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi
chown -R appuser:appgroup /config /tmp/nginx-client-body /tmp/nginx-proxy \
  /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi

SECRETS=/config/secrets.env
if [ ! -s "$SECRETS" ]; then
  tmp="${SECRETS}.tmp.$$"
  {
    printf 'RELAY_SHARED_SECRET=%s\n' "$(openssl rand -hex 32)"
    printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'REDIS_TOKEN=%s\n' "$(openssl rand -hex 32)"
  } > "$tmp"
  chmod 600 "$tmp"
  chown appuser:appgroup "$tmp"
  mv "$tmp" "$SECRETS"
fi
chmod 600 "$SECRETS"
# shellcheck disable=SC1090
. "$SECRETS"
export RELAY_SHARED_SECRET REDIS_PASSWORD REDIS_TOKEN

export LOCAL_API_PORT="${LOCAL_API_PORT:-46123}"
export LOCAL_API_MODE=docker
export LOCAL_API_CLOUD_FALLBACK=false
export LOCAL_API_TOKEN="${LOCAL_API_TOKEN:-$(openssl rand -hex 32)}"
export UPSTASH_REDIS_REST_URL=http://127.0.0.1:8079
export UPSTASH_REDIS_REST_TOKEN="$REDIS_TOKEN"
export UPSTASH_ALLOW_INSECURE_HTTP=true
export WS_RELAY_URL=http://127.0.0.1:3004
export REDIS_REST_HOST=127.0.0.1
export RELAY_HOST=127.0.0.1
export SRH_TOKEN="$REDIS_TOKEN"
export SRH_CONNECTION_STRING="redis://:${REDIS_PASSWORD}@127.0.0.1:6379"
export PORT=3004

{
  printf 'bind 127.0.0.1\n'
  printf 'protected-mode yes\n'
  printf 'port 6379\n'
  printf 'requirepass %s\n' "$REDIS_PASSWORD"
  printf 'dir /config/redis\n'
  printf 'appendonly yes\n'
  printf 'appendfsync everysec\n'
  printf 'save 900 1\n'
  printf 'save 300 10\n'
  printf 'save 60 10000\n'
  printf 'maxmemory %s\n' "${REDIS_MAXMEMORY:-256mb}"
  printf 'maxmemory-policy allkeys-lru\n'
} > /config/redis.conf
chmod 600 /config/redis.conf
chown appuser:appgroup /config/redis.conf

envsubst '$LOCAL_API_PORT $LOCAL_API_TOKEN' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
node -e "const fs=require('fs');const p='/tmp/nginx.conf';let s=fs.readFileSync(p,'utf8');s=s.replace('error_log /dev/stderr warn;','error_log stderr warn;').replace('access_log /dev/stdout main;','access_log off;');fs.writeFileSync(p,s);"
chmod 600 /tmp/nginx.conf
chown appuser:appgroup /tmp/nginx.conf

if [ "${WM_TEST_MODE:-0}" = 1 ]; then
  echo "World Monitor AIO configuration generated"
  exit 0
fi

exec /usr/bin/supervisord -c /app/docker/unraid/supervisord.conf

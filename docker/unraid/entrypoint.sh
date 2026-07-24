#!/bin/sh
set -eu
umask 077

fail() {
  printf 'World Monitor AIO startup refused: %s\n' "$1" >&2
  exit 1
}

safe_directory() {
  path="$1"
  if [ -L "$path" ]; then
    fail "$path must not be a symbolic link"
  fi
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    fail "$path exists but is not a directory"
  fi
  mkdir -p "$path"
}

safe_directory /config
# With all capabilities dropped, root cannot bypass ordinary directory mode bits.
# Take temporary ownership using CAP_CHOWN, initialize only known paths, then
# hand the mount back to the unprivileged runtime account.
chown root:root /config
chmod 0750 /config
safe_directory /config/redis
safe_directory /config/state
safe_directory /tmp/nginx-client-body
safe_directory /tmp/nginx-proxy
safe_directory /tmp/nginx-fastcgi
safe_directory /tmp/nginx-uwsgi
safe_directory /tmp/nginx-scgi

# Never recursively follow user-controlled content from the persistent mount.
chmod 0700 /config/redis /config/state

SECRETS=/config/secrets.env
if [ -L "$SECRETS" ]; then
  fail "$SECRETS must not be a symbolic link"
fi
if [ -e "$SECRETS" ] && [ ! -f "$SECRETS" ]; then
  fail "$SECRETS exists but is not a regular file"
fi

if [ ! -s "$SECRETS" ]; then
  tmp="$(mktemp /config/.secrets.env.XXXXXX)"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  {
    printf 'RELAY_SHARED_SECRET=%s\n' "$(openssl rand -hex 32)"
    printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'REDIS_TOKEN=%s\n' "$(openssl rand -hex 32)"
  } > "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$SECRETS"
  trap - EXIT HUP INT TERM
fi
chown root:root "$SECRETS"
chmod 0600 "$SECRETS"

RELAY_SHARED_SECRET=
REDIS_PASSWORD=
REDIS_TOKEN=
while IFS='=' read -r key value; do
  case "$key" in
    RELAY_SHARED_SECRET) RELAY_SHARED_SECRET="$value" ;;
    REDIS_PASSWORD) REDIS_PASSWORD="$value" ;;
    REDIS_TOKEN) REDIS_TOKEN="$value" ;;
    '') ;;
    *) fail "$SECRETS contains an unexpected key: $key" ;;
  esac
done < "$SECRETS"

for key in RELAY_SHARED_SECRET REDIS_PASSWORD REDIS_TOKEN; do
  eval "value=\${$key}"
  [ "${#value}" -eq 64 ] || fail "$key must contain exactly 64 lowercase hexadecimal characters"
  case "$value" in
    *[!0-9a-f]*) fail "$key must contain only lowercase hexadecimal characters" ;;
  esac
done
export REDIS_PASSWORD REDIS_TOKEN

export LOCAL_API_PORT=46123
export LOCAL_API_MODE=docker
export LOCAL_API_CLOUD_FALLBACK=false
export LOCAL_API_TOKEN="$(openssl rand -hex 32)"
export UPSTASH_REDIS_REST_URL=http://127.0.0.1:8079
export UPSTASH_REDIS_REST_TOKEN="$REDIS_TOKEN"
export UPSTASH_ALLOW_INSECURE_HTTP=true
export WS_RELAY_URL=http://127.0.0.1:3004
export REDIS_REST_HOST=127.0.0.1
export RELAY_HOST=127.0.0.1
export SRH_TOKEN="$REDIS_TOKEN"
export SRH_CONNECTION_STRING="redis://:${REDIS_PASSWORD}@127.0.0.1:6379"
export PORT=3004

REDIS_MAXMEMORY="${REDIS_MAXMEMORY:-256mb}"
printf '%s\n' "$REDIS_MAXMEMORY" | grep -Eq '^[1-9][0-9]*(b|kb|mb|gb)$' ||
  fail 'REDIS_MAXMEMORY must be a positive integer followed by b, kb, mb, or gb'
case "$REDIS_MAXMEMORY" in
  *gb) amount=${REDIS_MAXMEMORY%gb}; maximum=16 ;;
  *mb) amount=${REDIS_MAXMEMORY%mb}; maximum=16384 ;;
  *kb) amount=${REDIS_MAXMEMORY%kb}; maximum=16777216 ;;
  *b) amount=${REDIS_MAXMEMORY%b}; maximum=17179869184 ;;
esac
[ "$amount" -le "$maximum" ] || fail 'REDIS_MAXMEMORY must not exceed 16gb'

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
  printf 'maxmemory %s\n' "$REDIS_MAXMEMORY"
  printf 'maxmemory-policy allkeys-lru\n'
} > /tmp/valkey.conf
chmod 0600 /tmp/valkey.conf
chown appuser:appgroup /tmp/valkey.conf

envsubst '$LOCAL_API_PORT $LOCAL_API_TOKEN' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
node -e "const fs=require('fs');const p='/tmp/nginx.conf';let s=fs.readFileSync(p,'utf8');s=s.replace('error_log /dev/stderr warn;','error_log stderr warn;').replace('access_log /dev/stdout main;','access_log off;').replace('http {','http {\\n  server_tokens off;\\n  client_max_body_size 2m;\\n  client_header_timeout 10s;\\n  client_body_timeout 10s;\\n  send_timeout 30s;');fs.writeFileSync(p,s);"
chmod 0600 /tmp/nginx.conf
chown appuser:appgroup /tmp/nginx.conf

# Render the generated relay credential only into the two programs that need
# one of its scoped aliases, then remove the source variable before supervisor
# starts so unrelated child processes cannot inherit RELAY_SHARED_SECRET.
export RELAY_SHARED_SECRET
envsubst '$RELAY_SHARED_SECRET' < /app/docker/unraid/supervisord.conf > /run/supervisord.conf
unset RELAY_SHARED_SECRET
chmod 0600 /run/supervisord.conf

# Hand known files and directories to the runtime UID; change /config last so
# root can finish initialization without CAP_DAC_OVERRIDE.
chown appuser:appgroup "$SECRETS" /config/redis /config/state \
  /tmp/nginx-client-body /tmp/nginx-proxy /tmp/nginx-fastcgi \
  /tmp/nginx-uwsgi /tmp/nginx-scgi /config

if [ "${WM_TEST_MODE:-0}" = 1 ]; then
  echo "World Monitor AIO configuration generated"
  exit 0
fi

exec /usr/bin/supervisord -c /run/supervisord.conf

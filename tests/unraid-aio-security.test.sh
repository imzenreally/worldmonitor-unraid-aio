#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-unraid-aio:dev}"
expected_revision="${2:-}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

exposed=$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")
[[ "$exposed" == '{"8080/tcp":{}}' ]] || fail "unexpected exposed ports: $exposed"

for label in \
  org.opencontainers.image.source \
  org.opencontainers.image.licenses \
  org.opencontainers.image.revision \
  org.opencontainers.image.version; do
  value=$(docker image inspect --format "{{index .Config.Labels \"$label\"}}" "$image")
  [[ -n "$value" && "$value" != '<no value>' ]] || fail "missing OCI label $label"
done

source_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$image")
license_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.licenses"}}' "$image")
[[ "$source_label" == 'https://github.com/imzenreally/worldmonitor-unraid-aio' ]] || fail "unexpected source label: $source_label"
[[ "$license_label" == 'AGPL-3.0-only' ]] || fail "unexpected license label: $license_label"
if [[ -n "$expected_revision" ]]; then
  revision_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")
  [[ "$revision_label" == "$expected_revision" ]] || fail "revision label $revision_label does not match $expected_revision"
  expected_source="https://github.com/imzenreally/worldmonitor-unraid-aio/tree/$expected_revision"
  docker run --rm --entrypoint sh "$image" -c 'grep -R -F -m1 -- "$1" /usr/share/nginx/html >/dev/null' sh "$expected_source" ||
    fail 'built UI does not link to the exact corresponding source revision'
fi

if docker run --rm --entrypoint sh "$image" -c 'command -v npm >/dev/null 2>&1 || command -v npx >/dev/null 2>&1'; then
  fail 'npm or npx is present in the final runtime image'
fi
docker run --rm --entrypoint node "$image" --version >/dev/null
valkey_version=$(docker run --rm --entrypoint valkey-server "$image" --version)
grep -q 'v=9.0.4' <<<"$valkey_version"
if docker run --rm --entrypoint sh "$image" -c 'command -v redis-server >/dev/null 2>&1'; then
  fail 'Redis is present; the release must use pinned BSD-licensed Valkey'
fi

image_env=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image")
if grep -Eq '(API_KEY|PASSWORD|TOKEN)=.+' <<<"$image_env"; then
  fail 'image config contains a baked credential-like environment value'
fi

# Root initialization must refuse a hostile symlink in the persistent mount.
symlink_volume="wm-security-symlink-$RANDOM-$$"
memory_volume="wm-security-memory-$RANDOM-$$"
cleanup() {
  docker volume rm "$symlink_volume" "$memory_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker volume create "$symlink_volume" >/dev/null
docker volume create "$memory_volume" >/dev/null
docker run --rm --entrypoint sh -v "$symlink_volume:/config" "$image" -c 'ln -s /etc/passwd /config/secrets.env'
if docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=32m \
  --tmpfs /run:rw,nosuid,nodev,size=8m \
  --cap-drop=ALL --cap-add=CHOWN --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID \
  --security-opt no-new-privileges:true \
  -e WM_TEST_MODE=1 \
  -v "$symlink_volume:/config" \
  "$image" >/dev/null 2>&1; then
  fail 'entrypoint accepted a symlinked secrets file'
fi

for invalid_memory in $'256mb\nbind 0.0.0.0' 0 17gb; do
  if docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,size=32m \
    --tmpfs /run:rw,nosuid,nodev,size=8m \
    --cap-drop=ALL --cap-add=CHOWN --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID \
    --security-opt no-new-privileges:true \
    -e WM_TEST_MODE=1 \
    -e "REDIS_MAXMEMORY=$invalid_memory" \
    -v "$memory_volume:/config" \
    "$image" >/dev/null 2>&1; then
    fail "entrypoint accepted unsafe REDIS_MAXMEMORY: $invalid_memory"
  fi
done

for invalid_scheduler_setting in \
  'SEED_ON_START=maybe' \
  'SEED_ON_START_DELAY_SECONDS=999999999999999999999999' \
  'SEED_INTERVAL_MINUTES=not-a-number' \
  'SEED_INTERVAL_MINUTES=010' \
  'SEED_INTERVAL_MINUTES=10081' \
  'SEED_INTERVAL_MINUTES=999999999999999999999999'; do
  if docker run --rm --entrypoint env "$image" \
    "$invalid_scheduler_setting" \
    /app/docker/unraid/seed-scheduler.sh >/dev/null 2>&1; then
    fail "seed scheduler accepted unsafe setting: $invalid_scheduler_setting"
  fi
done

printf 'PASS: runtime image security contract\n'

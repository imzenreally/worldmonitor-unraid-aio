#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-unraid-aio:dev}"
wait_seconds="${SEED_TEST_WAIT_SECONDS:-600}"
suffix="$RANDOM-$$"
name="wm-seed-$suffix"
volume="$name-config"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$volume" >/dev/null
docker run -d --name "$name" --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --tmpfs /run:rw,nosuid,nodev,size=32m \
  --security-opt no-new-privileges:true \
  --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  --pids-limit 512 \
  -e SEED_ON_START=true -e SEED_ON_START_DELAY_SECONDS=2 -e SEED_INTERVAL_MINUTES=0 \
  -v "$volume":/config "$image" >/dev/null

deadline=$((SECONDS + wait_seconds))
while (( SECONDS < deadline )); do
  health=$(docker inspect --format '{{.State.Health.Status}}' "$name")
  dbsize=0
  if [[ "$health" == healthy ]] && docker logs "$name" 2>&1 | grep -qF '[seed-scheduler] starting seed pass'; then
    dbsize=$(docker exec --user appuser:appgroup "$name" sh -c 'REDISCLI_AUTH="$(awk -F= '\''$1 == "REDIS_PASSWORD" { print substr($0, index($0, "=") + 1); exit }'\'' /config/secrets.env)" valkey-cli dbsize' 2>/dev/null || printf '0')
  fi
  if [[ "$dbsize" =~ ^[0-9]+$ ]] && (( dbsize > 0 )); then
    if docker logs "$name" 2>&1 | grep -Eq 'ERR_MODULE_NOT_FOUND|Cannot find package|Cannot find module'; then
      docker logs --tail 200 "$name" >&2
      printf 'FAIL: runtime module-loading error during seeding\n' >&2
      exit 1
    fi
    secret_checksum=$(docker exec --user appuser:appgroup "$name" sha256sum /config/secrets.env | awk '{print $1}')

    docker rm -f "$name" >/dev/null
    docker run -d --name "$name" --read-only \
      --tmpfs /tmp:rw,nosuid,nodev,size=256m \
      --tmpfs /run:rw,nosuid,nodev,size=32m \
      --security-opt no-new-privileges:true \
      --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
      --pids-limit 512 \
      -e SEED_ON_START=false -e SEED_INTERVAL_MINUTES=0 \
      -v "$volume":/config "$image" >/dev/null

    restart_deadline=$((SECONDS + 120))
    while (( SECONDS < restart_deadline )); do
      health=$(docker inspect --format '{{.State.Health.Status}}' "$name")
      [[ "$health" == healthy ]] && break
      [[ "$health" == unhealthy ]] && { docker logs --tail 200 "$name" >&2; exit 1; }
      sleep 2
    done
    [[ "$health" == healthy ]] || { docker logs --tail 200 "$name" >&2; printf 'FAIL: restart did not become healthy\n' >&2; exit 1; }
    restarted_checksum=$(docker exec --user appuser:appgroup "$name" sha256sum /config/secrets.env | awk '{print $1}')
    [[ "$restarted_checksum" == "$secret_checksum" ]] || { printf 'FAIL: internal secrets rotated across restart\n' >&2; exit 1; }
    restarted_dbsize=$(docker exec --user appuser:appgroup "$name" sh -c 'REDISCLI_AUTH="$(awk -F= '\''$1 == "REDIS_PASSWORD" { print substr($0, index($0, "=") + 1); exit }'\'' /config/secrets.env)" valkey-cli dbsize')
    [[ "$restarted_dbsize" =~ ^[0-9]+$ ]] && (( restarted_dbsize > 0 )) || { printf 'FAIL: Valkey data did not persist across restart\n' >&2; exit 1; }
    printf 'PASS: initial seed and restart persistence; valkey_dbsize=%s\n' "$restarted_dbsize"
    exit 0
  fi
  if docker exec --user appuser:appgroup "$name" test -f /config/state/last-seed-failure; then
    docker logs --tail 200 "$name" >&2
    printf 'FAIL: initial seed pass reported failures\n' >&2
    exit 1
  fi
  sleep 5
done

docker logs --tail 200 "$name" >&2
printf 'FAIL: seeders did not populate Valkey within %s seconds\n' "$wait_seconds" >&2
exit 1

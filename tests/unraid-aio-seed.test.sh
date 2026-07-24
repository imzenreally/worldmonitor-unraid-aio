#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-aio:dev}"
wait_seconds="${SEED_TEST_WAIT_SECONDS:-1800}"
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
  --security-opt no-new-privileges:true --pids-limit 512 \
  -e SEED_ON_START=true -e SEED_ON_START_DELAY_SECONDS=2 -e SEED_INTERVAL_MINUTES=0 \
  -v "$volume":/config "$image" >/dev/null

deadline=$((SECONDS + wait_seconds))
while (( SECONDS < deadline )); do
  if docker exec "$name" sh -c 'test -f /config/state/last-seed-success'; then
    if docker logs "$name" 2>&1 | grep -Eq 'ERR_MODULE_NOT_FOUND|Cannot find package|Cannot find module'; then
      docker logs --tail 200 "$name" >&2
      printf 'FAIL: seeder encountered a missing runtime dependency\n' >&2
      exit 1
    fi
    status=$(docker inspect --format '{{.State.Health.Status}}' "$name")
    [[ "$status" == healthy ]] || { docker logs --tail 200 "$name" >&2; exit 1; }
    printf 'PASS: initial seed pass completed without missing runtime dependencies\n'
    exit 0
  fi
  if docker exec "$name" sh -c 'test -f /config/state/last-seed-failure'; then
    docker logs --tail 200 "$name" >&2
    printf 'FAIL: initial seed pass reported failure\n' >&2
    exit 1
  fi
  sleep 5
done

docker logs --tail 200 "$name" >&2
printf 'FAIL: initial seed pass did not finish within %s seconds\n' "$wait_seconds" >&2
exit 1

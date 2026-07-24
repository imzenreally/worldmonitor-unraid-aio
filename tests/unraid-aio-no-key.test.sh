#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-aio:dev}"
name="wm-no-key-test-$RANDOM-$$"
volume="${name}-config"
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
  -e SEED_ON_START=false -e SEED_INTERVAL_MINUTES=0 \
  -v "$volume":/config "$image" >/dev/null
for _ in $(seq 1 30); do
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name")
  if [[ "$status" == healthy ]]; then
    printf 'PASS: healthy without optional AIS key\n'
    exit 0
  fi
  sleep 2
done
docker logs --tail 100 "$name" >&2
exit 1

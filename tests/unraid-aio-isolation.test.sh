#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-aio:dev}"
suffix="$RANDOM-$$"
name="wm-isolation-$suffix"
volume="$name-config"
network="$name-net"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker volume create "$volume" >/dev/null
docker run -d --name "$name" --network "$network" --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --tmpfs /run:rw,nosuid,nodev,size=32m \
  --security-opt no-new-privileges:true --pids-limit 512 \
  -e SEED_ON_START=false -e SEED_INTERVAL_MINUTES=0 \
  -v "$volume":/config "$image" >/dev/null

for _ in $(seq 1 45); do
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name")
  [[ "$status" == healthy ]] && break
  sleep 2
done
[[ "${status:-}" == healthy ]] || { docker logs --tail 100 "$name" >&2; exit 1; }

docker run --rm --network "$network" curlimages/curl:8.12.1 \
  -fsS --max-time 5 "http://$name:8080/api/sidecar-health" >/dev/null

for port in 6379 8079 3004 46123; do
  if docker run --rm --network "$network" curlimages/curl:8.12.1 \
    -fsS --max-time 2 "http://$name:$port/" >/dev/null 2>&1; then
    printf 'FAIL: internal port %s is reachable from a peer container\n' "$port" >&2
    exit 1
  fi
done

printf 'PASS: only the web service is reachable from the Docker network\n'

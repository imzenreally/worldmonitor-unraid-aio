#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-unraid-aio:dev}"
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
  --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  -e SEED_ON_START=false -e SEED_INTERVAL_MINUTES=0 \
  -v "$volume":/config "$image" >/dev/null
for _ in $(seq 1 30); do
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name")
  if [[ "$status" == healthy ]]; then
    docker exec --user appuser:appgroup "$name" sh -c '
      set -eu
      seen=0
      field() {
        wanted="$1:"
        file="$2"
        while read -r key value rest; do
          [ "$key" = "$wanted" ] && { printf "%s\n" "$value"; return; }
        done < "$file"
      }
      for status in /proc/[0-9]*/status; do
        ppid=$(field PPid "$status")
        [ "$ppid" = 1 ] || continue
        uid=$(field Uid "$status")
        cap=$(field CapEff "$status")
        [ "$uid" = 101 ]
        [ "$cap" = 0000000000000000 ]
        seen=$((seen + 1))
      done
      [ "$seen" -ge 6 ]
    '
    logs=$(docker logs "$name" 2>&1)
    grep -q 'disabled: optional AISSTREAM_API_KEY is not configured' <<<"$logs"
    bootstrap_status=$(docker exec "$name" \
      curl -sS -o /tmp/bootstrap-test.json -w '%{http_code}' \
      'http://127.0.0.1:8080/api/bootstrap?keys=weatherAlerts')
    [[ "$bootstrap_status" == 200 ]] || {
      docker exec "$name" sh -c 'sed -n "1,20p" /tmp/bootstrap-test.json' >&2
      fail_msg="bootstrap handler returned HTTP $bootstrap_status"
      printf 'FAIL: %s\n' "$fail_msg" >&2
      exit 1
    }
    printf 'PASS: healthy without optional AIS key; bundled bootstrap handler loads; all supervised services are capability-free appuser\n'
    exit 0
  fi
  sleep 2
done
docker logs --tail 100 "$name" >&2
exit 1

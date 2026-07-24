#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-unraid-aio:dev}"
volume="wm-readonly-test-$RANDOM-$$"
cleanup() { docker volume rm "$volume" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker volume create "$volume" >/dev/null
docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=64m \
  --tmpfs /run:rw,nosuid,nodev,size=16m \
  --security-opt no-new-privileges:true \
  --cap-drop ALL --cap-add CHOWN --cap-add FOWNER --cap-add SETUID --cap-add SETGID \
  -e WM_TEST_MODE=1 \
  -v "$volume":/config \
  "$image" | grep -q 'configuration generated'
printf 'PASS: read-only startup configuration\n'

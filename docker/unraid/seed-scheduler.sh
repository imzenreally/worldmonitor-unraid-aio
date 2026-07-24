#!/bin/sh
set -u

LOCK=/config/state/seeder.lock

wait_for_redis_rest() {
  i=0
  while [ "$i" -lt 120 ]; do
    if curl --config - >/dev/null 2>&1 <<EOF
silent
show-error
fail
max-time = 2
header = "Authorization: Bearer $REDIS_TOKEN"
header = "Content-Type: application/json"
data = "[\"PING\"]"
url = "http://127.0.0.1:8079/"
EOF
    then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

run_seeders() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    echo '[seed-scheduler] another seed pass is active; skipping'
    return 0
  fi
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT HUP INT TERM
  echo '[seed-scheduler] starting seed pass'
  if /app/scripts/run-seeders.sh; then
    date -u +%FT%TZ > /config/state/last-seed-success
    rm -f /config/state/last-seed-failure
    echo '[seed-scheduler] seed pass finished'
  else
    rc=$?
    date -u +%FT%TZ > /config/state/last-seed-failure
    echo "[seed-scheduler] seed pass completed with failures (exit $rc)"
  fi
  rmdir "$LOCK" 2>/dev/null || true
  trap - EXIT HUP INT TERM
}

# A lock can only survive an unclean process/container exit; no concurrent
# scheduler exists before supervisor starts this process.
if [ -L "$LOCK" ] || { [ -e "$LOCK" ] && [ ! -d "$LOCK" ]; }; then
  echo '[seed-scheduler] unsafe lock path in persistent state' >&2
  exit 1
fi
rmdir "$LOCK" 2>/dev/null || true

if ! wait_for_redis_rest; then
  echo '[seed-scheduler] Redis-compatible REST service did not become ready' >&2
  exit 1
fi

seed_on_start="${SEED_ON_START:-true}"
case "$seed_on_start" in
  true|false) ;;
  *) echo '[seed-scheduler] SEED_ON_START must be true or false' >&2; exit 1 ;;
esac

delay="${SEED_ON_START_DELAY_SECONDS:-10}"
case "$delay" in
  ''|*[!0-9]*) echo '[seed-scheduler] invalid SEED_ON_START_DELAY_SECONDS' >&2; exit 1 ;;
esac
if [ "$delay" -gt 3600 ]; then
  echo '[seed-scheduler] SEED_ON_START_DELAY_SECONDS must not exceed 3600' >&2
  exit 1
fi

if [ "$seed_on_start" = true ]; then
  sleep "$delay"
  run_seeders
fi

interval="${SEED_INTERVAL_MINUTES:-30}"
case "$interval" in
  ''|*[!0-9]*) echo '[seed-scheduler] invalid SEED_INTERVAL_MINUTES' >&2; exit 1 ;;
esac
if [ "$interval" -eq 0 ]; then
  echo '[seed-scheduler] recurring seeding disabled'
  exec sleep infinity
fi

while :; do
  sleep $((interval * 60))
  run_seeders
done

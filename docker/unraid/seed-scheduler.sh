#!/bin/sh
set -u

wait_for_redis_rest() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS --max-time 3 -H "Authorization: Bearer ${REDIS_TOKEN}" \
      -H 'Content-Type: application/json' -d '["PING"]' http://127.0.0.1:8079/ >/dev/null; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

run_seeders() {
  lock=/config/state/seeder.lock
  if ! mkdir "$lock" 2>/dev/null; then
    echo '[seed-scheduler] previous run still active; skipping'
    return 0
  fi
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT INT TERM
  echo '[seed-scheduler] starting seed pass'
  if /app/scripts/run-seeders.sh; then
    date -u +%FT%TZ > /config/state/last-seed-success
    echo '[seed-scheduler] seed pass finished'
  else
    rc=$?
    date -u +%FT%TZ > /config/state/last-seed-failure
    echo "[seed-scheduler] seed pass completed with failures (exit $rc)"
  fi
  rmdir "$lock" 2>/dev/null || true
  trap - EXIT INT TERM
}

if ! wait_for_redis_rest; then
  echo '[seed-scheduler] Redis REST did not become ready' >&2
  exit 1
fi

if [ "${SEED_ON_START:-true}" = true ]; then
  sleep "${SEED_ON_START_DELAY_SECONDS:-10}"
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

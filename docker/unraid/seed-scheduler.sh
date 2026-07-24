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

validate_uint() {
  name="$1"
  value="$2"
  max_digits="$3"
  max_value="$4"
  case "$value" in
    ''|*[!0-9]*) echo "[seed-scheduler] invalid $name" >&2; exit 1 ;;
  esac
  case "$value" in
    0|[1-9]*) ;;
    *) echo "[seed-scheduler] $name must not contain leading zeroes" >&2; exit 1 ;;
  esac
  if [ "${#value}" -gt "$max_digits" ] || [ "$value" -gt "$max_value" ]; then
    echo "[seed-scheduler] $name must not exceed $max_value" >&2
    exit 1
  fi
}

seed_on_start="${SEED_ON_START:-true}"
case "$seed_on_start" in
  true|false) ;;
  *) echo '[seed-scheduler] SEED_ON_START must be true or false' >&2; exit 1 ;;
esac

delay="${SEED_ON_START_DELAY_SECONDS:-10}"
validate_uint SEED_ON_START_DELAY_SECONDS "$delay" 4 3600

interval="${SEED_INTERVAL_MINUTES:-30}"
validate_uint SEED_INTERVAL_MINUTES "$interval" 5 10080

# Validate every user-controlled scheduler value before touching persistent state,
# waiting for services, or starting a seed pass.
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

if [ "$seed_on_start" = true ]; then
  sleep "$delay"
  run_seeders
fi

if [ "$interval" -eq 0 ]; then
  echo '[seed-scheduler] recurring seeding disabled'
  exec sleep infinity
fi

while :; do
  sleep $((interval * 60))
  run_seeders
done

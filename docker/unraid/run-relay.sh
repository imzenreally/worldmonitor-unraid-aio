#!/bin/sh
set -eu
if [ -z "${AISSTREAM_API_KEY:-${VITE_AISSTREAM_API_KEY:-}}" ]; then
  echo '[ais-relay] disabled: optional AISSTREAM_API_KEY is not configured'
  exec sleep infinity
fi
exec node /app/scripts/ais-relay.cjs

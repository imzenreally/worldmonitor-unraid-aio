#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE_TAG="worldmonitor-upstream:${WORLDMONITOR_REVISION:-local}"
AIO_TAG="${AIO_TAG:-worldmonitor-aio:dev}"
docker build --pull -t "$BASE_TAG" -f Dockerfile .
docker build --pull --build-arg BASE_IMAGE="$BASE_TAG" -t "$AIO_TAG" -f Dockerfile.unraid .
printf 'Built %s from %s\n' "$AIO_TAG" "$BASE_TAG"

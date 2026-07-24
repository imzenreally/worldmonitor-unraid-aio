#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

revision="${WORLDMONITOR_REVISION:-$(git rev-parse --short=12 HEAD)}"
version="${BUILD_VERSION:-dev}"
base_tag="worldmonitor-upstream:${revision}"
aio_tag="${AIO_TAG:-worldmonitor-aio:${version}}"

docker build --pull -t "$base_tag" -f Dockerfile .
docker build --pull \
  --build-arg BASE_IMAGE="$base_tag" \
  --build-arg BUILD_VERSION="$version" \
  --build-arg VCS_REF="$revision" \
  -t "$aio_tag" -f Dockerfile.unraid .

printf 'Built %s from %s at revision %s\n' "$aio_tag" "$base_tag" "$revision"

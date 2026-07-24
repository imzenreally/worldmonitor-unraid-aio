#!/bin/sh
set -eu

image="${1:-}"
shift || true

case "$image" in
  ghcr.io/*/*) repository="${image#ghcr.io/}" ;;
  *) echo 'usage: check-ghcr-tags-absent.sh ghcr.io/owner/image tag [tag ...]' >&2; exit 2 ;;
esac

if [ "$#" -eq 0 ]; then
  echo 'at least one tag is required' >&2
  exit 2
fi

: "${GITHUB_ACTOR:?GITHUB_ACTOR is required}"
: "${GHCR_TOKEN:?GHCR_TOKEN is required}"

registry_token="$({
  curl --silent --show-error --fail-with-body \
    --user "$GITHUB_ACTOR:$GHCR_TOKEN" \
    --get 'https://ghcr.io/token' \
    --data-urlencode 'service=ghcr.io' \
    --data-urlencode "scope=repository:${repository}:pull"
} | jq -er '.token // .access_token')" || {
  echo 'could not obtain a GHCR manifest-read token; refusing to publish' >&2
  exit 1
}

for tag in "$@"; do
  case "$tag" in
    ''|*[!A-Za-z0-9_.-]*) echo "invalid container tag: $tag" >&2; exit 2 ;;
  esac

  status="$(curl --silent --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --request HEAD \
    --header "Authorization: Bearer $registry_token" \
    --header 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${repository}/manifests/${tag}")" || {
      echo "GHCR manifest lookup failed for $image:$tag; refusing to publish" >&2
      exit 1
    }

  case "$status" in
    404) ;;
    200) echo "refusing to overwrite immutable tag: $image:$tag" >&2; exit 1 ;;
    *) echo "GHCR manifest lookup returned HTTP $status for $image:$tag; refusing to publish" >&2; exit 1 ;;
  esac
done

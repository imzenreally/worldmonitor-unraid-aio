#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/jq" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '%s\n' test-registry-token
EOF

cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
case " $* " in
  *' https://ghcr.io/token '*)
    [ "${MOCK_TOKEN_FAILURE:-false}" = true ] && exit 7
    printf '%s\n' '{"token":"test-registry-token"}'
    ;;
  *'/manifests/'*)
    case " $* " in *' --request HEAD '*) exit 65 ;; esac
    [ "${MOCK_LOOKUP_FAILURE:-false}" = true ] && exit 28
    printf '%s' "${MOCK_MANIFEST_STATUS:-500}"
    ;;
  *) exit 64 ;;
esac
EOF
chmod 0755 "$tmp/bin/curl" "$tmp/bin/jq"

run_guard() {
  env PATH="$tmp/bin:$PATH" GITHUB_ACTOR=test GHCR_TOKEN=test \
    "$root/scripts/check-ghcr-tags-absent.sh" \
    ghcr.io/imzenreally/worldmonitor-unraid-aio test-tag
}

MOCK_MANIFEST_STATUS=404 run_guard >/dev/null 2>&1 || fail 'explicit 404 was not accepted as tag absent'

for status in 200 401 403 429 500; do
  if MOCK_MANIFEST_STATUS="$status" run_guard >/dev/null 2>&1; then
    fail "HTTP $status failed open"
  fi
done

if MOCK_LOOKUP_FAILURE=true run_guard >/dev/null 2>&1; then
  fail 'manifest transport failure failed open'
fi

if MOCK_TOKEN_FAILURE=true run_guard >/dev/null 2>&1; then
  fail 'token transport failure failed open'
fi

printf 'PASS: GHCR immutable-tag guard fails closed\n'

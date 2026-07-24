#!/usr/bin/env bash
set -euo pipefail
image="${1:-worldmonitor-aio:dev}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

exposed=$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")
[[ "$exposed" == '{"8080/tcp":{}}' ]] || fail "unexpected exposed ports: $exposed"

for label in \
  org.opencontainers.image.source \
  org.opencontainers.image.licenses \
  org.opencontainers.image.revision \
  org.opencontainers.image.version; do
  value=$(docker image inspect --format "{{index .Config.Labels \"$label\"}}" "$image")
  [[ -n "$value" && "$value" != '<no value>' ]] || fail "missing OCI label $label"
done

if docker run --rm --entrypoint sh "$image" -c 'command -v npm >/dev/null 2>&1 || command -v npx >/dev/null 2>&1'; then
  fail 'npm or npx is present in the final runtime image'
fi
docker run --rm --entrypoint node "$image" --version >/dev/null

if docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image" | grep -Eq '(API_KEY|PASSWORD|TOKEN)=.+'; then
  fail 'image config contains a baked credential-like environment value'
fi

printf 'PASS: runtime image security contract\n'

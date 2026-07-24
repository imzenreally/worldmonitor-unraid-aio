#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
require_absent() { ! grep -Fq -- "$2" "$1" || fail "$1 unexpectedly contains: $2"; }

for file in \
  Dockerfile.unraid \
  NOTICE \
  docker/unraid/build-aio.sh \
  docker/unraid/entrypoint.sh \
  docker/unraid/healthcheck.sh \
  docker/unraid/patch-loopback.mjs \
  docker/unraid/patch-source-link.mjs \
  docker/unraid/redis-rest-package.json \
  docker/unraid/redis-rest-package-lock.json \
  docker/unraid/run-relay.sh \
  docker/unraid/seed-scheduler.sh \
  docker/unraid/supervisord.conf \
  docs/THIRD_PARTY_NOTICES.md \
  docs/UNRAID.md \
  templates/worldmonitor-aio.xml; do
  require_file "$file"
done

require_text Dockerfile.unraid '# syntax=docker/dockerfile:1.7@sha256:'
require_text Dockerfile.unraid 'ARG BASE_IMAGE'
require_text Dockerfile.unraid 'org.opencontainers.image.source'
require_text Dockerfile.unraid 'org.opencontainers.image.licenses="AGPL-3.0-only"'
require_text Dockerfile.unraid 'HEALTHCHECK'
require_text Dockerfile.unraid 'EXPOSE 8080'
require_text Dockerfile.unraid 'rm -rf /usr/local/lib/node_modules/npm'
require_text Dockerfile.unraid 'valkey=9.0.4-r0'
require_text Dockerfile.unraid 'valkey-cli=9.0.4-r0'
require_text Dockerfile.unraid 'su-exec=0.3-r0'
require_text Dockerfile.unraid 'node:24-alpine@sha256:'
require_text Dockerfile.unraid 'HEALTHCHECK'
require_text Dockerfile.unraid 'appuser:appgroup'
require_text Dockerfile.unraid 'redis-rest-package-lock.json'
require_text Dockerfile.unraid 'patch-loopback.mjs'
require_text Dockerfile.unraid 'patch-source-link.mjs'
require_text Dockerfile.unraid 'worldmonitor-unraid-aio/tree/${VCS_REF}'
require_absent Dockerfile.unraid 'apk add --no-cache redis'
require_absent Dockerfile.unraid 'npm install --ignore-scripts --omit=optional redis@4'
require_text docker/unraid/supervisord.conf '[program:valkey]'
require_text docker/unraid/supervisord.conf '[program:redis-rest]'
require_text docker/unraid/supervisord.conf '[program:ais-relay]'
require_text docker/unraid/supervisord.conf '[program:worldmonitor-api]'
require_text docker/unraid/supervisord.conf '[program:nginx]'
require_text docker/unraid/supervisord.conf '[program:seed-scheduler]'
require_text docker/unraid/entrypoint.sh '/config/secrets.env'
require_text docker/unraid/entrypoint.sh 'chmod 0600'
require_text docker/unraid/entrypoint.sh 'must not be a symbolic link'
require_absent docker/unraid/entrypoint.sh 'chown -R'
require_text docker/unraid/healthcheck.sh '/api/sidecar-health'
require_text docker/unraid/healthcheck.sh 'valkey-cli'
require_text docker/unraid/healthcheck.sh '3004/health'
require_text docker/unraid/healthcheck.sh 'data = "[\"PING\"]"'
require_text docker/unraid/seed-scheduler.sh 'data = "[\"PING\"]"'
require_text .github/workflows/unraid-aio.yml "github.event_name == 'push'"
require_text .github/workflows/unraid-aio.yml '^v[0-9]+\.[0-9]+\.[0-9]+-unraid\.[0-9]+$'
require_text .github/workflows/unraid-aio.yml './scripts/check-ghcr-tags-absent.sh'
require_text scripts/check-ghcr-tags-absent.sh '404) ;;'
require_text scripts/check-ghcr-tags-absent.sh 'refusing to publish'
require_absent .github/workflows/unraid-aio.yml 'docker buildx build --load --pull \'
require_text tests/unraid-aio-no-key.test.sh 'logs=$(docker logs "$name" 2>&1)'
require_absent tests/unraid-aio-no-key.test.sh 'docker logs "$name" 2>&1 | grep -q'
require_text docs/UNRAID.md 'does not provide built-in user authentication'
require_text docker/unraid/supervisord.conf 'user=root'

program_count=$(grep -c '^\[program:' docker/unraid/supervisord.conf)
appuser_count=$(grep -c '^user=appuser$' docker/unraid/supervisord.conf)
[[ "$program_count" -eq "$appuser_count" ]] || fail 'every supervised application process must run as appuser'

python3 - <<'PY'
from pathlib import Path
import re
import xml.etree.ElementTree as ET

for workflow in Path('.github/workflows').glob('*.yml'):
    for line_number, line in enumerate(workflow.read_text().splitlines(), 1):
        match = re.search(r'\buses:\s+([^\s#]+)', line)
        if not match or match.group(1).startswith('./'):
            continue
        reference = match.group(1)
        assert '@' in reference, f'{workflow}:{line_number} action is unpinned: {reference}'
        revision = reference.rsplit('@', 1)[1]
        assert re.fullmatch(r'[0-9a-f]{40}', revision), f'{workflow}:{line_number} action is not pinned to a 40-character commit: {reference}'

path = Path('templates/worldmonitor-aio.xml')
text = path.read_text()
assert 'REPLACE_ME' not in text
root = ET.fromstring(text)
assert root.tag == 'Container'
assert root.attrib.get('version') == '2'
assert root.findtext('Name') == 'World Monitor AIO (Unofficial)'
assert root.findtext('Repository') == 'ghcr.io/imzenreally/worldmonitor-unraid-aio:beta'
assert root.findtext('Registry') == 'https://github.com/users/imzenreally/packages/container/package/worldmonitor-unraid-aio'
assert root.findtext('WebUI') == 'http://[IP]:[PORT:8080]/'
assert root.findtext('Privileged') == 'false'
assert root.findtext('Network') == 'bridge'
assert root.findtext('License') == 'AGPL-3.0-only'
assert root.findtext('Beta') == 'true'
assert root.findtext('TemplateURL').endswith('/templates/worldmonitor-aio.xml')
extra = root.findtext('ExtraParams') or ''
for required in (
    '--read-only', 'no-new-privileges', '--cap-drop=ALL',
    '--cap-add=CHOWN', '--cap-add=FOWNER', '--cap-add=SETUID',
    '--cap-add=SETGID', '--pids-limit=512',
):
    assert required in extra
configs = {item.attrib['Target']: item.attrib for item in root.findall('Config')}
required_configs = {
    '8080', '/config', 'SEED_ON_START', 'SEED_INTERVAL_MINUTES', 'SEED_TIMEOUT',
    'REDIS_MAXMEMORY', 'AISSTREAM_API_KEY', 'NASA_FIRMS_API_KEY',
    'FINNHUB_API_KEY', 'FRED_API_KEY', 'EIA_API_KEY', 'AVIATIONSTACK_API',
    'TRAVELPAYOUTS_API_TOKEN', 'CLOUDFLARE_API_TOKEN', 'ACLED_ACCESS_TOKEN',
    'ACLED_EMAIL', 'ACLED_PASSWORD', 'GROQ_API_KEY', 'OPENROUTER_API_KEY',
    'LLM_API_URL', 'LLM_API_KEY', 'LLM_MODEL',
}
missing = sorted(required_configs - configs.keys())
assert not missing, f'missing Config targets: {missing}'
for key in (
    'AISSTREAM_API_KEY', 'NASA_FIRMS_API_KEY', 'FINNHUB_API_KEY', 'FRED_API_KEY',
    'EIA_API_KEY', 'AVIATIONSTACK_API', 'TRAVELPAYOUTS_API_TOKEN',
    'CLOUDFLARE_API_TOKEN', 'ACLED_ACCESS_TOKEN', 'ACLED_PASSWORD',
    'GROQ_API_KEY', 'OPENROUTER_API_KEY', 'LLM_API_KEY',
):
    assert configs[key].get('Mask') == 'true', f'{key} must be masked'
PY

printf 'PASS: static AIO package contract\n'

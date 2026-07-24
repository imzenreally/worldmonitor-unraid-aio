#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }

for file in \
  Dockerfile.unraid \
  docker/unraid/build-aio.sh \
  docker/unraid/entrypoint.sh \
  docker/unraid/healthcheck.sh \
  docker/unraid/run-relay.sh \
  docker/unraid/seed-scheduler.sh \
  docker/unraid/supervisord.conf \
  docs/UNRAID.md \
  templates/worldmonitor-aio.xml; do
  require_file "$file"
done

require_text Dockerfile.unraid 'ARG BASE_IMAGE'
require_text Dockerfile.unraid 'org.opencontainers.image.source'
require_text Dockerfile.unraid 'org.opencontainers.image.licenses="AGPL-3.0-or-later"'
require_text Dockerfile.unraid 'HEALTHCHECK'
require_text Dockerfile.unraid 'EXPOSE 8080'
require_text Dockerfile.unraid 'rm -rf /usr/local/lib/node_modules/npm'
require_text docker/unraid/supervisord.conf '[program:redis]'
require_text docker/unraid/supervisord.conf '[program:redis-rest]'
require_text docker/unraid/supervisord.conf '[program:ais-relay]'
require_text docker/unraid/supervisord.conf '[program:worldmonitor-api]'
require_text docker/unraid/supervisord.conf '[program:nginx]'
require_text docker/unraid/supervisord.conf '[program:seed-scheduler]'
require_text docker/unraid/entrypoint.sh '/config/secrets.env'
require_text docker/unraid/entrypoint.sh 'chmod 600'
require_text docker/unraid/healthcheck.sh '/api/sidecar-health'
require_text docker/unraid/healthcheck.sh 'redis-cli'
require_text docker/unraid/healthcheck.sh '3004/health'
require_text docs/UNRAID.md 'does not provide built-in user authentication'

python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

path = Path('templates/worldmonitor-aio.xml')
text = path.read_text()
assert 'REPLACE_ME' not in text
root = ET.fromstring(text)
assert root.tag == 'Container'
assert root.attrib.get('version') == '2'
assert root.findtext('Name') == 'World Monitor AIO'
assert root.findtext('Repository') == 'ghcr.io/imzenreally/worldmonitor-aio:latest'
assert root.findtext('Registry') == 'https://ghcr.io/imzenreally/worldmonitor-aio'
assert root.findtext('WebUI') == 'http://[IP]:[PORT:8080]/'
assert root.findtext('Privileged') == 'false'
assert root.findtext('Network') == 'bridge'
assert root.findtext('License') == 'AGPL-3.0-or-later'
assert root.findtext('Beta') == 'true'
assert root.findtext('TemplateURL').endswith('/templates/worldmonitor-aio.xml')
extra = root.findtext('ExtraParams') or ''
for required in ('--read-only', 'no-new-privileges', '--pids-limit=512'):
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

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }

require_file Dockerfile.unraid
require_file docker/unraid/entrypoint.sh
require_file docker/unraid/healthcheck.sh
require_file docker/unraid/seed-scheduler.sh
require_file docker/unraid/supervisord.conf
require_file templates/worldmonitor-aio.xml

require_text Dockerfile.unraid 'ARG BASE_IMAGE'
require_text Dockerfile.unraid 'HEALTHCHECK'
require_text Dockerfile.unraid 'EXPOSE 8080'
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
require_text templates/worldmonitor-aio.xml '<Privileged>false</Privileged>'
require_text templates/worldmonitor-aio.xml '<Network>bridge</Network>'
require_text templates/worldmonitor-aio.xml '/mnt/user/appdata/worldmonitor'

python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse('templates/worldmonitor-aio.xml').getroot()
assert root.tag == 'Container'
assert root.attrib.get('version') == '2'
assert root.findtext('Name') == 'World Monitor AIO'
assert root.findtext('WebUI') == 'http://[IP]:[PORT:8080]/'
PY

printf 'PASS: static AIO package contract\n'

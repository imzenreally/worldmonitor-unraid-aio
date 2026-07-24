'use strict';

const assert = require('node:assert').strict;
const { existsSync } = require('node:fs');
const { resolve } = require('node:path');

const helperPath = resolve(__dirname, '../scripts/shared/runtime-endpoints.cjs');
assert.equal(existsSync(helperPath), true, 'missing scripts/shared/runtime-endpoints.cjs');

const { resolveCiiRelayKey, resolveCiiRpcUrl } = require(helperPath);
assert.equal(
  resolveCiiRpcUrl({ LOCAL_API_MODE: 'docker' }),
  'http://127.0.0.1:8080/api/intelligence/v1/get-risk-scores',
  'Docker mode must warm CII through the private local API',
);
assert.equal(
  resolveCiiRpcUrl({}),
  'https://api.worldmonitor.app/api/intelligence/v1/get-risk-scores',
  'non-Docker deployments must retain the hosted endpoint',
);
assert.equal(
  resolveCiiRpcUrl({ LOCAL_API_MODE: 'docker', CII_RPC_URL: 'https://example.test/risk' }),
  'https://example.test/risk',
  'explicit CII endpoint overrides must win',
);

assert.equal(
  resolveCiiRpcUrl({ LOCAL_API_MODE: 'docker', CII_RPC_URL: '   ' }),
  'http://127.0.0.1:8080/api/intelligence/v1/get-risk-scores',
  'blank overrides must fall back to the private Docker endpoint',
);
assert.equal(
  resolveCiiRelayKey(
    { LOCAL_API_MODE: 'docker', WORLDMONITOR_LOCAL_RELAY_KEY: 'local-only-secret' },
    'http://127.0.0.1:8080/api/intelligence/v1/get-risk-scores',
  ),
  'local-only-secret',
  'Docker loopback CII requests must use the local-only relay key',
);
assert.equal(
  resolveCiiRelayKey(
    {
      LOCAL_API_MODE: 'docker',
      WORLDMONITOR_LOCAL_RELAY_KEY: 'must-not-leave',
      WORLDMONITOR_RELAY_KEY: 'hosted-key-that-must-also-stay-off-overrides',
      CII_RPC_URL: 'https://example.test/risk',
    },
    'https://example.test/risk',
  ),
  '',
  'Docker mode must fail closed and send no relay key to a non-loopback override',
);
for (const loopbackUrl of [
  'http://localhost:8080/api/intelligence/v1/get-risk-scores',
  'http://127.0.0.1:8080/api/intelligence/v1/get-risk-scores',
  'http://[::1]:8080/api/intelligence/v1/get-risk-scores',
]) {
  assert.equal(
    resolveCiiRelayKey(
      { LOCAL_API_MODE: 'docker', WORLDMONITOR_LOCAL_RELAY_KEY: 'local-only-secret' },
      loopbackUrl,
    ),
    'local-only-secret',
    `Docker loopback URL must use the local relay key: ${loopbackUrl}`,
  );
}
assert.equal(
  resolveCiiRelayKey(
    { WORLDMONITOR_RELAY_KEY: 'hosted-relay-secret' },
    'https://api.worldmonitor.app/api/intelligence/v1/get-risk-scores',
  ),
  'hosted-relay-secret',
  'non-Docker deployments retain the hosted relay credential',
);

console.log('PASS: Unraid runtime endpoint resolution');

'use strict';

const assert = require('node:assert').strict;
const { existsSync } = require('node:fs');
const { resolve } = require('node:path');

const helperPath = resolve(__dirname, '../scripts/shared/runtime-endpoints.cjs');
assert.equal(existsSync(helperPath), true, 'missing scripts/shared/runtime-endpoints.cjs');

const { buildCiiFetchOptions, buildCiiWarmPingUrl, resolveCiiRelayKey, resolveCiiRpcUrl } = require(helperPath);
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

assert.equal(
  buildCiiWarmPingUrl('https://example.test/risk?existing=yes#result', 12345),
  'https://example.test/risk?existing=yes&_wm_warm_ping=12345#result',
  'warm-ping cache busting must preserve configured query strings and fragments',
);
assert.equal(
  buildCiiFetchOptions({ 'X-WorldMonitor-Key': 'local-only-secret' }).redirect,
  'error',
  'credentialed CII warm-pings must never follow redirects',
);

async function verifyRedirectIsBlocked() {
  const http = require('node:http');
  let redirectedRequests = 0;
  const target = http.createServer((_req, res) => {
    redirectedRequests += 1;
    res.end('unexpected');
  });
  const source = http.createServer((_req, res) => {
    const targetAddress = target.address();
    res.writeHead(302, { Location: `http://127.0.0.1:${targetAddress.port}/capture` });
    res.end();
  });
  const listen = (server) => new Promise((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const close = (server) => new Promise((resolveClose) => server.close(resolveClose));
  await listen(target);
  await listen(source);
  try {
    const sourceAddress = source.address();
    await assert.rejects(
      fetch(
        `http://127.0.0.1:${sourceAddress.port}/risk`,
        buildCiiFetchOptions({ 'X-WorldMonitor-Key': 'must-not-follow' }),
      ),
      'redirecting a credentialed CII request must fail instead of following',
    );
    assert.equal(redirectedRequests, 0, 'redirect target must never receive the local credentialed request');
  } finally {
    await Promise.all([close(source), close(target)]);
  }
}

verifyRedirectIsBlocked()
  .then(() => console.log('PASS: Unraid runtime endpoint resolution'))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });

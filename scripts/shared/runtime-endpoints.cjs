'use strict';

const HOSTED_CII_RPC_URL = 'https://api.worldmonitor.app/api/intelligence/v1/get-risk-scores';
const DOCKER_CII_RPC_URL = 'http://127.0.0.1:8080/api/intelligence/v1/get-risk-scores';

function resolveCiiRpcUrl(env = process.env) {
  const configured = String(env.CII_RPC_URL || '').trim();
  if (configured) return configured;
  return env.LOCAL_API_MODE === 'docker' ? DOCKER_CII_RPC_URL : HOSTED_CII_RPC_URL;
}

function isLoopbackUrl(rawUrl) {
  try {
    const hostname = new URL(rawUrl).hostname.toLowerCase();
    return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '::1' || hostname === '[::1]';
  } catch {
    return false;
  }
}

function resolveCiiRelayKey(env = process.env, rpcUrl = resolveCiiRpcUrl(env)) {
  if (env.LOCAL_API_MODE === 'docker') {
    if (!isLoopbackUrl(rpcUrl)) return '';
    return String(env.WORLDMONITOR_LOCAL_RELAY_KEY || '').trim();
  }
  return String(env.WORLDMONITOR_RELAY_KEY || '').trim();
}

function buildCiiWarmPingUrl(rpcUrl, timestamp = Date.now()) {
  const url = new URL(rpcUrl);
  url.searchParams.set('_wm_warm_ping', String(timestamp));
  return url.toString();
}

function buildCiiFetchOptions(headers, signal) {
  return { headers, signal, redirect: 'error' };
}

module.exports = {
  buildCiiFetchOptions,
  buildCiiWarmPingUrl,
  resolveCiiRelayKey,
  resolveCiiRpcUrl,
};

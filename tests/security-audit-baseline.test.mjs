import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

import {
  BASELINE_ADVISORIES_BY_LOCKFILE,
  buildBulkAuditPayload,
  bulkAdvisoriesToAuditReport,
  collectAuditFindings,
  collectStaleBaselineEntries,
  collectUnbaselinedFindings,
  isInvokedAsScript,
  parsePossiblyGzippedJson,
} from '../.github/scripts/audit-production-dependencies.mjs';

function auditReportWith(via) {
  return {
    vulnerabilities: {
      [via.name]: {
        name: via.name,
        severity: via.severity,
        via: [via],
      },
    },
  };
}

function readRepoJson(relativePath) {
  return JSON.parse(readFileSync(new URL(`../${relativePath}`, import.meta.url), 'utf8'));
}

describe('security audit baseline', () => {
  it('allows currently baselined high advisories', () => {
    const report = auditReportWith({
      name: 'sharp',
      severity: 'high',
      title: 'sharp inherited vulnerabilities in libvips',
      url: 'https://github.com/advisories/GHSA-f88m-g3jw-g9cj',
    });

    assert.deepEqual(collectUnbaselinedFindings(report, 'package-lock.json'), []);
  });

  it('ignores moderate production advisories for the high-severity PR gate', () => {
    const report = auditReportWith({
      name: 'uuid',
      severity: 'moderate',
      title: 'moderate advisory',
      url: 'https://github.com/advisories/GHSA-w5hq-g745-h8pq',
    });

    assert.deepEqual(collectAuditFindings(report), []);
  });

  it('fails a new unbaselined high advisory', () => {
    const report = auditReportWith({
      name: 'new-package',
      severity: 'high',
      title: 'new advisory',
      url: 'https://github.com/advisories/GHSA-1111-2222-3333',
    });

    assert.deepEqual(collectUnbaselinedFindings(report, 'package-lock.json'), [
      {
        id: 'GHSA-1111-2222-3333',
        name: 'new-package',
        severity: 'high',
        title: 'new advisory',
        url: 'https://github.com/advisories/GHSA-1111-2222-3333',
      },
    ]);
  });

  it('decodes a gzip audit response even when the registry omits its content-encoding header', () => {
    const advisories = {
      sharp: [{
        url: 'https://github.com/advisories/GHSA-f88m-g3jw-g9cj',
        title: 'sharp inherited vulnerabilities in libvips',
        severity: 'high',
      }],
    };

    assert.deepEqual(parsePossiblyGzippedJson(gzipSync(JSON.stringify(advisories))), advisories);
  });

  it('converts the registry bulk response into the report consumed by the fail-closed gate', () => {
    const report = bulkAdvisoriesToAuditReport({
      sharp: [{
        url: 'https://github.com/advisories/GHSA-f88m-g3jw-g9cj',
        title: 'sharp inherited vulnerabilities in libvips',
        severity: 'high',
      }],
    });

    assert.deepEqual(collectAuditFindings(report), [{
      id: 'GHSA-f88m-g3jw-g9cj',
      name: 'sharp',
      severity: 'high',
      title: 'sharp inherited vulnerabilities in libvips',
      url: 'https://github.com/advisories/GHSA-f88m-g3jw-g9cj',
    }]);
  });

  it('builds the fallback bulk payload from production lockfile packages only', () => {
    const payload = buildBulkAuditPayload({
      packages: {
        '': { name: 'example' },
        'node_modules/astro': { version: '6.4.7' },
        'node_modules/sharp': { version: '0.34.5' },
        'node_modules/dev-only': { version: '1.0.0', dev: true },
        'node_modules/astro/node_modules/sharp': { version: '0.34.4' },
      },
    });

    assert.deepEqual(payload, {
      astro: ['6.4.7'],
      sharp: ['0.34.4', '0.34.5'],
    });
  });

  it('tracks a baseline entry for each audited lockfile', () => {
    assert.deepEqual(Object.keys(BASELINE_ADVISORIES_BY_LOCKFILE).sort(), [
      'blog-site/package-lock.json',
      'consumer-prices-core/package-lock.json',
      'docker/runtime-package-lock.json',
      'docker/unraid/redis-rest-package-lock.json',
      'package-lock.json',
      'pro-test/package-lock.json',
      'scripts/package-lock.json',
    ]);
  });

  it('pins patched nanoid and js-yaml releases in every affected production lockfile', () => {
    const rootLock = readRepoJson('package-lock.json');
    const blogLock = readRepoJson('blog-site/package-lock.json');
    const proLock = readRepoJson('pro-test/package-lock.json');
    const consumerPricesLock = readRepoJson('consumer-prices-core/package-lock.json');
    const rootPackage = readRepoJson('package.json');

    assert.equal(rootPackage.overrides?.['markdownlint-cli2']?.['js-yaml'], '4.3.1');
    assert.equal(rootLock.packages['node_modules/nanoid']?.version, '3.3.18');
    assert.equal(rootLock.packages['node_modules/js-yaml']?.version, '4.3.1');
    assert.equal(rootLock.packages['node_modules/@istanbuljs/load-nyc-config/node_modules/js-yaml']?.version, '3.15.1');
    assert.equal(blogLock.packages['node_modules/nanoid']?.version, '3.3.18');
    assert.equal(blogLock.packages['node_modules/js-yaml']?.version, '4.3.1');
    assert.equal(blogLock.packages['node_modules/gray-matter/node_modules/js-yaml']?.version, '3.15.1');
    assert.equal(proLock.packages['node_modules/nanoid']?.version, '3.3.18');
    assert.equal(consumerPricesLock.packages['node_modules/js-yaml']?.version, '4.3.1');
  });

  it('baselines only the unpatched image-size parser advisories in non-server tooling', () => {
    const imageSizeAdvisories = ['GHSA-5p2g-fcmc-qvqq', 'GHSA-w3rx-r6r6-pgpr'];

    assert.deepEqual(
      BASELINE_ADVISORIES_BY_LOCKFILE['package-lock.json'],
      ['GHSA-f88m-g3jw-g9cj', ...imageSizeAdvisories],
    );
    assert.deepEqual(
      BASELINE_ADVISORIES_BY_LOCKFILE['pro-test/package-lock.json'],
      imageSizeAdvisories,
    );
  });

  it('keeps consumer-prices-core on the Fastify v5 audit fix', () => {
    const packageJson = readRepoJson('consumer-prices-core/package.json');
    const lockfile = readRepoJson('consumer-prices-core/package-lock.json');

    assert.match(packageJson.dependencies.fastify, /^\^5\./);
    assert.match(packageJson.dependencies['@fastify/cors'], /^\^11\./);
    assert.match(packageJson.dependencies['js-yaml'], /^\^4\.(?:[2-9]|\d{2,})\./);
    assert.match(lockfile.packages['node_modules/fastify']?.version, /^5\./);
    assert.match(lockfile.packages['node_modules/@fastify/cors']?.version, /^11\./);
    assert.match(lockfile.packages['node_modules/js-yaml']?.version, /^4\.(?:[2-9]|\d{2,})\./);
    assert.deepEqual(BASELINE_ADVISORIES_BY_LOCKFILE['consumer-prices-core/package-lock.json'], []);
  });

  it('keeps the root esbuild audit fix scoped away from Vite build tooling', () => {
    const packageJson = readRepoJson('package.json');
    const lockfile = readRepoJson('package-lock.json');
    const rootEsbuild = lockfile.packages['node_modules/esbuild'];
    const vite = lockfile.packages['node_modules/vite'];
    const viteEsbuild = lockfile.packages['node_modules/vite/node_modules/esbuild'];

    assert.equal(packageJson.overrides?.esbuild, undefined);
    assert.equal(packageJson.overrides?.convex?.esbuild, '0.28.1');
    assert.equal(rootEsbuild?.version, '0.28.1');
    assert.equal(vite?.dependencies?.esbuild, '^0.25.0');
    assert.ok(viteEsbuild, 'Vite must keep its own esbuild when root uses the audit-patched version');
    assert.match(viteEsbuild.version, /^0\.25\./);
    assert.notEqual(viteEsbuild.version, rootEsbuild.version);
  });

  it('flags baseline entries that no longer match any current advisory', () => {
    const report = {
      vulnerabilities: {
        '@clerk/clerk-js': {
          name: '@clerk/clerk-js',
          severity: 'high',
          via: [{
            name: '@clerk/clerk-js',
            severity: 'high',
            title: 'known clerk advisory',
            url: 'https://github.com/advisories/GHSA-w24r-5266-9c3c',
          }],
        },
        'shell-quote': {
          name: 'shell-quote',
          severity: 'high',
          via: [{
            name: 'shell-quote',
            severity: 'high',
            title: 'shell-quote DoS',
            url: 'https://github.com/advisories/GHSA-395f-4hp3-45gv',
          }],
        },
        'sharp': {
          name: 'sharp',
          severity: 'high',
          via: [{
            name: 'sharp',
            severity: 'high',
            title: 'sharp inherited vulnerabilities in libvips',
            url: 'https://github.com/advisories/GHSA-f88m-g3jw-g9cj',
          }],
        },
        'image-size': {
          name: 'image-size',
          severity: 'high',
          via: [
            {
              name: 'image-size',
              severity: 'high',
              title: 'image-size JXL and HEIF parser denial of service',
              url: 'https://github.com/advisories/GHSA-5p2g-fcmc-qvqq',
            },
            {
              name: 'image-size',
              severity: 'high',
              title: 'image-size ICNS parser denial of service',
              url: 'https://github.com/advisories/GHSA-w3rx-r6r6-pgpr',
            },
          ],
        },
      },
    };

    // Pro-test's unpatched image-size advisories are present, so neither is stale.
    assert.deepEqual(collectStaleBaselineEntries(report, 'pro-test/package-lock.json'), []);
    // Root's baselined sharp and image-size advisories are all present.
    assert.deepEqual(collectStaleBaselineEntries(report, 'package-lock.json'), []);
  });

  it('treats a symlinked entry path as direct invocation (no silent fail-open)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'audit-guard-'));
    try {
      const real = join(dir, 'audit.mjs');
      writeFileSync(real, '// stub\n');
      const link = join(dir, 'audit-link.mjs');
      symlinkSync(real, link);
      const moduleUrl = pathToFileURL(real).href;

      // Invoked through the symlink, the guard still fires (the bug being fixed).
      assert.equal(isInvokedAsScript(link, moduleUrl), true);
      assert.equal(isInvokedAsScript(real, moduleUrl), true);
      // A different file must not be mistaken for the module entry.
      assert.equal(isInvokedAsScript(join(dir, 'other.mjs'), moduleUrl), false);
      assert.equal(isInvokedAsScript(undefined, moduleUrl), false);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

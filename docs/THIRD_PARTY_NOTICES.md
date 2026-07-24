# Third-party notices for World Monitor Unraid AIO

This image is an unofficial aggregate distribution. The complete corresponding source for the modified World Monitor image is published at <https://github.com/imzenreally/worldmonitor-unraid-aio> and the upstream project remains at <https://github.com/koala73/worldmonitor>.

The release workflow generates and attests an SPDX SBOM for the exact published digest. That SBOM is the authoritative package-level inventory. The following table identifies the principal runtime components and their upstream license families.

| Component | Purpose | License |
|---|---|---|
| World Monitor and this derivative packaging | Dashboard, local API, relay, seeders, integration | AGPL-3.0-only for this distributed derivative; upstream `LICENSE` also grants later-version use |
| Alpine Linux | Runtime operating-system packages | Multiple OSI licenses; package metadata is recorded in the SBOM |
| Node.js | JavaScript runtime | MIT and bundled third-party notices |
| nginx | HTTP server and reverse proxy | BSD-2-Clause |
| Valkey 9.0.4 | Authenticated Redis-protocol-compatible datastore | BSD-3-Clause, BSD-2-Clause, and MIT |
| `redis` npm package 4.7.1 | Valkey/Redis protocol client used by the private REST adapter | MIT |
| curl/libcurl | Health and readiness probes | curl license |
| OpenSSL | Internal credential generation and TLS support | Apache-2.0 |
| GNU coreutils | Seeder timeout and runtime utilities | GPL-3.0-or-later |
| Supervisor | Process supervision | BSD-derived license |
| su-exec | Healthcheck privilege drop | MIT |
| gettext/envsubst | Safe nginx template expansion | GPL/LGPL components as identified by package metadata |

No upstream affiliation or endorsement is claimed. World Monitor names and artwork identify the packaged upstream application; the container repository, image name, listing name, and user documentation identify this build as unofficial.

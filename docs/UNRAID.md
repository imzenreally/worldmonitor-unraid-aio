# World Monitor AIO for Unraid

This repository contains the source for an **unofficial** all-in-one Unraid image of [World Monitor](https://github.com/koala73/worldmonitor). It packages the upstream dashboard, local API, authenticated Redis cache, Redis REST adapter, optional AIS relay, and scheduled data seeders into one container.

Published image:

```text
ghcr.io/imzenreally/worldmonitor-aio:latest
```

The Community Applications metadata is maintained separately at [imzenreally/unraid-community-apps](https://github.com/imzenreally/unraid-community-apps).

## Security model

The image is designed for LAN or VPN access. **World Monitor does not provide built-in user authentication. Do not expose it directly to the public internet.** If remote browser access is required, place it behind an authenticated reverse proxy or use a VPN.

The Unraid template uses:

- Bridge networking
- One published HTTP port (`8080` inside the container)
- One persistent `/config` path
- No privileged mode
- No host networking
- No Docker socket
- No host devices
- No array, media, or system mounts
- `no-new-privileges`
- A read-only root filesystem with limited temporary filesystems
- A PID limit and bounded Docker logs

Redis, the Redis REST adapter, the local API, and the AIS relay bind to loopback inside the container. They are not published to the Docker network.

The entrypoint and supervisor start as root so a newly created Unraid appdata directory can be initialized. All application services run as the unprivileged `appuser` account.

## Requirements

- Unraid 6.12 or newer
- AMD64/x86-64 CPU
- Approximately 1 GB free Docker image space
- At least 2 GB available RAM; 4 GB is recommended during initial seeding
- Outbound HTTPS access for upstream feeds
- No API key is required to start the dashboard

## Manual Unraid installation

Until the application has passed manual testing and been submitted to Community Applications:

1. Open **Docker** in the Unraid web UI.
2. Choose **Add Container**.
3. Enable **Advanced View**.
4. Enter:

   | Field | Value |
   |---|---|
   | Name | `worldmonitor-aio` |
   | Repository | `ghcr.io/imzenreally/worldmonitor-aio:latest` |
   | Network Type | `Bridge` |
   | Web UI | `http://[IP]:[PORT:8080]/` |
   | Port | Container `8080`, host `3300` or another unused TCP port |
   | Appdata | `/mnt/user/appdata/worldmonitor-aio` mapped read/write to `/config` |

5. Set Extra Parameters to:

   ```text
   --read-only --tmpfs /tmp:rw,nosuid,nodev,size=256m --tmpfs /run:rw,nosuid,nodev,size=32m --security-opt=no-new-privileges:true --pids-limit=512 --log-opt max-size=25m --log-opt max-file=2
   ```

6. Add these variables:

   | Variable | Default |
   |---|---|
   | `SEED_ON_START` | `true` |
   | `SEED_INTERVAL_MINUTES` | `30` |
   | `SEED_TIMEOUT` | `1800` |
   | `REDIS_MAXMEMORY` | `256mb` |

7. Add only the optional API keys you intend to use.
8. Apply the container and open `http://UNRAID-IP:3300/`.

The first seed pass can take several minutes. Panels populate incrementally, and an empty panel does not necessarily indicate a failed container.

## Optional API keys

All keys are optional. Keep them in the Unraid template variables; do not place them in screenshots, issues, or logs.

| Variable | Feature |
|---|---|
| `AISSTREAM_API_KEY` | Live AIS vessel tracking |
| `NASA_FIRMS_API_KEY` | NASA FIRMS wildfire data |
| `FINNHUB_API_KEY` | Market data |
| `FRED_API_KEY` | Federal Reserve economic data |
| `EIA_API_KEY` | US energy data |
| `AVIATIONSTACK_API` | Aviation data |
| `TRAVELPAYOUTS_API_TOKEN` | Travel and flight data |
| `CLOUDFLARE_API_TOKEN` | Cloudflare Radar-backed data; account access may be restricted or paid |
| `ACLED_ACCESS_TOKEN` | ACLED conflict data |
| `ACLED_EMAIL` | ACLED account email when required by the upstream API |
| `ACLED_PASSWORD` | ACLED account password when required by the upstream API |
| `GROQ_API_KEY` | Groq-backed AI summaries |
| `OPENROUTER_API_KEY` | OpenRouter-backed AI summaries |
| `LLM_API_URL` | OpenAI-compatible endpoint URL |
| `LLM_API_KEY` | OpenAI-compatible endpoint key |
| `LLM_MODEL` | Model name for the compatible endpoint |

Some datasets use public sources and are populated by the seeders. API keys do not fill every health entry. Upstream services may also rate-limit, restrict, or discontinue feeds.

## Persistent data

`/config` contains:

- Generated internal Redis and API credentials
- Redis database files
- Seeder status and timing files

Back up the appdata directory while the container is stopped. Do not publish `secrets.env` from that directory.

To reset the installation completely, remove the container and delete only its dedicated appdata directory. Never point `/config` at an existing application directory.

## Health and troubleshooting

Docker health verifies nginx, the local API, optional AIS relay when configured, and Redis.

Useful commands from an Unraid terminal:

```bash
docker ps --filter name=worldmonitor-aio
docker logs --tail 200 worldmonitor-aio
docker inspect --format '{{.State.Health.Status}}' worldmonitor-aio
```

The dashboard's `/api/health` endpoint reports **data freshness**, not just container liveness. It can report unhealthy while the Docker container is healthy because optional datasets are unconfigured, rate-limited, or still seeding.

Common situations:

- **Dashboard loads but many panels are empty:** wait for the first seed run and inspect the container logs.
- **AIS is absent:** configure `AISSTREAM_API_KEY`; without it the relay is deliberately disabled.
- **Container health is failing:** inspect Docker logs for nginx, API, Redis, or relay startup failures.
- **Redis memory warning:** increase `REDIS_MAXMEMORY` only if the server has adequate RAM.
- **Port conflict:** choose a different host port while keeping container port `8080`.

## Updating and rollback

Before updating, back up `/config` and record the currently running digest:

```bash
docker inspect --format '{{index .RepoDigests 0}}' worldmonitor-aio
```

The `latest` tag follows the newest tested Unraid release. Immutable release tags use the upstream version plus an Unraid packaging revision, for example:

```text
2.10.0-unraid.1
```

To roll back, change the repository field to the prior immutable tag and apply the container again.

## Support boundaries

- Report AIO image, startup, seeding, persistence, or Unraid-template problems at [imzenreally/worldmonitor issues](https://github.com/imzenreally/worldmonitor/issues).
- Report upstream application bugs only after confirming they also occur with the official upstream deployment.

This packaging is not affiliated with or endorsed by the upstream World Monitor maintainer.

## License and source

World Monitor and this derivative image are distributed under the GNU Affero General Public License, version 3 or later. The complete corresponding source for published images is available in this repository. Upstream copyright and attribution are retained in [`LICENSE`](../LICENSE).

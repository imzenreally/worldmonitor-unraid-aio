# Getting API keys for World Monitor AIO on Unraid

World Monitor starts without any third-party credentials. Add only the providers you want: an empty key disables or degrades that provider without preventing the container from starting.

Provider plans, quotas, and approval rules change. The links below point to the providers' official signup or documentation pages rather than copying volatile pricing into this guide.

## Add or change a credential in Unraid

1. Open **Docker** in the Unraid web UI.
2. Click the `WorldMonitorAIO-Unofficial` icon and choose **Edit**.
3. Find the matching variable. Enable **Advanced View** if necessary.
4. Paste only the credential value—not a variable name, shell command, or surrounding quotes.
5. Click **Apply**. Unraid recreates the container while preserving `/mnt/user/appdata/worldmonitor-aio`.
6. Allow the relevant seeder or panel to refresh. The first broad seed pass can take several minutes.

Masked fields protect casual screen viewing, but an Unraid administrator can still inspect Docker environment variables. Do not post screenshots of expanded variables, `docker inspect` output, `/config/secrets.env`, or provider dashboards.

## Quick selection guide

| If you want… | Configure |
|---|---|
| Live vessel positions | `AISSTREAM_API_KEY` |
| Higher-quality satellite wildfire detections | `NASA_FIRMS_API_KEY` |
| Real-time stock quotes and market data | `FINNHUB_API_KEY` |
| Federal Reserve and shipping/economic series | `FRED_API_KEY` |
| US oil, inventory, production, and energy data | `EIA_API_KEY` |
| Live flight and airport data | `AVIATIONSTACK_API` |
| Flight-price search | `TRAVELPAYOUTS_API_TOKEN` |
| Cloudflare Radar outage annotations | `CLOUDFLARE_API_TOKEN` |
| ACLED conflict and protest events | ACLED credentials described below |
| Hosted AI summaries | `GROQ_API_KEY` and/or `OPENROUTER_API_KEY` |
| Your own OpenAI-compatible model endpoint | `LLM_API_URL`, `LLM_API_KEY`, and `LLM_MODEL` |

## AISStream

**Unraid variable:** `AISSTREAM_API_KEY`

**Feature:** Live AIS vessel tracking through the private relay inside the AIO container.

1. Open [AISStream authentication](https://aisstream.io/authenticate).
2. Sign in using one of the supported identity providers.
3. Open the AISStream API Keys/customer page and create an API key.
4. Copy the generated key into `AISSTREAM_API_KEY`.

Official reference: [AISStream API documentation](https://aisstream.io/documentation).

Without this key, the AIS relay deliberately remains disabled; the rest of World Monitor continues normally.

## NASA FIRMS

**Unraid variable:** `NASA_FIRMS_API_KEY`

**Feature:** Satellite fire detections from NASA's Fire Information for Resource Management System.

1. Open the official [FIRMS API map-key registration page](https://firms.modaps.eosdis.nasa.gov/api/map_key/).
2. Register an email address for a free FIRMS `MAP_KEY`.
3. Complete any email verification requested by NASA.
4. Paste the map key into `NASA_FIRMS_API_KEY`.

NASA calls this credential a **MAP_KEY**, but World Monitor's variable is named `NASA_FIRMS_API_KEY`.

## Finnhub

**Unraid variable:** `FINNHUB_API_KEY`

**Feature:** Real-time stock quotes and market data.

1. [Register for Finnhub](https://finnhub.io/register) or sign in to an existing account.
2. Open the Finnhub dashboard and locate the API key assigned to the account.
3. Paste it into `FINNHUB_API_KEY`.

Provider entitlements and rate limits depend on the active Finnhub plan. Without a key, World Monitor falls back to more limited market sources where available.

## FRED

**Unraid variable:** `FRED_API_KEY`

**Feature:** Federal Reserve Economic Data, including macroeconomic and shipping-related series.

1. Sign in to a FRED account.
2. Open the official [FRED API key page](https://fred.stlouisfed.org/docs/api/api_key.html).
3. Choose **Request API Key** and provide the short application description FRED requests.
4. Paste the issued key into `FRED_API_KEY`.

A FRED key is a 32-character lowercase alphanumeric value. Do not use the demonstration key shown in FRED's documentation.

## US Energy Information Administration

**Unraid variable:** `EIA_API_KEY`

**Feature:** US oil prices, production, inventory, fuel, and other energy data.

1. Open the official [EIA Open Data registration page](https://www.eia.gov/opendata/register.php).
2. Submit the requested contact information and accept the API terms.
3. Retrieve the key using the instructions sent by EIA.
4. Paste it into `EIA_API_KEY`.

World Monitor uses the current EIA Open Data API. Do not follow old API v1 tutorials.

## Aviationstack

**Unraid variable:** `AVIATIONSTACK_API`

**Feature:** Live flight, airport, delay, and carrier data.

1. Open [Aviationstack signup](https://aviationstack.com/signup/free) and select an appropriate plan.
2. Verify the account if requested.
3. Copy the access key shown in the Aviationstack dashboard.
4. Paste it into `AVIATIONSTACK_API`.

Official reference: [Aviationstack API documentation](https://aviationstack.com/documentation).

Aviation data can consume substantial quota because monitored airports refresh repeatedly. Check the provider's current plan limits before enabling it. The AIO template does not expose the upstream project's advanced Aviationstack budget knobs, so choose a plan whose quota can tolerate the default seeding schedule.

## Travelpayouts

**Unraid variable:** `TRAVELPAYOUTS_API_TOKEN`

**Feature:** Flight-price search in the aviation interface.

1. Register or sign in at [Travelpayouts](https://www.travelpayouts.com/).
2. Open the account profile.
3. Find the **API token** section and copy the automatically issued token.
4. Paste it into `TRAVELPAYOUTS_API_TOKEN`.

Official reference: [Where to find the API token](https://support.travelpayouts.com/hc/en-us/articles/13024069738386-Where-to-find-API-token).

Some Travelpayouts/Aviasales APIs have partner, attribution, traffic, or approval requirements. Possessing a token does not guarantee access to every endpoint. This token affects flight pricing, not basic flight tracking.

## Cloudflare Radar

**Unraid variable:** `CLOUDFLARE_API_TOKEN`

**Feature:** Cloudflare Radar internet-outage annotations.

1. Sign in to Cloudflare and open [My Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens).
2. Choose **Create Token**, then create a **Custom Token**.
3. Add the permission **Account → Radar → Read**.
4. Restrict account resources to the account you intend to use.
5. Create the token, copy it once, and paste it into `CLOUDFLARE_API_TOKEN`.

Official reference: [Make your first Radar API request](https://developers.cloudflare.com/radar/get-started/first-request/).

Use a scoped API token—not the Cloudflare Global API Key. Do not grant DNS, Workers, R2, or account-edit permissions for this feature.

## ACLED

**Unraid variables:**

- Preferred: `ACLED_EMAIL` and `ACLED_PASSWORD`
- Alternative: `ACLED_ACCESS_TOKEN`

**Feature:** Armed Conflict Location & Event Data conflict and protest feeds.

1. Create or sign in to a myACLED account through the official [ACLED API getting-started guide](https://acleddata.com/api-documentation/getting-started).
2. Confirm the account has API/data access under ACLED's current terms.
3. Choose one authentication method:

### Preferred: automatic OAuth refresh

Set both:

- `ACLED_EMAIL` to the account username/email
- `ACLED_PASSWORD` to the account password

World Monitor exchanges these credentials for an OAuth access token and refreshes it as needed. If both email and password are present, this method takes priority over `ACLED_ACCESS_TOKEN`.

### Alternative: static access token

Generate an OAuth access token through ACLED's documented account/API flow and set only `ACLED_ACCESS_TOKEN`. Static ACLED access tokens expire, so this method requires periodic manual replacement.

Official references:

- [ACLED API documentation](https://acleddata.com/acled-api-documentation)
- [ACLED endpoint and OAuth example](https://acleddata.com/api-documentation/acled-endpoint)

Storing account credentials in Docker environment variables is a meaningful trade-off. If you do not want the ACLED password available to Unraid administrators through container inspection, use the short-lived token method and rotate it manually.

## Groq

**Unraid variable:** `GROQ_API_KEY`

**Feature:** Primary hosted provider for AI-generated summaries and briefs.

1. Sign in to GroqCloud.
2. Open [GroqCloud API Keys](https://console.groq.com/keys).
3. Create a key for this World Monitor installation.
4. Copy it immediately and paste it into `GROQ_API_KEY`.

Official reference: [Groq quickstart](https://console.groq.com/docs/quickstart).

Groq account roles, models, quotas, and billing can change. Review the current console limits before enabling frequent AI-assisted seeding.

## OpenRouter

**Unraid variable:** `OPENROUTER_API_KEY`

**Feature:** Hosted AI fallback when Groq is unavailable or unsuitable.

1. Sign in to OpenRouter.
2. Open [OpenRouter API Keys](https://openrouter.ai/settings/keys).
3. Create a key, preferably with a descriptive name and a spending/credit limit.
4. Paste it into `OPENROUTER_API_KEY`.

Official references:

- [OpenRouter authentication](https://openrouter.ai/docs/api_reference/authentication)
- [OpenRouter model catalog](https://openrouter.ai/models)

A key can exist without enough credit or provider access for the model World Monitor selects. Check the OpenRouter activity page if summaries fail while the key appears valid.

## Generic OpenAI-compatible endpoint

**Unraid variables:**

- `LLM_API_URL`
- `LLM_API_KEY`
- `LLM_MODEL`

**Feature:** AI summaries through a local or hosted OpenAI-compatible Chat Completions endpoint.

Set all three together:

1. `LLM_API_URL` — the complete Chat Completions URL, including `/v1/chat/completions`, for example:

   ```text
   http://192.168.0.112:11434/v1/chat/completions
   ```

2. `LLM_API_KEY` — the credential required by that endpoint. World Monitor requires a non-empty value and sends it as a Bearer token. For a trusted local endpoint that ignores authentication, use a non-secret placeholder value accepted by that server.
3. `LLM_MODEL` — the exact model identifier exposed by the endpoint, including any provider namespace or tag it requires.

Important networking notes:

- `localhost` and `127.0.0.1` refer to the World Monitor container itself, not the Unraid host or another machine.
- Use a reachable LAN IP, DNS name, or Docker-network hostname.
- Keep an unauthenticated local model endpoint on a trusted network; do not expose it publicly.
- The endpoint must implement an OpenAI-compatible **Chat Completions** request/response shape. A provider's base URL alone is not enough.

This generic provider is separate from `GROQ_API_KEY` and `OPENROUTER_API_KEY`. You may configure more than one provider for fallback behavior.

## Troubleshooting credentials

### A panel remains empty

- Wait for the initial seed pass and the provider's next refresh interval.
- Open the container's **Logs** from Unraid and search for the provider name—not the credential value.
- Confirm the value contains no quotes, leading/trailing spaces, variable name, or copied shell syntax.
- Check the provider dashboard for quota exhaustion, account approval, billing, or token revocation.
- Remember that some data sources are public and some health entries are optional; adding every key does not make every freshness indicator green.

### A key was exposed

1. Revoke it in the provider dashboard immediately.
2. Create a replacement.
3. Edit the Unraid container and replace the value.
4. Apply the template to recreate the container.
5. Remove screenshots, logs, shell history, or issue attachments containing the old value where possible.

Do not merely delete the variable from Unraid: once a credential has been exposed, revocation at the provider is what invalidates it.

### The container becomes unhealthy after adding a key

A malformed optional key normally causes only that provider to fail. If Docker health changes after an edit:

1. Verify that the container still has its `/config` mapping and required runtime variables.
2. Confirm the container port remains `8080` even if the host port is different.
3. Inspect container logs for startup/configuration errors.
4. Temporarily clear only the newly added credential and apply again.
5. Report reproducible AIO packaging problems at [imzenreally/worldmonitor-unraid-aio issues](https://github.com/imzenreally/worldmonitor-unraid-aio/issues) without including the secret.

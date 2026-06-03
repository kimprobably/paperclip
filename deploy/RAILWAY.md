# Deploying Paperclip on Railway (the `maestro-fabro` company OS)

This fork deploys Paperclip as the **hub** of our agent company OS, in the
existing Railway project **`maestro-fabro`** (`production` env), co-located with
the Hermes agents (`maestro-hermes-gateway`, `maestro-hermes-joni`) and Fabro
(`fabro-maestro`). Internal traffic (Paperclip ↔ Postgres ↔ Hermes ↔ Fabro)
rides Railway's **free IPv6 private network**; only Paperclip's web UI is public.

## What this fork changes vs upstream
- **Pinned agent CLIs** in `Dockerfile` (claude-code, codex, opencode, convex) —
  no `@latest` drift. Bump deliberately.
- **Fabro CLI** baked in (`ARG FABRO_VERSION`) so local agents can run
  deterministic workflows.
- **Removed `VOLUME ["/paperclip"]`** — Railway rejects Dockerfile VOLUME and
  won't mount its managed volume over it.
- Added `railway.toml` (healthcheck `/api/health`, restart policy).

## Service config (set in Railway)
1. **Postgres**: a dedicated `paperclip-db` Postgres service in `maestro-fabro`.
2. **Volume**: attach a volume to the `paperclip` service, mount path `/paperclip`.
3. **Resources**: ~2 vCPU / 4 GB (it spawns agent CLIs).
4. **Public domain**: generate one on the `paperclip` service → that's `PAPERCLIP_API_URL`.

## Environment variables
| Var | Value | Notes |
|-----|-------|-------|
| `DATABASE_URL` | `${{paperclip-db.DATABASE_URL}}` | Reference var → private IPv6 host, free |
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` | login required |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `public` | internet-facing |
| `PAPERCLIP_BIND` | `custom` | use explicit bind host below |
| `PAPERCLIP_BIND_HOST` | `::` | IPv6 all-ifaces: Railway public proxy **and** private-net receive |
| `HOST` | `::` | legacy override kept consistent with bind host |
| `PAPERCLIP_API_URL` | `https://<railway-domain>` | satisfies public-mode "explicit URL" check |
| `PAPERCLIP_PUBLIC_URL` | `https://<railway-domain>` | their compose used this name; harmless to set both |
| `SERVE_UI` | `true` | serve the React UI from the server |
| `PAPERCLIP_HOME` | `/paperclip` | = volume mount |
| `BETTER_AUTH_SECRET` | `openssl rand -base64 32` | ⚠️ **clean, no trailing newline** |
| `PAPERCLIP_SECRETS_MASTER_KEY` | `openssl rand -base64 32` | ⚠️ clean; encrypts stored agent secrets; set explicitly so it survives redeploys |
| `PORT` | _unset_ | Railway injects it; app honors it |
| `PAPERCLIP_AUTH_DISABLE_SIGN_UP` | `true` | **set AFTER first admin signs up**, then redeploy |

If keeping the all-LLM-via-OpenRouter standard for API-key adapters, point
`ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` at OpenRouter instead of setting raw
provider keys. (Subscription-OAuth adapters don't need keys at all.)

## Two human-only gates (browser OAuth — cannot be automated)
1. **Subscription auth** for the agent CLIs, persisted on the `/paperclip` volume:
   ```bash
   railway run --service paperclip codex login          # ChatGPT sub
   railway run --service paperclip claude setup-token    # Claude sub
   ```
2. **First admin**: visit `https://<railway-domain>` → sign up. First signup =
   board admin. Then set `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true`, redeploy, and use
   the in-app invite flow for everyone else.

## Verify
- `curl -sf https://<railway-domain>/api/health` → 200
- Logs show `plugin job coordinator started` + `plugin-loader: loadAll complete`
- `railway run --service paperclip fabro --version` works inside the container

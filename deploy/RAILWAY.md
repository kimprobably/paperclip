# Paperclip on Railway — the `maestro-fabro` company OS

**Live:** https://paperclip-production-9411.up.railway.app (authenticated + public).
Runs in the Railway project **`maestro-fabro`** / `production`, co-located on the
free IPv6 private network with the Hermes agents (`maestro-hermes-gateway`,
`maestro-hermes-joni`) and Fabro (`fabro-maestro`). Only this service is public.

## Why we deploy a prebuilt image (not source)

Building Paperclip from source via the root `Dockerfile` currently **fails** the
server `tsc` step: the lockfile drifted onto `@types/express-serve-static-core@5.1.x`,
which stops the global `Express.Request.actor` augmentation from applying (~80
`req.actor` errors), and HEAD has a stray `req.params.filePath` route-param error.
Their tagged releases carry the same `@types` drift. So instead we layer onto the
maintainers' **green prebuilt image**:

- `deploy/Dockerfile.railway` = `FROM ghcr.io/paperclipai/paperclip:sha-70b1a91`
  + the **Fabro CLI**. Builds in seconds (no monorepo build). `railway.toml`
  points `dockerfilePath` here.
- Upgrade by bumping the `FROM` sha tag (see GHCR for `latest`) and `FABRO_VERSION`.

The image already ships `claude` + `codex`; we add `fabro`. All three are on PATH
in the running container.

## Service config (already applied)

| Thing | Value |
|---|---|
| Service | `paperclip` (`029d8dfb-790b-44b8-8723-680832878eb2`) |
| Postgres | `Postgres` (`93a1a451-…`), `DATABASE_URL=${{Postgres.DATABASE_URL}}` (private) |
| Volume | `paperclip-volume` → `/paperclip` |
| Domain | `paperclip-production-9411.up.railway.app` (port 3100) |

### Volume permission gotcha (important)
The image entrypoint only `chown`s `/paperclip` to the `node` user **if**
`USER_UID`/`USER_GID` differ from the baked-in `1000/1000`. On Railway the volume
mounts as root, so the server boots as `node` and dies with
`EACCES mkdir /paperclip/instances/default/logs`. **Fix:** set `USER_GID=1001`
(keep `USER_UID=1000`) on the service → the entrypoint (running as root) chowns the
volume on boot. Already set.

### Environment variables (already set)
```
DATABASE_URL=${{Postgres.DATABASE_URL}}
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=public
PAPERCLIP_BIND=custom
PAPERCLIP_BIND_HOST=::          # IPv6: Railway public proxy + private-net receive
HOST=::
PORT=3100
SERVE_UI=true
PAPERCLIP_HOME=/paperclip
PAPERCLIP_API_URL=https://paperclip-production-9411.up.railway.app
PAPERCLIP_PUBLIC_URL=https://paperclip-production-9411.up.railway.app
USER_UID=1000
USER_GID=1001                   # triggers the volume chown
BETTER_AUTH_SECRET=…            # clean, no trailing newline
PAPERCLIP_SECRETS_MASTER_KEY=… # clean; encrypts stored agent secrets
```

## Operator steps that require a browser (only these remain)

1. **First admin:** open the URL → sign up. First signup becomes board admin.
   Then set `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` and redeploy; invite the rest in-app.
2. **Agent CLI subscription auth** — must run **inside** the container so creds land
   on the `/paperclip` volume. Use `railway ssh` (NOT `railway run`, which is local):
   ```bash
   railway ssh --service paperclip
   # inside the container:
   export HOME=/paperclip
   codex login          # ChatGPT subscription (device flow → approve in browser)
   claude setup-token   # Claude subscription
   fabro auth login     # Fabro
   ```
   Alternative: set `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` env vars (point
   `ANTHROPIC_BASE_URL`/`OPENAI_BASE_URL` at OpenRouter to keep the all-LLM-via-
   OpenRouter standard).

## Health / verify
- `curl -sf https://paperclip-production-9411.up.railway.app/api/health` → 200
- `railway ssh --service paperclip sh -lc 'fabro --version; command -v codex claude'`

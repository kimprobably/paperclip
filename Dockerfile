# syntax=docker/dockerfile:1.20
FROM node:lts-trixie-slim AS base
ARG USER_UID=1000
ARG USER_GID=1000
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gosu curl gh git wget ripgrep python3 \
  && rm -rf /var/lib/apt/lists/* \
  && corepack enable

# Modify the existing node user/group to have the specified UID/GID to match host user
RUN usermod -u $USER_UID --non-unique node \
  && groupmod -g $USER_GID --non-unique node \
  && usermod -g $USER_GID -d /paperclip node

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./
COPY cli/package.json cli/
COPY server/package.json server/
COPY ui/package.json ui/
COPY packages/shared/package.json packages/shared/
COPY packages/db/package.json packages/db/
COPY packages/adapter-utils/package.json packages/adapter-utils/
COPY packages/mcp-server/package.json packages/mcp-server/
COPY packages/skills-catalog/package.json packages/skills-catalog/
COPY packages/adapters/acpx-local/package.json packages/adapters/acpx-local/
COPY packages/adapters/claude-local/package.json packages/adapters/claude-local/
COPY packages/adapters/codex-local/package.json packages/adapters/codex-local/
COPY packages/adapters/cursor-cloud/package.json packages/adapters/cursor-cloud/
COPY packages/adapters/cursor-local/package.json packages/adapters/cursor-local/
COPY packages/adapters/gemini-local/package.json packages/adapters/gemini-local/
COPY packages/adapters/grok-local/package.json packages/adapters/grok-local/
COPY packages/adapters/openclaw-gateway/package.json packages/adapters/openclaw-gateway/
COPY packages/adapters/opencode-local/package.json packages/adapters/opencode-local/
COPY packages/adapters/pi-local/package.json packages/adapters/pi-local/
COPY packages/plugins/sdk/package.json packages/plugins/sdk/
COPY --parents packages/plugins/sandbox-providers/./*/package.json packages/plugins/sandbox-providers/
COPY packages/plugins/paperclip-plugin-fake-sandbox/package.json packages/plugins/paperclip-plugin-fake-sandbox/
COPY packages/plugins/plugin-llm-wiki/package.json packages/plugins/plugin-llm-wiki/
COPY packages/plugins/plugin-workspace-diff/package.json packages/plugins/plugin-workspace-diff/
COPY patches/ patches/
COPY scripts/link-plugin-dev-sdk.mjs scripts/

# cachebust-2: changing this RUN busts Railway's cached deps layer. Also asserts
# the express-serve-static-core pin (5.0.x) held — 5.1.x silently breaks the
# global Express.Request `actor` augmentation and fails the server tsc build.
RUN pnpm install --frozen-lockfile \
 && echo "== installed express-serve-static-core ==" \
 && ls -d node_modules/.pnpm/@types+express-serve-static-core@* \
 && ! ls -d node_modules/.pnpm/@types+express-serve-static-core@5.1* 2>/dev/null

FROM base AS build
WORKDIR /app
COPY --from=deps /app /app
COPY . .
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

FROM base AS production
ARG USER_UID=1000
ARG USER_GID=1000
WORKDIR /app
COPY --chown=node:node --from=build /app /app
# Pin agent CLIs to today's known-good versions. `@latest` is a footgun: a
# codex protocol change (0.134.0) silently broke our Hermes JSON-RPC wrapper.
# Bump these deliberately, never let them drift at build time.
RUN npm install --global --omit=dev \
      @anthropic-ai/claude-code@2.1.161 \
      @openai/codex@0.136.0 \
      opencode-ai@1.15.13 \
      convex@1.40.0 \
  && apt-get update \
  && apt-get install -y --no-install-recommends openssh-client jq \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /paperclip \
  && chown node:node /paperclip

COPY scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ── Fabro CLI (deterministic workflow runtime our agents call) ────────────────
# Bypass install.sh (needs authenticated gh at build time); pull the pinned
# release tarball directly. Debian trixie = glibc, so use the -gnu target.
# Bump FABRO_VERSION deliberately to upgrade.
ARG FABRO_VERSION=v0.252.0
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
      x86_64)  TARGET="x86_64-unknown-linux-gnu" ;; \
      aarch64) TARGET="aarch64-unknown-linux-gnu" ;; \
      *) echo "unsupported arch $ARCH"; exit 1 ;; \
    esac; \
    ASSET_URL="$(curl -fsSL "https://api.github.com/repos/fabro-sh/fabro/releases/tags/${FABRO_VERSION}" \
      | jq -r --arg t "fabro-${TARGET}.tar.gz" '.assets[] | select(.name==$t) | .browser_download_url')"; \
    test -n "$ASSET_URL" || { echo "fabro asset not found for ${FABRO_VERSION}/${TARGET}"; exit 1; }; \
    curl -fsSL "$ASSET_URL" | tar xz -C /tmp; \
    mv "/tmp/fabro-${TARGET}/fabro" /usr/local/bin/fabro; \
    chmod +x /usr/local/bin/fabro; \
    fabro --version

ENV NODE_ENV=production \
  HOME=/paperclip \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip \
  PAPERCLIP_INSTANCE_ID=default \
  USER_UID=${USER_UID} \
  USER_GID=${USER_GID} \
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
  PAPERCLIP_DEPLOYMENT_MODE=authenticated \
  PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
  OPENCODE_ALLOW_ALL_MODELS=true

# NOTE: no `VOLUME ["/paperclip"]` directive — Railway rejects Dockerfile VOLUME
# and won't mount its managed volume cleanly over it. The persistent volume is
# attached at /paperclip via Railway service config instead.
EXPOSE 3100

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]

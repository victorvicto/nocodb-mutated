RUN curl -L https://github.com/benbjohnson/litestream/releases/download/v0.5.8/litestream-0.5.8-linux-x86_64.deb \
  -o /usr/local/bin/ \
  && dpkg -i /usr/local/bin/litestream-0.5.8-linux-x86_64.deb \
  && chmod +x /usr/local/bin/litestream


# ---------- app builder ----------
FROM node:22-slim AS builder
WORKDIR /usr/src/app

# Build-time dependencies (node native build toolchain + git)
RUN apt-get update && apt-get install -y \
  python3 \
  python-is-python3 \
  make \
  g++ \
  git \
  && rm -rf /var/lib/apt/lists/*

# Ensure pnpm available
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# Copy entire repo (build context must be repo root)
COPY . .

# Install workspace deps (full install)
RUN pnpm install --frozen-lockfile

# Build frontend (nc-gui)
RUN pnpm --filter nc-gui build

# Build backend bundle (uses rspack as defined in packages/nocodb/package.json)
# RUN pnpm --filter nocodb build
EE="true-xc-test" pnpm --filter nocodb build

# Seeing what has been created for eventual further debugging
RUN echo "=== listing packages/nocodb ===" && ls -lh packages/nocodb && echo "=== listing dist ===" && ls -lh packages/nocodb/dist

# Verify expected artifact exists (fail early if missing)
RUN test -f packages/nocodb/dist/bundle.js \
  && echo "Backend bundle present: packages/nocodb/dist/bundle.js"

# Create a production-only hoisted node_modules layout
# Write hoisted linker to .npmrc to match upstream expectations
RUN echo "node-linker=hoisted" > .npmrc \
  && pnpm install --prod --shamefully-hoist


# ---------- runtime ----------
FROM node:22-slim AS runtime
WORKDIR /usr/src/app

ENV NODE_ENV=production \
    PORT=8080 \
    NC_DOCKER=0.6 \
    NC_TOOL_DIR=/usr/app/data/

# Runtime deps used by upstream image
RUN apt-get update && apt-get install -y dumb-init curl wget \
  && curl -L "https://github.com/TomWright/dasel/releases/download/v2.8.1/dasel_linux_$(dpkg --print-architecture)" -o /usr/local/bin/dasel \
  && chmod +x /usr/local/bin/dasel \
  && rm -rf /var/lib/apt/lists/*

# Copy litestream binary from lt-builder
COPY --from=lt-builder /usr/src/lt /usr/local/bin/litestream

# Copy the built backend runtime files from builder
# The runtime will expect /usr/src/app/dist and /usr/src/app/docker
COPY --from=builder /usr/src/app/packages/nocodb/dist ./dist
COPY --from=builder /usr/src/app/packages/nocodb/docker ./docker
COPY --from=builder /usr/src/app/packages/nocodb/package.json ./package.json

# Copy hoisted production node_modules
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/.npmrc ./.npmrc

# Expose port and set entrypoint/cmd to match upstream
EXPOSE 8080

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["node", "docker/main"]

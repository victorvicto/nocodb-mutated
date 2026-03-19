###########
# Litestream Builder (Unchanged)
###########
FROM golang:1.25 AS lt-builder
WORKDIR /usr/src/
RUN apt-get update && apt-get install -y git make gcc libc-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/benbjohnson/litestream.git litestream && cd litestream && go install ./cmd/litestream
RUN cp /go/bin/litestream /usr/src/lt

###########
# Build & Deploy Stage
###########
FROM node:22-slim AS builder
WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y python3 python-is-python3 make g++ libssl-dev git && rm -rf /var/lib/apt/lists/*
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# 1. Copy workspace metadata
#COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml .npmrc tsconfig.json lerna.json ./
# Copy API definitions if they exist (used by SDK generator)
COPY APIs.json* ./
COPY scripts ./scripts
COPY packages ./packages

# 2. Install all dependencies (needed for build)
RUN pnpm install --frozen-lockfile

# 3. Build SDKs (Crucial: builds both main and module now)
RUN pnpm --filter nocodb-sdk... build
RUN pnpm --filter nocodb-sdk-v2... build

# 4. Build the GUI (your custom Vue files)
RUN pnpm --filter nc-gui build

# 5. Build the Backend
RUN pnpm --filter nocodb build

# 6. THE DEPLOY STEP
# This creates a standalone production folder for the backend at /usr/src/deploy
RUN pnpm --filter nocodb --prod deploy /usr/src/deploy

# 7. Move built GUI files into the backend's public folder
# NocoDB serves the frontend from its own 'public' or 'static' directory
RUN cp -r packages/nc-gui/.output/public/* /usr/src/deploy/public/ 2>/dev/null || true

###########
# Runner (The Slim Production Image)
###########
FROM node:22-slim
WORKDIR /usr/src/app

ENV NC_DOCKER=0.6 \
    NC_TOOL_DIR=/usr/app/data/ \
    NODE_ENV=production \
    PORT=8080

RUN apt-get update && apt-get install -y dumb-init curl wget && \
    curl -L "https://github.com/TomWright/dasel/releases/download/v2.8.1/dasel_linux_$(dpkg --print-architecture)" -o /usr/local/bin/dasel && \
    chmod +x /usr/local/bin/dasel && \
    rm -rf /var/lib/apt/lists/*

# Copy litestream from the first stage
COPY --from=lt-builder /usr/src/lt /usr/local/bin/litestream

# Copy ONLY the deployed application (no devDeps, no broken symlinks)
COPY --from=builder /usr/src/deploy /usr/src/app

# Copy the start scripts and config
COPY packages/nocodb/docker/litestream.yml /etc/litestream.yml
COPY packages/nocodb/docker/start-litestream.sh /usr/src/app/start.sh
RUN chmod +x /usr/src/app/start.sh

EXPOSE 8080
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/usr/src/app/start.sh"]

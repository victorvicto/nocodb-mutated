###########
# Litestream Builder
###########
FROM golang:1.25 AS lt-builder

WORKDIR /usr/src/

RUN apt-get update && apt-get install -y \
    git \
    make \
    gcc \
    libc-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# build litestream
RUN git clone https://github.com/benbjohnson/litestream.git litestream
RUN cd litestream && go install ./cmd/litestream
RUN cp $GOPATH/bin/litestream /usr/src/lt


###########
# Node Builder
###########
FROM node:22-slim AS builder

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y \
    python3 \
    python-is-python3 \
    make \
    g++ \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# pnpm
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# workspace config
COPY pnpm-workspace.yaml ./
COPY package.json pnpm-lock.yaml ./

# packages
COPY packages ./packages

# install dependencies
RUN pnpm install --frozen-lockfile

# build dependencies required by nocodb runtime
RUN pnpm --filter nocodb-sdk build
RUN pnpm --filter nocodb-sdk-v2 build
RUN pnpm --filter nc-gui build

# build nocodb backend bundle
RUN pnpm --filter nocodb build

# copy start script
RUN mkdir -p /usr/src/appEntry
RUN cp packages/nocodb/docker/start-litestream.sh /usr/src/appEntry/start.sh
RUN chmod +x /usr/src/appEntry/start.sh

# reduce node_modules size
RUN pnpm prune --prod


##########
# Runner
##########
FROM node:22-slim

WORKDIR /usr/src/app

ENV \
  LITESTREAM_S3_SKIP_VERIFY=false \
  LITESTREAM_RETENTION=1440h \
  LITESTREAM_RETENTION_CHECK_INTERVAL=72h \
  LITESTREAM_SNAPSHOT_INTERVAL=24h \
  LITESTREAM_SYNC_INTERVAL=60s \
  NC_DOCKER=0.6 \
  NC_TOOL_DIR=/usr/app/data/ \
  NODE_ENV=production \
  PORT=8080

RUN apt-get update && apt-get install -y \
    dumb-init \
    curl \
    wget \
    && curl -L "https://github.com/TomWright/dasel/releases/download/v2.8.1/dasel_linux_$(dpkg --print-architecture)" \
       -o /usr/local/bin/dasel \
    && chmod +x /usr/local/bin/dasel \
    && rm -rf /var/lib/apt/lists/*

# litestream
COPY --from=lt-builder /usr/local/bin/litestream /usr/local/bin/litestream
COPY packages/nocodb/docker/litestream.yml /etc/litestream.yml

# built application
COPY --from=builder /usr/src/app/packages/nocodb/docker /usr/src/app/docker
COPY --from=builder /usr/src/app/node_modules /usr/src/app/node_modules
COPY --from=builder /usr/src/app/packages/nocodb/package.json /usr/src/app/package.json

# startup script
COPY --from=builder /usr/src/appEntry /usr/src/appEntry

EXPOSE 8080

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["/usr/src/appEntry/start.sh"]

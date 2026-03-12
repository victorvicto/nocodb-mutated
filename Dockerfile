# ---------- litestream builder ----------
FROM golang:bullseye AS lt-builder

WORKDIR /usr/src

RUN apt-get update && apt-get install -y git make gcc libc-dev \
 && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/benbjohnson/litestream.git
RUN cd litestream && go install ./cmd/litestream
RUN cp $GOPATH/bin/litestream /usr/src/lt


# ---------- app builder ----------
FROM node:22-slim AS builder
WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y \
  python3 \
  python-is-python3 \
  make \
  g++ \
  git \
 && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

COPY . .

RUN pnpm install

# build frontend (nc-gui)
RUN pnpm --filter nc-gui build

# build backend bundle
RUN pnpm --filter nocodb build

# install production deps only
RUN pnpm install --prod


# ---------- runtime ----------
FROM node:22-slim

WORKDIR /usr/src/app

ENV NODE_ENV=production
ENV PORT=8080

RUN apt-get update && apt-get install -y dumb-init curl wget \
 && rm -rf /var/lib/apt/lists/*

# litestream
COPY --from=lt-builder /usr/src/lt /usr/local/bin/litestream

# compiled backend + runtime files
COPY --from=builder /usr/src/app/packages/nocodb /usr/src/app/packages/nocodb

# docker entry files
COPY docker /usr/src/app/docker

EXPOSE 8080

ENTRYPOINT ["/usr/bin/dumb-init","--"]

CMD ["node","docker/main"]

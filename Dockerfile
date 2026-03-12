FROM node:22-slim AS builder

WORKDIR /usr/src/app

# install build tools required by native deps
RUN apt-get update && apt-get install -y \
    python3 \
    python-is-python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# enable pnpm (same as upstream)
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

# copy full repository
COPY . .

# install dependencies for the workspace
RUN pnpm install

# build all workspace packages (frontend + backend)
RUN pnpm build

# -------- runtime image --------

FROM node:22-slim

WORKDIR /usr/src/app

ENV NODE_ENV=production
ENV PORT=8080

# copy built workspace
COPY --from=builder /usr/src/app /usr/src/app

EXPOSE 8080

CMD ["pnpm","--filter","nocodb","start"]

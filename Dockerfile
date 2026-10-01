# Local Tasks API image. Built by Jenkins with rootless Podman, scanned by Trivy,
# pushed to Docker Hub and run on the server by local-tasks.service.
# Base image pinned by digest; bump it deliberately (node:22-alpine).
ARG NODE_IMAGE=docker.io/library/node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402

FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

FROM ${NODE_IMAGE}
# The app does not need a package manager at runtime; removing them also removes
# the CVEs in npm's own bundled dependencies.
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-*
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json app.js ./
COPY public ./public
# node user from the base image
USER 1000:1000
EXPOSE 8083
CMD ["node", "app.js"]

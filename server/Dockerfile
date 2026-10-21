# The study server as a small production image: Node 24 LTS on Alpine,
# compiled JavaScript and runtime dependencies only, run as the unprivileged
# "node" user.
#
#   docker build -t tasikaso-study-server .
#   docker run -p 8787:8787 -e ANTHROPIC_API_KEY=sk-ant-... -e APP_TOKEN=... tasikaso-study-server

FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:24-alpine
ENV NODE_ENV=production \
    PORT=8787
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" > /dev/null || exit 1
CMD ["node", "dist/index.js"]

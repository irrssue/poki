FROM node:24.21.0-bookworm-slim AS build
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci
COPY backend/ ./
COPY supabase/migrations/ /app/supabase/migrations/
RUN npm run typecheck && npm test && npm prune --omit=dev

FROM node:24.21.0-bookworm-slim AS runtime
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3000 LOG_LEVEL=info
WORKDIR /app
COPY --from=build --chown=node:node /app/backend/package*.json ./
COPY --from=build --chown=node:node /app/backend/node_modules/ ./node_modules/
COPY --from=build --chown=node:node /app/backend/dist/src/ ./dist/src/
USER node
EXPOSE 3000
CMD ["node", "dist/src/server.js"]

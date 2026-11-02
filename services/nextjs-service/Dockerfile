FROM node:22-alpine AS builder

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json next.config.ts ./
COPY src ./src
COPY public ./public
RUN npm run build

FROM node:22-alpine

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
# Standalone tracing misses this dependency of the HTTP instrumentation.
COPY --from=builder /app/node_modules/forwarded-parse ./node_modules/forwarded-parse

USER appuser
EXPOSE 3002

ENV NODE_ENV=production
ENV PORT=3002
ENV HOSTNAME=0.0.0.0

CMD ["node", "server.js"]

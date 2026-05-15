# ── Stage 1: Build React/Vite ────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── Stage 2: Serve con Nginx (usuario no-root) ───────────────────────────────
FROM nginx:alpine

RUN apk add --no-cache gettext

# Copiar nginx.conf principal modificado para usar /tmp como pid y conf dir
COPY nginx-main.conf /etc/nginx/nginx.conf

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx \
    && chmod +x /docker-entrypoint.sh \
    && mkdir -p /tmp/nginx-conf \
    && chown -R nginx:nginx /tmp/nginx-conf

USER nginx

EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]

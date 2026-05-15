# ── Stage 1: Build React/Vite ────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── Stage 2: Serve con Nginx (usuario no-root, envsubst para IPs) ─────────────
FROM nginx:alpine

RUN apk add --no-cache gettext

# Puerto 8080 no requiere root
RUN mkdir -p /var/cache/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx /usr/share/nginx/html \
    && chmod -R 755 /etc/nginx/conf.d

COPY --from=builder /app/dist /usr/share/nginx/html

# Copiar la plantilla de nginx (con ${BACKEND_DESPACHOS} y ${BACKEND_VENTAS})
COPY nginx.conf /etc/nginx/conf.d/default.conf.template

# Entrypoint: sustituye variables y arranca nginx
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

USER nginx

EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]

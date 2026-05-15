# ── Stage 1: Build React/Vite ────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── Stage 2: Serve con Nginx ─────────────────────────────────────────────────
FROM nginx:alpine

RUN apk add --no-cache gettext

# Crea directorio para PID y ajusta permisos
RUN mkdir -p /var/cache/nginx /tmp/nginx \
    && chown -R nginx:nginx /var/cache/nginx /tmp/nginx

# Nginx PID en /tmp para no requerir root
RUN sed -i 's|pid\s*/var/run/nginx.pid|pid /tmp/nginx.pid|' /etc/nginx/nginx.conf

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

# Permisos necesarios para usuario nginx
RUN chmod +x /docker-entrypoint.sh \
    && chown -R nginx:nginx /usr/share/nginx/html \
    && chmod 777 /etc/nginx/conf.d

USER nginx

EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]

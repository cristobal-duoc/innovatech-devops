# ── Stage 1: Build React/Vite ────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ── Stage 2: Serve con Nginx (usuario no-root) ───────────────────────────────
FROM nginx:alpine

# Nginx escucha en 8080 para no requerir root (puerto < 1024 requiere CAP_NET_BIND)
RUN sed -i 's/listen\s*80;/listen 8080;/g' /etc/nginx/conf.d/default.conf

# Ajusta permisos para que el usuario 'nginx' pueda escribir en cache y PID
RUN mkdir -p /var/cache/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx /usr/share/nginx/html

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER nginx

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]

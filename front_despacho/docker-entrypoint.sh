#!/bin/sh
set -e
# Sustituye IPs de backend en plantilla nginx y arranca
envsubst '${BACKEND_DESPACHOS} ${BACKEND_VENTAS}' \
  < /etc/nginx/conf.d/default.conf.template \
  > /etc/nginx/conf.d/default.conf
exec nginx -g "daemon off;"

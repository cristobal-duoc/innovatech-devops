#!/bin/sh
set -e
# Sustituye IPs de backend y escribe en /tmp (siempre escribible)
envsubst '${BACKEND_DESPACHOS} ${BACKEND_VENTAS}' \
  < /etc/nginx/conf.d/default.conf.template \
  > /tmp/nginx-conf/default.conf
exec nginx -g "daemon off;"

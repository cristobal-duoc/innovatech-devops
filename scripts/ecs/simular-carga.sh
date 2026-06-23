#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# simular-carga.sh — Genera carga sobre el ALB para disparar el autoscaling (IE3)
#
# Lanza peticiones concurrentes durante N segundos. Mientras corre, observa en
# la consola ECS → servicio → pestaña "Health and metrics" cómo sube la CPU y el
# desiredCount pasa de 1 a 2/3/4 tareas. Captura ese momento como evidencia.
#
# Uso:  bash scripts/ecs/simular-carga.sh [segundos] [concurrencia]
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

DURACION="${1:-300}"
CONCURRENCIA="${2:-50}"

ALB_DNS="$(aws elbv2 describe-load-balancers --names innovatech-alb \
  --query "LoadBalancers[0].DNSName" --output text)"
URL="http://$ALB_DNS/"

echo "==> Generando carga sobre $URL"
echo "    duración=${DURACION}s  concurrencia=${CONCURRENCIA}"
echo "    (Ctrl+C para detener)"

FIN=$(( $(date +%s) + DURACION ))
worker () { while [ "$(date +%s)" -lt "$FIN" ]; do curl -s -o /dev/null "$URL" || true; done; }

for i in $(seq 1 "$CONCURRENCIA"); do worker & done
wait
echo "==> Carga finalizada."

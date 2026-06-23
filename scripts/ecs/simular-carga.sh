#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# simular-carga.sh — Genera carga sobre el ALB para disparar el autoscaling (IE3)
# Mientras corre, observa en ECS → servicio → Health and metrics cómo sube la CPU
# y el desiredCount pasa de 1 a 2/3/4.
#   Uso:  bash scripts/ecs/simular-carga.sh [segundos] [concurrencia]
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail
DUR="${1:-300}"; CONC="${2:-50}"
ALB=$(aws elbv2 describe-load-balancers --names innovatech-alb-pub --query "LoadBalancers[0].DNSName" --output text)
URL="http://$ALB/"
echo "==> Carga sobre $URL  (dur=${DUR}s conc=${CONC})  Ctrl+C para detener"
FIN=$(( $(date +%s) + DUR ))
w(){ while [ "$(date +%s)" -lt "$FIN" ]; do curl -s -o /dev/null "$URL" || true; done; }
for i in $(seq 1 "$CONC"); do w & done
wait
echo "==> Carga finalizada."

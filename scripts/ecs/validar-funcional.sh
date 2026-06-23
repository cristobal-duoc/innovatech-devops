#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# validar-funcional.sh — Validación funcional del clúster Front → Back  (IE7)
#
# Comprueba:  estado de los servicios ECS, salud del target group, respuesta del
# frontend por el ALB y respuesta de los backends a través del proxy nginx.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

echo "==> 1. Estado de los servicios ECS"
aws ecs describe-services --cluster "$CLUSTER_NAME" \
  --services "$SVC_FRONTEND" "$SVC_VENTAS" "$SVC_DESPACHOS" "$SVC_DB" \
  --query "services[].{Servicio:serviceName,Estado:status,Deseadas:desiredCount,Activas:runningCount}" \
  --output table

echo "==> 2. Salud del Target Group (frontend)"
TG_ARN="$(aws elbv2 describe-target-groups --names innovatech-frontend-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text)"
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{Target:Target.Id,Estado:TargetHealth.State}" \
  --output table

ALB_DNS="$(aws elbv2 describe-load-balancers --names innovatech-alb \
  --query "LoadBalancers[0].DNSName" --output text)"
BASE="http://$ALB_DNS"

echo "==> 3. Frontend por el ALB ($BASE)"
curl -s -o /dev/null -w "    HTTP %{http_code}  (%{time_total}s)\n" "$BASE/"

echo "==> 4. Comunicación Front → Back (proxy nginx)"
echo -n "    /api/ventas/   -> "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/ventas/"
echo -n "    /api/despachos/-> "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/api/despachos/"

echo "==> Validación finalizada (revisa que los códigos sean 2xx/3xx/4xx esperados, no 5xx/timeout)."

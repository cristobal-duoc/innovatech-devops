#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# validar-funcional.sh — Validación funcional del clúster Front → Back  (IE7)
# Comprueba estado de servicios, salud de targets y respuesta Front→Back por el ALB.
#   Uso:  bash scripts/ecs/validar-funcional.sh
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail
CLUSTER=innovatech-cluster

echo "==> 1. Servicios ECS"
aws ecs describe-services --cluster "$CLUSTER" \
  --services innovatech-frontend innovatech-ventas innovatech-despachos \
  --query "services[].{Servicio:serviceName,Estado:status,Deseadas:desiredCount,Corriendo:runningCount}" --output table

echo "==> 2. Salud de target groups"
for tg in innovatech-front-tg innovatech-ventas-tg innovatech-despachos-tg; do
  ARN=$(aws elbv2 describe-target-groups --names "$tg" --query "TargetGroups[0].TargetGroupArn" --output text)
  H=$(aws elbv2 describe-target-health --target-group-arn "$ARN" --query "TargetHealthDescriptions[?TargetHealth.State=='healthy']|length(@)" --output text)
  echo "    $tg: $H target(s) healthy"
done

ALB=$(aws elbv2 describe-load-balancers --names innovatech-alb-pub --query "LoadBalancers[0].DNSName" --output text)
B="http://$ALB"
echo "==> 3. Frontend por el ALB ($B)"
curl -s -o /dev/null -w "    HTTP %{http_code} (%{time_total}s)\n" "$B/"
echo "==> 4. Comunicación Front → Back"
echo -n "    /api/ventas/v3/api-docs    -> "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$B/api/ventas/v3/api-docs"
echo -n "    /api/despachos/v3/api-docs -> "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$B/api/despachos/v3/api-docs"
echo "==> Validación finalizada (se esperan 200)."

#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# destruir-todo.sh — Limpieza para no consumir el crédito del Learner Lab.
# Borra servicios, ALB, target group, namespace y clúster. (La red EP1 se mantiene.)
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

echo "==> Bajando servicios ECS a 0 y eliminándolos..."
for svc in "$SVC_FRONTEND" "$SVC_VENTAS" "$SVC_DESPACHOS" "$SVC_DB"; do
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$svc" --desired-count 0 >/dev/null 2>&1 || true
  aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$svc" --force >/dev/null 2>&1 || true
done

echo "==> Eliminando ALB, listener y target group..."
ALB_ARN="$(aws elbv2 describe-load-balancers --names innovatech-alb --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)"
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  for l in $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query "Listeners[].ListenerArn" --output text); do
    aws elbv2 delete-listener --listener-arn "$l" >/dev/null 2>&1 || true
  done
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" >/dev/null 2>&1 || true
  sleep 15
fi
TG_ARN="$(aws elbv2 describe-target-groups --names innovatech-frontend-tg --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)"
[ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG_ARN" >/dev/null 2>&1 || true

echo "==> Eliminando servicios Cloud Map y namespace..."
NS_ID="$(aws servicediscovery list-namespaces --query "Namespaces[?Name=='${NAMESPACE_NAME}'].Id" --output text)"
for name in db backend-ventas backend-despachos; do
  SID="$(aws servicediscovery list-services --query "Services[?Name=='$name'].Id" --output text)"
  [ -n "$SID" ] && [ "$SID" != "None" ] && aws servicediscovery delete-service --id "$SID" >/dev/null 2>&1 || true
done
[ -n "$NS_ID" ] && [ "$NS_ID" != "None" ] && aws servicediscovery delete-namespace --id "$NS_ID" >/dev/null 2>&1 || true

echo "==> Eliminando clúster ECS..."
aws ecs delete-cluster --cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true

echo "✅ Recursos EP3 eliminados (la red e imágenes ECR se conservan)."

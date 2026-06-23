#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# destruir-learnerlab.sh — Limpieza de los recursos EP3 realmente desplegados
# (arquitectura Learner Lab: ALB interno + RDS, sin Cloud Map).
# Ejecutar al terminar de capturar evidencias para no gastar el crédito del lab.
#   Uso:  MSYS_NO_PATHCONV=1 bash scripts/ecs/destruir-learnerlab.sh
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail
export MSYS_NO_PATHCONV=1
CL=innovatech-cluster
REGION=us-east-1

echo "==> 1. Eliminando servicios ECS..."
for svc in innovatech-frontend innovatech-ventas innovatech-despachos; do
  aws ecs update-service --cluster $CL --service $svc --desired-count 0 >/dev/null 2>&1
  aws ecs delete-service --cluster $CL --service $svc --force >/dev/null 2>&1 && echo "   $svc borrado"
done

echo "==> 2. Eliminando ALB (público + interno), listeners y target groups..."
for alb in innovatech-alb-pub innovatech-alb-int; do
  ARN=$(aws elbv2 describe-load-balancers --names $alb --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
  if [ -n "$ARN" ] && [ "$ARN" != "None" ]; then
    for L in $(aws elbv2 describe-listeners --load-balancer-arn "$ARN" --query "Listeners[].ListenerArn" --output text); do
      aws elbv2 delete-listener --listener-arn "$L" >/dev/null 2>&1
    done
    aws elbv2 delete-load-balancer --load-balancer-arn "$ARN" >/dev/null 2>&1 && echo "   $alb borrado"
  fi
done
sleep 20
for tg in innovatech-front-tg innovatech-ventas-tg innovatech-despachos-tg; do
  ARN=$(aws elbv2 describe-target-groups --names $tg --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
  [ -n "$ARN" ] && [ "$ARN" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$ARN" >/dev/null 2>&1 && echo "   $tg borrado"
done

echo "==> 3. Eliminando RDS (sin snapshot)..."
aws rds delete-db-instance --db-instance-identifier innovatech-mysql \
  --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 && echo "   RDS en eliminación"
aws rds delete-db-subnet-group --db-subnet-group-name innovatech-dbsubnet >/dev/null 2>&1 || true

echo "==> 4. Eliminando clúster ECS..."
aws ecs delete-cluster --cluster $CL >/dev/null 2>&1 && echo "   clúster borrado"

echo "==> 5. (Opcional) Security Groups — se borran cuando se liberen las ENIs:"
echo "   innovatech-albpub-sg / albint-sg / front-sg / back-sg / db-sg"
echo
echo "NOTA: la red (VPC red-lab), el secret y los repos ECR NO se borran (reutilizables)."
echo "✅ Limpieza de cómputo y BD lanzada."

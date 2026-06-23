#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 03-crear-alb.sh — Security Groups + Application Load Balancer  (IE1 / IE2)
#
# Modelo de seguridad por capas:
#   sg-alb       :  80   desde Internet
#   sg-frontend  :  8080 desde sg-alb
#   sg-backend   :  8080 y 8081 desde sg-frontend (Front → Back)
#   sg-db        :  3306 desde sg-backend
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

# ── Helper: crea SG si no existe y devuelve su ID ─────────────────────────────
ensure_sg () {
  local name="$1" desc="$2" id
  id="$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$name" "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)"
  if [ -z "$id" ] || [ "$id" == "None" ]; then
    id="$(aws ec2 create-security-group --group-name "$name" \
      --description "$desc" --vpc-id "$VPC_ID" \
      --query "GroupId" --output text)"
    aws ec2 create-tags --resources "$id" --tags Key=Name,Value="$name" >/dev/null
  fi
  echo "$id"
}

authorize () {  # idempotente: ignora "ya existe"
  aws ec2 authorize-security-group-ingress "$@" >/dev/null 2>&1 || true
}

echo "==> Security Groups..."
SG_ALB="$(ensure_sg innovatech-alb-sg     "ALB publico Innovatech")"
SG_FRONT="$(ensure_sg innovatech-front-sg "Tareas frontend")"
SG_BACK="$(ensure_sg innovatech-back-sg   "Tareas backend")"
SG_DB="$(ensure_sg innovatech-db-sg       "Tarea MySQL")"

authorize --group-id "$SG_ALB"   --protocol tcp --port 80   --cidr 0.0.0.0/0
authorize --group-id "$SG_FRONT" --protocol tcp --port 8080 --source-group "$SG_ALB"
authorize --group-id "$SG_BACK"  --protocol tcp --port 8080 --source-group "$SG_FRONT"
authorize --group-id "$SG_BACK"  --protocol tcp --port 8081 --source-group "$SG_FRONT"
authorize --group-id "$SG_DB"    --protocol tcp --port 3306 --source-group "$SG_BACK"

echo "    sg-alb=$SG_ALB sg-front=$SG_FRONT sg-back=$SG_BACK sg-db=$SG_DB"

# ── Application Load Balancer (subredes públicas) ─────────────────────────────
echo "==> Application Load Balancer..."
ALB_ARN="$(aws elbv2 describe-load-balancers --names innovatech-alb \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)"

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
  ALB_ARN="$(aws elbv2 create-load-balancer \
    --name innovatech-alb \
    --type application --scheme internet-facing \
    --subnets "$PUB_A" "$PUB_B" \
    --security-groups "$SG_ALB" \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)"
fi

# ── Target Group del frontend (target-type ip → Fargate awsvpc) ───────────────
TG_ARN="$(aws elbv2 describe-target-groups --names innovatech-frontend-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)"

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
  TG_ARN="$(aws elbv2 create-target-group \
    --name innovatech-frontend-tg \
    --protocol HTTP --port 8080 --target-type ip \
    --vpc-id "$VPC_ID" \
    --health-check-path "/" --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
    --query "TargetGroups[0].TargetGroupArn" --output text)"
fi

# ── Listener :80 → Target Group ───────────────────────────────────────────────
LISTENER_ARN="$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`80\`].ListenerArn | [0]" --output text 2>/dev/null || true)"

if [ -z "$LISTENER_ARN" ] || [ "$LISTENER_ARN" == "None" ]; then
  aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
fi

ALB_DNS="$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" --output text)"

echo "──────────────────────────────────────────────"
echo " ALB DNS (URL pública del Frontend):"
echo "   http://$ALB_DNS"
echo "──────────────────────────────────────────────"

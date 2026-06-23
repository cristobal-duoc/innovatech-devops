#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# desplegar-learnerlab.sh — Despliegue completo EP3 en AWS Academy Learner Lab
#
# Arquitectura (adaptada al Learner Lab, que BLOQUEA AWS Cloud Map):
#   Internet → ALB público → ECS frontend (nginx)
#            → ALB interno (:8080 ventas, :8081 despachos) → ECS ventas/despachos
#            → RDS MySQL
#
# El descubrimiento Front→Back se hace por el ALB interno (no Cloud Map) y la BD
# es RDS. No requiere modificar las imágenes: el nginx del frontend resuelve los
# backends por el DNS del ALB interno (inyectado como variable de entorno).
#
# Requisitos:  AWS CloudShell (aws, jq, envsubst, bash) y la red de EP1 creada
#              (scripts/crear-red-lab.sh). Imágenes ya en ECR (manual o por CI/CD).
#   Uso:  bash scripts/ecs/desplegar-learnerlab.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

export AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT="red-lab"
CLUSTER="innovatech-cluster"
SECRET_NAME="innovatech/db"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Credenciales de BD (cámbialas en un entorno real)
DB_NAME="${DB_NAME:-innovatech}"
DB_USERNAME="${DB_USERNAME:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-AppPass2026}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-AppPass2026}"

echo "### 0. Descubriendo red de EP1 (VPC ${PROJECT}) ###"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-vpc" --query "Vpcs[0].VpcId" --output text)
[ "$VPC_ID" = "None" ] && { echo "ERROR: ejecuta antes scripts/crear-red-lab.sh"; exit 1; }
sn(){ aws ec2 describe-subnets --filters "Name=tag:Name,Values=$1" --query "Subnets[0].SubnetId" --output text; }
PUB_A=$(sn "${PROJECT}-public-a"); PUB_B=$(sn "${PROJECT}-public-b")
APP_A=$(sn "${PROJECT}-app-a");    APP_B=$(sn "${PROJECT}-app-b")
DATA_A=$(sn "${PROJECT}-data-a");  DATA_B=$(sn "${PROJECT}-data-b")
echo "VPC=$VPC_ID  pub=$PUB_A,$PUB_B  app=$APP_A,$APP_B  data=$DATA_A,$DATA_B"

echo "### 1. Service-linked roles (idempotente) ###"
for s in ecs.amazonaws.com ecs.application-autoscaling.amazonaws.com; do
  aws iam create-service-linked-role --aws-service-name "$s" >/dev/null 2>&1 || true
done

echo "### 2. Secret de BD en Secrets Manager ###"
SECRET_JSON="{\"DB_NAME\":\"$DB_NAME\",\"DB_USERNAME\":\"$DB_USERNAME\",\"DB_PASSWORD\":\"$DB_PASSWORD\",\"DB_ROOT_PASSWORD\":\"$DB_ROOT_PASSWORD\"}"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --secret-id "$SECRET_NAME" --secret-string "$SECRET_JSON" >/dev/null
else
  aws secretsmanager create-secret --name "$SECRET_NAME" --description "Credenciales BD Innovatech (EP3)" --secret-string "$SECRET_JSON" >/dev/null
fi
export SECRET_DB_ARN="$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --query ARN --output text)"

echo "### 3. Log groups + clúster ECS ###"
for lg in /ecs/innovatech-frontend /ecs/innovatech-ventas /ecs/innovatech-despachos; do
  aws logs create-log-group --log-group-name "$lg" 2>/dev/null && aws logs put-retention-policy --log-group-name "$lg" --retention-in-days 7 || true
done
aws ecs create-cluster --cluster-name "$CLUSTER" --capacity-providers FARGATE FARGATE_SPOT \
  --settings name=containerInsights,value=enabled >/dev/null

echo "### 4. Security Groups (alb-pub → front → alb-int → back → db) ###"
mksg(){ local id; id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
  if [ -z "$id" ] || [ "$id" = "None" ]; then id=$(aws ec2 create-security-group --group-name "$1" --description "$2" --vpc-id "$VPC_ID" --query GroupId --output text); aws ec2 create-tags --resources "$id" --tags Key=Name,Value="$1" >/dev/null; fi; echo "$id"; }
auth(){ aws ec2 authorize-security-group-ingress "$@" >/dev/null 2>&1 || true; }
SG_ALBPUB=$(mksg innovatech-albpub-sg "ALB publico");  SG_ALBINT=$(mksg innovatech-albint-sg "ALB interno")
SG_FRONT=$(mksg innovatech-front-sg "Frontend");       SG_BACK=$(mksg innovatech-back-sg "Backends")
SG_DB=$(mksg innovatech-db-sg "RDS")
auth --group-id "$SG_ALBPUB" --protocol tcp --port 80   --cidr 0.0.0.0/0
auth --group-id "$SG_FRONT"  --protocol tcp --port 8080 --source-group "$SG_ALBPUB"
auth --group-id "$SG_ALBINT" --protocol tcp --port 8080 --source-group "$SG_FRONT"
auth --group-id "$SG_ALBINT" --protocol tcp --port 8081 --source-group "$SG_FRONT"
auth --group-id "$SG_BACK"   --protocol tcp --port 8080 --source-group "$SG_ALBINT"
auth --group-id "$SG_BACK"   --protocol tcp --port 8081 --source-group "$SG_ALBINT"
auth --group-id "$SG_DB"     --protocol tcp --port 3306 --source-group "$SG_BACK"

echo "### 5. RDS MySQL (espera a 'available') ###"
aws rds create-db-subnet-group --db-subnet-group-name innovatech-dbsubnet \
  --db-subnet-group-description "Innovatech RDS" --subnet-ids "$DATA_A" "$DATA_B" >/dev/null 2>&1 || true
if ! aws rds describe-db-instances --db-instance-identifier innovatech-mysql >/dev/null 2>&1; then
  aws rds create-db-instance --db-instance-identifier innovatech-mysql \
    --engine mysql --engine-version 8.0 --db-instance-class db.t3.micro --allocated-storage 20 \
    --master-username "$DB_USERNAME" --master-user-password "$DB_PASSWORD" --db-name "$DB_NAME" \
    --vpc-security-group-ids "$SG_DB" --db-subnet-group-name innovatech-dbsubnet \
    --no-publicly-accessible --backup-retention-period 0 --no-multi-az >/dev/null
fi
echo "Esperando RDS..."; aws rds wait db-instance-available --db-instance-identifier innovatech-mysql
export RDS_ENDPOINT="$(aws rds describe-db-instances --db-instance-identifier innovatech-mysql --query "DBInstances[0].Endpoint.Address" --output text)"
echo "RDS endpoint: $RDS_ENDPOINT"

echo "### 6. ALB público (frontend) ###"
alb(){ aws elbv2 describe-load-balancers --names "$1" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null; }
tg(){ aws elbv2 describe-target-groups --names "$1" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null; }
ALB_PUB=$(alb innovatech-alb-pub); [ -z "$ALB_PUB" -o "$ALB_PUB" = "None" ] && ALB_PUB=$(aws elbv2 create-load-balancer --name innovatech-alb-pub --type application --scheme internet-facing --subnets "$PUB_A" "$PUB_B" --security-groups "$SG_ALBPUB" --query "LoadBalancers[0].LoadBalancerArn" --output text)
TG_FRONT=$(tg innovatech-front-tg); [ -z "$TG_FRONT" -o "$TG_FRONT" = "None" ] && TG_FRONT=$(aws elbv2 create-target-group --name innovatech-front-tg --protocol HTTP --port 8080 --target-type ip --vpc-id "$VPC_ID" --matcher HttpCode=200-399 --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 describe-listeners --load-balancer-arn "$ALB_PUB" --query "Listeners[?Port==\`80\`]" --output text | grep -q . || aws elbv2 create-listener --load-balancer-arn "$ALB_PUB" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="$TG_FRONT" >/dev/null

echo "### 7. ALB interno (backends, descubrimiento Front→Back) ###"
ALB_INT=$(alb innovatech-alb-int); [ -z "$ALB_INT" -o "$ALB_INT" = "None" ] && ALB_INT=$(aws elbv2 create-load-balancer --name innovatech-alb-int --type application --scheme internal --subnets "$APP_A" "$APP_B" --security-groups "$SG_ALBINT" --query "LoadBalancers[0].LoadBalancerArn" --output text)
TG_VENTAS=$(tg innovatech-ventas-tg); [ -z "$TG_VENTAS" -o "$TG_VENTAS" = "None" ] && TG_VENTAS=$(aws elbv2 create-target-group --name innovatech-ventas-tg --protocol HTTP --port 8080 --target-type ip --vpc-id "$VPC_ID" --matcher HttpCode=200-499 --query "TargetGroups[0].TargetGroupArn" --output text)
TG_DESP=$(tg innovatech-despachos-tg); [ -z "$TG_DESP" -o "$TG_DESP" = "None" ] && TG_DESP=$(aws elbv2 create-target-group --name innovatech-despachos-tg --protocol HTTP --port 8081 --target-type ip --vpc-id "$VPC_ID" --matcher HttpCode=200-499 --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 describe-listeners --load-balancer-arn "$ALB_INT" --query "Listeners[?Port==\`8080\`]" --output text | grep -q . || aws elbv2 create-listener --load-balancer-arn "$ALB_INT" --protocol HTTP --port 8080 --default-actions Type=forward,TargetGroupArn="$TG_VENTAS" >/dev/null
aws elbv2 describe-listeners --load-balancer-arn "$ALB_INT" --query "Listeners[?Port==\`8081\`]" --output text | grep -q . || aws elbv2 create-listener --load-balancer-arn "$ALB_INT" --protocol HTTP --port 8081 --default-actions Type=forward,TargetGroupArn="$TG_DESP" >/dev/null
export ALB_INT_DNS="$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_INT" --query "LoadBalancers[0].DNSName" --output text)"

echo "### 8. Task definitions (envsubst) + ECR ###"
export ECR_REPO_FRONTEND="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/innovatech-frontend"
export ECR_REPO_VENTAS="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/innovatech-ventas"
export ECR_REPO_DESPACHOS="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/innovatech-despachos"
reg(){ envsubst < "$ROOT/ecs/task-def-$1.json" > /tmp/td-$1.json; aws ecs register-task-definition --cli-input-json file:///tmp/td-$1.json >/dev/null; }
reg frontend; reg ventas; reg despachos

echo "### 9. Servicios ECS (con registro en target groups) ###"
NETF="awsvpcConfiguration={subnets=[$APP_A,$APP_B],securityGroups=[$SG_FRONT],assignPublicIp=DISABLED}"
NETB="awsvpcConfiguration={subnets=[$APP_A,$APP_B],securityGroups=[$SG_BACK],assignPublicIp=DISABLED}"
svc_exists(){ [ "$(aws ecs describe-services --cluster "$CLUSTER" --services "$1" --query "services[0].status" --output text 2>/dev/null)" = "ACTIVE" ]; }
mk_svc(){ # nombre taskdef net tg container puerto grace
  if svc_exists "$1"; then aws ecs update-service --cluster "$CLUSTER" --service "$1" --task-definition "$2" >/dev/null
  else aws ecs create-service --cluster "$CLUSTER" --service-name "$1" --task-definition "$2" --desired-count 1 --launch-type FARGATE \
    --network-configuration "$3" --load-balancers "targetGroupArn=$4,containerName=$5,containerPort=$6" --health-check-grace-period-seconds "$7" >/dev/null; fi; }
mk_svc innovatech-frontend  innovatech-frontend  "$NETF" "$TG_FRONT"  frontend  8080 120
mk_svc innovatech-ventas    innovatech-ventas    "$NETB" "$TG_VENTAS" ventas    8080 180
mk_svc innovatech-despachos innovatech-despachos "$NETB" "$TG_DESP"   despachos 8081 180

echo "### 10. Autoscaling (Target Tracking CPU 50%, 1→4) ###"
for svc in innovatech-frontend innovatech-ventas innovatech-despachos; do
  aws application-autoscaling register-scalable-target --service-namespace ecs --resource-id "service/$CLUSTER/$svc" --scalable-dimension ecs:service:DesiredCount --min-capacity 1 --max-capacity 4 >/dev/null
  aws application-autoscaling put-scaling-policy --service-namespace ecs --resource-id "service/$CLUSTER/$svc" --scalable-dimension ecs:service:DesiredCount --policy-name "$svc-cpu-tt" --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{"TargetValue":50.0,"PredefinedMetricSpecification":{"PredefinedMetricType":"ECSServiceAverageCPUUtilization"},"ScaleInCooldown":300,"ScaleOutCooldown":60}' >/dev/null
done

ALB_PUB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_PUB" --query "LoadBalancers[0].DNSName" --output text)
echo "──────────────────────────────────────────────"
echo " ✅ Despliegue EP3 completado."
echo "    URL pública del Frontend:  http://$ALB_PUB_DNS"
echo "──────────────────────────────────────────────"

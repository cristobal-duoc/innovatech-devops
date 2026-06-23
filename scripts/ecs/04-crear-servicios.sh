#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 04-crear-servicios.sh — Registra task definitions y crea los servicios ECS (IE2)
#
#  · Descubrimiento interno (Front→Back→DB) vía AWS Cloud Map:
#       db.innovatech.local / backend-ventas.innovatech.local / backend-despachos...
#  · Frontend expuesto por el ALB (target group del paso 03).
#  · Las task definitions salen de las plantillas ecs/*.json (envsubst).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
source "$DIR/00-variables.sh"

# ── Datos derivados que necesitan las task definitions / servicios ────────────
export SECRET_DB_ARN="$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" \
  --query "ARN" --output text)"

NS_ID="$(aws servicediscovery list-namespaces \
  --query "Namespaces[?Name=='${NAMESPACE_NAME}'].Id" --output text)"

sg_id () { aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text; }
SG_FRONT="$(sg_id innovatech-front-sg)"
SG_BACK="$(sg_id innovatech-back-sg)"
SG_DB="$(sg_id innovatech-db-sg)"

TG_ARN="$(aws elbv2 describe-target-groups --names innovatech-frontend-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text)"

# ── Helper: registra una task definition a partir de su plantilla ─────────────
register_taskdef () {  # $1 = ruta plantilla json
  envsubst < "$1" > /tmp/td.json
  aws ecs register-task-definition --cli-input-json file:///tmp/td.json \
    --query "taskDefinition.taskDefinitionArn" --output text
}

# ── Helper: crea un servicio Cloud Map (registro DNS A) y devuelve su ARN ──────
cloudmap_service () {  # $1 = nombre dns (ej. backend-ventas)
  local name="$1" arn
  arn="$(aws servicediscovery list-services \
    --query "Services[?Name=='$name'].Arn" --output text)"
  if [ -z "$arn" ] || [ "$arn" == "None" ]; then
    arn="$(aws servicediscovery create-service \
      --name "$name" \
      --namespace-id "$NS_ID" \
      --dns-config "NamespaceId=$NS_ID,DnsRecords=[{Type=A,TTL=10}],RoutingPolicy=MULTIVALUE" \
      --health-check-custom-config FailureThreshold=1 \
      --query "Service.Arn" --output text)"
  fi
  echo "$arn"
}

# ── Helper: crea (o salta si ya existe) un servicio ECS ───────────────────────
ecs_service_exists () {
  local s; s="$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$1" \
    --query "services[0].status" --output text 2>/dev/null || true)"
  [ "$s" == "ACTIVE" ]
}

NETCFG_BACK="awsvpcConfiguration={subnets=[$APP_A,$APP_B],securityGroups=[$SG_BACK],assignPublicIp=DISABLED}"
NETCFG_DB="awsvpcConfiguration={subnets=[$APP_A,$APP_B],securityGroups=[$SG_DB],assignPublicIp=DISABLED}"
NETCFG_FRONT="awsvpcConfiguration={subnets=[$APP_A,$APP_B],securityGroups=[$SG_FRONT],assignPublicIp=DISABLED}"

echo "==> Registrando task definitions..."
TD_DB="$(register_taskdef "$ROOT/ecs/task-def-db.json")"
TD_VENTAS="$(register_taskdef "$ROOT/ecs/task-def-ventas.json")"
TD_DESPACHOS="$(register_taskdef "$ROOT/ecs/task-def-despachos.json")"
TD_FRONT="$(register_taskdef "$ROOT/ecs/task-def-frontend.json")"

echo "==> Servicios Cloud Map (DNS interno)..."
CM_DB="$(cloudmap_service db)"
CM_VENTAS="$(cloudmap_service backend-ventas)"
CM_DESPACHOS="$(cloudmap_service backend-despachos)"

# ── DB ────────────────────────────────────────────────────────────────────────
if ecs_service_exists "$SVC_DB"; then
  echo "==> Actualizando $SVC_DB"
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SVC_DB" \
    --task-definition "$TD_DB" >/dev/null
else
  echo "==> Creando $SVC_DB"
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SVC_DB" \
    --task-definition "$TD_DB" --desired-count 1 --launch-type FARGATE \
    --network-configuration "$NETCFG_DB" \
    --service-registries "registryArn=$CM_DB" >/dev/null
fi

# ── Backend Ventas ─────────────────────────────────────────────────────────────
if ecs_service_exists "$SVC_VENTAS"; then
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SVC_VENTAS" \
    --task-definition "$TD_VENTAS" >/dev/null
else
  echo "==> Creando $SVC_VENTAS"
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SVC_VENTAS" \
    --task-definition "$TD_VENTAS" --desired-count 1 --launch-type FARGATE \
    --network-configuration "$NETCFG_BACK" \
    --service-registries "registryArn=$CM_VENTAS" >/dev/null
fi

# ── Backend Despachos ──────────────────────────────────────────────────────────
if ecs_service_exists "$SVC_DESPACHOS"; then
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SVC_DESPACHOS" \
    --task-definition "$TD_DESPACHOS" >/dev/null
else
  echo "==> Creando $SVC_DESPACHOS"
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SVC_DESPACHOS" \
    --task-definition "$TD_DESPACHOS" --desired-count 1 --launch-type FARGATE \
    --network-configuration "$NETCFG_BACK" \
    --service-registries "registryArn=$CM_DESPACHOS" >/dev/null
fi

# ── Frontend (detrás del ALB) ──────────────────────────────────────────────────
if ecs_service_exists "$SVC_FRONTEND"; then
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SVC_FRONTEND" \
    --task-definition "$TD_FRONT" >/dev/null
else
  echo "==> Creando $SVC_FRONTEND"
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SVC_FRONTEND" \
    --task-definition "$TD_FRONT" --desired-count 1 --launch-type FARGATE \
    --network-configuration "$NETCFG_FRONT" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=frontend,containerPort=8080" \
    --health-check-grace-period-seconds 60 >/dev/null
fi

echo "==> Servicios desplegados. Estado:"
aws ecs describe-services --cluster "$CLUSTER_NAME" \
  --services "$SVC_FRONTEND" "$SVC_VENTAS" "$SVC_DESPACHOS" "$SVC_DB" \
  --query "services[].{Servicio:serviceName,Deseadas:desiredCount,Activas:runningCount}" \
  --output table

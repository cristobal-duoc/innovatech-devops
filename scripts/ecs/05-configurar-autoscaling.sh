#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 05-configurar-autoscaling.sh — ECS Service Auto Scaling (Target Tracking)  (IE3)
#
# Política Target Tracking sobre CPU promedio = 50 %.
# Justificación del umbral: 50 % deja margen para absorber picos de tráfico antes
# de saturar (escala "hacia arriba" pronto) sin sobre-aprovisionar en reposo
# (cooldown de salida de 5 min evita oscilaciones). Rango 1→4 tareas por servicio.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

CPU_TARGET="${CPU_TARGET:-50}"
MIN="${MIN:-1}"
MAX="${MAX:-4}"

configurar () {  # $1 = nombre del servicio ECS
  local svc="$1"
  local resource="service/$CLUSTER_NAME/$svc"

  echo "==> Registrando scalable target para $svc (min=$MIN max=$MAX)..."
  aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "$resource" \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity "$MIN" --max-capacity "$MAX"

  echo "==> Política Target Tracking CPU ${CPU_TARGET}% para $svc..."
  aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id "$resource" \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name "${svc}-cpu-tt" \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration "$(cat <<JSON
{
  "TargetValue": ${CPU_TARGET}.0,
  "PredefinedMetricSpecification": { "PredefinedMetricType": "ECSServiceAverageCPUUtilization" },
  "ScaleInCooldown": 300,
  "ScaleOutCooldown": 60
}
JSON
)" >/dev/null
}

# Se escalan los servicios con carga variable. La BD no se autoescala.
configurar "$SVC_FRONTEND"
configurar "$SVC_VENTAS"
configurar "$SVC_DESPACHOS"

echo "==> Autoscaling configurado. Políticas registradas:"
aws application-autoscaling describe-scaling-policies --service-namespace ecs \
  --query "ScalingPolicies[].{Recurso:ResourceId,Politica:PolicyName}" --output table

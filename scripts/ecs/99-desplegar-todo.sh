#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 99-desplegar-todo.sh — Orquestador maestro: levanta TODO el entorno EP3.
#
#   Requisitos previos:
#     · Red EP1 creada  → scripts/crear-red-lab.sh
#     · Imágenes en ECR → push manual o vía workflows CI/CD
#     · AWS CLI autenticado (credenciales del Learner Lab activas)
#
#   Uso:   bash scripts/ecs/99-desplegar-todo.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "##### 1/5  Secrets Manager #############################"; bash "$DIR/01-crear-secrets.sh"
echo "##### 2/5  Clúster ECS + Cloud Map + Logs ##############"; bash "$DIR/02-crear-cluster.sh"
echo "##### 3/5  Security Groups + ALB #######################"; bash "$DIR/03-crear-alb.sh"
echo "##### 4/5  Task Definitions + Servicios ################"; bash "$DIR/04-crear-servicios.sh"
echo "##### 5/5  Autoscaling #################################"; bash "$DIR/05-configurar-autoscaling.sh"

echo
echo "✅ Despliegue EP3 completado."
echo "   URL pública del Frontend (ALB):"
aws elbv2 describe-load-balancers --names innovatech-alb \
  --query "LoadBalancers[0].DNSName" --output text | sed 's%^%   http://%'

#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 00-variables.sh — Configuración central y descubrimiento de la red EP1
#
# Este archivo NO se ejecuta solo: lo cargan (source) los demás scripts.
# Reutiliza la VPC/subredes creadas en EP1 (scripts/crear-red-lab.sh) buscándolas
# por su tag Name, de modo que EP3 se monta encima de la infraestructura existente.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Parámetros generales ──────────────────────────────────────────────────────
export AWS_REGION="${AWS_REGION:-us-east-1}"
export PROJECT="red-lab"                  # mismo prefijo de tags que en EP1
export CLUSTER_NAME="innovatech-cluster"
export NAMESPACE_NAME="innovatech.local"  # Cloud Map (DNS privado interno)
export SECRET_NAME="innovatech/db"

# Nombres lógicos de los servicios ECS
export SVC_FRONTEND="innovatech-frontend"
export SVC_VENTAS="innovatech-ventas"
export SVC_DESPACHOS="innovatech-despachos"
export SVC_DB="innovatech-db"

# ── Account ID (necesario para el ARN de LabRole y de los secrets) ────────────
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# ── Descubrimiento de la VPC de EP1 ───────────────────────────────────────────
export VPC_ID="$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
  --query "Vpcs[0].VpcId" --output text)"

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo "ERROR: no existe la VPC '${PROJECT}-vpc'. Ejecuta antes scripts/crear-red-lab.sh (EP1)." >&2
  exit 1
fi

subnet_id () {
  aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$1" \
    --query "Subnets[0].SubnetId" --output text
}

# Públicas → ALB ;  App privadas → tareas Fargate (salen a Internet por el NAT de EP1)
export PUB_A="$(subnet_id "${PROJECT}-public-a")"
export PUB_B="$(subnet_id "${PROJECT}-public-b")"
export APP_A="$(subnet_id "${PROJECT}-app-a")"
export APP_B="$(subnet_id "${PROJECT}-app-b")"

# ── ECR: URIs de los repositorios (creados en EP2) ────────────────────────────
ecr_uri () {
  aws ecr describe-repositories --repository-names "$1" \
    --query "repositories[0].repositoryUri" --output text 2>/dev/null || true
}
export ECR_REPO_FRONTEND="$(ecr_uri innovatech-frontend)"
export ECR_REPO_VENTAS="$(ecr_uri innovatech-ventas)"
export ECR_REPO_DESPACHOS="$(ecr_uri innovatech-despachos)"

echo "──────────────────────────────────────────────"
echo " Región        : $AWS_REGION"
echo " Account ID     : $AWS_ACCOUNT_ID"
echo " VPC (EP1)      : $VPC_ID"
echo " Subredes pub   : $PUB_A / $PUB_B"
echo " Subredes app   : $APP_A / $APP_B"
echo " ECR frontend   : ${ECR_REPO_FRONTEND:-<no creado>}"
echo " ECR ventas     : ${ECR_REPO_VENTAS:-<no creado>}"
echo " ECR despachos  : ${ECR_REPO_DESPACHOS:-<no creado>}"
echo "──────────────────────────────────────────────"

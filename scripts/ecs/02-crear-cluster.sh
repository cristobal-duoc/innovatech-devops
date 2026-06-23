#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 02-crear-cluster.sh — Clúster ECS, namespace Cloud Map, log groups y ECR  (IE1)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

# ── 1. Repositorios ECR (idempotente; normalmente ya existen desde EP2) ───────
for repo in innovatech-frontend innovatech-ventas innovatech-despachos; do
  aws ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1 \
    || { echo "==> Creando repositorio ECR $repo"; \
         aws ecr create-repository --repository-name "$repo" \
           --image-scanning-configuration scanOnPush=true >/dev/null; }
done

# ── 2. Log groups en CloudWatch (IE6) ─────────────────────────────────────────
for lg in /ecs/innovatech-frontend /ecs/innovatech-ventas /ecs/innovatech-despachos /ecs/innovatech-db; do
  aws logs create-log-group --log-group-name "$lg" 2>/dev/null \
    && echo "==> Log group creado: $lg" || echo "    Log group ya existe: $lg"
  aws logs put-retention-policy --log-group-name "$lg" --retention-in-days 7 2>/dev/null || true
done

# ── 3. Clúster ECS con Container Insights (métricas) ──────────────────────────
echo "==> Creando clúster $CLUSTER_NAME..."
aws ecs create-cluster \
  --cluster-name "$CLUSTER_NAME" \
  --capacity-providers FARGATE FARGATE_SPOT \
  --settings name=containerInsights,value=enabled \
  --query "cluster.clusterArn" --output text

# ── 4. Namespace privado de Cloud Map (DNS interno innovatech.local) ──────────
NS_ID="$(aws servicediscovery list-namespaces \
  --query "Namespaces[?Name=='${NAMESPACE_NAME}'].Id" --output text)"

if [ -z "$NS_ID" ] || [ "$NS_ID" == "None" ]; then
  echo "==> Creando namespace Cloud Map $NAMESPACE_NAME..."
  OP_ID="$(aws servicediscovery create-private-dns-namespace \
    --name "$NAMESPACE_NAME" --vpc "$VPC_ID" \
    --query "OperationId" --output text)"
  echo "    operación $OP_ID en curso, esperando..."
  for i in $(seq 1 30); do
    STATUS="$(aws servicediscovery get-operation --operation-id "$OP_ID" \
      --query "Operation.Status" --output text)"
    [ "$STATUS" == "SUCCESS" ] && break
    [ "$STATUS" == "FAIL" ] && { echo "ERROR creando namespace"; exit 1; }
    sleep 5
  done
  echo "    namespace creado."
else
  echo "    namespace ya existe: $NS_ID"
fi

echo "==> Clúster, logs y namespace listos."

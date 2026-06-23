#!/bin/bash
# ============================================================
# deploy-ec2.sh — Script de levantamiento Innovatech Chile
# Uso: ./scripts/deploy-ec2.sh
# Requiere: AWS CLI configurado, variables de entorno del lab
# ============================================================
set -e

# ── Configuración ─────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REGISTRY="${ECR_REGISTRY}"          # ej: 192005133577.dkr.ecr.us-east-1.amazonaws.com
ECR_REPO_FRONTEND="${ECR_REPO_FRONTEND}"
ECR_REPO_DESPACHOS="${ECR_REPO_DESPACHOS}"
ECR_REPO_VENTAS="${ECR_REPO_VENTAS}"
EC2_FRONTEND_ID="${EC2_FRONTEND_ID}"    # i-0aeb9d2adf03857aa
EC2_BACKEND_ID="${EC2_BACKEND_ID}"      # i-074614beb76d1d1bf
DB_ENDPOINT="${DB_ENDPOINT}"
DB_NAME="${DB_NAME:-innovatech}"
DB_USERNAME="${DB_USERNAME:-appuser}"
DB_PASSWORD="${DB_PASSWORD}"

echo "========================================"
echo " Innovatech Chile — Deploy a EC2 (AWS)"
echo "========================================"

# ── 1. Login en Amazon ECR ────────────────────────────────────
echo "[1/4] Autenticando en Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# ── 2. Build y Push de las 3 imágenes ─────────────────────────
echo "[2/4] Build y Push de imágenes Docker..."

echo "  → Backend Despachos..."
docker build -t innovatech-despachos ./back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO
docker tag innovatech-despachos:latest "$ECR_REPO_DESPACHOS:latest"
docker push "$ECR_REPO_DESPACHOS:latest"

echo "  → Backend Ventas..."
docker build -t innovatech-ventas ./back-Ventas_SpringBoot/Springboot-API-REST
docker tag innovatech-ventas:latest "$ECR_REPO_VENTAS:latest"
docker push "$ECR_REPO_VENTAS:latest"

echo "  → Frontend React/Vite..."
docker build -t innovatech-frontend ./front_despacho
docker tag innovatech-frontend:latest "$ECR_REPO_FRONTEND:latest"
docker push "$ECR_REPO_FRONTEND:latest"

# ── 3. Deploy Backend en EC2 privada (via SSM) ────────────────
echo "[3/4] Desplegando backends en EC2 privada (SSM)..."
aws ssm send-command \
  --instance-ids "$EC2_BACKEND_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy innovatech backends" \
  --parameters commands="[
    \"aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY\",
    \"docker pull $ECR_REPO_DESPACHOS:latest\",
    \"docker pull $ECR_REPO_VENTAS:latest\",
    \"docker stop innovatech-despachos || true\",
    \"docker rm   innovatech-despachos || true\",
    \"docker stop innovatech-ventas    || true\",
    \"docker rm   innovatech-ventas    || true\",
    \"docker run -d --name innovatech-despachos --restart unless-stopped -p 8081:8081 -e DB_ENDPOINT=$DB_ENDPOINT -e DB_PORT=3306 -e DB_NAME=$DB_NAME -e DB_USERNAME=$DB_USERNAME -e DB_PASSWORD=$DB_PASSWORD $ECR_REPO_DESPACHOS:latest\",
    \"docker run -d --name innovatech-ventas    --restart unless-stopped -p 8080:8080 -e DB_ENDPOINT=$DB_ENDPOINT -e DB_PORT=3306 -e DB_NAME=$DB_NAME -e DB_USERNAME=$DB_USERNAME -e DB_PASSWORD=$DB_PASSWORD $ECR_REPO_VENTAS:latest\"
  ]" \
  --region "$AWS_REGION" \
  --output text
echo "  Backend deploy enviado via SSM."

# ── 4. Deploy Frontend en EC2 pública (via SSM) ───────────────
echo "[4/4] Desplegando frontend en EC2 pública (SSM)..."
aws ssm send-command \
  --instance-ids "$EC2_FRONTEND_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy innovatech frontend" \
  --parameters commands="[
    \"aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY\",
    \"docker pull $ECR_REPO_FRONTEND:latest\",
    \"docker stop innovatech-frontend || true\",
    \"docker rm   innovatech-frontend || true\",
    \"docker run -d --name innovatech-frontend --restart unless-stopped -p 80:8080 -e BACKEND_DESPACHOS=$EC2_BACKEND_ID -e BACKEND_VENTAS=$EC2_BACKEND_ID $ECR_REPO_FRONTEND:latest\"
  ]" \
  --region "$AWS_REGION" \
  --output text
echo "  Frontend deploy enviado via SSM."

echo ""
echo "========================================"
echo " Deploy completado exitosamente."
echo " Frontend disponible en:"
echo " http://$(aws ec2 describe-instances \
    --instance-ids $EC2_FRONTEND_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region $AWS_REGION)"
echo "========================================"

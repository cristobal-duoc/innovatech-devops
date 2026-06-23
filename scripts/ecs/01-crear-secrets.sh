#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-crear-secrets.sh — Credenciales de BD en AWS Secrets Manager  (IE5)
#
# En lugar de viajar como texto plano en las task definitions, las credenciales
# se guardan cifradas en Secrets Manager y las tareas las inyectan en runtime
# mediante el bloque "secrets" (valueFrom). Sin exposición en el repositorio.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/00-variables.sh"

# Los valores se toman de variables de entorno si existen; si no, usa los del
# docker-compose de desarrollo. CÁMBIALOS en producción.
DB_NAME="${DB_NAME:-innovatech}"
DB_USERNAME="${DB_USERNAME:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-apppass}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root123}"

SECRET_JSON="$(cat <<JSON
{
  "DB_NAME": "$DB_NAME",
  "DB_USERNAME": "$DB_USERNAME",
  "DB_PASSWORD": "$DB_PASSWORD",
  "DB_ROOT_PASSWORD": "$DB_ROOT_PASSWORD"
}
JSON
)"

echo "==> Creando/actualizando secret '$SECRET_NAME'..."
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string "$SECRET_JSON" >/dev/null
  echo "    secret actualizado."
else
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Credenciales BD Innovatech (EP3)" \
    --secret-string "$SECRET_JSON" >/dev/null
  echo "    secret creado."
fi

SECRET_DB_ARN="$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" \
  --query "ARN" --output text)"
echo "    ARN: $SECRET_DB_ARN"

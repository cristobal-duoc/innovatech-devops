# Backend Ventas — Innovatech Chile (Spring Boot)

API REST de **ventas**. Spring Boot empaquetado como imagen Docker multi-stage
(build con Maven/Temurin 17 → runtime `eclipse-temurin:17-jre-alpine`, usuario
no-root). Escucha en el **puerto 8080**.

## Rol en la arquitectura
- Servicio ECS `innovatech-ventas` en subred privada (sin IP pública).
- Registrado en el **ALB interno** (`innovatech-alb-int`, listener `:8080`).
- El frontend lo alcanza vía `/api/ventas/` → ALB interno.

## Variables de entorno
| Variable      | Origen           | Descripción                          |
|---------------|------------------|--------------------------------------|
| `DB_ENDPOINT` | task definition  | endpoint de **Amazon RDS** (`innovatech-mysql…`) |
| `DB_PORT`     | task definition  | `3306`                               |
| `DB_NAME`     | **Secrets Manager** | nombre de la base de datos        |
| `DB_USERNAME` | **Secrets Manager** | usuario de BD                     |
| `DB_PASSWORD` | **Secrets Manager** | contraseña de BD                  |

Las credenciales se inyectan desde el secret `innovatech/db` (nunca en el repo).

## Build & ejecución local
```bash
cd Springboot-API-REST
docker build -t innovatech-ventas .
docker run -p 8080:8080 \
  -e DB_ENDPOINT=host.docker.internal -e DB_PORT=3306 \
  -e DB_NAME=innovatech -e DB_USERNAME=appuser -e DB_PASSWORD=apppass \
  innovatech-ventas
```

## Despliegue
Automático por [`.github/workflows/cicd-ventas.yml`](../.github/workflows/cicd-ventas.yml)
(build → push ECR → deploy ECS) al hacer `push` a `deploy`.

# Backend Despachos — Innovatech Chile (Spring Boot)

API REST de **despachos**. Spring Boot empaquetado como imagen Docker multi-stage
(build con Maven/Temurin 17 → runtime `eclipse-temurin:17-jre-alpine`, usuario
no-root). Escucha en el **puerto 8081**.

## Rol en la arquitectura
- Servicio ECS `innovatech-despachos` en subred privada (sin IP pública).
- Descubrible internamente como **`backend-despachos.innovatech.local`** (Cloud Map).
- El frontend lo alcanza vía `/api/despachos/`.

## Variables de entorno
| Variable      | Origen           | Descripción                          |
|---------------|------------------|--------------------------------------|
| `DB_ENDPOINT` | task definition  | `db.innovatech.local`                |
| `DB_PORT`     | task definition  | `3306`                               |
| `DB_NAME`     | **Secrets Manager** | nombre de la base de datos        |
| `DB_USERNAME` | **Secrets Manager** | usuario de BD                     |
| `DB_PASSWORD` | **Secrets Manager** | contraseña de BD                  |

Las credenciales se inyectan desde el secret `innovatech/db` (nunca en el repo).

## Build & ejecución local
```bash
cd Springboot-API-REST-DESPACHO
docker build -t innovatech-despachos .
docker run -p 8081:8081 \
  -e DB_ENDPOINT=host.docker.internal -e DB_PORT=3306 \
  -e DB_NAME=innovatech -e DB_USERNAME=appuser -e DB_PASSWORD=apppass \
  innovatech-despachos
```

## Despliegue
Automático por [`.github/workflows/cicd-despachos.yml`](../.github/workflows/cicd-despachos.yml)
(build → push ECR → deploy ECS) al hacer `push` a `deploy`.

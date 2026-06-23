# Innovatech Chile — Orquestación y CI/CD en AWS (EP3)

Plataforma de despacho y ventas de **Innovatech Chile** desplegada como **microservicios contenedorizados sobre AWS ECS Fargate**, con pipeline **CI/CD en GitHub Actions** (build → push → deploy), **autoscaling**, **gestión de secrets**, **logs en CloudWatch** y descubrimiento interno por **AWS Cloud Map**.

Este repositorio integra el trabajo de las tres evaluaciones:

| Etapa | Aporte |
|-------|--------|
| **EP1** | Diseño e infraestructura de red en AWS (VPC, subredes, NAT, IGW). |
| **EP2** | Contenedorización con Docker + primer CI/CD a EC2. |
| **EP3** | Orquestación en **ECS Fargate**, autoscaling, CI/CD a clúster, secrets, logs y validación. |

---

## 1. Arquitectura

```
                    Internet
                       │
                       ▼
            ┌──────────────────────┐   subredes públicas (red-lab-public-a/b)
            │  Application Load     │
            │  Balancer  :80        │
            └──────────┬───────────┘
                       │ HTTP 8080
                       ▼
        ┌──────────────────────────────┐  subredes privadas app (red-lab-app-a/b)
        │  ECS Service: frontend        │  React/Vite + Nginx  (Fargate)
        │  innovatech-frontend          │
        └───────┬───────────────┬──────┘
        /api/ventas/      /api/despachos/      (proxy nginx)
                │               │
                ▼               ▼
   ┌─────────────────┐  ┌────────────────────┐   Cloud Map: *.innovatech.local
   │ ECS: ventas     │  │ ECS: despachos     │   Spring Boot (Fargate)
   │ :8080           │  │ :8081              │
   └────────┬────────┘  └─────────┬──────────┘
            │  JDBC 3306           │
            └──────────┬───────────┘
                       ▼
              ┌──────────────────┐
              │ ECS: db (MySQL)  │   Cloud Map: db.innovatech.local
              └──────────────────┘

  Secrets Manager (innovatech/db)  ──►  inyecta credenciales en las tareas
  CloudWatch Logs (/ecs/innovatech-*) ◄─ logs de cada contenedor
  Application Auto Scaling (CPU 50%) ──► escala frontend/ventas/despachos 1→4
```

### Justificación de la arquitectura
- **ECS Fargate** (sin servidores que administrar): es el orquestador soportado de forma estable en **AWS Academy Learner Lab**, donde solo se dispone del rol fijo `LabRole` y no se pueden crear roles IAM propios (lo que complica EKS/eksctl).
- **Tareas en subredes privadas** (`red-lab-app-*`): no exponen IP pública; salen a Internet para descargar imágenes de ECR a través del **NAT Gateway** creado en EP1.
- **ALB en subredes públicas**: único punto de entrada desde Internet, en dos AZ → alta disponibilidad.
- **Cloud Map (DNS privado `innovatech.local`)**: el frontend resuelve los backends por nombre (`backend-ventas.innovatech.local`, `backend-despachos.innovatech.local`) y los backends resuelven la base (`db.innovatech.local`), sin IPs fijas. Encaja con el proxy nginx ya existente (variables `BACKEND_VENTAS` / `BACKEND_DESPACHOS`).

---

## 2. Estructura del repositorio

```
.
├── front_despacho/                 # Frontend React/Vite (Nginx)  → puerto 8080
├── back-Ventas_SpringBoot/         # API Ventas (Spring Boot)     → puerto 8080
├── back-Despachos_SpringBoot/      # API Despachos (Spring Boot)  → puerto 8081
├── docker-compose.yml              # Stack local de desarrollo
├── ecs/                            # Task definitions ECS (plantillas)
│   ├── task-def-frontend.json
│   ├── task-def-ventas.json
│   ├── task-def-despachos.json
│   └── task-def-db.json
├── scripts/
│   ├── crear-red-lab.sh            # Red AWS (EP1)
│   └── ecs/                        # Infraestructura EP3
│       ├── 00-variables.sh         # Config + descubrimiento de la red EP1
│       ├── 01-crear-secrets.sh     # Secrets Manager
│       ├── 02-crear-cluster.sh     # Clúster ECS + Cloud Map + Logs
│       ├── 03-crear-alb.sh         # Security Groups + ALB
│       ├── 04-crear-servicios.sh   # Task defs + servicios ECS
│       ├── 05-configurar-autoscaling.sh
│       ├── 99-desplegar-todo.sh    # Orquestador maestro
│       ├── simular-carga.sh        # Carga para evidenciar autoscaling
│       ├── validar-funcional.sh    # Validación Front → Back
│       └── destruir-todo.sh        # Limpieza de recursos
├── docs/
│   └── EP3_Guia_Ejecucion.md       # Paso a paso para el Learner Lab
└── .github/workflows/              # Pipelines CI/CD (build → push → deploy ECS)
    ├── cicd-frontend.yml
    ├── cicd-ventas.yml
    └── cicd-despachos.yml
```

---

## 3. Despliegue en AWS (resumen)

> Guía detallada paso a paso en **[`docs/EP3_Guia_Ejecucion.md`](docs/EP3_Guia_Ejecucion.md)**.

**Requisitos:** AWS CLI autenticado con las credenciales del Learner Lab, `bash`, `jq`, `gettext` (envsubst). Ejecutar desde AWS CloudShell o una shell Linux.

```bash
# 1. Red base (si no existe aún, de EP1)
bash scripts/crear-red-lab.sh

# 2. Imágenes en ECR — manual la primera vez, luego vía CI/CD
#    (o deja que los workflows construyan y publiquen)

# 3. Levantar TODO el entorno EP3
bash scripts/ecs/99-desplegar-todo.sh
#    → imprime la URL pública del Frontend (DNS del ALB)
```

Limpieza para no gastar crédito del laboratorio:

```bash
bash scripts/ecs/destruir-todo.sh
```

---

## 4. CI/CD (GitHub Actions)

Cada microservicio tiene su pipeline, disparado por `push` a la rama **`deploy`** (con *path filter*) o manualmente (`workflow_dispatch`):

1. **Checkout** del código.
2. **Login** en ECR.
3. **Build & Push** de la imagen Docker con doble tag: `:<git-sha>` (inmutable, trazable) y `:latest`.
4. **Render** de la task definition activa sustituyendo la nueva imagen.
5. **Deploy** a ECS (`amazon-ecs-deploy-task-definition`) esperando estabilidad del servicio (rollout controlado, rollback si falla).

### Secrets requeridos en GitHub (Settings → Secrets → Actions)

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` | Credenciales temporales del Learner Lab. |
| `ECR_REPO_FRONTEND` / `ECR_REPO_VENTAS` / `ECR_REPO_DESPACHOS` | URI completo del repositorio ECR de cada servicio. |

> Las credenciales del Learner Lab caducan; hay que actualizar los 3 secrets de AWS cada sesión.

---

## 5. Gestión de Secrets (IE5)

Las credenciales de base de datos **no viajan en texto plano**. Se almacenan cifradas en **AWS Secrets Manager** (secret `innovatech/db`) y las task definitions las inyectan en runtime con el bloque `secrets[].valueFrom`. El repositorio nunca contiene contraseñas reales (solo *defaults* de desarrollo en `01-crear-secrets.sh`, que deben cambiarse).

---

## 6. Autoscaling (IE3)

**Application Auto Scaling — Target Tracking** sobre `ECSServiceAverageCPUUtilization = 50 %`, rango **1 → 4** tareas, para `frontend`, `ventas` y `despachos`.

**¿Por qué 50 %?** Deja margen para absorber picos antes de saturar (escala "hacia arriba" con `ScaleOutCooldown` corto de 60 s) y evita oscilaciones al bajar (`ScaleInCooldown` de 300 s). Evidencia: ejecutar `scripts/ecs/simular-carga.sh` y observar en *ECS → Health and metrics* cómo crece el `desiredCount`.

---

## 7. Logs y métricas (IE6)

- **CloudWatch Logs**: cada contenedor envía stdout/stderr a `/ecs/innovatech-<servicio>` (driver `awslogs`).
- **Container Insights** habilitado en el clúster → métricas de CPU/memoria por servicio.
- **Métricas de pipeline**: tiempo de cada *run* y resultado en la pestaña *Actions* de GitHub.

---

## 8. Desarrollo local

```bash
docker compose up --build
# Frontend  → http://localhost
# Ventas    → http://localhost:8080
# Despachos → http://localhost:8081
```

---

## Autor
Cristóbal Martínez — Asignatura **Introducción a Herramientas DevOps (ISY1101)**, Duoc UC, 2025.

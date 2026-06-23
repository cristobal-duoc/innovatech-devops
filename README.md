# Innovatech Chile — Orquestación y CI/CD en AWS (EP3)

Plataforma de despacho y ventas de **Innovatech Chile** desplegada como **microservicios contenedorizados sobre AWS ECS Fargate**, con pipeline **CI/CD en GitHub Actions** (build → push → deploy), **autoscaling**, **gestión de secrets**, **logs en CloudWatch** y **base de datos en Amazon RDS**.

Este repositorio integra el trabajo de las tres evaluaciones:

| Etapa | Aporte |
|-------|--------|
| **EP1** | Diseño e infraestructura de red en AWS (VPC, subredes, NAT, IGW). |
| **EP2** | Contenedorización con Docker + primer CI/CD a EC2. |
| **EP3** | Orquestación en **ECS Fargate**, autoscaling, CI/CD al clúster, secrets, logs y validación. |

> **Despliegue real verificado** en cuenta `208288623082`, región `us-east-1`.

---

## 1. Arquitectura

```
                    Internet
                       │
                       ▼
         ┌──────────────────────────┐   subredes públicas (red-lab-public-a/b)
         │  ALB público  :80         │
         │  innovatech-alb-pub       │
         └───────────┬──────────────┘
                     │ HTTP 8080
                     ▼
        ┌───────────────────────────┐  subredes privadas app (red-lab-app-a/b)
        │  ECS Service: frontend     │  React/Vite + Nginx  (Fargate)
        │  innovatech-frontend       │
        └───────┬───────────────┬───┘
        /api/ventas/      /api/despachos/      (proxy nginx)
                │               │
                ▼               ▼
        ┌───────────────────────────┐  descubrimiento Front→Back
        │  ALB interno              │  innovatech-alb-int
        │  :8080 ventas             │  (listener por puerto)
        │  :8081 despachos          │
        └───────┬───────────────┬───┘
                ▼               ▼
   ┌─────────────────┐  ┌────────────────────┐   Spring Boot (Fargate)
   │ ECS: ventas     │  │ ECS: despachos     │
   │ :8080           │  │ :8081              │
   └────────┬────────┘  └─────────┬──────────┘
            │  JDBC 3306           │
            └──────────┬───────────┘
                       ▼
              ┌──────────────────┐
              │ Amazon RDS MySQL │   innovatech-mysql (8.0)
              └──────────────────┘

  Secrets Manager (innovatech/db)  ──►  inyecta credenciales en las tareas
  CloudWatch Logs (/ecs/innovatech-*) ◄─ logs de cada contenedor
  Application Auto Scaling (CPU 50%) ──► escala frontend/ventas/despachos 1→4
```

### Justificación y nota sobre el Learner Lab
- **ECS Fargate** (sin servidores que administrar): es el orquestador soportado de forma estable en **AWS Academy Learner Lab**, donde solo se dispone del rol fijo `LabRole`.
- **Descubrimiento Front→Back por ALB interno**: el Learner Lab **bloquea AWS Cloud Map** (`servicediscovery`), por lo que en lugar de DNS de Cloud Map se usa un **ALB interno** con un listener por backend (`:8080` ventas, `:8081` despachos). El proxy nginx del frontend apunta a ese ALB mediante variables de entorno — **sin modificar las imágenes**.
- **Base de datos en Amazon RDS**: endpoint estable, alineado con la configuración Spring de la app; las credenciales se inyectan desde Secrets Manager.
- **Tareas en subredes privadas** (`red-lab-app-*`): sin IP pública; descargan imágenes de ECR por el **NAT Gateway** de EP1.
- **ALB público en subredes públicas** en dos AZ → alta disponibilidad.

---

## 2. Estructura del repositorio

```
.
├── front_despacho/                 # Frontend React/Vite (Nginx)  → puerto 8080
├── back-Ventas_SpringBoot/         # API Ventas (Spring Boot)     → puerto 8080
├── back-Despachos_SpringBoot/      # API Despachos (Spring Boot)  → puerto 8081
├── docker-compose.yml              # Stack local de desarrollo
├── ecs/                            # Task definitions ECS (plantillas envsubst)
│   ├── task-def-frontend.json      #   BACKEND_* = DNS del ALB interno
│   ├── task-def-ventas.json        #   DB_ENDPOINT = endpoint RDS + secrets
│   └── task-def-despachos.json
├── scripts/
│   ├── crear-red-lab.sh            # Red AWS (EP1)
│   └── ecs/
│       ├── desplegar-learnerlab.sh # Despliegue completo EP3 (maestro)
│       ├── validar-funcional.sh    # Validación Front → Back (IE7)
│       ├── simular-carga.sh        # Carga para evidenciar autoscaling (IE3)
│       └── destruir-learnerlab.sh  # Limpieza de recursos
├── docs/
│   └── EP3_Guia_Ejecucion.md       # Paso a paso para el Learner Lab
└── .github/workflows/              # Pipelines CI/CD (build → push → deploy ECS)
    ├── cicd-frontend.yml
    ├── cicd-ventas.yml
    └── cicd-despachos.yml
```

---

## 3. Despliegue en AWS

> Guía detallada en **[`docs/EP3_Guia_Ejecucion.md`](docs/EP3_Guia_Ejecucion.md)**.

**Requisitos:** AWS CLI autenticado (credenciales del Learner Lab), `bash`, `jq`, `gettext` (envsubst). Ejecutar desde **AWS CloudShell**.

```bash
# 1. Red base (EP1), si no existe
bash scripts/crear-red-lab.sh

# 2. Imágenes en ECR — vía los workflows de GitHub Actions (recomendado),
#    o build/push manual desde un PC con Docker.

# 3. Desplegar TODO el entorno EP3 (clúster, RDS, ALBs, servicios, autoscaling)
bash scripts/ecs/desplegar-learnerlab.sh
#    → imprime la URL pública del Frontend

# 4. Validar
bash scripts/ecs/validar-funcional.sh
```

Limpieza para no gastar crédito:

```bash
bash scripts/ecs/destruir-learnerlab.sh
```

---

## 4. CI/CD (GitHub Actions)

Cada microservicio tiene su pipeline, disparado por `push` a la rama **`deploy`** (con *path filter*) o manualmente (`workflow_dispatch`):

1. **Checkout** del código.
2. **Login** en ECR.
3. **Build & Push** de la imagen Docker con doble tag: `:<git-sha>` (inmutable) y `:latest`.
4. **Render** de la task definition activa con la nueva imagen.
5. **Deploy** a ECS (`amazon-ecs-deploy-task-definition`) esperando estabilidad del servicio.

### Secrets requeridos en GitHub (Settings → Secrets → Actions)

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` | Credenciales temporales del Learner Lab (se renuevan cada sesión). |
| `ECR_REPO_FRONTEND` / `ECR_REPO_VENTAS` / `ECR_REPO_DESPACHOS` | URI completo del repositorio ECR de cada servicio. |

---

## 5. Gestión de Secrets (IE5)

Las credenciales de base de datos **no viajan en texto plano**. Se almacenan cifradas en **AWS Secrets Manager** (secret `innovatech/db`) y las task definitions las inyectan en runtime con `secrets[].valueFrom`. Lo no sensible (`DB_ENDPOINT`, `DB_PORT`) va como valor directo.

## 6. Autoscaling (IE3)

**Application Auto Scaling — Target Tracking** sobre `ECSServiceAverageCPUUtilization = 50 %`, rango **1 → 4** tareas, en `frontend`, `ventas` y `despachos`. El 50 % deja margen para picos (scale-out 60 s) y evita oscilaciones (scale-in 300 s). Evidencia: `scripts/ecs/simular-carga.sh`.

## 7. Logs y métricas (IE6)

- **CloudWatch Logs**: cada contenedor envía stdout/stderr a `/ecs/innovatech-<servicio>`.
- **Container Insights** en el clúster → métricas de CPU/memoria.
- **Tiempos de pipeline**: en la pestaña *Actions* de GitHub.

## 8. Desarrollo local

```bash
docker compose up --build
# Frontend → http://localhost · Ventas → :8080 · Despachos → :8081
```

---

## Autor
Cristóbal Martínez — **Introducción a Herramientas DevOps (ISY1101)**, Duoc UC, 2025.

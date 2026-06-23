# EP3 — Guía de ejecución paso a paso (AWS Academy Learner Lab)

Esta guía te lleva desde cero hasta el sistema funcionando en **ECS Fargate**, e
indica **qué capturar como evidencia** en cada paso (mapeado a los indicadores
IE1–IE7 de la pauta).

> **Dónde ejecutar los comandos:** abre el Learner Lab → *AWS Details* → inicia la
> consola AWS, y usa **AWS CloudShell** (icono `>_` arriba a la derecha). CloudShell
> ya trae `aws`, `bash`, `jq` y `git`. Sube el repo con `git clone` de tu fork.

---

## 0. Preparación

```bash
# Clonar tu repositorio
git clone https://github.com/<tu-usuario>/innovatech-devops.git
cd innovatech-devops

# Verificar identidad / región
aws sts get-caller-identity
export AWS_REGION=us-east-1
```

Comprueba que tienes `jq` y `envsubst`:
```bash
jq --version && envsubst --version | head -1
```

📸 **Evidencia:** salida de `aws sts get-caller-identity` (demuestra cuenta + LabRole).

---

## 1. Red base (EP1) — IE1

Si la red `red-lab` aún no existe en esta sesión:
```bash
bash scripts/crear-red-lab.sh
```
📸 **Evidencia:** consola **VPC → Your VPCs / Subnets**, mostrando `red-lab-vpc`,
las subredes públicas/app/data y el NAT Gateway.

---

## 2. Imágenes en ECR (build inicial)

La primera vez conviene publicar las imágenes manualmente (luego lo hace el CI/CD).
Crea los repos y haz push:

```bash
# Login en ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin \
    "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com"
```

> En CloudShell no hay Docker; usa los **workflows de GitHub Actions** para construir
> y publicar (recomendado), o hazlo desde tu PC con Docker Desktop. Ver paso 7.

---

## 3. Clúster, secrets, ALB y servicios — IE1, IE2, IE5

Despliegue completo en un comando:
```bash
bash scripts/ecs/99-desplegar-todo.sh
```

Este orquestador ejecuta, en orden:
1. `01-crear-secrets.sh` → secret `innovatech/db` en **Secrets Manager**.
2. `02-crear-cluster.sh` → clúster `innovatech-cluster`, namespace Cloud Map y log groups.
3. `03-crear-alb.sh` → Security Groups + **ALB** (imprime la URL pública).
4. `04-crear-servicios.sh` → task definitions + 4 servicios ECS.
5. `05-configurar-autoscaling.sh` → políticas de autoscaling.

📸 **Evidencia IE1:** consola **ECS → Clusters → innovatech-cluster** (clúster activo);
**Secrets Manager** mostrando `innovatech/db`; **EC2 → Security Groups** (las 4 SG).
📸 **Evidencia IE2:** **ECS → Services** con los 4 servicios en `runningCount = desiredCount`;
**EC2 → Load Balancers → innovatech-alb** y su **Target Group** con targets `healthy`.
📸 **Evidencia IE5:** detalle del secret y el bloque `secrets` en la task definition
(ECS → Task Definitions → revisión → JSON), demostrando que la contraseña no está en texto plano.

---

## 4. Validación funcional Front → Back — IE7

```bash
bash scripts/ecs/validar-funcional.sh
```
Abre además la **URL del ALB** en el navegador y navega la app.

📸 **Evidencia IE7:** salida del script (servicios ACTIVE, targets healthy, HTTP 200
del frontend y de `/api/ventas/` y `/api/despachos/`); captura del navegador con la app
cargada por la URL del ALB.

---

## 5. Logs y métricas — IE6

```bash
# Logs de un servicio
aws logs tail /ecs/innovatech-ventas --since 10m --follow
```
📸 **Evidencia IE6:** **CloudWatch → Log groups → /ecs/innovatech-*** con eventos;
**ECS → servicio → Health and metrics** (Container Insights, CPU/memoria).

---

## 6. Autoscaling en acción — IE3

En una pestaña de CloudShell genera carga; en otra (o en la consola) observa el escalado:
```bash
bash scripts/ecs/simular-carga.sh 300 60
```
📸 **Evidencia IE3:** **ECS → servicio frontend → Health and metrics** mostrando la CPU
sobre 50 % y el `desiredCount` subiendo de 1 → 2 → 3; consola **EC2 Auto Scaling** o
**Application Auto Scaling** con la política `*-cpu-tt`; y luego el *scale-in* al cesar la carga.

---

## 7. Pipeline CI/CD (build → push → deploy) — IE4

1. En GitHub → **Settings → Secrets and variables → Actions**, define:
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
   (copiados de *AWS Details* del Learner Lab) y
   `ECR_REPO_FRONTEND`, `ECR_REPO_VENTAS`, `ECR_REPO_DESPACHOS` (URI de cada repo ECR).
2. Haz un cambio pequeño en un servicio y `git push` a la rama **`deploy`**:
   ```bash
   git checkout deploy
   git commit -am "ci: prueba de despliegue automático a ECS"
   git push origin deploy
   ```
3. Observa el run en la pestaña **Actions**: build → push → render → deploy con espera de estabilidad.

📸 **Evidencia IE4:** run verde en *Actions* con los pasos; en ECS, la nueva revisión de
la task definition y el rollout; tag de imagen `:<git-sha>` en ECR.
📸 **Evidencia IE7 (recuperación):** fuerza un redeploy
(`aws ecs update-service --cluster innovatech-cluster --service innovatech-ventas --force-new-deployment`)
y captura cómo ECS levanta una tarea nueva y retira la anterior sin downtime.

---

## 8. Limpieza (¡importante para el crédito!)

Al terminar de capturar evidencias:
```bash
bash scripts/ecs/destruir-todo.sh
```

---

## Checklist de evidencias por indicador

| Indicador | Evidencia mínima |
|-----------|------------------|
| **IE1** Clúster | ECS cluster activo, 4 SG, namespace Cloud Map, roles (LabRole) |
| **IE2** Despliegue Front+Back | 4 servicios running, ALB + target group healthy, URL pública |
| **IE3** Autoscaling | Política CPU 50 %, gráfico de CPU y desiredCount subiendo/bajando |
| **IE4** Pipeline CI/CD | Run de Actions build→push→deploy, nueva revisión en ECS |
| **IE5** Secrets | Secret en Secrets Manager + bloque `secrets` en task definition |
| **IE6** Logs/métricas | CloudWatch Logs + Container Insights, tiempos del pipeline |
| **IE7** Validación Front→Back | App por ALB, `/api/*` respondiendo, recuperación post-redeploy |

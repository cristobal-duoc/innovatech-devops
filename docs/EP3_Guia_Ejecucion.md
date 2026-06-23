# EP3 — Guía de ejecución paso a paso (AWS Academy Learner Lab)

Reproduce desde cero el despliegue en **ECS Fargate** e indica qué capturar como
evidencia (IE1–IE7).

> **Dónde:** Learner Lab → *AWS Details* → consola AWS → **CloudShell** (icono `>_`),
> que ya trae `aws`, `jq`, `git` y `envsubst`. Clona tu fork con `git clone`.

---

## 0. Preparación
```bash
git clone https://github.com/<tu-usuario>/innovatech-devops.git
cd innovatech-devops
aws sts get-caller-identity      # 📸 cuenta + LabRole
export AWS_REGION=us-east-1
```

## 1. Red base (EP1) — IE1
```bash
bash scripts/crear-red-lab.sh
```
📸 VPC → Your VPCs / Subnets (`red-lab-vpc`, subredes, NAT).

## 2. Imágenes en ECR
Recomendado: que las construya **GitHub Actions** (paso 7). Alternativa: build/push
manual desde un PC con Docker Desktop:
```bash
aws ecr create-repository --repository-name innovatech-frontend  || true
aws ecr create-repository --repository-name innovatech-ventas    || true
aws ecr create-repository --repository-name innovatech-despachos || true
# docker build/tag/push de cada imagen a su repo ECR
```

## 3. Desplegar todo el entorno EP3 — IE1, IE2, IE5
```bash
bash scripts/ecs/desplegar-learnerlab.sh
```
Crea, en orden: secret, log groups, **clúster ECS**, Security Groups, **RDS MySQL**
(espera a `available`), **ALB público** (frontend), **ALB interno** (backends),
task definitions, **3 servicios** y **autoscaling**. Al final imprime la URL pública.

📸 **IE1:** ECS → Clusters → innovatech-cluster (ACTIVE, Container Insights).
📸 **IE2:** ECS → Services (3 running); EC2 → Load Balancers (pub + int) y Target Groups healthy; la app abierta en la URL.
📸 **IE5:** Secrets Manager → `innovatech/db`; y Task definition → bloque *Secrets* (`valueFrom`).

## 4. Validación funcional Front → Back — IE7
```bash
bash scripts/ecs/validar-funcional.sh
```
📸 Salida (servicios ACTIVE, targets healthy, HTTP 200 en `/` y en `/api/*/v3/api-docs`);
y el navegador mostrando `…/api/ventas/v3/api-docs` con el JSON del backend.

## 5. Logs y métricas — IE6
```bash
aws logs tail /ecs/innovatech-ventas --since 10m --follow
```
📸 CloudWatch → Log groups → `/ecs/innovatech-*`; ECS → servicio → *Health and metrics*.

## 6. Autoscaling en acción — IE3
```bash
bash scripts/ecs/simular-carga.sh 300 60
```
📸 ECS → frontend → Auto Scaling (política CPU 50 %, mín 1 / máx 4) y, durante la carga,
la CPU > 50 % con el `desiredCount` subiendo.

## 7. Pipeline CI/CD (build → push → deploy) — IE4
1. GitHub → **Settings → Secrets → Actions**: define
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (de *AWS Details*) y
   `ECR_REPO_FRONTEND/VENTAS/DESPACHOS` (URI de cada repo ECR de tu cuenta).
2. Push a la rama `deploy`:
   ```bash
   git checkout deploy
   git commit -am "ci: despliegue automatico a ECS"
   git push origin deploy
   ```
3. 📸 GitHub → **Actions**: runs en verde; dentro de uno, los pasos `Build y Push` y `Desplegar en ECS`.

## 8. Limpieza (¡cuida el crédito!)
```bash
bash scripts/ecs/destruir-learnerlab.sh
```

---

## Checklist de evidencias

| Indicador | Evidencia |
|-----------|-----------|
| **IE1** Clúster | ECS cluster ACTIVE, SG, roles (LabRole) |
| **IE2** Front+Back | 3 servicios running, ALB pub+int, target groups healthy, URL pública |
| **IE3** Autoscaling | Política CPU 50 % (1→4), CPU/desiredCount subiendo |
| **IE4** Pipeline | Run de Actions build→push→deploy en verde |
| **IE5** Secrets | Secret en Secrets Manager + `valueFrom` en task definition |
| **IE6** Logs/métricas | CloudWatch Logs + Container Insights, tiempos del pipeline |
| **IE7** Front→Back | App por ALB, `/api/*` 200, comunicación correcta |

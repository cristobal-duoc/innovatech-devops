# Frontend — Innovatech Chile (React + Vite + Nginx)

Interfaz web de la plataforma de despachos/ventas. En producción se sirve como
contenido estático con **Nginx**, que además actúa de **reverse proxy** hacia los
backends.

## Rol en la arquitectura
- Imagen multi-stage: build con `node:20-alpine` (`npm run build`) → sirve el
  `dist/` con `nginx:alpine` como **usuario no-root**, escuchando en el **puerto 8080**.
- En ECS corre como servicio `innovatech-frontend` **detrás del ALB** (única
  entrada pública del sistema).

## Proxy a backends (Front → Back)
`nginx.conf` enruta por path hacia los backends, cuyos hostnames se inyectan por
variables de entorno. En ECS apuntan al **ALB interno** (`innovatech-alb-int`),
que tiene un listener por backend (`:8080` ventas, `:8081` despachos):

| Ruta pública            | Destino interno                          |
|-------------------------|------------------------------------------|
| `/api/ventas/`          | `${BACKEND_VENTAS}:8080`                  |
| `/api/despachos/`       | `${BACKEND_DESPACHOS}:8081`              |

| Variable             | Valor en ECS                              |
|----------------------|-------------------------------------------|
| `BACKEND_VENTAS`     | DNS del ALB interno (`innovatech-alb-int…`) |
| `BACKEND_DESPACHOS`  | DNS del ALB interno (`innovatech-alb-int…`) |

> El Learner Lab bloquea AWS Cloud Map, por eso el descubrimiento Front→Back se
> hace por el ALB interno en vez de DNS de servicio.

`docker-entrypoint.sh` aplica `envsubst` sobre la plantilla de nginx en arranque.

## Build & ejecución local
```bash
npm install
npm run dev                 # desarrollo (Vite, HMR)

# o como contenedor:
docker build -t innovatech-frontend .
docker run -p 80:8080 \
  -e BACKEND_VENTAS=host.docker.internal \
  -e BACKEND_DESPACHOS=host.docker.internal \
  innovatech-frontend
```

## Despliegue
Automático por el workflow [`.github/workflows/cicd-frontend.yml`](../.github/workflows/cicd-frontend.yml)
(build → push ECR → deploy ECS) al hacer `push` a la rama `deploy`.

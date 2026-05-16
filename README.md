# tourism-platform

Plataforma multi-tenant para gestión turística desplegada sobre Kubernetes mediante una arquitectura de microservicios.

Este repositorio contiene la implementación de referencia, los manifiestos de Kubernetes, los scripts de despliegue y el informe académico correspondiente al trabajo dirigido del curso de Tópicos Avanzados en Redes.

---

**Universidad Nacional de San Antonio Abad del Cusco**
Facultad de Ingeniería Eléctrica, Electrónica, Informática y Mecánica
Escuela Profesional de Ingeniería Informática y de Sistemas

| | |
|---|---|
| Asignatura | Tópicos Avanzados en Redes (Dirigido) |
| Semestre | 2026-I |
| Autor | Cesar Ciro Olarte Bautista |
| Código | 200785 |

---

## Tabla de contenido

1. [Descripción del proyecto](#1-descripción-del-proyecto)
2. [Arquitectura](#2-arquitectura)
3. [Tecnologías utilizadas](#3-tecnologías-utilizadas)
4. [Requisitos previos](#4-requisitos-previos)
5. [Procedimiento de despliegue](#5-procedimiento-de-despliegue)
6. [Especificación de la API](#6-especificación-de-la-api)
7. [Verificación de funcionalidad](#7-verificación-de-funcionalidad)
8. [Estructura del repositorio](#8-estructura-del-repositorio)
9. [Patrones de diseño aplicados](#9-patrones-de-diseño-aplicados)
10. [Trabajo futuro](#10-trabajo-futuro)
11. [Limpieza del entorno](#11-limpieza-del-entorno)
12. [Referencias](#12-referencias)

---

## 1. Descripción del proyecto

El proyecto implementa una plataforma que expone, mediante una API REST autenticada, un catálogo de tours turísticos y un sistema de reservas que puede ser consumido por múltiples empresas clientes de manera concurrente y con aislamiento de datos.

El sistema está compuesto por cuatro microservicios independientes, contenedorizados con Docker y orquestados mediante Kubernetes. Incorpora persistencia con PostgreSQL, caché distribuido con Redis y exposición controlada al exterior a través de un Ingress Controller NGINX.

El propósito académico del trabajo es demostrar, en una implementación funcional, los conceptos fundamentales de arquitecturas cloud-native: contenedorización, orquestación declarativa, descubrimiento de servicios, persistencia de estado y patrones de comunicación entre microservicios.

## 2. Arquitectura

```
                    Empresas clientes (consumidores externos)
                                │
                                ▼
                    ┌───────────────────────┐
                    │   Ingress NGINX       │  tourism.local:80
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │     API Gateway       │  Valida X-API-Key
                    │     (2 réplicas)      │  Inyecta X-Company-Id
                    └─┬─────────┬─────────┬─┘
                      │         │         │
          ┌───────────▼─┐  ┌────▼─────┐  ┌▼──────────────┐
          │ auth-service│  │tours-svc │  │bookings-service│
          │ (2 réplicas)│  │ (2 rép.) │  │  (2 réplicas)  │
          └─────────┬───┘  └─┬────┬───┘  └────────┬───────┘
                    │        │    │               │
                    │        │    └─── (s2s) ─────┤
                    │        ▼                    │
                    │  ┌──────────┐               │
                    │  │  Redis   │               │
                    │  │  Cache   │               │
                    │  └──────────┘               │
                    │                             │
                    └──────────┬──────────────────┘
                               │
                       ┌───────▼────────┐
                       │   PostgreSQL   │  StatefulSet + PVC 1Gi
                       │   (postgres-0) │
                       └────────────────┘
```

### 2.1. Componentes

| Componente | Tipo de objeto | Réplicas | Responsabilidad |
|---|---|---:|---|
| `api-gateway` | Deployment | 2 | Punto único de entrada. Validación de API Key y enrutamiento hacia servicios internos. |
| `auth-service` | Deployment | 2 | Registro de empresas clientes y validación de credenciales. |
| `tours-service` | Deployment | 2 | Gestión del catálogo de tours. Implementa caché distribuido. |
| `bookings-service` | Deployment | 2 | Gestión de reservas con aislamiento por tenant. |
| `postgres` | StatefulSet | 1 | Persistencia relacional mediante PersistentVolumeClaim de 1 GiB. |
| `redis` | Deployment | 1 | Caché en memoria con TTL configurable. |
| `ingress-nginx` | DaemonSet | — | Exposición HTTP/HTTPS hacia el exterior del clúster. |

## 3. Tecnologías utilizadas

| Categoría | Tecnología | Versión |
|---|---|---|
| Lenguaje de programación | Python | 3.12 |
| Framework web | FastAPI | 0.115 |
| Servidor ASGI | Uvicorn | 0.32 |
| Driver PostgreSQL asíncrono | asyncpg | 0.30 |
| Cliente Redis asíncrono | redis-py | 5.1 |
| Cliente HTTP asíncrono | httpx | 0.27 |
| Validación de esquemas | Pydantic | 2.9 |
| Container runtime | Docker | — |
| Orquestador | Kubernetes | 1.35 |
| Distribución local | Kind | 0.27 |
| Base de datos relacional | PostgreSQL | 16-alpine |
| Caché en memoria | Redis | 7-alpine |
| Ingress Controller | NGINX | latest |

## 4. Requisitos previos

El entorno de despliegue requiere los siguientes componentes instalados:

- Docker Engine ≥ 24.0
- Kind ≥ 0.20
- kubectl ≥ 1.28
- `jq` (opcional, mejora la legibilidad de la salida del script de demostración)

En sistemas basados en Arch Linux:

```
sudo pacman -S docker kubectl jq
yay -S kind-bin
```

Adicionalmente, se requiere mapear el dominio local `tourism.local` a la interfaz de loopback:

```
echo "127.0.0.1  tourism.local" | sudo tee -a /etc/hosts
```

## 5. Procedimiento de despliegue

El despliegue completo se realiza mediante cuatro scripts secuenciales ubicados en el directorio `scripts/`:

```
./scripts/01-setup-cluster.sh    # Crea el clúster Kind y despliega Ingress NGINX
./scripts/02-build-images.sh     # Construye las imágenes Docker y las carga al clúster
./scripts/03-deploy.sh           # Aplica los manifiestos en orden de dependencias
./scripts/04-demo.sh             # Ejecuta una demostración end-to-end
```

El script `05-apply-retry-fix.sh` está disponible para reaplicar parches sobre los servicios cuando se modifica su código, sin requerir un nuevo despliegue completo.

Una vez ejecutado el despliegue, el estado del clúster puede verificarse con:

```
kubectl -n tourism get pods
kubectl -n tourism get services
curl http://tourism.local/
```

La documentación interactiva generada automáticamente por FastAPI está disponible en `http://tourism.local/docs`.

## 6. Especificación de la API

Todas las rutas (excepto el registro de empresas) requieren el header `X-API-Key` con un token válido.

### 6.1. Registro de empresa cliente

```
POST /companies
Content-Type: application/json

{
  "name": "Mi Agencia SAC",
  "email": "info@miagencia.pe"
}
```

Respuesta `201 Created`:

```json
{
  "id": 1,
  "name": "Mi Agencia SAC",
  "email": "info@miagencia.pe",
  "api_key": "tk_xxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "created_at": "2026-05-15T01:18:48"
}
```

La API Key se devuelve únicamente en este momento. En la base de datos se almacena exclusivamente su hash SHA-256.

### 6.2. Consulta del catálogo

```
GET /tours
X-API-Key: tk_xxxxxxxxxxxx
```

Respuesta `200 OK`:

```json
{
  "source": "database",
  "data": [
    {
      "id": 1,
      "title": "Machu Picchu Full Day",
      "location": "Cusco",
      "price_usd": 280.00,
      "duration_hours": 14
    }
  ]
}
```

El campo `source` indica el origen de los datos: `database` en la primera lectura y `cache` en las subsiguientes durante el TTL de 60 segundos.

### 6.3. Creación de reserva

```
POST /bookings
Content-Type: application/json
X-API-Key: tk_xxxxxxxxxxxx

{
  "tour_id": 1,
  "customer_name": "Juan Pérez",
  "customer_email": "juan@example.com",
  "tour_date": "2026-07-01",
  "num_people": 4
}
```

### 6.4. Listado de reservas del tenant

```
GET /bookings
X-API-Key: tk_xxxxxxxxxxxx
```

Solo se devuelven las reservas asociadas a la empresa identificada por la API Key.

## 7. Verificación de funcionalidad

### 7.1. Autorreparación (self-healing)

Al eliminar un pod, el controlador de Kubernetes recrea automáticamente una réplica para mantener el estado declarado:

```
kubectl -n tourism delete pod -l app=tours-service
kubectl -n tourism get pods -l app=tours-service -w
```

### 7.2. Escalado horizontal

El número de réplicas puede modificarse en caliente sin interrupción del servicio:

```
kubectl -n tourism scale deployment tours-service --replicas=5
kubectl -n tourism get pods -l app=tours-service
```

### 7.3. Comportamiento del caché

La primera consulta debe reportar `source: "database"` y las subsiguientes `source: "cache"`:

```
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
```

### 7.4. Persistencia de datos

Al eliminar y recrear el pod de PostgreSQL, los datos sobreviven gracias al PersistentVolumeClaim:

```
kubectl -n tourism delete pod postgres-0
kubectl -n tourism wait --for=condition=ready pod/postgres-0 --timeout=120s
kubectl -n tourism exec -it postgres-0 -- psql -U tourism -d tourism_db \
  -c "SELECT COUNT(*) FROM bookings;"
```

## 8. Estructura del repositorio

```
tourism-platform/
├── README.md
├── informe.typ                 Informe académico (Typst)
├── docs/
│   └── GUION_VIDEO.md
├── services/
│   ├── api-gateway/            Servicio: punto de entrada
│   ├── auth-service/           Servicio: autenticación
│   ├── tours-service/          Servicio: catálogo
│   └── bookings-service/       Servicio: reservas
├── k8s/
│   ├── base/                   Namespace, ConfigMap, Secret
│   ├── databases/              Manifiestos de PostgreSQL y Redis
│   ├── services/               Deployments y Services de la aplicación
│   └── ingress/                Reglas de enrutamiento HTTP
└── scripts/
    ├── 01-setup-cluster.sh
    ├── 02-build-images.sh
    ├── 03-deploy.sh
    ├── 04-demo.sh
    └── 05-apply-retry-fix.sh
```

Cada subdirectorio de `services/` contiene un `Dockerfile`, el código fuente del servicio (`main.py`) y su archivo de dependencias (`requirements.txt`).

## 9. Patrones de diseño aplicados

| Patrón | Implementación en el proyecto |
|---|---|
| API Gateway | El servicio `api-gateway` actúa como punto único de ingreso, centralizando autenticación y enrutamiento. |
| Multi-tenancy | Cada empresa cliente se identifica por una API Key única. El campo `company_id` se inyecta vía header y filtra las consultas de la base de datos. |
| Cache-aside | `tours-service` consulta Redis antes que PostgreSQL. En caso de miss, recupera de la base de datos y popula el caché. Las escrituras invalidan la entrada cacheada. |
| Service-to-service discovery | La comunicación entre servicios utiliza el DNS interno del clúster (`http://tours-service:8000`), eliminando la necesidad de configuración de IPs estáticas. |
| Self-healing | Los Deployments mantienen un número declarado de réplicas mediante el reconciliation loop del controlador. |
| Retry con backoff | Las llamadas a dependencias externas (base de datos, otros servicios) implementan reintentos con espera incremental para tolerar fallos transitorios. |
| Twelve-Factor App | Configuración externalizada mediante variables de entorno (ConfigMap), logs dirigidos a stdout, procesos sin estado local. |
| StatefulSet con PVC | PostgreSQL mantiene identidad estable y almacenamiento persistente entre reinicios. |

## 10. Trabajo futuro

A partir de la base implementada, las siguientes extensiones representan rutas naturales de evolución:

- **Helm Chart** para empaquetar el despliegue de manera parametrizable y versionada.
- **Prometheus y Grafana** para observabilidad de métricas a nivel de clúster, servicios y aplicación.
- **Loki** para centralización y búsqueda de logs estructurados.
- **HorizontalPodAutoscaler** para escalado automático basado en uso de CPU, memoria o métricas personalizadas (requests por segundo).
- **NetworkPolicy** para restricción de tráfico inter-pod siguiendo el principio de menor privilegio.
- **cert-manager con Let's Encrypt** para gestión automática de certificados TLS.
- **Service mesh** (Istio o Linkerd) para mTLS automático entre servicios y observabilidad a nivel de aplicación.
- **GitOps con Argo CD** para sincronización continua del clúster con el estado declarado en este repositorio.
- **Replicación de PostgreSQL** para alta disponibilidad de la capa de persistencia.
- **Rate limiting por API Key** en el Gateway para protección contra abuso y soporte de modelos de pricing por tier.

## 11. Limpieza del entorno

Para eliminar completamente el clúster y los recursos asociados:

```
kind delete cluster --name tourism
```

Los volúmenes persistentes residen dentro de los nodos de Kind y se eliminan junto con el clúster.

## 12. Referencias

1. The Kubernetes Authors. *Kubernetes Documentation*. https://kubernetes.io/docs/
2. Docker Inc. *Docker Documentation*. https://docs.docker.com/
3. Ramírez, S. *FastAPI Documentation*. https://fastapi.tiangolo.com/
4. The Kind Authors. *Kind: Kubernetes in Docker*. https://kind.sigs.k8s.io/
5. Newman, S. (2021). *Building Microservices: Designing Fine-Grained Systems* (2nd ed.). O'Reilly Media.
6. Burns, B., Beda, J., Hightower, K., & Evenson, L. (2022). *Kubernetes: Up and Running* (3rd ed.). O'Reilly Media.
7. Richardson, C. (2018). *Microservices Patterns: With Examples in Java*. Manning Publications.
8. Wiggins, A. *The Twelve-Factor App*. https://12factor.net/
9. NGINX Inc. *NGINX Ingress Controller Documentation*. https://kubernetes.github.io/ingress-nginx/

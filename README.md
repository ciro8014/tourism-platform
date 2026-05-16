# Tourism Platform 🌎

> Plataforma multi-tenant para gestión turística desplegada sobre Kubernetes con microservicios

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Python](https://img.shields.io/badge/python-3.12-3776AB?style=flat&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat&logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=flat&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=flat&logo=redis&logoColor=white)

**Curso:** Tópicos Avanzados en Redes (Dirigido) — UNSAAC 2026-I
**Autor:** Cesar Ciro Olarte Bautista (200785)

---

## 📋 Tabla de contenidos

- [¿Qué hace este proyecto?](#-qué-hace-este-proyecto)
- [Arquitectura](#-arquitectura)
- [Tecnologías](#-tecnologías)
- [Requisitos](#-requisitos)
- [Despliegue rápido](#-despliegue-rápido)
- [Cómo consumir la API](#-cómo-consumir-la-api)
- [Demos y verificación](#-demos-y-verificación)
- [Estructura del proyecto](#-estructura-del-proyecto)
- [Patrones implementados](#-patrones-implementados)
- [Trabajo futuro](#-trabajo-futuro)
- [Limpieza](#-limpieza)

---

## 🎯 ¿Qué hace este proyecto?

Una **plataforma multi-tenant** que expone un catálogo de tours y un sistema de reservas como APIs consumibles por múltiples empresas (otras agencias de turismo). Cada empresa cliente se registra, obtiene una API Key y puede:

- Consultar el catálogo de tours disponibles
- Crear reservas para sus propios clientes
- Listar sus reservas (aisladas de las de otras empresas)

Todo desplegado sobre Kubernetes con microservicios, demostrando los patrones de arquitectura cloud-native modernos.

---

## 🏗️ Arquitectura

```
                    Empresas clientes (otras agencias)
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

### Componentes

| Componente | Tipo | Réplicas | Responsabilidad |
|---|---|---|---|
| `api-gateway` | Deployment | 2 | Punto único de entrada, autenticación, routing |
| `auth-service` | Deployment | 2 | Registro de empresas y validación de API Keys |
| `tours-service` | Deployment | 2 | CRUD del catálogo, caché Redis con cache-aside |
| `bookings-service` | Deployment | 2 | CRUD de reservas, validación s2s con tours-service |
| `postgres` | StatefulSet | 1 | Persistencia (PVC 1Gi) |
| `redis` | Deployment | 1 | Caché en memoria |
| `ingress-nginx` | DaemonSet | — | Exposición externa |

---

## 🛠️ Tecnologías

- **Lenguaje:** Python 3.12 (async)
- **Framework:** FastAPI 0.115
- **Driver DB:** asyncpg 0.30
- **Cliente Redis:** redis-py 5.1 (async)
- **HTTP client:** httpx 0.27 (para service-to-service)
- **Contenedores:** Docker
- **Orquestación:** Kubernetes 1.35 (Kind 0.27)
- **DB:** PostgreSQL 16-alpine
- **Caché:** Redis 7-alpine
- **Ingress:** NGINX Ingress Controller

---

## 📦 Requisitos

- Docker
- [Kind](https://kind.sigs.k8s.io/) ≥ 0.20
- kubectl
- `jq` (opcional, mejora la salida del demo)

Instalación en Arch / Nyarch / EndeavourOS:

```bash
sudo pacman -S docker kubectl jq
yay -S kind-bin
```

Agrega `tourism.local` a tu `/etc/hosts`:

```bash
echo "127.0.0.1  tourism.local" | sudo tee -a /etc/hosts
```

---

## 🚀 Despliegue rápido

Cuatro comandos y tienes la plataforma corriendo:

```bash
# 1. Cluster Kind de 3 nodos + Ingress NGINX
./scripts/01-setup-cluster.sh

# 2. Construir las 4 imágenes Docker y cargarlas al cluster
./scripts/02-build-images.sh

# 3. Aplicar todos los manifests de Kubernetes
./scripts/03-deploy.sh

# 4. Demo end-to-end
./scripts/04-demo.sh
```

Verificación:

```bash
kubectl -n tourism get pods
curl http://tourism.local/
```

Documentación interactiva (Swagger UI): http://tourism.local/docs

---

## 🔌 Cómo consumir la API

Una empresa cliente se registra una sola vez y obtiene una API Key:

### 1. Registro (público, sin autenticación)

```bash
curl -X POST http://tourism.local/companies \
  -H "Content-Type: application/json" \
  -d '{"name": "Mi Agencia SAC", "email": "info@miagencia.pe"}'
```

Respuesta:
```json
{
  "id": 1,
  "name": "Mi Agencia SAC",
  "email": "info@miagencia.pe",
  "api_key": "tk_xxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "created_at": "2026-05-15T01:18:48"
}
```

### 2. Consumir el catálogo

```bash
curl http://tourism.local/tours \
  -H "X-API-Key: tk_xxxxxxxxxxxx"
```

### 3. Crear una reserva

```bash
curl -X POST http://tourism.local/bookings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: tk_xxxxxxxxxxxx" \
  -d '{
    "tour_id": 1,
    "customer_name": "Juan Perez",
    "customer_email": "juan@example.com",
    "tour_date": "2026-07-01",
    "num_people": 4
  }'
```

### 4. Listar reservas propias

```bash
curl http://tourism.local/bookings \
  -H "X-API-Key: tk_xxxxxxxxxxxx"
```

---

## 🎬 Demos y verificación

### Self-healing (autoreparación)

Kubernetes recrea pods automáticamente si mueren:

```bash
kubectl -n tourism delete pod -l app=tours-service
kubectl -n tourism get pods -l app=tours-service -w
```

### Escalado horizontal

```bash
kubectl -n tourism scale deployment tours-service --replicas=5
kubectl -n tourism get pods -l app=tours-service
```

### Verificar el cache-aside

```bash
# Primera llamada: source = "database"
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source

# Segunda inmediata: source = "cache"
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
```

### Persistencia de PostgreSQL

```bash
kubectl -n tourism delete pod postgres-0
kubectl -n tourism wait --for=condition=ready pod/postgres-0 --timeout=120s
# Los datos persisten gracias al PersistentVolumeClaim
```

### Logs en vivo

```bash
kubectl -n tourism logs -f deployment/api-gateway
```

---

## 📁 Estructura del proyecto

```
tourism-platform/
├── README.md
├── informe.typ              # Informe académico (Typst → PDF)
├── docs/
│   └── GUION_VIDEO.md
├── services/
│   ├── api-gateway/         # FastAPI - punto de entrada
│   ├── auth-service/        # FastAPI - API Keys
│   ├── tours-service/       # FastAPI - catálogo + Redis
│   └── bookings-service/    # FastAPI - reservas
├── k8s/
│   ├── base/                # Namespace, ConfigMap, Secret
│   ├── databases/           # PostgreSQL (StatefulSet) + Redis
│   ├── services/            # 4 Deployments + Services
│   └── ingress/             # Ingress NGINX
└── scripts/
    ├── 01-setup-cluster.sh
    ├── 02-build-images.sh
    ├── 03-deploy.sh
    ├── 04-demo.sh
    └── 05-apply-retry-fix.sh
```

---

## 🧩 Patrones implementados

| Patrón | Implementación |
|---|---|
| **API Gateway** | `api-gateway` centraliza autenticación y routing |
| **Multi-tenancy** | Aislamiento por `company_id` inyectado vía header |
| **Cache-aside** | `tours-service` consulta primero Redis, fallback a Postgres |
| **Service-to-service** | `bookings-service` → `tours-service` via DNS interno |
| **Self-healing** | Deployments mantienen N réplicas mediante reconciliation loop |
| **Retry con backoff** | Resiliencia ante fallos transitorios de red/DNS |
| **12-Factor App** | Configuración vía env vars (ConfigMap), logs a stdout |
| **StatefulSet + PVC** | Identidad estable y persistencia para PostgreSQL |

---

## 🔮 Trabajo futuro

- **Helm Chart** para empaquetar el despliegue parametrizado
- **Prometheus + Grafana** para observabilidad y métricas
- **Loki** para centralización de logs
- **HorizontalPodAutoscaler** para escalado automático por CPU/RPS
- **NetworkPolicy** para seguridad zero-trust entre pods
- **cert-manager + Let's Encrypt** para TLS automático
- **Service mesh** (Istio/Linkerd) para mTLS y observabilidad L7
- **Argo CD** para GitOps
- **Rate limiting** por API Key en el Gateway
- **Replicación de PostgreSQL** para alta disponibilidad

---

## 🧹 Limpieza

Para borrar todo el cluster cuando termines:

```bash
kind delete cluster --name tourism
```

Los datos persistentes (PVC) viven dentro del nodo Kind, así que se eliminan junto con el cluster.

---

## 📄 Licencia

Trabajo académico desarrollado para la UNSAAC. Uso libre con atribución.

---

<sub>Hecho con ☕ en Cusco, Perú</sub># Tourism Platform 🌎

> Plataforma multi-tenant para gestión turística desplegada sobre Kubernetes con microservicios

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Python](https://img.shields.io/badge/python-3.12-3776AB?style=flat&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat&logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=flat&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=flat&logo=redis&logoColor=white)

**Curso:** Tópicos Avanzados en Redes (Dirigido) — UNSAAC 2026-I
**Autor:** Cesar Ciro Olarte Bautista (200785)

---

## 📋 Tabla de contenidos

- [¿Qué hace este proyecto?](#-qué-hace-este-proyecto)
- [Arquitectura](#-arquitectura)
- [Tecnologías](#-tecnologías)
- [Requisitos](#-requisitos)
- [Despliegue rápido](#-despliegue-rápido)
- [Cómo consumir la API](#-cómo-consumir-la-api)
- [Demos y verificación](#-demos-y-verificación)
- [Estructura del proyecto](#-estructura-del-proyecto)
- [Patrones implementados](#-patrones-implementados)
- [Trabajo futuro](#-trabajo-futuro)
- [Limpieza](#-limpieza)

---

## 🎯 ¿Qué hace este proyecto?

Una **plataforma multi-tenant** que expone un catálogo de tours y un sistema de reservas como APIs consumibles por múltiples empresas (otras agencias de turismo). Cada empresa cliente se registra, obtiene una API Key y puede:

- Consultar el catálogo de tours disponibles
- Crear reservas para sus propios clientes
- Listar sus reservas (aisladas de las de otras empresas)

Todo desplegado sobre Kubernetes con microservicios, demostrando los patrones de arquitectura cloud-native modernos.

---

## 🏗️ Arquitectura

```
                    Empresas clientes (otras agencias)
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

### Componentes

| Componente | Tipo | Réplicas | Responsabilidad |
|---|---|---|---|
| `api-gateway` | Deployment | 2 | Punto único de entrada, autenticación, routing |
| `auth-service` | Deployment | 2 | Registro de empresas y validación de API Keys |
| `tours-service` | Deployment | 2 | CRUD del catálogo, caché Redis con cache-aside |
| `bookings-service` | Deployment | 2 | CRUD de reservas, validación s2s con tours-service |
| `postgres` | StatefulSet | 1 | Persistencia (PVC 1Gi) |
| `redis` | Deployment | 1 | Caché en memoria |
| `ingress-nginx` | DaemonSet | — | Exposición externa |

---

## 🛠️ Tecnologías

- **Lenguaje:** Python 3.12 (async)
- **Framework:** FastAPI 0.115
- **Driver DB:** asyncpg 0.30
- **Cliente Redis:** redis-py 5.1 (async)
- **HTTP client:** httpx 0.27 (para service-to-service)
- **Contenedores:** Docker
- **Orquestación:** Kubernetes 1.35 (Kind 0.27)
- **DB:** PostgreSQL 16-alpine
- **Caché:** Redis 7-alpine
- **Ingress:** NGINX Ingress Controller

---

## 📦 Requisitos

- Docker
- [Kind](https://kind.sigs.k8s.io/) ≥ 0.20
- kubectl
- `jq` (opcional, mejora la salida del demo)

Instalación en Arch / Nyarch / EndeavourOS:

```bash
sudo pacman -S docker kubectl jq
yay -S kind-bin
```

Agrega `tourism.local` a tu `/etc/hosts`:

```bash
echo "127.0.0.1  tourism.local" | sudo tee -a /etc/hosts
```

---

## 🚀 Despliegue rápido

Cuatro comandos y tienes la plataforma corriendo:

```bash
# 1. Cluster Kind de 3 nodos + Ingress NGINX
./scripts/01-setup-cluster.sh

# 2. Construir las 4 imágenes Docker y cargarlas al cluster
./scripts/02-build-images.sh

# 3. Aplicar todos los manifests de Kubernetes
./scripts/03-deploy.sh

# 4. Demo end-to-end
./scripts/04-demo.sh
```

Verificación:

```bash
kubectl -n tourism get pods
curl http://tourism.local/
```

Documentación interactiva (Swagger UI): http://tourism.local/docs

---

## 🔌 Cómo consumir la API

Una empresa cliente se registra una sola vez y obtiene una API Key:

### 1. Registro (público, sin autenticación)

```bash
curl -X POST http://tourism.local/companies \
  -H "Content-Type: application/json" \
  -d '{"name": "Mi Agencia SAC", "email": "info@miagencia.pe"}'
```

Respuesta:
```json
{
  "id": 1,
  "name": "Mi Agencia SAC",
  "email": "info@miagencia.pe",
  "api_key": "tk_xxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "created_at": "2026-05-15T01:18:48"
}
```

### 2. Consumir el catálogo

```bash
curl http://tourism.local/tours \
  -H "X-API-Key: tk_xxxxxxxxxxxx"
```

### 3. Crear una reserva

```bash
curl -X POST http://tourism.local/bookings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: tk_xxxxxxxxxxxx" \
  -d '{
    "tour_id": 1,
    "customer_name": "Juan Perez",
    "customer_email": "juan@example.com",
    "tour_date": "2026-07-01",
    "num_people": 4
  }'
```

### 4. Listar reservas propias

```bash
curl http://tourism.local/bookings \
  -H "X-API-Key: tk_xxxxxxxxxxxx"
```

---

## 🎬 Demos y verificación

### Self-healing (autoreparación)

Kubernetes recrea pods automáticamente si mueren:

```bash
kubectl -n tourism delete pod -l app=tours-service
kubectl -n tourism get pods -l app=tours-service -w
```

### Escalado horizontal

```bash
kubectl -n tourism scale deployment tours-service --replicas=5
kubectl -n tourism get pods -l app=tours-service
```

### Verificar el cache-aside

```bash
# Primera llamada: source = "database"
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source

# Segunda inmediata: source = "cache"
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
```

### Persistencia de PostgreSQL

```bash
kubectl -n tourism delete pod postgres-0
kubectl -n tourism wait --for=condition=ready pod/postgres-0 --timeout=120s
# Los datos persisten gracias al PersistentVolumeClaim
```

### Logs en vivo

```bash
kubectl -n tourism logs -f deployment/api-gateway
```

---

## 📁 Estructura del proyecto

```
tourism-platform/
├── README.md
├── informe.typ              # Informe académico (Typst → PDF)
├── docs/
│   └── GUION_VIDEO.md
├── services/
│   ├── api-gateway/         # FastAPI - punto de entrada
│   ├── auth-service/        # FastAPI - API Keys
│   ├── tours-service/       # FastAPI - catálogo + Redis
│   └── bookings-service/    # FastAPI - reservas
├── k8s/
│   ├── base/                # Namespace, ConfigMap, Secret
│   ├── databases/           # PostgreSQL (StatefulSet) + Redis
│   ├── services/            # 4 Deployments + Services
│   └── ingress/             # Ingress NGINX
└── scripts/
    ├── 01-setup-cluster.sh
    ├── 02-build-images.sh
    ├── 03-deploy.sh
    ├── 04-demo.sh
    └── 05-apply-retry-fix.sh
```

---

## 🧩 Patrones implementados

| Patrón | Implementación |
|---|---|
| **API Gateway** | `api-gateway` centraliza autenticación y routing |
| **Multi-tenancy** | Aislamiento por `company_id` inyectado vía header |
| **Cache-aside** | `tours-service` consulta primero Redis, fallback a Postgres |
| **Service-to-service** | `bookings-service` → `tours-service` via DNS interno |
| **Self-healing** | Deployments mantienen N réplicas mediante reconciliation loop |
| **Retry con backoff** | Resiliencia ante fallos transitorios de red/DNS |
| **12-Factor App** | Configuración vía env vars (ConfigMap), logs a stdout |
| **StatefulSet + PVC** | Identidad estable y persistencia para PostgreSQL |

---

## 🔮 Trabajo futuro

- **Helm Chart** para empaquetar el despliegue parametrizado
- **Prometheus + Grafana** para observabilidad y métricas
- **Loki** para centralización de logs
- **HorizontalPodAutoscaler** para escalado automático por CPU/RPS
- **NetworkPolicy** para seguridad zero-trust entre pods
- **cert-manager + Let's Encrypt** para TLS automático
- **Service mesh** (Istio/Linkerd) para mTLS y observabilidad L7
- **Argo CD** para GitOps
- **Rate limiting** por API Key en el Gateway
- **Replicación de PostgreSQL** para alta disponibilidad

---

## 🧹 Limpieza

Para borrar todo el cluster cuando termines:

```bash
kind delete cluster --name tourism
```

Los datos persistentes (PVC) viven dentro del nodo Kind, así que se eliminan junto con el cluster.

---

## 📄 Licencia

Trabajo académico desarrollado para la UNSAAC. Uso libre con atribución.

---

<sub>Hecho con ☕ en Cusco, Perú</sub>

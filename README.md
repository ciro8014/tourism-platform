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
6. [Malla de servicios, seguridad de red y autoescalado](#6-malla-de-servicios-seguridad-de-red-y-autoescalado)
7. [Especificación de la API](#7-especificación-de-la-api)
8. [Verificación de funcionalidad](#8-verificación-de-funcionalidad)
9. [Estructura del repositorio](#9-estructura-del-repositorio)
10. [Patrones de diseño aplicados](#10-patrones-de-diseño-aplicados)
11. [Trabajo futuro](#11-trabajo-futuro)
12. [Limpieza del entorno](#12-limpieza-del-entorno)
13. [Referencias](#13-referencias)

---

## 1. Descripción del proyecto

El proyecto implementa una plataforma que expone, mediante una API REST autenticada, un catálogo de tours turísticos y un sistema de reservas que puede ser consumido por múltiples empresas clientes de manera concurrente y con aislamiento de datos.

El sistema está compuesto por cuatro microservicios independientes, contenedorizados con Docker y orquestados mediante Kubernetes. Incorpora persistencia con PostgreSQL, caché distribuido con Redis y exposición controlada al exterior a través de un Ingress Controller NGINX.

El propósito académico del trabajo es demostrar, en una implementación funcional, los conceptos fundamentales de arquitecturas cloud-native: contenedorización, orquestación declarativa, descubrimiento de servicios, persistencia de estado y patrones de comunicación entre microservicios.

En su segunda fase, el proyecto extiende esta base hacia el plano de red: incorpora una malla de servicios con cifrado mTLS automático, segmentación de red de mínimo privilegio y autoescalado dirigido por métricas de la propia malla. Con ello demuestra conceptos de seguridad en tránsito, defensa en profundidad, observabilidad y resiliencia bajo carga en entornos de microservicios.

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
                    │   (2–6 réplicas)      │  Inyecta X-Company-Id
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

En la segunda entrega, todo el tráfico entre servicios dentro del clúster se cifra con mTLS mediante la malla Linkerd, las conexiones se restringen con NetworkPolicies de mínimo privilegio y el `api-gateway` se autoescala según su tasa de peticiones (ver la sección 6).

### 2.1. Componentes

| Componente | Tipo de objeto | Réplicas | Responsabilidad |
|---|---|---:|---|
| `api-gateway` | Deployment | 2–6 | Punto único de entrada. Validación de API Key y enrutamiento hacia servicios internos. Autoescalado por RPS. |
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
| CNI (aplica NetworkPolicies) | kindnet | v20251212-v0.29.0-alpha |
| Malla de servicios | Linkerd | edge-26.6.3 |
| Gateway API (CRDs) | Gateway API | v1.2.1 |
| Autoescalado | KEDA | 2.20.1 |
| Generación de carga | k6 | — |
| Base de datos relacional | PostgreSQL | 16-alpine |
| Caché en memoria | Redis | 7-alpine |
| Ingress Controller | NGINX | latest |

## 4. Requisitos previos

El entorno de despliegue requiere los siguientes componentes instalados:

- Docker Engine ≥ 24.0
- Kind ≥ 0.20
- kubectl ≥ 1.28
- CLI de Linkerd (canal edge) y Helm ≥ 3, para la capa de red y el autoescalado
- `jq` (opcional, mejora la legibilidad de la salida del script de demostración)

En sistemas basados en Arch Linux:

```
sudo pacman -S docker kubectl jq helm
yay -S kind-bin
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
```

Adicionalmente, se requiere mapear el dominio local `tourism.local` a la interfaz de loopback:

```
echo "127.0.0.1  tourism.local" | sudo tee -a /etc/hosts
```

## 5. Procedimiento de despliegue

### 5.1. Plataforma base

El despliegue de la plataforma base se realiza mediante los scripts secuenciales del directorio `scripts/`:

```
./scripts/01-setup-cluster.sh    # Crea el clúster Kind y despliega Ingress NGINX
./scripts/02-build-images.sh     # Construye las imágenes Docker y las carga al clúster
./scripts/03-deploy.sh           # Aplica los manifiestos en orden de dependencias
./scripts/04-demo.sh             # Ejecuta una demostración end-to-end
```

El script `05-apply-retry-fix.sh` está disponible para reaplicar parches sobre los servicios cuando se modifica su código, sin requerir un nuevo despliegue completo.

### 5.2. Capa de red, seguridad y autoescalado

```
# 1. Gateway API CRDs (prerrequisito de Linkerd; --server-side por su tamaño)
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# 2. Malla de servicios Linkerd y su extensión de observabilidad
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -

# 3. Inyección de la malla en el namespace de la aplicación
kubectl annotate namespace tourism linkerd.io/inject=enabled
kubectl -n tourism rollout restart deploy

# 4. Segmentación de red (mínimo privilegio)
kubectl apply -f k8s/network/network-policies.yaml

# 5. Autoescalado dirigido por métricas de la malla
helm install keda kedacore/keda -n keda --create-namespace
kubectl apply -f k8s/autoscaling/keda-linkerd-authz.yaml
kubectl apply -f k8s/autoscaling/keda-scaledobject.yaml
```

Una vez ejecutado el despliegue, el estado del clúster puede verificarse con:

```
kubectl -n tourism get pods
kubectl -n tourism get services
curl http://tourism.local/
```

La documentación interactiva generada automáticamente por FastAPI está disponible en `http://tourism.local/docs`.

## 6. Malla de servicios, seguridad de red y autoescalado

La segunda entrega incorpora tres capacidades sobre la plataforma base, sin modificar la lógica de los microservicios.

### 6.1. Malla de servicios y mTLS (Linkerd)

Se instaló Linkerd en su canal `edge` junto con la extensión `linkerd-viz`, que aporta un dashboard y un Prometheus propio. La malla se habilita anotando el namespace con `linkerd.io/inject=enabled`; tras reiniciar los workloads, cada pod ejecuta un proxy adicional (pasa de 1/1 a 2/2 contenedores). A partir de ese momento, todo el tráfico entre servicios viaja cifrado con TLS mutuo, sin cambios en el código ni en las imágenes. PostgreSQL (5432) y Redis (6379) se tratan como puertos opacos por defecto.

La evidencia de cifrado se obtiene con:

```
linkerd viz edges -n tourism deployment
```

donde la columna `SECURED` confirma las conexiones protegidas con mTLS.

### 6.2. Segmentación de red (NetworkPolicies)

Se aplicó una política `default-deny` de ingreso y un conjunto de reglas de mínimo privilegio que habilitan únicamente los flujos legítimos de la aplicación. Estas políticas son aplicadas de forma nativa por kindnet, por lo que no fue necesario instalar un CNI adicional como Calico. Entre pods incorporados a la malla las reglas filtran por identidad de origen, ya que el tráfico proxy-a-proxy de Linkerd viaja por el puerto `4143` y no por el puerto del servicio.

| Origen permitido | Destino |
|---|---|
| Ingress NGINX | api-gateway |
| api-gateway | auth-service, tours-service, bookings-service |
| bookings-service | tours-service |
| auth / tours / bookings | postgres |
| tours-service | redis |
| linkerd-viz (Prometheus) | todos (puerto admin 4191/4190) |

El aislamiento se verifica lanzando un pod no autorizado y comprobando que no alcanza los destinos sensibles:

```
kubectl -n tourism run netcheck --image=nicolaka/netshoot --restart=Never \
  --annotations="linkerd.io/inject=disabled" --rm -it -- \
  bash -c 'nc -zv -w3 postgres-service 5432; nc -zv -w3 redis-service 6379; nc -zv -w3 tours-service 8000'
```

Las tres conexiones deben expirar por tiempo de espera (timeout).

### 6.3. Autoescalado (KEDA)

El `api-gateway` —identificado como cuello de botella del sistema mediante la observabilidad de la malla— se autoescala según su tasa de peticiones de entrada (RPS), que KEDA lee del Prometheus de Linkerd. El `ScaledObject` consulta la métrica:

```
sum(rate(request_total{namespace="tourism", deployment="api-gateway", direction="inbound"}[1m]))
```

con un mínimo de 2 réplicas, un máximo de 6 y un umbral de 10 RPS por réplica. Dado que `linkerd-viz` protege su Prometheus con una política de acceso propia, se autorizó a KEDA mediante una `AuthorizationPolicy` y una `NetworkAuthentication`, sin incorporarlo a la malla.

El comportamiento se verifica observando el HPA y las réplicas mientras se aplica carga:

```
watch kubectl -n tourism get hpa,pods -l app=api-gateway
k6 run loadtest/scale-gateway.js
```

### 6.4. Resultados

| Aspecto | Resultado |
|---|---|
| Cifrado mTLS | Confirmado en todas las conexiones entre servicios (columna SECURED). |
| Sobrecosto de la malla | Despreciable para la carga evaluada. |
| Cuello de botella | Localizado en el `api-gateway` (P50 ≈ 95 ms frente a 1–5 ms del resto). |
| Autoescalado | 2 → 5 réplicas bajo carga y retorno a 2; 0 errores. |
| Hallazgo principal | El autoescalado preserva la disponibilidad, pero no reduce la latencia (su raíz es arquitectónica, en el `api-gateway`). |

El análisis completo, incluidos los problemas de integración encontrados y su resolución, se documenta en el informe del directorio `informe-v2/`.

## 7. Especificación de la API

Todas las rutas (excepto el registro de empresas) requieren el header `X-API-Key` con un token válido.

### 7.1. Registro de empresa cliente

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

### 7.2. Consulta del catálogo

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

### 7.3. Creación de reserva

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

### 7.4. Listado de reservas del tenant

```
GET /bookings
X-API-Key: tk_xxxxxxxxxxxx
```

Solo se devuelven las reservas asociadas a la empresa identificada por la API Key.

## 8. Verificación de funcionalidad

### 8.1. Autorreparación (self-healing)

Al eliminar un pod, el controlador de Kubernetes recrea automáticamente una réplica para mantener el estado declarado:

```
kubectl -n tourism delete pod -l app=tours-service
kubectl -n tourism get pods -l app=tours-service -w
```

### 8.2. Escalado horizontal

El número de réplicas puede modificarse en caliente sin interrupción del servicio:

```
kubectl -n tourism scale deployment tours-service --replicas=5
kubectl -n tourism get pods -l app=tours-service
```

### 8.3. Comportamiento del caché

La primera consulta debe reportar `source: "database"` y las subsiguientes `source: "cache"`:

```
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
curl -s http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
```

### 8.4. Persistencia de datos

Al eliminar y recrear el pod de PostgreSQL, los datos sobreviven gracias al PersistentVolumeClaim:

```
kubectl -n tourism delete pod postgres-0
kubectl -n tourism wait --for=condition=ready pod/postgres-0 --timeout=120s
kubectl -n tourism exec -it postgres-0 -- psql -U tourism -d tourism_db \
  -c "SELECT COUNT(*) FROM bookings;"
```

La verificación de las capacidades de red (mTLS, aislamiento y autoescalado) se describe en la sección 6.

## 9. Estructura del repositorio

```
tourism-platform/
├── README.md
├── docs/
│   └── GUION_VIDEO.md
├── informe-v2/                 Informe académico de la segunda entrega (Typst + PDF)
│   ├── main.typ
│   ├── plantilla.typ
│   ├── capitulos/
│   └── imagenes/
├── services/
│   ├── api-gateway/            Servicio: punto de entrada
│   ├── auth-service/           Servicio: autenticación
│   ├── tours-service/          Servicio: catálogo
│   └── bookings-service/       Servicio: reservas
├── k8s/
│   ├── base/                   Namespace, ConfigMap, Secret
│   ├── databases/              Manifiestos de PostgreSQL y Redis
│   ├── services/               Deployments y Services de la aplicación
│   ├── ingress/                Reglas de enrutamiento HTTP
│   ├── network/                NetworkPolicies de mínimo privilegio
│   └── autoscaling/            KEDA: ScaledObject y autorización de acceso a Prometheus
├── loadtest/
│   ├── baseline-tours.js       Carga de referencia (línea base)
│   └── scale-gateway.js        Carga para ejercitar el autoescalado
└── scripts/
    ├── 01-setup-cluster.sh
    ├── 02-build-images.sh
    ├── 03-deploy.sh
    ├── 04-demo.sh
    └── 05-apply-retry-fix.sh
```

Cada subdirectorio de `services/` contiene un `Dockerfile`, el código fuente del servicio (`main.py`) y su archivo de dependencias (`requirements.txt`).

## 10. Patrones de diseño aplicados

| Patrón | Implementación en el proyecto |
|---|---|
| API Gateway | El servicio `api-gateway` actúa como punto único de ingreso, centralizando autenticación y enrutamiento. |
| Multi-tenancy | Cada empresa cliente se identifica por una API Key única. El campo `company_id` se inyecta vía header y filtra las consultas de la base de datos. |
| Cache-aside | `tours-service` consulta Redis antes que PostgreSQL. En caso de miss, recupera de la base de datos y popula el caché. Las escrituras invalidan la entrada cacheada. |
| Service-to-service discovery | La comunicación entre servicios utiliza el DNS interno del clúster (`http://tours-service:8000`), eliminando la necesidad de configuración de IPs estáticas. |
| Self-healing | Los Deployments mantienen un número declarado de réplicas mediante el reconciliation loop del controlador. |
| Retry con backoff | Las llamadas a dependencias externas (base de datos, otros servicios) implementan reintentos con espera incremental para tolerar fallos transitorios. |
| Sidecar (service mesh) | El proxy de Linkerd se inyecta junto a cada servicio, aportando mTLS y métricas sin modificar la aplicación. |
| Zero-trust networking | NetworkPolicies con `default-deny` y autorización explícita de la malla: ningún flujo se permite por omisión. |
| Autoescalado dirigido por métricas | KEDA ajusta las réplicas del `api-gateway` según la tasa de peticiones reportada por la malla. |
| Twelve-Factor App | Configuración externalizada mediante variables de entorno (ConfigMap), logs dirigidos a stdout, procesos sin estado local. |
| StatefulSet con PVC | PostgreSQL mantiene identidad estable y almacenamiento persistente entre reinicios. |

## 11. Trabajo futuro

A partir de la base implementada, las siguientes extensiones representan rutas naturales de evolución hacia un sistema completo y operable:

- **Pool de conexiones reutilizable en el `api-gateway`**, reemplazando la creación de un cliente HTTP por petición, para corregir de raíz la latencia observada bajo carga.
- **Políticas de egreso y autorización a nivel de aplicación (L7)** mediante `AuthorizationPolicy` de Linkerd, restringiendo no solo qué pods se comunican, sino qué rutas y métodos HTTP pueden invocarse.
- **Grafana y alertas** sobre el Prometheus de la malla, para un monitoreo continuo de latencia, tasa de éxito y saturación.
- **Resiliencia de la malla**: configuración de timeouts, reintentos y circuit breaking a nivel de Linkerd.
- **cert-manager con Let's Encrypt** para gestión automática de certificados TLS en el Ingress.
- **Helm Chart** para empaquetar el despliegue de manera parametrizable y versionada.
- **Loki** para centralización y búsqueda de logs estructurados.
- **GitOps con Argo CD** para sincronización continua del clúster con el estado declarado en este repositorio.
- **Replicación de PostgreSQL** para alta disponibilidad de la capa de persistencia.
- **Rate limiting por API Key** en el Gateway para protección contra abuso y soporte de modelos de pricing por tier.

## 12. Limpieza del entorno

Para eliminar completamente el clúster y los recursos asociados:

```
kind delete cluster --name tourism
```

Los volúmenes persistentes residen dentro de los nodos de Kind y se eliminan junto con el clúster.

## 13. Referencias

1. The Kubernetes Authors. *Kubernetes Documentation*. https://kubernetes.io/docs/
2. Docker Inc. *Docker Documentation*. https://docs.docker.com/
3. Ramírez, S. *FastAPI Documentation*. https://fastapi.tiangolo.com/
4. The Kind Authors. *Kind: Kubernetes in Docker*. https://kind.sigs.k8s.io/
5. Linkerd Authors. *Linkerd Documentation*. https://linkerd.io/2/
6. Morgan, W. *Announcing Linkerd 2.15: a new model for stable releases*. Buoyant. https://www.buoyant.io/blog/announcing-linkerd-2-15-vm-workloads-spiffe-identities
7. KEDA Authors. *KEDA — Kubernetes Event-driven Autoscaling*. https://keda.sh/docs/
8. The Kubernetes Authors. *Network Policies*. https://kubernetes.io/docs/concepts/services-networking/network-policies/
9. Newman, S. (2021). *Building Microservices: Designing Fine-Grained Systems* (2nd ed.). O'Reilly Media.
10. Burns, B., Beda, J., Hightower, K., & Evenson, L. (2022). *Kubernetes: Up and Running* (3rd ed.). O'Reilly Media.
11. Richardson, C. (2018). *Microservices Patterns: With Examples in Java*. Manning Publications.
12. Wiggins, A. *The Twelve-Factor App*. https://12factor.net/
13. NGINX Inc. *NGINX Ingress Controller Documentation*. https://kubernetes.github.io/ingress-nginx/

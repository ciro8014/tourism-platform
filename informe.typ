// Informe — Tópicos Avanzados en Redes
// Plataforma multi-tenant sobre Kubernetes
// Compilar con: typst compile informe.typ

#set document(
  title: "Plataforma multi-tenant sobre Kubernetes",
  author: "Cesar Ciro Olarte Bautista",
)

#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 2.5cm),
  numbering: "1 / 1",
  number-align: center,
)

#set text(
  font: "New Computer Modern",
  size: 11pt,
  lang: "es",
)

#set par(justify: true, leading: 0.7em, first-line-indent: 0pt)
#set heading(numbering: "1.")

#show heading.where(level: 1): it => [
  #pagebreak(weak: true)
  #set text(size: 18pt, weight: "bold")
  #v(1em)
  #it
  #v(0.5em)
]

#show heading.where(level: 2): it => [
  #set text(size: 13pt, weight: "bold")
  #v(0.8em)
  #it
  #v(0.2em)
]

#show heading.where(level: 3): it => [
  #set text(size: 11pt, weight: "bold", style: "italic")
  #v(0.5em)
  #it
]

#show raw.where(block: true): block.with(
  fill: rgb("#f5f5f5"),
  inset: 8pt,
  radius: 4pt,
  width: 100%,
)

#show raw.where(block: false): box.with(
  fill: rgb("#f0f0f0"),
  inset: (x: 3pt, y: 1pt),
  outset: (y: 2pt),
  radius: 2pt,
)

#show link: set text(fill: rgb("#0066cc"))

// ═══════════════════════════════════════
// PORTADA
// ═══════════════════════════════════════

#align(center)[
  // #v(3cm)
  
  #v(1cm)
  #text(size: 14pt)[*UNIVERSIDAD NACIONAL DE SAN ANTONIO ABAD DEL CUSCO*]

  #v(0.3cm)
  #text(size: 12pt)[Facultad de Ingeniería Eléctrica, Electrónica, Informática y Mecánica]

  #v(0.3cm)
  #text(size: 12pt)[Escuela Profesional de Ingeniería Informática y de Sistemas]

  #image("Escudo_UNSAAC.png", width: 6cm)


  #text(size: 16pt, weight: "bold")[
    Plataforma multi-tenant para gestión turística \
    desplegada en Kubernetes con microservicios
  ]

  #v(0.5cm)
  #text(size: 12pt, style: "italic")[
    Implementación de una arquitectura cloud-native \
    con contenedorización, orquestación y exposición \
    controlada de APIs hacia clientes externos
  ]

  #v(1cm)
  #table(
    columns: (auto, auto),
    align: left,
    stroke: none,
    [*Asignatura:*], [Tópicos Avanzados en Redes (Dirigido)],
    [*Semestre:*], [2026-I],
    [*Estudiante:*], [Cesar Ciro Olarte Bautista],
    [*Código:*], [200785],
    [*Fecha:*], [Mayo 2026],
  )

  #v(1fr)
  Cusco -- Perú
]

// ═══════════════════════════════════════
// RESUMEN
// ═══════════════════════════════════════

= Resumen

El presente informe documenta el diseño, implementación y despliegue de una *plataforma multi-tenant para gestión turística* construida bajo el paradigma de microservicios y desplegada sobre un clúster de Kubernetes. La plataforma expone, mediante una API REST autenticada por API Key, un catálogo de tours y un sistema de reservas que puede ser consumido por múltiples empresas clientes de forma aislada.

La solución integra cuatro microservicios independientes desarrollados en Python con FastAPI, contenedorizados con Docker y orquestados por Kubernetes (distribución Kind). Se incorporan dos servicios de almacenamiento --- PostgreSQL para persistencia y Redis para caché --- y se expone el sistema al exterior mediante un Ingress NGINX con un API Gateway como punto único de entrada.

El proyecto demuestra patrones de arquitectura de la industria como _API Gateway_, _Cache-aside_, _Service Discovery_ vía DNS interno, _Multi-tenancy_ por API Key, y aislamiento de estado con `StatefulSet` y `PersistentVolumeClaim`.

// ═══════════════════════════════════════
// INTRODUCCIÓN
// ═══════════════════════════════════════

= Introducción

== Contexto y problema

En el sector turístico peruano, especialmente en Cusco, conviven decenas de agencias pequeñas que requieren acceso a información actualizada sobre tours y a infraestructura de reservas. Construir y mantener esta infraestructura individualmente resulta económicamente inviable para cada agencia. Surge entonces la necesidad de una *plataforma compartida* (Backend-as-a-Service) que ofrezca:

- Acceso autenticado por agencia (multi-tenant)
- Catálogo unificado de tours
- Sistema centralizado de reservas con aislamiento de datos
- API documentada y consumible programáticamente
- Alta disponibilidad y escalabilidad horizontal

== Justificación arquitectónica

Una arquitectura monolítica tradicional presenta limitaciones críticas para este caso de uso:

- *Acoplamiento*: un fallo en el módulo de reservas afecta la consulta de catálogo.
- *Escalabilidad uniforme*: no es posible escalar selectivamente la parte del sistema que recibe más carga.
- *Despliegues*: cualquier cambio implica redesplegar todo el sistema.

La adopción de *microservicios desplegados en Kubernetes* mitiga estos problemas al permitir:

- Despliegue independiente de cada componente
- Escalado horizontal selectivo según la carga real
- Aislamiento de fallos (un servicio caído no tumba todo el sistema)
- Autoreparación automática mediante el control loop de Kubernetes

== Objetivos

=== Objetivo general

Diseñar, implementar y desplegar una plataforma de microservicios sobre Kubernetes que demuestre los conceptos de contenedorización, orquestación, descubrimiento de servicios y exposición controlada de APIs hacia consumidores externos.

=== Objetivos específicos

+ Implementar al menos tres microservicios independientes con responsabilidades acotadas.
+ Empaquetar cada servicio como imagen Docker reproducible.
+ Desplegar todo el sistema en un clúster Kubernetes local (Kind) con persistencia de datos.
+ Exponer la plataforma al exterior mediante un Ingress y un API Gateway con autenticación.
+ Implementar al menos un patrón de optimización (caché distribuido) y demostrar resiliencia ante fallos.

// ═══════════════════════════════════════
// MARCO TEÓRICO
// ═══════════════════════════════════════

= Marco teórico

== Contenedores y Docker

Un *contenedor* es un proceso de Linux aislado mediante `namespaces` (vista del filesystem, PIDs, red, hostname) y `cgroups` (límites de CPU y memoria) del kernel del host. A diferencia de una máquina virtual, un contenedor *no incluye un sistema operativo completo*, sino que comparte el kernel del host. Esto se traduce en:

- *Arranque*: milisegundos vs minutos.
- *Tamaño*: megabytes vs gigabytes.
- *Densidad*: cientos de contenedores por host vs decenas de VMs.

*Docker* es la plataforma que populariza esta tecnología en 2013, proveyendo herramientas para construir imágenes (`docker build`), distribuirlas (registries) y ejecutarlas (`docker run`).

== Microservicios

El estilo arquitectónico de _microservicios_ propone descomponer un sistema en servicios pequeños y autónomos, cada uno responsable de una capacidad de negocio específica, comunicados mediante protocolos livianos (típicamente HTTP/REST o gRPC). Cada servicio:

- Tiene su propio ciclo de despliegue.
- Puede usar su propio stack tecnológico.
- Posee su propio almacenamiento (idealmente).
- Es desplegado y escalado independientemente.

== Kubernetes

*Kubernetes* (k8s) es un orquestador de contenedores de código abierto originalmente desarrollado por Google. Su modelo es *declarativo*: el usuario describe el _estado deseado_ del sistema mediante manifiestos YAML, y Kubernetes ejecuta un _reconciliation loop_ continuo para llevar el estado real hacia el deseado.

=== Arquitectura

Un clúster Kubernetes se compone de:

- *Control Plane*: API Server (punto único de ingreso), `etcd` (base de datos clave-valor distribuida), Scheduler (asignación de pods a nodos), Controller Manager (ejecuta los reconciliation loops).
- *Nodos worker*: ejecutan los workloads del usuario mediante `kubelet` (agente) y un _container runtime_ (containerd, CRI-O).

=== Objetos fundamentales

#table(
  columns: (1fr, 3fr),
  stroke: 0.5pt + gray,
  inset: 6pt,
  [*Objeto*], [*Función*],
  [`Pod`], [Unidad mínima de despliegue. Envoltorio de uno o varios contenedores que comparten red y storage.],
  [`Deployment`], [Garantiza N réplicas vivas de un pod. Maneja rolling updates y rollbacks.],
  [`Service`], [Provee IP virtual estable, DNS interno y balanceo de carga sobre un conjunto de pods.],
  [`ConfigMap`], [Configuración no sensible (URLs, parámetros) inyectada como variables de entorno o archivos.],
  [`Secret`], [Equivalente al ConfigMap para datos sensibles (credenciales, tokens).],
  [`Ingress`], [Reglas de enrutamiento HTTP/HTTPS desde el exterior hacia Services.],
  [`StatefulSet`], [Variante de Deployment para servicios con estado (identidad estable, almacenamiento persistente por pod).],
  [`PersistentVolumeClaim`], [Petición de almacenamiento que sobrevive a la muerte de pods.],
)

// ═══════════════════════════════════════
// ARQUITECTURA
// ═══════════════════════════════════════

= Arquitectura propuesta

== Visión general

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

== Componentes

=== Microservicios

+ *`api-gateway`*: punto único de entrada. Valida la API Key contra `auth-service` y enruta hacia los servicios internos inyectando el header `X-Company-Id` que identifica al tenant.

+ *`auth-service`*: registro de empresas clientes. Genera API Keys aleatorias criptográficamente seguras (`secrets.token_urlsafe(32)`), almacenando únicamente su hash SHA-256 en la base de datos.

+ *`tours-service`*: catálogo de tours. Implementa el patrón _Cache-aside_ con Redis (TTL de 60 segundos) para minimizar la carga sobre PostgreSQL en operaciones de lectura.

+ *`bookings-service`*: gestión de reservas. Antes de persistir una reserva valida la existencia del tour mediante una llamada _service-to-service_ a `tours-service` por DNS interno.

=== Almacenamiento

- *PostgreSQL 16* desplegado como `StatefulSet` con `PersistentVolumeClaim` de 1 GiB. Garantiza identidad estable del pod (`postgres-0`) y persistencia de datos ante reinicios.
- *Redis 7* como `Deployment` (estado efímero aceptable, ya que el caché se reconstruye automáticamente).

=== Red

- *DNS interno*: provisto por CoreDNS, permite que los servicios se descubran por nombre (`http://tours-service:8000`).
- *Service Discovery*: cada microservicio expone un objeto `Service` con `ClusterIP`, accesible solo dentro del clúster.
- *Ingress NGINX*: actúa como reverse proxy desde `tourism.local` hacia el `api-gateway`.

== Patrones aplicados

#table(
  columns: (1fr, 3fr),
  stroke: 0.5pt + gray,
  inset: 6pt,
  [*Patrón*], [*Implementación en el proyecto*],
  [API Gateway], [`api-gateway` centraliza autenticación y enrutamiento.],
  [Multi-tenancy], [Cada empresa tiene un `company_id` único; las reservas se filtran automáticamente por este campo.],
  [Cache-aside], [`tours-service` consulta primero Redis; si hay miss, va a la DB y guarda en caché. Invalida en escrituras.],
  [Service-to-service], [`bookings-service` llama a `tours-service` por DNS interno (`http://tours-service:8000`).],
  [Self-healing], [Cada Deployment garantiza N réplicas; pods muertos son recreados automáticamente.],
  [Resiliencia al arranque], [Los servicios implementan _retry con espera_ al conectar con DB/Redis (hasta 30 intentos con 2s de espera).],
  [Twelve-Factor], [Configuración vía variables de entorno (ConfigMap), logs a stdout, procesos stateless.],
)

// ═══════════════════════════════════════
// IMPLEMENTACIÓN
// ═══════════════════════════════════════

= Implementación

== Stack tecnológico

#table(
  columns: (1fr, 2fr),
  stroke: 0.5pt + gray,
  inset: 6pt,
  [*Categoría*], [*Tecnología*],
  [Lenguaje], [Python 3.12],
  [Framework web], [FastAPI 0.115 (async)],
  [Servidor ASGI], [Uvicorn 0.32],
  [Driver PostgreSQL], [`asyncpg` 0.30],
  [Cliente Redis], [`redis-py` 5.1 (async)],
  [Cliente HTTP], [`httpx` 0.27 (async, para s2s)],
  [Validación], [Pydantic 2.9],
  [Container runtime], [Docker (con `containerd` en los nodos Kind)],
  [Orquestador], [Kubernetes 1.35 (Kind 0.27)],
  [Base de datos], [PostgreSQL 16-alpine],
  [Caché], [Redis 7-alpine],
  [Ingress Controller], [NGINX (controller oficial de Kubernetes)],
)

== Estructura del proyecto

```
tourism-platform/
├── services/
│   ├── api-gateway/        # FastAPI - punto de entrada
│   ├── auth-service/       # FastAPI - API Keys
│   ├── tours-service/      # FastAPI - catálogo + Redis
│   └── bookings-service/   # FastAPI - reservas
├── k8s/
│   ├── base/               # Namespace, ConfigMap, Secret
│   ├── databases/          # PostgreSQL (StatefulSet) + Redis
│   ├── services/           # 4 Deployments + Services
│   └── ingress/            # Ingress NGINX
└── scripts/
    ├── 01-setup-cluster.sh
    ├── 02-build-images.sh
    ├── 03-deploy.sh
    └── 04-demo.sh
```

== Detalles destacables del código

=== Hashing de API Keys

Las API Keys se generan con `secrets.token_urlsafe(32)` (256 bits de entropía) y se almacenan únicamente como hash SHA-256, siguiendo el principio de _defense in depth_: aunque la base de datos se filtre, las claves originales no se exponen.

```python
def hash_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()
```

=== Cache-aside en `tours-service`

```python
@app.get("/tours")
async def list_tours():
    cached = await cache.get("tours:all")
    if cached:
        return {"source": "cache", "data": json.loads(cached)}

    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM tours ORDER BY id")
    data = [...]
    await cache.setex("tours:all", CACHE_TTL, json.dumps(data))
    return {"source": "database", "data": data}
```

El campo `source` en la respuesta hace explícito el origen de los datos, facilitando la verificación del comportamiento en tiempo de ejecución.

=== Retry con backoff en el Gateway

```python
async def fetch_with_retry(client, method, url, **kwargs):
    last_err = None
    for attempt in range(3):
        try:
            return await client.request(method, url, **kwargs)
        except httpx.RequestError as e:
            last_err = e
            if attempt < 2:
                await asyncio.sleep(0.3 * (2 ** attempt))
    raise HTTPException(503, f"Servicio downstream no disponible: {last_err}")
```

Este patrón mitiga fallos transitorios de red entre microservicios, comunes en entornos dinámicos como Kubernetes donde los pods cambian de IP.

== Manifests destacables

=== StatefulSet de PostgreSQL

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-service
  replicas: 1
  ...
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

El uso de `volumeClaimTemplates` provisiona automáticamente un PVC por cada pod, garantizando que `postgres-0` siempre reciba el mismo volumen al recrearse.

=== Probes en cada Deployment

```yaml
readinessProbe:
  httpGet: { path: /health, port: 8000 }
  initialDelaySeconds: 5
  periodSeconds: 5
livenessProbe:
  httpGet: { path: /health, port: 8000 }
  initialDelaySeconds: 15
  periodSeconds: 10
```

La `readinessProbe` controla si el pod recibe tráfico del Service; la `livenessProbe` decide si el contenedor debe ser reiniciado.

// ═══════════════════════════════════════
// DESPLIEGUE Y PRUEBAS
// ═══════════════════════════════════════

= Despliegue y verificación

== Procedimiento de despliegue

El despliegue se automatiza en cuatro scripts secuenciales:

+ `01-setup-cluster.sh`: crea un cluster Kind de 3 nodos (1 control-plane + 2 workers) e instala el Ingress NGINX Controller.
+ `02-build-images.sh`: construye las 4 imágenes Docker y las carga al cluster con `kind load docker-image`.
+ `03-deploy.sh`: aplica los manifests YAML en orden (namespace → DBs → servicios → ingress) con `kubectl wait` entre etapas para garantizar dependencias.
+ `04-demo.sh`: ejecuta una demostración end-to-end consumiendo la API como una empresa cliente.

== Verificación de funcionalidad

Tras el despliegue, todos los pods pasan al estado `Running`:

```
NAME                                READY   STATUS    RESTARTS   AGE
api-gateway-xxxxxxxxxx-xxxxx        1/1     Running   0          2m
auth-service-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
bookings-service-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
postgres-0                          1/1     Running   0          3m
redis-xxxxxxxxxx-xxxxx              1/1     Running   0          3m
tours-service-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
```

== Resultados de la demostración

La ejecución de `04-demo.sh` evidencia que la plataforma responde correctamente a:

+ *Registro de empresa*: devuelve API Key generada aleatoriamente.
+ *Rechazo de petición sin autenticación*: HTTP 422.
+ *Consulta de catálogo* (primera vez): `source: database`.
+ *Consulta de catálogo* (segunda vez): `source: cache`, evidenciando el funcionamiento del Cache-aside.
+ *Creación de reserva*: bookings-service valida el tour vía s2s y persiste.
+ *Listado de reservas*: solo las del tenant autenticado.

== Demostraciones de capacidades de Kubernetes

=== Self-healing

```bash
$ kubectl -n tourism delete pod -l app=tours-service
pod "tours-service-xxxxxxxxxx-xxxxx" deleted
```

A los pocos segundos, Kubernetes recrea automáticamente el pod, manteniendo siempre las 2 réplicas declaradas.

=== Escalado horizontal

```bash
$ kubectl -n tourism scale deployment tours-service --replicas=5
deployment.apps/tours-service scaled
```

Se levantan 3 réplicas adicionales en cuestión de segundos, distribuidas automáticamente entre los nodos disponibles.

=== Persistencia de PostgreSQL

```bash
$ kubectl -n tourism delete pod postgres-0
$ kubectl -n tourism wait --for=condition=ready pod/postgres-0
$ kubectl -n tourism exec -it postgres-0 -- psql -U tourism -d tourism_db \
    -c "SELECT * FROM bookings;"
```

Los datos persisten gracias al `PersistentVolumeClaim` montado en `/var/lib/postgresql/data`.

// ═══════════════════════════════════════
// CONCLUSIONES
// ═══════════════════════════════════════

= Conclusiones

+ La implementación demuestra que es viable exponer servicios internos de una empresa como una *API consumible por terceros* siguiendo prácticas estándar de la industria, aún en un entorno local con recursos limitados.

+ El paradigma *declarativo* de Kubernetes simplifica enormemente la gestión operacional: una vez expresado el estado deseado en YAML, el sistema lo mantiene automáticamente sin intervención manual.

+ La separación en *microservicios* introduce complejidad operacional adicional (4 imágenes Docker, 4 Deployments, manejo de comunicación inter-servicios) pero permite escalado y mantenimiento selectivos.

+ Los *patrones de resiliencia* (retry, probes, self-healing) son críticos en sistemas distribuidos. El proyecto evidenció en la práctica fallos transitorios de DNS interno que motivaron la incorporación de retry en el código de los servicios.

+ El uso de *DNS interno* de Kubernetes elimina por completo la necesidad de configurar manualmente direcciones IP entre microservicios, materializando el principio de _service discovery_ automático.

= Trabajo futuro

A partir de la base implementada, las siguientes extensiones representan rutas naturales de evolución:

#table(
  columns: (1fr, 3fr),
  stroke: 0.5pt + gray,
  inset: 6pt,
  [*Mejora*], [*Justificación*],
  [Helm Chart], [Empaquetado parametrizable y versionado del despliegue completo.],
  [Prometheus + Grafana], [Observabilidad: métricas de cluster, servicios y aplicación.],
  [Loki], [Centralización y búsqueda de logs.],
  [HorizontalPodAutoscaler], [Escalado automático basado en CPU/memoria/RPS.],
  [NetworkPolicy], [Restricción de tráfico inter-pod según el principio de menor privilegio.],
  [cert-manager + Let's Encrypt], [TLS automático para producción.],
  [Service mesh (Istio/Linkerd)], [mTLS automático entre servicios y observabilidad L7.],
  [Argo CD (GitOps)], [Despliegue continuo: el cluster refleja el estado de un repositorio Git.],
  [Replicación PostgreSQL], [Alta disponibilidad de la base de datos.],
  [Rate limiting por API Key], [Protección contra abuso y modelos de pricing por tier.],
)

// ═══════════════════════════════════════
// REFERENCIAS
// ═══════════════════════════════════════

= Referencias

#set par(first-line-indent: 0pt, hanging-indent: 1em)

+ The Kubernetes Authors. _Kubernetes Documentation_. https://kubernetes.io/docs/

+ Docker Inc. _Docker Documentation_. https://docs.docker.com/

+ Sebastián Ramírez. _FastAPI Documentation_. https://fastapi.tiangolo.com/

+ The Kind Authors. _Kind: Kubernetes in Docker_. https://kind.sigs.k8s.io/

+ Newman, S. (2021). _Building Microservices: Designing Fine-Grained Systems_ (2nd ed.). O'Reilly Media.

+ Burns, B., Beda, J., Hightower, K., & Evenson, L. (2022). _Kubernetes: Up and Running_ (3rd ed.). O'Reilly Media.

+ Richardson, C. (2018). _Microservices Patterns_. Manning Publications.

+ The Twelve-Factor App. https://12factor.net/

+ NGINX Inc. _NGINX Ingress Controller Documentation_. https://kubernetes.github.io/ingress-nginx/

= Anexos

== A. Repositorio del proyecto

Código fuente completo, manifests, scripts y documentación: \
#text(style: "italic")[(URL del repositorio --- a completar al publicar)]

== B. Comandos clave de operación

```bash
# Crear cluster + Ingress
./scripts/01-setup-cluster.sh

# Construir y cargar imágenes
./scripts/02-build-images.sh

# Desplegar todo
./scripts/03-deploy.sh

# Demo end-to-end
./scripts/04-demo.sh

# Inspección
kubectl -n tourism get all
kubectl -n tourism logs -f deployment/api-gateway
kubectl -n tourism describe pod <pod-name>

# Limpieza
kind delete cluster --name tourism
```

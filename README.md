# Tourism Platform — Microservicios sobre Kubernetes

**Curso:** Tópicos Avanzados en Redes — UNSAAC 2026-I
**Autor:** Cesar Ciro Olarte Bautista (200785)

Plataforma multi-tenant que expone un catálogo de tours turísticos y un sistema de reservas como APIs consumibles por empresas externas. Implementada como un conjunto de microservicios desplegados en Kubernetes, con base de datos persistente, caché en memoria, autenticación por API Key y un Gateway como punto único de entrada.

---

## 1. Arquitectura

```
                                    INTERNET / Empresas clientes
                                              │
                                              ▼
                                   ┌──────────────────────┐
                                   │   Ingress NGINX      │   tourism.local:80
                                   └──────────┬───────────┘
                                              │
                                   ┌──────────▼───────────┐
                                   │    API Gateway       │   FastAPI
                                   │  (valida X-API-Key)  │   2 réplicas
                                   └──┬────────┬────────┬─┘
                       ┌──────────────┘        │        └──────────────┐
                       │                       │                       │
              ┌────────▼────────┐    ┌─────────▼────────┐    ┌─────────▼────────┐
              │  auth-service   │    │  tours-service   │    │ bookings-service │
              │  (API Keys)     │    │  (catálogo)      │    │  (reservas)      │
              │  2 réplicas     │    │  2 réplicas      │    │  2 réplicas      │
              └────────┬────────┘    └────┬──────┬──────┘    └────────┬─────────┘
                       │                  │      │                    │
                       │                  │      └─── tours-service ──┤
                       │                  │           (service-to-    │
                       │                  │            service call)  │
                       │                  ▼                           │
                       │         ┌─────────────────┐                  │
                       │         │  Redis Cache    │                  │
                       │         │  (TTL 60s)      │                  │
                       │         └─────────────────┘                  │
                       │                                              │
                       └───────────────┬──────────────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │   PostgreSQL    │   StatefulSet
                              │   (1Gi PVC)     │   1 réplica
                              └─────────────────┘
```

### Componentes

| Componente | Tipo | Réplicas | Función |
|---|---|---|---|
| `api-gateway` | Deployment | 2 | Punto único de entrada, valida API Keys, hace ruteo |
| `auth-service` | Deployment | 2 | Registra empresas, valida API Keys |
| `tours-service` | Deployment | 2 | CRUD de tours, usa Redis como cache-aside |
| `bookings-service` | Deployment | 2 | CRUD de reservas, llama a tours-service vía DNS interno |
| `postgres` | StatefulSet | 1 | Base de datos persistente (PVC 1Gi) |
| `redis` | Deployment | 1 | Caché en memoria |
| `ingress-nginx` | DaemonSet | — | Exposición externa hacia tourism.local |

### Patrones implementados

- **API Gateway** como punto único de entrada y autenticación centralizada
- **Multi-tenant**: cada empresa cliente tiene su propia API Key, sus reservas están aisladas por `company_id`
- **Cache-aside** en `tours-service` con Redis (TTL configurable, invalidación en escrituras)
- **Service-to-service** via DNS interno de Kubernetes (`bookings-service` llama a `tours-service` por su nombre de Service)
- **StatefulSet + PVC** para que PostgreSQL sobreviva a reinicios del pod
- **ConfigMap + Secret** para configuración externalizada (12-factor)
- **Liveness y Readiness probes** en todos los servicios
- **Resource requests y limits** para evitar el "noisy neighbor problem"

---

## 2. Requisitos previos

- Docker
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) >= 0.20
- kubectl
- jq (opcional, para que el script de demo se vea mejor)

```bash
# Arch / Endeavour / Nyarch
sudo pacman -S docker kubectl
yay -S kind-bin
```

Agregar `tourism.local` al `/etc/hosts`:

```bash
echo "127.0.0.1  tourism.local" | sudo tee -a /etc/hosts
```

---

## 3. Despliegue (4 pasos)

```bash
# 1. Crear cluster Kind de 3 nodos con Ingress
./scripts/01-setup-cluster.sh

# 2. Construir las 4 imágenes Docker y cargarlas al cluster
./scripts/02-build-images.sh

# 3. Aplicar todos los manifests de Kubernetes
./scripts/03-deploy.sh

# 4. Ejecutar la demo end-to-end
./scripts/04-demo.sh
```

Verificación rápida:

```bash
kubectl -n tourism get pods
kubectl -n tourism get svc
curl http://tourism.local/
```

---

## 4. Cómo otras empresas consumen la API

Una empresa externa solo necesita **registrarse una vez** y obtener su API Key:

```bash
# Paso 1: Registro (público)
curl -X POST http://tourism.local/companies \
  -H "Content-Type: application/json" \
  -d '{"name": "Mi Agencia SAC", "email": "info@miagencia.pe"}'
# -> devuelve: {"id": 1, ..., "api_key": "tk_xxxxxxxx"}

# Paso 2: Consumir el catálogo
curl http://tourism.local/tours -H "X-API-Key: tk_xxxxxxxx"

# Paso 3: Crear reservas
curl -X POST http://tourism.local/bookings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: tk_xxxxxxxx" \
  -d '{"tour_id": 1, "customer_name": "Juan", "customer_email": "juan@x.com",
       "tour_date": "2026-07-01", "num_people": 4}'
```

Documentación interactiva (Swagger UI): `http://tourism.local/docs`

---

## 5. Demostraciones útiles para el informe/video

### 5.1 Resiliencia (self-healing)

```bash
# Matar un pod manualmente. Kubernetes lo recrea solo.
kubectl -n tourism delete pod -l app=tours-service --field-selector=metadata.name!=tours-service-xxx
kubectl -n tourism get pods -w
```

### 5.2 Escalado horizontal

```bash
# Pasar de 2 a 5 réplicas en segundos
kubectl -n tourism scale deployment tours-service --replicas=5
kubectl -n tourism get pods -l app=tours-service
```

### 5.3 Verificar el caché Redis

```bash
# Primera llamada: source = "database"
curl http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
# Segunda llamada inmediata: source = "cache"
curl http://tourism.local/tours -H "X-API-Key: $KEY" | jq .source
```

### 5.4 Persistencia de PostgreSQL

```bash
# Crear datos, reiniciar el pod, los datos siguen ahí
kubectl -n tourism delete pod postgres-0
kubectl -n tourism wait --for=condition=ready pod/postgres-0
# Repetir consulta -> los datos persisten gracias al PVC
```

### 5.5 Logs en vivo

```bash
kubectl -n tourism logs -f deployment/api-gateway
```

---

## 6. Estructura del proyecto

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
├── scripts/
│   ├── 01-setup-cluster.sh
│   ├── 02-build-images.sh
│   ├── 03-deploy.sh
│   └── 04-demo.sh
└── README.md
```

---

## 7. Mejoras futuras (sección para el informe)

- **Observabilidad**: Prometheus + Grafana + cAdvisor para métricas; Loki para logs centralizados
- **CI/CD**: GitHub Actions que construya las imágenes y aplique los manifests automáticamente
- **Service mesh**: Istio o Linkerd para mTLS automático entre servicios y observabilidad L7
- **Helm Chart**: empaquetar todo el despliegue como un chart parametrizable
- **HorizontalPodAutoscaler**: escalado automático basado en CPU/memoria/RPS
- **Rate limiting** en el Gateway por API Key
- **TLS**: cert-manager + Let's Encrypt para HTTPS real

---

## 8. Limpieza

```bash
kind delete cluster --name tourism
```

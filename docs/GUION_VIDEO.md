# Guion sugerido para el video (15-18 minutos)

## Antes de grabar
- Cluster ya levantado con `./scripts/01-setup-cluster.sh` y `./scripts/02-build-images.sh`
- 2 terminales abiertas: una para comandos, otra para `kubectl get pods -w` corriendo
- Diagrama de arquitectura abierto en otra pantalla / pestaña
- Postman o Bruno listo con los endpoints, o usar el script de demo

## Estructura

### Minuto 0-2 — Introducción y problema
- Presentación: nombre, curso, semestre
- Problema: "Una empresa de turismo quiere ofrecer sus tours y sistema de reservas
  como un servicio que otras agencias puedan consumir vía API. ¿Cómo lo desplegamos
  de forma escalable y resiliente?"
- Respuesta: microservicios + Kubernetes

### Minuto 2-4 — Arquitectura
- Mostrar el diagrama del README
- Explicar cada componente: Gateway, 3 microservicios, Postgres, Redis, Ingress
- Mencionar patrones: API Gateway, multi-tenant, cache-aside, service-to-service

### Minuto 4-6 — Recorrido por el código
- Abrir `services/api-gateway/main.py`: mostrar la validación de API Key
- Abrir `services/tours-service/main.py`: mostrar el patrón cache-aside con Redis
- Abrir `services/bookings-service/main.py`: mostrar la llamada httpx a tours-service

### Minuto 6-9 — Docker y construcción de imágenes
- Mostrar un Dockerfile
- Ejecutar `docker images | grep tourism` (ya están construidas)
- Explicar que cada microservicio es una imagen independiente

### Minuto 9-13 — Kubernetes en acción
- `kubectl get nodes` → 3 nodos
- `kubectl -n tourism get pods` → todos Running
- `kubectl -n tourism get svc` → servicios expuestos
- `kubectl -n tourism describe pod auth-service-xxxx` → mostrar probes, env, resources
- **Demo de self-healing**: `kubectl -n tourism delete pod -l app=tours-service`
  → mostrar que se recrea solo en la otra terminal
- **Demo de escalado**: `kubectl -n tourism scale deployment tours-service --replicas=5`

### Minuto 13-16 — Consumo desde "otra empresa"
- Ejecutar `./scripts/04-demo.sh` paso a paso (o usar Postman)
- Mostrar el flujo completo:
  1. Registro de empresa → recibe API Key
  2. Intento sin API Key → 401
  3. Listado de tours: primera vez "database", segunda "cache"
  4. Crear reserva: el bookings-service consulta a tours-service internamente
- Abrir `http://tourism.local/docs` → Swagger UI generado automáticamente

### Minuto 16-18 — Cierre
- Resumen de lo demostrado: containerización, orquestación, microservicios,
  caché, persistencia, autenticación, exposición externa
- Mejoras futuras (sección 7 del README): observabilidad, CI/CD, HPA, mTLS
- Despedida

## Consejos de grabación
- Usa OBS Studio (está en repos de Arch)
- Resolución 1080p, 30 fps es suficiente
- Activa zoom de cursor o usa un tamaño de fuente grande en la terminal (14-16pt)
- Para la terminal: una fuente monoespaciada bonita (JetBrains Mono, Fira Code)
- Si te trabas en algún comando, edita el video después; no rehacas todo

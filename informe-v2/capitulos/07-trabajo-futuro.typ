= Trabajo futuro

El trabajo futuro se orienta hacia el tercer entregable, en el que la plataforma alcanzará un estado completo y listo para operar. Las siguientes líneas se desprenden directamente de los hallazgos de esta entrega y de las capas que quedaron señaladas como mejorables.

+ *Resolver el cuello de botella del api-gateway.* Reemplazar la creación de un cliente `httpx.AsyncClient` en cada petición por un cliente persistente con un pool de conexiones reutilizable, y evaluar la paralelización de las llamadas downstream. Es la corrección de fondo a la latencia observada en el Eje 1, que el autoescalado no resuelve (solo preserva la disponibilidad).

+ *Completar la seguridad de red.* Añadir políticas de egreso —para controlar también el tráfico saliente, permitiendo de forma explícita el DNS y el control plane de la malla— y autorización a nivel de aplicación (L7) mediante `AuthorizationPolicy` de Linkerd, de modo de restringir no solo qué pods se comunican, sino qué rutas y métodos HTTP pueden invocarse.

+ *Observabilidad y operación.* Incorporar Grafana sobre el Prometheus de la malla, con dashboards y alertas (latencia, tasa de éxito, saturación), para pasar de la inspección puntual a un monitoreo continuo del sistema.

+ *Resiliencia de la malla.* Configurar timeouts, reintentos y, eventualmente, circuit breaking a nivel de malla, de manera que un servicio degradado no propague sus fallos a toda la cadena de llamadas.

+ *Camino a producción (software completo).* De cara al entregable final: exposición externa con TLS real en el Ingress (por ejemplo, con `cert-manager`), automatización del despliegue mediante CI/CD, y una estrategia de persistencia y respaldo para PostgreSQL.

En conjunto, estas líneas llevan la plataforma desde un prototipo robusto en el plano de red hacia un sistema completo y operable, que es el objetivo del tercer entregable.

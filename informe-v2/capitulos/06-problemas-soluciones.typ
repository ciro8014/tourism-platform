= Problemas encontrados y soluciones

Durante la implementación surgieron varios problemas de integración entre Kubernetes, la malla de servicios y el autoescalado. Más que incidencias, resultaron reveladores sobre cómo interactúan estas capas; se documentan como casos, indicando síntoma, causa raíz y solución.

== Validar antes de destruir: NetworkPolicies sin recrear el clúster

El plan inicial contemplaba instalar Calico —lo que exige recrear el clúster— bajo la premisa común de que el CNI por defecto de Kind (kindnet) no aplica NetworkPolicies. Antes de una operación destructiva, se verificó empíricamente esa premisa con una prueba mínima: un `default-deny` de ingreso y un intento de conexión desde un pod de prueba.

La conexión quedó bloqueada: la versión actual de kindnet (`v20251212-v0.29.0-alpha`) integra el controlador `kube-network-policies` y *sí* aplica NetworkPolicies vía nftables. En consecuencia, se evitó Calico y la recreación del clúster por completo.

*Lección:* validar empíricamente una suposición —sobre todo si la alternativa es destructiva— antes de actuar sobre ella.

== Prerrequisito no evidente: Gateway API en Linkerd

La instalación de las CRDs de Linkerd (`linkerd install --crds`) se detuvo limpiamente porque faltaban las CRDs de la Gateway API. El propio instalador indicó el comando exacto, que debe aplicarse con `--server-side` (las CRDs de Gateway API son grandes y un `apply` normal puede fallar por el límite de tamaño de anotación).

*Lección:* leer la salida de la herramienta; varios instaladores señalan el prerrequisito y el comando correcto.

== Filtrado por puerto entre pods con malla: el puerto 4143

Tras aplicar las NetworkPolicies (`default-deny` + reglas que permitían el puerto de aplicación 8000), el registro de empresas comenzó a fallar con HTTP 500. El diagnóstico mostró que el `api-gateway` recibía una respuesta vacía de `auth-service`, y que `auth-service` nunca registraba la petición en sus logs. Sin embargo, el tráfico desde el Ingress NGINX (origen *no* meshed) hacia el gateway sí pasaba por el 8000.

La causa raíz está en esa asimetría: entre pods *meshed*, Linkerd transporta el tráfico proxy-a-proxy por su puerto de entrada (4143), no por el puerto del servicio. Una NetworkPolicy que solo permite el 8000 bloquea el tráfico real, que viaja por el 4143. La solución fue eliminar la restricción de puerto en las reglas *meshed → meshed* y filtrar por *identidad de origen* (el pod que se conecta), conservando el puerto solo para orígenes no meshed (Ingress) y el scrape de Prometheus.

*Lección:* una NetworkPolicy opera en L3/L4 sobre IP y puerto; entre pods meshed no puede gobernar puertos, porque el puerto observable es el del sidecar. El control fino de puerto/L7 corresponde a la malla (`Server` / `AuthorizationPolicy` de Linkerd).

== Zero-trust de la malla sobre su propia observabilidad: el HTTP 403

Al crear el `ScaledObject` de KEDA, el HPA quedó con la métrica en `<unknown>` y los logs del operador mostraban repetidamente `prometheus query api returned error. status: 403`. KEDA alcanzaba el Prometheus de `linkerd-viz`, pero recibía 403.

La causa raíz: `linkerd-viz` protege su Prometheus con una `AuthorizationPolicy` que solo admite a sus propios componentes, autenticados con identidad mTLS. KEDA, desde el namespace `keda` y sin identidad de malla, es rechazado. La solución fue autorizar a KEDA por *red*: una `NetworkAuthentication` sobre el CIDR de pods del clúster más una `AuthorizationPolicy` sobre el `Server` `prometheus-admin`. No se metió a KEDA en la malla a propósito, porque inyectar un sidecar en su `metrics-apiserver` rompería la API agregada de métricas.

*Lección:* el modelo zero-trust de Linkerd alcanza incluso a su stack de observabilidad; integrar herramientas externas (como un autoescalador) exige autorizarlas de forma explícita.

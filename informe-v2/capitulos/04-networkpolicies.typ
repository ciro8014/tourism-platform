#import "../plantilla.typ": captura, placeholder-figura

= Eje 2 — Segmentación de red con NetworkPolicies

== Diseño de mínimo privilegio

Sobre el namespace `tourism` se aplicó una política `default-deny` de ingreso, que rechaza toda conexión entrante salvo las explícitamente autorizadas. A partir de esa base se habilitaron únicamente los flujos legítimos de la aplicación, resumidos en la @tbl-netpol-design: cada servicio acepta conexiones solo de quien realmente las origina. Así, por ejemplo, PostgreSQL solo es alcanzable desde los servicios de autenticación, tours y reservas, y ningún otro pod puede conectarse a él. Estas políticas son efectivas porque el CNI del clúster (kindnet) las aplica de forma nativa, lo que evitó instalar un CNI adicional (ver el capítulo de problemas y soluciones).

Se optó por controlar únicamente el *ingreso* y no el egreso: una política de egreso obligaría a permitir manualmente el DNS y el tráfico de los sidecars hacia el control plane de Linkerd, lo que resulta más frágil; el egreso queda señalado como trabajo futuro. Además, entre pods de la malla las reglas filtran por *identidad de origen* y no por puerto, debido a cómo Linkerd transporta el tráfico entre proxies; este matiz se detalla en el capítulo de problemas y soluciones.

#figure(
  table(
    columns: (1fr, 1fr),
    align: (left, left),
    table.header([*Origen permitido*], [*Destino*]),
    [Ingress NGINX], [api-gateway],
    [api-gateway], [auth-service, tours-service, bookings-service],
    [bookings-service], [tours-service],
    [auth / tours / bookings], [postgres],
    [tours-service], [redis],
    [linkerd-viz (Prometheus)], [todos (puerto admin 4191/4190)],
  ),
  caption: "Flujos de red autorizados bajo la política default-deny.",
) <tbl-netpol-design>

== Demostración del aislamiento

Con las políticas activas se comprobaron las dos caras de la segmentación. Por un lado, los flujos legítimos siguen operando: el recorrido de extremo a extremo —registro de empresa, consulta de tours desde la caché, creación de reserva con validación cruzada y listado multi-tenant— completó sus siete pasos sin error. Por otro lado, se verificó el bloqueo: se lanzó un pod de prueba sin ninguna etiqueta autorizada e intentó conectarse directamente a la base de datos, la caché y un servicio interno; las tres conexiones expiraron por tiempo de espera (@tbl-bloqueo, @fig-netpol).

#figure(
  table(
    columns: (1fr, auto, auto),
    align: (left, center, center),
    table.header([*Intento desde pod no autorizado*], [*Puerto*], [*Resultado*]),
    [→ postgres-service], [5432], [Bloqueado (timeout)],
    [→ redis-service], [6379], [Bloqueado (timeout)],
    [→ tours-service], [8000], [Bloqueado (timeout)],
  ),
  caption: "Un pod no autorizado es bloqueado en todos los destinos sensibles.",
) <tbl-bloqueo>

#captura(
  "/imagenes/netcheck-bloqueo.png",
  caption: "Aislamiento verificado: un pod no autorizado no alcanza los servicios internos.",
  ancho: 100%,
) <fig-netpol>

El contraste —el tráfico autorizado fluye, el no autorizado se corta— constituye la evidencia empírica del mínimo privilegio a nivel de red.

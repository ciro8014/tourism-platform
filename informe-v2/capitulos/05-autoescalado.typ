#import "../plantilla.typ": captura

= Eje 3 — Autoescalado dinámico con KEDA y métricas de la malla

== Arquitectura

Se escala el `api-gateway` —el cuello de botella identificado en el Eje 1— según su tasa de peticiones de entrada (RPS), que KEDA lee del Prometheus de Linkerd @keda_docs. El lazo de control es el siguiente: KEDA consulta periódicamente esa métrica, la expone al Horizontal Pod Autoscaler (HPA) y este ajusta el número de réplicas. La @fig-keda-arch ilustra el flujo.

#captura(
  "/imagenes/keda-arquitectura.svg",
  caption: "Arquitectura de autoescalado guiado por métricas de la malla.",
  ancho: 100%,
) <fig-keda-arch>

Concretamente, el `ScaledObject` de KEDA consulta la siguiente métrica:

```promql
sum(rate(request_total{namespace="tourism", deployment="api-gateway", direction="inbound"}[1m]))
```

Esto se configura con un mínimo de 2 réplicas, un máximo de 6 y un umbral de 10 RPS por réplica; el HPA resultante calcula las réplicas deseadas como el cociente entre el RPS total y dicho umbral. Para que KEDA pudiera consultar el Prometheus de `linkerd-viz` fue necesario autorizarlo explícitamente, pues la malla lo protege con su propia política de acceso; ese caso se detalla en el capítulo de problemas y soluciones.

== Resultados del escalado

Bajo una carga en rampa hasta 40 VUs durante ~4 min (9280 peticiones, 0 errores), el `api-gateway` escaló automáticamente de 2 a 5 réplicas y, al cesar la carga, regresó a 2 (@tbl-escalado, @fig-escalado).

#figure(
  table(
    columns: (1fr, auto),
    align: (left, center),
    table.header([*Estado*], [*Réplicas del api-gateway*]),
    [Reposo (mínimo)], [2],
    [Bajo carga (pico)], [5],
    [Tras la carga (scale-down)], [2],
  ),
  caption: "Autoescalado del api-gateway en respuesta a la tasa de peticiones.",
) <tbl-escalado>

#captura(
  "/imagenes/escalado-watch.png",
  caption: "Escalado en vivo: el api-gateway alcanza 5 réplicas bajo carga.",
  ancho: 100%,
) <fig-escalado>

== Discusión: el autoescalado preserva disponibilidad, no resuelve la latencia

Un resultado matizado e importante: incluso con 5 réplicas, la latencia del `api-gateway` se mantuvo alta —P50 ≈ 1185 ms, P95 ≈ 2780 ms— mientras sus dependencias seguían respondiendo en pocos milisegundos (@tbl-latencia-carga). Cabe aclarar que estos tiempos de Linkerd miden la latencia _server-side_ en el pico de mayor saturación; por contraste, los resultados de k6 promedian toda la ejecución (incluida la rampa inicial de subida donde la latencia es baja), lo que resulta en una mediana y promedio globales menores, pero confirman el mismo cuello de botella en el extremo superior.

#figure(
  table(
    columns: (1fr, auto, auto),
    align: (left, center, center),
    table.header([*Servicio (bajo carga)*], [*P50*], [*P95*]),
    [api-gateway (5 réplicas)], [1185 ms], [2780 ms],
    [auth-service], [≤ 6 ms], [≤ 9 ms],
    [tours-service], [≤ 4 ms], [≤ 7 ms],
  ),
  caption: "Latencia bajo carga con el gateway ya escalado: el cuello de botella persiste.",
) <tbl-latencia-carga>

El autoescalado preservó la disponibilidad —0 errores y throughput sostenido, que sin escalar probablemente habría colapsado— pero no redujo la latencia, porque su raíz es arquitectónica: el `api-gateway` crea un cliente `httpx.AsyncClient` nuevo en cada petición y realiza dos llamadas downstream secuenciales por request, sin reutilizar conexiones. Escalar añade capacidad, no resuelve un cuello de botella de diseño; el arreglo de fondo correspondería a la aplicación (un pool de conexiones reutilizable). Esto evidencia que el autoescalado no es una solución universal frente a límites de diseño.

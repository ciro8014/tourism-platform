#import "../plantilla.typ": captura, placeholder-figura

= Eje 1 — Malla de servicios con Linkerd y mTLS

== Instalación e inyección

La malla se instaló con el CLI de Linkerd en su canal `edge` @linkerd_docs. Como requisito previo se aplicaron las CRDs de la Gateway API con `--server-side` —por el tamaño de sus anotaciones— y, a continuación, las CRDs y el control plane de Linkerd; el comando `linkerd check` validó la instalación con todos sus controles en verde. Luego se instaló la extensión `linkerd-viz`, que aporta el dashboard y un Prometheus propio para las métricas del plano de datos.

La incorporación de los servicios a la malla se realizó anotando el namespace `tourism` con `linkerd.io/inject=enabled` y reiniciando los workloads (`rollout restart`). Tras el reinicio, cada pod pasó de uno a dos contenedores —la aplicación más el proxy de Linkerd—, sin modificar el código ni las imágenes. Conviene notar que PostgreSQL (5432) y Redis (6379) figuran entre los puertos opacos por defecto de Linkerd, por lo que la malla no les aplica detección de protocolo y no se ven afectados al reiniciarse.

== Evidencia de mTLS

Una vez inyectados los sidecars, el comando `linkerd viz edges` confirmó que las conexiones entre servicios viajan cifradas con TLS mutuo (columna SECURED). La @tbl-mtls resume las aristas principales y la @fig-mtls muestra el estado de la malla en el dashboard.

#figure(
  table(
    columns: (1fr, 1fr, auto),
    align: (left, left, center),
    table.header([*Origen*], [*Destino*], [*Cifrado (mTLS)*]),
    [api-gateway], [auth-service], [√],
    [api-gateway], [tours-service], [√],
    [tours-service], [redis], [√],
  ),
  caption: "Conexiones entre servicios cifradas con TLS mutuo (linkerd viz edges).",
) <tbl-mtls>

#captura(
  "/imagenes/dashboard-linkerd.png",
  caption: "Dashboard de Linkerd: topología del namespace tourism con todos los servicios al 100% en la malla.",
  ancho: 100%,
) <fig-mtls>

== Costo de la malla: latencia antes y después

Para cuantificar el costo de introducir la malla se midió `GET /tours` con k6 (20 usuarios virtuales, carga sostenida) antes y después de su activación. La @tbl-latencia compara ambos escenarios.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, center),
    table.header([*Métrica*], [*Sin malla*], [*Con Linkerd*]),
    [Latencia promedio], [354 ms], [271 ms],
    [Mediana], [348 ms], [227 ms],
    [p95], [725 ms], [633 ms],
    [p99], [870 ms], [788 ms],
    [Throughput], [18.4 req/s], [20.4 req/s],
    [Errores], [0 %], [0 %],
  ),
  caption: "Latencia y throughput de GET /tours, sin malla vs. con Linkerd.",
) <tbl-latencia>

El sidecar no introdujo una penalización medible: la latencia se mantuvo en el mismo rango, incluso ligeramente menor. No obstante, cabe un matiz metodológico: la medición sin malla se tomó sobre pods con varios días de actividad y reinicios acumulados, mientras que la medición con malla corrió sobre pods recién reiniciados. Parte de la mejora aparente se atribuye a ese estado más "fresco", no a la malla; por ello la conclusión defendible es que el sobrecosto del proxy es despreciable para esta carga, y no que la malla reduzca la latencia.

== Hallazgo: localización del cuello de botella

El desglose de latencia por servicio (`linkerd viz stat`) bajo carga reveló que el tiempo de respuesta se concentra en el `api-gateway`, mientras que el resto de servicios y la caché responden en pocos milisegundos (@tbl-bottleneck).

#figure(
  table(
    columns: (1fr, auto, auto, auto),
    align: (left, center, center, center),
    table.header([*Servicio*], [*P50*], [*P95*], [*P99*]),
    [api-gateway], [95 ms], [330 ms], [397 ms],
    [auth-service], [1 ms], [5 ms], [44 ms],
    [tours-service], [1 ms], [3 ms], [4 ms],
    [redis], [1 ms], [1 ms], [1 ms],
  ),
  caption: "Latencia por servicio bajo carga: el api-gateway domina el tiempo de respuesta.",
) <tbl-bottleneck>

Este resultado es relevante por dos motivos. Primero, la observabilidad de la malla permitió aislar el cuello de botella sin instrumentar el código de la aplicación. Segundo, orientó la decisión del Eje 3: el servicio a autoescalar debe ser el `api-gateway`, no `tours-service`, que ya responde en milisegundos.

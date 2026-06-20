#import "../plantilla.typ": captura

= Entorno y herramientas

El trabajo se realiza sobre el mismo clúster local de la primera entrega: un clúster Kind de tres nodos —un `control-plane` y dos `workers`— que ejecuta Kubernetes v1.35.0, con la plataforma `tourism-platform` ya desplegada en el namespace `tourism` (los cuatro microservicios FastAPI, PostgreSQL como `StatefulSet`, Redis e Ingress NGINX). La segunda entrega incorpora componentes adicionales sobre esa base, sin modificar la lógica de los servicios. La @fig-arquitectura resume la arquitectura resultante.

#captura(
  "/imagenes/arquitectura-sistema.svg",
  caption: "Arquitectura de la plataforma: topología de servicios, malla con mTLS y flujos permitidos por las NetworkPolicies.",
  ancho: 100%,
) <fig-arquitectura>

La @tbl-herramientas resume los componentes y versiones empleados en esta entrega.

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    table.header([*Componente*], [*Versión / detalle*]),
    [Kubernetes (Kind)], [v1.35.0, 3 nodos (1 control-plane + 2 workers)],
    [CNI], [kindnet `v20251212-v0.29.0-alpha` (aplica NetworkPolicies vía nftables)],
    [Service mesh], [Linkerd `edge-26.6.3` + extensión `linkerd-viz`],
    [Gateway API CRDs], [v1.2.1 (requisito de Linkerd)],
    [Autoescalado], [KEDA `2.20.1` + `metrics-server`],
    [Generación de carga], [k6 `v2.0.0`],
  ),
  caption: "Componentes y versiones del entorno.",
) <tbl-herramientas>

#captura(
  "/imagenes/entorno-cluster.png",
  caption: "Estado del clúster: nodos y pods del namespace tourism.",
  ancho: 100%,
)

== Justificación de las decisiones

Se eligió *Linkerd* en su canal `edge` porque, desde febrero de 2024, el proyecto de código abierto ya no publica versiones `stable` —estas pasaron a distribución comercial @buoyant_edge—, y las versiones `edge` se consideran aptas para producción. Frente a alternativas como Istio, Linkerd usa un micro-proxy escrito en Rust, mucho más liviano, lo que resulta apropiado para un clúster de un solo equipo.

Para la segmentación de red no fue necesario instalar un CNI adicional (como Calico): se verificó que la versión actual de *kindnet* ya aplica NetworkPolicies de forma nativa, evitando una recreación destructiva del clúster (ver el capítulo de problemas y soluciones).

El autoescalado se implementó con *KEDA* —en lugar de un HPA por CPU— porque el cuello de botella identificado no es de cómputo, sino de concurrencia; KEDA permite escalar según una métrica de aplicación real (la tasa de peticiones que reporta la malla). Finalmente, *k6* se empleó por permitir cargas reproducibles y descritas como código.

== Metodología de medición

Las mediciones de latencia y throughput se obtuvieron con k6 contra el endpoint `GET /tours` a través del Ingress, simulando usuarios virtuales concurrentes. Se tomó una línea base antes de instalar la malla y se repitió la prueba tras los cambios relevantes, para comparar bajo el mismo perfil de carga. Para los ensayos de autoescalado se usó un perfil más agresivo (sin pausas entre peticiones) que fuerza el aumento de la tasa de peticiones.

// NOTA: el caveat metodológico sobre el estado de los pods en la línea base se
// detalla en el Eje 1 (sección de latencia antes/después).

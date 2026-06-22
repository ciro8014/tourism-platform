# Guion de video — Segunda entrega

| | |
|---|---|
| Proyecto | tourism-platform |
| Curso | Tópicos Avanzados en Redes (Dirigido) — 2026-I |
| Tema | Malla de servicios (mTLS), NetworkPolicies y autoescalado (KEDA) |
| Duración objetivo | 3 a 5 minutos |
| Formato | Grabación de pantalla con locución |

---

## Preparación previa (antes de grabar)

- Clúster levantado con la malla, las NetworkPolicies y KEDA ya aplicados.
- Generar algo de tráfico para que el dashboard de Linkerd muestre datos: `bash scripts/04-demo.sh`.
- Tener el dashboard de Linkerd abierto en el navegador, en el namespace `tourism` (`linkerd viz dashboard`).
- Tres terminales preparadas: una para `linkerd viz`, una para el `watch` del autoescalado y otra para `k6`.
- Aumentar el tamaño de fuente de la terminal para que se lea en el video.
- Ejecutar una vez `k6 run loadtest/scale-gateway.js` antes de grabar, para "calentar" y confirmar tiempos.

---

## Escena 1 — Introducción (0:00 – 0:30)

**Pantalla:** terminal con `kubectl -n tourism get pods` (o la portada del informe).

**Narración:**
> Buenas. Soy Cesar Olarte. Esta es la segunda entrega del curso de Tópicos Avanzados en Redes. Sobre la plataforma de microservicios de la primera entrega —tourism-platform, sobre Kubernetes— en esta fase trabajé tres cosas en el plano de red: una malla de servicios con cifrado mTLS, segmentación con NetworkPolicies, y autoescalado con KEDA. Lo voy a demostrar en vivo.

---

## Escena 2 — Eje 1: malla y mTLS (0:30 – 1:30)

**Pantalla:** dashboard de Linkerd (namespace `tourism`, servicios al 100% en la malla) y luego la terminal con:
```
linkerd viz edges -n tourism deployment
```

**Narración:**
> Primero, la malla. Instalé Linkerd y lo activé anotando el namespace; ahora cada pod corre un proxy al lado de la aplicación, sin tocar el código. En el dashboard se ve que todos los servicios están al cien por ciento dentro de la malla. Y con `linkerd viz edges`, la columna SECURED confirma que todo el tráfico entre servicios viaja cifrado con TLS mutuo.

**Pantalla (opcional):** `linkerd viz stat -n tourism deploy` bajo algo de carga.

**Narración (opcional):**
> Además, la observabilidad de la malla me dejó ver algo clave: el cuello de botella está en el api-gateway, no en la base de datos ni en los demás servicios. Ese hallazgo definió qué iba a autoescalar después.

---

## Escena 3 — Eje 2: NetworkPolicies (1:30 – 2:30)

**Pantalla:** primero `bash scripts/04-demo.sh` (el flujo completo funciona), luego el pod intruso:
```
kubectl -n tourism run netcheck --image=nicolaka/netshoot --restart=Never \
  --annotations="linkerd.io/inject=disabled" --rm -it -- \
  bash -c 'nc -zv -w3 postgres-service 5432; nc -zv -w3 redis-service 6379; nc -zv -w3 tours-service 8000'
```

**Narración:**
> Segundo, la segmentación. Apliqué una política default-deny: por defecto, nada se conecta con nada, y luego habilité solo los flujos legítimos. El recorrido completo de la aplicación sigue funcionando: registro, tours y reserva. Pero si lanzo un pod no autorizado e intento llegar a la base de datos, a Redis o a un servicio interno... las tres conexiones se cortan por timeout. Eso es mínimo privilegio a nivel de red.

---

## Escena 4 — Eje 3: autoescalado con KEDA (2:30 – 3:45)

**Pantalla:** dividida. Terminal A con el observador, terminal B con la carga:
```
# Terminal A
watch -n2 'kubectl -n tourism get hpa; kubectl -n tourism get pods -l app=api-gateway'
# Terminal B
k6 run loadtest/scale-gateway.js
```

**Narración:**
> Tercero, el autoescalado. KEDA lee la tasa de peticiones desde el Prometheus de la malla y escala el api-gateway. Voy a meterle carga con k6... y aquí, en el watch, el gateway empieza a escalar: de 2 réplicas sube a 5 conforme crece el tráfico. Cuando la carga baja, regresa a 2. Cero errores en todo el proceso.
>
> Un detalle honesto: el autoescalado mantuvo la disponibilidad, pero no bajó la latencia, porque la causa es de diseño dentro del gateway. Escalar da capacidad, no arregla un cuello de botella de arquitectura.

---

## Escena 5 — Cierre (3:45 – 4:15)

**Pantalla:** el informe en PDF o el diagrama de arquitectura.

**Narración:**
> En resumen: observé la red con la malla, la aseguré con mTLS y NetworkPolicies, y la hice elástica con KEDA. En el camino documenté los problemas más interesantes, como el del puerto 4143 entre pods con malla, o el 403 de zero-trust al integrar KEDA. Todo está explicado en el informe y en el repositorio. Para la tercera entrega viene el software completo. Gracias.

---

## Notas de ritmo

- Si el video se acerca a los 5 minutos, recorta la parte opcional de la Escena 2 y abrevia el cierre.
- Lo más vistoso es el autoescalado (Escena 4): que se vea claramente el salto de 2 a 5 réplicas en el `watch`.
- Hablar pausado; cada escena admite 2 o 3 segundos de silencio mientras el comando corre.

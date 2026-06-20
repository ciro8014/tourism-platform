#import "plantilla.typ": informe

#show: informe.with(
  titulo: "Segunda entrega: malla de servicios, seguridad de red y autoescalado sobre Kubernetes",
  curso: "Tópicos Avanzados en Redes",
  docente: "Dr. Rony Villafuerte Serna",
  semestre: "2026-I",
  // OJO: arreglo de 1 elemento -> coma final obligatoria. Agrega más entre paréntesis.
  autores: ("Cesar Ciro Olarte Bautista — 200785",),
  ciudad: "Cusco",
  pais: "Perú",
  anio: "2026",
)

#include "capitulos/01-introduccion.typ"
#include "capitulos/02-entorno-herramientas.typ"
#include "capitulos/03-malla-mtls.typ"
#include "capitulos/04-networkpolicies.typ"
#include "capitulos/05-autoescalado.typ"
#include "capitulos/06-problemas-soluciones.typ"
#include "capitulos/08-conclusiones.typ"
#include "capitulos/07-trabajo-futuro.typ"

#bibliography("bibliografia/referencias.bib")

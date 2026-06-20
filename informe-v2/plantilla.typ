// plantilla.typ — basada en tu template/lib.typ

// 1. HELPER: CAPTURA (tu versión, para imágenes reales)
#let captura(ruta, caption: "", ancho: 80%) = {
  figure(
    image(ruta, width: ancho),
    caption: caption,
  )
}

// 1b. HELPER TEMPORAL: placeholder hasta tener la captura.
//     Reemplázalo por:  captura("../imagenes/archivo.png", caption: "...")
#let placeholder-figura(texto) = figure(
  rect(
    width: 100%,
    inset: 1.2em,
    radius: 4pt,
    stroke: 0.5pt + luma(160),
    fill: luma(245),
  )[#align(center + horizon)[#text(style: "italic", fill: luma(90))[#texto]]],
)

// 2. HELPER: PORTADA
#let portada(titulo: "", curso: "", docente: "", semestre: "", autores: (), ciudad: "", pais: "", anio: "") = {
  set page(numbering: none)
  align(center)[
    #text(size: 16pt, weight: "bold")[
      UNIVERSIDAD NACIONAL DE SAN ANTONIO ABAD DEL CUSCO
    ]
    #v(0.3cm)
    #text(size: 14pt)[
      FACULTAD DE INGENIERÍA ELÉCTRICA, ELECTRÓNICA, \
      INFORMÁTICA Y MECÁNICA
    ]
    #v(0.3cm)
    #text(size: 12pt)[
      ESCUELA PROFESIONAL DE INGENIERÍA INFORMÁTICA Y DE SISTEMAS
    ]
    #v(0.6cm)
    #grid(
      columns: 2,
      column-gutter: 2cm,
      image("imagenes/Escudo_UNSAAC.png", width: 5cm), image("imagenes/Escudo_INFO.png", width: 5cm),
    )
    #v(0.6cm)
    #text(size: 11pt, weight: "medium", tracking: 4pt)[INFORME]
    #v(0.4cm)
    #line(length: 100%, stroke: 0.7pt)
    #v(0.1cm)
    #block(width: 75%)[
      #text(size: 20pt, weight: "bold")[#titulo]
    ]
    #v(0.1cm)
    #line(length: 100%, stroke: 0.7pt)
    #v(1cm)
    #text(size: 12pt)[
      *Curso:* #curso \
      #if docente != "" [*Docente:* #docente \ ]
      #if semestre != "" [*Semestre:* #semestre]
    ]
    #v(1cm)
    #text(size: 12pt, weight: "bold")[Integrantes:]
    #v(0.3cm)
    #text(size: 12pt)[
      #for autor in autores [
        #autor \
      ]
    ]
    #v(1fr)
    #text(size: 12pt)[#ciudad — #pais \ #anio]
  ]
}

// 3. FUNCIÓN PRINCIPAL: INFORME
#let informe(
  titulo: "",
  curso: "",
  docente: "",
  semestre: "",
  autores: (),
  ciudad: "Cusco",
  pais: "Perú",
  anio: "2026",
  body,
) = {
  set page(paper: "a4", margin: (x: 2.5cm, y: 2.5cm), numbering: "1", number-align: center)
  set text(font: "Linux Libertine", size: 11pt, lang: "es", region: "pe")
  set par(justify: true, leading: 0.7em, first-line-indent: 1.5em, spacing: 1em)
  set heading(numbering: "1.1.1.")

  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    set text(size: 18pt, weight: "bold")
    block(below: 1em, it)
  }
  show heading.where(level: 2): it => {
    set text(size: 14pt, weight: "bold")
    block(above: 1.2em, below: 0.8em, it)
  }
  show heading.where(level: 3): it => {
    set text(size: 12pt, weight: "bold", style: "italic")
    block(above: 1em, below: 0.6em, it)
  }
  show raw.where(block: false): it => box(fill: luma(240), inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, text(
    font: "DejaVu Sans Mono",
    size: 0.9em,
    it,
  ))
  show raw.where(block: true): it => block(fill: luma(245), inset: 10pt, radius: 4pt, width: 100%, text(
    font: "DejaVu Sans Mono",
    size: 0.9em,
    it,
  ))
  set table(inset: 7pt, stroke: 0.5pt + luma(180))
  show table.cell.where(y: 0): set text(weight: "bold")
  show figure.caption: it => {
    set text(size: 10pt, style: "italic")
    it
  }

  portada(
    titulo: titulo,
    curso: curso,
    docente: docente,
    semestre: semestre,
    autores: autores,
    ciudad: ciudad,
    pais: pais,
    anio: anio,
  )
  pagebreak()

  show outline.entry.where(level: 1): it => {
    v(0.5em, weak: true)
    strong(it)
  }
  outline(title: [Índice], indent: auto, depth: 3)
  pagebreak()

  body
}

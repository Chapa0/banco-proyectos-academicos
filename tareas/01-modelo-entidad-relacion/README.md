# Entrega 01 - Modelo entidad-relación

Entrega inicial: 26 de octubre de 2026. Presentación conceptual y revisión editorial 1.1: 27 de octubre de 2026. Primera entrega académica del banco de proyectos.

Acuerdos posteriores a esta entrega: el 29 de octubre se confirmó [D-03](../../docs/07-registro-de-decisiones.md#d-03), un director vigente por proyecto sin codirección ni gestión de equipos. El 30 de octubre se confirmaron [D-01](../../docs/07-registro-de-decisiones.md#d-01), tres candidaturas activas simultáneas por alumno; [D-02](../../docs/07-registro-de-decisiones.md#d-02), cupo por proyecto propuesto por la empresa y validado antes de publicar; [D-04](../../docs/07-registro-de-decisiones.md#d-04), un proyecto asignado simultáneamente por alumno; y [D-05](../../docs/07-registro-de-decisiones.md#d-05), inicio administrativo con proyecto publicado, cupo validado, al menos un alumno y el director autorizados, sin llenar el cupo. El 10 de noviembre se confirmó [D-06](../../docs/07-registro-de-decisiones.md#d-06): pendientes de evaluación, evaluadas y preseleccionadas consumen candidaturas; asignaciones vigentes reservan plazas y carga desde la autorización y finalizadas/revocadas dejan de contar, con historial conservado. La interpretación vigente está en [08 Modelo](../../docs/08-modelo-entidad-relacion.md); los PDF, SVG y fuentes JSON se conservan como la entrega de su fecha y no acreditan controles físicos.

## PDF breve para presentar al profesor

La versión principal para exposición es [Modelo conceptual Chen y flujo](modelo-conceptual-y-flujo.pdf): **tres páginas A4 horizontales**, con siete entidades principales, relaciones del negocio, un flujo sencillo y una explicación con ejemplo. Los rectángulos, rombos y óvalos siguen Chen simplificada. Las operaciones temporales se explican aparte en el flujo.

La presentación usa blanco y negro, títulos sencillos y numeración discreta. Se retiraron encabezados de entrega, fecha, fondos de color, separadores decorativos y referencias internas del expediente.

| Página | Contenido |
| --- | --- |
| 1 | Modelo conceptual principal y leyenda de la notación |
| 2 | Publicación del proyecto y ramas independientes de alumno y profesor |
| 3 | Descripción de conceptos y relaciones, ejemplo y aspectos por definir |

En esta vista, «evalúa», «resuelve», «participa» y «dirige» son relaciones conceptuales. Sus registros de evaluación, decisión y asignación continúan en el diseño lógico; no se fusionan solicitudes con asignaciones ni se reducen las tablas de la aplicación. Alumno, Profesor y Administrador se presentan como participantes del negocio; su identidad y acceso se implementarán mediante Usuario y los perfiles correspondientes. Las habilidades, revisiones, avisos e historial conservan su detalle en el modelo lógico.

## Informe lógico de apoyo

El [informe lógico de apoyo](modelo-entidad-relacion.pdf) tiene **15 páginas A3 horizontales del mismo tamaño**. Primero presenta el sistema y explica la notación; después desarrolla el modelo de **21 entidades y 37 relaciones**, cinco áreas explicadas, un caso práctico y un catálogo de referencia. Cada área reúne propósito, diagrama, lectura de relaciones y ejemplo. Las reglas incluyen su justificación y las preguntas pendientes se expresan en lenguaje claro.

Se revisaron las 15 páginas renderizadas y la ubicación de las 37 etiquetas del modelo general, sin pares superpuestos. Las seis vistas conservan formato vectorial. La revisión editorial mantiene intacta la fuente del modelo.

## Orden de lectura del informe lógico

| Páginas | Contenido |
| --- | --- |
| 1-3 | Presentación, índice, funcionamiento de alumnos y profesores y guía de notación |
| 4 | Modelo general de todo el sistema, agrupado por áreas |
| 5-9 | Cinco áreas con explicación y ejemplo junto a cada diagrama |
| 10 | Caso ficticio de Nova, Elena, Lucía y Raúl que conecta los procesos |
| 11-13 | Catálogo equilibrado: siete entidades por página, con atributos y claves |
| 14-15 | Reglas y su propósito, acuerdos aplicados, definiciones pendientes y fuentes |

## Archivos

| Archivo | Uso |
| --- | --- |
| [PDF conceptual para exposición](modelo-conceptual-y-flujo.pdf) | Versión breve: Chen simplificada, flujo y explicación |
| [Informe lógico de apoyo](modelo-entidad-relacion.pdf) | Desarrollo detallado de entidades, claves y relaciones |
| [Generador del PDF conceptual](fuentes/generar_conceptual.py) | Compone las tres páginas de presentación |
| [Dibujo Chen editable](fuentes/dibujar_chen.py) | Entidades, relaciones, atributos y distribución de la lámina conceptual |
| [Modelo general SVG](diagramas/general.svg) | Lámina integral ampliable sin pérdida de calidad |
| [Identidad y empresas](diagramas/identidad.svg) | Cuentas, perfiles y representación empresarial |
| [Proyectos y habilidades](diagramas/proyectos.svg) | Propiedad, autoría, revisiones y habilidades |
| [Participación y acompañamiento](diagramas/participacion.svg) | Solicitudes, autorizaciones, asignaciones y correspondencia alumno/director |
| [Evaluación](diagramas/evaluacion.svg) | Evaluador, candidatura, criterios y puntuaciones |
| [Control y comunicación](diagramas/control.svg) | Decisiones, auditoría y notificaciones |
| [Modelo editable](fuentes/modelo.json) | Entidades, atributos, claves, relaciones y selección de vistas |
| [Explicaciones editables](fuentes/explicaciones.json) | Propósito de las áreas, ejemplos, recorrido y justificación de reglas |
| [Generador de diagramas](fuentes/generar_diagramas.mjs) | Produce los SVG desde el modelo |
| [Generador de PDF](fuentes/generar_pdf.py) | Compone el documento desde el modelo y los SVG |

## Lectura e impresión

El PDF breve usa A4 horizontal; el informe lógico usa A3 horizontal. Cada documento mantiene un tamaño uniforme y sus gráficos son vectoriales. Para exposición e impresión ordinaria se recomienda el PDF breve. En el informe lógico, la lámina general prioriza entidades y PK; las vistas por áreas muestran PK/FK y los atributos completos se leen en el catálogo.

`1`, `0..1`, `0..N` y `1..N` son multiplicidades. Las relaciones describen el historial, mientras los cupos simultáneos se controlan con las reglas correspondientes. Los campos marcados PK componen la clave primaria; FK identifica referencias; UK representa unicidad. En RevisionProyecto, `UK*` corresponde a la pareja `(proyecto_id, numero)`.

## Alcance de la entrega

El modelo completa el preliminar con una vista integral y con Acompanamiento, que identifica qué dirección acompaña a qué alumno dentro de un mismo proyecto. Aplica D-09 y conserva como propuestas los detalles aún sujetos a decisiones institucionales. No declara aprobados equipos, periodos, capacidades, rúbricas ni procedimientos de relevo.

La explicación vigente está en [08 Modelo entidad-relación](../../docs/08-modelo-entidad-relacion.md), y las comprobaciones se registran en [06 Seguimiento](../../docs/06-seguimiento.md). Esta entrega incluye diseño documental, no DDL ni una aplicación implementada.

`tmp/pdfs/` conserva las imágenes de revisión, con prefijos que distinguen las versiones. El archivo principal para entregar al maestro es `modelo-conceptual-y-flujo.pdf`; el informe lógico y las fuentes sirven como apoyo y para editar o verificar el trabajo.

## Regeneración

Se utilizó Node.js con `@viz-js/viz` 3.25.0, y Python con `reportlab` y `PyMuPDF`; las fuentes son Arial o DejaVu Sans. Usar la misma versión de Graphviz WASM para reproducir la colocación y los ajustes de etiquetas. Ejecutar primero `node fuentes/generar_diagramas.mjs` y después `python fuentes/generar_pdf.py`. Si el paquete de Node no se resuelve automáticamente, pasar la ruta a `@viz-js/viz/dist/viz.js` como argumento del primer comando. Los generadores localizan los archivos a partir de su propia ubicación. Después de cambiar la fuente, volver a renderizar e inspeccionar el PDF.

El documento conceptual se regenera con `python fuentes/generar_conceptual.py`; utiliza ReportLab, PyMuPDF y el módulo `dibujar_chen.py`, sin necesitar Graphviz.

# Guía visual

Guía vigente para las pantallas del banco de proyectos. WEB-03 la aplica al inicio de sesión, cambio de contraseña, panel de los cuatro roles y administración de cuentas. Las pantallas futuras seguirán esta base y se verificarán al implementarlas.

## Rediseño vigente (RD-01)

12 de noviembre de 2026. El usuario aprobó la [vista previa](design/rediseno-vista-previa.html) y eligió la paleta azul. Este apartado prevalece sobre lo que las secciones siguientes digan de colores, encabezado, fuentes y bibliotecas; el resto de sus reglas (jerarquía, ayudas, estados, accesibilidad) sigue vigente.

**Color.** Primario azul `#2f5bd3` (texto blanco 5.9:1), fondo `#f5f7fb`, superficies blancas, texto `#172036`/`#3a4560`/`#5f6b85`. Estados con significado fijo: verde aprobado, ámbar en espera, rojo rechazado, siempre con ícono y texto. **Modo oscuro** con fondos gris azulado (`#0d1322`, `#161e33`), primario aclarado `#8fa8ff` y texto oscuro sobre los botones (8.3:1). Gráficas `#2f5bd3` en claro y `#6f8cf0` en oscuro, validadas con la guía de visualización. Los valores están en [design-tokens.json](design/design-tokens.json) y en las variables `--site-*` de `app.css`.

**Tema.** Botón sol/luna en la barra superior y en el encabezado público. Sin elección previa sigue la preferencia del sistema; la elección se recuerda en el navegador. El tema se aplica antes de pintar para evitar un destello.

**Estructura.** Las cuentas trabajan con una barra lateral clara a la izquierda: marca, grupos (Proyectos, Participación, Mi cuenta, Administración) con íconos, contador de avisos sin leer, y al pie nombre, rol, Cambiar contraseña y **Cerrar sesión** en rojo, separado del resto. Arriba, una barra con el tema y la campana de avisos. Por debajo de 992 px la barra lateral se esconde tras un botón de menú y se abre sobre el contenido con fondo atenuado; Escape o el fondo la cierran y devuelven el foco. Quien tiene contraseña temporal solo ve Cambiar contraseña y Cerrar sesión.

**Regreso al origen (NAV-01).** El enlace «Volver» de una página de detalle lleva a la página desde la que se llegó, con su texto («Volver a la solicitud de dirección», «Volver al proyecto», «Volver a mi espacio»), y conserva los filtros y la página de las listas. Los enlaces que cruzan secciones añaden el origen en `?volver=` con `App\Support\Regreso::enlace`; las páginas lo leen con el componente `<x-volver>`. Sin origen o con uno no válido, «Volver» va a la lista de su sección. Los pasos internos (crear o editar) siguen volviendo a su propia lista o ficha.

**Portada y acceso.** Encabezado público con marca, «Cómo funciona», tema e «Iniciar sesión». Portada con título grande, tarjetas ilustrativas del sistema, pasos y participantes en tarjetas con ícono; no consulta la base.

**Tipografía e íconos.** Inter (variable) y Bootstrap Icons instalados con npm y compilados por Vite: funcionan sin conexión. Tarjetas con radio de 14 px y sombra suave; controles con radio de 10 px y foco con halo del primario.

**Verificación.** Auditoría automática de contraste de todos los textos visibles en 29 páginas por rol (administración, empresa, alumna, profesor y públicas), en claro y oscuro: sin fallos tras corregir el distintivo ilustrativo de la portada. Teléfono a 375 px sin desplazamiento horizontal.

## Dirección y estructura

El sistema es una herramienta de trabajo para alumnos, profesores, representantes y administradores. Debe permitir reconocer la cuenta, encontrar la acción y comprender el resultado con pocas distracciones. Usamos una composición sobria: fondo gris claro, superficies blancas, texto azul oscuro y verde discreto para la acción principal. El detalle común es la navegación activa subrayada y el orden estable de títulos, ayudas y controles.

La referencia es la propia aplicación de WEB-02: conservamos su identidad azul/verde, sus etiquetas y sus recorridos; corregimos tamaños de títulos, densidad de formularios y lectura móvil. No se necesitan imágenes, logotipos inventados, fuentes externas ni una investigación de competidores para este bloque. Bootstrap continúa como base; no se añade otra biblioteca visual.

| Pantalla | Trabajo y acción principal | Jerarquía comprobable |
| --- | --- | --- |
| Inicio de sesión | Entrar con la cuenta proporcionada | Título, instrucción breve, correo, contraseña, Entrar y ayuda de restablecimiento |
| Cambio de contraseña | Sustituir la clave temporal o actual | Motivo, actual, nueva con ayuda, confirmación y Guardar; Cancelar solo cuando ya puede entrar al panel |
| Panel | Reconocer la cuenta y acceder a las acciones disponibles | Nombre del área y saludo; cuentas para administrador; datos de cuenta y cambio de contraseña para todos |
| Cuentas | Encontrar una cuenta o crearla | Título/Crear cuenta, filtros, total, registros con estado textual, acción Administrar y paginación |
| Alta | Crear acceso de un rol | Datos, rol/empresa, contraseña inicial, entrega manual y Crear cuenta |
| Administración de cuenta | Cambiar datos o acceso con motivo | Identidad/estado; formularios separados de datos, contraseña, estado y relevo cuando proceda |

El panel no muestra estadísticas ni accesos a módulos aún sin implementar. La navegación indica la sección actual; Cuentas se presenta solo al administrador, manteniendo la autorización real en el servidor. No se muestran identificadores técnicos o información de conexión.

El [wireframe](design/wireframes.html) conserva la estructura previa sin estilo final. La lista móvil implementada usa registros apilados para evitar desplazar una tabla completa. Los cuatro datos de cuenta y la acción se mantienen.

## Proyectos y revisión de WEB-04

La empresa trabaja sobre datos propios, una lista de proyectos y un formulario por secciones: contenido/cupo, requisitos/planificación y habilidades. Guardar borrador no equivale a enviar. El detalle presenta estado, contenido, acciones permitidas y revisiones anteriores. Los campos académicos/cupo pendientes se indican como «Sin registrar» y los opcionales vacíos se omiten; al enviar un borrador incompleto se conserva la posibilidad de corregirlo.

La bandeja administrativa comienza en En revisión, con filtros para todos los estados. El detalle de un envío pendiente prioriza su instantánea y deja al lado la resolución, el cupo validado y el motivo. En móvil la resolución sigue al contenido. Las revisiones anteriores se despliegan con `details/summary`; cada una conserva su propio contenido y decisión. El administrador puede consultar borradores, sin editarlos ni resolverlos antes de su envío.

Contrato de estas pantallas: misma paleta y controles, 390×844 y 1440×900, con comprobación adicional de reflujo a 320 px. La [revisión WEB-04](evidencia/web04/revision-visual.json) registra guardado/envío, borrador parcial, listado sin coincidencias, errores de validación, éxito de devolución/publicación y permiso denegado; las pruebas HTTP/SQL acreditan pertenencia y conflictos. Los proyectos publicados carecen de edición o reenvío. Las ayudas y estados describen acciones de la aplicación, sin mostrar identificadores internos o información de conexión.

## Perfiles y catálogo de WEB-05

Alumno y profesor encuentran «Mi perfil» y «Catálogo de proyectos» en la navegación y el panel. El perfil propio permite completar datos académicos y contacto sin cambiar los datos de acceso. La matrícula o el número de empleado identifican el perfil; los campos restantes son opcionales. El alumno selecciona habilidades duras y blandas y puede describir su nivel y evidencia. Los detalles opcionales se despliegan mediante `details/summary`, abiertos cuando la habilidad está seleccionada o contiene errores. El profesor registra especialidad y experiencia. La evidencia se presenta como texto, sin enlaces ejecutables ni archivos.

El catálogo prioriza título, empresa, descripción y plazas disponibles. El profesor también ve si la dirección está disponible. Los cinco filtros conservan sus valores y la paginación. El detalle ordena contenido académico, disponibilidad y contacto empresarial; en móvil se apilan. Las publicaciones sin plazas siguen visibles. No se ofrecen acciones de candidatura o dirección antes de WEB-06.

Contrato de revisión: 390×844 y 1440×900, más reflujo a 320 px, teclado y texto largo. Comprobar perfil inicial sin datos, edición y guardado, espera durante el envío, validación y conflicto de versión, catálogo vacío con recuperación, detalle aprobado y rechazo de otros roles o proyectos privados. El resumen de errores conserva los valores y recibe foco; un conflicto pide recargar para revisar los cambios. Las comprobaciones y capturas se registran en la [revisión WEB-05](evidencia/web05/revision-visual.json).

## Participación y seguimiento de WEB-06

El alumno envía su candidatura desde un proyecto disponible y consulta «Mis candidaturas». El profesor añade experiencia y justificación a su solicitud y consulta «Mis solicitudes». Las listas muestran proyecto, empresa, estado y acceso al detalle, con filtros y paginación. La cancelación previa se presenta en el detalle, con sus consecuencias y confirmación explícita; una asignación aprobada explica que el retiro corresponde al administrador.

La empresa revisa candidatos de sus proyectos: perfil permitido, tres criterios con puntuación/comentario, recomendación y evaluación general. Evaluar y preseleccionar son acciones separadas. El administrador consulta solicitudes y resuelve con motivo; aprobación y asignación forman una operación. El seguimiento agrupa proyecto, participantes autorizados, eventos e inicio/continuidad/cierre permitidos. Se usan las superficies, ayudas y colores existentes; no se añaden estadísticas o decoraciones.

Contrato de revisión: 390×844 y 1440×900, más reflujo a 320 px y teclado. Espera al enviar con anuncio y botón temporalmente inactivo; listas vacías con recuperación; perfil incompleto con enlace para completarlo; errores de datos, cupo, carga o versión que conservan el formulario; confirmación tras envío/evaluación/resolución; permisos denegados sin contenido privado. Las operaciones de retiro y cierre exigen motivo y confirmación, y advierten sus efectos concretos antes de enviarse. Los detalles de historia usan `details/summary` nativo cuando mejoran la lectura.

La [revisión WEB-06](evidencia/web06/revision-visual.json) acredita el recorrido real, estados y adaptación. En las vacantes, el móvil presenta primero la acción de solicitar; se omiten las secciones personales vacías que ese visitante no puede consultar. Se comprobó además envío sin JavaScript, movimiento reducido emulado y conflictos entre pestañas. La revisión declara sus límites sin sustituir una certificación de accesibilidad.

## Avisos y reportes de WEB-07

Los cuatro roles encuentran «Avisos» en la navegación. La bandeja presenta mensaje, fecha y estado leído/no leído, con búsqueda, filtro y contador de no leídos. El detalle conserva el mensaje y ofrece «Marcar como leído» mediante formulario; consultar no marca automáticamente. Si hay un recurso disponible para ese usuario, un enlace interno permite continuar el trámite. Un recurso que dejó de estar autorizado no amplía permisos por haber recibido un aviso.

Solo el administrador encuentra «Reportes». Selecciona uno de los cinco informes previstos, aplica sus filtros y consulta totales y registros paginados. La tabla de escritorio se sustituye por registros apilados en móvil, conservando todos los datos. Los totales describen el conjunto filtrado completo; no se presentan como indicadores de una sola página. Se mantienen la paleta, componentes y etiquetas actuales, sin gráficos decorativos ni otra biblioteca.

Contrato de revisión: 390×844 y1440×900, más reflujo320px, teclado, nombres/mensajes largos y movimiento reducido. Comprobar envío de lectura, éxito e idempotencia, bandeja sin avisos o sin coincidencias, filtros y paginación, detalle ya leído, reportes sin resultados y permiso denegado. Los controles tienen etiqueta visible, errores asociados y foco; la lectura y las consultas funcionan sin JavaScript. La [revisión WEB-07](evidencia/web07/revision-visual.json) registra los estados y adaptación comprobados. Las pruebas HTTP integrales acreditan el recorrido CA-01 a CA-10 y su generación de avisos, separadas de esta revisión visual.

## Valores y componentes

[design-tokens.json](design/design-tokens.json) registra los valores compartidos con las variables de [app.css](resources/css/app.css). Al cambiar un valor, actualizar ambos y comprobar su coincidencia; no crear otra paleta por pantalla. La [muestra interactiva](design/design-preview.html) permite revisar la base sin iniciar Laravel y no es una pantalla de la aplicación.

| Uso | Valor o criterio |
| --- | --- |
| Título/texto/ayuda | `#183342` / `#334852` / `#536670` |
| Acción principal | `#245c59`, texto blanco; interacción `#1b4845` |
| Fondo/superficie | `#f3f5f6` / `#ffffff` |
| Separación/control | `#d9e0e3` / `#7b8d96`; el borde suave no identifica por sí solo controles |
| Foco | `#165e91`, contorno de 3 px y separación de 3 px |
| Éxito/error | `#235b44` sobre `#eaf3ee` / `#a52a36` sobre `#fbefef`, siempre con texto |
| Tipografía | Sistema, cuerpo 16 px, ayuda 14 px, título 28–32 px, sección 20 px |
| Espacios | Escala de 4, 8, 12, 16, 24, 32 y 48 px |
| Controles/superficies | Radio 6 / 10 px; sin sombras decorativas |
| Interacción | Controles de al menos 44 px de alto; navegación nativa y foco visible |

Cada página tiene un h1; las secciones usan h2 o legend. `surface` agrupa una unidad funcional; no se anidan tarjetas. `page-header`, `page-title` y `page-description` ordenan el encabezado; `form-section` y `form-actions` organizan formularios; `status-badge` siempre incluye Activa/Inactiva. Los cambios de estado peligrosos usan rojo y un motivo, conservando la operación autorizada del servidor.

Etiquetas visibles antes del campo, ayudas y errores unidos mediante `aria-describedby`, `aria-invalid` cuando corresponde. El resumen de errores de cuentas recibe foco tras una respuesta inválida. Las contraseñas nunca se rellenan ni se muestran en confirmaciones. No se prohíbe pegar una contraseña.

### Ayudas de formulario (UX-01)

Cada campo de texto muestra dentro un ejemplo realista con el formato esperado, iniciado con «Ej.» cuando es contenido libre (`nombre@ejemplo.com`, `Ej. 20231234`). El ejemplo nunca sustituye a la etiqueta ni contiene reglas obligatorias: los requisitos que condicionan el envío (longitud de contraseña, cupo validado) permanecen visibles como ayuda bajo el campo.

Cuando el campo necesita más contexto (para qué sirve, quién lo verá, qué consecuencia tiene), la etiqueta lleva el componente `x-info`: un círculo con «i» que abre una explicación breve al pasar el cursor, al enfocarlo con Tab o al tocarlo; Escape o un toque fuera la cierra. El botón incluye el texto completo en su nombre accesible, por lo que también se lee sin JavaScript. Su área táctil alcanza 44 px.

`x-campo` y `cuentas._campo` aceptan `placeholder`, `info`, `autocomplete` e `inputmode`; correo y teléfono reciben `autocomplete` y teclado adecuados, y el correo desactiva corrector y mayúscula automática. Los obligatorios se marcan con un asterisco rojo además del texto «(obligatorio)» para lectores de pantalla y de la nota que ya encabeza cada formulario.

Mejoras progresivas en JavaScript: las contraseñas tienen botón **Mostrar/Ocultar**, aviso de Bloq Mayús, conteo hacia el mínimo y confirmación de coincidencia; los textos largos con límite muestran su contador y lo anuncian solo cuando queda menos del 10 %. Sin JavaScript, los formularios y la validación del servidor no cambian.

### Coincidencia de habilidades y avance del perfil (UX-02)

El alumno ve en cada proyecto del catálogo y en su detalle «Cumples X de Y habilidades solicitadas», una barra y las faltantes, con las obligatorias marcadas en rojo y con texto. La empresa y el administrador ven «Cumple X de Y» en la candidatura, comparada con la versión publicada del proyecto. Una habilidad cuenta si el alumno la tiene registrada; el nivel es texto libre y no se compara. Es una guía: no ordena, filtra ni bloquea candidaturas y la evaluación sigue siendo de la empresa. El profesor no la recibe, porque su perfil no tiene habilidades estructuradas.

«Perfil completo al X %» aparece en Mi perfil y en el panel de alumno y profesor. Enumera los datos recomendados que faltan como enlaces al campo correspondiente. Los obligatorios se siguen validando al guardar y al participar; el porcentaje no impide nada. La barra tiene `role="progressbar"` con su valor; el texto expresa el mismo dato.

### Documentos PDF del perfil (UX-04)

«Mi perfil» termina con la sección **Documentos PDF**: currículum (subir, reemplazar, descargar y quitar) y, para el alumno, evidencias por habilidad con un selector de la habilidad y hasta tres archivos por cada una. Un texto inicial dice quién podrá verlos. Cada archivo se muestra con la etiqueta «PDF», su nombre y tamaño; «Quitar» pide confirmación. Errores de tipo, tamaño, firma o máximo se muestran bajo el formulario que los produjo y en el resumen superior. En el perfil que consultan empresa, administración o director aparecen «Currículum» y «Evidencias en PDF» dentro de cada habilidad. Las descargas son siempre archivos adjuntos; no se previsualizan en la página.

### Catálogo de habilidades (UX-10)

La administración tiene **Habilidades** en la navegación y en su panel. La página muestra tres cifras (total, duras y blandas), un bloque plegable **Agregar habilidad** (abierto si el catálogo está vacío o el alta tuvo errores), búsqueda por nombre o descripción y filtro por tipo. Cada fila tiene el nombre con una etiqueta de tipo, la descripción, el uso («Usada por 3 alumnos · 1 proyecto · en 1 versión publicada» o «Sin uso») y, si aplica, un aviso rojo claro de **posible duplicado**. **Editar** despliega el formulario en la propia fila; **Eliminar** solo aparece cuando la habilidad no se usa y pide confirmación. Los errores se muestran únicamente en el formulario que se envió.

### Panorama gráfico de Reportes (UX-09)

Reportes empieza con **Panorama general**: cuatro tarjetas en cuadrícula (una columna en teléfonos). Tres son barras horizontales de una sola serie (proyectos, candidaturas y solicitudes de dirección por estado), en el orden fijo de los estados y con los estados en cero atenuados; la cuarta es una lista de medidores con la carga de cada profesor frente al límite de tres, con «al límite» en texto cuando se alcanza. Cada fila muestra el nombre del estado a la izquierda, la barra y el número a la derecha en tinta del texto; al pasar el cursor se resalta y su `title` da cantidad y porcentaje; el nombre enlaza al reporte filtrado. Las barras tienen 14 px de grosor, punta redondeada de 4 px y base recta, sin ejes ni cuadrícula. El color de las marcas, `#008a7e`, es un verde azulado de la misma familia que el acento, elegido porque el acento `#245c59` no supera el mínimo de croma para datos; se comprobó con el validador de la guía de visualización (luminosidad, croma ≥ 0.10 y contraste ≥ 3:1). No hay leyenda: cada gráfica tiene una sola serie y su título la nombra.

### Foto de perfil y logo de empresa (UX-08)

El alumno y el profesor suben su **foto** en «Mi perfil», en una tarjeta propia bajo el avance del perfil; la empresa sube su **logo** en «Datos de empresa». Cada tarjeta muestra la imagen actual en grande (círculo para la foto, cuadrado redondeado con borde para el logo) o las iniciales en su lugar, el selector de archivo con su ayuda «i», el botón Subir o Reemplazar y el enlace rojo «Quitar imagen» con confirmación. La foto aparece en el menú de cuenta y en el perfil que consultan la empresa, la administración y el director; el logo, junto al nombre de la empresa en el catálogo, en las recomendaciones y en el encabezado del proyecto publicado. Sin imagen se muestran iniciales: en la foto, blancas sobre el color de acento; en el logo, del color de acento sobre gris claro.

### Constancia de participación (UX-07)

Cuando una participación concluye con el cierre del proyecto, la tarjeta **Asignación** del detalle muestra un recuadro verde claro con borde de acento: «Participación concluida» y el botón principal **Descargar constancia (PDF)**. Lo ven el alumno o director titular y la administración; la empresa no. El PDF, tamaño carta, tiene doble marco en el color de acento, una franja corta sobre el nombre del sistema, el título «Constancia de participación», el nombre de la persona en grande, su matrícula o número de empleado, un párrafo con proyecto, empresa y periodo, una tabla con empresa, modalidad, periodo, dirección académica y equipo, y al pie el folio, la fecha de emisión y la aclaración de que no sustituye una constancia firmada por la institución. Los textos son neutros en género.

### Recomendados para ti y línea de tiempo (UX-06)

**Recomendados para ti** aparece al alumno en «Mi espacio» y en la primera vista del catálogo, sin filtros ni otra página: hasta tres tarjetas con el título, la empresa y la modalidad, la coincidencia compacta («Cumples 3 de 3») y las plazas libres. Cada tarjeta tiene un borde superior de color de acento. Una línea explica el criterio: habilidades del perfil, solo proyectos con plazas en los que aún no participa. Si no hay coincidencias, la sección no aparece.

La **línea de tiempo del estado** va bajo el encabezado del detalle de candidatura o solicitud de dirección, del proyecto de la empresa, de la revisión y del seguimiento. Cada paso tiene un círculo: con palomita si ya ocurrió, con punto y halo si es el paso actual, vacío si falta y rojo con «×» si el trámite terminó ahí (rechazo o cancelación). Debajo va su fecha cuando se conoce. En pantallas anchas es horizontal con una línea que se colorea hasta el paso actual; en teléfonos se apila en vertical. Para lectores de pantalla cada paso dice si está completado, es el actual o está pendiente, y el actual lleva `aria-current="step"`.

### Pendientes del panel y exportación (UX-05)

«Mi espacio» empieza con **Pendientes**: una fila por tarea con el número en un círculo del color de acento, el texto en singular o plural («1 candidatura por evaluar», «2 proyectos enviados esperan revisión») y un botón secundario con el verbo de la acción (Revisar, Resolver, Evaluar, Corregir, Leer) que abre la lista ya filtrada. Solo aparecen tareas con al menos un elemento; si no hay, una línea en gris lo dice. Son tareas, no estadísticas: no hay gráficas ni totales históricos. En pantallas estrechas el botón pasa debajo del texto, alineado con él. El número se repite oculto en el texto para lectores de pantalla y el botón incluye la tarea en su nombre accesible.

En Reportes, **Exportar CSV** aparece junto al título del reporte cuando hay registros, con una línea que explica que incluye todas las páginas con los filtros aplicados (hasta 5 000). El archivo usa los mismos encabezados y etiquetas que la tabla.

### Menú de cuenta y salida segura (UX-03)

La marca y el menú de cuenta ocupan una barra superior; la navegación de secciones va en su propia fila, sin acciones de cuenta mezcladas. El menú muestra iniciales, nombre y rol; al abrirlo (clic, Enter o espacio) presenta nombre y rol, Mi espacio, Cambiar contraseña y, separado, **Cerrar sesión** como botón rojo con ícono. Salir requiere abrir el menú a propósito. Usa `details/summary` nativo: funciona sin JavaScript; con JavaScript, Escape o un clic fuera lo cierran y devuelven el foco. En móvil se ocultan nombre y rol del disparador y se conservan las iniciales.

Si un formulario POST tiene cambios sin enviar, salir de la página (cerrar sesión, otro enlace o cerrar la pestaña) muestra la confirmación del navegador. Guardar ese mismo formulario no avisa; el acceso queda excluido con `data-sin-aviso-salida`.

## Adaptación e interacción


Contrato de revisión: **390×844** y **1440×900**. Además se comprueba reflujo a 320 px (equivalente de ancho de una ventana de 1280 px al 400 %), textos largos y teclado. Las tablas se muestran desde 768 px; los reportes de mayor anchura esperan hasta 992 px. Por debajo se usan registros con todos los datos. Los filtros pasan de cuatro zonas a dos y luego a una columna. Los formularios se apilan, y la navegación permanece visible sin depender de un menú oculto o de JavaScript.

El acceso tiene ancho máximo de 30 rem y un solo objetivo. El panel usa una o dos columnas según el rol y el ancho; los formularios administrativos conservan sus operaciones separadas. Los correos, nombres y razones sociales largos pueden partir línea.

JavaScript solo mejora el envío: cambia el texto, anuncia la espera y desactiva el botón de ese formulario mientras navega. Al volver con el historial recupera el estado. Sin JavaScript, los enlaces, filtros, formularios y validaciones del servidor siguen disponibles. No hay transiciones de entrada; el cambio de color dura 120 ms y se elimina con movimiento reducido. Esta versión usa un tema claro, sin selector de tema.

## Estados y recuperación

| Estado | Disparador y respuesta | Siguiente acción |
| --- | --- | --- |
| Envío | Formulario válido enviado: texto de progreso y aviso de espera; sin borrar campos | Esperar la respuesta; errores permiten corregir y reenviar |
| Vacío | Búsqueda sin coincidencias: explica el filtro sin resultados | Cambiar filtros o Ver todas las cuentas |
| Error | Validación, conflicto o límite de acceso: mensaje textual; campos implicados identificados cuando procede | Corregir, recargar los datos en un conflicto o esperar el límite |
| Parcial | Cuenta sin perfil académico o empresa, según rol: muestra identidad/acceso disponibles; la razón social solo existe para Empresa | Administrar los datos disponibles; no inventar un perfil o un módulo |
| Éxito | Alta/cambio confirmado por el servidor mediante aviso persistente en la página siguiente | Revisar la cuenta o continuar desde el panel |
| Permiso | Servidor rechaza la sección con 403 y explica el límite sin datos del recurso | Volver a mi espacio |
| Sesión o servicio | 419 solicita entrar de nuevo; 503 ofrece volver al inicio sin consultar identidad al renderizar el error | Entrar otra vez o intentarlo más tarde |

## Habilidades y verificación

Para WEB-03 se aplican `wireframe` a la estructura, `ecc:frontend-design-direction` al contrato y revisión renderizada, `ecc:design-system` a valores/guía/muestra, `ecc:make-interfaces-feel-better` a espaciado y controles, y `ecc:accessibility` a semántica, teclado y contraste. `ecc:laravel-security` y `ecc:laravel-verification` orientan la revisión proporcional de las vistas y regresiones existentes. La [matriz de trabajo](../docs/05-reglas-de-trabajo.md#selección-de-habilidades-antes-de-implementar) define la selección para cada bloque; no todas las habilidades son necesarias en cada cambio.

La revisión incluye renderizado real de las pantallas y estados aplicables, capturas con cuentas ficticias, contraste calculado de pares usados, controles/etiquetas, teclado, movimiento reducido y pruebas de acceso contra PostgreSQL temporal. La [revisión visual](evidencia/web03/revision-visual.json) enlaza capturas y el [seguimiento](../docs/06-seguimiento.md) registra resultados y límites; los informes de versiones anteriores conservan su fecha y no certifican vistas posteriores. Una revisión local no equivale a una certificación completa de accesibilidad ni a despliegue institucional.

Referencias consultadas: [accesibilidad en Bootstrap 5.3](https://getbootstrap.com/docs/5.3/getting-started/accessibility/) y [validación del servidor](https://getbootstrap.com/docs/5.3/forms/validation/). La accesibilidad depende también del HTML y las modificaciones propias; por eso se comprueban etiquetas, contraste, foco y mensajes en el resultado.

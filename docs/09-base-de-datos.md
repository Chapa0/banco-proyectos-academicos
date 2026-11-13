# Base de datos PostgreSQL

La base física conserva las 21 entidades del [modelo lógico](08-modelo-entidad-relacion.md) y añade referencias de integridad e historial. El motor y la arquitectura están en D-13/D-14; las políticas y su fuente se consultan en [el registro de decisiones](07-registro-de-decisiones.md). El usuario delegó completar las opciones de la primera versión el 10 de noviembre de 2026.

Las migraciones versionadas son la fuente del esquema. [Database](../database/README.md) contiene comandos, contratos y reproducción; [el seguimiento](06-seguimiento.md) y los recibos de [pruebas](../database/evidencia/verificacion.json) e [instalación](../database/evidencia/instalacion.json) distinguen lo preparado de lo verificado. El diccionario siguiente se genera desde PostgreSQL real.

## Estructura y evolución

| Migraciones | Responsabilidad |
| --- | --- |
| 001–003 | Entidades, claves, integridad cruzada, historial inmutable y publicación inicial |
| 004–009 | Cupo validado, dirección única, límites de participación, inicio administrativo y envíos |
| 010–013 | Alta administrativa, textos obligatorios, cancelación previa, retiro y continuidad |
| [014](../database/migrations/014_cierre_proyectos.sql) | Finalización/cancelación coordinada y evidencia exacta de cierre |
| [015](../database/migrations/015_cancelacion_solicitud_direccion.sql) | Cancelación propia de solicitud docente pendiente |
| [016](../database/migrations/016_evaluacion_autorizacion.sql) | Evaluación, preselección y autorización con asignación conjunta |
| [017](../database/migrations/017_cuentas_y_privacidad.sql) | Estado de cuentas, relevo empresarial y consulta limitada de perfiles |
| [018](../database/migrations/018_notificaciones_internas.sql) | Avisos internos por evento y lectura propia |
| [019](../database/migrations/019_conexion_web.sql) | Grupo mínimo para la conexión Laravel, sin DDL ni acceso a tablas privadas |
| [020](../database/migrations/020_acceso_web.sql) | Funciones concretas de acceso/cuentas, versión de acceso y cambio de contraseña inicial |
| [021](../database/migrations/021_publicacion_web.sql) | Nueve gateways de empresa/publicación, siete auxiliares privados y versiones opacas para formularios, sin columnas nuevas |
| [022](../database/migrations/022_perfiles_catalogo_web.sql) | Seis gateways de perfiles propios/catálogo y cinco auxiliares privados, con versiones de perfil y lectura de publicaciones válidas |
| [023](../database/migrations/023_participacion_web.sql) | Ocho gateways de participación, evaluación y ciclo y ocho auxiliares privados; ámbitos por relación y versiones para decidir sobre datos vigentes |
| [024](../database/migrations/024_avisos_reportes_web.sql) | Cuatro gateways de bandeja propia, lectura de avisos y reportes administrativos, con tres auxiliares privados y sin cambios de tablas |

Las nuevas referencias admiten NULL en la historia anterior; no se fabrican evaluaciones, cupos, retiros o cierres. Las migraciones aplicadas no se editan. `control.migracion`, separado del negocio, conserva nombre, SHA-256 y fecha. Los PDF y el JSON académicos son entregas históricas y no se regeneran por cada cambio físico.

## Integridad y capacidad

Las PK/FK impiden referencias inexistentes. Las claves compuestas unen fuente, participante, proyecto y decisión aprobatoria exactos. El estado aprobado, la decisión y su asignación deben quedar juntos al confirmar; una aprobación aislada no libera candidatura. Revisiones, decisiones, evaluaciones, detalles y auditoría conservan su historia, sin borrados en cascada.

D-01 a D-06 se aplican con índices, comprobaciones y bloqueos: máximo tres candidaturas activas por alumno, sin duplicado activo; cupo positivo propio del proyecto validado al publicar; un director vigente por proyecto; un proyecto vigente global por alumno y tres por profesor. Las asignaciones vigentes reservan desde la autorización, incluso antes del inicio. Las finalizadas/revocadas liberan; no se cuenta por fecha estimada ni se libera por desactivar cuentas.

El inicio exige publicación/cupo válidos, al menos un alumno y un director autorizados y confirmación administrativa. No exige llenar plazas. `evento_inicio_id` conserva el primer inicio; `evento_estado_id` conserva la última pausa/reanudación con enlaces a los eventos anteriores. El retiro administrativo con motivo cierra únicamente esa asignación y sus acompañamientos; perder todos los alumnos o el director en En curso pausa conservando las otras reservas. Durante Pausado solo se repone el tipo faltante y el administrador confirma la reanudación.

## Cierre y conservación

D-07 permite finalizar solo En curso y cancelar cualquier estado abierto, siempre por administrador activo con motivo. `evento_cierre_id` enlaza un evento raíz en Proyecto y los hijos afectados. La operación finaliza/revoca las asignaciones y acompañamientos vigentes, cancela candidaturas activas y solicitudes docentes pendientes y libera todas sus reservas en una transacción. Una revisión pendiente se cancela sin simular un rechazo administrativo; fuentes aprobadas, decisiones, publicación, inicio y pausas anteriores permanecen.

Los períodos comenzados conservan como fin la fecha real del evento. Si todavía no comenzaron, el estado terminal y la evidencia exacta permiten `fin` NULL, sin inventar un final futuro; ese NULL no significa vigencia. El cierre no añade calificaciones ni entregables académicos.

No se reabren registros terminales ni se modifica el contenido/cupo publicado. Para un cambio sustantivo se crea otro proyecto. Tampoco se habilitan incorporaciones generales En curso. El alumno cancela su candidatura activa y el profesor su solicitud pendiente antes de asignarse; después el retiro corresponde al administrador.

## Evaluación y autorización

D-08 usa tres criterios manuales: conocimientos técnicos, habilidades blandas y requisitos académicos, con escala 0–2, igual peso y comentario por criterio. Se añaden comentario general y recomendación. La evaluación completa es atómica e inmutable; su definición aplicada queda guardada en cada detalle. Reevaluar crea otra versión e invalida la preselección actual, conservando la evidencia anterior.

La empresa preselecciona expresamente con su última evaluación completa favorable. La aprobación administrativa de alumno requiere esa preselección y crea la decisión y asignación exacta juntas; el rechazo puede resolver una candidatura activa sin evaluación previa. Las solicitudes de dirección requieren experiencia y justificación, sin evaluación empresarial del profesor. La puntuación no asigna automáticamente ni tiene umbral de aprobación.

## Cuentas, privacidad y avisos

D-09 conserva un representante activo por empresa y un vínculo permanente por cuenta empresarial. El alta académica puede preceder al perfil; matrícula y número de empleado no se inventan. D-10 añade cambio administrativo de estado con motivo y relevo atómico por una cuenta nueva; el representante anterior queda inactivo y conserva su empresa y autoría. Desactivar no libera participaciones ni borra historia. La operación conserva al menos un administrador activo.

La consulta de perfiles usa una lista expresa de campos y relación con el registro: titular/administrador, empresa con candidatos propios o profesor con alumnos asignados. No expone hash; los perfiles compartidos omiten correo de acceso, matrícula/número de empleado y registros de terceros. Los permisos de sesión y recurso de Laravel siguen siendo necesarios. No existe purga automática; la retención legal de producción es un dato institucional todavía por conocer.

D-11 utiliza evidencia como texto o enlace escrito, sin adjuntos ni descarga automática. Los avisos internos se insertan con el evento en la misma transacción, por destinatario activo, sin copiar motivos privados o evidencias. La primera lectura propia queda registrada sin borrar ni reescribir el aviso. No hay correo, SMS o entrega externa.

`usuario.version_acceso` cambia al editar nombre, correo, hash, rol, estado o requerimiento de clave, incluso desde operaciones internas existentes. Laravel conserva la versión de entrada y revalida cuenta/versión en cada petición protegida. `requiere_cambio_clave` obliga a sustituir las claves temporales entregadas por el administrador. Las semillas conservan su hash inválido; el primer acceso se prepara mediante una operación local de sistema separada del servidor web. Una edición obsoleta devuelve `40001`, sin sobrescribir datos ni reintentar el formulario viejo.

## Bloqueos y acceso técnico

Las escrituras con integridad cruzada exigen READ COMMITTED; otro aislamiento se rechaza con `25001`. Las operaciones sobre fuentes existentes siguen fuente → participante → proyecto. El cierre toma sus fuentes y perfiles ordenados antes de Proyecto y revalida el alcance tras esperar. Si apareció otra solicitud o asignación devuelve `40001`: el llamador reintenta la transacción completa. Los retiros y la reanudación conservan sus protocolos sin tomar perfiles nuevos después de Proyecto.

Las operaciones originales conservan `SECURITY INVOKER`. Las migraciones 020–024 conceden treinta y ocho entradas `SECURITY DEFINER`: once de acceso/cuentas, nueve de empresa/publicación, seis de perfiles/catálogo, ocho de participación/ciclo y cuatro de avisos/reportes. Fijan `search_path`; las modificaciones validan actor, rol, pertenencia y versión según su operación. Los auxiliares siguen privados y no se abre DML general. La credencial de servidor es confiable: el actor proviene de la sesión Laravel y SQL por sí solo no autentica esos identificadores. PUBLIC y los grupos técnicos no reciben DML ni ejecución general; `banco_web` conserva el directorio mínimo y esos EXECUTE explícitos; `banco_lectura`/`banco_escritura`, ambos NOLOGIN, solo tienen el directorio mínimo. El propietario local es una cuenta de mantenimiento de desarrollo.

## Verificación y límites

`python database/manage.py test` instala en bases temporales propias, verifica actualización histórica, casos válidos y rechazos, rollback, idempotencia y carreras con bloqueos observados. Los fixtures DML del propietario prueban integridad y se distinguen de las pruebas de las operaciones D-08. Una publicación antigua de formato 1 se conserva sin cupo inventado; no habilita nuevas participaciones hasta conciliar su capacidad. Los datos incompatibles rechazan la migración con rollback, sin arreglos silenciosos.

La recuperación compara datos, columnas, restricciones, índices, triggers, funciones, vistas, permisos de esquemas/objetos, las quince secuencias con su estado y el historial técnico exacto. Después exige que el migrador sea una segunda ejecución sin cambios. `restore-check` rechaza fuentes pendientes o modificadas antes de crear una copia; no actualiza silenciosamente la instalación antigua. El esquema exportado se carga en otro destino para comparación estructural, nunca sobre una base migrada.

D-12 concreta la entrega local PostgreSQL 18.6 con respaldo manual y restauración comprobada. No acredita alojamiento, volumen, disponibilidad ni recuperación institucional de producción. WEB-01 a WEB-07 aportan conexión propia, sesión, cuentas, empresa/publicación, perfiles, catálogo, participación/ciclo, avisos y reportes según la [guía web](../web/README.md). Las APIs y el despliegue institucional conservan sus etapas posteriores. La evidencia SQL acredita las operaciones de base; los recorridos de aplicación se registran por separado.

## Publicación integrada en WEB-04

021 añade datos propios de la empresa y creación/edición de borradores con campos permitidos, habilidades y cupo; ofrece listados por rol y detalle con las revisiones y sus decisiones. La empresa solo accede a proyectos propios; el administrador puede consultarlos todos y resuelve los envíos pendientes. No se conceden SELECT/DML general: se mantienen los once gateways de acceso/cuentas y se añaden nueve de publicación. Los siete auxiliares nuevos siguen privados.

Los formularios reciben una versión opaca SHA-256 de contenido, estado, habilidades, último envío y evento. El SQL vuelve a comprobarla bajo bloqueo y rechaza datos obsoletos con `40001`; no es una credencial ni un permiso. Los cambios mantienen auditoría. Envío y resolución reutilizan las operaciones internas existentes y los avisos transaccionales de 018. Para aprobar, el cupo validado debe coincidir con la propuesta de la instantánea exacta; cambiarlo requiere devolución y nuevo envío. Una revisión histórica sin cupo se conserva y puede devolverse o rechazarse, sin inventarle capacidad.

La migración no cambia tablas, columnas, restricciones, índices, triggers o secuencias. Al cerrar WEB-04, la instalación tenía 21 tablas, 164 columnas de tablas y cinco de vista, 263 restricciones, 86 índices, 75 triggers, 114 funciones y quince secuencias. La instalación, pruebas HTTP y límites se consultan en el seguimiento; el diccionario generado debajo conserva los mismos atributos de negocio.

## Perfiles propios y catálogo integrados en WEB-05

022 permite a las cuentas activas de alumno y profesor crear o editar su propio perfil, incluso si el administrador creó primero la cuenta sin datos académicos. El alumno conserva matrícula, carrera, semestre, datos académicos y contacto; el profesor, número de empleado, especialidad, experiencia y contacto. Solo el alumno tiene habilidades estructuradas duras/blandas, con dominio, descripción y evidencia textual. Se reutilizan las tablas existentes y no se añaden habilidades docentes ni archivos adjuntos. Los campos permitidos impiden cambiar titular, identidad de acceso o rol desde el perfil.

El guardado confirma perfil, asociaciones de habilidades y auditoría juntos; cualquier fallo revierte el conjunto. Una versión opaca incorpora el contenido y el último evento para detectar formularios obsoletos, incluso si los datos regresaron a un valor anterior. Un bloqueo compartido protege la lectura del par datos/versión y otro exclusivo serializa los guardados del mismo titular. En perfiles existentes se conserva el orden participante → Usuario; la comparación posterior al bloqueo rechaza con `40001` y exige recargar y revisar.

El catálogo es exclusivo de alumnos y profesores activos, sin exigir un perfil previo. Muestra proyectos Publicados con revisión aprobada de formato 2, decisión exacta, campos completos, cupo positivo y contenido/requisitos coincidentes con la versión aprobada. Combina búsqueda, empresa, modalidad, habilidad y tipo, con páginas de veinte en Laravel. Los nombres y requisitos de habilidades se leen de la instantánea aprobada. El detalle devuelve contenido del proyecto y contacto empresarial permitido, sin motivos administrativos, revisiones privadas, correo de acceso o hashes. Su bloqueo compartido sobre Proyecto permite revalidar después de un cierre concurrente.

Las asignaciones vigentes determinan las plazas libres y si la dirección está ocupada. Un proyecto lleno conserva visibilidad con cero plazas; esta disponibilidad es informativa y no reserva ni autoriza una participación. El catálogo de habilidades permite elegir registros existentes; su mantenimiento no forma parte de WEB-05. La semilla local conserva únicamente «SQL de ejemplo»: falta cargar las opciones de habilidades blandas para su uso, aunque su almacenamiento y selección ya están implementados y probados.

La instalación de 022 conservó exactamente el contenido y conteos de las 21 tablas, las quince secuencias y los veintiún registros anteriores de migración, sin ejecutar semillas. En ese corte había veintidós migraciones y 125 funciones; los demás conteos estructurales permanecían como en WEB-04. La cuenta web tenía veintiséis gateways concretos, sin SELECT/DML general de tablas privadas ni privilegios administrativos o de creación. La suite SQL acreditó 335 rechazos y 58 carreras con espera real; sus 52 fuentes coincidían con el recibo. La base de trabajo se restauró y comparó en otra base temporal propia, después eliminada. El esquema exportado y este diccionario se regeneraron desde la instalación real; los siete archivos académicos PDF/JSON comparados conservaron sus huellas.

## Participación y ciclo integrados en WEB-06

023 integra el recorrido web sobre las operaciones de negocio existentes: presentar y cancelar candidaturas, solicitar y cancelar dirección pendiente, consultar estados e historia, evaluar y preseleccionar por la empresa, resolver administrativamente con asignación atómica y gestionar inicio, retiros, pausa, reposición, reanudación y cierre coordinado. Añade ocho gateways `SECURITY DEFINER` y ocho auxiliares privados, sin nuevas tablas, columnas o reglas institucionales. Las APIs y la bandeja general de avisos siguen fuera de este bloque; las operaciones reutilizan los avisos transaccionales de 018.

El ámbito de las bandejas depende del actor: el alumno y profesor ven solicitudes propias, la empresa vigente ve candidaturas de sus proyectos y el administrador gestiona ambos tipos. El detalle conserva evaluaciones y decisiones de esa solicitud, con perfiles autorizados por D-10. La empresa recibe contacto académico y habilidades del candidato, sin matrícula ni correo de acceso. El profesor vigente consulta perfiles de alumnos vigentes de su proyecto; un profesor pendiente o retirado no obtiene esos perfiles. El detalle de proyectos conserva relaciones históricas y estados cerrados, sin ampliar la consulta a perfiles ajenos. Una vacante de proyecto pausado puede descubrirse por el tipo faltante; el visitante solo recibe contenido académico y empresa, sin participantes o historial administrativo ajenos.

Cada escritura compara una versión opaca bajo bloqueo. El token de solicitud incluye su fila, perfil, contexto del proyecto y último evento; la versión de ciclo incorpora solicitudes y asignaciones. Se conserva la comparación tras esperar un bloqueo y se rechaza el formulario obsoleto con `40001`, sin repetir automáticamente su decisión. Los envíos bloquean perfil y proyecto; las decisiones bloquean fuente, perfil y proyecto; el cierre conserva fuentes y perfiles antes de retener Proyecto. El acceso empresarial mantiene Empresa → Usuario, igual que el relevo, evitando invertir ese orden. Las funciones de negocio vuelven a comprobar etapas, cupos, cargas, identidad y transiciones.

La suite SQL de 001–023 pasó 369 negativos y 69 carreras con bloqueo observado: 34 negativos y once carreras nuevos para permisos, CAS, duplicados, tres candidaturas activas, última plaza, carga docente, cancelación frente a autorización, reevaluación, inicio/cierre, desactivación y relevo frente a lectura. Las 55 fuentes del recibo coinciden con sus SHA. Los casos HTTP y la revisión renderizada se registran en [el seguimiento](06-seguimiento.md), sin atribuirlos a esta prueba de base.

La instalación de 023 conservó exactamente contenido y conteos de las 21 tablas, quince secuencias, 22 registros técnicos anteriores, 125 funciones previas y siete archivos académicos, sin ejecutar semillas ni añadir usuarios o participaciones de prueba en trabajo. El corte local tiene 23 migraciones y 141 funciones; los demás conteos estructurales no cambian. El runtime accede a 34 gateways concretos, sin privilegios administrativos, DDL o SELECT/DML general de tablas privadas. La recuperación, exportación y diccionario se comprueban en [la instalación](../database/evidencia/instalacion.json); las temporales visuales y su limpieza se registran por separado en el seguimiento.

## Avisos y reportes integrados en WEB-07

024 utiliza los avisos transaccionales de 018. Las cuatro clases de cuenta activa pueden consultar únicamente su bandeja, buscar mensajes y filtrar Todos, No leídos o Leídos. El listado devuelve página, total filtrado y total propio sin leer; este último se calcula sobre toda la bandeja. Abrir un detalle no registra lectura. La acción expresa de marcarlo conserva la fecha de la primera lectura, incluso ante repeticiones simultáneas, y reutiliza la operación interna que comprueba destinatario y cuenta activa.

Un aviso devuelve solo identificador, mensaje y fechas. El enlace opcional se deriva del evento y de la relación actual con la solicitud o proyecto; no expone el evento bruto, motivos privados ni evidencia. Si el destinatario ya no tiene acceso al recurso, conserva su aviso sin recibir ese enlace. La comprobación del recurso usa lecturas MVCC, manteniendo el orden de bloqueos del relevo empresarial. El detalle y la lectura protegen primero Notificación y después Usuario.

RF-41 reserva los reportes al administrador. Se implementan cinco consultas de solo lectura sobre las tablas existentes:

| Reporte | Filtros combinados | Totales antes de paginar |
| --- | --- | --- |
| Proyectos | Texto, estado y empresa | Proyectos, alumnos vigentes y directores vigentes |
| Candidaturas | Texto, estado, empresa y proyecto | Candidaturas, activas, aprobadas, rechazadas y canceladas |
| Solicitudes de dirección | Texto, estado, empresa, proyecto y profesor | Solicitudes, pendientes, aprobadas, rechazadas y canceladas |
| Carga de profesores | Texto y profesor | Profesores, direcciones vigentes y profesores con carga |
| Participantes asignados | Texto, estado, empresa y proyecto | Asignaciones, alumnos/directores vigentes, finalizadas y revocadas |

Laravel presenta páginas de veinte. Los filtros vacíos o JSON `null` equivalen a ausentes; un filtro desconocido, no aplicable o de tipo incorrecto se rechaza. Los listados usan campos expresos sin correo de acceso, matrícula, número de empleado, calificaciones, comentarios o motivos privados. La carga depende del estado vigente y conserva las asignaciones de cuentas inactivas. Las asignaciones de alumno y dirección se unen como filas independientes; los conteos por proyecto se calculan por separado para evitar multiplicarlos al combinar ambos tipos. Cada resumen y su total utilizan el mismo conjunto filtrado antes de aplicar la página.

Las entradas concedidas son `web_bandeja_avisos`, `web_detalle_aviso`, `web_leer_aviso` y `web_reporte`; los tres auxiliares permanecen privados. No se agregan tablas, exportación, APIs, envío externo o tiempo real. El contrato y los comandos se documentan en [database](../database/README.md).

La suite SQL de 001–024 pasó 411 negativos y 75 carreras con bloqueo observado, incluidos 42 negativos y seis carreras nuevos sobre privacidad, filtros, totales, primera lectura, desactivación, relevo y autorización concurrente. Las 58 fuentes del recibo coinciden con sus SHA. La instalación de 024 conservó exactamente contenido y conteos de las 21 tablas, quince secuencias, 23 registros técnicos previos, 141 funciones anteriores y siete archivos académicos, sin semillas ni datos de prueba en trabajo. Quedaron 24 migraciones, 148 funciones y 38 gateways concretos; las demás estructuras permanecieron iguales. Se verificaron migración repetida sin cambios y recuperación en temporal propia, después eliminada; el esquema exportado y este diccionario se regeneraron desde trabajo. Los recibos de [pruebas](../database/evidencia/verificacion.json) e [instalación](../database/evidencia/instalacion.json) acreditan esos resultados; la recuperación combinada con Laravel y el cierre de sus temporales se registran en el seguimiento.

UX-02 añade [025](../database/migrations/025_coincidencia_habilidades_web.sql): un gateway de solo lectura, `banco.web_coincidencia_catalogo`, que devuelve para proyectos publicados válidos cuántas habilidades requeridas tiene registradas el alumno actor y cuáles faltan. Usa la instantánea publicada y los datos propios; el profesor recibe un objeto vacío. No hay tablas, columnas ni datos nuevos. El 12 de noviembre de 2026 la suite SQL 001–025 pasó con 411 negativos y quedó en 149 funciones; la base de trabajo recibió solo 025 después de un respaldo y una segunda migración no hizo cambios.
UX-04 añade [026](../database/migrations/026_documentos_pdf_web.sql), conforme a la modificación de D-11: esquema `adjunto` y tabla `adjunto.documento` con titular, tipo (`curriculum` o `evidencia`), habilidad para evidencias, nombre original, ruta privada UUID, tamaño hasta 5 MB, SHA-256, fecha de carga y fecha de retiro. Un índice único parcial permite un solo currículum vigente; un disparador impide borrar o cambiar filas salvo para registrar una vez el retiro. Los permisos de lectura siguen `banco.consultar_perfil` (D-10). La tabla no forma parte de las 21 entidades del modelo ni del diccionario generado; la aplicación no tiene privilegios sobre ella y opera solo con los cuatro gateways. La suite SQL 001–026 pasó con 411 negativos y 154 funciones en `banco`; la base de trabajo recibió solo 026 tras su respaldo.
UX-06 añade [027](../database/migrations/027_recomendaciones_web.sql): `banco.web_recomendaciones`, de solo lectura, devuelve hasta 20 proyectos publicados válidos con plazas libres en los que el alumno actor no tiene candidatura ni asignación, con al menos una habilidad coincidente. Ordena por obligatorias faltantes, proporción y número de coincidencias; usa la instantánea publicada y la regla de 025. El profesor recibe un arreglo vacío. Sin tablas, columnas ni datos nuevos. La suite SQL 001–027 pasó con 411 negativos y 155 funciones; la base de trabajo recibió solo 027 tras el respaldo `20261112T151224.dump`.
UX-07 añade [028](../database/migrations/028_constancia_participacion_web.sql): `banco.web_constancia`, de solo lectura, devuelve folio, participante, proyecto, empresa, periodo, directores y alumnos de una participación concluida con el cierre del proyecto (asignación finalizada, sin retiro, proyecto finalizado). Usa la apertura de `web_abrir_participacion` y además exige que el actor sea el titular o la administración; en otro caso responde `23503`. Sin tablas, columnas ni datos nuevos. La suite SQL 001–028 pasó con 411 negativos y 156 funciones; la base de trabajo recibió solo 028 tras el respaldo `20261112T152639.dump`.
UX-08 añade [029](../database/migrations/029_imagenes_web.sql): tabla `adjunto.imagen` con tipo (`foto` o `logo`), titular (usuario para la foto, empresa para el logo), quién la subió, ruta privada UUID `.webp`, tamaño hasta 1 MB, SHA-256, fecha de carga y de retiro. Índices únicos parciales permiten una foto vigente por persona y un logo vigente por empresa; el disparador de 026 conserva las filas y solo admite registrar el retiro una vez. `adjunto.puede_ver_foto` aplica el ámbito de `banco.consultar_perfil` (D-10); el logo lo ve cualquier cuenta activa. Cuatro gateways: registrar, retirar, mapa de imágenes visibles (por usuario, empresa o proyecto) y apertura. La aplicación no tiene privilegios sobre la tabla. La suite SQL 001–029 pasó con 411 negativos y 160 funciones en `banco`; la base de trabajo recibió solo 029 tras el respaldo `20261112T161833.dump`.
UX-09 añade [030](../database/migrations/030_panorama_reportes_web.sql): `banco.web_panorama_reportes`, de solo lectura y exclusivo de la administración, devuelve los conteos globales por estado de proyectos, candidaturas y solicitudes de dirección (con los estados en cero) y la carga vigente de cada profesor que dirige proyectos frente al límite de tres de D-04. Usa los mismos criterios que `web_reporte` sin filtros. Sin tablas, columnas ni datos nuevos. La suite SQL 001–030 pasó con 411 negativos y 161 funciones; la base de trabajo recibió solo 030 tras el respaldo `20261112T175933.dump`.
UX-10 añade [031](../database/migrations/031_catalogo_habilidades_web.sql): `banco.normalizar_habilidad` (minúsculas, sin acentos ni espacios repetidos), `banco.usos_habilidad` (alumnos, proyectos, evidencias e instantáneas publicadas) y tres gateways de administración: listar con usos y posibles duplicados, crear o editar rechazando nombres equivalentes (`23505`) y eliminar solo habilidades sin ningún uso (`55000` si se usan). Los cambios se auditan. No hay índice único porque podría haber duplicados previos; se señalan y no se fusionan, ya que las instantáneas guardan el identificador. La suite SQL 001–031 pasó con 411 negativos y 166 funciones; la base de trabajo recibió solo 031 tras el respaldo `20261112T185507.dump` y no tenía duplicados.

<!-- diccionario generado -->

## Diccionario físico

Generado del catálogo PostgreSQL con `python database/manage.py dictionary`. No editar las tablas a mano.

### acompanamiento

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `asignacion_alumno_id` | bigint | No | - |
| `asignacion_direccion_id` | bigint | No | - |
| `inicio` | timestamp with time zone | No | - |
| `fin` | timestamp with time zone | Sí | - |
| `estado` | text | No | 'vigente'::text |
| `evento_retiro_id` | bigint | Sí | - |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `acompanamiento_asignacion_alumno_id_fkey`: `FOREIGN KEY (asignacion_alumno_id) REFERENCES banco.asignacion_alumno(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `acompanamiento_asignacion_alumno_id_not_null`: `NOT NULL asignacion_alumno_id`.
- `acompanamiento_asignacion_direccion_id_fkey`: `FOREIGN KEY (asignacion_direccion_id) REFERENCES banco.asignacion_direccion(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `acompanamiento_asignacion_direccion_id_not_null`: `NOT NULL asignacion_direccion_id`.
- `acompanamiento_estado_check`: `CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text])))`.
- `acompanamiento_estado_not_null`: `NOT NULL estado`.
- `acompanamiento_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `acompanamiento_evento_retiro_id_fkey`: `FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `acompanamiento_id_not_null`: `NOT NULL id`.
- `acompanamiento_inicio_not_null`: `NOT NULL inicio`.
- `acompanamiento_pkey`: `PRIMARY KEY (id)`.
- `ck_acompanamiento_fechas`: `CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))`.
- `ct_acompanamiento_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.

### alumno

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `usuario_id` | bigint | No | - |
| `matricula` | text | No | - |
| `carrera` | text | Sí | - |
| `semestre` | smallint | Sí | - |
| `datos_academicos` | text | Sí | - |
| `contacto_correo` | text | Sí | - |
| `contacto_telefono` | text | Sí | - |

Restricciones:

- `alumno_matricula_check`: `CHECK ((btrim(matricula) <> ''::text))`.
- `alumno_matricula_key`: `UNIQUE (matricula)`.
- `alumno_matricula_not_null`: `NOT NULL matricula`.
- `alumno_pkey`: `PRIMARY KEY (usuario_id)`.
- `alumno_semestre_check`: `CHECK ((semestre > 0))`.
- `alumno_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `alumno_usuario_id_not_null`: `NOT NULL usuario_id`.

### alumno_habilidad

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `alumno_id` | bigint | No | - |
| `habilidad_id` | bigint | No | - |
| `nivel_dominio` | text | Sí | - |
| `descripcion` | text | Sí | - |
| `evidencia` | text | Sí | - |

Restricciones:

- `alumno_habilidad_alumno_id_fkey`: `FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `alumno_habilidad_alumno_id_not_null`: `NOT NULL alumno_id`.
- `alumno_habilidad_habilidad_id_fkey`: `FOREIGN KEY (habilidad_id) REFERENCES banco.habilidad(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `alumno_habilidad_habilidad_id_not_null`: `NOT NULL habilidad_id`.
- `alumno_habilidad_pkey`: `PRIMARY KEY (alumno_id, habilidad_id)`.

### asignacion_alumno

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `candidatura_id` | bigint | No | - |
| `decision_id` | bigint | No | - |
| `alumno_id` | bigint | No | - |
| `proyecto_id` | bigint | No | - |
| `resultado_decision` | text | No | Generada: 'aprobada'::text |
| `inicio` | timestamp with time zone | No | - |
| `fin` | timestamp with time zone | Sí | - |
| `estado` | text | No | 'vigente'::text |
| `evento_retiro_id` | bigint | Sí | - |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `asignacion_alumno_alumno_id_fkey`: `FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_alumno_alumno_id_not_null`: `NOT NULL alumno_id`.
- `asignacion_alumno_candidatura_id_key`: `UNIQUE (candidatura_id)`.
- `asignacion_alumno_candidatura_id_not_null`: `NOT NULL candidatura_id`.
- `asignacion_alumno_decision_id_fkey`: `FOREIGN KEY (decision_id) REFERENCES banco.decision_administrativa(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_alumno_decision_id_key`: `UNIQUE (decision_id)`.
- `asignacion_alumno_decision_id_not_null`: `NOT NULL decision_id`.
- `asignacion_alumno_estado_check`: `CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text])))`.
- `asignacion_alumno_estado_not_null`: `NOT NULL estado`.
- `asignacion_alumno_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_alumno_evento_retiro_id_fkey`: `FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_alumno_id_not_null`: `NOT NULL id`.
- `asignacion_alumno_inicio_not_null`: `NOT NULL inicio`.
- `asignacion_alumno_pkey`: `PRIMARY KEY (id)`.
- `asignacion_alumno_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_alumno_proyecto_id_not_null`: `NOT NULL proyecto_id`.
- `asignacion_alumno_resultado_decision_not_null`: `NOT NULL resultado_decision`.
- `ck_asignacion_alumno_fechas`: `CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))`.
- `ct_asignacion_alumno_aprobacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_alumno_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_alumno_minimos`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_alumno_vigencias`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `fk_asignacion_alumno_aprobacion`: `FOREIGN KEY (decision_id, candidatura_id, resultado_decision) REFERENCES banco.decision_administrativa(id, candidatura_id, resultado) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `fk_asignacion_alumno_origen`: `FOREIGN KEY (candidatura_id, alumno_id, proyecto_id) REFERENCES banco.candidatura(id, alumno_id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

### asignacion_direccion

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `solicitud_direccion_id` | bigint | No | - |
| `decision_id` | bigint | No | - |
| `profesor_id` | bigint | No | - |
| `proyecto_id` | bigint | No | - |
| `resultado_decision` | text | No | Generada: 'aprobada'::text |
| `inicio` | timestamp with time zone | No | - |
| `fin` | timestamp with time zone | Sí | - |
| `estado` | text | No | 'vigente'::text |
| `evento_retiro_id` | bigint | Sí | - |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `asignacion_direccion_decision_id_fkey`: `FOREIGN KEY (decision_id) REFERENCES banco.decision_administrativa(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_direccion_decision_id_key`: `UNIQUE (decision_id)`.
- `asignacion_direccion_decision_id_not_null`: `NOT NULL decision_id`.
- `asignacion_direccion_estado_check`: `CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text])))`.
- `asignacion_direccion_estado_not_null`: `NOT NULL estado`.
- `asignacion_direccion_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_direccion_evento_retiro_id_fkey`: `FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_direccion_id_not_null`: `NOT NULL id`.
- `asignacion_direccion_inicio_not_null`: `NOT NULL inicio`.
- `asignacion_direccion_pkey`: `PRIMARY KEY (id)`.
- `asignacion_direccion_profesor_id_fkey`: `FOREIGN KEY (profesor_id) REFERENCES banco.profesor(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_direccion_profesor_id_not_null`: `NOT NULL profesor_id`.
- `asignacion_direccion_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `asignacion_direccion_proyecto_id_not_null`: `NOT NULL proyecto_id`.
- `asignacion_direccion_resultado_decision_not_null`: `NOT NULL resultado_decision`.
- `asignacion_direccion_solicitud_direccion_id_key`: `UNIQUE (solicitud_direccion_id)`.
- `asignacion_direccion_solicitud_direccion_id_not_null`: `NOT NULL solicitud_direccion_id`.
- `ck_asignacion_direccion_fechas`: `CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))`.
- `ct_asignacion_direccion_aprobacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_direccion_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_direccion_minimos`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_asignacion_direccion_vigencias`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `fk_asignacion_direccion_aprobacion`: `FOREIGN KEY (decision_id, solicitud_direccion_id, resultado_decision) REFERENCES banco.decision_administrativa(id, solicitud_direccion_id, resultado) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `fk_asignacion_direccion_origen`: `FOREIGN KEY (solicitud_direccion_id, profesor_id, proyecto_id) REFERENCES banco.solicitud_direccion(id, profesor_id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.

### candidatura

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `alumno_id` | bigint | No | - |
| `proyecto_id` | bigint | No | - |
| `fecha_solicitud` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `estado` | text | No | 'pendiente_evaluacion'::text |
| `observaciones` | text | Sí | - |
| `evento_cierre_id` | bigint | Sí | - |
| `evaluacion_vigente_id` | bigint | Sí | - |
| `evento_preseleccion_id` | bigint | Sí | - |

Restricciones:

- `candidatura_alumno_id_fkey`: `FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `candidatura_alumno_id_not_null`: `NOT NULL alumno_id`.
- `candidatura_estado_check`: `CHECK ((estado = ANY (ARRAY['pendiente_evaluacion'::text, 'evaluada'::text, 'preseleccionada'::text, 'aprobada'::text, 'rechazada'::text, 'cancelada'::text])))`.
- `candidatura_estado_not_null`: `NOT NULL estado`.
- `candidatura_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `candidatura_evento_preseleccion_id_fkey`: `FOREIGN KEY (evento_preseleccion_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `candidatura_fecha_solicitud_not_null`: `NOT NULL fecha_solicitud`.
- `candidatura_id_not_null`: `NOT NULL id`.
- `candidatura_pkey`: `PRIMARY KEY (id)`.
- `candidatura_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `candidatura_proyecto_id_not_null`: `NOT NULL proyecto_id`.
- `ck_candidatura_cierre`: `CHECK (((evento_cierre_id IS NULL) OR (estado = 'cancelada'::text)))`.
- `ct_candidatura_aprobacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_candidatura_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `fk_candidatura_evaluacion_exacta`: `FOREIGN KEY (evaluacion_vigente_id, id) REFERENCES banco.evaluacion_candidato(id, candidatura_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `uq_candidatura_origen`: `UNIQUE (id, alumno_id, proyecto_id)`.

### criterio_evaluacion

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `nombre` | text | No | - |
| `descripcion` | text | Sí | - |
| `escala` | text | Sí | - |
| `ponderacion` | numeric | Sí | - |
| `codigo` | text | Sí | - |

Restricciones:

- `ck_ponderacion_finita`: `CHECK (((ponderacion IS NULL) OR (ponderacion <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric]))))`.
- `criterio_evaluacion_id_not_null`: `NOT NULL id`.
- `criterio_evaluacion_nombre_check`: `CHECK ((btrim(nombre) <> ''::text))`.
- `criterio_evaluacion_nombre_not_null`: `NOT NULL nombre`.
- `criterio_evaluacion_pkey`: `PRIMARY KEY (id)`.

### decision_administrativa

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `administrador_usuario_id` | bigint | No | - |
| `revision_proyecto_id` | bigint | Sí | - |
| `candidatura_id` | bigint | Sí | - |
| `solicitud_direccion_id` | bigint | Sí | - |
| `fecha` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `resultado` | text | No | - |
| `justificacion` | text | No | - |

Restricciones:

- `ck_correccion_solo_revision`: `CHECK (((resultado <> 'en_correccion'::text) OR (revision_proyecto_id IS NOT NULL)))`.
- `ck_decision_justificacion_texto`: `CHECK ((justificacion ~ '[^[:space:]]'::text))`.
- `ck_decision_objeto_unico`: `CHECK ((num_nonnulls(revision_proyecto_id, candidatura_id, solicitud_direccion_id) = 1))`.
- `ct_decision_participacion_aprobacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `decision_administrativa_administrador_usuario_id_fkey`: `FOREIGN KEY (administrador_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `decision_administrativa_administrador_usuario_id_not_null`: `NOT NULL administrador_usuario_id`.
- `decision_administrativa_candidatura_id_fkey`: `FOREIGN KEY (candidatura_id) REFERENCES banco.candidatura(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `decision_administrativa_fecha_not_null`: `NOT NULL fecha`.
- `decision_administrativa_id_not_null`: `NOT NULL id`.
- `decision_administrativa_justificacion_check`: `CHECK ((btrim(justificacion) <> ''::text))`.
- `decision_administrativa_justificacion_not_null`: `NOT NULL justificacion`.
- `decision_administrativa_pkey`: `PRIMARY KEY (id)`.
- `decision_administrativa_resultado_check`: `CHECK ((resultado = ANY (ARRAY['aprobada'::text, 'rechazada'::text, 'en_correccion'::text])))`.
- `decision_administrativa_resultado_not_null`: `NOT NULL resultado`.
- `decision_administrativa_revision_proyecto_id_fkey`: `FOREIGN KEY (revision_proyecto_id) REFERENCES banco.revision_proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `decision_administrativa_solicitud_direccion_id_fkey`: `FOREIGN KEY (solicitud_direccion_id) REFERENCES banco.solicitud_direccion(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `uq_decision_candidatura`: `UNIQUE (id, candidatura_id, resultado)`.
- `uq_decision_direccion`: `UNIQUE (id, solicitud_direccion_id, resultado)`.

### detalle_evaluacion

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `evaluacion_id` | bigint | No | - |
| `criterio_id` | bigint | No | - |
| `puntuacion` | numeric | No | - |
| `comentario` | text | Sí | - |
| `definicion_aplicada` | jsonb | No | - |

Restricciones:

- `ct_detalle_d08`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `detalle_evaluacion_criterio_id_fkey`: `FOREIGN KEY (criterio_id) REFERENCES banco.criterio_evaluacion(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `detalle_evaluacion_criterio_id_not_null`: `NOT NULL criterio_id`.
- `detalle_evaluacion_definicion_aplicada_check`: `CHECK ((jsonb_typeof(definicion_aplicada) = 'object'::text))`.
- `detalle_evaluacion_definicion_aplicada_not_null`: `NOT NULL definicion_aplicada`.
- `detalle_evaluacion_evaluacion_id_fkey`: `FOREIGN KEY (evaluacion_id) REFERENCES banco.evaluacion_candidato(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `detalle_evaluacion_evaluacion_id_not_null`: `NOT NULL evaluacion_id`.
- `detalle_evaluacion_pkey`: `PRIMARY KEY (evaluacion_id, criterio_id)`.
- `detalle_evaluacion_puntuacion_check`: `CHECK ((puntuacion <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric])))`.
- `detalle_evaluacion_puntuacion_not_null`: `NOT NULL puntuacion`.

### empresa

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `razon_social` | text | No | - |
| `sector` | text | Sí | - |
| `identificacion` | text | Sí | - |
| `contacto_nombre` | text | Sí | - |
| `contacto_correo` | text | Sí | - |
| `contacto_telefono` | text | Sí | - |

Restricciones:

- `ct_empresa_representante`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `empresa_id_not_null`: `NOT NULL id`.
- `empresa_pkey`: `PRIMARY KEY (id)`.
- `empresa_razon_social_check`: `CHECK ((btrim(razon_social) <> ''::text))`.
- `empresa_razon_social_not_null`: `NOT NULL razon_social`.

### evaluacion_candidato

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `candidatura_id` | bigint | No | - |
| `evaluador_usuario_id` | bigint | No | - |
| `fecha` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `comentarios` | text | Sí | - |
| `recomendacion` | text | Sí | - |
| `version_rubrica` | smallint | Sí | - |

Restricciones:

- `ck_evaluacion_rubrica_version`: `CHECK (((version_rubrica IS NULL) OR (version_rubrica = 1)))`.
- `ct_evaluacion_d08`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `evaluacion_candidato_candidatura_id_fkey`: `FOREIGN KEY (candidatura_id) REFERENCES banco.candidatura(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `evaluacion_candidato_candidatura_id_not_null`: `NOT NULL candidatura_id`.
- `evaluacion_candidato_evaluador_usuario_id_fkey`: `FOREIGN KEY (evaluador_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `evaluacion_candidato_evaluador_usuario_id_not_null`: `NOT NULL evaluador_usuario_id`.
- `evaluacion_candidato_fecha_not_null`: `NOT NULL fecha`.
- `evaluacion_candidato_id_not_null`: `NOT NULL id`.
- `evaluacion_candidato_pkey`: `PRIMARY KEY (id)`.
- `uq_evaluacion_origen`: `UNIQUE (id, candidatura_id)`.

### evento_auditoria

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `actor_usuario_id` | bigint | Sí | - |
| `origen` | text | No | - |
| `operacion` | text | No | - |
| `fecha` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `entidad_afectada` | text | No | - |
| `registro_afectado` | text | No | - |
| `transicion` | text | Sí | - |
| `resultado` | text | No | - |

Restricciones:

- `ck_auditoria_actor`: `CHECK ((((origen = 'usuario'::text) AND (actor_usuario_id IS NOT NULL)) OR ((origen = 'sistema'::text) AND (actor_usuario_id IS NULL))))`.
- `evento_auditoria_actor_usuario_id_fkey`: `FOREIGN KEY (actor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `evento_auditoria_entidad_afectada_check`: `CHECK ((btrim(entidad_afectada) <> ''::text))`.
- `evento_auditoria_entidad_afectada_not_null`: `NOT NULL entidad_afectada`.
- `evento_auditoria_fecha_not_null`: `NOT NULL fecha`.
- `evento_auditoria_id_not_null`: `NOT NULL id`.
- `evento_auditoria_operacion_check`: `CHECK ((btrim(operacion) <> ''::text))`.
- `evento_auditoria_operacion_not_null`: `NOT NULL operacion`.
- `evento_auditoria_origen_check`: `CHECK ((origen = ANY (ARRAY['usuario'::text, 'sistema'::text])))`.
- `evento_auditoria_origen_not_null`: `NOT NULL origen`.
- `evento_auditoria_pkey`: `PRIMARY KEY (id)`.
- `evento_auditoria_registro_afectado_check`: `CHECK ((btrim(registro_afectado) <> ''::text))`.
- `evento_auditoria_registro_afectado_not_null`: `NOT NULL registro_afectado`.
- `evento_auditoria_resultado_check`: `CHECK ((btrim(resultado) <> ''::text))`.
- `evento_auditoria_resultado_not_null`: `NOT NULL resultado`.

### habilidad

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `nombre` | text | No | - |
| `tipo` | text | No | - |
| `descripcion` | text | Sí | - |

Restricciones:

- `habilidad_id_not_null`: `NOT NULL id`.
- `habilidad_nombre_check`: `CHECK ((btrim(nombre) <> ''::text))`.
- `habilidad_nombre_not_null`: `NOT NULL nombre`.
- `habilidad_pkey`: `PRIMARY KEY (id)`.
- `habilidad_tipo_check`: `CHECK ((tipo = ANY (ARRAY['dura'::text, 'blanda'::text])))`.
- `habilidad_tipo_not_null`: `NOT NULL tipo`.

### notificacion

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `destinatario_usuario_id` | bigint | No | - |
| `evento_id` | bigint | No | - |
| `mensaje` | text | No | - |
| `fecha` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `fecha_lectura` | timestamp with time zone | Sí | - |

Restricciones:

- `ck_notificacion_lectura`: `CHECK (((fecha_lectura IS NULL) OR (fecha_lectura >= fecha)))`.
- `notificacion_destinatario_usuario_id_fkey`: `FOREIGN KEY (destinatario_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `notificacion_destinatario_usuario_id_not_null`: `NOT NULL destinatario_usuario_id`.
- `notificacion_evento_id_fkey`: `FOREIGN KEY (evento_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `notificacion_evento_id_not_null`: `NOT NULL evento_id`.
- `notificacion_fecha_not_null`: `NOT NULL fecha`.
- `notificacion_id_not_null`: `NOT NULL id`.
- `notificacion_mensaje_check`: `CHECK ((btrim(mensaje) <> ''::text))`.
- `notificacion_mensaje_not_null`: `NOT NULL mensaje`.
- `notificacion_pkey`: `PRIMARY KEY (id)`.
- `uq_notificacion_evento_destinatario`: `UNIQUE (evento_id, destinatario_usuario_id)`.

### profesor

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `usuario_id` | bigint | No | - |
| `numero_empleado` | text | No | - |
| `especialidad` | text | Sí | - |
| `experiencia` | text | Sí | - |
| `contacto_correo` | text | Sí | - |
| `contacto_telefono` | text | Sí | - |

Restricciones:

- `profesor_numero_empleado_check`: `CHECK ((btrim(numero_empleado) <> ''::text))`.
- `profesor_numero_empleado_key`: `UNIQUE (numero_empleado)`.
- `profesor_numero_empleado_not_null`: `NOT NULL numero_empleado`.
- `profesor_pkey`: `PRIMARY KEY (usuario_id)`.
- `profesor_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `profesor_usuario_id_not_null`: `NOT NULL usuario_id`.

### proyecto

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `empresa_id` | bigint | No | - |
| `autor_usuario_id` | bigint | No | - |
| `titulo` | text | No | - |
| `descripcion` | text | Sí | - |
| `problematica` | text | Sí | - |
| `objetivos` | text | Sí | - |
| `justificacion` | text | Sí | - |
| `alcance` | text | Sí | - |
| `requisitos_academicos` | text | Sí | - |
| `duracion_estimada` | text | Sí | - |
| `modalidad` | text | Sí | - |
| `fecha_inicio_estimada` | date | Sí | - |
| `fecha_fin_estimada` | date | Sí | - |
| `recursos` | text | Sí | - |
| `estado` | text | No | 'borrador'::text |
| `revision_publicada_id` | bigint | Sí | - |
| `cupo_maximo_alumnos` | integer | Sí | - |
| `evento_inicio_id` | bigint | Sí | - |
| `evento_estado_id` | bigint | Sí | - |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `ck_proyecto_cierre_evidencia`: `CHECK (((estado = ANY (ARRAY['finalizado'::text, 'cancelado'::text])) = (evento_cierre_id IS NOT NULL)))`.
- `ck_proyecto_cupo_positivo`: `CHECK (((cupo_maximo_alumnos IS NULL) OR (cupo_maximo_alumnos > 0)))`.
- `ck_proyecto_fechas`: `CHECK (((fecha_inicio_estimada IS NULL) OR (fecha_fin_estimada IS NULL) OR (fecha_fin_estimada >= fecha_inicio_estimada)))`.
- `ck_proyecto_inicio_evidencia`: `CHECK ((((estado <> ALL (ARRAY['en_curso'::text, 'pausado'::text])) OR (evento_inicio_id IS NOT NULL)) AND ((evento_inicio_id IS NULL) OR (estado = ANY (ARRAY['en_curso'::text, 'pausado'::text, 'finalizado'::text, 'cancelado'::text]))) AND ((estado <> 'pausado'::text) OR (evento_estado_id IS NOT NULL)) AND ((evento_estado_id IS NULL) OR (evento_inicio_id IS NOT NULL))))`.
- `ct_proyecto_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_proyecto_minimos`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `fk_proyecto_revision_publicada`: `FOREIGN KEY (revision_publicada_id, id) REFERENCES banco.revision_proyecto(id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_autor_usuario_id_fkey`: `FOREIGN KEY (autor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_autor_usuario_id_not_null`: `NOT NULL autor_usuario_id`.
- `proyecto_empresa_id_fkey`: `FOREIGN KEY (empresa_id) REFERENCES banco.empresa(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_empresa_id_not_null`: `NOT NULL empresa_id`.
- `proyecto_estado_check`: `CHECK ((estado = ANY (ARRAY['borrador'::text, 'en_revision'::text, 'en_correccion'::text, 'publicado'::text, 'rechazado'::text, 'en_curso'::text, 'pausado'::text, 'finalizado'::text, 'cancelado'::text])))`.
- `proyecto_estado_not_null`: `NOT NULL estado`.
- `proyecto_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_evento_estado_id_fkey`: `FOREIGN KEY (evento_estado_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_evento_inicio_id_fkey`: `FOREIGN KEY (evento_inicio_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_id_not_null`: `NOT NULL id`.
- `proyecto_pkey`: `PRIMARY KEY (id)`.
- `proyecto_titulo_check`: `CHECK ((btrim(titulo) <> ''::text))`.
- `proyecto_titulo_not_null`: `NOT NULL titulo`.
- `uq_proyecto_evento_cierre`: `UNIQUE (evento_cierre_id)`.
- `uq_proyecto_evento_estado`: `UNIQUE (evento_estado_id)`.
- `uq_proyecto_evento_inicio`: `UNIQUE (evento_inicio_id)`.

### proyecto_habilidad

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `proyecto_id` | bigint | No | - |
| `habilidad_id` | bigint | No | - |
| `nivel_minimo` | text | Sí | - |
| `obligatoria` | boolean | No | false |

Restricciones:

- `proyecto_habilidad_habilidad_id_fkey`: `FOREIGN KEY (habilidad_id) REFERENCES banco.habilidad(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_habilidad_habilidad_id_not_null`: `NOT NULL habilidad_id`.
- `proyecto_habilidad_obligatoria_not_null`: `NOT NULL obligatoria`.
- `proyecto_habilidad_pkey`: `PRIMARY KEY (proyecto_id, habilidad_id)`.
- `proyecto_habilidad_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `proyecto_habilidad_proyecto_id_not_null`: `NOT NULL proyecto_id`.

### representacion_empresa

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `usuario_id` | bigint | No | - |
| `empresa_id` | bigint | No | - |
| `vigente` | boolean | No | true |
| `fecha_vinculacion` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `fecha_fin` | timestamp with time zone | Sí | - |

Restricciones:

- `ck_representacion_fechas`: `CHECK (((vigente AND (fecha_fin IS NULL)) OR ((NOT vigente) AND (fecha_fin IS NOT NULL) AND (fecha_fin >= fecha_vinculacion))))`.
- `ct_representacion_exacta`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `representacion_empresa_empresa_id_fkey`: `FOREIGN KEY (empresa_id) REFERENCES banco.empresa(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `representacion_empresa_empresa_id_not_null`: `NOT NULL empresa_id`.
- `representacion_empresa_fecha_vinculacion_not_null`: `NOT NULL fecha_vinculacion`.
- `representacion_empresa_pkey`: `PRIMARY KEY (usuario_id)`.
- `representacion_empresa_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `representacion_empresa_usuario_id_not_null`: `NOT NULL usuario_id`.
- `representacion_empresa_vigente_not_null`: `NOT NULL vigente`.

### revision_proyecto

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `proyecto_id` | bigint | No | - |
| `autor_usuario_id` | bigint | No | - |
| `numero` | integer | No | - |
| `fecha_envio` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `estado_revision` | text | No | 'en_revision'::text |
| `instantanea_contenido` | jsonb | No | - |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `ck_revision_cierre`: `CHECK (((estado_revision = 'cancelada'::text) = (evento_cierre_id IS NOT NULL)))`.
- `ct_revision_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `revision_proyecto_autor_usuario_id_fkey`: `FOREIGN KEY (autor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `revision_proyecto_autor_usuario_id_not_null`: `NOT NULL autor_usuario_id`.
- `revision_proyecto_estado_revision_check`: `CHECK ((estado_revision = ANY (ARRAY['en_revision'::text, 'aprobada'::text, 'en_correccion'::text, 'rechazada'::text, 'cancelada'::text])))`.
- `revision_proyecto_estado_revision_not_null`: `NOT NULL estado_revision`.
- `revision_proyecto_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `revision_proyecto_fecha_envio_not_null`: `NOT NULL fecha_envio`.
- `revision_proyecto_id_not_null`: `NOT NULL id`.
- `revision_proyecto_instantanea_contenido_check`: `CHECK ((jsonb_typeof(instantanea_contenido) = 'object'::text))`.
- `revision_proyecto_instantanea_contenido_not_null`: `NOT NULL instantanea_contenido`.
- `revision_proyecto_numero_check`: `CHECK ((numero > 0))`.
- `revision_proyecto_numero_not_null`: `NOT NULL numero`.
- `revision_proyecto_pkey`: `PRIMARY KEY (id)`.
- `revision_proyecto_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `revision_proyecto_proyecto_id_not_null`: `NOT NULL proyecto_id`.
- `uq_revision_numero`: `UNIQUE (proyecto_id, numero)`.
- `uq_revision_proyecto_pertenencia`: `UNIQUE (id, proyecto_id)`.

### solicitud_direccion

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `profesor_id` | bigint | No | - |
| `proyecto_id` | bigint | No | - |
| `fecha_solicitud` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `experiencia_aplicable` | text | Sí | - |
| `justificacion` | text | Sí | - |
| `estado` | text | No | 'pendiente'::text |
| `evento_cierre_id` | bigint | Sí | - |

Restricciones:

- `ck_solicitud_direccion_cierre`: `CHECK (((evento_cierre_id IS NULL) OR (estado = 'cancelada'::text)))`.
- `ct_solicitud_direccion_aprobacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `ct_solicitud_direccion_cierre`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `solicitud_direccion_estado_check`: `CHECK ((estado = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text, 'cancelada'::text])))`.
- `solicitud_direccion_estado_not_null`: `NOT NULL estado`.
- `solicitud_direccion_evento_cierre_id_fkey`: `FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `solicitud_direccion_fecha_solicitud_not_null`: `NOT NULL fecha_solicitud`.
- `solicitud_direccion_id_not_null`: `NOT NULL id`.
- `solicitud_direccion_pkey`: `PRIMARY KEY (id)`.
- `solicitud_direccion_profesor_id_fkey`: `FOREIGN KEY (profesor_id) REFERENCES banco.profesor(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `solicitud_direccion_profesor_id_not_null`: `NOT NULL profesor_id`.
- `solicitud_direccion_proyecto_id_fkey`: `FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT`.
- `solicitud_direccion_proyecto_id_not_null`: `NOT NULL proyecto_id`.
- `uq_solicitud_direccion_origen`: `UNIQUE (id, profesor_id, proyecto_id)`.

### usuario

| Columna | Tipo | Admite NULL | Valor inicial o generación |
| --- | --- | --- | --- |
| `id` | bigint | No | IDENTITY BY DEFAULT |
| `nombre` | text | No | - |
| `correo_normalizado` | text | No | - |
| `hash_contrasena` | text | No | - |
| `rol_principal` | text | No | - |
| `estado_cuenta` | text | No | 'activa'::text |
| `fecha_alta` | timestamp with time zone | No | CURRENT_TIMESTAMP |
| `version_acceso` | bigint | No | 1 |
| `requiere_cambio_clave` | boolean | No | false |

Restricciones:

- `ck_correo_normalizado`: `CHECK (((correo_normalizado = lower(btrim(correo_normalizado))) AND (correo_normalizado <> ''::text)))`.
- `ck_usuario_version_acceso`: `CHECK ((version_acceso > 0))`.
- `ct_usuario_representacion`: `TRIGGER DEFERRABLE INITIALLY DEFERRED`.
- `usuario_correo_normalizado_key`: `UNIQUE (correo_normalizado)`.
- `usuario_correo_normalizado_not_null`: `NOT NULL correo_normalizado`.
- `usuario_estado_cuenta_check`: `CHECK ((estado_cuenta = ANY (ARRAY['activa'::text, 'inactiva'::text])))`.
- `usuario_estado_cuenta_not_null`: `NOT NULL estado_cuenta`.
- `usuario_fecha_alta_not_null`: `NOT NULL fecha_alta`.
- `usuario_hash_contrasena_check`: `CHECK ((btrim(hash_contrasena) <> ''::text))`.
- `usuario_hash_contrasena_not_null`: `NOT NULL hash_contrasena`.
- `usuario_id_not_null`: `NOT NULL id`.
- `usuario_nombre_check`: `CHECK ((btrim(nombre) <> ''::text))`.
- `usuario_nombre_not_null`: `NOT NULL nombre`.
- `usuario_pkey`: `PRIMARY KEY (id)`.
- `usuario_requiere_cambio_clave_not_null`: `NOT NULL requiere_cambio_clave`.
- `usuario_rol_principal_check`: `CHECK ((rol_principal = ANY (ARRAY['empresa'::text, 'alumno'::text, 'profesor'::text, 'administrador'::text])))`.
- `usuario_rol_principal_not_null`: `NOT NULL rol_principal`.
- `usuario_version_acceso_not_null`: `NOT NULL version_acceso`.

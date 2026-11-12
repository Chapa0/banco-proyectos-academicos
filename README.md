# Banco de proyectos académicos

El sistema conecta necesidades tecnológicas de empresas con alumnos y profesores de Sistemas Computacionales. La institución controlará la publicación de proyectos y las asignaciones mediante un administrador, conservando el historial de cada decisión.

Esta carpeta contiene el análisis, el diseño, la base PostgreSQL y la aplicación web en Laravel para la entrega local. Los 42 requisitos funcionales del PDF se organizan en los bloques WEB-01 a WEB-07; el seguimiento conserva su alcance y comprobaciones. La web usa Laravel con Blade y Bootstrap; las APIs se diseñarán después y reutilizarán los servicios de negocio.

## Entrada de trabajo

Antes de hacer cambios, leer [AGENTS.md](../AGENTS.md), [las reglas de trabajo](docs/05-reglas-de-trabajo.md) y [el seguimiento vigente](docs/06-seguimiento.md). Después consultar las fuentes afectadas por la tarea. El seguimiento es el lugar para conocer el estado actual, los bloques, sus comprobaciones y la siguiente acción.

## Documentación del proyecto

| Documento | Contenido |
| --- | --- |
| [Proyecto original](Proyecto.pdf) | Requisitos de referencia, 12 páginas |
| [Alcance y requisitos](docs/01-alcance-y-requisitos.md) | Roles, módulos, exclusiones, reglas, permisos y flujos propuestos |
| [Arquitectura y datos](docs/02-arquitectura-y-datos.md) | Monolito modular Laravel, Blade y Bootstrap, responsabilidades e integración con PostgreSQL |
| [Plan y validación](docs/03-plan-y-validacion.md) | Fases, [inicio web](docs/03-plan-y-validacion.md#plan-de-inicio-de-la-parte-web), trazabilidad de los 42 requisitos, pruebas y criterios de entrega |
| [Elección de PostgreSQL](docs/04-eleccion-de-postgresql.md) | Comparación y fundamento técnico de la decisión del motor |
| [Reglas de trabajo](docs/05-reglas-de-trabajo.md) | Lectura inicial, fuentes, estados, comprobaciones y cierre de bloques |
| [Seguimiento](docs/06-seguimiento.md) | Estado vigente, dependencias, evidencia, problemas y siguiente acción |
| [Registro de decisiones](docs/07-registro-de-decisiones.md) | Preguntas, propuestas, acuerdos, fuentes e impacto; conserva D-01 a D-14 |
| [Presentación conceptual](tareas/01-modelo-entidad-relacion/modelo-conceptual-y-flujo.pdf) | PDF breve para el profesor: Chen simplificada, flujo y explicación |
| [Modelo entidad-relación detallado](docs/08-modelo-entidad-relacion.md) | Apoyo lógico: 21 entidades, 37 relaciones y supuestos expresos |
| [Base de datos física](docs/09-base-de-datos.md) | Esquema PostgreSQL, diccionario, restricciones y partes condicionadas |
| [Ejecución y uso de la aplicación web](web/README.md) | Instalación, recuperación, primer acceso, recorrido por rol, avisos, reportes y pruebas web |
| [Guía visual web](web/DESIGN.md) | Dirección visual, componentes, adaptación móvil, estados y muestra de interfaz |
| [Ejecución de la base de datos](database/README.md) | Migraciones SQL, entorno local, datos ficticios, pruebas y respaldo |
| [Tareas y entregas académicas](tareas/README.md) | Carpetas numeradas con PDF, diagramas y fuentes; [entrega 01](tareas/01-modelo-entidad-relacion/README.md) |

## Base de trabajo

- **Alcance confirmado por el PDF:** usuarios, empresas, proyectos, perfiles, habilidades, candidaturas, solicitudes de dirección, evaluaciones, autorizaciones, asignaciones, notificaciones, reportes y auditoría.
- **Fuera de la primera versión según el PDF:** entregables académicos, calificaciones, convenios y pagos.
- **Motor elegido:** PostgreSQL. La resolución, su fuente y su alcance están en [D-13](docs/07-registro-de-decisiones.md#d-13).
- **Cuentas y empresas:** altas por el administrador, un representante activo por empresa y una sola empresa por cuenta empresarial, conforme a [D-09](docs/07-registro-de-decisiones.md#d-09). La migración 010 añade altas internas con administrador activo y auditoría atómica: la cuenta de alumno o profesor puede preceder a su perfil; empresa, cuenta y representante se crean juntos. El relevo y cambio de estado administrativo se incorporan en SQL; WEB-02 ya integra inicio/cierre de sesión y administración de cuentas con permisos por rol.
- **Dirección docente:** máximo un director vigente por proyecto, sin codirección ni gestión de equipos en la primera versión, conforme a [D-03](docs/07-registro-de-decisiones.md#d-03). El índice por proyecto y sus pruebas de integridad/concurrencia ya están implementados en SQL.
- **Base tecnológica elegida:** Laravel con Blade y Bootstrap, confirmado por el usuario el 29 de octubre de 2026. WEB-01 instala Laravel 13.40.0, PHP 8.5.12 y Bootstrap 5.3.8, con dependencias fijadas en Composer y npm. PostgreSQL 18.6 ya está instalado para desarrollo local, con SQL versionado. Alcance e historia en [D-14](docs/07-registro-de-decisiones.md#d-14).
- **Arquitectura elegida:** monolito modular con MVC y servicios de negocio, vistas renderizadas en el servidor, permisos por recurso y PostgreSQL como protección de la integridad. La aplicación se ubicará en `web/`, separada de las herramientas existentes de `database/`.
- **Inicio web:** WEB-01 y WEB-02 preparan `web/`, conexión PostgreSQL propia, sesión, cuentas, cambio de contraseña y permisos por rol. WEB-03 define y aplica la [guía visual](web/DESIGN.md) al acceso, los paneles y las cuentas. El [seguimiento](docs/06-seguimiento.md) acredita las comprobaciones y el cierre de cada bloque; WEB-04 incorpora los datos propios de empresa y el recorrido de creación, envío, corrección y publicación; WEB-05 incorpora los perfiles propios de alumno y profesor y el catálogo autenticado de proyectos publicados válidos. [Guía de ejecución](web/README.md).
- **Candidaturas del alumno:** máximo tres activas simultáneamente, confirmado el 30 de octubre de 2026 en [D-01](docs/07-registro-de-decisiones.md#d-01), con historial conservado. D-06 confirma pendientes de evaluación, evaluadas y preseleccionadas como activas; el conteo, la unicidad activa y el envío interno están implementados y probados en PostgreSQL.
- **Cupo de alumnos por proyecto:** propuesto por la empresa y validado por el administrador antes de publicar, conforme a [D-02](docs/07-registro-de-decisiones.md#d-02). SQL ya incorpora el atributo, la instantánea revisada, la validación de publicación y el límite de plazas, sin cupo por defecto.
- **Carga del alumno:** máximo un proyecto asignado simultáneamente, con historial conservado, conforme a [D-04](docs/07-registro-de-decisiones.md#d-04). La asignación vigente consume esa carga desde su autorización según D-06; el control global está implementado y probado.
- **Inicio del proyecto:** publicado, cupo validado, al menos un alumno y un director autorizados, con confirmación expresa del administrador y sin exigir llenar el cupo, conforme a [D-05](docs/07-registro-de-decisiones.md#d-05). La función interna `banco.iniciar_proyecto` revalida condiciones y registra el evento con actor/fecha de forma atómica e idempotente.
- **Consumo y liberación:** [D-06](docs/07-registro-de-decisiones.md#d-06), confirmada el 10 de noviembre de 2026, reserva plazas y carga desde la autorización de asignaciones vigentes, incluso antes del inicio; finalizadas o revocadas dejan de contar. SQL protege los máximos y la aprobación junto con su asignación exacta en la misma transacción, sin cancelar otras candidaturas.
- **Cancelación y continuidad:** [D-07](docs/07-registro-de-decisiones.md#d-07) permite al alumno cancelar antes de asignarse y reserva el retiro posterior de alumnos/directores al administrador, con motivo e historial. Si el proyecto en curso pierde el mínimo, se pausa conservando las demás cargas. La reposición usa pendientes o nuevas solicitudes del tipo faltante y el administrador confirma la reanudación. La primera versión añade cierre definitivo administrativo coordinado, cancelación docente pendiente y conservación de registros terminales, por los acuerdos y la delegación del usuario. El contenido/cupo publicado no se modifica; un cambio sustantivo requiere otro proyecto.
- **Evaluación, acceso y avisos:** D-08 concreta una rúbrica manual de tres criterios y autorización administrativa después de preselección; D-10 define perfiles por relación, conservación y relevo; D-11 usa evidencia textual y avisos internos. El usuario delegó elegir y aplicar las opciones recomendadas el 10 de noviembre de 2026; el criterio y los límites están en [el registro](docs/07-registro-de-decisiones.md). D-12 distingue la base local del alojamiento, calendario y carga institucional todavía desconocidos.

La restricción de tres candidaturas del alumno y la de tres proyectos dirigidos por el profesor son límites diferentes. La preselección de una empresa siempre requiere la autorización administrativa correspondiente para convertirse en asignación.

La fuente SQL incluye los procesos de evaluación, autorización, cierre, cuentas y avisos internos. El [seguimiento](docs/06-seguimiento.md) y los recibos enlazados conservan el estado de instalación, pruebas y límites de cada bloque. 020 añade once funciones concretas de acceso y cuentas; [021](database/migrations/021_publicacion_web.sql) incorpora nueve gateways de empresa y publicación y siete auxiliares privados, sin lectura general de tablas ni DML. WEB-04 permite capturar datos de la empresa, guardar borradores con habilidades duras/blandas, enviar los seis campos obligatorios y el cupo, revisar, devolver, corregir, reenviar, publicar o rechazar. Se conserva cada revisión y su decisión; las operaciones generan sus avisos internos en la misma transacción. [022](database/migrations/022_perfiles_catalogo_web.sql) añade seis gateways de perfiles propios y catálogo y cinco auxiliares privados. El alumno registra datos académicos y habilidades duras/blandas con dominio, descripción y evidencia textual; el profesor completa especialidad, experiencia y contacto. El catálogo de alumno/profesor combina búsqueda, empresa, modalidad, habilidad y tipo, con páginas de 20 y disponibilidad indicativa.

WEB-06 integra candidaturas, solicitudes de dirección, cancelación propia anterior a asignación, evaluación/preselección empresarial, resolución y asignación administrativas, inicio, retiro, pausa, reposición, reanudación y cierre. [023](database/migrations/023_participacion_web.sql) añade ocho gateways y ocho auxiliares privados sobre las mismas 21 tablas. Las bandejas y el seguimiento combinan búsqueda y estado, con páginas de 20; cada rol consulta su ámbito y conserva el historial.

WEB-07 incorpora **Mis avisos** para los cuatro roles y cinco reportes exclusivos del administrador según RF-41: proyectos, candidaturas, solicitudes de dirección, carga docente y participantes asignados. La consulta del aviso no cambia su lectura; **Marcar como leído** usa POST y conserva la primera fecha aunque se repita. Los reportes usan filtros permitidos, páginas de 20 y totales de todo el conjunto filtrado. [024](database/migrations/024_avisos_reportes_web.sql) añade cuatro gateways y tres auxiliares privados, sin tablas nuevas. La [guía web](web/README.md) reúne el recorrido de uso por rol y la recuperación junto con la [guía PostgreSQL](database/README.md). El seguimiento acredita las pruebas, instalación y cierre local; las APIs y el despliegue institucional mantienen sus etapas posteriores y D-12 conserva los datos externos pendientes. No se añaden exportaciones ni correo.

Antes de implementar cada bloque se eligen y leen las habilidades pertinentes mediante la [matriz de trabajo](docs/05-reglas-de-trabajo.md#selección-de-habilidades-antes-de-implementar). Incluye Laravel, seguridad, PostgreSQL, diseño, accesibilidad y verificación según el cambio; el seguimiento distingue las habilidades aplicadas de las recomendadas para después.

## Organización sencilla

Se conservan los documentos numerados en `docs/`, con tres registros de organización: reglas, seguimiento y decisiones. Las entregas académicas solicitadas se guardan en carpetas numeradas de `tareas/`, con su PDF y fuentes editables. Los problemas y las revisiones comienzan dentro del seguimiento; se separan solo cuando su volumen lo requiera. Las versiones y sus evidencias de aplicación se abren cuando exista una entrega real de software.

Fecha del análisis inicial: 20 de octubre de 2026. Adaptación del método de trabajo: 21 de octubre de 2026. Para conocer el avance consultar [el seguimiento](docs/06-seguimiento.md).

# Alcance y requisitos del banco de proyectos académicos

La primera versión permitirá que las empresas propongan proyectos, los alumnos presenten candidaturas y los profesores soliciten dirigirlos. El administrador revisará la publicación y formalizará las asignaciones. Cada participante podrá consultar el estado de sus procesos.

La referencia funcional es [Proyecto.pdf](../Proyecto.pdf): 42 requisitos funcionales, 14 reglas de negocio, 12 requisitos no funcionales, 12 casos de uso principales y 10 criterios de aceptación. Las referencias de página corresponden al orden de las 12 páginas del archivo.

## Objetivo y resultado esperado

Gestionar un banco de proyectos que permita registrar, consultar, evaluar, autorizar y asignar participaciones, vinculando necesidades empresariales con habilidades de alumnos y especialidades docentes. El resultado será una aplicación web adaptable a escritorio y móvil, con acceso por rol y trazabilidad de las decisiones institucionales. Fuente: páginas 1 y 8.

El flujo completo demostrable será: empresa registra proyecto, administrador publica, alumno se postula, empresa evalúa y recomienda, profesor solicita dirección, administrador decide las asignaciones y el sistema registra y notifica los resultados.

## Alcance de la primera versión

Todos los módulos siguientes pertenecen al alcance de la versión inicial, aunque se implementen por etapas. Fuente: páginas 2 a 5.

| Módulo | Funciones principales | Requisitos |
| --- | --- | --- |
| Acceso y usuarios | Sesiones, cuatro roles, administración y estado de cuentas | RF-01 a RF-06 |
| Empresas | Datos de identificación y contacto; gestión de proyectos propios | RF-07, RF-12 |
| Proyectos | Contenido académico, requisitos, modalidad, fechas, borrador, revisión y publicación | RF-08 a RF-13, RF-21, RF-27, RF-33, RF-34 |
| Perfil y habilidades del alumno | Datos académicos, habilidades duras y blandas, dominio y evidencias | RF-17 a RF-20 |
| Candidaturas | Postular, consultar historial y cancelar cuando proceda; límite y duplicados | RF-22 a RF-25, RF-35 |
| Perfil y dirección docente | Perfil, especialidad, solicitud de dirección, carga e historial | RF-26 a RF-32, RF-36 |
| Evaluación empresarial | Consulta de candidatos, criterios, valoración y preselección | RF-14 a RF-16 |
| Autorizaciones y asignaciones | Decisión institucional separada para alumno y profesor; validación de límites | RF-37 a RF-40 |
| Comunicación y control | Notificaciones, reportes e historial de operaciones | RF-06, RF-41, RF-42 |

## Exclusiones y límites de la propuesta

El PDF, página 2, deja para una fase posterior la administración de entregables, calificaciones, convenios y pagos. Tampoco se añade a esta propuesta inicial una aplicación móvil nativa, chat, firma electrónica, integración con el sistema escolar ni selección automática mediante inteligencia artificial. Estas últimas son exclusiones de diseño propuestas, no prohibiciones del PDF.

El seguimiento inicial consiste en estados, participantes y eventos históricos. La evaluación de candidatos corresponde a la empresa; la decisión definitiva corresponde al administrador. La versión inicial debe incluir evaluación, notificaciones y auditoría, porque el PDF ya las exige.

## Actores y permisos

Cada cuenta tendrá un rol principal, conforme a RN-01. La matriz siguiente aplica el acceso por relación con el registro definido en [D-10](07-registro-de-decisiones.md#d-10). El titular ve su perfil completo; en perfiles compartidos se excluyen matrícula, número de empleado, correo de acceso, hash y datos administrativos de la cuenta. El contacto compartido es el capturado expresamente en el perfil.

Según [D-09](07-registro-de-decisiones.md#d-09), el administrador creará las cuentas, cada empresa tendrá un representante activo y cada cuenta empresarial se vinculará a una sola empresa. El representante podrá capturar y editar los datos de esa empresa conforme a RF-07; esta operación se distingue de crear la cuenta. Es una aclaración acordada con el usuario sobre los requisitos del PDF.

| Operación | Empresa | Alumno | Profesor | Administrador |
| --- | --- | --- | --- | --- |
| Administrar cuentas y asignar rol al crear | No | No | No | Sí; no conversión de perfiles existentes en WEB-02 |
| Cambiar contraseña propia | Propia | Propia | Propia | Propia |
| Editar perfil propio | Empresa propia | Perfil propio | Perfil propio | Gestionar datos autorizados |
| Crear y enviar proyecto | Propios | No | No | Revisar |
| Consultar proyectos | Propios | Publicados disponibles | Publicados disponibles y asignados | Todos |
| Publicar o devolver proyecto | No | No | No | Sí |
| Enviar o cancelar candidatura | No | Propia; cancelar activa antes de asignación | No | Revisar y resolver |
| Ver perfiles de candidatos | Datos académicos, habilidades, evidencias y contacto de candidatos propios | Perfil propio | Perfil académico y contacto de alumnos asignados; sin evaluaciones empresariales privadas | Registros necesarios para administrar |
| Evaluar y recomendar candidato | De sus proyectos | No | No | Consultar para resolver |
| Solicitar o cancelar dirección pendiente | No | No | Propia antes de asignación | Revisar y resolver |
| Formalizar asignaciones, retirar participantes o cerrar proyectos | No | No | No | Sí; motivo e historial en retiros y cierres |
| Consultar solicitudes y decisiones | Relacionadas con sus proyectos | Propias | Propias | Todas |
| Consultar notificaciones | Propias | Propias | Propias | Propias |
| Consultar reportes e historial global | No | No | No | Sí |

El servidor verificará sesión, cuenta activa, rol, pertenencia del registro y estado permitido en cada operación. Cambiar un identificador en una petición no debe permitir acceder a proyectos o perfiles ajenos. Fuente: RF-04, RF-05 y RNF-02, RNF-03.

### Acceso y cuentas de WEB-02

WEB-02 integra RF-01 a RF-06 en su alcance de sesión y administración de cuentas. El ingreso usa el correo normalizado y una contraseña; solo una cuenta activa con credenciales válidas puede entrar. El servidor regenera la sesión al autenticar y vuelve a comprobar cuenta, rol y versión de acceso en cada petición protegida. Cerrar sesión es una acción POST con protección CSRF; invalida la sesión y el token. El panel identifica los cuatro roles y solo el administrador puede abrir las rutas de cuentas. Cambiar la URL o enviar otro rol no amplía permisos.

Las altas son administrativas, sin autorregistro. El administrador crea alumno, profesor o administrador, o crea conjuntamente empresa, cuenta y representante; puede consultar, editar nombre/correo, activar o desactivar, restablecer una contraseña temporal y realizar el relevo empresarial. La edición y los cambios de estado o clave rechazan formularios obsoletos; el relevo comprueba el representante exacto. Los roles se asignan al crear y no se convierten perfiles existentes en este bloque. Desactivar conserva participaciones/carga y exige las salvaguardas de D-10.

Las contraseñas nuevas requieren al menos 12 caracteres y como máximo 72 bytes; Laravel genera bcrypt y nunca presenta el hash. El administrador entrega la contraseña temporal por un canal manual fuera de la aplicación; al primer acceso o después de un restablecimiento, el titular debe cambiarla antes de usar su panel, comprobando la actual y eligiendo otra diferente. No hay envío de claves por correo ni recuperación pública en esta versión. Los cambios de nombre, correo, rol, estado, hash o requisito de clave incrementan la versión y terminan las sesiones anteriores; el cambio propio renueva la sesión actual.

El inicio limita intentos por correo/IP y por IP, presenta mensajes de rechazo uniformes y no guarda contraseñas o correos de acceso en las bitácoras de intentos. Las páginas protegidas no se almacenan en caché. La preparación del primer administrador es una operación local controlada con secreto temporal privado, sin convertir las semillas en accesos conocidos. Estas concreciones técnicas se registran en D-09/D-10; [el seguimiento](06-seguimiento.md) conserva instalación, pruebas y límites. WEB-03 continuará la estructura visual de los demás flujos; proyectos, perfiles, participación y reportes aún no se gestionan desde estas pantallas.

## Reglas de negocio obligatorias

| Reglas del PDF | Interpretación de implementación |
| --- | --- |
| RN-01 | Un rol principal por usuario entre empresa, alumno, profesor y administrador |
| RN-02 | Publicar exige datos obligatorios y aprobación administrativa |
| RN-03, RN-04 | Impedir una cuarta candidatura activa del alumno, conforme a D-01; cuentan pendientes de evaluación, evaluadas y preseleccionadas según D-06 |
| RN-05, RN-10 | Impedir una cuarta dirección simultánea; contar proyectos distintos, no candidatos ni solicitudes pendientes |
| RN-06, RN-07, RN-08 | Solicitar, evaluar o recomendar no formaliza una asignación; se requiere autorización administrativa |
| RN-09 | Revalidar que el proyecto esté autorizado y disponible al asignar al alumno |
| RN-11 | Impedir dos candidaturas activas del mismo alumno para el mismo proyecto |
| RN-12, RN-13 | Conservar decisiones, rechazos y cancelaciones con su historial |
| RN-14 | Cambiar estados únicamente mediante las transiciones permitidas |

El límite de tres solicitudes de dirección pendientes no aparece en el PDF y no se impone. El máximo de un proyecto asignado simultáneamente por alumno tampoco procedía del PDF: ahora es una política institucional confirmada expresamente en D-04.

Según [D-03](07-registro-de-decisiones.md#d-03), confirmada el 29 de octubre de 2026, cada proyecto tendrá como máximo un director vigente, con autorización administrativa; la primera versión no incluirá codirección ni gestión de equipos. Este máximo por proyecto es independiente del máximo de tres proyectos por profesor de RN-05/RN-10. Puede haber cero directores antes de asignar; D-05 exige uno autorizado para iniciar. Se conserva el historial; el cupo de alumnos se define por proyecto conforme a D-02. El índice único parcial por proyecto protege la dirección vigente y está verificado con dos profesores concurrentes.

[D-02](07-registro-de-decisiones.md#d-02), confirmada el 30 de octubre de 2026, establece un cupo máximo de alumnos por proyecto, propuesto por la empresa y validado por el administrador antes de publicarlo. No se fija una cifra común ni una plaza por defecto; las asignaciones autorizadas no podrán superar la capacidad aprobada según los estados de ocupación de D-06. Este cupo no limita las candidaturas recibidas ni el total histórico de alumnos. Las asignaciones individuales pueden compartir el único director de D-03 sin incorporar gestión de equipos. D-04 limita al alumno a un proyecto asignado simultáneamente; D-05 permite iniciar sin llenar el cupo cuando se cumplan sus demás condiciones y D-07 conserva los cambios posteriores a publicación. El atributo, la instantánea con el cupo propuesto, su aprobación y el control de plazas están implementados y probados en SQL; los seis campos originales de RF-08 mantienen su identidad.

[D-04](07-registro-de-decisiones.md#d-04), confirmada el 30 de octubre de 2026, establece como máximo un proyecto asignado simultáneamente por alumno. La comprobación es global entre proyectos, mantiene las asignaciones históricas y admite que un alumno todavía no tenga ninguna. D-06 confirma que la asignación vigente consume carga desde la autorización, incluso antes del inicio; finalizada o revocada deja de contar. D-07 conserva los cierres o cambios permitidos. El acuerdo no cancela automáticamente otras candidaturas ni prohíbe seguir postulándose; tampoco cambia el máximo de tres candidaturas de D-01. El control global está implementado y probado en PostgreSQL.

[D-05](07-registro-de-decisiones.md#d-05) permite iniciar un proyecto publicado y con cupo validado cuando tenga al menos un alumno y un director autorizados. El administrador confirma expresamente el inicio; la última autorización no inicia por sí sola ni se exige llenar el cupo. La publicación, cupos, cargas y mínimo se revalidan en la misma operación. No se añaden fechas estimadas obligatorias u otra confirmación empresarial.

## Estados y transiciones

El PDF fija literalmente «Pendiente de evaluación» para CU-05; las demás etiquetas y transiciones concretan RN-14 mediante D-05 a D-08. El 10 de noviembre el usuario delegó resolver y aplicar las opciones recomendadas. El [registro](07-registro-de-decisiones.md) distingue los acuerdos expresos de esas concreciones; el [seguimiento](06-seguimiento.md) indica qué está implementado, instalado y probado.

| Objeto | Transiciones permitidas en la primera versión |
| --- | --- |
| Proyecto | Borrador → En revisión → Publicado, En corrección o Rechazado; En corrección → En revisión; Publicado → En curso por administrador y condiciones D-05; En curso → Pausado al quedar sin alumnos o sin director; Pausado → En curso por confirmación administrativa y revalidación; En curso → Finalizado por administrador; cualquier estado abierto → Cancelado por administrador |
| Revisión de proyecto | Cada envío anterior a publicación conserva una instantánea; se aprueba, rechaza o devuelve para corrección. Si se cancela el proyecto durante la revisión, la revisión pendiente se cancela sin simular un rechazo administrativo |
| Candidatura | Pendiente de evaluación → Evaluada → Preseleccionada → Aprobada con asignación administrativa atómica. Una nueva evaluación devuelve a Evaluada e invalida la preselección anterior. El administrador puede rechazar desde cualquier estado activo. El alumno puede cancelar su candidatura activa antes de asignación; el cierre del proyecto cancela las activas restantes |
| Solicitud de dirección | Pendiente → Aprobada con asignación administrativa atómica, Rechazada por administrador o Cancelada por el profesor titular antes de asignación; el cierre cancela las pendientes |
| Asignación y acompañamiento | Vigente → Revocada por retiro administrativo o cancelación del proyecto; Vigente → Finalizada al finalizar el proyecto. Conservar origen, decisión e historial; los registros cerrados no se reabren |

### Candidaturas, evaluación y autorización

[D-01](07-registro-de-decisiones.md#d-01) fija como máximo tres candidaturas activas simultáneamente entre todos los proyectos del alumno. Según D-06, cuentan pendientes de evaluación, evaluadas y preseleccionadas; rechazadas y canceladas válidamente dejan de contar. La aprobada libera candidatura al formalizar su asignación exacta en la misma transacción. Si falla la asignación, se revierte también la aprobación y la liberación. Las otras candidaturas no se cancelan por aprobar una.

La cancelación propia de [D-07](07-registro-de-decisiones.md#d-07) conserva la candidatura, audita su estado anterior y libera espacio. Solo corresponde al alumno titular activo antes de la asignación; no exige motivo ni modifica otras candidaturas o asignaciones. El profesor puede cancelar su solicitud de dirección propia pendiente antes de asignación. Ninguna de estas cancelaciones permite retirar una asignación unilateralmente.

[D-08](07-registro-de-decisiones.md#d-08) define tres criterios de evaluación empresarial: conocimientos técnicos, habilidades blandas y requisitos académicos. Cada uno usa 0 = no cumple, 1 = cumple parcialmente y 2 = cumple, con igual peso y comentario explicativo. Se conservan comentario general y recomendación sí/no. La puntuación orienta una valoración manual; no existe nota mínima automática ni asignación por puntuación. Un dato opcional ausente se explica en el comentario, sin convertirlo en obligatorio.

La empresa preselecciona expresamente sobre la última evaluación completa favorable. Reevaluar crea una nueva evaluación inmutable, conserva la anterior e invalida la preselección previa. El administrador aprueba solo una candidatura preseleccionada, con motivo, publicación válida, plaza disponible y carga compatible; puede rechazar una activa sin fabricar una evaluación innecesaria. La dirección requiere experiencia y justificación, autorización administrativa y carga disponible; no lleva evaluación empresarial del profesor. Las dos autorizaciones siguen siendo independientes.

Presentar una candidatura no reserva plaza ni exige que el alumno esté sin asignación; se comprueban máximo de tres y duplicados. Las solicitudes de dirección pendientes no consumen carga ni tienen un límite de tres. Según D-06, una asignación vigente reserva desde la autorización, incluso antes del inicio: alumno ocupa una plaza y su máximo de un proyecto; dirección ocupa la única dirección del proyecto y uno del máximo de tres del profesor. Finalizadas y revocadas dejan de contar y conservan historial. Publicar, vencer fechas estimadas o desactivar una cuenta no libera por sí mismo.

### Retiro, pausa y cierre

Solo el administrador retira a un alumno o director asignados, con motivo e historial. Si el proyecto En curso queda sin alumnos o sin director, pasa a Pausado; las demás asignaciones conservan vigencia y carga. Retirar a uno de varios alumnos no pausa mientras se conserve el mínimo. Durante Pausado se usan pendientes y nuevas solicitudes únicamente del tipo faltante, con autorización normal de D-08. Recuperar participantes no reanuda: el administrador confirma y revalida publicación, cupo, carga y al menos un alumno y el director autorizados.

Solo el administrador activo puede finalizar o cancelar el proyecto, con motivo e historial. Finalizar requiere En curso; cancelar admite cualquier estado abierto. La operación cierra conjuntamente las asignaciones y acompañamientos vigentes y cancela candidaturas activas, solicitudes de dirección y revisión pendientes, liberando las reservas correspondientes. Conserva las fuentes aprobadas, sus decisiones y la historia previa. No inventa fechas finales para períodos que todavía no comenzaron ni calificaciones o entregables académicos.

La empresa edita contenido en borrador o corrección. El contenido y cupo publicados quedan congelados; un cambio sustantivo requiere un proyecto nuevo y, cuando corresponda, cancelar el anterior. La alternativa de revisar una publicación se aplaza. No hay reapertura de registros cerrados ni altas generales En curso; la reposición mínima durante Pausado conserva su regla específica.

### Privacidad, evidencias y avisos

D-10 limita cada consulta a los registros relacionados con el actor. La empresa ve candidatos de sus proyectos; el profesor ve sus solicitudes, proyectos y alumnos asignados, sin evaluaciones empresariales privadas; el alumno ve su proceso; el administrador gestiona los registros necesarios. Desactivar una cuenta bloquea acciones nuevas y conserva participaciones e historial. El relevo empresarial es administrativo y atómico, con una nueva cuenta vinculada a la misma empresa y la anterior inactiva. No se deja a la empresa sin representante activo ni al sistema sin administrador activo.

[D-11](07-registro-de-decisiones.md#d-11) define evidencias como texto descriptivo o enlace escrito, sin adjuntos ni descargas automáticas. Los avisos son internos, persistentes y propios del destinatario; se registran en la misma transacción del evento y no duplican destinatarios. Los mensajes no contienen motivos, puntuaciones ni evidencias privadas: el detalle requiere D-10. No hay correo, SMS ni servicios externos. No se aplica purga automática en la primera versión local.

## Decisiones que afectan al alcance

D-01 a D-11 ya definen las políticas de la primera versión en [el registro](07-registro-de-decisiones.md), mediante acuerdos expresos y la delegación del usuario. Una definición no acredita ejecución: [el seguimiento](06-seguimiento.md) conserva la instalación, pruebas y límites reales de cada bloque SQL. Las funciones internas reciben identificadores y comprueban coherencia; WEB-02 integra sesión y autorización de cuentas en Laravel. Las consultas y acciones de los demás módulos se incorporarán con su flujo y deberán aplicar el mismo origen de actor autenticado.

[D-12](07-registro-de-decisiones.md#d-12) concreta una entrega local con PostgreSQL aislado, migraciones reproducibles, datos ficticios y respaldo/restauración comprobados. Fecha escolar, equipo, alojamiento, carga y compromisos de servicio institucionales siguen por conocer al preparar el despliegue; no bloquean la entrega de la base local. [D-13](07-registro-de-decisiones.md#d-13) conserva PostgreSQL y [D-14](07-registro-de-decisiones.md#d-14), Laravel con Blade y Bootstrap. La web ya cuenta con entorno, acceso y cuentas; sus recorridos de proyectos, perfiles y participación siguen en los bloques posteriores. Las APIs se diseñarán después.

## Pantallas necesarias

- Comunes: inicio y cierre de sesión, panel del rol, perfil propio y bandeja de notificaciones.
- Empresa: datos de empresa, lista de proyectos, formulario de proyecto, detalle de revisión, candidatos, perfil visible y evaluación.
- Alumno: perfil académico y habilidades, catálogo de proyectos, detalle, postulación y solicitudes con historial y cupo disponible.
- Profesor: perfil y especialidades, catálogo, solicitud de dirección, solicitudes y proyectos asignados con carga disponible.
- Administrador: usuarios, revisión de proyectos, candidaturas, solicitudes de dirección, decisiones y asignaciones, reportes e historial.

Los formularios y las acciones disponibles reflejarán el estado actual. Cada rechazo, límite alcanzado o transición inválida mostrará un motivo comprensible.

# Aplicación web

Aplicación Laravel con Blade y Bootstrap del banco de proyectos académicos. WEB-01 prepara el entorno y WEB-02 incorpora sesión, paneles de cuatro roles y administración de cuentas. WEB-03 define y aplica la [guía visual](DESIGN.md) al acceso, el cambio de contraseña, los paneles y las cuentas. WEB-04 incorpora datos propios de empresa, creación y envío de proyectos y revisión/publicación administrativa. WEB-05 incorpora perfiles propios y catálogo autenticado de publicaciones válidas. WEB-06 integra participación, evaluación, asignaciones y ciclo de proyectos. WEB-07 incorpora avisos propios, cinco reportes administrativos y la guía de entrega local. Todavía no hay APIs.

El [plan](../docs/03-plan-y-validacion.md#plan-de-inicio-de-la-parte-web) define los bloques siguientes; el [seguimiento](../docs/06-seguimiento.md) conserva los resultados y límites de las comprobaciones.

## Guía visual y trabajo de interfaz

[DESIGN.md](DESIGN.md) es la fuente de las reglas visuales. Incluye estructura, componentes, estados y criterios de accesibilidad; enlaza los [valores compartidos](design/design-tokens.json), la [muestra interactiva](design/design-preview.html) y los [wireframes](design/wireframes.html). La muestra y los wireframes son apoyos de diseño que se abren directamente en un navegador; no son rutas de la aplicación.

La plantilla común mantiene navegación visible y sección actual, con Cuentas disponible solo para el administrador. Los formularios comparten etiquetas, ayudas, errores y acciones. El listado presenta tabla en escritorio y registros apilados en móvil, con los mismos datos y acciones. Los errores 403, 404, 419 y 503 usan una plantilla independiente que no consulta identidad al renderizar; la protección sigue en middleware, Gates y servicios.

Al cambiar colores, espacios o tamaños, actualizar los valores de `design/design-tokens.json` y las variables correspondientes de `resources/css/app.css`. Antes de implementar, consultar la [matriz de habilidades](../docs/05-reglas-de-trabajo.md#selección-de-habilidades-antes-de-implementar) y aplicar las pertinentes. No se añade otra biblioteca visual ni se trasladan reglas de negocio a Blade.

El contrato visual contempla 390×844 y 1440×900, reflujo a 320 px, contenido largo, teclado, foco, contraste y movimiento reducido. Revisar también envío, vacío, validación, éxito y denegación de permiso. JavaScript mejora el aviso de envío y evita repetirlo mientras llega la respuesta; los formularios y enlaces siguen funcionando sin JavaScript. WEB-03 está completado localmente: [revisión visual](evidencia/web03/revision-visual.json), [regresión de acceso](evidencia/web03/acceso-postgres.json) e [informe del bloque](evidencia/web03/web03.json). El seguimiento conserva resultados y límites; WEB-04 aplica esta base al recorrido de publicación y WEB-05 la aplica a perfiles propios y catálogo.

## Entorno

| Componente | Versión local |
| --- | --- |
| PHP | 8.5.12 NTS x64, paquete oficial Windows revisión 1, con `pdo_pgsql` |
| Laravel | 13.40.0 |
| Composer | 2.11.2 |
| Node.js / npm | 24.14.1 / 10.5.2 |
| Vite / complemento Laravel | 8.3.7 / 3.2.1 |
| Bootstrap | 5.3.8 |
| dompdf (constancias en PDF) | 3.1.6 |
| Inter y Bootstrap Icons (rediseño RD-01) | `@fontsource-variable/inter` 5.2.8 y `bootstrap-icons` 1.13.1 con npm, sin carga desde internet |
| GD (imágenes de perfil y logos) | extensión de PHP, activada en el `php.ini` portable |
| PostgreSQL | 18.6, esquema `banco`, conexiones UTC |

`composer.lock` y `package-lock.json` fijan las dependencias. En este equipo PHP y Composer están en `proyecto/.local/tools/`, sin modificar el PATH global. `dev.ps1` usa esas herramientas si existen; en otro equipo utiliza PHP y Composer disponibles en el sistema.

Para reproducirlo en Windows, instalar [PHP 8.5](https://www.php.net/downloads.php?os=windows), [Composer](https://getcomposer.org/download/) y [Node.js 24 LTS](https://nodejs.org/en/download). Habilitar `pdo_pgsql`, `mbstring`, `openssl`, `fileinfo`, `intl`, `curl` y `zip` en PHP, además de las extensiones requeridas por Composer. Se necesita Python 3.10 o posterior para las herramientas de base y pruebas. La [guía PostgreSQL](../database/README.md#reproducir-en-otro-equipo) explica cómo preparar la instancia y su configuración privada; no se copian las credenciales de otra persona.

## Preparar y ejecutar

Desde `proyecto/`, con PostgreSQL local configurado:

```powershell
python database/manage.py start
python database/manage.py migrate
python database/provision_web.py
python database/crear_admin_web.py
cd web
.\dev.ps1 composer install
.\dev.ps1 npm ci
.\dev.ps1 npm run build
.\dev.ps1 artisan banco:comprobar-conexion --json
.\dev.ps1 serve
```

Abrir [http://127.0.0.1:8000](http://127.0.0.1:8000). `serve` permanece en ejecución; Ctrl+C lo detiene. Para modificar CSS o JavaScript con recarga, ejecutar `.\dev.ps1 npm run dev` en otra terminal dentro de `web/`.

El aprovisionamiento requiere la migración SQL 019 aplicada. Crea una credencial LOGIN local sin privilegios administrativos, miembro de `banco_web`, y genera la clave de aplicación en `.env`. Si ya existe una configuración privada, la conserva. `.env.example` no contiene secretos y `.env` está excluido de Git. No es una cuenta humana del sistema académico: la herramienta local `database/crear_admin_web.py` prepara por separado el primer administrador, con contraseña aleatoria temporal y cambio inicial obligatorio. Sus datos de ingreso quedan únicamente en `proyecto/.local/primer-acceso-web.txt`; abrirlo localmente, no compartirlo ni incluirlo al entregar fuentes. Las semillas siguen sin permitir inicio de sesión. La preparación conserva el registro del administrador ficticio exacto, pero lo deja inactivo para que no cuente como una alternativa al último administrador real.

`banco:comprobar-conexion` comprueba PDO, esquema, UTC, aislamiento y permisos mínimos sin mostrar contraseñas. El diagnóstico está en consola; la portada pública no muestra estado de conexión ni información de usuarios.

## Compartir pruebas por internet (PRUEBAS-01)

Desde `web/`, en este equipo con las dependencias ya preparadas:

```powershell
.\pruebas-publicas.ps1 Iniciar
.\pruebas-publicas.ps1 Estado
.\pruebas-publicas.ps1 Detener
```

`Iniciar` prepara `banco_pruebas_publicas` con las migraciones SQL y los datos de [DEMO-01](../database/README.md#datos-de-demostración-demo-01): 19 cuentas ficticias, cuatro empresas, catorce habilidades, nueve proyectos, once candidaturas y cinco solicitudes de dirección. Conserva los cambios de pruebas en ejecuciones posteriores y no reinicia los datos. Las cuentas y su contraseña común están en esa guía. No usa ni modifica `banco_proyectos` ni `web/.env`.

El servidor de pruebas escucha solo en `127.0.0.1:8088`, con la raíz HTTP en `public/`. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) proporciona el enlace HTTPS que muestra el comando; se comparte añadiendo `/login`. Cada reinicio del túnel genera otro enlace. El equipo debe permanecer encendido, sin suspensión y conectado a internet. No se configura arranque automático ni se acredita alojamiento permanente o carga institucional.

El entorno público usa `APP_DEBUG=false`, cookies Secure, una clave de aplicación propia y almacenamiento independiente para sesiones, caché y archivos de prueba. Laravel acepta las cabeceras del proxy únicamente desde loopback cuando está activa `BANCO_TUNEL_PUBLICO`; la configuración local conserva su comportamiento. Los procesos, registros, configuración privada y enlace vigente se guardan en `proyecto/.local/pruebas-publicas/`, fuera de Git. `Estado` consulta los procesos y `Detener` solo para los procesos identificados por ruta, PID y fecha de inicio; no elimina los datos ni detiene la web local del puerto 8000.

El ejecutable oficial de `cloudflared` se instala localmente, sin alterar el PATH:

```powershell
# Desde proyecto/; requiere acceso a GitHub.
New-Item -ItemType Directory -Path .local/tools/cloudflared -Force
Invoke-WebRequest https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe -OutFile .local/tools/cloudflared/cloudflared.exe
```

`py -3.12 tests/pruebas_publicas.py`, desde `web/` y con el túnel activo, comprueba por HTTPS las 19 cuentas, páginas permitidas por rol, cierre de sesión, rechazo de acceso administrativo, CSRF, cookies y recursos compilados. Guarda el resultado sin contraseñas en [la evidencia pública](evidencia/pruebas-publicas.json). Este recorrido registra accesos en la auditoría; no cambia decisiones ni contraseñas. La [preparación](../database/preparar_demo_publica.py) rechaza publicar una base que contenga cuentas ajenas a `demo.test`.

## Actualizar y recuperar la aplicación

Antes de actualizar una instalación con datos, detener `serve`, conservar las fuentes y archivos de bloqueo de esa versión y ejecutar `python database/manage.py backup` desde `proyecto/`. Aplicar las migraciones SQL nuevas con `manage.py migrate`, instalar las dependencias con `composer install` y `npm ci` y compilar con `npm run build`. Los comandos se ejecutan mediante `dev.ps1` como en el arranque anterior; no usar `composer update` o `npm update` para reproducir una entrega. Las migraciones SQL ya aplicadas se conservan; Artisan `migrate`, `migrate:*` y `db:wipe` permanecen bloqueados.

El dump SQL contiene los datos académicos, hashes de las cuentas, auditoría e historial técnico; no incluye `web/.env`, `APP_KEY`, credenciales LOGIN de PostgreSQL, dependencias ni sesiones/caché en archivos. Guardar la configuración privada y la clave de aplicación por separado, bajo acceso restringido y fuera de Git. Recuperar una base no recupera las sesiones web. Si se conserva configuración cifrada debe conservarse su clave correspondiente; no generar otra encima de una `APP_KEY` válida. En un entorno nuevo sin configuración, el aprovisionamiento prepara una clave y credencial propias; los usuarios vuelven a iniciar sesión con sus cuentas restauradas.
**PDF del perfil (D-11).** Los currículums y evidencias se guardan en `web/storage/app/private/documentos/`, fuera de la carpeta pública; la base solo registra sus metadatos en `adjunto.documento`. Respaldar esa carpeta junto con el dump: uno sin el otro deja enlaces sin archivo o archivos sin registro. PHP debe aceptar subidas de 5 MB: en `php.ini` usar al menos `upload_max_filesize=6M` y `post_max_size=8M` (el PHP portable de `.local/tools/php` ya lo tiene). Las pruebas usan un disco falso y no escriben en esa carpeta.

**Foto de perfil y logo (UX-08).** Se aceptan JPG, PNG o WebP de hasta 4 MB y entre 64 y 6000 px por lado. Con la extensión GD cada imagen se recorta (foto) o se encaja (logo) en un cuadrado de 320 px y se guarda como WebP en `web/storage/app/private/imagenes/`, sin metadatos. Respaldar esa carpeta junto con la de documentos. PHP necesita `extension=gd`; en el PHP portable se activó y, por un fallo de OPcache de PHP 8.5.12 con GD en el servidor web local (Laravel no podía leer `.env`), se añadió `opcache.enable=0`. En otro equipo con el mismo PHP hay que aplicar ambos ajustes.

La [recuperación PostgreSQL](../database/README.md#recuperación-local) restaura primero en otra base vacía, con roles técnicos y propietario configurados. No cargar el dump sobre una base ya migrada ni reemplazar automáticamente la base de trabajo. Una vez comprobada la copia, con la web detenida, ajustar de forma privada `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME` y `DB_PASSWORD` para ese destino y una cuenta LOGIN miembro de `banco_web`, nunca el propietario. `provision_web.py` conserva un `.env` previo; no corrige automáticamente su destino.

Desde `web/`, instalar dependencias y compilar como en la preparación; después ejecutar:

```powershell
.\dev.ps1 artisan config:clear
.\dev.ps1 artisan banco:comprobar-conexion --json
.\dev.ps1 serve
```

Comprobar inicio de sesión y una consulta permitida por cada rol, incluidos avisos y reportes administrativos. Las sesiones de la instalación anterior deben descartarse durante la recuperación; no copiar archivos de sesión entre equipos ni restaurarlos desde una fecha distinta de la base. No ejecutar semillas ni `crear_admin_web.py` para recuperar cuentas existentes. Una restauración incompatible exige revisar sus fuentes e historial antes de aplicar migraciones pendientes; no editar checksums para hacerla pasar. Esta guía describe recuperación local; alojamiento, HTTPS, carga, responsables y compromisos de servicio institucionales siguen D-12.

## Acceso y cuentas

Abrir `/login` e ingresar con los datos del archivo privado del primer administrador. El primer acceso dirige a `/clave`: escribir la temporal, elegir otra diferente y confirmarla. Las contraseñas nuevas requieren al menos 12 caracteres y como máximo 72 bytes. El sistema no envía claves por correo ni ofrece autorregistro o recuperación pública. No hay una contraseña predeterminada para las cuentas de demostración.

Cada rol dispone de su panel en `/panel`. Todos pueden cambiar su contraseña y cerrar sesión; solo el administrador tiene acceso a `/admin/cuentas`. Allí puede:

- Buscar y filtrar cuentas, consultar o editar nombre/correo con motivo.
- Crear alumno, profesor, administrador o empresa con su representante conjunto; el rol se asigna al crear y no se convierte un perfil existente.
- Activar o desactivar conservando historial y cargas; no dejar al sistema sin administrador activo ni a una empresa sin representante vigente.
- Restablecer una clave temporal con motivo o relevar al representante de una empresa mediante una cuenta nueva.

En las altas, restablecimientos y relevos, el administrador entrega la contraseña temporal por un canal manual fuera de la aplicación; el titular debe cambiarla antes de usar el panel. Los formularios no vuelven a mostrar contraseñas ni hashes en mensajes o respuestas. La edición compara la versión leída y el relevo al representante exacto; si otra operación cambió esos datos, recargar la página y revisarlos antes de volver a enviar.

El servidor vuelve a comprobar estado y versión en cada petición protegida. Cambios de nombre, correo, rol, estado, hash o requisito de clave invalidan las sesiones anteriores; el cambio propio renueva la actual. Logout usa POST y CSRF y destruye sesión/token; no basta con cerrar una pestaña. Se limitan cinco intentos fallidos por correo/IP y veinte por IP durante un minuto. Las páginas protegidas usan no-store; las cookies son HttpOnly y SameSite=Lax y la sesión se cifra en archivos. HTTPS y cookies Secure corresponden al entorno de despliegue; el arranque de esta guía permanece en loopback local.

## Empresa y publicación de proyectos

Para una cuenta empresarial, abrir **Datos de empresa** (`/empresa`) y capturar razón social, identificación, sector y contacto. Estos datos pertenecen a la empresa; el correo y la contraseña de acceso de la cuenta se administran por separado. La empresa y su representante inicial siguen creándose juntos desde cuentas administrativas.

En **Mis proyectos** (`/empresa/proyectos`):

1. Crear un borrador con título. Se pueden guardar datos incompletos y añadir después descripción, problemática, objetivos, justificación, alcance, requisitos académicos, duración, modalidad, fechas estimadas y recursos.
2. Indicar el cupo máximo de alumnos y, si corresponde, seleccionar habilidades duras/blandas del catálogo, su nivel mínimo y obligatoriedad. No se exige una cantidad mínima de habilidades.
3. Guardar y abrir el detalle. **Enviar a revisión** exige título, descripción, problemática, objetivos, justificación, alcance y cupo positivo. El envío conserva una instantánea y bloquea la edición durante la revisión.
4. Consultar el historial. Si el administrador devuelve el proyecto, revisar sus observaciones, editar y reenviar; se crea otra revisión conservando la anterior. Publicados y rechazados no se editan ni reabren desde este recorrido.

El administrador abre **Revisión de proyectos** (`/admin/proyectos`), inicialmente filtrada por pendientes. Puede cambiar filtros y consultar todos los proyectos necesarios, incluidos borradores, sin convertirlos en una revisión pendiente. En un envío pendiente, revisar la instantánea y seleccionar Publicar, Devolver para corrección o Rechazar; escribir siempre el motivo. Publicar exige confirmar exactamente el cupo propuesto en esa revisión. Si el cupo necesita cambios, devolver el proyecto para un nuevo envío de la empresa.

Los formularios comparan versiones opacas y la revisión concreta. Si otra operación cambió los datos, recargar y revisarlos antes de volver a enviar; no se sobrescribe una modificación concurrente ni se repite una decisión antigua. Los avisos de envío y resolución se generan dentro de la misma transacción SQL, sin correo externo. El detalle conserva el historial; **Mis avisos** permite consultar las notificaciones propias.

La instalación, pruebas y cierre de WEB-04 se acreditan en [el seguimiento](../docs/06-seguimiento.md). El recorrido se comprueba con `python tests/publicacion.py` desde `web/`, usando una base temporal propia y la credencial de aplicación. Los resultados de versiones anteriores no certifican las nuevas pantallas o permisos.

## Perfil y catálogo de proyectos

Alumno y profesor pueden abrir **Mi perfil** (`/perfil`) después de cambiar su contraseña temporal. No necesitan tener un perfil creado previamente. La matrícula del alumno y el número de empleado del profesor son obligatorios y únicos; los demás datos son opcionales.

- El alumno captura carrera, semestre, formación y contacto. Selecciona habilidades duras/blandas del catálogo existente y añade dominio, descripción y evidencia si corresponde. Desmarcar una habilidad retira su asociación del perfil.
- El profesor captura especialidad, experiencia y contacto. Las habilidades estructuradas corresponden al alumno; el perfil docente usa los campos académicos de RF-26.

La evidencia admite texto descriptivo o un enlace escrito, que se muestra como texto. No hay carga de archivos, enlaces ejecutables ni descarga automática. Guardar el contacto del perfil no cambia el correo de acceso. Si el perfil cambió en otra sesión, recargar y revisar antes de guardar; el formulario conserva los datos y la versión enviada después de una validación o conflicto.

Pendiente de datos: cargar las habilidades institucionales; la semilla local contiene solo «SQL de ejemplo». El formulario actual admite catálogos de hasta 200 habilidades; antes de superar ese tamaño se debe paginar o acotar su edición. El soporte de tipos duro/blando se verifica con datos temporales, sin añadir un mantenimiento del catálogo en WEB-05.

**Catálogo de proyectos** (`/catalogo`) está disponible para alumno/profesor activos, incluso antes de completar su perfil. Combina búsqueda, empresa, modalidad, habilidad y tipo de habilidad, con 20 proyectos por página. Solo muestra publicaciones aprobadas válidas con cupo autorizado; no expone borradores, motivos de revisión o datos de acceso. El detalle incluye contenido, requisitos de la instantánea aprobada y contacto empresarial.

Los proyectos con cero plazas siguen visibles. Plazas disponibles y dirección disponible se calculan desde asignaciones vigentes y son datos informativos; no reservan cupo. Desde el detalle se abre el contexto de candidatura o dirección de WEB-06. Empresa y administrador conservan sus consultas del módulo de publicación.

La instalación, pruebas y cierre de WEB-05 se consultan en [el seguimiento](../docs/06-seguimiento.md). `python tests/perfiles.py`, desde `web/`, prepara una base temporal propia para el recorrido HTTP y los permisos de la conexión; preparar o describir el ejecutor no acredita una ejecución correcta.

## Candidaturas, dirección y seguimiento

El alumno abre **Presentar candidatura** desde un proyecto publicado, revisa el contexto y confirma el envío. Debe tener perfil académico y menos de tres candidaturas activas, sin duplicar una activa del mismo proyecto. El profesor usa **Solicitar dirección**, con perfil, experiencia aplicable y justificación. No hay un máximo de tres solicitudes docentes pendientes: ese máximo corresponde a sus proyectos asignados. El envío no reserva plazas o carga.

**Mis candidaturas** y **Mis solicitudes de dirección** (`/participacion/candidatura` y `/participacion/direccion`) conservan estado e historial, con búsqueda y filtro por estado y páginas de veinte registros. El titular puede cancelar una solicitud activa anterior a la asignación, sin motivo obligatorio; después, el retiro corresponde al administrador. El alumno consulta sus evaluaciones y resoluciones; los demás roles reciben únicamente los registros y campos permitidos por su relación con el proyecto.

La empresa consulta las candidaturas de sus proyectos, el perfil académico compartido y las habilidades. Registra los tres criterios de la rúbrica con 0/1/2, comentario por criterio, comentario general y recomendación sí/no. Evaluar conserva la versión anterior e invalida una preselección previa; **Preseleccionar candidato** es otra acción expresa basada en la evaluación favorable. No asigna al alumno. El administrador aprueba la candidatura preseleccionada o rechaza una activa con motivo; resuelve independientemente la dirección docente. Aprobar crea la asignación en la misma transacción y vuelve a comprobar cupo y cargas.

**Seguimiento de proyectos** (`/seguimiento/proyectos`) presenta contenido, participantes e historial autorizados para cada rol. Para alumno/profesor incluye sus proyectos relacionados y las vacantes permitidas de proyectos pausados. El visitante de una vacante no recibe perfiles de otros participantes. El administrador confirma inicio con al menos un alumno y director autorizados, sin llenar necesariamente el cupo; registra retiros con motivo, pausa al perder el mínimo, repone solo al tipo faltante y confirma la reanudación. Solo él finaliza En curso o cancela un estado abierto con cierre coordinado e historial. No hay reapertura ni incorporaciones generales En curso.

**Constancia de participación (UX-07).** Cuando el proyecto se finaliza, el alumno y el director con participación concluida ven en su solicitud **Descargar constancia (PDF)**; la administración puede descargar cualquiera. El PDF se genera al momento con dompdf, sin recursos externos, con folio `BP-<año>-A|D<número>`. No lleva firma institucional y lo aclara al pie. Quien no es titular ni administración, o una participación no concluida, recibe «no encontrado».

Los formularios conservan una versión opaca junto a los datos enviados. Ante un conflicto, recargar y revisar antes de decidir; no se sobrescriben cambios ni se repite automáticamente la decisión. Los avisos se generan dentro de la operación SQL y se consultan en **Mis avisos**. El [seguimiento](../docs/06-seguimiento.md) registra instalación, pruebas y límites. `python tests/participacion.py`, desde `web/`, prepara una base temporal propia para verificar este recorrido.

## Avisos y reportes

Los cuatro roles acceden a **Avisos** en la navegación o **Mis avisos** desde el panel (`/avisos`). El listado muestra únicamente los propios y empieza por todos, con búsqueda de mensaje, filtro Todos/No leídos/Leídos, contador de no leídos y páginas de 20. Abrir uno permite consultar mensaje y fecha sin marcarlo automáticamente. **Marcar como leído** registra la primera lectura mediante POST y CSRF; repetir la operación mantiene esa fecha. No hay borrado de avisos.

El enlace del detalle abre la candidatura, solicitud o proyecto solo si la cuenta conserva permiso para consultarlo. Los avisos de cuentas y los recursos que ya no estén disponibles pueden carecer de enlace; el mensaje se conserva. No muestran motivos privados, rúbricas o evidencias y no se envían por correo. El aviso informa; las decisiones se realizan desde la pantalla del trámite correspondiente.

Solo el administrador dispone de **Reportes** (`/reportes`). Puede cambiar el tipo, combinar sus filtros y limpiar la consulta:

| Reporte | Filtros además de búsqueda | Qué permiten comprobar sus totales |
| --- | --- | --- |
| Proyectos | Estado y empresa | Cantidad de proyectos y alumnos/directores con asignación vigente |
| Candidaturas | Estado, empresa y proyecto | Total, activas, aprobadas, rechazadas y canceladas |
| Solicitudes de dirección | Estado, empresa, proyecto y profesor | Total, pendientes, aprobadas, rechazadas y canceladas |
| Carga de profesores | Profesor | Cantidad de profesores, direcciones vigentes y profesores con carga; incluye quienes tienen cero y cuentas inactivas que conservan carga |
| Participantes asignados | Estado, empresa y proyecto | Asignaciones, alumnos/directores vigentes e historial finalizado/revocado |

**Panorama general (UX-09):** al abrir Reportes se ven gráficas de proyectos, candidaturas y solicitudes de dirección por estado, y la carga de cada profesor frente al límite de tres; son totales de todo el sistema y cada categoría abre su reporte filtrado. Cada reporte muestra 20 filas por página. **Totales del conjunto filtrado** incluye todas sus páginas; una búsqueda sin resultados conserva totales en cero. La carga se determina por asignaciones vigentes, no por la fecha estimada ni el estado de la cuenta. Los filtros no aplicables a un tipo se rechazan. Los reportes son consultas de administración de RF-41, sin acceso para otros roles. **Exportar CSV** descarga el reporte completo con los filtros aplicados (todas las páginas, hasta 5 000 registros) en UTF-8 que Excel abre con acentos; los textos que empiezan con `=`, `+`, `-` o `@` llevan un apóstrofo para que no se interpreten como fórmulas. Los reportes y su exportación no incluyen contraseñas, identificadores académicos reservados, rúbricas o evidencias. La información refleja el momento de la consulta; recargar para obtener cambios posteriores.

## Recorrido de uso por rol

Después de que el administrador cree las cuentas y cada titular cambie su clave temporal, se puede demostrar un proyecto completo en este orden. Las instrucciones detalladas de cada pantalla están en las secciones anteriores.

| Paso | Quién | Acción y resultado esperado |
| --- | --- | --- |
| 1 | Administrador | En **Cuentas**, crear empresa con representante, alumno y profesor. Entregar sus claves temporales de forma manual; cada cuenta conserva un solo rol |
| 2 | Empresa | Completar **Datos de empresa**, crear un proyecto en **Mis proyectos**, proponer cupo y enviarlo a revisión con sus campos obligatorios |
| 3 | Administrador | En **Revisión de proyectos**, revisar el envío exacto y publicar validando su cupo, o devolver con motivo para que la empresa corrija y reenvíe |
| 4 | Alumno | Completar **Mi perfil** y habilidades, buscar el proyecto en **Catálogo**, abrirlo y presentar candidatura. En **Mis candidaturas**, consultar estado e historial o cancelar antes de asignarse |
| 5 | Profesor | Completar **Mi perfil**, abrir el proyecto del catálogo y solicitar dirección con experiencia y justificación. Consultar **Mis solicitudes** o cancelar mientras esté pendiente |
| 6 | Empresa | Abrir la candidatura de su proyecto, revisar perfil y habilidades, registrar los tres criterios con comentarios y recomendación y, si es favorable, preseleccionar expresamente |
| 7 | Administrador | Revisar y resolver candidatura preseleccionada y dirección pendiente con motivo. Aprobar crea cada asignación y revalida cupo y carga; preseleccionar no equivale a asignar |
| 8 | Administrador y participantes | Consultar **Seguimiento**. El administrador confirma inicio con al menos un alumno y director autorizados. Los participantes consultan su ámbito; retiros, pausa, reposición y reanudación mantienen las reglas descritas arriba |
| 9 | Administrador | Finalizar En curso o cancelar un estado abierto con motivo; el cierre coordinado conserva historial y libera reservas. Consultar reportes para comprobar resultados |
| 10 | Todos | Abrir **Mis avisos**, consultar los cambios que les corresponden y marcar lectura. Cerrar sesión con el botón correspondiente al terminar |

Un alumno puede mantener hasta tres candidaturas activas y solo una asignación vigente; un profesor puede dirigir hasta tres proyectos, con un director vigente por proyecto. La empresa evalúa y preselecciona; el administrador autoriza. Cada rol recibe únicamente datos y acciones de su ámbito. Una operación rechazada no debe repetirse cambiando IDs o desde otro formulario: revisar el mensaje, corregir o recargar los datos según corresponda.

## Organización y conexión

- `routes/web.php`: portada pública, login, cambio de contraseña, panel, cuentas, publicación, perfil propio, catálogo, participación, seguimiento, avisos y reportes. Middleware y Gates verifican acceso antes de la operación.
- `resources/views/layouts/app.blade.php`: plantilla común; `layouts/estado.blade.php` y `errors/` presentan errores sin consultar identidad; `inicio.blade.php` contiene la presentación pública.
- `resources/views/cuentas/_campo.blade.php`, `_clave.blade.php` y `_errores.blade.php`: parciales compartidos para campos, contraseñas y resumen de validación.
- `resources/css/app.css` y `resources/js/app.js`: Bootstrap y recursos propios compilados por Vite.
- `app/Services/ConexionPostgres.php`: comprobación de conexión y privilegios.
- `app/Models/Usuario.php` y `app/Auth/UsuarioProvider.php`: identidad adaptada al esquema y lectura de acceso por gateways; el hash se verifica en servidor y no se serializa a vistas.
- `AuthController`, `ClaveController` y `CuentaService`: coordinan validación, sesión y llamadas parametrizadas; las reglas no dependen de ocultar botones.
- `EmpresaController`, `ProyectoController`, `Admin/RevisionProyectoController`, `Http/Requests/Proyectos/` y `PublicacionService`: datos propios, borradores y publicación; Gate, validación y llamadas a los gateways de 021. Las vistas reciben banderas calculadas de acciones y datos autorizados.
- `PerfilController`, `CatalogoController`, `Http/Requests/Perfiles/`, `PerfilService` y `CatalogoService`: perfil propio y catálogo académico mediante los seis gateways de 022; validación, campos permitidos, versión y datos autorizados antes de Blade.
- `ParticipacionController`, `SeguimientoController`, `Http/Requests/Participacion/` y `ParticipacionService`: contexto/envío, bandejas, evaluación, resolución y ciclo mediante ocho gateways de 023. Las peticiones validan datos por acción y actor, y los detalles reciben acciones y campos autorizados por SQL.
- `AvisoController`, `ReporteController`, `Http/Requests/Consultas/` y `ConsultaService`: avisos propios, lectura idempotente y cinco reportes administrativos mediante cuatro gateways de 024. Filtros permitidos y paginación se validan antes de consultar; las vistas reciben únicamente campos autorizados y enlaces internos.
- `config/database.php` y `.env`: conexión `pgsql`, búsqueda de esquema `banco,public` y UTC.

La migración [019](../database/migrations/019_conexion_web.sql) da al grupo NOLOGIN `banco_web` USAGE de `banco` y lectura del directorio mínimo. [020](../database/migrations/020_acceso_web.sql) añade once gateways `SECURITY DEFINER` específicos de acceso y cuentas, con búsqueda fija y sin SELECT/DML general de tablas. Los gateways de autenticación entregan el hash de una sola cuenta al servidor para verificarlo; los listados administrativos no lo exponen. [021](../database/migrations/021_publicacion_web.sql) incorpora nueve gateways de empresa/publicación y siete auxiliares privados; reutiliza internamente envío y resolución sin conceder esas funciones internas al runtime. [022](../database/migrations/022_perfiles_catalogo_web.sql) añade seis gateways de perfiles propios/catálogo y cinco auxiliares privados, sin tablas ni columnas nuevas. [023](../database/migrations/023_participacion_web.sql) incorpora ocho gateways de participación/ciclo y ocho auxiliares privados. [024](../database/migrations/024_avisos_reportes_web.sql) incorpora cuatro gateways de avisos/reportes y tres auxiliares privados, con treinta y ocho entradas concedidas al runtime. La aplicación obtiene el actor de sesión y aplica Gates; los gateways revalidan rol, pertenencia, estado y versión cuando corresponde. La credencial no es propietaria ni superusuario y no recibe DML ni lectura general de tablas o ejecución de auxiliares.

Las migraciones SQL de `../database/migrations/` son la única fuente del esquema. Se retiraron las migraciones y semillas predeterminadas de Laravel y la aplicación bloquea Artisan `migrate`, `migrate:*` y `db:wipe`; usar `python database/manage.py migrate` desde `proyecto/`. Las sesiones y la caché usan archivos y la cola es síncrona, sin tablas técnicas nuevas. Estos archivos locales y las dependencias están excluidos de Git.

## Autorización por recurso (SEG-01)

Cada operación identifica al actor desde la sesión. Los Gates limitan el rol y los gateways PostgreSQL comprueban la pertenencia, el estado y los identificadores relacionados antes de leer o modificar datos. La versión de un formulario evita sobrescribir cambios concurrentes; conocer esa versión no otorga permiso sobre el registro. Se conserva la matriz de D-10: el administrador gestiona cuentas y procesos, los avisos son personales incluso para él y los logos son visibles para las cuentas activas.

Los documentos y las fotos viven en almacenamiento privado y se entregan únicamente por sus controladores, que vuelven a comprobar el permiso. `filesystems.disks.local.serve=false` desactiva las rutas auxiliares GET/PUT `/storage/{path}` de Laravel: un enlace firmado no reemplaza la sesión ni la autorización del registro, ni permite sobrescribir un archivo por esa vía. No se generan enlaces temporales directos a ese disco.

`py -3.12 tests/autorizacion.py` prepara una base temporal propia con DEMO-01 y verifica rutas anónimas, permisos por rol, intercambio de IDs al consultar/editar/cancelar/retirar, campos ocultos, verbos simulados y relaciones entre proyecto, revisión y asignación. Comprueba que los recursos rechazados se conservan, revierte cada caso y elimina la temporal. No escribe en la base de trabajo o la pública. [Evidencia por recurso](evidencia/autorizacion-recursos.json) y [cierre de SEG-01](../docs/06-seguimiento.md#auditoría-de-autorización-por-recurso-de-seg-01).

## Comprobaciones

Desde `web/`:

```powershell
.\dev.ps1 composer validate --strict
.\dev.ps1 composer check-platform-reqs
.\dev.ps1 composer audit
.\dev.ps1 php vendor/bin/pint --test
.\dev.ps1 artisan test "--testsuite=Unit,Feature"
python tests/postgres.py
python tests/acceso.py
python tests/publicacion.py
python tests/perfiles.py
python tests/participacion.py
python tests/comunicacion.py
py -3.12 tests/autorizacion.py
.\dev.ps1 npm run build
```

La integración PostgreSQL crea y elimina una base temporal propia, aplica el SQL real y prueba la conexión con la credencial de aplicación. No reinicia ni usa como destino de pruebas `banco_proyectos`. Requiere la configuración privada de administración y web, y no admite configuración Laravel cacheada; si la hay, ejecutar `.\dev.ps1 artisan config:clear` antes. El ejecutor detecta PHP portable o de sistema y admite `BANCO_PHP_BINARY` para indicar otro ejecutable.

[La evidencia de conexión](evidencia/postgres.json) y [la de acceso/cuentas](evidencia/web02-postgres.json) conservan resultados y huellas de fuentes. Las pruebas Unit/Feature, preparación local y recorrido de navegador se registran por separado en el seguimiento; allí se consultan las cifras finales y el cierre de cada bloque. Los recibos anteriores acreditan las fuentes y la fecha que registran, no vistas modificadas después. Ejecutar directamente toda la suite de PHPUnit sin el auxiliar no acredita integración PostgreSQL: esos casos se omiten si falta la base temporal protegida.

El repositorio local está inicializado en `proyecto/`, rama `main`, todavía sin commits. Se excluyen `.env`, `.local/`, `vendor/`, `node_modules/`, recursos compilados y archivos de ejecución; no se incluyen credenciales o clústeres al compartir fuentes.

WEB-04 está completado localmente: [informe del bloque](evidencia/web04/web04.json), [publicación HTTP](evidencia/web04/regresion-postgres.json), [regresión de acceso](evidencia/web04/acceso-regresion.json), [conexión](evidencia/web04/conexion-postgres.json) y [revisión visual](evidencia/web04/revision-visual.json). Estos recibos conservan las fuentes comprobadas; los anteriores permanecen históricos.

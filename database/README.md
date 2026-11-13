# Base de datos PostgreSQL

Objetivo: implementar y comprobar la base de datos del sistema antes de desarrollar las APIs. El diseño funcional está en [el modelo lógico](../docs/08-modelo-entidad-relacion.md); los bloques de ejecución están en [el plan](../docs/03-plan-y-validacion.md#objetivo-de-implementación-de-la-base-de-datos).

Las migraciones SQL son la fuente del esquema físico. Los datos, herramientas y credenciales locales se guardan en `.local/`, que no forma parte de la entrega. Nunca utilizar una base ajena para ejecutar pruebas.

Las decisiones y sus fuentes se conservan en [el registro](../docs/07-registro-de-decisiones.md). El usuario delegó completar las opciones de la primera versión. La base local y la aplicación web tienen entregas distintas.

## Entorno preparado

Se preparó una instancia portable PostgreSQL 18.6 propia del proyecto, en `127.0.0.1:55432`, base `banco_proyectos`, esquema `banco`, UTF8 y conexiones UTC. El PostgreSQL 10 existente en el equipo no se modifica. Esta instancia se inicia manualmente; no se instaló como servicio ni se arranca Docker.

La configuración está en `.local/connection.json`; contiene rutas y datos de conexión, no la contraseña. `passfile` señala un archivo privado de autenticación. No incluir `.local/` al compartir las fuentes. El ejecutor rechaza destinos remotos, cadenas de conexión en el nombre de base y servidores de otra rama; nunca utiliza la contraseña de otra instalación.

## Comandos

Ejecutar desde la carpeta `proyecto/`, con Python 3.10 o posterior. No se requieren paquetes adicionales de Python.

```powershell
python database/manage.py start
python database/manage.py status
python database/manage.py migrate
python database/manage.py seed
python database/manage.py test
python database/manage.py backup
python database/manage.py restore-check
python database/manage.py snapshot
python database/manage.py dictionary
```

`migrate` crea la base del proyecto si no existe y aplica cada archivo una vez. Una migración fallida se revierte; se rechazan archivos modificados o desaparecidos después de aplicarse. Las evoluciones posteriores usan un nuevo archivo numerado. No editar las migraciones que ya están registradas en una instalación.

`seed` añade ejemplos identificados como ficticios y puede repetirse sin duplicarlos. No genera claves de acceso válidas ni participaciones autorizadas. `test` crea bases temporales propias, aplica migraciones, verifica datos/restricciones/concurrencia y comprueba respaldo y restauración; no reinicia ni vacía la base de trabajo. Los procesos temporales se cierran incluso ante errores. Un fallo devuelve salida distinta de cero; solo una ejecución completa correcta actualiza [la evidencia](evidencia/verificacion.json).

`backup` conserva un archivo custom nuevo en `.local/backups/`. `restore-check` requiere antes `migrate` con las mismas fuentes actuales: rechaza versiones pendientes o checksum diferentes antes de crear un respaldo o una base temporal. Después restaura una copia, compara estructura, permisos, contenido, definición y estado de secuencias e historial técnico de migraciones. Comprueba que `migrate` sobre la copia sea una segunda ejecución sin cambios y vuelve a ejecutar integridad. Los roles de grupo se crean con las migraciones; para restaurar en otra instancia también deben existir. D-12 distingue esta recuperación local de los objetivos de servicio del futuro alojamiento institucional.

La [evidencia de instalación](evidencia/instalacion.json) registra las migraciones aplicadas, hashes de fuentes/esquema, datos ficticios y restauración de la base de trabajo. Es distinta de las pruebas que se ejecutan en bases temporales.

`snapshot` genera [sql/esquema.sql](sql/esquema.sql), sin propietarios ni permisos, para inspección o entrega académica. `dictionary` actualiza únicamente la sección generada de [09 Base de datos física](../docs/09-base-de-datos.md). La instalación habitual utiliza las migraciones; el esquema exportado no se carga encima de ellas.

Para detener únicamente esta instancia, una vez cerradas las conexiones de trabajo:

```powershell
python database/manage.py stop
```

## Datos de demostración (DEMO-01)

Para presentar el sistema con datos creíbles:

```
py -3.12 database/cargar_demo.py
```

Primero respalda la base de trabajo en `database/.local/backups/<fecha>-antes-demo.dump`, luego ejecuta [demo.sql](demo.sql). Si la demostración ya está cargada no hace nada; para quitarla, restaurar ese respaldo. Todo es ficticio: personas, empresas, matrículas y teléfonos inventados, y correos del dominio reservado `demo.test`. Los estados se producen con las funciones de negocio (enviar, publicar, postular, evaluar, resolver, iniciar y cerrar), así que la auditoría y los avisos son coherentes.

Todas las cuentas usan la contraseña **`Demo-Banco-2026`** y no piden cambiarla.

| Rol | Cuenta | Qué muestra |
| --- | --- | --- |
| Administración | `coordinacion@demo.test` (María Fernanda Ruiz) | Un proyecto por revisar, una candidatura preseleccionada y una solicitud de dirección pendientes; reportes con nueve proyectos |
| Empresa | `jorge.medina@demo.test` (Panadería La Espiga) | Proyecto en curso con dos alumnas y directora; inventario con candidaturas por evaluar y por preseleccionar |
| Empresa | `daniela.ortiz@demo.test` (Clínica Veterinaria Huellitas) | Expediente clínico publicado con dos candidaturas nuevas y un proyecto en revisión |
| Empresa | `ricardo.salas@demo.test` (Transportes del Golfo) | Proyecto finalizado, uno devuelto a corrección y uno rechazado con motivo |
| Empresa | `lucia.hernandez@demo.test` (Cooperativa Café Altura) | Proyecto publicado con alumna y director aprobados, una candidatura rechazada y un borrador |
| Alumno | `ana.torres@demo.test` | Perfil al 100 %, asignada a un proyecto en curso y con otra candidatura pendiente |
| Alumno | `luis.ramirez@demo.test` | Perfil y participación ficticios |
| Alumno | `valeria.gomez@demo.test` | Perfil y participación ficticios |
| Alumno | `diego.morales@demo.test` | Participación concluida con constancia disponible |
| Alumno | `camila.reyes@demo.test` | Perfil y participación ficticios |
| Alumno | `emiliano.vazquez@demo.test` | Perfil y participación ficticios |
| Alumno | `ximena.flores@demo.test` | Perfil y participación ficticios |
| Alumno | `sebastian.cortes@demo.test` | Perfil y participación ficticios |
| Alumno | `renata.aguirre@demo.test` | Perfil y participación ficticios |
| Alumno | `mateo.juarez@demo.test` | Perfil incompleto, para mostrar el avance del perfil |
| Profesor | `alberto.cruz@demo.test` | Dirección aprobada en Café Altura y solicitud pendiente en Inventario |
| Profesor | `patricia.lara@demo.test` | Directora del sistema de pedidos en curso |
| Profesor | `fernando.rios@demo.test` | Participación concluida con constancia disponible |
| Profesor | `sofia.mendoza@demo.test` | Perfil docente ficticio y solicitud rechazada |

Las 19 cuentas figuran en la tabla. Todas las fechas de los trámites son las del momento de la carga; las fechas estimadas de los proyectos sí están repartidas en 2026 y 2027.

Para pruebas compartidas por internet, [la guía web](../web/README.md#compartir-pruebas-por-internet-pruebas-01) usa una base independiente, `banco_pruebas_publicas`. `py -3.12 database/preparar_demo_publica.py` la prepara con el mismo SQL versionado y la demostración; no carga los ejemplos anteriores de `seed.sql`, no modifica la base de trabajo y conserva lo probado al volver a ejecutarlo. Su configuración privada queda en `proyecto/.local/pruebas-publicas/`. No es una migración ni una sustitución del alojamiento institucional.

## Reproducir en otro equipo

1. Obtener PostgreSQL 18 para el equipo desde [la distribución oficial de Windows](https://www.postgresql.org/download/windows/). Se necesitan `postgres`, `initdb`, `pg_ctl`, `psql`, `pg_dump` y `pg_restore` de la misma rama.
2. Preparar una instancia local independiente, un usuario administrador de desarrollo y un archivo privado [pgpass](https://www.postgresql.org/docs/18/libpq-pgpass.html). Las migraciones iniciales requieren crear la base y los grupos `NOLOGIN`; no se usa una cuenta de producción.
3. Copiar [connection.example.json](connection.example.json) a `.local/connection.json` y completar las rutas absolutas, puerto y usuario. `database` debe ser `banco_proyectos`, nunca `postgres` ni una URI. El servidor debe estar en loopback. Para usar `start/stop`, el clúster propio debe estar en `.local/data`, con puerto y escucha configurados allí.
4. Con la instancia iniciada, ejecutar `migrate`, `seed` y `test`. La evidencia incluye la versión real utilizada. No copiar el clúster ni las credenciales de otra persona.

Para una instalación nueva de la aplicación, continuar con la [preparación web](../web/README.md#preparar-y-ejecutar): aprovisionar una conexión LOGIN propia miembro de `banco_web`, preparar el primer administrador una sola vez, instalar con `composer.lock`/`package-lock.json`, compilar y comprobar la conexión antes de abrir el servidor. Las semillas son ejemplos ficticios sin contraseñas válidas; no sustituyen el alta del primer administrador. La web no ejecuta migraciones Laravel.

## Recuperación local

`python database/manage.py backup` genera un dump custom sin propietario y sin sobrescribir un respaldo existente. Contiene esquema, datos, secuencias, permisos de objetos e historial técnico; debe guardarse de forma privada porque incluye cuentas y datos académicos. `python database/manage.py restore-check` crea una base temporal propia, restaura el respaldo y la compara con el origen antes de eliminar solo esa copia temporal. Esta comprobación verifica una copia de la instalación actual; no reemplaza la base de trabajo ni ofrece recuperación automática desde cualquier archivo antiguo.

Para recuperar un respaldo conservado:

1. Detener la aplicación y elegir una **base nueva y vacía**, distinta de `banco_proyectos`. Mantener intactos el origen y el dump. Usar PostgreSQL 18 y fuentes que correspondan a las migraciones registradas en ese respaldo.
2. Preparar el propietario técnico local indicado en la configuración privada y los grupos `NOLOGIN` `banco_lectura`, `banco_escritura` y `banco_web`, con los atributos mínimos de 002/019. Los roles y sus membresías son de la instancia y `pg_dump` no los recrea. En la misma instancia de desarrollo ya existen; en otra, revisarlos o crearlos antes de restaurar, sin modificar roles ajenos ni conceder al runtime la propiedad del esquema. Crear la base vacía con el propietario elegido, UTF8 y configuración compatible.
3. Ejecutar `pg_restore` como ese propietario técnico, con `--no-owner --exit-on-error`, conservando los permisos del dump. No usar `--clean`, no cargar sobre una base previamente migrada y no omitir las ACL con `--no-privileges`. Ejemplo desde una terminal con autenticación privada preparada; adaptar binario, puerto, propietario, destino y archivo:

   ```powershell
   & 'C:\ruta\postgresql18\bin\pg_restore.exe' --host 127.0.0.1 --port 55432 --username proweb_admin --no-password --dbname banco_proyectos_recuperacion --no-owner --exit-on-error 'C:\ruta\respaldo.dump'
   ```

4. Comparar esquema, datos, permisos, secuencias y `control.migracion` con la información conservada. Una configuración privada separada, basada en `connection.example.json` y apuntada expresamente a la copia, permite usar `python database/manage.py --config <archivo-privado> migrate`: con las mismas fuentes debe ser una segunda ejecución sin cambios. Revisar cualquier diferencia de checksum o migración pendiente antes de avanzar; no borrar el historial para eludirla. No ejecutar `seed` sobre los datos recuperados.
5. Preparar o verificar una credencial LOGIN de aplicación propia y su membresía `banco_web`; los secretos y las membresías LOGIN no vienen en el dump. Ajustar la configuración privada web al destino elegido y ejecutar `banco:comprobar-conexion`, inicio de sesión y consultas por rol según la [guía de recuperación web](../web/README.md#actualizar-y-recuperar-la-aplicación). No ejecutar `crear_admin_web.py` sobre cuentas restauradas ni usar al propietario para conectar Laravel.

Para una instancia nueva también puede prepararse primero una instalación SQL vacía separada con `manage.py migrate`, que crea los grupos; la restauración se realiza en **otra** base vacía y conserva sus datos/historial. El propietario efectivo de funciones `SECURITY DEFINER` debe ser el técnico confiable usado al restaurar, nunca `banco_web` o la cuenta LOGIN de Laravel. La comprobación de permisos web forma parte de la recuperación, además de la comparación SQL.

El respaldo de base no contiene `web/.env`, `APP_KEY`, credenciales PostgreSQL, sesiones/caché en archivos ni dependencias. Su recuperación se documenta en la guía web; no copiar secretos al repositorio ni asumir que restaurar SQL recupera sesiones. Una copia incompatible requiere diagnóstico y una corrección hacia delante, sin reemplazo destructivo automático. D-12 conserva por definir retención, tiempos y responsables institucionales; estos pasos cubren la operación local.

## Estado de los procesos

Las fuentes incluyen treinta y una migraciones y 166 funciones en `banco`, y conservan las 21 tablas de negocio, 164 columnas de tablas y cinco de vista. 001–030 permanecen inmutables. 014–018 completan cierre, cancelación docente previa, evaluación/autorización, cuentas/perfiles y avisos internos; 019 prepara la conexión y 020 integra acceso/cuentas. [021](migrations/021_publicacion_web.sql) añade nueve gateways de empresa/publicación y siete auxiliares privados, sin columnas nuevas ni cambios de contenido histórico. [022](migrations/022_perfiles_catalogo_web.sql) añade seis gateways de perfiles propios/catálogo y cinco auxiliares privados. [023](migrations/023_participacion_web.sql) añade ocho gateways de participación/ciclo y ocho auxiliares privados. [024](migrations/024_avisos_reportes_web.sql) añade cuatro gateways de avisos/reportes y tres auxiliares privados sobre el mismo esquema, sin tablas nuevas. [025](migrations/025_coincidencia_habilidades_web.sql) añade un gateway de solo lectura con la coincidencia entre las habilidades propias del alumno y las de proyectos publicados (UX-02), sin tablas ni datos nuevos. [026](migrations/026_documentos_pdf_web.sql) añade el esquema `adjunto` con la tabla de metadatos de PDF del perfil (D-11) y cuatro gateways; queda fuera de las 21 entidades de `banco`. `snapshot` y `restore-check` no comparan `adjunto`, y los archivos de `web/storage/app/private/documentos` se respaldan aparte. [027](migrations/027_recomendaciones_web.sql) añade un gateway de solo lectura con los proyectos recomendados para el alumno según sus habilidades (UX-06), sin tablas ni datos nuevos. [028](migrations/028_constancia_participacion_web.sql) añade un gateway de solo lectura con los datos de la constancia de participación (UX-07). [029](migrations/029_imagenes_web.sql) añade `adjunto.imagen` para la foto de perfil y el logo de empresa (UX-08) con cuatro gateways; las imágenes viven en `web/storage/app/private/imagenes` y, como los PDF, se respaldan aparte. [030](migrations/030_panorama_reportes_web.sql) añade un gateway de solo lectura con los conteos del panorama gráfico de Reportes (UX-09). [031](migrations/031_catalogo_habilidades_web.sql) añade el mantenimiento del catálogo de habilidades por la administración (UX-10). El [seguimiento](../docs/06-seguimiento.md) y los recibos distinguen las fuentes preparadas de la instalación verificada. El [diccionario físico](../docs/09-base-de-datos.md) explica sus referencias y restricciones.

| Operación interna | Resultado |
| --- | --- |
| `crear_cuenta(admin,nombre,correo,hash,rol)` | Cuenta académica o administrativa; el perfil puede completarse después |
| `crear_empresa_con_representante(admin,nombre,correo,hash,razon_social)` | Empresa, cuenta y representante inicial en una transacción |
| `enviar_proyecto(proyecto,autor)` | Revisión de los seis campos RF-08 y cupo positivo |
| `resolver_publicacion(revision,admin,resultado,motivo)` | Aprobación, corrección o rechazo de la versión exacta |
| `presentar_candidatura(proyecto,alumno)` | Envío con máximo tres activas y sin duplicado activo |
| `cancelar_candidatura(candidatura,alumno)` | Cancelación propia anterior a asignarse, con historial |
| `solicitar_direccion(proyecto,profesor,experiencia,justificacion)` | Solicitud pendiente sin reservar carga |
| `cancelar_solicitud_direccion(solicitud,profesor)` | Cancelación propia pendiente; después solo retiro administrativo |
| `evaluar_candidatura(candidatura,representante,puntuaciones,comentarios,recomendacion)` | Evaluación completa inmutable; una reevaluación invalida la preselección anterior |
| `preseleccionar_candidatura(candidatura,representante)` | Selección expresa con su última evaluación favorable |
| `resolver_candidatura(candidatura,admin,resultado,motivo)` | Aprobación posterior a preselección y asignación exacta atómica; rechazo desde una fuente activa |
| `resolver_direccion(solicitud,admin,resultado,motivo)` | Resolución administrativa y asignación conjunta al aprobar |
| `iniciar_proyecto(proyecto,admin)` | Publicación y cupo válidos, mínimo un alumno y un director autorizados; sin llenar plazas |
| `retirar_alumno(asignacion,admin,motivo)` / `retirar_director(asignacion,admin,motivo)` | Retiro y cierre de acompañamientos afectados; pausa si pierde el mínimo |
| `reanudar_proyecto(proyecto,admin)` | Confirma expresamente los mínimos recuperados y conserva primer inicio |
| `finalizar_proyecto(proyecto,admin,motivo)` / `cancelar_proyecto(proyecto,admin,motivo)` | Cierre coordinado de asignaciones, acompañamientos y pendientes; libera reservas e incluye aviso raíz |
| `cambiar_estado_cuenta(admin,usuario,estado,motivo)` | Activa/desactiva sin borrar ni liberar participaciones |
| `relevar_representante(admin,empresa,nombre,correo,hash,motivo)` | Nuevo representante; anterior inactivo y vínculo histórico conservado |
| `consultar_perfil(actor,titular)` | Perfil por relación y lista expresa de campos; sin hash |
| `consultar_notificaciones(usuario,limite,antes_id)` | Bandeja propia, hasta 100 avisos por página |
| `marcar_notificacion_leida(notificacion,usuario)` | Primera lectura propia, idempotente y sin borrar historial |

Todas las funciones pertenecen al esquema `banco`. Las operaciones originales son internas `SECURITY INVOKER`; once entradas de 020, nueve de 021, seis de 022, ocho de 023 y cuatro de 024 son `SECURITY DEFINER` con búsqueda fija `pg_catalog,banco,pg_temp`. Se concede a `banco_web` únicamente esas treinta y ocho entradas, además del directorio de 019; los auxiliares de 021 a 024 quedan privados. Se conservan denegados DML, lectura general de tablas y ejecución general de funciones. `banco_lectura` y `banco_escritura` son NOLOGIN y conservan únicamente el directorio mínimo. Los identificadores recibidos no autentican a una persona: Laravel los obtiene de la sesión y usa su credencial específica; no utiliza al propietario local.

### Gateways de publicación de WEB-04

| Entrada concedida a la conexión web | Operación |
| --- | --- |
| `web_obtener_empresa(actor)` / `web_editar_empresa(actor,datos,version)` | Datos de la empresa del representante vigente; edición con comparación de versión y auditoría |
| `web_listar_proyectos(actor,buscar,estado,limite,desplazamiento)` / `web_obtener_proyecto(actor,proyecto)` | Empresa propia o consulta administrativa, con revisiones/decisiones y contenido autorizado |
| `web_catalogo_habilidades(actor)` | Habilidades existentes para los formularios del módulo, sin crear ni editar catálogo |
| `web_crear_proyecto(actor,datos)` / `web_editar_proyecto(actor,proyecto,datos,version)` | Borrador o corrección, contenido y habilidades validados; empresa y autoría derivadas del actor |
| `web_enviar_proyecto(actor,proyecto,version)` | Validación de seis campos y cupo; llama al envío interno y conserva instantánea/auditoría/avisos |
| `web_resolver_publicacion(actor,proyecto,revision,resultado,motivo,cupo_validado,version)` | Resolución administrativa exacta; al aprobar confirma el cupo propuesto sin modificarlo |

Los tokens son SHA-256 opacos de 64 caracteres, sin columna nueva y sin valor de autenticación. Los gateways toman los bloqueos del proyecto o empresa antes de comparar y escribir; rechazan una versión antigua con `40001`. El formulario debe recargar los datos para una nueva decisión, sin reintentar automáticamente aquella operación. Los campos JSON permitidos son expresos; la conexión no puede cambiar empresa, autor, estado o revisión publicada mediante un campo adicional.

El envío y resolución reutilizan las funciones y el trigger de avisos de 018; no duplican las notificaciones desde Laravel. Publicar exige la instantánea vigente, cupo positivo de esa misma versión y motivo. Las revisiones históricas sin cupo no se convierten silenciosamente: se conservan y requieren devolución/corrección/nuevo envío para una propuesta válida. No se habilita edición de contenido o cupo publicados.

`python web/tests/publicacion.py` desde `proyecto/` prueba el recorrido HTTP contra una base temporal propia y cuenta web; la suite SQL comprueba contratos, permisos, integridad y concurrencia del motor. La instalación y los resultados se consultan en [el seguimiento](../docs/06-seguimiento.md); preparar estas fuentes no sustituye su aplicación verificada. La evolución es hacia delante: conservar respaldo y 001–020, y usar otra migración para corregir o retirar capacidades después de aplicar 021.

### Gateways de perfiles y catálogo de WEB-05

| Entrada concedida a la conexión web | Operación |
| --- | --- |
| `web_obtener_perfil_propio(actor)` | Perfil propio y token opaco, incluso si la cuenta aún no tiene fila académica |
| `web_guardar_perfil_propio(actor,datos,version)` | Alta/edición del perfil y habilidades del alumno, con CAS y auditoría atómica |
| `web_listar_habilidades_perfil(actor)` | Catálogo existente para elegir habilidades; no crea ni modifica ese catálogo |
| `web_catalogo_proyectos(actor,buscar,empresa,modalidad,habilidad,tipo_habilidad,limite,desplazamiento)` | Publicaciones válidas filtradas, total y página; Laravel usa 20 por página |
| `web_obtener_proyecto_catalogo(actor,proyecto)` | Contenido aprobado, habilidades de instantánea, contacto empresarial y disponibilidad indicativa |
| `web_filtros_catalogo(actor)` | Empresas, modalidades y habilidades derivadas solo de publicaciones visibles |

Los seis exigen alumno/profesor activos y no requieren un perfil previo para consultar el catálogo. El perfil se limita al actor: alumno con datos académicos y habilidades duras/blandas, profesor con especialidad/experiencia/contacto, sin otra tabla de habilidades docentes. El JSON no puede modificar identidad, rol, cuenta o titular. El guardado reemplaza las asociaciones elegidas y confirma perfil, habilidades y evento de auditoría juntos; cualquier fallo revierte el conjunto. La evidencia permanece como texto, sin archivos o descarga automática.

El token incorpora perfil, habilidades y último evento para detectar también cambios que regresen al mismo valor. Un bloqueo asesor compartido protege la lectura datos/versión; el exclusivo serializa guardados del titular, incluso si aún no existe fila. En perfiles existentes se respeta participante → Usuario. La comparación se hace después del bloqueo: `40001` obliga a recargar y revisar. El servicio solo reintenta `40P01` de forma acotada cuando controla la transacción completa.

El catálogo exige Publicado, revisión aprobada de formato 2, decisión exacta, campos completos, cupo positivo y contenido/requisitos coincidentes. Los filtros de habilidad/tipo y los nombres de habilidades usan las instantáneas aprobadas; no divulgan datos de borradores ni motivos privados. Los filtros habilidad/tipo se aplican sobre la misma habilidad. El detalle bloquea Proyecto en modo compartido y revalida después de una operación concurrente. Las asignaciones vigentes determinan plazas libres y dirección ocupada; un proyecto lleno conserva visibilidad con cero plazas. Son datos informativos, sin reserva ni autorización de participación.

`python web/tests/perfiles.py`, desde `proyecto/`, prepara una base temporal propia para comprobar el recorrido HTTP. La suite SQL contempla permisos, alta sin perfil, versiones, atomicidad y concurrencia. La ejecución e instalación se acreditan por separado en [el seguimiento](../docs/06-seguimiento.md). Para evolucionar después de aplicar 022 se crea otra migración; 001–021 se conservan.

### Gateways de participación y ciclo de WEB-06

[023](migrations/023_participacion_web.sql) añade las entradas concretas siguientes. Todos los actores proceden de la sesión web y se revalidan en SQL; las funciones internas de negocio no se conceden directamente al runtime.

| Gateway | Responsabilidad |
| --- | --- |
| `web_bandeja_participacion` | Solicitudes del ámbito autorizado, tipo, búsqueda/estado y paginación |
| `web_detalle_participacion` | Solicitud, perfil permitido, evaluaciones/decisiones/historial y acciones/versiones |
| `web_contexto_postulacion` | Perfil, actividad, publicación y disponibilidad para revisar el envío propio |
| `web_enviar_participacion` | Candidatura o dirección con contexto vigente, sin reservar carga |
| `web_operar_participacion` | Cancelar, evaluar, preseleccionar o resolver según rol, estado y versión |
| `web_proyectos_participacion` | Seguimiento propio o de gestión y vacantes permitidas de Pausado |
| `web_detalle_proyecto_participacion` | Contenido, participantes/perfiles e historial autorizados del proyecto |
| `web_operar_proyecto_participacion` | Inicio, reanudación, retiro y cierre administrativos con versión exacta |

Los listados combinan búsqueda y estado; la aplicación pagina de veinte en veinte. Las lecturas filtran datos y acciones por relación, manteniendo evaluaciones empresariales fuera de la consulta del profesor y los identificadores académicos reservados fuera de perfiles compartidos. El envío, la solicitud y el ciclo usan versiones opacas para rechazar formularios obsoletos. Las operaciones reutilizan integridad, auditoría y avisos transaccionales; el cierre conserva fuentes aprobadas y libera reservas coordinadamente. No se incorporan adjuntos, reapertura o incorporaciones generales En curso.

`python web/tests/participacion.py`, desde `proyecto/`, prepara una base temporal propia para los recorridos HTTP. La suite SQL contempla permisos, límites, rollback y carreras de estas operaciones; ejecución e instalación se acreditan en [el seguimiento](../docs/06-seguimiento.md). Cualquier evolución posterior conserva 001–023 y añade una migración nueva.

### Gateways de avisos y reportes de WEB-07

| Entrada concedida a la conexión web | Responsabilidad |
| --- | --- |
| `web_bandeja_avisos(actor,estado,buscar,limite,desplazamiento)` | Avisos del destinatario, búsqueda/lectura, total filtrado y contador propio de no leídos |
| `web_detalle_aviso(actor,aviso)` | Mensaje y fechas propios, con recurso interno solo cuando conserve ámbito autorizado |
| `web_leer_aviso(actor,aviso)` | Reutiliza 018 para registrar la primera fecha de lectura de forma idempotente |
| `web_reporte(actor,tipo,filtros,limite,desplazamiento)` | Cinco consultas exclusivas de administrador activo, opciones de filtro, filas y totales del mismo conjunto filtrado |

Los tres auxiliares `web_exigir_avisos`, `web_recurso_aviso` y `web_opciones_reporte` permanecen privados. Los cuatro roles activos consultan solo sus avisos; detalle y lectura verifican destinatario. No se devuelve el evento crudo ni motivos privados; el aviso persiste aunque no tenga recurso navegable. Laravel marca con POST y CSRF, nunca al abrir el detalle por GET.

Los reportes admiten `buscar` (máximo 150 caracteres), estados del dominio correspondiente e identificadores aplicables: empresa para proyectos; empresa/proyecto para candidaturas y asignaciones; empresa/proyecto/profesor para direcciones; profesor para carga. Carga no admite estado. Se rechazan tipos, claves o referencias numéricas fuera de bigint; las consultas son parametrizadas, con límite/desplazamiento comprobados y sin SQL dinámico. Laravel usa páginas de 20. Los totales derivan de la misma selección antes de paginar; la carga incluye cero asignaciones y cuentas inactivas que mantengan reservas. No se incluyen credenciales, identificadores académicos reservados, rúbricas o evidencias.

`python web/tests/comunicacion.py`, desde `proyecto/`, prepara una base temporal propia para las comprobaciones HTTP. La suite SQL contempla privacidad, filtros, totales y concurrencia de lectura; el [seguimiento](../docs/06-seguimiento.md) conserva los resultados ejecutados e instalación, separados de esta descripción. No se añaden exportaciones, correo, API o tablas. Una evolución posterior a aplicar 024 requiere una nueva migración y conserva 001–024.

### Reservas y continuidad

D-06 cuenta candidaturas pendientes, evaluadas y preseleccionadas; una aprobada libera su espacio solo junto con la asignación exacta. Las asignaciones vigentes reservan desde la autorización: cupo validado del proyecto, un proyecto global por alumno, tres proyectos por profesor y un director por proyecto. Las finalizadas/revocadas liberan sus reservas. Fechas estimadas o cuentas inactivas no liberan por sí solas. Origen, decisión y asignación deben quedar coherentes al confirmar; un fallo revierte el conjunto.

Las escrituras cruzadas requieren READ COMMITTED (`25001` en otro aislamiento). Las fuentes existentes se bloquean antes del participante y proyecto. El cierre lee el alcance, bloquea fuentes y perfiles en orden, toma Proyecto y revalida; si aparece una fuente o participante nuevo devuelve `40001`. El llamador debe reintentar **toda la transacción**, con sus lecturas nuevas. No se reintenta solo la última sentencia ni se ignora el error.

En Pausado se repone solo el tipo faltante, usando pendientes o solicitudes nuevas, con las etapas de D-08. Recuperar mínimos no reanuda automáticamente. No hay incorporaciones generales En curso, reapertura ni modificación del contenido/cupo publicado. Un cambio sustantivo requiere un proyecto nuevo. Finalizar solo admite En curso; cancelar admite cualquier estado abierto. Los cierres conservan fuentes aprobadas, decisiones, publicación, inicio y pausas; una revisión pendiente se cancela sin fabricar un rechazo administrativo.

`evento_retiro_id` y `evento_cierre_id` conservan la operación exacta. Si un período no había comenzado, el cierre mantiene `fin` NULL y estado terminal con su evento; no inventa un fin futuro. El estado, no ese NULL, determina la carga. La finalización del proyecto no añade calificaciones o entregables académicos.

La rúbrica D-08 usa las claves `tecnico`, `blando` y `academico`. Cada valor contiene `puntuacion` (0, 1 o 2) y `comentario` no blanco. Los tres pesan igual y no hay umbral automático. Ejemplo del argumento JSON:

```json
{
  "tecnico": {"puntuacion": 2, "comentario": "Conocimientos acordes al proyecto"},
  "blando": {"puntuacion": 1, "comentario": "Debe reforzar la comunicación"},
  "academico": {"puntuacion": 2, "comentario": "Cumple los requisitos indicados"}
}
```

Los avisos internos se generan con el evento de negocio y la misma transacción, sin correo ni servicios externos. No copian motivos privados, puntuaciones o evidencias. La evidencia de habilidad es texto o enlace escrito, sin adjuntos ni descarga automática. No se ejecuta purga automática; D-10 conserva el límite de retención institucional por concretar para producción.

Las publicaciones históricas de formato 1 se conservan sin cupo inventado. Una publicación sin capacidad validada no habilita nuevas participaciones ni inicio. Una instalación incompatible rechaza la migración con rollback y necesita conciliación explícita; no se cierran registros para forzarla. Las migraciones son hacia delante: ante una incidencia, conservar respaldo y corregir mediante una migración nueva. No eliminar referencias de auditoría para simular un rollback de negocio.

`test` comprueba instalación desde cero, actualización con historial, rechazos de datos incompatibles, rollback, idempotencia, roles, privacidad, operaciones coordinadas, carreras reales y recuperación. La restauración compara datos, catálogo, permisos de esquemas/objetos, las quince secuencias y su estado, y el historial técnico exacto. Los datos ficticios de trabajo no incluyen credenciales válidas ni procesos autorizados; los casos de negocio se verifican en bases temporales propias. Las [pruebas](evidencia/verificacion.json) y la [instalación](evidencia/instalacion.json) son recibos diferentes.

La [aplicación web](../web/README.md) incorpora portada, sesión, cuentas por rol y los recorridos de empresa/publicación de WEB-04 y perfiles propios/catálogo de WEB-05, además de participación y ciclo de WEB-06; el seguimiento acredita su estado de verificación. Ejecutar `python database/provision_web.py` desde `proyecto/` después de migrar prepara la cuenta LOGIN local propia y `web/.env` con clave aleatoria, sin imprimir secretos; una ejecución posterior conserva las credenciales existentes. El SQL versionado define permisos; el aprovisionamiento local guarda el secreto fuera de las fuentes.

Después de aplicar 020, `python database/crear_admin_web.py` prepara una sola vez el primer administrador local y guarda su acceso temporal en `.local/primer-acceso-web.txt`, fuera de Git. Audita como operación de sistema y desactiva únicamente el administrador ficticio exacto, para conservar un administrador real activo; no borra cuentas ni convierte las semillas en contraseñas conocidas. El titular debe cambiar la contraseña al entrar.

La participación y el ciclo de WEB-06 reutilizan estas operaciones desde la aplicación. WEB-07 incorpora la bandeja propia de avisos, los cinco reportes administrativos y las instrucciones de entrega local. Las APIs y el despliegue institucional mantienen sus etapas posteriores. El [seguimiento](../docs/06-seguimiento.md) acredita los recorridos y comprobaciones ejecutados; los resultados locales no acreditan una carga institucional de producción.

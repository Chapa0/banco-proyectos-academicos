# Elección de PostgreSQL para el banco de proyectos académicos

La decisión del motor se conserva en [D-13](07-registro-de-decisiones.md#d-13). Esta comparación fundamenta la elección de PostgreSQL: permite expresar directamente la unicidad de candidaturas y asignaciones activas mientras conserva el historial. El motivo principal es la claridad de las restricciones del dominio; el rendimiento deberá medirse con las consultas y la carga reales.

El alcance comprende modelo físico, migraciones, scripts SQL, pruebas y operación sobre PostgreSQL. La concreción local de PostgreSQL 18.6 se registra en [D-14](07-registro-de-decisiones.md#d-14); la política oficial mantiene esa rama soportada hasta noviembre de 2030. Fuente: [versiones de PostgreSQL](https://www.postgresql.org/support/versioning/).

## Comparación aplicada al proyecto

| Necesidad | PostgreSQL | MySQL 8.4 | Evaluación para el proyecto |
| --- | --- | --- | --- |
| Candidatura única mientras siga activa | Índice único parcial con condición por estado | Puede representarse con columna generada e índice único | PostgreSQL expresa directamente la regla |
| Conservar solicitudes anteriores | Filas históricas excluidas del índice parcial | Posible con el diseño de unicidad adecuado | Ambos satisfacen el requisito |
| Máximo de tres candidaturas o direcciones | Requiere validar conteo y concurrencia | También requiere validar conteo y concurrencia | Depende del protocolo transaccional |
| Decisión, asignación y avisos atómicos | Transacciones | Transacciones InnoDB | Ambos permiten la operación completa |
| Claves y validaciones de una fila | Claves foráneas, unicidad y CHECK | También dispone de esas restricciones | La consistencia exige diseñarlas en ambos |
| Instantáneas estructuradas de revisiones | JSONB | JSON | Ambos ofrecen datos JSON; mantener relaciones explícitas |
| Integración con Laravel | Soporte directo | Soporte directo | Se conservan arquitectura y módulos |
| Rendimiento | Medir consultas, índices y carga | Medir con el mismo escenario | Sin una prueba comparable no hay un ganador demostrado |
| Instalación y alojamiento | Requiere PostgreSQL y el driver PHP correspondiente | Requiere MySQL y su driver | Verificar el entorno institucional elegido |

El diseño equivalente en MySQL para unicidad activa puede usar un marcador generado que sea 1 en filas activas y NULL en históricas, junto con un índice único compuesto. Es una alternativa válida; PostgreSQL reduce esa adaptación. Fuentes: [columnas generadas de MySQL](https://dev.mysql.com/doc/refman/8.4/en/create-table-secondary-indexes.html) e [índices únicos de MySQL](https://dev.mysql.com/doc/refman/8.4/en/create-index.html).

Para las capacidades compartidas, consultar [transacciones InnoDB](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking-transaction-model.html), [CHECK de MySQL](https://dev.mysql.com/doc/refman/8.4/en/create-table-check-constraints.html), [JSON de MySQL](https://dev.mysql.com/doc/refman/8.4/en/json.html) y [motores admitidos por Laravel](https://laravel.com/framework/docs/13.x/database).

## Unicidad activa e historial

Ejemplo ilustrativo con los estados confirmados en D-06. Las migraciones SQL son la fuente de los nombres y restricciones instalados:

```sql
CREATE UNIQUE INDEX candidaturas_activas_unicas
ON banco.candidatura (alumno_id, proyecto_id)
WHERE estado IN (
    'pendiente_evaluacion',
    'evaluada',
    'preseleccionada'
);
```

Impedirá repetir la pareja alumno y proyecto dentro de esos estados y permitirá conservar intentos rechazados o cancelados. `alumno_id`, `proyecto_id` y `estado` serán obligatorios. La misma técnica se aplicará a parejas de proyecto y participante con asignación vigente. Fuente: [índices únicos parciales](https://www.postgresql.org/docs/18/indexes-partial.html).

El predicado dependerá de columnas de su propia tabla. La protección de unicidad funciona aunque una consulta no utilice el índice para leer. Los planes de consulta se comprobarán por separado, manteniendo parámetros para los datos del usuario.

## Límites de tres y operaciones simultáneas

El índice anterior evita duplicados, pero no cuenta el total de proyectos distintos de un participante. Si dos peticiones leen dos candidaturas y después insertan sin protección, pueden terminar con cuatro.

La implementación serializa las reservas por participante:

1. Abrir una transacción con READ COMMITTED.
2. Bloquear primero el participante y después el proyecto, conforme al orden de los controles de reserva SQL.
3. Con los bloqueos adquiridos, ejecutar una sentencia nueva para consultar el conteo y comprobar disponibilidad.
4. Registrar únicamente la operación válida con sus registros y auditoría aplicables; los avisos se añadirán cuando se concreten D-10/D-11.
5. Confirmar todos los cambios o revertirlos juntos.

READ COMMITTED toma una instantánea por sentencia. Por esa semántica, combinar la espera del bloqueo y el conteo en una sola sentencia podría consultar datos anteriores a la espera; se mantendrán separados. Todos los caminos que modifiquen cupos deberán aplicar el protocolo, incluidos cierres, cancelaciones e importaciones futuras. Fuentes: [aislamiento](https://www.postgresql.org/docs/18/transaction-iso.html) y [bloqueos](https://www.postgresql.org/docs/18/explicit-locking.html).

## Restricciones y tipos de datos

| Elemento | Decisión de diseño propuesta |
| --- | --- |
| Identidad de registros | Claves primarias y foráneas; participantes, proyectos y decisiones en tablas relacionadas |
| Datos obligatorios | NOT NULL además de validaciones del formulario |
| Fechas y valores de una fila | CHECK para coherencia de fechas y valores permitidos |
| Máximo de tres | Bloqueos y validación de conteos en SQL; un CHECK no puede garantizar conteos de otras filas |
| Correo de acceso | Política explícita de normalización y unicidad, sin diferencias de mayúsculas |
| Instantes de eventos | timestamptz, UTC en conexiones y conversión al presentar |
| Fechas académicas sin hora | date |
| Contenido de una revisión | JSONB con versión de formato y controles de inmutabilidad |

PostgreSQL limita CHECK a condiciones de la fila verificada; las reglas agregadas requieren otro mecanismo. Las relaciones compuestas que comprueben participante y proyecto deberán apuntar a una clave única adecuada, no al índice parcial. Fuente: [restricciones de PostgreSQL](https://www.postgresql.org/docs/18/ddl-constraints.html).

Para acceso se propone recortar espacios externos y normalizar el correo al guardar y autenticar, con unicidad de su forma normalizada en la base. Tratar todo el correo sin diferencias de mayúsculas es una política de esta aplicación. Fuente técnica: [índices sobre expresiones](https://www.postgresql.org/docs/18/indexes-expressional.html).

`timestamptz` conserva el instante, no la zona original. JSONB conserva contenido estructurado y admite consultas; su tipo no impide modificaciones. Las claves de participantes y decisiones seguirán siendo relacionales. Fuentes: [fechas](https://www.postgresql.org/docs/18/datatype-datetime.html) y [JSONB](https://www.postgresql.org/docs/18/datatype-json.html).

## Efectos sobre Laravel y el entorno

Se mantienen el monolito modular, las vistas Blade y los servicios del negocio. La configuración usará `DB_CONNECTION=pgsql`; se verificará `pdo_pgsql` en el PHP de consola y el del servidor. El instalador de PostgreSQL o una herramienta gráfica no sustituyen ese controlador. Fuentes: [conexiones de Laravel](https://laravel.com/framework/docs/13.x/database) y [PDO PostgreSQL](https://www.php.net/manual/en/ref.pdo-pgsql.php).

Las migraciones SQL existentes en `database/migrations/` serán la única fuente de evolución del esquema al integrar Laravel; se conservarán su historial y sus comprobaciones. Los cambios de la web se incorporarán como nuevas migraciones, sin recrear tablas mediante las migraciones predeterminadas del framework. El script académico se exportará desde el esquema comprobado. Los nombres siguen minúsculas y snake_case; la base usa UTF8. La integración y sus límites se desarrollan en [arquitectura](02-arquitectura-y-datos.md#integración-con-postgresql-existente).

Antes de poner en servicio se verificará que el alojamiento permita conexión, migraciones, índices y recuperación. La entrega local ya incluye respaldo custom con `pg_dump` y restauración comprobada con `pg_restore`; el procedimiento se conserva en [database](../database/README.md). La reproducción contempla roles y permisos; un dump de una base no incluye los objetos globales del servidor. La operación institucional sigue pendiente de D-12. Fuente: [pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html).

## Costo del cambio y validación

Al elegir PostgreSQL el 21 de octubre de 2026, el proyecto contenía PDF y documentación, sin aplicación ni datos que migrar. Ese fue el contexto de la comparación inicial. Desde el 28 de octubre existen esquema, datos ficticios y conexión SQL verificados sobre PostgreSQL 18.6. La integración desde Laravel todavía está pendiente y se preparará en WEB-01, conservando esa base y su historial.

Las pruebas locales acreditan integridad estructural, representación, publicación inicial con cupo, máximos de candidaturas y asignaciones, última plaza, envío de participaciones e inicio protegido. Se verifican concurrencia y reproducción mediante migraciones, exportación SQL y restauración dentro del alcance documentado. El servicio de autorización de participantes y los cierres mantienen sus dependencias de D-08/D-07. La integración web añadirá pruebas HTTP y conservará PostgreSQL real para acreditar restricciones y concurrencia. Los resultados ejecutados se consultan en el seguimiento.

El motor elegido no resuelve por sí mismo las decisiones institucionales D-01 a D-12. D-01 confirma tres candidaturas activas simultáneas por alumno; D-02, cupo por proyecto validado antes de publicar; D-03, un director vigente sin equipos ni codirección; D-04, un proyecto asignado simultáneamente por alumno; D-05, inicio administrativo con publicación, cupo validado, al menos un alumno y el director autorizados, sin llenar el cupo; D-06, estados activos y reserva desde la autorización; y D-09, cuentas y representación. SQL ya implementa sus controles, envíos internos e inicio protegido. D-07, D-08 y D-10 a D-12 conservan sus preguntas en el [registro de decisiones](07-registro-de-decisiones.md). Los nuevos acuerdos evolucionarán mediante otras migraciones, sin alterar las ya aplicadas. El avance y las pruebas ejecutadas se consultan en [el seguimiento](06-seguimiento.md).

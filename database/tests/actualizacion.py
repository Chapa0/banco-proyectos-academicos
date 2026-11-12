"""Actualizar una instalación real 001–003 sin reescribir historial ni inventar políticas."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile


def _rows(db, database):
    """Contenido previo, excluyendo únicamente atributos añadidos por la evolución."""
    tables = db.sql(database, """SELECT tablename FROM pg_tables
      WHERE schemaname='banco' ORDER BY tablename;""").splitlines()
    result = {}
    for name in tables:
        # Nombres devueltos por el catálogo, citados como identificadores SQL.
        quoted = '"' + name.replace('"', '""') + '"'
        new_columns = {
            'usuario': ('version_acceso', 'requiere_cambio_clave'),
            'proyecto': ('cupo_maximo_alumnos', 'evento_inicio_id', 'evento_estado_id', 'evento_cierre_id'),
            'asignacion_alumno': ('evento_retiro_id', 'evento_cierre_id'),
            'asignacion_direccion': ('evento_retiro_id', 'evento_cierre_id'),
            'acompanamiento': ('evento_retiro_id', 'evento_cierre_id'),
            'candidatura': ('evento_cierre_id', 'evaluacion_vigente_id', 'evento_preseleccion_id'),
            'solicitud_direccion': ('evento_cierre_id',),
            'revision_proyecto': ('evento_cierre_id',),
            'evaluacion_candidato': ('version_rubrica',),
            'criterio_evaluacion': ('codigo',),
        }
        expression = 'to_jsonb(t)' + ''.join("-'" + column + "'" for column in new_columns.get(name, ()))
        result[name] = json.loads(db.sql(database, f"""SELECT COALESCE(jsonb_agg(fila ORDER BY fila::text),'[]'::jsonb)
          FROM (SELECT {expression} AS fila FROM banco.{quoted} t) datos;"""))
    return result


def _fixture(db, database, *, assigned=False):
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-8501,'Admin actualización','actualizacion-admin@example.invalid','!prueba','administrador'),
        (-8502,'Empresa actualización','actualizacion-rep@example.invalid','!prueba','empresa'),
        (-8503,'Alumno actualización','actualizacion-alumno@example.invalid','!prueba','alumno'),
        (-8504,'Profesor actualización','actualizacion-profesor@example.invalid','!prueba','profesor');
      INSERT INTO banco.alumno(usuario_id,matricula) VALUES(-8503,'ACT-A-01');
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES(-8504,'ACT-P-01');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-8511,'Empresa ficticia actualización');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-8502,-8511);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance)
        VALUES(-8521,-8511,-8502,'Publicación anterior','Descripción','Problemática','Objetivos','Justificación','Alcance');
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-8521,-8502),-8501,'aprobada','Aprobación anterior a D-02');
      INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES(-8531,-8503,-8521);
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES(-8532,-8504,-8521);
      COMMIT;""")
    if assigned:
        db.sql(database, """BEGIN;
          UPDATE banco.candidatura SET estado='aprobada' WHERE id=-8531;
          INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
            VALUES(-8541,-8501,-8531,'aprobada','Asignación anterior al atributo de cupo');
          INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
            VALUES(-8551,-8531,-8541,-8503,-8521,'2026-01-01 00:00:00+00');
          COMMIT;""")


def _rejected(db, database, text):
    try:
        db.migrate(database)
    except RuntimeError as error:
        if text not in str(error):
            raise AssertionError(f'La actualización falló por un motivo inesperado: {error}') from error
    else:
        raise AssertionError('Se aceptó una actualización incompatible: ' + text)
    if db.sql(database, "SELECT count(*) FROM control.migracion WHERE version LIKE '006_%';") != '0':
        raise AssertionError('La migración 006 fallida quedó registrada como aplicada.')
    if db.sql(database, "SELECT to_regclass('banco.uq_asignacion_alumno_carga_vigente') IS NULL;") != 't':
        raise AssertionError('La migración 006 fallida dejó DDL parcialmente aplicado.')


def run(db):
    """Crear/eliminar bases propias; nunca actualizar ni vaciar la base de trabajo."""
    original = db.migrations_path
    local = (Path(__file__).resolve().parents[1] / '.local').resolve()
    local.mkdir(exist_ok=True)
    expected = sorted(path.name for path in original.glob('[0-9][0-9][0-9]_*.sql'))
    # El auxiliar solo contiene copias de migraciones antiguas, dentro de .local.
    # Resolver y comprobar el destino antes de permitir su limpieza recursiva.
    with tempfile.TemporaryDirectory(prefix='actualizacion_', dir=local) as folder:
        temporary = Path(folder).resolve()
        if temporary.parent != local or not temporary.name.startswith('actualizacion_'):
            raise AssertionError('El directorio auxiliar no está dentro del destino esperado.')
        for path in original.glob('00[1-3]_*.sql'):
            (temporary / path.name).write_bytes(path.read_bytes())
        database = None
        try:
            database = db.create_temporary()
            db.migrations_path = temporary
            db.migrate(database)
            _fixture(db, database)
            before = _rows(db, database)
            if db.sql(database, "SELECT instantanea_contenido->>'version_formato' FROM banco.revision_proyecto WHERE proyecto_id=-8521;") != '1':
                raise AssertionError('La base anterior no generó una publicación real v1.')
            db.migrations_path = original
            # La verificación con fixtures actuales requiere primero actualizar.
            # Rechazarlo antes del respaldo evita confundir una copia válida de
            # la versión anterior con una restauración corrupta o migrarla sola.
            created_before = set(db.created)
            backups_before = set((local / 'backups').glob('*.dump'))
            try:
                db.restore_check(database)
            except RuntimeError as error:
                if 'ejecute migrate antes' not in str(error):
                    raise
            else:
                raise AssertionError('Se verificó una versión anterior usando fuentes y fixtures posteriores.')
            if db.created != created_before or set((local / 'backups').glob('*.dump')) != backups_before:
                raise AssertionError('La precondición fallida creó un respaldo o una base temporal.')
            if _rows(db, database) != before:
                raise AssertionError('La comprobación previa alteró una base pendiente de actualización.')
            db.migrate(database)
            if _rows(db, database) != before:
                raise AssertionError('Actualizar reescribió usuarios, publicación, revisión, decisión o auditoría anteriores.')
            applied = db.sql(database, 'SELECT version FROM control.migracion ORDER BY version;').splitlines()
            if applied != expected:
                raise AssertionError('No se aplicaron todas las migraciones nuevas de la fuente vigente.')
            if db.sql(database, 'SELECT cupo_maximo_alumnos IS NULL AND evento_inicio_id IS NULL AND evento_estado_id IS NULL AND evento_cierre_id IS NULL FROM banco.proyecto WHERE id=-8521;') != 't':
                raise AssertionError('La actualización inventó cupo, inicio o continuidad para una publicación histórica.')
            for statement in ('SELECT banco.iniciar_proyecto(-8521,-8501);',
                              'SELECT banco.presentar_candidatura(-8521,-8503);'):
                try:
                    db.sql(database, statement)
                except RuntimeError as error:
                    if '23514' not in str(error) or 'D-02' not in str(error):
                        raise
                else:
                    raise AssertionError('Una publicación antigua sin cupo se trató como validada por D-02.')
            # El historial antiguo continúa legible y nuevos proyectos usan v2.
            db.sql(database, """BEGIN;
              INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
                objetivos,justificacion,alcance,cupo_maximo_alumnos)
                VALUES(-8522,-8511,-8502,'Publicación nueva','Descripción','Problemática','Objetivos','Justificación','Alcance',2);
              SELECT banco.resolver_publicacion(banco.enviar_proyecto(-8522,-8502),-8501,'aprobada','Se valida cupo de dos');
              COMMIT;""")
            if db.sql(database, """SELECT count(*) FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id
              WHERE p.id=-8522 AND p.cupo_maximo_alumnos=2 AND r.instantanea_contenido->>'version_formato'='2'
                AND r.instantanea_contenido->'proyecto'->'cupo_maximo_alumnos'='2'::jsonb;""") != '1':
                raise AssertionError('La instalación actualizada no publica nuevos cupos con snapshot v2.')
            db.drop_temporary(database)
            database = None

            # Datos anteriormente admitidos que contradicen D-01: cuatro activas.
            database = db.create_temporary()
            db.migrations_path = temporary
            db.migrate(database)
            _fixture(db, database)
            db.sql(database, """BEGIN;
              INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo)
                VALUES(-8522,-8511,-8502,'Candidatura dos'),(-8523,-8511,-8502,'Candidatura tres'),(-8524,-8511,-8502,'Candidatura cuatro');
              INSERT INTO banco.candidatura(id,alumno_id,proyecto_id)
                VALUES(-8533,-8503,-8522),(-8534,-8503,-8523),(-8535,-8503,-8524);
              COMMIT;""")
            before = _rows(db, database)
            db.migrations_path = original
            _rejected(db, database, 'más de tres candidaturas activas')
            if _rows(db, database) != before:
                raise AssertionError('Rechazar datos incompatibles eliminó o cambió candidaturas históricas.')
            db.drop_temporary(database)
            database = None

            # Una asignación heredada no permite deducir una capacidad aprobada.
            database = db.create_temporary()
            db.migrations_path = temporary
            db.migrate(database)
            _fixture(db, database, assigned=True)
            before = _rows(db, database)
            db.migrations_path = original
            _rejected(db, database, 'asignaciones previas sin cupo válido')
            if _rows(db, database) != before:
                raise AssertionError('La actualización completó cupos o alteró asignaciones por su cuenta.')
            if db.sql(database, 'SELECT cupo_maximo_alumnos IS NULL FROM banco.proyecto WHERE id=-8521;') != 't':
                raise AssertionError('Se inventó un cupo para una asignación anterior.')
            db.drop_temporary(database)
            database = None

            # 011 añade un CHECK sobre decisiones inmutables: rechazar datos
            # anteriores no puede inventar un motivo ni dejar el helper nuevo.
            for path in original.glob('[0-9][0-9][0-9]_*.sql'):
                if int(path.name[:3]) <= 10:
                    (temporary / path.name).write_bytes(path.read_bytes())
            database = db.create_temporary()
            db.migrations_path = temporary
            db.migrate(database)
            db.sql(database, """BEGIN;
              INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
                (-8501,'Admin texto anterior','texto-anterior-admin@example.invalid','!prueba','administrador'),
                (-8502,'Empresa texto anterior','texto-anterior-rep@example.invalid','!prueba','empresa');
              INSERT INTO banco.empresa(id,razon_social) VALUES(-8511,'Empresa ficticia de texto anterior');
              INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-8502,-8511);
              INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
                objetivos,justificacion,alcance,cupo_maximo_alumnos)
                VALUES(-8521,-8511,-8502,'Título','Descripción','Problemática','Objetivos','Justificación','Alcance',1);
              SELECT banco.resolver_publicacion(banco.enviar_proyecto(-8521,-8502),-8501,'aprobada',E'\\t\\n');
              COMMIT;""")
            before = _rows(db, database)
            helper = db.sql(database, "SELECT pg_get_functiondef('banco.exigir_campos_proyecto(banco.proyecto)'::regprocedure);")
            db.migrations_path = original
            try:
                db.migrate(database)
            except RuntimeError as error:
                if '23514' not in str(error) or 'ck_decision_justificacion_texto' not in str(error):
                    raise
            else:
                raise AssertionError('011 aceptó un motivo histórico compuesto solo por blancos.')
            if _rows(db, database) != before:
                raise AssertionError('Rechazar 011 reescribió el contenido histórico.')
            if db.sql(database, "SELECT count(*) FROM control.migracion WHERE version LIKE '011_%';") != '0':
                raise AssertionError('011 fallida quedó registrada como aplicada.')
            if db.sql(database, "SELECT count(*) FROM pg_constraint WHERE conrelid='banco.decision_administrativa'::regclass AND conname='ck_decision_justificacion_texto';") != '0':
                raise AssertionError('011 fallida dejó su CHECK parcial.')
            if db.sql(database, "SELECT pg_get_functiondef('banco.exigir_campos_proyecto(banco.proyecto)'::regprocedure);") != helper:
                raise AssertionError('011 fallida no revirtió la sustitución de su helper.')
            return {
                'version_inicial': '001–003 instaladas por migrador real; publicación v1 y datos de negocio anteriores',
                'actualizacion': 'todas las migraciones vigentes aplicadas; contenido anterior exacto conservado',
                'publicacion_historica': 'sin cupo ni inicio inventados; nuevas operaciones condicionadas a D-02',
                'publicacion_nueva': 'snapshot v2 con cupo propuesto y validado',
                'recuperacion_version_anterior': 'rechazo previo claro, sin respaldo, base temporal ni cambios; primero aplicar las migraciones actuales',
                'datos_incompatibles': 'cuatro candidaturas activas o asignación sin cupo previo rechazan 006 con rollback de DDL y sin registro aplicado',
                'motivos_historicos_blancos': '011 rechazada sin reescribir las 21 tablas, registrar aplicación ni dejar CHECK/helper parciales',
                'limite': 'La conciliación de publicaciones/asignaciones anteriores requiere decisión y procedimiento explícitos; el test no los inventa.'
            }
        finally:
            db.migrations_path = original
            if database is not None:
                db.drop_temporary(database)

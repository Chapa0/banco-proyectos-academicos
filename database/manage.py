"""Ejecutor local de SQL versionado. Usa PostgreSQL real, sin un framework web."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

BASE = Path(__file__).resolve().parent
SQL_TESTS = ('integridad.sql', 'proyectos.sql', 'cupo_publicacion.sql', 'participaciones.sql', 'altas_cuentas.sql', 'textos_obligatorios.sql', 'cancelacion_direccion.sql', 'notificaciones.sql', 'conexion_web.sql', 'acceso_web.sql', 'publicacion_web.sql', 'perfiles_catalogo_web.sql', 'participacion_web.sql', 'avisos_reportes_web.sql')
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def require_temporary_database(name: str) -> None:
    if not re.fullmatch(r'banco_proyectos_test_[0-9a-f]{12}', name):
        raise ValueError('Solo se pueden eliminar bases temporales propias de esta ejecución.')


def require_database_name(name: str) -> None:
    if not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9_]{0,62}', name):
        raise ValueError('La base debe ser un nombre SQL simple, no una URI ni una cadena de conexión.')


class Database:
    def __init__(self, config: Path):
        self.config = json.loads(config.read_text(encoding='utf-8-sig'))
        for key in ('pg_bin', 'host', 'port', 'user', 'database', 'passfile'):
            if key not in self.config:
                raise ValueError(f'Falta {key} en la configuración local.')
        if self.config['host'] not in ('127.0.0.1', 'localhost', '::1'):
            raise ValueError('Este ejecutor está destinado a una instancia local de desarrollo.')
        self.target = self.config['database']
        require_database_name(self.target)
        if self.target in ('postgres', 'template0', 'template1'):
            raise ValueError('Configurar una base del proyecto, nunca una base de mantenimiento.')
        self.bin = Path(self.config['pg_bin'])
        # PGHOSTADDR/PGSERVICE heredados pueden redirigir incluso una conexión
        # que recibió --host. Todas las opciones PG se toman de este proyecto.
        self.env = {k:v for k,v in os.environ.items() if not k.upper().startswith('PG')}
        self.env.update(PGPASSFILE=str(Path(self.config['passfile']).resolve()),
                        PGCLIENTENCODING='UTF8', PGOPTIONS='-c timezone=UTC')
        if not Path(self.env['PGPASSFILE']).is_file():
            raise ValueError('No existe el archivo privado de credenciales indicado.')
        self.created: set[str] = set()
        self.migrations_path = BASE / 'migrations'

    def command(self, binary: str, database: str) -> list[str]:
        require_database_name(database)
        exe = self.bin / (binary + ('.exe' if os.name == 'nt' else ''))
        if not exe.is_file():
            raise ValueError(f'No se encuentra la herramienta {binary} en pg_bin.')
        return [str(exe), '--host', self.config['host'], '--port', str(self.config['port']),
                '--username', self.config['user'], '--no-password', '--dbname', database]

    def run(self, binary: str, database: str, args: list[str], text: str | None = None,
            timeout: int = 90) -> str:
        result = subprocess.run(self.command(binary, database) + args, input=text, encoding='utf-8',
                                env=self.env, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f'{binary}: salida {result.returncode}')
        return result.stdout.strip()

    def sql(self, database: str, statement: str, timeout: int = 90) -> str:
        return self.run('psql', database, ['-X', '-qAt', '-v', 'ON_ERROR_STOP=on', '-v', 'VERBOSITY=verbose'], statement, timeout)

    def verify_server(self) -> str:
        version = int(self.sql('postgres', 'SHOW server_version_num;'))
        if not 180000 <= version < 190000:
            raise RuntimeError('Se requiere PostgreSQL 18; no se modificó el servidor encontrado.')
        return self.sql('postgres', 'SELECT version();')

    def ensure_target(self) -> None:
        exists = self.sql('postgres', f'SELECT 1 FROM pg_database WHERE datname={sql_literal(self.target)};')
        if not exists:
            self.sql('postgres', f'CREATE DATABASE {sql_identifier(self.target)} ENCODING \'UTF8\' TEMPLATE template0;')

    def create_temporary(self) -> str:
        name = 'banco_proyectos_test_' + uuid.uuid4().hex[:12]
        self.sql('postgres', f'CREATE DATABASE {sql_identifier(name)} ENCODING \'UTF8\' TEMPLATE template0;')
        self.created.add(name)
        return name

    def drop_temporary(self, name: str) -> None:
        require_temporary_database(name)
        if name not in self.created:
            raise ValueError('La base temporal no fue creada por este proceso.')
        self.sql('postgres', f'DROP DATABASE {sql_identifier(name)};')
        self.created.remove(name)

    def migrate(self, database: str) -> str:
        files = sorted(self.migrations_path.glob('[0-9][0-9][0-9]_*.sql'))
        if not files:
            raise ValueError('No hay migraciones; no se creó una estructura vacía como si fuera una entrega.')
        chunks = ["SELECT pg_advisory_lock(71620261028);",
                  'CREATE SCHEMA IF NOT EXISTS control;',
                  '''CREATE TABLE IF NOT EXISTS control.migracion (
                       version text PRIMARY KEY, sha256 text NOT NULL, aplicada_en timestamptz NOT NULL DEFAULT now());''']
        names = ','.join(sql_literal(file.name) for file in files)
        chunks += [f'''DO $missing$ BEGIN
            IF EXISTS (SELECT 1 FROM control.migracion WHERE version NOT IN ({names})) THEN
                RAISE EXCEPTION 'Una migración registrada no existe entre los archivos disponibles';
            END IF;
            END $missing$;''']
        for file in files:
            content = file.read_text(encoding='utf-8-sig')
            digest = hashlib.sha256(file.read_bytes()).hexdigest()
            name = sql_literal(file.name)
            chunks += [f'''DO $migration$ BEGIN
                IF EXISTS (SELECT 1 FROM control.migracion WHERE version={name} AND sha256<>{sql_literal(digest)}) THEN
                    RAISE EXCEPTION 'Una migración aplicada cambió: %', {name};
                END IF;
                END $migration$;''',
                f'SELECT NOT EXISTS (SELECT 1 FROM control.migracion WHERE version={name}) AS aplicar',
                r'\gset', r'\if :aplicar', 'BEGIN;', content,
                f'INSERT INTO control.migracion(version,sha256) VALUES ({name},{sql_literal(digest)});',
                'COMMIT;', r'\endif']
        chunks += ['SELECT pg_advisory_unlock(71620261028);']
        self.sql(database, '\n'.join(chunks))
        return self.sql(database, 'SELECT version FROM control.migracion ORDER BY version;')

    def seed(self, database: str) -> None:
        self.sql(database, (BASE / 'seed.sql').read_text(encoding='utf-8-sig'))

    def catalog(self, database: str, schema: str = 'banco') -> dict:
        if schema not in ('banco', 'control'):
            raise ValueError('Solo se inspeccionan los esquemas del proyecto.')
        query = '''SELECT json_build_object(
          'permisos_esquemas',(SELECT json_agg(json_build_array(n.nspname,coalesce(r.rolname,'PUBLIC'),
                                  x.privilege_type,x.is_grantable)
                                  ORDER BY n.nspname,x.grantee,x.privilege_type)
                             FROM pg_namespace n
                             CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x
                             LEFT JOIN pg_roles r ON r.oid=x.grantee WHERE n.nspname='banco'),
          'tablas',(SELECT json_agg(t.table_name ORDER BY t.table_name) FROM information_schema.tables t
                     WHERE table_schema='banco' AND table_type='BASE TABLE'),
          'restricciones',(SELECT json_agg(json_build_array(c.relname,k.conname,pg_get_constraintdef(k.oid))
                           ORDER BY c.relname,k.conname) FROM pg_constraint k
                           JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='banco'),
          'columnas',(SELECT json_agg(json_build_object('tabla',c.relname,'columna',a.attname,
                           'tipo',format_type(a.atttypid,a.atttypmod),'no_nulo',a.attnotnull,
                           'identidad',a.attidentity,'generada',a.attgenerated,
                           'predeterminado',pg_get_expr(d.adbin,d.adrelid),
                           'comentario',col_description(c.oid,a.attnum)) ORDER BY c.relname,a.attnum)
                      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                      JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
                      LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
                      WHERE n.nspname='banco' AND c.relkind IN ('r','v')),
          'secuencias',(SELECT json_agg(json_build_object('nombre',c.relname,
                          'tipo',format_type(s.seqtypid,NULL),'inicio',s.seqstart,
                          'incremento',s.seqincrement,'minimo',s.seqmin,'maximo',s.seqmax,
                          'cache',s.seqcache,'ciclica',s.seqcycle,'tabla',t.relname,
                          'columna',a.attname,'dependencia',dep.deptype) ORDER BY c.relname)
                       FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid
                       JOIN pg_namespace n ON n.oid=c.relnamespace
                       LEFT JOIN pg_depend dep ON dep.classid='pg_class'::regclass
                         AND dep.objid=c.oid AND dep.refclassid='pg_class'::regclass
                         AND dep.deptype IN ('a','i') AND dep.refobjsubid>0
                       LEFT JOIN pg_class t ON t.oid=dep.refobjid
                       LEFT JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=dep.refobjsubid
                       WHERE n.nspname='banco'),
          'indices',(SELECT json_agg(pg_get_indexdef(i.indexrelid) ORDER BY c.relname)
                     FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                     JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='banco'),
          'triggers',(SELECT json_agg(pg_get_triggerdef(t.oid) ORDER BY c.relname,t.tgname)
                      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                      JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='banco' AND NOT t.tgisinternal),
          'funciones',(SELECT json_agg(pg_get_functiondef(p.oid) ORDER BY p.proname,pg_get_function_identity_arguments(p.oid))
                       FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='banco'),
          'vistas',(SELECT json_agg(json_build_array(c.relname,pg_get_viewdef(c.oid)) ORDER BY c.relname)
                    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='banco' AND c.relkind='v'),
          'permisos_tablas',(SELECT json_agg(json_build_array(table_name,grantee,privilege_type,is_grantable)
                                      ORDER BY table_name,grantee,privilege_type)
                             FROM information_schema.table_privileges WHERE table_schema='banco'),
          'permisos_secuencias',(SELECT json_agg(json_build_array(c.relname,coalesce(r.rolname,'PUBLIC'),
                                  x.privilege_type,x.is_grantable)
                                  ORDER BY c.relname,x.grantee,x.privilege_type)
                             FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                             CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('s',c.relowner))) x
                             LEFT JOIN pg_roles r ON r.oid=x.grantee
                             WHERE n.nspname='banco' AND c.relkind='S'),
          'permisos_funciones',(SELECT json_agg(json_build_array(p.proname,pg_get_function_identity_arguments(p.oid),
                                  coalesce(r.rolname,'PUBLIC'),x.privilege_type,x.is_grantable)
                                  ORDER BY p.proname,pg_get_function_identity_arguments(p.oid),x.grantee,x.privilege_type)
                             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                             CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
                             LEFT JOIN pg_roles r ON r.oid=x.grantee WHERE n.nspname='banco'));
        '''
        # La misma inspección se aplica al historial técnico sin mezclarlo con
        # las entidades de negocio. El esquema está limitado a los dos propios.
        return json.loads(self.sql(database, query.replace("'banco'", sql_literal(schema))))

    def sequence_values(self, database: str) -> dict:
        sequences = self.catalog(database)['secuencias'] or []
        if not sequences:
            return {}
        parts = [f'''SELECT {sql_literal(sequence['nombre'])} AS nombre,
          json_build_object('ultimo_valor',last_value,'llamada',is_called) AS valor
          FROM banco.{sql_identifier(sequence['nombre'])}''' for sequence in sequences]
        return json.loads(self.sql(database,
            'SELECT json_object_agg(nombre,valor) FROM (' + ' UNION ALL '.join(parts) + ') q;'))

    def migration_state(self, database: str) -> dict:
        catalog = self.catalog(database, 'control')
        rows = None
        if 'migracion' in (catalog['tablas'] or []):
            rows = json.loads(self.sql(database, '''SELECT COALESCE(json_agg(json_build_object(
              'version',version,'sha256',sha256,'aplicada_en',aplicada_en) ORDER BY version),'[]'::json)
              FROM control.migracion;'''))
        return {'catalogo': catalog, 'filas': rows}

    def counts(self, database: str) -> dict:
        tables = self.catalog(database)['tablas'] or []
        if not tables:
            return {}
        parts = [f'SELECT {sql_literal(t)} AS tabla,count(*) AS total FROM banco.{sql_identifier(t)}' for t in tables]
        return json.loads(self.sql(database, 'SELECT json_object_agg(tabla,total) FROM (' + ' UNION ALL '.join(parts) + ') q;'))

    def content_fingerprints(self, database: str) -> dict:
        parts = [f'''SELECT {sql_literal(t)} AS tabla,
          encode(sha256(convert_to(coalesce(string_agg(to_jsonb(fila)::text,E'\\n'
            ORDER BY to_jsonb(fila)::text),''),'UTF8')),'hex') AS sha256
          FROM banco.{sql_identifier(t)} fila''' for t in self.catalog(database)['tablas']]
        return json.loads(self.sql(database, 'SELECT json_object_agg(tabla,sha256) FROM (' + ' UNION ALL '.join(parts) + ') q;'))

    def dictionary(self, database: str) -> Path:
        catalog = self.catalog(database)
        path = BASE.parent / 'docs/09-base-de-datos.md'
        original = path.read_text(encoding='utf-8')
        marker = '<!-- diccionario generado -->'
        if marker not in original:
            raise ValueError('Falta el marcador del diccionario; no se sobrescribió la documentación.')
        rows = ['## Diccionario físico', '', 'Generado del catálogo PostgreSQL con `python database/manage.py dictionary`. No editar las tablas a mano.', '']
        escape = lambda value: str(value or '').replace('|', '\\|').replace('\n', ' ')
        for table in catalog['tablas']:
            rows += [f'### {table}', '', '| Columna | Tipo | Admite NULL | Valor inicial o generación |', '| --- | --- | --- | --- |']
            for column in catalog['columnas']:
                if column['tabla'] != table:
                    continue
                default = 'IDENTITY BY DEFAULT' if column['identidad'] else column['predeterminado']
                if column['generada']:
                    default = 'Generada: ' + str(default)
                rows += [f"| `{column['columna']}` | {escape(column['tipo'])} | {'No' if column['no_nulo'] else 'Sí'} | {escape(default) or '-'} |"]
            rows += ['', 'Restricciones:', '']
            rows += [f'- `{escape(name)}`: `{escape(definition)}`.' for parent,name,definition in catalog['restricciones'] if parent==table]
            rows += ['']
        path.write_text(original.split(marker)[0] + marker + '\n\n' + '\n'.join(rows), encoding='utf-8')
        return path

    def local_server(self, action: str) -> str:
        cluster = BASE / '.local/data'
        if not (cluster / 'PG_VERSION').is_file() or (cluster / 'PG_VERSION').read_text().strip() != '18':
            raise ValueError('No se encontró el clúster PostgreSQL 18 propio de este proyecto.')
        binary = self.bin / ('pg_ctl.exe' if os.name == 'nt' else 'pg_ctl')
        command = [str(binary), '-D', str(cluster)]
        options = dict(capture_output=True, encoding='utf-8', errors='replace', timeout=45,
                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        status = subprocess.run(command + ['status'], **options)
        if action == 'start' and status.returncode == 0:
            return 'La instancia del proyecto ya está en ejecución.'
        if action == 'stop' and status.returncode == 3:
            return 'La instancia del proyecto ya está detenida.'
        args = ['-l', str(BASE / '.local/postgresql.log'), '-w', '-t','20','start'] if action=='start' else ['-m','fast','-w','-t','20','stop']
        # En Windows el servidor puede heredar una tubería capturada de pg_ctl;
        # esperar EOF de esa tubería bloquearía al ejecutor aunque pg_ctl termine.
        # El archivo permite esperar únicamente al proceso de control.
        log = BASE / '.local/pg_ctl.log'
        with log.open('w',encoding='utf-8') as output:
            result = subprocess.run(command + args, stdin=subprocess.DEVNULL, stdout=output,
                stderr=subprocess.STDOUT, timeout=45,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        message = log.read_text(encoding='utf-8',errors='replace').strip()
        if result.returncode:
            raise RuntimeError(message)
        return message

    def backup(self, database: str, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            raise ValueError('El respaldo de destino ya existe; elegir un nombre nuevo.')
        self.run('pg_dump', database, ['--format=custom', '--no-owner', '--file', str(path)], timeout=180)

    def restore_check(self, database: str) -> dict:
        current_migrations = self.migration_state(database)
        registered = {row['version']: row['sha256'] for row in (current_migrations['filas'] or [])}
        available = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in self.migrations_path.glob('[0-9][0-9][0-9]_*.sql')}
        if not available or registered != available:
            raise RuntimeError('La base y las migraciones disponibles no coinciden; ejecute migrate antes de verificar la restauración.')
        destination = self.create_temporary()
        path = BASE / '.local' / 'backups' / f'{uuid.uuid4().hex}.dump'
        try:
            self.backup(database, path)
            self.run('pg_restore', destination, ['--exit-on-error', '--no-owner', str(path)], timeout=180)
            if self.catalog(database) != self.catalog(destination):
                raise RuntimeError('El catálogo restaurado difiere del origen.')
            migration_state = self.migration_state(database)
            if migration_state != self.migration_state(destination):
                raise RuntimeError('El historial técnico de migraciones restaurado difiere del origen.')
            counts = self.counts(database)
            if counts != self.counts(destination):
                raise RuntimeError('Las cantidades de registros restauradas difieren del origen.')
            fingerprints = self.content_fingerprints(database)
            if fingerprints != self.content_fingerprints(destination):
                raise RuntimeError('El contenido restaurado difiere del origen.')
            sequence_values = self.sequence_values(database)
            if sequence_values != self.sequence_values(destination):
                raise RuntimeError('El estado de las secuencias restauradas difiere del origen.')
            # Verificar primero el historial: migrate no debe reconstruirlo ni
            # ocultar una restauración incompleta. Después debe ser un no-op.
            self.migrate(destination)
            if migration_state != self.migration_state(destination):
                raise RuntimeError('Migrar la copia restaurada cambió su historial técnico.')
            for filename in SQL_TESTS:
                self.sql(destination, (BASE / 'tests' / filename).read_text(encoding='utf-8-sig'))
            return {'resultado': 'correcto', 'tablas': len(counts), 'filas_por_tabla': counts,
                    'sha256_respaldo': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'sha256_contenido_por_tabla': fingerprints,
                    'secuencias': sequence_values,
                    'historial_migraciones': 'catálogo, versiones, checksum y fechas idénticos; migrate posterior sin cambios',
                    'alcance': 'Restauración en otra base: estructura, permisos de esquemas y objetos, contenido, secuencias, historial técnico, migración posterior e integridad comprobados.'}
        finally:
            self.drop_temporary(destination)


def run_tests(db: Database) -> dict:
    start = time.monotonic()
    unit = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(BASE / 'tests'),
                           '-p', 'test_runner.py', '-v'], capture_output=True, encoding='utf-8', timeout=30)
    if unit.returncode:
        raise RuntimeError(unit.stderr)
    name = db.create_temporary()
    try:
        first = db.migrate(name)
        if db.migrate(name) != first:
            raise RuntimeError('Migraciones no idempotentes')
        spec = importlib.util.spec_from_file_location('migraciones', BASE / 'tests/migraciones.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        migration_guards = module.run(db, name)
        spec = importlib.util.spec_from_file_location('actualizacion', BASE / 'tests/actualizacion.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        upgrade = module.run(db)
        db.seed(name)
        initial = db.counts(name)
        db.seed(name)
        if db.counts(name) != initial:
            raise RuntimeError('Semillas no idempotentes')
        test_files = [BASE / 'tests' / filename for filename in SQL_TESTS]
        output = '\n'.join(db.sql(name, path.read_text(encoding='utf-8-sig')) for path in test_files)
        spec = importlib.util.spec_from_file_location('concurrencia', BASE / 'tests' / 'concurrencia.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        concurrent = module.run(db, name)
        concurrent.update(module.publication_races(db, name))
        isolation = module.isolation_guard(db, name)
        participation = {}
        for filename in ('direccion_unica', 'cupos_y_carga', 'inicio_proyecto', 'cancelacion_candidatura', 'retiro_pausa_reanudacion', 'cierre_proyectos', 'evaluacion_autorizacion', 'cuentas_privacidad', 'acceso_concurrencia', 'publicacion_concurrencia', 'perfiles_catalogo_concurrencia', 'participacion_web_concurrencia', 'avisos_reportes_concurrencia'):
            spec = importlib.util.spec_from_file_location(filename, BASE / 'tests' / (filename + '.py'))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            participation[filename] = module.run(db, name)
        recovery = db.restore_check(name)
        spec = importlib.util.spec_from_file_location('recuperacion', BASE / 'tests/recuperacion.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        corruption = module.run(db, name)
        catalog = db.catalog(name)
        expected = json.loads((BASE.parent / 'tareas/01-modelo-entidad-relacion/fuentes/modelo.json').read_text(encoding='utf-8'))
        if set(catalog['tablas']) != {e['id'] for e in expected['entidades']}:
            raise RuntimeError('Tablas diferentes al modelo')
        result = {'fecha_utc': datetime.now(timezone.utc).isoformat(), 'postgres': db.verify_server(),
                  'resultado': 'correcto', 'tablas_negocio': len(catalog['tablas']),
                  'restricciones': len(catalog['restricciones']),
                  'indices': len(catalog['indices']), 'triggers': len(catalog['triggers']),
                  'funciones': len(catalog['funciones']),
                  'secuencias': len(catalog['secuencias'] or []),
                  'protecciones_ejecutor': 'unittest correcto',
                  'integridad': [line for line in output.splitlines() if line.strip() and not line.strip().isdigit()],
                  'casos_negativos_sql': sum(len(re.findall(r'SELECT pg_temp\.(?:espera_error|proyecto_error|cupo_error|participacion_error|alta_error|texto_error|cancel_dir_error|aviso_error|web_error|acceso_error|publicacion_error|perfil_error|part_web_error|com_web_error)\(', path.read_text(encoding='utf-8-sig'))) for path in test_files),
                  'concurrencia': concurrent, 'respaldo_restauracion': recovery,
                  'participacion_e_inicio': participation,
                  'aislamiento_de_escritura': isolation,
                  'deteccion_de_corrupcion': corruption,
                  'migraciones_y_semillas': 'segunda ejecución sin cambios',
                  'protecciones_migracion': migration_guards,
                  'actualizacion_con_historial': upgrade,
                  'sha256_fuentes': {str(path.relative_to(BASE)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in sorted([BASE / 'manage.py', BASE / 'seed.sql',
                                        *BASE.joinpath('migrations').glob('*.sql'),
                                        *BASE.joinpath('tests').glob('*.sql'),
                                        *BASE.joinpath('tests').glob('*.py')])},
                  'politicas_pendientes': [],
                  'datos_institucionales_por_conocer': ['D-12: alojamiento, calendario, equipo y carga de producción; retención legal D-10'],
                  'decisiones_delegadas': 'D-07/D-08/D-10/D-11 concretadas para primera versión por delegación del usuario el 10 de noviembre de 2026.',
                  'limite': 'Base PostgreSQL local con operaciones internas y avisos persistentes; sin APIs, autenticación web, envío externo ni despliegue institucional. No acredita los recorridos web de los 42 RF.',
                  'segundos': round(time.monotonic() - start, 2)}
        evidence = BASE / 'evidencia/verificacion.json'
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        return result
    finally:
        db.drop_temporary(name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=BASE / '.local/connection.json')
    parser.add_argument('command', choices=['start','stop','status','migrate','seed','test','backup','snapshot','dictionary','restore-check'])
    args = parser.parse_args()
    db = Database(args.config)
    if args.command in ('start','stop'):
        print(db.local_server(args.command))
        return
    version = db.verify_server()
    if args.command == 'status':
        print(version)
        print(db.sql('postgres', "SELECT datname FROM pg_database WHERE datname LIKE 'banco_proyectos%' ORDER BY 1;"))
    elif args.command == 'test':
        print(json.dumps(run_tests(db), ensure_ascii=False, indent=2))
    elif args.command == 'migrate':
        db.ensure_target()
        print(db.migrate(db.target))
    elif args.command == 'seed':
        db.seed(db.target)
        print(json.dumps(db.counts(db.target), ensure_ascii=False))
    elif args.command == 'backup':
        path = BASE / '.local/backups' / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S') + '.dump')
        db.backup(db.target, path)
        print(path)
    elif args.command == 'snapshot':
        out = BASE / 'sql/esquema.sql'
        out.parent.mkdir(parents=True, exist_ok=True)
        db.run('pg_dump', db.target, ['--schema-only', '--no-owner', '--no-privileges', '--schema=banco', '--file', str(out)])
        print(out)
    elif args.command == 'dictionary':
        print(db.dictionary(db.target))
    else:
        print(json.dumps(db.restore_check(db.target), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)

"""WEB-05: perfiles y catálogo por HTTP sobre una PostgreSQL temporal propia."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from postgres import IntegrationError, dotenv, phpunit_summary
from acceso import FIXTURE_PASSWORD
from publicacion import fixture as fixture_publicacion

WEB = Path(__file__).resolve().parents[1]
PROJECT = WEB.parent
DATABASE = PROJECT / 'database'
sys.path.insert(0, str(DATABASE))
from manage import Database, require_temporary_database, sql_identifier, sql_literal  # noqa: E402


def show_output(output: str) -> None:
    directory = PROJECT / '.local'
    directory.mkdir(exist_ok=True)
    (directory / 'web05-pruebas.log').write_text(output + '\n', encoding='utf-8')
    for line in output.splitlines():
        try:
            result = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(result, dict) and result.get('tool') == 'phpunit':
            summary = {key: result[key] for key in ('tool', 'result', 'tests', 'passed', 'failed', 'assertions', 'duration_ms')
                       if key in result}
            if result.get('failures'):
                summary['failures'] = [{'test': row.get('test'), 'message': row.get('message', '')[:600]}
                                       for row in result['failures']]
            print(json.dumps(summary, ensure_ascii=False))
            return
    print(output[-5000:])


def sources() -> dict[str, str]:
    files = {
        Path(__file__).resolve(), WEB / 'tests/postgres.py', WEB / 'tests/acceso.py', WEB / 'tests/publicacion.py',
        WEB / 'tests/PostgresTestCase.php', WEB / 'tests/Integration/PerfilesCatalogoTest.php',
        WEB / 'phpunit.xml', WEB / 'composer.json', WEB / 'composer.lock',
        WEB / 'package.json', WEB / 'package-lock.json', DATABASE / 'manage.py', DATABASE / 'seed.sql',
        *WEB.joinpath('app').rglob('*.php'), *WEB.joinpath('config').glob('*.php'),
        *WEB.joinpath('routes').glob('*.php'), *WEB.joinpath('bootstrap').glob('*.php'),
        *WEB.joinpath('resources').rglob('*.blade.php'),
        *DATABASE.joinpath('migrations').glob('[0-9][0-9][0-9]_*.sql'),
    }
    return {str(file.relative_to(PROJECT)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in sorted(files) if file.is_file()}


def prepare_database(db: Database, name: str, php: str) -> None:
    """Ejercitar una publicación v1 auténtica y su actualización sin eludir triggers."""
    require_temporary_database(name)
    if name not in db.created:
        raise IntegrationError('La fixture requiere una temporal creada por el mismo proceso.')
    original = db.migrations_path
    directory = PROJECT / '.local'
    directory.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='web05-migraciones-', dir=directory) as temporary:
        prefix = Path(temporary)
        for migration in sorted(original.glob('[0-9][0-9][0-9]_*.sql')):
            if int(migration.name[:3]) <= 3:
                shutil.copyfile(migration, prefix / migration.name)
        try:
            db.migrations_path = prefix
            db.migrate(name)
        finally:
            db.migrations_path = original
    db.sql(name, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      VALUES(-250011,'Administrador histórico WEB05','legacy-admin-web05@example.invalid','!SIN-ACCESO-LEGADO','administrador'),
        (-250012,'Representante histórico WEB05','legacy-rep-web05@example.invalid','!SIN-ACCESO-LEGADO','empresa');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-250111,'Empresa histórica WEB05');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-250012,-250111);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance)
      VALUES(-250206,-250111,-250012,'PUBLICADO_LEGADO_SIN_CUPO_WEB05','Descripción histórica','Problema histórico',
        'Objetivo histórico','Justificación histórica','Alcance histórico');
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-250206,-250012),-250011,'aprobada','MOTIVO_LEGADO_PRIVADO_WEB05');
      COMMIT;""")
    db.migrate(name)
    db.seed(name)
    fixture(db, name, php)


def fixture(db: Database, name: str, php: str) -> None:
    """Participantes y publicaciones ficticios; nunca modifica la base de trabajo."""
    require_temporary_database(name)
    if name not in db.created:
        raise IntegrationError('La fixture requiere una temporal creada por el mismo proceso.')
    fixture_publicacion(db, name, php)
    db.sql(name, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT -250003,'Otro alumno WEB05','web05-otro-alumno@example.invalid',hash_contrasena,'alumno' FROM banco.usuario WHERE id=-220003
      UNION ALL SELECT -250004,'Otro profesor WEB05','web05-otro-profesor@example.invalid',hash_contrasena,'profesor' FROM banco.usuario WHERE id=-220004;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta)
        SELECT -250005,'Profesor inactivo WEB05','web05-inactivo-profesor@example.invalid',hash_contrasena,'profesor','inactiva'
        FROM banco.usuario WHERE id=-220004;
      INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo)
        VALUES(-250003,'WEB05-OTRO-001','Carrera privada WEB05',4,'DATOS_ACADEMICOS_AJENOS_WEB05','otro-contacto-web05@example.invalid');
      INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo)
        VALUES(-250004,'WEB05-PROF-001','Especialidad ajena WEB05','EXPERIENCIA_AJENA_WEB05','otro-prof-contacto@example.invalid');
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES(-250005,'WEB05-PROF-INACTIVO');
      INSERT INTO banco.habilidad(id,nombre,tipo,descripcion)
        VALUES(-250101,'Programación WEB05','dura','Diseño de programas'),(-250102,'Comunicación WEB05','blanda','Comunicación oral');
      UPDATE banco.empresa SET sector='Tecnología',contacto_nombre='Contacto público WEB05',
        contacto_correo='empresa-contacto-web05@example.invalid',contacto_telefono='5550102020' WHERE id=-220101;
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,
        alcance,cupo_maximo_alumnos,modalidad,requisitos_academicos,duracion_estimada,recursos)
      VALUES(-250201,-220101,-220005,'Inventario WEB05','Descripción publicada WEB05','Problema de existencias',
        'Registrar existencias','Evitar pérdidas','Registro interno',3,'remota','Bases de datos','Doce semanas','Computadora'),
      (-250202,-220102,-220006,'Portal comunitario WEB05','Descripción del portal','Problema de comunicación',
        'Comunicar actividades','Informar comunidad','Portal público',2,'presencial','Comunicación','Diez semanas','Oficina'),
      (-250203,-220101,-220005,'BORRADOR_PRIVADO_WEB05','Descripción borrador','Problema','Objetivo','Justificación','Alcance',1,'remota',NULL,NULL,NULL),
      (-250204,-220101,-220005,'CORRECCION_PRIVADA_WEB05','Descripción corrección','Problema','Objetivo','Justificación','Alcance',1,'remota',NULL,NULL,NULL),
      (-250205,-220101,-220005,'RECHAZADO_PRIVADO_WEB05','Descripción rechazo','Problema','Objetivo','Justificación','Alcance',1,'remota',NULL,NULL,NULL),
      (-250207,-220101,-220005,'Cupo agotado WEB05','Descripción agotado','Problema','Objetivo','Justificación','Alcance',1,'remota',NULL,NULL,NULL);
      INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria)
        VALUES(-250201,-250101,'Intermedio aprobado WEB05',true),(-250202,-250102,'Básico aprobado WEB05',false);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,autor_usuario_id),-220001,
        CASE id WHEN -250204 THEN 'en_correccion' WHEN -250205 THEN 'rechazada' ELSE 'aprobada' END,'MOTIVO_PRIVADO_WEB05_NO_CATALOGO')
        FROM banco.proyecto WHERE id IN (-250201,-250202,-250204,-250205,-250207);
      SELECT banco.evaluar_candidatura(banco.presentar_candidatura(-250207,-250003),-220005,
        '{"tecnico":{"puntuacion":2,"comentario":"Cumple"},"blando":{"puntuacion":2,"comentario":"Cumple"},"academico":{"puntuacion":2,"comentario":"Cumple"}}'::jsonb,
        'Evaluación de fixture WEB05',true);
      SELECT banco.preseleccionar_candidatura(id,-220005) FROM banco.candidatura WHERE proyecto_id=-250207;
      SELECT banco.resolver_candidatura(id,-220001,'aprobada','Asignación de fixture WEB05') FROM banco.candidatura WHERE proyecto_id=-250207;
      SELECT banco.resolver_direccion(banco.solicitar_direccion(-250201,-250004,'Experiencia de fixture','Justificación de fixture'),
        -220001,'aprobada','Dirección de fixture WEB05');
      -- Una modificación posterior del catálogo de habilidades no debe cambiar
      -- el nombre/tipo que la revisión publicada aprobó.
      UPDATE banco.habilidad SET nombre='NOMBRE_NUEVO_NO_APROBADO_WEB05' WHERE id=-250101;
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos,modalidad)
      SELECT -251000-n,-220102,-220006,'Paginación WEB05 '||lpad(n::text,2,'0'),'Descripción paginada',
        'Problema','Objetivo','Justificación','Alcance',1,'hibrida' FROM generate_series(1,22) n;
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,autor_usuario_id),-220001,'aprobada','MOTIVO_PRIVADO_WEB05_NO_CATALOGO')
        FROM banco.proyecto WHERE id BETWEEN -251022 AND -251001;
      COMMIT;""")


def main() -> None:
    started = time.monotonic()
    values = dotenv(WEB / '.env')
    password, username = values.get('DB_PASSWORD', ''), values.get('DB_USERNAME', '')
    host, port = values.get('DB_HOST', ''), values.get('DB_PORT', '')
    if not password or not username or username == 'proweb_admin':
        raise IntegrationError('Preparar primero la credencial propia de la aplicación.')
    if host not in ('127.0.0.1', 'localhost', '::1') or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise IntegrationError('Solo se permite una instancia PostgreSQL local explícita.')
    portable = PROJECT / '.local/tools/php/php.exe'
    php = os.environ.get('BANCO_PHP_BINARY') or (str(portable) if portable.is_file() else shutil.which('php'))
    if not php or not Path(php).is_file() or not (WEB / 'vendor/bin/phpunit').is_file():
        raise IntegrationError('No se encontraron PHP y las dependencias de integración.')
    if (WEB / 'bootstrap/cache/config.php').exists():
        raise IntegrationError('Ejecutar antes artisan config:clear para aislar la configuración.')
    db = Database(DATABASE / '.local/connection.json')
    if str(db.config['port']) != port or db.config['host'] != host:
        raise IntegrationError('La web y las herramientas deben usar la misma instancia local.')
    role = db.sql('postgres', f'''SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)}
      AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls AND pg_has_role(oid,'banco_web','USAGE');''')
    if role != '1':
        raise IntegrationError('Las pruebas requieren la credencial web sin privilegios administrativos.')
    before, name = sources(), None
    try:
        name = db.create_temporary()
        prepare_database(db, name, php)
        baseline = db.sql(name, 'SELECT count(*) FROM banco.evento_auditoria;')
        db.sql('postgres', f'GRANT CONNECT ON DATABASE {sql_identifier(name)} TO {sql_identifier(username)};')
        env = {key: value for key, value in os.environ.items() if not key.startswith(('DB_', 'BANCO_TEST_', 'PG'))}
        env.update(APP_ENV='testing', BANCO_TEST_WEB02='1', BANCO_TEST_WEB05='1', BANCO_TEST_DATABASE=name,
                   BANCO_TEST_USERNAME=username, BANCO_TEST_PASSWORD=password, BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        result = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/PerfilesCatalogoTest.php', '--colors=never'],
                                cwd=WEB, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=240)
        output = (result.stdout + '\n' + result.stderr).strip()
        for value in (password, FIXTURE_PASSWORD, 'CambioSeguro-2026!'):
            output = output.replace(value, '[REDACTADO]')
        show_output(output)
        if result.returncode:
            raise IntegrationError('Falló la integración de perfiles y catálogo; no se actualizó la evidencia.')
        summary = phpunit_summary(output)
        if db.sql(name, 'SELECT count(*) FROM banco.evento_auditoria;') != baseline:
            raise IntegrationError('Las pruebas dejaron auditorías fuera de su transacción de aislamiento.')
        if sources() != before:
            raise IntegrationError('Las fuentes cambiaron durante la prueba; repetir cuando estén estables.')
        migration_count = int(db.sql(name, 'SELECT count(*) FROM control.migracion;'))
        version = db.verify_server()
    finally:
        if name is not None:
            db.drop_temporary(name)
    receipt = {
        'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto', 'bloque': 'WEB-05',
        'postgres': version, 'migraciones': migration_count, 'phpunit': summary,
        'base_de_trabajo_usada': False, 'temporal_eliminada': True,
        'credencial': 'Aplicación, sin superusuario ni lectura/DML general de tablas.',
        'aislamiento': 'Base temporal propia; cada caso HTTP revierte su transacción y sus auditorías.',
        'alcance': 'Perfiles propios alumno/profesor, habilidades y evidencia textual, CAS, privacidad, validación, permisos, CSRF y catálogo publicado con filtros, paginación, instantánea y disponibilidad.',
        'limites': 'HTTP Laravel y PostgreSQL real; no sustituye la revisión visual en navegador. Candidaturas y dirección web corresponden a WEB-06.',
        'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
    }
    target = WEB / 'evidencia/web05/regresion-postgres.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Integración WEB-05 correcta; temporal propia eliminada y evidencia guardada sin modificar recibos anteriores.')


if __name__ == '__main__':
    try:
        main()
    except IntegrationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(f'Integración WEB-05 interrumpida ({type(error).__name__}); sin evidencia nueva ni secretos mostrados.', file=sys.stderr)
        sys.exit(1)

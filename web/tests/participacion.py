"""WEB-06: participación y ciclo por HTTP sobre PostgreSQL temporal propio."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from postgres import IntegrationError, dotenv, phpunit_summary
from acceso import FIXTURE_PASSWORD
from perfiles import prepare_database as prepare_perfiles

WEB = Path(__file__).resolve().parents[1]
PROJECT = WEB.parent
DATABASE = PROJECT / 'database'
sys.path.insert(0, str(DATABASE))
from manage import Database, require_temporary_database, sql_identifier, sql_literal  # noqa: E402


def require_fixture(db: Database, name: str) -> None:
    require_temporary_database(name)
    if name not in db.created:
        raise IntegrationError('La fixture requiere una temporal creada por el mismo proceso.')


def prepare_database(db: Database, name: str, php: str) -> None:
    """Preparar también el legado v1 de WEB-05, sin omitir sus protecciones."""
    require_fixture(db, name)
    prepare_perfiles(db, name, php)
    fixture(db, name, php)


def fixture(db: Database, name: str, php: str) -> None:
    """Actores, proyectos y fallos controlados exclusivos de una temporal propia."""
    require_fixture(db, name)
    db.sql(name, """BEGIN;
      INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo)
        VALUES(-220003,'WEB06-ALUMNO-PROPIO','Sistemas computacionales',5,'Formación académica WEB06','alumno-contacto-web06@example.invalid');
      INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo)
        VALUES(-220004,'WEB06-PROFESOR-PROPIO','Bases de datos','Docencia y dirección académica WEB06','profesor-contacto-web06@example.invalid');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT -260000-n,'Alumno adicional WEB06 '||n,'web06-alumno-'||n||'@example.invalid',hash_contrasena,'alumno'
        FROM banco.usuario CROSS JOIN generate_series(1,8) n WHERE id=-220003;
      INSERT INTO banco.alumno(usuario_id,matricula,carrera,contacto_correo)
        SELECT id,'WEB06-EXTRA-'||(-id),'Datos académicos reservados '||id,'contacto'||(-id)||'@example.invalid'
        FROM banco.usuario WHERE id BETWEEN -260008 AND -260001;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT -260010-n,'Profesor adicional WEB06 '||n,'web06-profesor-'||n||'@example.invalid',hash_contrasena,'profesor'
        FROM banco.usuario CROSS JOIN generate_series(1,5) n WHERE id=-220004;
      INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo)
        SELECT id,'WEB06-PROF-EXTRA-'||(-id),'Especialidad reservada '||id,'Experiencia docente '||id,'contacto'||(-id)||'@example.invalid'
        FROM banco.usuario WHERE id BETWEEN -260015 AND -260011;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT x.id,x.nombre,x.correo,u.hash_contrasena,'alumno' FROM banco.usuario u CROSS JOIN (VALUES
          (-260090::bigint,'Alumno fallo auditoría WEB06','web06-auditoria@example.invalid'),
          (-260091::bigint,'Alumno fallo aviso WEB06','web06-aviso@example.invalid'),
          (-260092::bigint,'Alumno sin perfil WEB06','web06-sin-perfil@example.invalid'),
          (-260099::bigint,'Alumno historial WEB06','web06-historial@example.invalid')) x(id,nombre,correo)
        WHERE u.id=-220003;
      INSERT INTO banco.alumno(usuario_id,matricula) VALUES
        (-260090,'WEB06-AUDITORIA'),(-260091,'WEB06-AVISO'),(-260099,'WEB06-HISTORIAL');
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,
        justificacion,alcance,cupo_maximo_alumnos,modalidad,requisitos_academicos,duracion_estimada)
        SELECT -260200-n,CASE WHEN n<=24 THEN -220101 ELSE -220102 END,
          CASE WHEN n<=24 THEN -220005 ELSE -220006 END,
          'Proyecto WEB06 '||lpad(n::text,2,'0'),'Descripción pública WEB06 '||n,
          'Problema de la empresa','Objetivo académico','Justificación del proyecto','Alcance acordado',
          CASE WHEN n=24 THEN 1 ELSE 3 END,'remota','Bases de datos y programación','Doce semanas'
          FROM generate_series(1,28) n;
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,autor_usuario_id),-220001,
        'aprobada','Motivo administrativo publicado WEB06') FROM banco.proyecto WHERE id BETWEEN -260228 AND -260201;
      INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,descripcion,evidencia)
        VALUES(-220003,-250101,'Intermedio','Consultas y pruebas','javascript:alert("EVIDENCIA_WEB06")'),
          (-220003,-250102,'Avanzado','Presentaciones del equipo','Texto de evidencia WEB06');
      DO $history$ DECLARE v_id bigint; BEGIN
        FOR n IN 1..22 LOOP
          v_id:=banco.presentar_candidatura(-260201,-260099);
          PERFORM banco.cancelar_candidatura(v_id,-260099);
        END LOOP;
      END $history$;
      COMMIT;""")
    # La aplicación no recibe DDL ni acceso a estas tablas. Solo los dos actores
    # ficticios dedicados provocan fallos, para acreditar rollback del gateway.
    db.sql(name, """
      CREATE FUNCTION banco.fixture_web06_fallo_auditoria() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.actor_usuario_id=-260090 AND NEW.operacion='presentar_candidatura'
          THEN RAISE EXCEPTION 'Fallo controlado de auditoría WEB06'; END IF;
        RETURN NEW;
      END;$$;
      CREATE TRIGGER fixture_web06_fallo_auditoria BEFORE INSERT ON banco.evento_auditoria
        FOR EACH ROW EXECUTE FUNCTION banco.fixture_web06_fallo_auditoria();
      CREATE FUNCTION banco.fixture_web06_fallo_aviso() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF EXISTS(SELECT 1 FROM banco.evento_auditoria WHERE id=NEW.evento_id AND actor_usuario_id=-260091 AND operacion='presentar_candidatura')
          THEN RAISE EXCEPTION 'Fallo controlado de aviso WEB06'; END IF;
        RETURN NEW;
      END;$$;
      CREATE TRIGGER fixture_web06_fallo_aviso BEFORE INSERT ON banco.notificacion
        FOR EACH ROW EXECUTE FUNCTION banco.fixture_web06_fallo_aviso();
      REVOKE ALL ON FUNCTION banco.fixture_web06_fallo_auditoria(),banco.fixture_web06_fallo_aviso()
        FROM PUBLIC,banco_web,banco_lectura,banco_escritura;
    """)


def sources() -> dict[str, str]:
    files = {
        Path(__file__).resolve(), WEB / 'tests/postgres.py', WEB / 'tests/acceso.py',
        WEB / 'tests/publicacion.py', WEB / 'tests/perfiles.py', WEB / 'tests/PostgresTestCase.php',
        WEB / 'tests/Integration/ParticipacionTest.php', WEB / 'phpunit.xml',
        WEB / 'composer.json', WEB / 'composer.lock', WEB / 'package.json', WEB / 'package-lock.json',
        DATABASE / 'manage.py', DATABASE / 'seed.sql',
        *WEB.joinpath('app').rglob('*.php'), *WEB.joinpath('config').glob('*.php'),
        *WEB.joinpath('routes').glob('*.php'), *WEB.joinpath('bootstrap').glob('*.php'),
        *WEB.joinpath('resources').rglob('*.blade.php'),
        *DATABASE.joinpath('migrations').glob('[0-9][0-9][0-9]_*.sql'),
    }
    return {str(file.relative_to(PROJECT)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in sorted(files) if file.is_file()}


def show_output(output: str) -> None:
    directory = PROJECT / '.local'
    directory.mkdir(exist_ok=True)
    (directory / 'web06-pruebas.log').write_text(output + '\n', encoding='utf-8')
    for line in output.splitlines():
        try:
            result = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(result, dict) and result.get('tool') == 'phpunit':
            summary = {key: result[key] for key in ('tool', 'result', 'tests', 'passed', 'failed', 'assertions', 'duration_ms') if key in result}
            if result.get('failures'):
                summary['failures'] = [{'test': row.get('test'), 'message': row.get('message', '')[:900]} for row in result['failures']]
            print(json.dumps(summary, ensure_ascii=False))
            return
    print(output[-5000:])


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
    role = db.sql('postgres', f"""SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)}
      AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls AND pg_has_role(oid,'banco_web','USAGE');""")
    if role != '1':
        raise IntegrationError('Las pruebas requieren la credencial web sin privilegios administrativos.')
    before, name = sources(), None
    try:
        name = db.create_temporary()
        prepare_database(db, name, php)
        baseline = db.content_fingerprints(name)
        db.sql('postgres', f'GRANT CONNECT ON DATABASE {sql_identifier(name)} TO {sql_identifier(username)};')
        env = {key: value for key, value in os.environ.items() if not key.startswith(('DB_', 'BANCO_TEST_', 'PG'))}
        env.update(APP_ENV='testing', BANCO_TEST_WEB02='1', BANCO_TEST_WEB06='1', BANCO_TEST_DATABASE=name,
                   BANCO_TEST_USERNAME=username, BANCO_TEST_PASSWORD=password, BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        result = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/ParticipacionTest.php', '--colors=never'],
                                cwd=WEB, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=360)
        output = (result.stdout + '\n' + result.stderr).strip()
        for value in (password, FIXTURE_PASSWORD, 'CambioSeguro-2026!'):
            output = output.replace(value, '[REDACTADO]')
        show_output(output)
        if result.returncode:
            raise IntegrationError('Falló la integración de participación; no se actualizó la evidencia.')
        summary = phpunit_summary(output)
        if db.content_fingerprints(name) != baseline:
            raise IntegrationError('Las pruebas dejaron cambios de negocio fuera de su transacción de aislamiento.')
        if sources() != before:
            raise IntegrationError('Las fuentes cambiaron durante la prueba; repetir cuando estén estables.')
        migration_count = int(db.sql(name, 'SELECT count(*) FROM control.migracion;'))
        version = db.verify_server()
    finally:
        if name is not None:
            db.drop_temporary(name)
    receipt = {
        'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto', 'bloque': 'WEB-06',
        'postgres': version, 'migraciones': migration_count, 'phpunit': summary,
        'base_de_trabajo_usada': False, 'temporal_eliminada': True,
        'credencial': 'Aplicación, sin superusuario ni lectura/DML general de tablas.',
        'aislamiento': 'Base temporal propia; cada caso HTTP revierte su transacción, con huellas de las21tablas comparadas.',
        'alcance': 'Participación propia, evaluación/preselección empresarial, resolución/asignación y ciclo administrativo, privacidad, validación, CSRF, versiones y rollback de auditoría/avisos.',
        'limites': 'HTTP Laravel y PostgreSQL real; la concurrencia y la revisión visual se acreditan por separado. Sin APIs ni bandeja general de avisos.',
        'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
    }
    target = WEB / 'evidencia/web06/regresion-postgres.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Integración WEB-06 correcta; temporal propia eliminada y evidencia guardada sin modificar recibos anteriores.')


if __name__ == '__main__':
    try:
        main()
    except IntegrationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(f'Integración WEB-06 interrumpida ({type(error).__name__}); sin evidencia nueva ni secretos mostrados.', file=sys.stderr)
        sys.exit(1)

"""WEB-07: avisos y reportes por HTTP sobre PostgreSQL temporal propio."""
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
from participacion import prepare_database as prepare_participacion

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
    """Conservar fixtures de perfiles, participación y el legado v1 de WEB-05."""
    require_fixture(db, name)
    prepare_participacion(db, name, php)
    fixture(db, name, php)


def fixture(db: Database, name: str, php: str) -> None:
    """Fixtures WEB-07: avisos y totales contrastables, solo en una temporal propia."""
    require_fixture(db, name)
    db.sql(name, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT -270010-n,'Profesor WEB07 '||n,'web07-profesor-'||n||'@example.invalid',hash_contrasena,'profesor'
        FROM banco.usuario CROSS JOIN generate_series(1,4) n WHERE id=-220004;
      INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo)
        SELECT id,'EMPLEADO_PRIVADO_WEB07_'||(-id),'Bases de datos WEB07','Experiencia WEB07',
          'docente-contacto-web07-'||(-id)||'@example.invalid' FROM banco.usuario WHERE id BETWEEN -270014 AND -270011;
      INSERT INTO banco.habilidad(id,nombre,tipo,descripcion) VALUES
        (-270101,'Programación WEB07','dura','Desarrollo de software'),
        (-270102,'Trabajo en equipo WEB07','blanda','Colaboración académica');
      INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,descripcion,evidencia) VALUES
        (-260008,-270101,'intermedio','Programación académica','EVIDENCIA_PRIVADA_WEB07'),
        (-260008,-270102,'intermedio','Trabajo colaborativo','EVIDENCIA_PRIVADA_WEB07');
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,
        justificacion,alcance,cupo_maximo_alumnos,modalidad,requisitos_academicos,duracion_estimada)
        SELECT -270200-n,CASE WHEN n<=21 THEN -220101 ELSE -220102 END,
          CASE WHEN n<=21 THEN -220005 ELSE -220006 END,
          'Proyecto WEB07 '||lpad(n::text,2,'0')||CASE WHEN n=26 THEN ' <script>alert("XSS_WEB07")</script>' ELSE '' END,
          'Descripción WEB07 '||n,'Problema académico','Objetivo del proyecto','Justificación de la empresa',
          'Alcance WEB07',3,'remota','Bases de datos','Doce semanas' FROM generate_series(1,26) n;
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,autor_usuario_id),-220001,
        CASE WHEN id=-270207 THEN 'rechazada' ELSE 'aprobada' END,'MOTIVO_ADMINISTRATIVO_PRIVADO_WEB07')
        FROM banco.proyecto WHERE id BETWEEN -270226 AND -270201 AND id NOT IN (-270206,-270208);
      SELECT banco.enviar_proyecto(-270206,-220005);
      DO $asignaciones$
      DECLARE x record;v_c bigint;v_s bigint;v_r jsonb:='{"tecnico":{"puntuacion":2,"comentario":"Técnica WEB07"},"blando":{"puntuacion":1,"comentario":"Comunicación WEB07"},"academico":{"puntuacion":2,"comentario":"Formación WEB07"}}';
      BEGIN
        FOR x IN SELECT * FROM (VALUES(-270201,-220003),(-270201,-260001),(-270202,-260002),
          (-270203,-260003),(-270204,-260004),(-270209,-260005)) t(proyecto,alumno)
        LOOP
          v_c:=banco.presentar_candidatura(x.proyecto,x.alumno);
          PERFORM banco.evaluar_candidatura(v_c,-220005,v_r,'COMENTARIO_PRIVADO_WEB07',true);
          PERFORM banco.preseleccionar_candidatura(v_c,-220005);
          PERFORM banco.resolver_candidatura(v_c,-220001,'aprobada','MOTIVO_ADMINISTRATIVO_PRIVADO_WEB07');
        END LOOP;
        FOR x IN SELECT * FROM (VALUES(-270201,-270011),(-270202,-270011),(-270203,-270012),
          (-270204,-270012),(-270209,-270013)) t(proyecto,profesor)
        LOOP
          v_s:=banco.solicitar_direccion(x.proyecto,x.profesor,'EXPERIENCIA_PRIVADA_WEB07','JUSTIFICACION_PRIVADA_WEB07');
          PERFORM banco.resolver_direccion(v_s,-220001,'aprobada','MOTIVO_ADMINISTRATIVO_PRIVADO_WEB07');
        END LOOP;
        PERFORM banco.iniciar_proyecto(-270201,-220001);
        PERFORM banco.iniciar_proyecto(-270203,-220001);
        PERFORM banco.finalizar_proyecto(-270203,-220001,'MOTIVO_CIERRE_PRIVADO_WEB07');
        PERFORM banco.iniciar_proyecto(-270204,-220001);
        PERFORM banco.retirar_director((SELECT id FROM banco.asignacion_direccion WHERE proyecto_id=-270204),-220001,'MOTIVO_RETIRO_PRIVADO_WEB07');
        PERFORM banco.cancelar_proyecto(-270205,-220001,'MOTIVO_CIERRE_PRIVADO_WEB07');
        PERFORM banco.cambiar_estado_cuenta(-220001,-270013,'inactiva','MOTIVO_CUENTA_PRIVADO_WEB07');
        v_c:=banco.presentar_candidatura(-270202,-260006);
        v_c:=banco.presentar_candidatura(-270226,-260006);
        v_c:=banco.presentar_candidatura(-270202,-260007);
        PERFORM banco.resolver_candidatura(v_c,-220001,'rechazada','MOTIVO_RECHAZO_PRIVADO_WEB07');
        v_c:=banco.presentar_candidatura(-270210,-220003);
        FOR n IN 1..22 LOOP
          PERFORM banco.evaluar_candidatura(v_c,-220005,v_r,'COMENTARIO_PRIVADO_WEB07_'||n,n%2=0);
        END LOOP;
        v_s:=banco.solicitar_direccion(-270211,-220004,'EXPERIENCIA_PRIVADA_WEB07','JUSTIFICACION_PRIVADA_WEB07');
        PERFORM banco.resolver_direccion(v_s,-220001,'rechazada','MOTIVO_RECHAZO_PRIVADO_WEB07');
        PERFORM banco.solicitar_direccion(-270226,-270014,'Experiencia WEB07','Justificación WEB07');
      END $asignaciones$;
      INSERT INTO banco.notificacion(id,destinatario_usuario_id,evento_id,mensaje,fecha)
        SELECT -270501,-220003,min(id),'<script>alert("AVISO_XSS_WEB07")</script>',clock_timestamp() FROM banco.evento_auditoria;
      COMMIT;""")


def sources() -> dict[str, str]:
    files = {
        Path(__file__).resolve(), WEB / 'tests/postgres.py', WEB / 'tests/acceso.py',
        WEB / 'tests/publicacion.py', WEB / 'tests/perfiles.py', WEB / 'tests/participacion.py', WEB / 'tests/PostgresTestCase.php',
        WEB / 'tests/Integration/AvisosReportesTest.php', WEB / 'phpunit.xml',
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
    (directory / 'web07-pruebas.log').write_text(output + '\n', encoding='utf-8')
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
        env.update(APP_ENV='testing', BANCO_TEST_WEB02='1', BANCO_TEST_WEB07='1', BANCO_TEST_DATABASE=name,
                   BANCO_TEST_USERNAME=username, BANCO_TEST_PASSWORD=password, BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        result = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/AvisosReportesTest.php', '--colors=never'],
                                cwd=WEB, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=360)
        output = (result.stdout + '\n' + result.stderr).strip()
        for value in (password, FIXTURE_PASSWORD, 'CambioSeguro-2026!'):
            output = output.replace(value, '[REDACTADO]')
        show_output(output)
        if result.returncode:
            raise IntegrationError('Falló la integración de avisos y reportes; no se actualizó la evidencia.')
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
        'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto', 'bloque': 'WEB-07',
        'postgres': version, 'migraciones': migration_count, 'phpunit': summary,
        'base_de_trabajo_usada': False, 'temporal_eliminada': True,
        'credencial': 'Aplicación, sin superusuario ni lectura/DML general de tablas.',
        'aislamiento': 'Base temporal propia; cada caso HTTP revierte su transacción, con huellas de las 21 tablas comparadas.',
        'alcance': 'Avisos individuales, lectura idempotente y CSRF, reportes administrativos con filtros/totales/paginación y recorrido integral con notificaciones.',
        'limites': 'HTTP Laravel y PostgreSQL real; la concurrencia y la revisión visual se acreditan por separado. Sin APIs, exportación o despliegue institucional.',
        'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
    }
    target = WEB / 'evidencia/web07/regresion-postgres.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Integración WEB-07 correcta; temporal propia eliminada y evidencia guardada sin modificar recibos anteriores.')


if __name__ == '__main__':
    try:
        main()
    except IntegrationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(f'Integración WEB-07 interrumpida ({type(error).__name__}); sin evidencia nueva ni secretos mostrados.', file=sys.stderr)
        sys.exit(1)

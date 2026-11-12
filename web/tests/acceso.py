"""HTTP, sesión y cuentas de WEB-02 contra PostgreSQL temporal propio.

La configuración de administración solo prepara y elimina el destino aislado.
Las peticiones Laravel utilizan exclusivamente la credencial de aplicación.
"""
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

WEB = Path(__file__).resolve().parents[1]
PROJECT = WEB.parent
DATABASE = PROJECT / 'database'
sys.path.insert(0, str(DATABASE))
from manage import Database, sql_identifier, sql_literal  # noqa: E402

FIXTURE_PASSWORD = 'PruebaSegura-2026!'


def show_output(output: str) -> None:
    """Conservar el diagnóstico privado sin volcar trazas enteras al informe."""
    directory = PROJECT / '.local'
    directory.mkdir(exist_ok=True)
    (directory / 'web02-pruebas.log').write_text(output + '\n', encoding='utf-8')
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
        Path(__file__).resolve(), WEB / 'tests/postgres.py',
        WEB / 'tests/PostgresTestCase.php', WEB / 'tests/Integration/AccesoCuentasTest.php',
        WEB / 'phpunit.xml', WEB / 'composer.json', WEB / 'composer.lock',
        WEB / 'package.json', WEB / 'package-lock.json',
        DATABASE / 'manage.py', DATABASE / 'seed.sql',
        *WEB.joinpath('app').rglob('*.php'), *WEB.joinpath('config').glob('*.php'),
        *WEB.joinpath('routes').glob('*.php'), *WEB.joinpath('bootstrap').glob('*.php'),
        *WEB.joinpath('resources').rglob('*.blade.php'),
        *DATABASE.joinpath('migrations').glob('[0-9][0-9][0-9]_*.sql'),
    }
    return {str(file.relative_to(PROJECT)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in sorted(files) if file.is_file()}


def fixture(db: Database, name: str, php: str) -> None:
    encoded = subprocess.run(
        [php, '-r', '$value=stream_get_contents(STDIN); echo password_hash($value,PASSWORD_BCRYPT,["cost"=>4]);'],
        input=FIXTURE_PASSWORD, text=True, encoding='utf-8', capture_output=True, check=True,
    ).stdout.strip()
    if not encoded.startswith('$2y$04$') or len(encoded) != 60:
        raise IntegrationError('PHP no produjo el hash de pruebas esperado.')
    users = [
        (-220001, 'Admin WEB02', 'web02-admin@example.invalid', 'administrador', 'activa', False),
        (-220002, 'Otro admin WEB02', 'web02-otro-admin@example.invalid', 'administrador', 'activa', False),
        (-220003, 'Alumno WEB02', 'web02-alumno@example.invalid', 'alumno', 'activa', False),
        (-220004, 'Profesor WEB02', 'web02-profesor@example.invalid', 'profesor', 'activa', False),
        (-220005, 'Representante WEB02', 'web02-empresa@example.invalid', 'empresa', 'activa', False),
        (-220006, 'Otro representante WEB02', 'web02-otra-empresa@example.invalid', 'empresa', 'activa', False),
        (-220007, 'Inactivo WEB02', 'web02-inactivo@example.invalid', 'alumno', 'inactiva', False),
        (-220008, 'Clave temporal WEB02', 'web02-temporal@example.invalid', 'alumno', 'activa', True),
        (-220009, 'Sin acceso WEB02', 'web02-demo@example.invalid', 'alumno', 'activa', False),
    ]
    rows = []
    for identifier, display, email, role, state, temporary in users:
        password = '!SIN-ACCESO-DEMO' if identifier == -220009 else encoded
        rows.append('(' + ','.join([str(identifier), sql_literal(display), sql_literal(email),
                    sql_literal(password), sql_literal(role), sql_literal(state),
                    'true' if temporary else 'false']) + ')')
    db.sql(name, '''BEGIN;
      SET CONSTRAINTS ALL DEFERRED;
      -- Los administradores de la semilla no tienen acceso real. La fixture
      -- los deja inactivos para comprobar el último administrador operativo.
      UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id>0 AND rol_principal='administrador';
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta,requiere_cambio_clave)
      VALUES ''' + ','.join(rows) + ''';
      INSERT INTO banco.empresa(id,razon_social) VALUES
        (-220101,'Empresa WEB02'),(-220102,'Otra empresa WEB02');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES
        (-220005,-220101),(-220006,-220102);
      COMMIT;''')


def main() -> None:
    started = time.monotonic()
    values = dotenv(WEB / '.env')
    password = values.get('DB_PASSWORD', '')
    username = values.get('DB_USERNAME', '')
    host = values.get('DB_HOST', '')
    port = values.get('DB_PORT', '')
    if not password or not username or username == 'proweb_admin':
        raise IntegrationError('Preparar primero la credencial propia de la aplicación.')
    if host not in ('127.0.0.1', 'localhost', '::1') or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise IntegrationError('Solo se permite una instancia PostgreSQL local explícita.')
    portable = PROJECT / '.local/tools/php/php.exe'
    php = os.environ.get('BANCO_PHP_BINARY') or (str(portable) if portable.is_file() else shutil.which('php'))
    if not php or not Path(php).is_file():
        raise IntegrationError('No se encontró el ejecutable PHP de la integración.')
    if not (WEB / 'vendor/bin/phpunit').is_file():
        raise IntegrationError('Instalar primero las dependencias PHP.')
    if (WEB / 'bootstrap/cache/config.php').exists():
        raise IntegrationError('Ejecutar antes artisan config:clear para aislar la configuración.')
    db = Database(DATABASE / '.local/connection.json')
    if str(db.config['port']) != port or db.config['host'] != host:
        raise IntegrationError('La web y las herramientas deben usar la misma instancia local.')
    role = db.sql('postgres', f'''SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)}
      AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls AND pg_has_role(oid,'banco_web','USAGE');''')
    if role != '1':
        raise IntegrationError('La conexión de pruebas no corresponde a la credencial web sin privilegios administrativos.')
    before = sources()
    name = None
    try:
        name = db.create_temporary()
        db.migrate(name)
        db.seed(name)
        fixture(db, name, php)
        db.sql('postgres', f'GRANT CONNECT ON DATABASE {sql_identifier(name)} TO {sql_identifier(username)};')
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('DB_', 'BANCO_TEST_', 'PG'))}
        env.update(APP_ENV='testing', BANCO_TEST_WEB02='1', BANCO_TEST_DATABASE=name,
                   BANCO_TEST_USERNAME=username, BANCO_TEST_PASSWORD=password,
                   BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        result = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/AccesoCuentasTest.php', '--colors=never'],
                                cwd=WEB, env=env, capture_output=True, text=True, encoding='utf-8',
                                errors='replace', timeout=240)
        output = (result.stdout + '\n' + result.stderr).strip()
        for value in (password, FIXTURE_PASSWORD, 'CambioSeguro-2026!'):
            output = output.replace(value, '[REDACTADO]')
        show_output(output)
        if result.returncode:
            raise IntegrationError('Falló la integración de acceso/cuentas; no se actualizó la evidencia.')
        summary = phpunit_summary(output)
        if sources() != before:
            raise IntegrationError('Las fuentes cambiaron durante la prueba; repetir cuando estén estables.')
        migration_count = int(db.sql(name, 'SELECT count(*) FROM control.migracion;'))
        version = db.verify_server()
    finally:
        if name is not None:
            db.drop_temporary(name)
    receipt = {
        'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto', 'bloque': 'WEB-02',
        'postgres': version, 'migraciones': migration_count, 'phpunit': summary,
        'base_de_trabajo_usada': False, 'temporal_eliminada': True,
        'credencial': 'Aplicación, sin superusuario ni lectura/DML general de tablas.',
        'aislamiento': 'Base temporal propia; cada caso HTTP revierte su transacción.',
        'alcance': 'Login/logout, normalización, invalidación y cambio de clave, CSRF real, límites de intentos, cuatro roles y gestión administrativa de cuentas.',
        'limites': 'HTTP de Laravel y PostgreSQL real; no sustituye la revisión de navegador ni el aprovisionamiento del primer administrador.',
        'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
    }
    target = WEB / 'evidencia/web02-postgres.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Integración WEB-02 correcta; temporal eliminada y evidencia guardada.')


if __name__ == '__main__':
    try:
        main()
    except IntegrationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(f'Integración WEB-02 interrumpida ({type(error).__name__}); sin evidencia nueva ni secretos mostrados.', file=sys.stderr)
        sys.exit(1)

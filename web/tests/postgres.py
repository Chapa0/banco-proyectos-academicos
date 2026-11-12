"""Integración PHP/PostgreSQL en una base temporal propia, con credencial web.

Ejecutar desde cualquier carpeta. La administración crea/migra/prepara y elimina
la temporal; PHPUnit consulta únicamente con la cuenta privada de web/.env.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

WEB = Path(__file__).resolve().parents[1]
PROJECT = WEB.parent
DATABASE = PROJECT / 'database'
sys.path.insert(0, str(DATABASE))
from manage import Database, sql_identifier, sql_literal  # noqa: E402


class IntegrationError(RuntimeError):
    """Mensaje de operación controlado que puede mostrarse sin secretos."""


def dotenv(path: Path) -> dict[str, str]:
    """Leer los valores locales necesarios, sin ejecutar ni imprimir el archivo."""
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*', line)
        if not match:
            continue
        key, value = match.groups()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = json.loads(value)
        elif len(value) >= 2 and value[0] == value[-1] == "'":
            value = value[1:-1]
        else:
            value = value.split(' #', 1)[0].rstrip()
        result[key] = value
    return result


def fingerprints() -> dict[str, str]:
    sources = [
        Path(__file__).resolve(), WEB / 'tests/Integration/PostgresConnectionTest.php',
        WEB / 'tests/TestCase.php', WEB / 'phpunit.xml', WEB / 'config/database.php',
        WEB / 'app/Services/ConexionPostgres.php', WEB / 'app/Models/Usuario.php',
        WEB / 'app/Console/Commands/ComprobarConexion.php', WEB / 'composer.lock',
        DATABASE / 'manage.py', DATABASE / 'seed.sql',
        *sorted((DATABASE / 'migrations').glob('[0-9][0-9][0-9]_*.sql')),
    ]
    return {str(path.relative_to(PROJECT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}


def phpunit_summary(output: str) -> dict:
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and value.get('tool') == 'phpunit':
            tests = value.get('tests', 0)
            if value.get('result') == 'passed' and tests > 0 and value.get('passed') == tests \
                    and value.get('assertions', 0) > 0 \
                    and not any(value.get(key, 0) for key in ('skipped', 'incomplete', 'risky', 'failures', 'errors')):
                return {'pruebas': tests, 'aserciones': value['assertions']}
            raise IntegrationError('El resultado de PHPUnit contiene fallos u omisiones.')
    match = re.search(r'OK \((\d+) tests?, (\d+) assertions?\)', output)
    if match and int(match[1]) > 0 and int(match[2]) > 0:
        return {'pruebas': int(match[1]), 'aserciones': int(match[2])}
    raise IntegrationError('La suite no acredita pruebas ejecutadas sin omisiones; no se actualizó la evidencia.')


def main() -> None:
    started = time.monotonic()
    values = dotenv(WEB / '.env')
    password = values.get('DB_PASSWORD', '')
    username = values.get('DB_USERNAME', '')
    host = values.get('DB_HOST', '')
    port = values.get('DB_PORT', '')
    if not password or not username or username == 'proweb_admin':
        raise IntegrationError('Configurar primero la credencial privada propia de la aplicación.')
    if host not in ('127.0.0.1', 'localhost', '::1') or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise IntegrationError('La integración solo permite PostgreSQL local y puerto explícito.')

    portable = PROJECT / '.local/tools/php/php.exe'
    php = os.environ.get('BANCO_PHP_BINARY') or (str(portable) if portable.is_file() else shutil.which('php'))
    if not php or not Path(php).is_file():
        raise IntegrationError('No se encontró PHP; configurar BANCO_PHP_BINARY o el ejecutable local.')
    if not (WEB / 'vendor/bin/phpunit').is_file():
        raise IntegrationError('Instalar primero las dependencias PHP de web/.')
    if (WEB / 'bootstrap/cache/config.php').exists():
        raise IntegrationError('Limpiar primero la configuración cacheada con artisan config:clear.')

    db = Database(DATABASE / '.local/connection.json')
    if str(db.config['port']) != port or db.config['host'] != host:
        raise IntegrationError('La administración y la web deben usar la misma instancia local de prueba.')
    role = db.sql('postgres', f"""SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)}
      AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls
      AND pg_has_role(oid,'banco_web','USAGE');""")
    if role != '1':
        raise IntegrationError('La credencial no corresponde al grupo mínimo de WEB-01.')

    before = fingerprints()
    name = None
    process = None
    try:
        name = db.create_temporary()
        db.migrate(name)
        db.seed(name)
        db.sql('postgres', f'GRANT CONNECT ON DATABASE {sql_identifier(name)} TO {sql_identifier(username)};')
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(('DB_', 'BANCO_TEST_', 'PG'))}
        env.update(APP_ENV='testing', BANCO_TEST_DATABASE=name, BANCO_TEST_USERNAME=username,
                   BANCO_TEST_PASSWORD=password, BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        process = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/PostgresConnectionTest.php', '--colors=never'],
                                 cwd=WEB, env=env, capture_output=True, text=True, encoding='utf-8',
                                 errors='replace', timeout=180)
        output = (process.stdout + '\n' + process.stderr).strip().replace(password, '[REDACTADO]')
        print(output)
        if process.returncode:
            raise IntegrationError('Falló la integración PHP/PostgreSQL; no se actualizó su evidencia.')
        summary = phpunit_summary(output)
        if fingerprints() != before:
            raise IntegrationError('Las fuentes cambiaron durante las pruebas; repetir con las fuentes estables.')
        version = db.verify_server()
        migration_count = int(db.sql(name, 'SELECT count(*) FROM control.migracion;'))
    finally:
        if name is not None:
            db.drop_temporary(name)

    php_version = subprocess.run([php, '--version'], capture_output=True, text=True,
                                 encoding='utf-8', errors='replace', check=True).stdout.splitlines()[0]
    result = {
        'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto',
        'postgres': version, 'php': php_version, 'suite': 'Integration', 'archivo': 'tests/Integration/PostgresConnectionTest.php',
        'migraciones': migration_count, 'base_de_trabajo_usada': False, 'temporal_eliminada': True,
        'credencial': 'Aplicación, miembro del grupo banco_web; no propietaria ni superusuario.',
        'resumen_phpunit': output, 'phpunit': summary,
        'alcance': 'PDO real, esquema/UTC/aislamiento, directorio mínimo, mapeo Usuario, permisos negativos y salida segura del comando. La autenticación y las cuentas se verifican por separado en WEB-02.',
        'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
    }
    destination = WEB / 'evidencia/postgres.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Integración correcta; temporal eliminada y evidencia guardada en web/evidencia/postgres.json.')


if __name__ == '__main__':
    try:
        main()
    except IntegrationError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        # Los detalles de subprocess ya se redactan. No volcar configuración,
        # entorno, trazas de conexión ni excepciones que puedan contener secretos.
        print(f'Integración PostgreSQL interrumpida ({type(error).__name__}); no se actualizó la evidencia.', file=sys.stderr)
        sys.exit(1)

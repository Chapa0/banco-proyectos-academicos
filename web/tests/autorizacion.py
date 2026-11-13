"""Auditoría de permisos por recurso en una PostgreSQL temporal propia con DEMO-01.

Uso desde web/: py -3.12 tests/autorizacion.py
Nunca usa como destino de pruebas la base de trabajo ni la demostración pública.
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
sys.path.insert(0, str(PROJECT / 'database'))
from cargar_demo import DEMO_CLAVE, cargar  # noqa: E402
from manage import BASE, Database, sql_identifier, sql_literal  # noqa: E402


def sources() -> dict[str, str]:
    files = {Path(__file__).resolve(), PROJECT / 'database/demo.sql', WEB / 'tests/PostgresTestCase.php',
             WEB / 'tests/Integration/AutorizacionRecursosTest.php', WEB / 'tests/Feature/AlmacenamientoPrivadoTest.php',
             WEB / 'composer.lock', WEB / 'phpunit.xml',
             *WEB.joinpath('app').rglob('*.php'), *WEB.joinpath('config').glob('*.php'),
             *WEB.joinpath('routes').glob('*.php'), *WEB.joinpath('bootstrap').glob('*.php'),
             *PROJECT.joinpath('database/migrations').glob('*.sql')}
    return {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}


def main() -> None:
    started = time.monotonic()
    values = dotenv(WEB / '.env')
    username, password = values.get('DB_USERNAME', ''), values.get('DB_PASSWORD', '')
    host, port = values.get('DB_HOST', ''), values.get('DB_PORT', '')
    if not password or not username or username == 'proweb_admin' or host not in ('127.0.0.1', 'localhost', '::1'):
        raise IntegrationError('Falta una credencial web local sin privilegios administrativos.')
    php_portable = PROJECT / '.local/tools/php/php.exe'
    php = os.environ.get('BANCO_PHP_BINARY') or (str(php_portable) if php_portable.is_file() else shutil.which('php'))
    if not php or (WEB / 'bootstrap/cache/config.php').exists():
        raise IntegrationError('Preparar PHP y dependencias y quitar la configuración cacheada antes de probar.')
    db = Database(BASE / '.local/connection.json')
    db.verify_server()
    if str(db.config['port']) != port or db.config['host'] != host:
        raise IntegrationError('Las herramientas y la aplicación deben usar la misma instancia local.')
    if db.sql('postgres', f"""SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)}
        AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
        AND NOT rolreplication AND NOT rolbypassrls AND pg_has_role(oid,'banco_web','USAGE');""") != '1':
        raise IntegrationError('La credencial de pruebas debe ser la de aplicación con permisos mínimos.')

    before = sources()
    name = None
    try:
        name = db.create_temporary()
        db.migrate(name)
        demo = cargar(db, name, php)
        baseline = db.content_fingerprints(name)
        attachments_sql = 'SELECT json_build_object(\'documentos\',(SELECT count(*) FROM adjunto.documento),\'imagenes\',(SELECT count(*) FROM adjunto.imagen));'
        baseline_files = db.sql(name, attachments_sql)
        db.sql('postgres', f'GRANT CONNECT ON DATABASE {sql_identifier(name)} TO {sql_identifier(username)};')
        env = {k: v for k, v in os.environ.items() if not k.startswith(('DB_', 'BANCO_TEST_', 'PG'))}
        env.update(APP_ENV='testing', BANCO_TEST_WEB02='1', BANCO_TEST_AUTORIZACION='1',
                   BANCO_TEST_DATABASE=name, BANCO_TEST_USERNAME=username, BANCO_TEST_PASSWORD=password,
                   BANCO_TEST_HOST=host, BANCO_TEST_PORT=port)
        result = subprocess.run([php, 'vendor/bin/phpunit', 'tests/Integration/AutorizacionRecursosTest.php', '--colors=never'],
                                cwd=WEB, env=env, capture_output=True, encoding='utf-8', errors='replace', timeout=480)
        output = result.stdout + '\n' + result.stderr
        for secret in (password, DEMO_CLAVE):
            output = output.replace(secret, '[REDACTADO]')
        (PROJECT / '.local/autorizacion-pruebas.log').write_text(output, encoding='utf-8')
        print(output.strip(), flush=True)
        if result.returncode:
            raise IntegrationError('Falló la comprobación de permisos; no se publicó evidencia de éxito.')
        summary = phpunit_summary(output)
        if db.content_fingerprints(name) != baseline or db.sql(name, attachments_sql) != baseline_files:
            raise IntegrationError('Las pruebas dejaron cambios fuera de sus transacciones.')
        if sources() != before:
            raise IntegrationError('Las fuentes cambiaron durante la prueba; repetir con fuentes estables.')
        routes_run = subprocess.run([php, 'artisan', 'route:list', '--json'], cwd=WEB, env=env,
                                    capture_output=True, encoding='utf-8', errors='replace', timeout=30)
        if routes_run.returncode:
            raise IntegrationError('No se pudo inventariar las rutas verificadas.')
        routes = json.loads(routes_run.stdout)
    finally:
        if name is not None:
            db.drop_temporary(name)

    receipt = {'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'correcto',
               'phpunit': summary, 'demo': demo, 'base_temporal_eliminada': True,
               'bases_de_trabajo_y_publica_usadas': False,
               'alcance': 'Rutas sin sesión, roles, intercambio de IDs, campos ocultos, verbos simulados, relaciones proyecto/revisión/asignación, lectura y escrituras denegadas sin mutación del recurso.',
               'rutas': [{'metodo': r['method'], 'uri': r['uri'], 'nombre': r['name']} for r in routes],
               'sha256_fuentes': before, 'segundos': round(time.monotonic() - started, 2),
               'limites': 'HTTP Laravel y PostgreSQL real en temporal propia; no es prueba de carga, navegador ni auditoría de dependencias completa.'}
    (WEB / 'evidencia/autorizacion-recursos.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'resultado': 'correcto', **summary, 'rutas': len(routes), 'temporal_eliminada': True}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except (IntegrationError, ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f'Error de verificación: {type(error).__name__}. Revisar .local/autorizacion-pruebas.log.', file=sys.stderr)
        sys.exit(1)

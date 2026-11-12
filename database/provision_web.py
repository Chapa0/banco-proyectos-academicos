"""Preparar credencial web local sin guardar secretos en SQL versionado."""
from __future__ import annotations

import base64
import hashlib
from pathlib import Path
import re
import secrets
import sys

from manage import BASE, Database, sql_identifier, sql_literal


def exigir_instalacion_web(database: Database) -> None:
    """Un rol es global; la migración debe estar aplicada en esta base concreta."""
    version = '019_conexion_web.sql'
    expected = hashlib.sha256((BASE / 'migrations' / version).read_bytes()).hexdigest()
    if database.sql(database.target, "SELECT to_regclass('control.migracion') IS NOT NULL;") != 't':
        raise RuntimeError('Aplicar primero la migración 019 en la base destino.')
    applied = database.sql(database.target,
        f'SELECT sha256 FROM control.migracion WHERE version={sql_literal(version)};')
    if applied != expected:
        raise RuntimeError('Aplicar primero la migración 019 con las fuentes actuales en la base destino.')
    if database.sql(database.target, "SELECT count(*) FROM pg_roles WHERE rolname='banco_web';") != '1':
        raise RuntimeError('La instalación requiere el grupo banco_web de la migración 019.')


def provision() -> None:
    database = Database(BASE / '.local/connection.json')
    exigir_instalacion_web(database)
    web = BASE.parent / 'web'
    environment = web / '.env'
    if environment.exists() and re.search(r'^DB_PASSWORD=.+$', environment.read_text(encoding='utf-8'), re.M):
        print('Se conserva la configuración web privada existente; no se rotaron credenciales.')
        return
    username = 'proweb_web'
    if database.sql(database.target, f'SELECT count(*) FROM pg_roles WHERE rolname={sql_literal(username)};') != '0':
        # No alterar una cuenta previa cuya contraseña o propietario desconocemos.
        username += '_' + secrets.token_hex(4)
    password = secrets.token_urlsafe(36)
    database.sql(database.target, f'''BEGIN;
      SET LOCAL password_encryption='scram-sha-256';
      CREATE ROLE {sql_identifier(username)} LOGIN INHERIT NOSUPERUSER NOCREATEDB
        NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD {sql_literal(password)};
      GRANT banco_web TO {sql_identifier(username)};
      COMMIT;''')
    text = (web / '.env.example').read_text(encoding='utf-8')
    settings = {
        'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
        'DB_HOST': database.config['host'],
        'DB_PORT': str(database.config['port']),
        'DB_DATABASE': database.target,
        'DB_USERNAME': username,
        'DB_PASSWORD': password,
    }
    for key, value in settings.items():
        text = re.sub(r'^' + key + r'=.*$', key + '=' + value, text, flags=re.M)
    environment.write_text(text, encoding='utf-8')
    print('Credencial local propia y clave de aplicación preparadas en web/.env, sin mostrarlas.')


if __name__ == '__main__':
    try:
        provision()
    except Exception:
        print('No se pudo preparar la configuración web. Revisa la instancia local y las instrucciones; no se mostraron secretos.', file=sys.stderr)
        sys.exit(1)

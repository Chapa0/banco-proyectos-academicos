"""Primer acceso administrativo local, separado de las peticiones web.

La contraseña solo se entrega en un archivo privado. No convierte las cuentas
ficticias ni atribuye la operación inicial a una persona que no ha iniciado sesión.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

from manage import BASE, Database, sql_literal

PRIVADO = (BASE.parent / '.local').resolve()
CABECERA = '# banco-bootstrap-v1 '


class BootstrapError(RuntimeError):
    def __init__(self, mensaje: str, recuperacion: Path | None = None):
        super().__init__(mensaje)
        self.recuperacion = recuperacion


def exigir_instalacion(database: Database) -> None:
    version = '020_acceso_web.sql'
    expected = hashlib.sha256((BASE / 'migrations' / version).read_bytes()).hexdigest()
    if database.sql(database.target, "SELECT to_regclass('control.migracion') IS NOT NULL;") != 't':
        raise BootstrapError('Aplicar primero la migración 020 en la base destino.')
    applied = database.sql(database.target,
        f'SELECT sha256 FROM control.migracion WHERE version={sql_literal(version)};')
    if applied != expected:
        raise BootstrapError('Aplicar primero la migración 020 con las fuentes actuales en la base destino.')


def _marca_coherente(database: Database, datos: dict) -> bool:
    if datos.get('base') != database.target or datos.get('host') != database.config['host'] \
            or str(datos.get('puerto')) != str(database.config['port']) \
            or not re.fullmatch(r'[0-9a-f]{32}', str(datos.get('referencia', ''))):
        return False
    return database.sql(database.target, f'''SELECT count(*) FROM banco.evento_auditoria e
      JOIN banco.usuario u ON e.registro_afectado=u.id::text
      WHERE e.operacion='crear_admin_inicial' AND e.entidad_afectada='usuario'
        AND e.origen='sistema' AND e.actor_usuario_id IS NULL
        AND e.resultado::jsonb->>'bootstrap_id'={sql_literal(datos['referencia'])}
        AND u.rol_principal='administrador'
        AND u.correo_normalizado={sql_literal(str(datos.get('correo', '')))};''') == '1'


def _hash_clave(php: Path, clave: str) -> str:
    code = "$clave=stream_get_contents(STDIN);echo password_hash($clave,PASSWORD_BCRYPT,['cost'=>12]);"
    result = subprocess.run([str(php), '-r', code], input=clave, encoding='utf-8',
        capture_output=True, timeout=30)
    digest = result.stdout.strip()
    if result.returncode or not re.fullmatch(r'\$2y\$12\$[./A-Za-z0-9]{53}', digest):
        raise BootstrapError('No se pudo preparar el hash con el PHP configurado.')
    return digest


def crear(database: Database, archivo: Path, nombre: str, correo: str, php: Path) -> bool:
    """Crear una vez; False conserva el archivo coherente sin rotar la cuenta.

    El llamador de las pruebas debe proporcionar una Database temporal propia.
    Solo main usa el destino local habitual de administración.
    """
    temporal: Path | None = None
    confirmado: bool | None = False
    datos: dict = {}
    try:
        exigir_instalacion(database)
        archivo = archivo.resolve()
        if not archivo.is_relative_to(PRIVADO):
            raise BootstrapError('El archivo de acceso debe permanecer dentro de la carpeta privada del proyecto.')
        if archivo.exists():
            primera = archivo.read_text(encoding='utf-8').splitlines()[0]
            if not primera.startswith(CABECERA) or not _marca_coherente(database, json.loads(primera[len(CABECERA):])):
                raise BootstrapError('El archivo existente no corresponde al acceso inicial de esta base; no se modificó.')
            return False
        nombre = nombre.strip()
        correo = correo.strip().lower()
        if not nombre or len(nombre) > 150 or any(c in nombre for c in '\r\n\x00') \
                or len(correo) > 254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', correo):
            raise BootstrapError('Indicar nombre y correo válidos para el acceso inicial.')
        if not php.is_file():
            raise BootstrapError('No se encontró el ejecutable PHP configurado.')

        clave = secrets.token_urlsafe(24)
        digest = _hash_clave(php, clave)
        datos = {'base': database.target, 'host': database.config['host'],
            'puerto': database.config['port'], 'correo': correo, 'referencia': secrets.token_hex(16)}
        contenido = CABECERA + json.dumps(datos, ensure_ascii=False, separators=(',', ':')) + '\n\n' + \
            'Primer acceso al banco de proyectos\n' + \
            'URL: http://127.0.0.1:8000/login\n' + \
            f'Correo: {correo}\nContraseña temporal: {clave}\n\n' + \
            'Debes cambiar la contraseña al iniciar sesión. No compartas este archivo.\n'
        archivo.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', prefix='.primer-acceso-',
                suffix='.tmp', dir=archivo.parent, delete=False) as handle:
            temporal = Path(handle.name).resolve()
            if temporal.parent != archivo.parent or not temporal.name.startswith('.primer-acceso-'):
                raise BootstrapError('El archivo auxiliar quedó fuera del destino privado esperado.')
            os.chmod(temporal, 0o600)
            handle.write(contenido)
            handle.flush()
            os.fsync(handle.fileno())

        try:
            database.sql(database.target, rf'''BEGIN;
              SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
              SELECT pg_advisory_xact_lock(7162026,2017);
              DO $bootstrap$ BEGIN
                IF EXISTS(SELECT 1 FROM banco.evento_auditoria WHERE operacion='crear_admin_inicial')
                  OR EXISTS(SELECT 1 FROM banco.usuario WHERE rol_principal='administrador'
                    AND estado_cuenta='activa'
                    AND hash_contrasena ~ '^\$2[aby]\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{{53}}$') THEN
                  RAISE EXCEPTION 'El acceso administrativo inicial ya fue preparado' USING ERRCODE='55000';
                END IF;
              END $bootstrap$;
              WITH nueva AS (
                INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,
                  rol_principal,estado_cuenta,requiere_cambio_clave)
                VALUES({sql_literal(nombre)},{sql_literal(correo)},{sql_literal(digest)},
                  'administrador','activa',true) RETURNING id
              )
              INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
                registro_afectado,transicion,resultado)
              SELECT NULL,'sistema','crear_admin_inicial','usuario',id::text,
                'sin cuenta -> activa',jsonb_build_object('bootstrap_id',{sql_literal(datos['referencia'])},
                  'requiere_cambio_clave',true)::text FROM nueva;
              WITH demo AS (
                UPDATE banco.usuario SET estado_cuenta='inactiva'
                WHERE correo_normalizado='demo-admin@example.invalid'
                  AND hash_contrasena='!SIN-ACCESO-DEMO' AND rol_principal='administrador'
                  AND estado_cuenta='activa' RETURNING id
              )
              INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
                registro_afectado,transicion,resultado)
              SELECT NULL,'sistema','desactivar_admin_demo','usuario',id::text,
                'activa -> inactiva',jsonb_build_object('motivo',
                  'Se preparó el acceso administrativo inicial; la cuenta ficticia conserva su historial.')::text
              FROM demo;
              COMMIT;''')
            confirmado = True
        except Exception:
            # Una pérdida de respuesta no acredita que COMMIT haya fallado.
            # Consultar la marca evita descartar un acceso ya creado.
            try:
                confirmado = _marca_coherente(database, datos)
            except Exception:
                confirmado = None
            if confirmado is not True:
                raise BootstrapError('No se pudo preparar el acceso inicial; revisa la instalación y las cuentas existentes.') from None

        if archivo.exists():
            raise BootstrapError('El destino privado apareció durante la operación; se conservó el auxiliar para recuperación.')
        # Publicación atómica sin sobrescribir archivos ajenos, también en Unix.
        os.link(temporal, archivo)
        temporal.unlink()
        temporal = None
        return True
    except Exception as error:
        if temporal is not None and temporal.exists():
            if confirmado is False:
                temporal.unlink()
            else:
                raise BootstrapError('No se pudo publicar el archivo final. Se conservó un auxiliar privado para recuperar el acceso.', temporal) from None
        if isinstance(error, BootstrapError):
            raise error from None
        raise BootstrapError('No se pudo preparar el acceso administrativo; no se mostraron secretos.') from None


def main() -> int:
    parser = argparse.ArgumentParser(description='Preparar una vez el primer acceso administrativo local.')
    parser.add_argument('--nombre', default='Administrador')
    parser.add_argument('--correo', default='admin@banco.local')
    args = parser.parse_args()
    portable = PRIVADO / 'tools/php/php.exe'
    php = portable if portable.is_file() else Path(shutil.which('php') or '')
    archivo = PRIVADO / 'primer-acceso-web.txt'
    try:
        creado = crear(Database(BASE / '.local/connection.json'), archivo, args.nombre, args.correo, php)
        print('Acceso administrativo preparado.' if creado else 'Se conserva el acceso inicial; no se restableció la cuenta.')
        print(f'Archivo privado: {archivo}')
        return 0
    except BootstrapError as error:
        print(str(error), file=sys.stderr)
        if error.recuperacion is not None:
            print(f'Auxiliar privado: {error.recuperacion}', file=sys.stderr)
        return 1
    except Exception:
        print('No se pudo preparar el acceso administrativo; no se mostraron secretos.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

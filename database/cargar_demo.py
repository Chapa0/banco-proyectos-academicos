"""Cargar los datos de demostración (DEMO-01) en la base de trabajo.

Uso: py -3.12 database/cargar_demo.py

Antes de cargar hace un respaldo en database/.local/backups. Las cuentas son ficticias
(dominio reservado demo.test) y comparten la contraseña DEMO_CLAVE, documentada en
database/README.md. Si la demostración ya está cargada no hace nada.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

from manage import BASE, Database, sql_literal

DEMO_CLAVE = 'Demo-Banco-2026'


def hash_clave(php: str, clave: str = DEMO_CLAVE) -> str:
    code = "$c=stream_get_contents(STDIN);echo password_hash($c,PASSWORD_BCRYPT,['cost'=>12]);"
    result = subprocess.run([php, '-r', code], input=clave, encoding='utf-8', capture_output=True, timeout=30)
    digest = result.stdout.strip()
    if result.returncode or not re.fullmatch(r'\$2y\$12\$[./A-Za-z0-9]{53}', digest):
        raise RuntimeError('No se pudo generar el hash de la contraseña con PHP.')
    return digest


def php_disponible() -> str:
    portable = BASE.parent / '.local/tools/php/php.exe'
    php = str(portable) if portable.is_file() else shutil.which('php')
    if not php:
        raise RuntimeError('No se encontró PHP para generar el hash de la contraseña.')
    return php


def cargada(db: Database, database: str) -> bool:
    return db.sql(database, "SELECT count(*) FROM banco.usuario WHERE correo_normalizado LIKE '%@demo.test';") != '0'


def cargar(db: Database, database: str, php: str) -> dict:
    script = (BASE / 'demo.sql').read_text(encoding='utf-8-sig')
    db.sql(database, script.replace('__HASH_DEMO__', sql_literal(hash_clave(php))), timeout=180)
    return json.loads(db.sql(database, """SELECT json_build_object(
        'cuentas',(SELECT count(*) FROM banco.usuario WHERE correo_normalizado LIKE '%@demo.test'),
        'empresas',(SELECT count(*) FROM banco.empresa e JOIN banco.representacion_empresa r ON r.empresa_id=e.id
                    JOIN banco.usuario u ON u.id=r.usuario_id WHERE u.correo_normalizado LIKE '%@demo.test'),
        'proyectos',(SELECT json_object_agg(estado,n) FROM (SELECT p.estado,count(*) n FROM banco.proyecto p
                    JOIN banco.usuario u ON u.id=p.autor_usuario_id WHERE u.correo_normalizado LIKE '%@demo.test' GROUP BY 1) x),
        'candidaturas',(SELECT json_object_agg(estado,n) FROM (SELECT c.estado,count(*) n FROM banco.candidatura c
                    JOIN banco.usuario u ON u.id=c.alumno_id WHERE u.correo_normalizado LIKE '%@demo.test' GROUP BY 1) x),
        'avisos',(SELECT count(*) FROM banco.notificacion n JOIN banco.usuario u ON u.id=n.destinatario_usuario_id
                    WHERE u.correo_normalizado LIKE '%@demo.test'));"""))


def main() -> None:
    db = Database(BASE / '.local/connection.json')
    db.verify_server()
    if cargada(db, db.target):
        print('La demostración ya está cargada; no se hizo ningún cambio.')
        return
    php = php_disponible()
    respaldo = BASE / '.local/backups' / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S') + '-antes-demo.dump')
    db.backup(db.target, respaldo)
    print(f'Respaldo previo: {respaldo}')
    print(json.dumps(cargar(db, db.target, php), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)

"""Preparar una demostración pública independiente, sin reiniciar datos existentes.

Uso: py -3.12 database/preparar_demo_publica.py
La configuración de conexión y la clave independientes quedan fuera de Git.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys

from cargar_demo import cargar, cargada, php_disponible
from manage import BASE, Database

DESTINO = "banco_pruebas_publicas"
RUNTIME = BASE.parent / ".local/pruebas-publicas"


def main() -> None:
    db = Database(BASE / ".local/connection.json")
    db.verify_server()
    if db.target == DESTINO:
        raise ValueError("La configuración de trabajo debe conservar su base original.")

    RUNTIME.mkdir(parents=True, exist_ok=True)
    db.target = DESTINO
    db.ensure_target()
    migraciones = db.migrate(DESTINO).splitlines()
    if not cargada(db, DESTINO):
        cargar(db, DESTINO, php_disponible())

    # Una base con cuentas ajenas requiere revisión: nunca publicarlas por accidente.
    ajenas = db.sql(DESTINO, "SELECT count(*) FROM banco.usuario WHERE correo_normalizado NOT LIKE '%@demo.test';")
    if ajenas != "0":
        raise ValueError("La base pública contiene cuentas ajenas a la demostración; no se inicia el servicio.")

    entorno = RUNTIME / "entorno.json"
    if not entorno.exists():
        clave = "base64:" + base64.b64encode(os.urandom(32)).decode("ascii")
        entorno.write_text(json.dumps({"APP_KEY": clave}), encoding="utf-8")

    config = dict(db.config, database=DESTINO)
    (RUNTIME / "connection.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
    for carpeta in ("app/private", "app/public", "framework/cache/data", "framework/cache/locks",
                    "framework/sessions", "framework/views", "logs"):
        (RUNTIME / "storage" / carpeta).mkdir(parents=True, exist_ok=True)

    resumen = json.loads(db.sql(DESTINO, """SELECT json_build_object(
        'cuentas', (SELECT count(*) FROM banco.usuario),
        'empresas', (SELECT count(*) FROM banco.empresa),
        'habilidades', (SELECT count(*) FROM banco.habilidad),
        'proyectos', (SELECT count(*) FROM banco.proyecto),
        'candidaturas', (SELECT count(*) FROM banco.candidatura),
        'direcciones', (SELECT count(*) FROM banco.solicitud_direccion),
        'avisos', (SELECT count(*) FROM banco.notificacion));"""))
    print(json.dumps({"base": DESTINO, "migraciones": len(migraciones), **resumen}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)

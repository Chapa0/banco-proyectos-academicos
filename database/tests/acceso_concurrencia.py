"""WEB-02: cambios de acceso y formularios obsoletos con espera real."""
from __future__ import annotations

import importlib.util
from pathlib import Path

HASH = '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'


def run(db, database):
    spec = importlib.util.spec_from_file_location('concurrencia_acceso', Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-201001,'Admin acceso concurrente','acc-conc-admin@example.invalid','!SIN-ACCESO','administrador'),
        (-201002,'Alumno clave concurrente','acc-conc-clave@example.invalid','!SIN-ACCESO','alumno'),
        (-201003,'Alumno edición concurrente','acc-conc-edit@example.invalid','!SIN-ACCESO','alumno'),
        (-201004,'Representante concurrente','acc-conc-rep@example.invalid','!SIN-ACCESO','empresa');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-201010,'Empresa de acceso concurrente');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-201004,-201010);
      COMMIT;""")
    cases = {}
    cases['restablecer_clave_contra_inicio_con_version_anterior'] = concurrent.race(db, database,
        f"SET LOCAL ROLE banco_web;SELECT banco.web_restablecer_clave(-201001,-201002,'{HASH}','Reset concurrente',1);",
        "SET LOCAL ROLE banco_web;SELECT banco.web_registrar_acceso(-201002,1,'inicio_sesion');", '40001')
    if db.sql(database, "SELECT count(*) FROM banco.evento_auditoria WHERE actor_usuario_id=-201002 AND operacion='inicio_sesion';") != '0':
        raise AssertionError('Una versión de acceso antigua registró un inicio después de esperar al reset.')
    cases['ediciones_simultaneas_con_misma_version'] = concurrent.race(db, database,
        "SET LOCAL ROLE banco_web;SELECT banco.web_editar_cuenta(-201001,-201003,'Primera edición','acc-conc-edit@example.invalid','Primera',1);",
        "SET LOCAL ROLE banco_web;SELECT banco.web_editar_cuenta(-201001,-201003,'Edición obsoleta','acc-conc-edit@example.invalid','Segunda',1);", '40001')
    if db.sql(database, "SELECT nombre||':'||version_acceso FROM banco.usuario WHERE id=-201003;") != 'Primera edición:2':
        raise AssertionError('El formulario obsoleto sobrescribió la primera edición de nombre.')
    cases['relevos_simultaneos_del_mismo_representante'] = concurrent.race(db, database,
        f"SET LOCAL ROLE banco_web;SELECT banco.web_relevar_representante(-201001,-201010,'Primer relevo','acc-conc-relevo@example.invalid','{HASH}','Primero',-201004);",
        f"SET LOCAL ROLE banco_web;SELECT banco.web_relevar_representante(-201001,-201010,'Relevo obsoleto','acc-conc-obsoleto@example.invalid','{HASH}','Segundo',-201004);", '40001')
    if db.sql(database, "SELECT count(*) FROM banco.representacion_empresa WHERE empresa_id=-201010 AND vigente;") != '1' \
        or db.sql(database, "SELECT count(*) FROM banco.usuario WHERE correo_normalizado='acc-conc-obsoleto@example.invalid';") != '0':
        raise AssertionError('El relevo obsoleto alteró la representación o dejó otra cuenta creada.')
    return {'concurrencia': cases,
            'version_acceso': 'Los cambios de acceso y de nombre incrementan versión; una versión anterior no inicia sesión ni sobrescribe una cuenta.',
            'relevo': 'CAS del representante exacto bajo el bloqueo empresarial; segundo formulario sin efectos.',
            'limite': 'Credencial de servidor banco_web; la identidad de persona sigue siendo responsabilidad de sesión Laravel.'}

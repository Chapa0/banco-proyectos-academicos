"""WEB-05: altas/ediciones propias, identificadores y lectura durante cierre.

Cada carrera usa dos conexiones reales y acredita la espera de un bloqueo.
Los actores son ficticios y solo se crean en la temporal del ejecutor.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def run(db, database):
    spec = importlib.util.spec_from_file_location('concurrencia_perfil_web', Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-221001,'Admin perfiles concurrentes','perfil-conc-admin@example.invalid','!SIN-ACCESO','administrador'),
        (-221002,'Rep perfiles concurrentes','perfil-conc-rep@example.invalid','!SIN-ACCESO','empresa'),
        (-221003,'Alumno concurrente A','perfil-conc-a@example.invalid','!SIN-ACCESO','alumno'),
        (-221004,'Profesor concurrente A','perfil-conc-p@example.invalid','!SIN-ACCESO','profesor'),
        (-221005,'Alumno concurrente B','perfil-conc-b@example.invalid','!SIN-ACCESO','alumno'),
        (-221006,'Alumno concurrente C','perfil-conc-c@example.invalid','!SIN-ACCESO','alumno'),
        (-221007,'Profesor concurrente B','perfil-conc-pb@example.invalid','!SIN-ACCESO','profesor'),
        (-221008,'Profesor concurrente C','perfil-conc-pc@example.invalid','!SIN-ACCESO','profesor');
      INSERT INTO banco.habilidad(id,nombre,tipo) VALUES(-221021,'Skill perfil concurrente','dura');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-221011,'Empresa perfiles concurrentes');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-221002,-221011);
      COMMIT;""")

    def literal(value):
        return "'" + value.replace("'", "''") + "'"

    def payload(data):
        return literal(json.dumps(data, ensure_ascii=False)) + '::jsonb'

    def version(actor):
        return literal(db.sql(database, f'SET ROLE banco_web;SELECT banco.web_obtener_perfil_propio({actor})->>\'version\';'))

    def save(actor, data, token):
        return f'SET LOCAL ROLE banco_web;SELECT banco.web_guardar_perfil_propio({actor},{payload(data)},{token});'

    cases = {}
    token = version(-221003)
    cases['alta_alumno_contra_alta_misma_version'] = concurrent.race(db, database,
        save(-221003, {'matricula': 'CONC-WEB05-A'}, token),
        save(-221003, {'matricula': 'CONC-WEB05-OBSOLETA'}, token), '40001')
    token = version(-221003)
    cases['edicion_alumno_habilidades_contra_edicion'] = concurrent.race(db, database,
        save(-221003, {'matricula': 'CONC-WEB05-A', 'carrera': 'Primera edición',
            'habilidades': [{'habilidad_id': -221021, 'descripcion': 'Versión conservada'}]}, token),
        save(-221003, {'matricula': 'CONC-WEB05-A', 'carrera': 'Edición obsoleta', 'habilidades': []}, token), '40001')
    if db.sql(database, "SELECT carrera FROM banco.alumno WHERE usuario_id=-221003;") != 'Primera edición' \
        or db.sql(database, 'SELECT count(*) FROM banco.alumno_habilidad WHERE alumno_id=-221003;') != '1' \
        or db.sql(database, "SELECT count(*) FROM banco.evento_auditoria WHERE operacion='guardar_perfil' AND registro_afectado='-221003';") != '2':
        raise AssertionError('La edición obsoleta alteró perfil, habilidades o auditoría.')

    token = version(-221004)
    cases['alta_profesor_contra_alta_misma_version'] = concurrent.race(db, database,
        save(-221004, {'numero_empleado': 'CONC-WEB05-P'}, token),
        save(-221004, {'numero_empleado': 'CONC-WEB05-OBSOLETO'}, token), '40001')
    token = version(-221004)
    cases['edicion_profesor_contra_edicion'] = concurrent.race(db, database,
        save(-221004, {'numero_empleado': 'CONC-WEB05-P', 'especialidad': 'Especialidad conservada'}, token),
        save(-221004, {'numero_empleado': 'CONC-WEB05-P', 'especialidad': 'Especialidad obsoleta'}, token), '40001')
    if db.sql(database, "SELECT especialidad FROM banco.profesor WHERE usuario_id=-221004;") != 'Especialidad conservada':
        raise AssertionError('La edición obsoleta sobrescribió al profesor.')

    cases['matricula_unica_entre_titulares'] = concurrent.race(db, database,
        save(-221005, {'matricula': 'CONC-WEB05-UNICA'}, version(-221005)),
        save(-221006, {'matricula': 'CONC-WEB05-UNICA'}, version(-221006)), '23505')
    cases['numero_empleado_unico_entre_titulares'] = concurrent.race(db, database,
        save(-221007, {'numero_empleado': 'CONC-WEB05-NUMERO'}, version(-221007)),
        save(-221008, {'numero_empleado': 'CONC-WEB05-NUMERO'}, version(-221008)), '23505')
    if db.sql(database, 'SELECT count(*) FROM banco.alumno WHERE usuario_id=-221006;') != '0' \
        or db.sql(database, 'SELECT count(*) FROM banco.profesor WHERE usuario_id=-221008;') != '0':
        raise AssertionError('El identificador duplicado dejó un perfil parcial.')

    token = version(-221003)
    cases['desactivacion_contra_guardado'] = concurrent.race(db, database,
        "UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-221003;",
        save(-221003, {'matricula': 'CONC-WEB05-A', 'carrera': 'Después de desactivar'}, token), '23514')
    if db.sql(database, "SELECT carrera FROM banco.alumno WHERE usuario_id=-221003;") != 'Primera edición':
        raise AssertionError('El guardado no volvió a comprobar la cuenta activa después de esperar.')

    content = payload({'titulo': 'Catálogo cerrado concurrentemente', 'descripcion': 'Descripción',
        'problematica': 'Problema', 'objetivos': 'Objetivos', 'justificacion': 'Justificación',
        'alcance': 'Alcance', 'cupo_maximo_alumnos': 1})
    project = int(db.sql(database, f'SET ROLE banco_web;SELECT banco.web_crear_proyecto(-221002,{content});'))
    token = db.sql(database, f"SET ROLE banco_web;SELECT banco.web_obtener_proyecto(-221002,{project})->'proyecto'->>'version';")
    revision = int(db.sql(database, f'SET ROLE banco_web;SELECT banco.web_enviar_proyecto(-221002,{project},{literal(token)});'))
    token = db.sql(database, f"SET ROLE banco_web;SELECT banco.web_obtener_proyecto(-221002,{project})->'proyecto'->>'version';")
    db.sql(database, f"SET ROLE banco_web;SELECT banco.web_resolver_publicacion(-221001,{project},{revision},'aprobada','Aprobado para carrera',1,{literal(token)});")
    cases['cierre_contra_detalle_catalogo'] = concurrent.race(db, database,
        f"SELECT banco.cancelar_proyecto({project},-221001,'Cierre concurrente');",
        f'SET LOCAL ROLE banco_web;SELECT banco.web_obtener_proyecto_catalogo(-221006,{project});', '23503')
    return {'concurrencia': cases,
        'perfiles': 'Alta sin fila y edición con CAS; unicidad entre titulares sin perfiles parciales.',
        'permisos': 'Cuenta activa revalidada después de esperar una desactivación.',
        'catalogo': 'El detalle espera el cierre y rechaza la publicación que dejó de estar disponible.',
        'limite': 'No acredita nuevas candidaturas web, reservas, evaluación ni asignación desde Laravel.'}

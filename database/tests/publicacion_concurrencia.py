"""WEB-04: versiones de formulario y publicación con bloqueos observados."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

HASH = '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'


def run(db, database):
    spec = importlib.util.spec_from_file_location('concurrencia_publicacion_web', Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-211001,'Admin publicación concurrente','pub-conc-admin@example.invalid','!SIN-ACCESO','administrador'),
        (-211002,'Rep publicación concurrente','pub-conc-rep@example.invalid','!SIN-ACCESO','empresa');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-211010,'Empresa publicación concurrente');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-211002,-211010);
      COMMIT;""")

    def literal(value):
        return "'" + value.replace("'", "''") + "'"

    def payload(title):
        return literal(json.dumps({'titulo': title, 'descripcion': 'Descripción', 'problematica': 'Problemática',
            'objetivos': 'Objetivos', 'justificacion': 'Justificación', 'alcance': 'Alcance',
            'cupo_maximo_alumnos': 2}, ensure_ascii=False)) + '::jsonb'

    def create(title):
        return int(db.sql(database, 'SET ROLE banco_web;SELECT banco.web_crear_proyecto(-211002,' + payload(title) + ');'))

    def version(project):
        return db.sql(database, f"SET ROLE banco_web;SELECT banco.web_obtener_proyecto(-211002,{project})->'proyecto'->>'version';")

    cases = {}
    project = create('Edición concurrente')
    token = literal(version(project))
    cases['editar_contra_editar_misma_version'] = concurrent.race(db, database,
        f'SET LOCAL ROLE banco_web;SELECT banco.web_editar_proyecto(-211002,{project},{payload("Primera edición")},{token});',
        f'SET LOCAL ROLE banco_web;SELECT banco.web_editar_proyecto(-211002,{project},{payload("Edición obsoleta")},{token});', '40001')
    if db.sql(database, f'SELECT titulo FROM banco.proyecto WHERE id={project};') != 'Primera edición':
        raise AssertionError('El segundo formulario sobrescribió el proyecto.')
    if db.sql(database, f"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='editar_proyecto' AND registro_afectado='{project}';") != '1':
        raise AssertionError('La edición obsoleta dejó un evento exitoso.')

    project = create('Envío concurrente')
    token = literal(version(project))
    cases['enviar_contra_editar_misma_version'] = concurrent.race(db, database,
        f'SET LOCAL ROLE banco_web;SELECT banco.web_enviar_proyecto(-211002,{project},{token});',
        f'SET LOCAL ROLE banco_web;SELECT banco.web_editar_proyecto(-211002,{project},{payload("Edición durante envío")},{token});', '40001')
    if db.sql(database, f'SELECT estado FROM banco.proyecto WHERE id={project};') != 'en_revision' \
        or db.sql(database, f'SELECT count(*) FROM banco.revision_proyecto WHERE proyecto_id={project};') != '1':
        raise AssertionError('El envío concurrente perdió estado o duplicó revisión.')

    token = literal(version(project))
    revision = int(db.sql(database, f'SELECT id FROM banco.revision_proyecto WHERE proyecto_id={project};'))
    cases['resolver_contra_resolver_misma_version'] = concurrent.race(db, database,
        f"SET LOCAL ROLE banco_web;SELECT banco.web_resolver_publicacion(-211001,{project},{revision},'aprobada','Primera resolución',2,{token});",
        f"SET LOCAL ROLE banco_web;SELECT banco.web_resolver_publicacion(-211001,{project},{revision},'rechazada','Segunda resolución',NULL,{token});", '40001')
    if db.sql(database, f'SELECT count(*) FROM banco.decision_administrativa WHERE revision_proyecto_id={revision};') != '1' \
        or db.sql(database, f"SELECT count(*) FROM banco.notificacion n JOIN banco.evento_auditoria a ON a.id=n.evento_id WHERE a.operacion='resolver_publicacion' AND a.registro_afectado='{project}' AND n.destinatario_usuario_id=-211002;") != '1':
        raise AssertionError('La resolución concurrente dejó decisión o aviso duplicado.')

    project = create('Doble envío concurrente')
    token = literal(version(project))
    cases['enviar_contra_enviar_misma_version'] = concurrent.race(db, database,
        f'SET LOCAL ROLE banco_web;SELECT banco.web_enviar_proyecto(-211002,{project},{token});',
        f'SET LOCAL ROLE banco_web;SELECT banco.web_enviar_proyecto(-211002,{project},{token});', '40001')
    if db.sql(database, f'SELECT count(*) FROM banco.revision_proyecto WHERE proyecto_id={project};') != '1':
        raise AssertionError('El doble envío duplicó la revisión.')

    token = literal(db.sql(database, "SET ROLE banco_web;SELECT banco.web_obtener_empresa(-211002)->>'version';"))
    cases['editar_empresa_contra_editar_misma_version'] = concurrent.race(db, database,
        f"SET LOCAL ROLE banco_web;SELECT banco.web_editar_empresa(-211002,'{{\"razon_social\":\"Primera razón social\"}}',{token});",
        f"SET LOCAL ROLE banco_web;SELECT banco.web_editar_empresa(-211002,'{{\"razon_social\":\"Razón social obsoleta\"}}',{token});", '40001')
    if db.sql(database, 'SELECT razon_social FROM banco.empresa WHERE id=-211010;') != 'Primera razón social':
        raise AssertionError('El segundo formulario sobrescribió los datos empresariales.')

    project = create('Relevo concurrente')
    token = literal(version(project))
    cases['relevo_contra_edicion_representante_anterior'] = concurrent.race(db, database,
        f"SET LOCAL ROLE banco_web;SELECT banco.web_relevar_representante(-211001,-211010,'Representante nuevo','pub-conc-nuevo@example.invalid','{HASH}','Relevo concurrente',-211002);",
        f'SET LOCAL ROLE banco_web;SELECT banco.web_editar_proyecto(-211002,{project},{payload("Edición posterior al relevo")},{token});', '23514')
    if db.sql(database, f'SELECT titulo FROM banco.proyecto WHERE id={project};') != 'Relevo concurrente':
        raise AssertionError('El representante anterior editó después de esperar al relevo.')
    return {'concurrencia': cases,
        'versiones': 'CAS de contenido/habilidades/estado/revisiones/eventos; se rechazan formularios obsoletos sin repetición.',
        'publicacion': 'Un envío y una resolución por revisión; espera real observada y sin avisos duplicados.',
        'representacion': 'La vigencia se vuelve a comprobar después de esperar al relevo.',
        'limite': 'Actor de sesión validado además por Laravel; SQL usa credencial de servidor y no autentica esos IDs.'}

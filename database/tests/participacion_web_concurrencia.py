"""WEB-06: CAS, límites, decisiones y ciclo con dos conexiones reales.

La segunda conexión debe esperar un bloqueo antes de ser rechazada.
Los datos solo se crean en la base temporal del ejecutor.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def run(db, database):
    spec = importlib.util.spec_from_file_location('concurrencia_web06', Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-231001,'Admin WEB06 carreras','pw-conc-admin@example.invalid','!SIN-ACCESO','administrador'),
        (-231002,'Rep WEB06 carreras','pw-conc-rep@example.invalid','!SIN-ACCESO','empresa');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT -231000-n,'Alumno carrera '||n,'pw-conc-alumno-'||n||'@example.invalid','!SIN-ACCESO','alumno'
        FROM generate_series(3,14)n;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
        SELECT -231000-n,'Profesor carrera '||n,'pw-conc-prof-'||n||'@example.invalid','!SIN-ACCESO','profesor'
        FROM generate_series(30,32)n;
      INSERT INTO banco.alumno(usuario_id,matricula)
        SELECT id,'WEB06-CONC-A-'||id FROM banco.usuario WHERE id BETWEEN -231014 AND -231003;
      INSERT INTO banco.profesor(usuario_id,numero_empleado)
        SELECT id,'WEB06-CONC-P-'||id FROM banco.usuario WHERE id BETWEEN -231032 AND -231030;
      INSERT INTO banco.empresa(id,razon_social) VALUES(-231050,'Empresa carreras WEB06');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-231002,-231050);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
        SELECT -231100-n,-231050,-231002,'Carrera WEB06 '||n,'Descripción','Problema','Objetivo','Justificación','Alcance',
          CASE n WHEN 10 THEN 1 ELSE 2 END FROM generate_series(1,17)n;
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-231002),-231001,'aprobada','Publicación de carreras')
        FROM banco.proyecto WHERE id BETWEEN -231117 AND -231101;
      COMMIT;""")

    def literal(value):
        return "'" + str(value).replace("'", "''") + "'"

    def payload(data):
        return literal(json.dumps(data, ensure_ascii=False)) + '::jsonb'

    def runtime(statement):
        return 'SET LOCAL ROLE banco_web;' + statement

    def context(actor, project):
        return db.sql(database, f"SET ROLE banco_web;SELECT banco.web_contexto_postulacion({actor},{project})->>'version';")

    def sending(actor, project, token=None, teacher=False):
        data = {'experiencia_aplicable': 'Experiencia concurrente', 'justificacion': 'Dirección concurrente'} if teacher else {}
        return f'SELECT banco.web_enviar_participacion({actor},{project},{payload(data)},{literal(token or context(actor, project))});'

    def send(actor, project, teacher=False):
        return int(db.sql(database, 'SET ROLE banco_web;' + sending(actor, project, teacher=teacher)))

    def version(actor, kind, request):
        return db.sql(database, f"SET ROLE banco_web;SELECT banco.web_detalle_participacion({actor},{literal(kind)},{request})->>'version';")

    def operation(actor, kind, request, action, data=None, token=None):
        return f'SELECT banco.web_operar_participacion({actor},{literal(kind)},{request},{literal(action)},{payload(data or {})},{literal(token or version(actor, kind, request))});'

    def cycle_version(project):
        return db.sql(database, f"SET ROLE banco_web;SELECT banco.web_detalle_proyecto_participacion(-231001,{project})->>'version';")

    def cycle(project, action, data=None, token=None):
        return f'SELECT banco.web_operar_proyecto_participacion(-231001,{project},{literal(action)},{payload(data or {})},{literal(token or cycle_version(project))});'

    rubric = {'puntuaciones': {key: {'puntuacion': 2, 'comentario': 'Cumple'} for key in ['tecnico', 'blando', 'academico']},
              'comentarios': 'Evaluación de concurrencia', 'recomendada': True}

    def preselect(request):
        db.sql(database, 'SET ROLE banco_web;' + operation(-231002, 'candidatura', request, 'evaluar', rubric))
        db.sql(database, 'SET ROLE banco_web;' + operation(-231002, 'candidatura', request, 'preseleccionar'))

    def approve(kind, request):
        db.sql(database, 'SET ROLE banco_web;' + operation(-231001, kind, request, 'aprobar', {'motivo': 'Asignación para carrera'}))

    cases = {}
    send(-231003, -231101)
    send(-231003, -231102)
    first, second = context(-231003, -231103), context(-231003, -231104)
    cases['tercera_y_cuarta_candidatura'] = concurrent.race(db, database,
        runtime(sending(-231003, -231103, first)), runtime(sending(-231003, -231104, second)), '40001')
    if db.sql(database, "SELECT count(*) FROM banco.candidatura WHERE alumno_id=-231003 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');") != '3':
        raise AssertionError('Se excedió el máximo de tres candidaturas.')

    token = context(-231005, -231105)
    cases['doble_envio_mismo_contexto'] = concurrent.race(db, database,
        runtime(sending(-231005, -231105, token)), runtime(sending(-231005, -231105, token)), '40001')
    if db.sql(database, 'SELECT count(*) FROM banco.candidatura WHERE alumno_id=-231005 AND proyecto_id=-231105;') != '1':
        raise AssertionError('El doble envío creó solicitudes duplicadas.')

    request = send(-231006, -231106)
    preselect(request)
    token = version(-231001, 'candidatura', request)
    cases['cancelacion_contra_autorizacion'] = concurrent.race(db, database,
        runtime(operation(-231006, 'candidatura', request, 'cancelar', token=token)),
        runtime(operation(-231001, 'candidatura', request, 'aprobar', {'motivo': 'No debe autorizar'}, token)), '40001')
    if db.sql(database, f'SELECT count(*) FROM banco.asignacion_alumno WHERE candidatura_id={request};') != '0':
        raise AssertionError('Se asignó una candidatura ya cancelada.')

    request = send(-231007, -231107)
    preselect(request)
    token = version(-231001, 'candidatura', request)
    cases['reevaluacion_contra_autorizacion_obsoleta'] = concurrent.race(db, database,
        runtime(operation(-231002, 'candidatura', request, 'evaluar', rubric, token)),
        runtime(operation(-231001, 'candidatura', request, 'aprobar', {'motivo': 'No debe autorizar'}, token)), '40001')
    if db.sql(database, f"SELECT estado FROM banco.candidatura WHERE id={request};") != 'evaluada':
        raise AssertionError('La reevaluación no invalidó la preselección.')

    request = send(-231030, -231108, teacher=True)
    token = version(-231001, 'direccion', request)
    cases['autorizar_director_contra_cancelacion'] = concurrent.race(db, database,
        runtime(operation(-231001, 'direccion', request, 'aprobar', {'motivo': 'Autorizar primero'}, token)),
        runtime(operation(-231030, 'direccion', request, 'cancelar', token=token)), '40001')
    if db.sql(database, f"SELECT count(*) FROM banco.asignacion_direccion WHERE solicitud_direccion_id={request} AND estado='vigente';") != '1':
        raise AssertionError('Autorización y asignación docente no quedaron juntas.')

    student, teacher = send(-231010, -231109), send(-231031, -231109, teacher=True)
    preselect(student)
    approve('candidatura', student)
    approve('direccion', teacher)
    token = cycle_version(-231109)
    cases['inicio_contra_cierre_obsoleto'] = concurrent.race(db, database,
        runtime(cycle(-231109, 'iniciar', token=token)),
        runtime(cycle(-231109, 'cancelar', {'motivo': 'No debe cerrar con formulario viejo'}, token)), '40001')
    if db.sql(database, 'SELECT estado FROM banco.proyecto WHERE id=-231109;') != 'en_curso':
        raise AssertionError('El cierre obsoleto cambió el proyecto iniciado.')

    a, b = send(-231008, -231110), send(-231009, -231110)
    preselect(a)
    preselect(b)
    first, second = version(-231001, 'candidatura', a), version(-231001, 'candidatura', b)
    cases['dos_autorizaciones_ultima_plaza'] = concurrent.race(db, database,
        runtime(operation(-231001, 'candidatura', a, 'aprobar', {'motivo': 'Última plaza'}, first)),
        runtime(operation(-231001, 'candidatura', b, 'aprobar', {'motivo': 'No debe exceder'}, second)), '40001')
    if db.sql(database, "SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=-231110 AND estado='vigente';") != '1':
        raise AssertionError('Se excedió la última plaza.')

    for project in [-231111, -231112]:
        approve('direccion', send(-231032, project, teacher=True))
    a, b = send(-231032, -231113, teacher=True), send(-231032, -231114, teacher=True)
    first, second = version(-231001, 'direccion', a), version(-231001, 'direccion', b)
    cases['tercera_y_cuarta_direccion'] = concurrent.race(db, database,
        runtime(operation(-231001, 'direccion', a, 'aprobar', {'motivo': 'Tercera dirección'}, first)),
        runtime(operation(-231001, 'direccion', b, 'aprobar', {'motivo': 'No debe ser cuarta'}, second)), '23514')
    if db.sql(database, "SELECT count(*) FROM banco.asignacion_direccion WHERE profesor_id=-231032 AND estado='vigente';") != '3':
        raise AssertionError('Se excedió la carga de tres direcciones.')

    token = context(-231011, -231115)
    cases['cierre_contra_nuevo_envio'] = concurrent.race(db, database,
        runtime(cycle(-231115, 'cancelar', {'motivo': 'Cerrar antes de recibir'})),
        runtime(sending(-231011, -231115, token)), '23503')
    if db.sql(database, 'SELECT count(*) FROM banco.candidatura WHERE alumno_id=-231011 AND proyecto_id=-231115;') != '0':
        raise AssertionError('Se recibió una solicitud después del cierre.')

    token = context(-231012, -231116)
    cases['desactivacion_contra_nuevo_envio'] = concurrent.race(db, database,
        "SELECT banco.cambiar_estado_cuenta(-231001,-231012,'inactiva','Desactivación concurrente');",
        runtime(sending(-231012, -231116, token)), '23514')
    if db.sql(database, 'SELECT count(*) FROM banco.candidatura WHERE alumno_id=-231012 AND proyecto_id=-231116;') != '0':
        raise AssertionError('La cuenta inactiva recibió una solicitud nueva.')

    request = int(db.sql(database, 'SELECT id FROM banco.candidatura WHERE proyecto_id=-231110 ORDER BY id LIMIT 1;'))
    cases['relevo_contra_lectura_empresarial'] = concurrent.race(db, database,
        "SELECT banco.relevar_representante(-231001,-231050,'Representante nuevo WEB06','pw-conc-relevo@example.invalid','!SIN-ACCESO','Relevo concurrente');",
        runtime(f"SELECT banco.web_detalle_participacion(-231002,'candidatura',{request});"), '23514')

    return {'concurrencia': cases,
        'integridad': 'Máximos reales, resolución/asignación atómicas, estados y token revalidados después de esperar.',
        'alcance': 'Todas las operaciones de participación/ciclo usan banco_web; desactivación utiliza operación interna administrativa.'}

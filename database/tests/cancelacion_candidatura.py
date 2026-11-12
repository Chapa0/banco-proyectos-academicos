"""D-07 parcial: cancelación anterior a asignación, historial y carreras reales.

Las aprobaciones y asignaciones de este módulo son fixtures técnicos coherentes
del propietario. No prueban las etapas de autorización todavía abiertas en D-08.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import time
import uuid


def _error(db, database, code, statement):
    try:
        db.sql(database, statement)
    except RuntimeError as error:
        if code not in str(error):
            raise AssertionError(f'Se esperaba {code}; se obtuvo: {error}') from error
    else:
        raise AssertionError(f'Se aceptó indebidamente una operación que debía devolver {code}.')


def _assert(db, database, query, expected, message):
    actual = db.sql(database, query)
    if actual != str(expected):
        raise AssertionError(f'{message}: esperado {expected}, obtenido {actual}.')


def _approval(candidate, assignment, student, project):
    return f"""UPDATE banco.candidatura SET estado='aprobada' WHERE id={candidate};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
        VALUES ({assignment},-120001,{candidate},'aprobada','Fixture técnico para la carrera D-07');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES ({assignment},{candidate},{assignment},{student},{project},'2026-01-01 00:00:00+00');"""


def _success_after_wait(db, database, concurrent, first_sql, second_sql):
    """Ambas operaciones válidas confirman; la segunda debe esperar un lock real."""
    token = uuid.uuid4().hex[:10]
    first = concurrent.Transaction(db, database, 'cancelacion_a_' + token)
    second = None
    observed = False
    try:
        first.execute(first_sql)
        app = 'cancelacion_b_' + token
        second = subprocess.Popen(db.command('psql', database) + ['-X','-qAt','-v','ON_ERROR_STOP=on',
            '-v','VERBOSITY=verbose'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', env={**db.env, 'PGAPPNAME': app})
        second.stdin.write('BEGIN;\n' + second_sql + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;\n')
        second.stdin.close()
        second.stdin = None
        deadline = time.monotonic() + 12
        while second.poll() is None and time.monotonic() < deadline:
            if db.sql(database, f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';") == '1':
                observed = True
                break
            time.sleep(.04)
        if not observed:
            output, error = second.communicate(timeout=3)
            raise AssertionError('La nueva candidatura no esperó el bloqueo de la cancelación: ' + error + output)
        first.close(commit=True)
        output, error = second.communicate(timeout=20)
        if second.returncode:
            raise AssertionError('La nueva candidatura no usó el cupo liberado tras esperar: ' + error + output)
        return {'espera_de_bloqueo_observada': True,
                'resultado': 'cancelación y nuevo envío confirmados; máximo de tres conservado'}
    finally:
        try:
            first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill()
                second.communicate()


def run(db, database):
    """Ejecutar únicamente en una base temporal propia del ejecutor."""
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-120001,'Admin cancelación','cancel-admin@example.invalid','!prueba','administrador'),
        (-120002,'Empresa cancelación','cancel-rep@example.invalid','!prueba','empresa'),
        (-120201,'Director cancelación','cancel-prof@example.invalid','!prueba','profesor');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta)
      SELECT id,'Alumno cancelación ' || id,'cancel-a' || abs(id) || '@example.invalid','!prueba','alumno',
        CASE WHEN id=-120104 THEN 'inactiva' ELSE 'activa' END
      FROM generate_series(-120113,-120101) AS alumnos(id);
      INSERT INTO banco.alumno(usuario_id,matricula)
      SELECT id,'CANCEL-A-' || abs(id) FROM generate_series(-120113,-120101) AS alumnos(id);
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES(-120201,'CANCEL-P-01');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-120010,'Empresa ficticia cancelación');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-120002,-120010);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos)
      SELECT id,-120010,-120002,'Cancelación ' || id,'Descripción','Problemática',
        'Objetivos','Justificación','Alcance',2
      FROM generate_series(-120317,-120301) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-120002),-120001,'aprobada','Publicación de prueba')
      FROM banco.proyecto WHERE empresa_id=-120010 ORDER BY id;
      INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado,observaciones) VALUES
        (-120401,-120101,-120301,'pendiente_evaluacion','Solicitud pendiente conservada'),
        (-120402,-120102,-120302,'evaluada','Evaluación conservada'),
        (-120403,-120103,-120303,'preseleccionada','Preselección conservada'),
        (-120404,-120104,-120304,'pendiente_evaluacion','Cuenta inactiva'),
        (-120405,-120105,-120305,'rechazada','Rechazo histórico'),
        (-120406,-120106,-120306,'pendiente_evaluacion','Alumno asignado'),
        (-120417,-120106,-120307,'evaluada','Otra candidatura del alumno ya asignado'),
        (-120407,-120107,-120307,'pendiente_evaluacion','Otra solicitud uno'),
        (-120408,-120107,-120308,'evaluada','Solicitud que libera cupo'),
        (-120409,-120107,-120309,'preseleccionada','Otra solicitud dos'),
        (-120410,-120108,-120310,'pendiente_evaluacion','Rollback auditoría'),
        (-120411,-120109,-120311,'preseleccionada','Pendiente de proyecto iniciado'),
        (-120420,-120110,-120311,'pendiente_evaluacion','Participante del proyecto iniciado'),
        (-120412,-120111,-120312,'preseleccionada','Cancelación gana carrera'),
        (-120413,-120112,-120313,'preseleccionada','Asignación gana carrera'),
        (-120414,-120113,-120314,'pendiente_evaluacion','Carrera cupo uno'),
        (-120415,-120113,-120315,'evaluada','Carrera cupo libera'),
        (-120416,-120113,-120316,'preseleccionada','Carrera cupo dos');
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES(-120450,-120201,-120311);
      """ + _approval(-120406,-120506,-120106,-120306)
      + _approval(-120420,-120520,-120110,-120311) + """
      UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-120450;
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES(-120550,-120001,-120450,'aprobada','Dirección para proyecto iniciado');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES(-120550,-120450,-120550,-120201,-120311,'2026-01-01 00:00:00+00');
      COMMIT;""")

    negatives = 0
    for code, sql in (
        ('23503', 'SELECT banco.cancelar_candidatura(-129999,-120101);'),
        ('23514', 'SELECT banco.cancelar_candidatura(-120401,-120102);'),
        ('23514', 'SELECT banco.cancelar_candidatura(-120401,-120001);'),
        ('23514', 'SELECT banco.cancelar_candidatura(-120404,-120104);'),
        ('55000', 'SELECT banco.cancelar_candidatura(-120405,-120105);'),
        ('55000', 'SELECT banco.cancelar_candidatura(-120406,-120106);'),
        ('25001', 'BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT banco.cancelar_candidatura(-120401,-120101); COMMIT;'),
        ('42501', 'BEGIN; SET LOCAL ROLE banco_escritura; SELECT banco.cancelar_candidatura(-120401,-120101); COMMIT;'),
    ):
        _error(db,database,code,sql)
        negatives += 1

    # Tener otra asignación no impide cancelar esta fuente aún no asignada.
    # El retiro del proyecto ya asignado sigue siendo otra operación de D-07.
    assignment_before = db.sql(database,'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id=-120506;')
    db.sql(database,'SELECT banco.cancelar_candidatura(-120417,-120106);')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-120417;",'cancelada','Se bloqueó la cancelación por una asignación de otra candidatura')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-120406;",'aprobada','Cancelar la fuente adicional alteró el origen ya asignado')
    _assert(db,database,'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id=-120506;',assignment_before,'Cancelar la fuente adicional alteró la asignación vigente')

    before = db.sql(database, "SELECT jsonb_agg(to_jsonb(c)-'estado' ORDER BY id) FROM banco.candidatura c WHERE id IN(-120401,-120402,-120403);")
    events = []
    for candidate, student in ((-120401,-120101),(-120402,-120102),(-120403,-120103)):
        events.append(db.sql(database, f'SELECT banco.cancelar_candidatura({candidate},{student});'))
    after = db.sql(database, "SELECT jsonb_agg(to_jsonb(c)-'estado' ORDER BY id) FROM banco.candidatura c WHERE id IN(-120401,-120402,-120403);")
    if before != after:
        raise AssertionError('Cancelar alteró identidad, autor, fecha, observaciones o proyecto históricos.')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE id IN(-120401,-120402,-120403) AND estado='cancelada';",3,'No se cancelaron los tres estados activos')
    _assert(db,database,"""SELECT count(*) FROM banco.evento_auditoria e JOIN banco.candidatura c ON c.id::text=e.registro_afectado
      WHERE c.id IN(-120401,-120402,-120403) AND e.operacion='cancelar_candidatura'
        AND e.entidad_afectada='candidatura' AND e.actor_usuario_id=c.alumno_id
        AND e.fecha IS NOT NULL AND e.transicion IN ('pendiente_evaluacion -> cancelada','evaluada -> cancelada','preseleccionada -> cancelada');""",3,'Falta actor, fecha o transición exacta de la cancelación')
    if len(set(events)) != 3:
        raise AssertionError('Distintas cancelaciones no devolvieron eventos distintos.')
    for sql in (
        'SELECT banco.cancelar_candidatura(-120401,-120101);',
        "UPDATE banco.candidatura SET estado='preseleccionada' WHERE id=-120401;",
        "UPDATE banco.candidatura SET observaciones='Reescritura' WHERE id=-120401;",
    ):
        _error(db,database,'55000',sql)
        negatives += 1
    _assert(db,database,"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='cancelar_candidatura' AND registro_afectado='-120401';",1,'Repetir la cancelación duplicó su evento')
    # Es un nuevo envío explícito, no reapertura ni postulación automática.
    db.sql(database,'SELECT banco.presentar_candidatura(-120303,-120103);')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-120103 AND proyecto_id=-120303;",2,'No se conservó la cancelada al presentar una candidatura nueva')

    db.sql(database,'SELECT banco.cancelar_candidatura(-120408,-120107); SELECT banco.presentar_candidatura(-120310,-120107);')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-120107 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');",3,'No se reutilizó el cupo liberado sin superar tres')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE id IN(-120407,-120409) AND estado IN ('pendiente_evaluacion','preseleccionada');",2,'Se alteraron las otras candidaturas del alumno')

    _error(db,database,'P9999',"""BEGIN;
      CREATE FUNCTION pg_temp.fallar_cancelacion() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.operacion='cancelar_candidatura' AND NEW.registro_afectado='-120410' THEN
          RAISE EXCEPTION 'Fallo controlado de auditoría' USING ERRCODE='P9999';
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER tr_zz_prueba_cancelacion BEFORE INSERT ON banco.evento_auditoria
        FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_cancelacion();
      SELECT banco.cancelar_candidatura(-120410,-120108);
      COMMIT;""")
    negatives += 1
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-120410;",'pendiente_evaluacion','El fallo de auditoría liberó indebidamente la candidatura')
    _assert(db,database,"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='cancelar_candidatura' AND registro_afectado='-120410';",0,'El fallo dejó auditoría parcial')

    db.sql(database,'SELECT banco.iniciar_proyecto(-120311,-120001); SELECT banco.cancelar_candidatura(-120411,-120109);')
    _assert(db,database,"SELECT estado FROM banco.proyecto WHERE id=-120311;",'en_curso','Cancelar una candidatura sin asignación alteró el proyecto iniciado')
    _assert(db,database,"SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=-120311 AND estado='vigente';",1,'Cancelar una candidatura alteró asignaciones de otros alumnos')
    _assert(db,database,"SELECT has_function_privilege('banco_lectura','banco.cancelar_candidatura(bigint,bigint)','EXECUTE') OR has_function_privilege('banco_escritura','banco.cancelar_candidatura(bigint,bigint)','EXECUTE');",'f','La función interna fue expuesta sin integración de aplicación')

    spec = importlib.util.spec_from_file_location('concurrencia_cancelacion',Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    races = {}
    races['cancelar_antes_de_asignar'] = concurrent.race(db,database,
      'SELECT banco.cancelar_candidatura(-120412,-120111);',
      _approval(-120412,-120512,-120111,-120312),'55000')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-120412;",'cancelada','La aprobación reabrió la candidatura cancelada')
    _assert(db,database,'SELECT count(*) FROM banco.decision_administrativa WHERE id=-120512;',0,'La aprobación rechazada dejó una decisión parcial')
    _assert(db,database,'SELECT count(*) FROM banco.asignacion_alumno WHERE candidatura_id=-120412;',0,'La candidatura cancelada terminó asignada')
    races['asignar_antes_de_cancelar'] = concurrent.race(db,database,
      _approval(-120413,-120513,-120112,-120313),
      'SELECT banco.cancelar_candidatura(-120413,-120112);','55000')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-120413;",'aprobada','La cancelación deshizo una aprobación ya formalizada')
    _assert(db,database,'SELECT count(*) FROM banco.asignacion_alumno WHERE candidatura_id=-120413;',1,'La asignación concurrente válida desapareció')
    _assert(db,database,"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='cancelar_candidatura' AND registro_afectado='-120413';",0,'La cancelación rechazada dejó auditoría parcial')
    races['cancelar_y_nuevo_envio'] = _success_after_wait(db,database,concurrent,
      'SELECT banco.cancelar_candidatura(-120415,-120113);',
      'SELECT banco.presentar_candidatura(-120317,-120113);')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-120113 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');",3,'La carrera excedió el máximo activo')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-120113;",4,'La carrera perdió el historial cancelado')
    return {
      'negativos_secuenciales':negatives,
      'estados':'pendiente_evaluacion, evaluada y preseleccionada cancelables antes de asignación; historia cancelada no reabre ni se reescribe',
      'actor_y_auditoria':'alumno activo propietario; evento con actor/fecha/estado anterior, sin motivo obligatorio para el alumno',
      'liberacion':'cupo de candidatura liberado atómicamente; otras candidaturas y asignaciones permanecen',
      'rollback':'fallo de auditoría revierte cancelación y liberación; repetición no duplica el evento',
      'proyecto_iniciado':'puede cancelar una candidatura previa sin asignación, sin alterar los participantes iniciados',
      'alumno_ya_asignado':'puede cancelar otra candidatura activa sin modificar el origen aprobado ni su asignación vigente',
      'concurrencia':races,
      'limite':'No implementa retiro posterior por administrador, cierre, cancelación docente, reapertura ni etapas de autorización D-08; funciones internas sin autenticación web.'
    }

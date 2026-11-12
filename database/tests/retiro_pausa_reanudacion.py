"""D-07: retiros administrativos, pausa, reposición y reanudación explícita.

Las aprobaciones son fixtures técnicos con origen/decisión/asignación coherentes.
No acreditan etapas previas de autorización D-08 ni sesión o permisos web.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import time
import uuid

ADMIN = -132001
OTHER_ADMIN = -132004


def _p(n): return -132300-n
def _s(n, second=False): return -132100-2*n-(2 if second else 1)
def _c(n, second=False): return -132400-10*n-(2 if second else 1)
def _a(n, second=False): return -132500-10*n-(2 if second else 1)
def _t(n): return -132200-n
def _r(n): return -132600-n
def _d(n): return -132700-n
def _v(n, second=False): return -132800-10*n-(2 if second else 1)


def _assert(db, database, query, expected, message):
    actual = db.sql(database, query)
    if actual != str(expected):
        raise AssertionError(f'{message}: esperado {expected}, obtenido {actual}.')


def _error(db, database, code, statement):
    try:
        db.sql(database, statement)
    except RuntimeError as error:
        if code not in str(error):
            raise AssertionError(f'Se esperaba {code}; se obtuvo: {error}') from error
    else:
        raise AssertionError(f'Se aceptó indebidamente una operación que debía devolver {code}.')


def _student(candidate, assignment, student, project, start="clock_timestamp()"):
    return f"""UPDATE banco.candidatura SET estado='aprobada' WHERE id={candidate};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
        VALUES({assignment},{ADMIN},{candidate},'aprobada','Fixture técnico de reposición');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES({assignment},{candidate},{assignment},{student},{project},{start});"""


def _teacher(request, assignment, teacher, project, start="clock_timestamp()"):
    return f"""UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id={request};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES({assignment},{ADMIN},{request},'aprobada','Fixture técnico de reposición docente');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES({assignment},{request},{assignment},{teacher},{project},{start});"""


def _transaction(sql):
    return 'BEGIN;\n' + sql + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;'


def _event_insert(kind, assignment, participant, project, actor=ADMIN):
    operation = 'retirar_alumno' if kind == 'alumno' else 'retirar_director'
    table = 'asignacion_alumno' if kind == 'alumno' else 'asignacion_direccion'
    return f"""INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
        registro_afectado,transicion,resultado)
      VALUES({actor},'usuario','{operation}','{table}','{assignment}','vigente -> revocada',
        jsonb_build_object('tipo','{kind}','asignacion_id',{assignment},'participante_id',{participant},
          'proyecto_id',{project},'motivo','Fixture de evidencia adversarial')::text)"""


def _manual_retirement(kind, assignment, participant, project, *, actor=ADMIN, close_links=False):
    table = 'asignacion_alumno' if kind == 'alumno' else 'asignacion_direccion'
    column = 'asignacion_alumno_id' if kind == 'alumno' else 'asignacion_direccion_id'
    sql = f"""CREATE TEMP TABLE evidencia_retiro(id bigint,fecha timestamptz);
      WITH e AS ({_event_insert(kind,assignment,participant,project,actor)} RETURNING id,fecha)
      INSERT INTO evidencia_retiro SELECT * FROM e;
      UPDATE banco.{table} SET estado='revocada',fin=(SELECT fecha FROM evidencia_retiro),
        evento_retiro_id=(SELECT id FROM evidencia_retiro) WHERE id={assignment};"""
    if close_links:
        sql += f"""UPDATE banco.acompanamiento SET estado='revocada',
          fin=CASE WHEN (SELECT fecha FROM evidencia_retiro)>inicio THEN (SELECT fecha FROM evidencia_retiro) ELSE NULL END,
          evento_retiro_id=(SELECT id FROM evidencia_retiro) WHERE {column}={assignment} AND estado='vigente';"""
    return sql


def _concurrent():
    spec = importlib.util.spec_from_file_location('concurrencia_retiros',Path(__file__).with_name('concurrencia.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _both(db, database, concurrent, first_sql, second_sql, same_event_query=None):
    """Dos operaciones válidas confirman después de una espera real."""
    token = uuid.uuid4().hex[:10]
    first = concurrent.Transaction(db,database,'retiro_a_' + token)
    second = None
    observed = False
    try:
        first.execute(first_sql)
        app = 'retiro_b_' + token
        second = subprocess.Popen(db.command('psql',database) + ['-X','-qAt','-v','ON_ERROR_STOP=on',
            '-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            text=True,encoding='utf-8',env={**db.env,'PGAPPNAME':app})
        second.stdin.write('BEGIN;\n' + second_sql + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;\n')
        second.stdin.close()
        second.stdin = None
        deadline = time.monotonic()+12
        while second.poll() is None and time.monotonic()<deadline:
            if db.sql(database,f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';") == '1':
                observed = True
                break
            time.sleep(.04)
        if not observed:
            output,error = second.communicate(timeout=3)
            raise AssertionError('La segunda operación no esperó el bloqueo: ' + error + output)
        first.close(commit=True)
        output,error = second.communicate(timeout=20)
        if second.returncode:
            raise AssertionError('Falló una operación que debía confirmar después de esperar: ' + error + output)
        if same_event_query is not None and db.sql(database,same_event_query) not in output.splitlines():
            raise AssertionError('La segunda reanudación no devolvió el mismo evento confirmado.')
        return {'espera_de_bloqueo_observada':True,'resultado':'ambas operaciones confirman sin interbloqueo'}
    finally:
        try:
            first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill()
                second.communicate()


def _setup(db, database):
    sql = """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
        (-132001,'Admin retiros','retiro-admin@example.invalid','!prueba','administrador','activa'),
        (-132002,'Empresa retiros','retiro-rep@example.invalid','!prueba','empresa','activa'),
        (-132003,'Admin retiros inactivo','retiro-admin-inactivo@example.invalid','!prueba','administrador','inactiva'),
        (-132004,'Otro admin retiros','retiro-admin2@example.invalid','!prueba','administrador','activa');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT id,'Alumno retiros ' || id,'retiro-a' || abs(id) || '@example.invalid','!prueba','alumno'
      FROM generate_series(-132140,-132101) AS alumnos(id);
      INSERT INTO banco.alumno(usuario_id,matricula)
      SELECT id,'RET-A-' || abs(id) FROM generate_series(-132140,-132101) AS alumnos(id);
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT id,'Profesor retiros ' || id,'retiro-p' || abs(id) || '@example.invalid','!prueba','profesor'
      FROM generate_series(-132220,-132201) AS profesores(id);
      INSERT INTO banco.profesor(usuario_id,numero_empleado)
      SELECT id,'RET-P-' || abs(id) FROM generate_series(-132220,-132201) AS profesores(id);
      INSERT INTO banco.empresa(id,razon_social) VALUES(-132010,'Empresa ficticia retiros');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-132002,-132010);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos)
      SELECT id,-132010,-132002,'Retiros ' || id,'Descripción','Problemática','Objetivos','Justificación','Alcance',3
      FROM generate_series(-132312,-132301) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-132002),-132001,'aprobada','Proyecto de prueba')
      FROM banco.proyecto WHERE empresa_id=-132010 ORDER BY id;
      """
    for n in range(1,13):
        sql += f"INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES({_c(n)},{_s(n)},{_p(n)});\n"
        sql += f"INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES({_r(n)},{_t(n)},{_p(n)});\n"
    for n in (1,2,8,10,11,12):
        sql += f"INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES({_c(n,True)},{_s(n,True)},{_p(n)});\n"
    sql += f"""INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES(-132951,-132101,{_p(11)});
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES
        (-132901,-132219,{_p(1)}),(-132909,-132220,{_p(9)});"""
    for n in range(1,13):
        student_start = "'2099-01-01 00:00:00+00'" if n == 2 else "'2020-01-01 00:00:00+00'"
        teacher_start = "'2099-01-01 00:00:00+00'" if n == 3 else "'2020-01-01 00:00:00+00'"
        sql += _student(_c(n),_a(n),_s(n),_p(n),student_start)
        sql += _teacher(_r(n),_d(n),_t(n),_p(n),teacher_start)
        link_start = "'2099-01-02 00:00:00+00'" if n in (1,2,3) else "'2020-01-02 00:00:00+00'"
        sql += f"INSERT INTO banco.acompanamiento(id,asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES({_v(n)},{_a(n)},{_d(n)},{link_start});\n"
    sql += _student(_c(1,True),_a(1,True),_s(1,True),_p(1),"'2020-01-01 00:00:00+00'")
    sql += f"INSERT INTO banco.acompanamiento(id,asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES({_v(1,True)},{_a(1,True)},{_d(1)},'2020-01-02 00:00:00+00');\n"
    sql += "SELECT banco.iniciar_proyecto(id,-132001) FROM banco.proyecto WHERE empresa_id=-132010 ORDER BY id;\nCOMMIT;"
    db.sql(database,sql)


def run(db, database):
    """Usar solo una base temporal propia; nunca la base de trabajo."""
    _setup(db,database)
    original_starts = json.loads(db.sql(database,"SELECT json_object_agg(id,evento_inicio_id) FROM banco.proyecto WHERE empresa_id=-132010;"))
    negatives = 0
    for code,sql in (
      ('23514',f"SELECT banco.retirar_alumno({_a(1)},{_s(1)},'No es administrador');"),
      ('23514',f"SELECT banco.retirar_director({_d(3)},{_t(3)},'No retiro unilateral');"),
      ('23514',f"SELECT banco.retirar_alumno({_a(1)},-132003,'Cuenta inactiva');"),
      ('23514',f"SELECT banco.retirar_director({_d(1)},{ADMIN},E' \\t\\n');"),
      ('23514',f"SELECT banco.retirar_alumno({_a(1)},{ADMIN},NULL);"),
      ('23503',f"SELECT banco.retirar_alumno(-139999,{ADMIN},'Sin asignación');"),
      ('25001',f"BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT banco.retirar_alumno({_a(1)},{ADMIN},'Aislamiento no admitido'); COMMIT;"),
      ('42501',f"BEGIN; SET LOCAL ROLE banco_escritura; SELECT banco.retirar_alumno({_a(1)},{ADMIN},'Sin permiso técnico'); COMMIT;"),
    ):
        _error(db,database,code,sql)
        negatives += 1

    # Un retiro normal puede cerrar un acompañamiento cuyo periodo aún no comenzó.
    retained_student = db.sql(database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id={_a(1,True)};')
    retained_teacher = db.sql(database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_direccion a WHERE id={_d(1)};')
    student_event = db.sql(database,f"SELECT banco.retirar_alumno({_a(1)},{ADMIN},'Retiro académico con historial');")
    _assert(db,database,f"SELECT estado || ':' || (fin IS NOT NULL)::text FROM banco.asignacion_alumno WHERE id={_a(1)};",'revocada:true','El retiro normal no registró fin real')
    _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_retiro_id FROM banco.acompanamiento WHERE id={_v(1)};",'revocada:true:'+student_event,'Se inventó un fin para el acompañamiento futuro')
    _assert(db,database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id={_a(1,True)};',retained_student,'Se alteró otro alumno al retirar a su compañero')
    _assert(db,database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_direccion a WHERE id={_d(1)};',retained_teacher,'El retiro de alumno alteró al director')
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(1)};",'en_curso','Se pausó un proyecto que conservaba su mínimo')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE alumno_id={_s(1)} AND estado='vigente';",0,'El retiro no liberó la carga del alumno')
    old_link = db.sql(database,f'SELECT to_jsonb(a)::text FROM banco.acompanamiento a WHERE id={_v(1)};')
    db.sql(database,f"UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id={ADMIN}; UPDATE banco.asignacion_direccion SET estado=estado WHERE id={_d(1)};")
    director_event = db.sql(database,f"SELECT banco.retirar_director({_d(1)},{OTHER_ADMIN},'Cambio autorizado de director');")
    _assert(db,database,f'SELECT to_jsonb(a)::text FROM banco.acompanamiento a WHERE id={_v(1)};',old_link,'El retiro docente reescribió un acompañamiento ya cerrado')
    _assert(db,database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id={_a(1,True)};',retained_student,'El retiro del director modificó al alumno retenido')
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(1)};",'pausado','Perder director no pausó el proyecto')
    db.sql(database,f"UPDATE banco.usuario SET estado_cuenta='activa' WHERE id={ADMIN};")
    _assert(db,database,f"SELECT banco.retirar_director({_d(1)},{ADMIN},'Repetición sin reescribir motivo');",director_event,'Repetir retiro duplicó su evidencia')

    # La vacante admite pendientes y nuevas solicitudes; una reposición basta.
    new_request = int(db.sql(database,f"SELECT banco.solicitar_direccion({_p(1)},-132220,'Experiencia','Justificación');"))
    db.sql(database,_transaction(_teacher(-132901,-132971,-132219,_p(1))))
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(1)};",'pausado','Reponer el director reanudó automáticamente')
    for sql in (
      f"SELECT banco.solicitar_direccion({_p(1)},-132218,'Experiencia','Justificación');",
      f'SELECT banco.presentar_candidatura({_p(1)},-132102);',
      _transaction(_teacher(new_request,-132972,-132220,_p(1))),
    ):
        _error(db,database,'55000',sql)
        negatives += 1
    for actor in (_s(1,True),-132003):
        _error(db,database,'23514',f'SELECT banco.reanudar_proyecto({_p(1)},{actor});')
        negatives += 1
    resumed = db.sql(database,f'SELECT banco.reanudar_proyecto({_p(1)},{ADMIN});')
    _assert(db,database,f'SELECT banco.reanudar_proyecto({_p(1)},{OTHER_ADMIN});',resumed,'Repetir reanudación duplicó el evento')
    _assert(db,database,f"SELECT count(*) FROM banco.acompanamiento v JOIN banco.asignacion_alumno a ON a.id=v.asignacion_alumno_id WHERE a.proyecto_id={_p(1)};",2,'La reposición creó acompañamientos no solicitados')

    # El periodo no iniciado se revoca sin una fecha final ficticia.
    anticipated_student = db.sql(database,f"SELECT banco.retirar_alumno({_a(2)},{ADMIN},'Retiro antes del periodo previsto');")
    _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_retiro_id FROM banco.asignacion_alumno WHERE id={_a(2)};",'revocada:true:'+anticipated_student,'El retiro anticipado de alumno inventó un fin')
    _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_retiro_id FROM banco.acompanamiento WHERE id={_v(2)};",'revocada:true:'+anticipated_student,'El acompañamiento anticipado no conservó el retiro exacto')
    db.sql(database,f'SELECT banco.presentar_candidatura({_p(2)},-132102);')
    _assert(db,database,f"SELECT count(*) FROM banco.candidatura WHERE proyecto_id={_p(2)} AND estado='pendiente_evaluacion';",2,'La vacante no conservó pendientes y nueva candidatura')
    anticipated_teacher = db.sql(database,f"SELECT banco.retirar_director({_d(3)},{ADMIN},'Retiro docente antes del periodo');")
    _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_retiro_id FROM banco.asignacion_direccion WHERE id={_d(3)};",'revocada:true:'+anticipated_teacher,'El retiro anticipado docente inventó un fin')
    _assert(db,database,f"SELECT estado FROM banco.asignacion_alumno WHERE id={_a(3)};",'vigente','El retiro docente liberó al alumno sin autorización')
    for n in (2,3):
        _error(db,database,'23514',f"INSERT INTO banco.acompanamiento(asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES({_a(n)},{_d(n)},'2099-01-03 00:00:00+00');")
        negatives += 1
        _error(db,database,'23514',f'SELECT banco.reanudar_proyecto({_p(n)},{ADMIN});')
        negatives += 1

    # Auditoría fallida antes o después del cambio del padre revierte el conjunto.
    source_before = db.sql(database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id={_a(4)};')
    for table,timing,condition in (
      ('evento_auditoria','BEFORE INSERT',f"NEW.operacion='retirar_alumno' AND NEW.registro_afectado='{_a(4)}'"),
      ('asignacion_alumno','AFTER UPDATE',f"NEW.id={_a(4)} AND NEW.estado='revocada'"),
    ):
        _error(db,database,'P9999',f"""BEGIN;
          CREATE FUNCTION pg_temp.fallar_retiro() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN IF {condition} THEN RAISE EXCEPTION 'Fallo controlado de retiro' USING ERRCODE='P9999'; END IF; RETURN NEW; END $$;
          CREATE TRIGGER tr_zz_prueba_retiro {timing} ON banco.{table} FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_retiro();
          SELECT banco.retirar_alumno({_a(4)},{ADMIN},'Se debe revertir'); COMMIT;""")
        negatives += 1
        _assert(db,database,f'SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id={_a(4)};',source_before,'El fallo dejó un retiro parcial')
        _assert(db,database,f"SELECT estado FROM banco.acompanamiento WHERE id={_v(4)};",'vigente','El fallo dejó un acompañamiento cerrado')
        _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(4)};",'en_curso','El fallo dejó una pausa parcial')

    # Un evento correcto no permite omitir la pausa al confirmar sin mínimos.
    _error(db,database,'23514',_transaction(_manual_retirement('alumno',_a(5),_s(5),_p(5),close_links=True)))
    negatives += 1
    _assert(db,database,f"SELECT estado FROM banco.asignacion_alumno WHERE id={_a(5)};",'vigente','El CT permitió confirmar En curso sin alumno')
    _assert(db,database,f"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='retirar_alumno' AND registro_afectado='{_a(5)}';",0,'El rechazo diferido dejó un evento parcial')
    stale = db.sql(database,_event_insert('alumno',_a(6),_s(6),_p(6))+' RETURNING id;')
    _error(db,database,'23514',f"UPDATE banco.asignacion_alumno SET estado='revocada',evento_retiro_id={stale},fin=(SELECT fecha FROM banco.evento_auditoria WHERE id={stale}) WHERE id={_a(6)};")
    negatives += 1
    # Un motivo y evento frescos de otro tipo tampoco autorizan el retiro.
    _error(db,database,'23514',_transaction(f"""CREATE TEMP TABLE evento_incorrecto(id bigint,fecha timestamptz);
      WITH e AS ({_event_insert('alumno',_a(4),_s(4),_p(4))} RETURNING id,fecha) INSERT INTO evento_incorrecto SELECT * FROM e;
      UPDATE banco.asignacion_direccion SET estado='revocada',fin=(SELECT fecha FROM evento_incorrecto),
        evento_retiro_id=(SELECT id FROM evento_incorrecto) WHERE id={_d(4)};"""))
    negatives += 1
    _error(db,database,'23514',_transaction(_manual_retirement('alumno',_a(4),_s(4),_p(4),actor=_s(4))))
    negatives += 1

    concurrent = _concurrent()
    races = {}
    races['retiros_alumno_y_director'] = _both(db,database,concurrent,
      f"SELECT banco.retirar_alumno({_a(7)},{ADMIN},'Retiro concurrente de alumno');",
      f"SELECT banco.retirar_director({_d(7)},{OTHER_ADMIN},'Retiro concurrente docente');")
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(7)};",'pausado','Los retiros concurrentes no preservaron la pausa')
    _assert(db,database,f"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='pausar_proyecto' AND registro_afectado='{_p(7)}';",1,'Dos retiros simultáneos duplicaron la pausa')

    db.sql(database,f"SELECT banco.retirar_alumno({_a(8)},{ADMIN},'Preparar reanudación');")
    db.sql(database,_transaction(_student(_c(8,True),_a(8,True),_s(8,True),_p(8))))
    races['dos_reanudaciones'] = _both(db,database,concurrent,
      f'SELECT banco.reanudar_proyecto({_p(8)},{ADMIN});',
      f'SELECT banco.reanudar_proyecto({_p(8)},{OTHER_ADMIN});',
      f'SELECT evento_estado_id FROM banco.proyecto WHERE id={_p(8)};')
    _assert(db,database,f"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='reanudar_proyecto' AND registro_afectado='{_p(8)}';",1,'La reanudación concurrente duplicó auditoría')

    db.sql(database,f"SELECT banco.retirar_director({_d(9)},{ADMIN},'Preparar reposición docente');")
    db.sql(database,_transaction(_teacher(-132909,-132979,-132220,_p(9))))
    races['reanudar_y_retirar'] = _both(db,database,concurrent,
      f'SELECT banco.reanudar_proyecto({_p(9)},{ADMIN});',
      f"SELECT banco.retirar_alumno({_a(9)},{OTHER_ADMIN},'Retiro posterior a reanudación');")
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(9)};",'pausado','El retiro posterior dejó En curso sin alumno')
    _assert(db,database,"SELECT estado FROM banco.asignacion_direccion WHERE id=-132979;",'vigente','El retiro del alumno alteró la dirección repuesta')

    db.sql(database,f"SELECT banco.retirar_alumno({_a(10)},{ADMIN},'Preparar reposición de alumno');")
    db.sql(database,_transaction(_student(_c(10,True),_a(10,True),_s(10,True),_p(10))))
    races['retirar_y_reanudar'] = concurrent.race(db,database,
      f"SELECT banco.retirar_director({_d(10)},{ADMIN},'Retiro antes de reanudar');",
      f'SELECT banco.reanudar_proyecto({_p(10)},{OTHER_ADMIN});','23514')
    _assert(db,database,f"SELECT estado FROM banco.proyecto WHERE id={_p(10)};",'pausado','La reanudación ignoró una vacante creada mientras esperaba')

    db.sql(database,f"SELECT banco.retirar_alumno({_a(11)},{ADMIN},'Abrir vacante mínima');")
    races['dos_reposiciones_misma_vacante'] = concurrent.race(db,database,
      _student(_c(11,True),_a(11,True),_s(11,True),_p(11)),
      _student(-132951,-132952,-132101,_p(11)),'55000')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id={_p(11)} AND estado='vigente';",1,'La reposición incorporó participantes adicionales al mínimo faltante')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-132951;",'pendiente_evaluacion','La reposición rechazada dejó fuente aprobada')
    _assert(db,database,'SELECT count(*) FROM banco.decision_administrativa WHERE id=-132952;',0,'La reposición rechazada dejó decisión parcial')

    db.sql(database,f"SELECT banco.retirar_alumno({_a(12)},{ADMIN},'Preparar fallo de reanudación');")
    db.sql(database,_transaction(_student(_c(12,True),_a(12,True),_s(12,True),_p(12))))
    pause_before = db.sql(database,f'SELECT evento_estado_id FROM banco.proyecto WHERE id={_p(12)};')
    _error(db,database,'P9999',f"""BEGIN;
      CREATE FUNCTION pg_temp.fallar_reanudacion() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.operacion='reanudar_proyecto' AND NEW.registro_afectado='{_p(12)}' THEN
        RAISE EXCEPTION 'Fallo controlado al reanudar' USING ERRCODE='P9999'; END IF; RETURN NEW; END $$;
      CREATE TRIGGER tr_zz_prueba_reanudar BEFORE INSERT ON banco.evento_auditoria
        FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_reanudacion();
      SELECT banco.reanudar_proyecto({_p(12)},{ADMIN}); COMMIT;""")
    negatives += 1
    _assert(db,database,f"SELECT estado || ':' || evento_estado_id FROM banco.proyecto WHERE id={_p(12)};",'pausado:'+pause_before,'El fallo de auditoría dejó reanudación parcial')
    db.sql(database,f'SELECT banco.reanudar_proyecto({_p(12)},{ADMIN});')
    for project,initial in original_starts.items():
        _assert(db,database,f'SELECT evento_inicio_id FROM banco.proyecto WHERE id={int(project)};',initial,'La pausa o reanudación sustituyó el primer inicio')
    _assert(db,database,"SELECT has_function_privilege('banco_escritura','banco.retirar_alumno(bigint,bigint,text)','EXECUTE') OR has_function_privilege('banco_lectura','banco.retirar_director(bigint,bigint,text)','EXECUTE') OR has_function_privilege('banco_escritura','banco.reanudar_proyecto(bigint,bigint)','EXECUTE');",'f','Se expusieron operaciones internas sin permisos de aplicación')
    return {
      'negativos_secuenciales':negatives,
      'retiros':'administrador activo, motivo e historial; origen aprobado conservado, carga retirada liberada y otras asignaciones intactas',
      'periodos_futuros':'padres y acompañamientos no iniciados revocados con fin NULL y fecha real en evento; no admiten hijos vigentes',
      'historia':'acompañamiento cerrado conserva su evento aunque se retire el otro padre y se inactive al administrador anterior',
      'pausa':'automática al perder un mínimo, sin liberar otras asignaciones; CT rechaza confirmar En curso sin mínimo',
      'reposicion':'pendientes y nuevas del tipo faltante; una reposición autorizada no reanuda ni permite extras del tipo ya cubierto',
      'reanudacion':'administrativa expresa, mínimos y límites revalidados, idempotente y primer inicio intacto',
      'evidencia':'evento de tipo/objeto/administrador exactos en la misma transacción; rollback en auditoría o tras cambiar el padre',
      'concurrencia':races,
      'limite':'Fixtures técnicos de aprobación; no etapas D-08, cierre definitivo, cancelación docente pendiente, cambios publicados ni autenticación/avisos web.'
    }

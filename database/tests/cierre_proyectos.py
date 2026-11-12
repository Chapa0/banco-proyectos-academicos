"""D-07: cierre administrativo coordinado, períodos e intercalaciones reales.

Las aprobaciones de las fixtures son DML técnico coherente del propietario.
No equivalen al recorrido de evaluación/autorización de D-08 ni a una sesión web.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import time
import uuid

ADMIN = -144001
OTHER_ADMIN = -144004
COMPANY = -144010


def _p(n): return -144300-n
def _s(n, slot=1): return -145000-10*n-slot
def _c(n, slot=1): return -146000-10*n-slot
def _a(n, slot=1): return -147000-10*n-slot
def _t(n, slot=1): return -148000-10*n-slot
def _r(n, slot=1): return -149000-10*n-slot
def _d(n, slot=1): return -150000-10*n-slot
def _v(n, slot=1): return -151000-10*n-slot


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


def _transaction(sql):
    return 'BEGIN;\n' + sql + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;'


def _student(n, slot=1, start="'2020-01-01 00:00:00+00'"):
    return f"""UPDATE banco.candidatura SET estado='aprobada' WHERE id={_c(n,slot)};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
        VALUES({_a(n,slot)},{ADMIN},{_c(n,slot)},'aprobada','Fixture técnica de cierre');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES({_a(n,slot)},{_c(n,slot)},{_a(n,slot)},{_s(n,slot)},{_p(n)},{start});"""


def _teacher(n, slot=1, start="'2020-01-01 00:00:00+00'"):
    return f"""UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id={_r(n,slot)};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES({_d(n,slot)},{ADMIN},{_r(n,slot)},'aprobada','Fixture técnica docente de cierre');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES({_d(n,slot)},{_r(n,slot)},{_d(n,slot)},{_t(n,slot)},{_p(n)},{start});"""


def _snapshot(db, database, n):
    """Contenido relevante, incluidas fuentes históricas y auditoría del proyecto."""
    return db.sql(database,f"""SELECT jsonb_build_object(
      'proyecto',(SELECT to_jsonb(p) FROM banco.proyecto p WHERE id={_p(n)}),
      'alumnos',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM banco.asignacion_alumno a WHERE proyecto_id={_p(n)}),
      'directores',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM banco.asignacion_direccion a WHERE proyecto_id={_p(n)}),
      'acompanamientos',(SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]') FROM banco.acompanamiento v JOIN banco.asignacion_alumno a ON a.id=v.asignacion_alumno_id WHERE a.proyecto_id={_p(n)}),
      'candidaturas',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM banco.candidatura c WHERE proyecto_id={_p(n)}),
      'solicitudes',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM banco.solicitud_direccion s WHERE proyecto_id={_p(n)}),
      'revisiones',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY id),'[]') FROM banco.revision_proyecto r WHERE proyecto_id={_p(n)}),
      'cierres',(SELECT count(*) FROM banco.evento_auditoria WHERE entidad_afectada='proyecto' AND registro_afectado='{_p(n)}' AND operacion IN('finalizar_proyecto','cancelar_proyecto')));""")


def _manual_event(n):
    return f"""CREATE TEMP TABLE cierre_incompleto(id bigint);
      WITH e AS (
        INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
        SELECT {ADMIN},'usuario','cancelar_proyecto','proyecto',id::text,estado || ' -> cancelado',
          jsonb_build_object('motivo','Fixture adversarial de cierre parcial','estado_anterior',estado,
            'evento_inicio_id',evento_inicio_id,'evento_estado_id',evento_estado_id,
            'revision_publicada_id',revision_publicada_id,'alcance',banco.alcance_cierre_proyecto(id))::text
        FROM banco.proyecto WHERE id={_p(n)} RETURNING id)
      INSERT INTO cierre_incompleto SELECT id FROM e;"""


def _concurrent():
    spec = importlib.util.spec_from_file_location('concurrencia_cierres',Path(__file__).with_name('concurrencia.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _race(db, database, concurrent, first_sql, second_sql, expected=None, event_query=None):
    """Verificar una espera real, el resultado tras el commit y ningún deadlock."""
    token = uuid.uuid4().hex[:10]
    first = concurrent.Transaction(db,database,'cierre_a_' + token)
    second = None
    try:
        first.execute(first_sql)
        app = 'cierre_b_' + token
        second = subprocess.Popen(db.command('psql',database) + ['-X','-qAt','-v','ON_ERROR_STOP=on',
            '-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            text=True,encoding='utf-8',env={**db.env,'PGAPPNAME':app})
        second.stdin.write(_transaction(second_sql))
        second.stdin.close()
        second.stdin = None
        observed = False
        deadline = time.monotonic()+12
        while second.poll() is None and time.monotonic()<deadline:
            if db.sql(database,f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';") == '1':
                observed = True
                break
            time.sleep(.04)
        if not observed:
            out,error = second.communicate(timeout=3)
            raise AssertionError('La segunda operación no esperó un bloqueo real: ' + error + out)
        first.close(commit=True)
        out,error = second.communicate(timeout=20)
        if expected is None:
            if second.returncode:
                raise AssertionError('La segunda operación debía confirmar después de esperar: ' + error + out)
            if event_query is not None and db.sql(database,event_query) not in out.splitlines():
                raise AssertionError('El cierre repetido no devolvió el evento original.')
        elif second.returncode == 0 or expected not in error:
            raise AssertionError(f'Se esperaba {expected} tras la espera: {error}{out}')
        return {'espera_de_bloqueo_observada':True,
                'resultado':'ambas confirman' if expected is None else 'segunda rechazada con ' + expected}
    finally:
        try:
            first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill()
                second.communicate()


def _setup(db, database):
    sql = f"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
        ({ADMIN},'Admin cierres','cierre-admin@example.invalid','!prueba','administrador','activa'),
        (-144002,'Empresa cierres','cierre-rep@example.invalid','!prueba','empresa','activa'),
        (-144003,'Admin cierres inactivo','cierre-inactivo@example.invalid','!prueba','administrador','inactiva'),
        ({OTHER_ADMIN},'Otro admin cierres','cierre-admin2@example.invalid','!prueba','administrador','activa');
      INSERT INTO banco.empresa(id,razon_social) VALUES({COMPANY},'Empresa ficticia cierres');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-144002,{COMPANY});
      """
    for n in range(1,25):
        for slot in range(1,8):
            sql += f"""INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
              VALUES({_s(n,slot)},'Alumno cierre {n}-{slot}','cierre-a{n}-{slot}@example.invalid','!prueba','alumno');
              INSERT INTO banco.alumno(usuario_id,matricula) VALUES({_s(n,slot)},'CIE-A-{n}-{slot}');"""
        for slot in (1,2):
            sql += f"""INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
              VALUES({_t(n,slot)},'Profesor cierre {n}-{slot}','cierre-p{n}-{slot}@example.invalid','!prueba','profesor');
              INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES({_t(n,slot)},'CIE-P-{n}-{slot}');"""
        sql += f"""INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
          objetivos,justificacion,alcance,cupo_maximo_alumnos)
          VALUES({_p(n)},{COMPANY},-144002,'Cierre {n}','Descripción','Problemática','Objetivos','Justificación','Alcance',3);"""
        if n == 2:
            sql += f'SELECT banco.enviar_proyecto({_p(n)},-144002);'
        elif n in (3,7):
            result = 'en_correccion' if n == 3 else 'rechazada'
            sql += f"SELECT banco.resolver_publicacion(banco.enviar_proyecto({_p(n)},-144002),{ADMIN},'{result}','Revisión de prueba');"
        elif n != 1:
            sql += f"SELECT banco.resolver_publicacion(banco.enviar_proyecto({_p(n)},-144002),{ADMIN},'aprobada','Publicación de prueba');"
            for slot in (1,2,3):
                sql += f'INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES({_c(n,slot)},{_s(n,slot)},{_p(n)});'
            for slot in (1,2):
                sql += f'INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES({_r(n,slot)},{_t(n,slot)},{_p(n)});'
    participants = (4,5,6,8,10,11,12,13,14,15,16,19,20,21,23,24)
    for n in participants:
        student_start = "'2099-01-01 00:00:00+00'" if n == 21 else "'2020-01-01 00:00:00+00'"
        teacher_start = student_start
        sql += _student(n,start=student_start) + _teacher(n,start=teacher_start)
        link_start = "'2099-01-02 00:00:00+00'" if n in (8,21) else "'2020-01-02 00:00:00+00'"
        sql += f'INSERT INTO banco.acompanamiento(id,asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES({_v(n)},{_a(n)},{_d(n)},{link_start});'
    for n in (5,8):
        sql += _student(n,2,"'2099-01-01 00:00:00+00'" if n == 8 else "'2020-01-01 00:00:00+00'")
        link_start = "'2099-01-02 00:00:00+00'" if n == 8 else "'2020-01-02 00:00:00+00'"
        sql += f'INSERT INTO banco.acompanamiento(id,asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES({_v(n,2)},{_a(n,2)},{_d(n)},{link_start});'
    # Historia cerrada antes de iniciar: el cierre posterior no debe reescribirla.
    sql += f'INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES({_c(5,7)},{_s(5,7)},{_p(5)});'
    sql += _student(5,7)
    sql += f"SELECT banco.retirar_alumno({_a(5,7)},{ADMIN},'Historia previa que se conserva');"
    # Los tres estados activos deben cerrarse; los rechazados no se reescriben.
    for slot,state in ((4,'evaluada'),(5,'preseleccionada'),(6,'rechazada')):
        sql += f"INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado,observaciones) VALUES({_c(4,slot)},{_s(4,slot)},{_p(4)},'{state}','Historia de prueba');"
    for n in participants:
        if n != 4:
            sql += f'SELECT banco.iniciar_proyecto({_p(n)},{ADMIN});'
    for n in (6,15):
        sql += f"SELECT banco.retirar_director({_d(n)},{ADMIN},'Preparar pausa de prueba');"
    sql += _teacher(15,2)
    sql += 'SET CONSTRAINTS ALL IMMEDIATE; COMMIT;'
    db.sql(database,sql)


def _check_closed(db, database, n, state, event):
    _assert(db,database,f"SELECT estado || ':' || evento_cierre_id FROM banco.proyecto WHERE id={_p(n)};",state+':'+event,'No se conservó el cierre exacto del proyecto')
    for table in ('asignacion_alumno','asignacion_direccion'):
        _assert(db,database,f"SELECT count(*) FROM banco.{table} WHERE proyecto_id={_p(n)} AND estado='vigente';",0,'El cierre dejó reservas vigentes')
    _assert(db,database,f"SELECT count(*) FROM banco.acompanamiento v JOIN banco.asignacion_alumno a ON a.id=v.asignacion_alumno_id WHERE a.proyecto_id={_p(n)} AND v.estado='vigente';",0,'El cierre dejó acompañamientos vigentes')
    _assert(db,database,f"SELECT count(*) FROM banco.candidatura WHERE proyecto_id={_p(n)} AND estado IN('pendiente_evaluacion','evaluada','preseleccionada');",0,'El cierre no liberó candidaturas activas')
    _assert(db,database,f"SELECT count(*) FROM banco.solicitud_direccion WHERE proyecto_id={_p(n)} AND estado='pendiente';",0,'El cierre dejó solicitudes docentes pendientes')


def run(db, database):
    """Invocar exclusivamente sobre una base temporal propiedad del ejecutor."""
    _setup(db,database)
    negatives = 0
    untouched = _snapshot(db,database,23)
    starts = db.sql(database,f'SELECT jsonb_object_agg(id,evento_inicio_id) FROM banco.proyecto WHERE empresa_id={COMPANY};')
    decisions = db.sql(database,f"""SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) FROM banco.decision_administrativa d
      WHERE d.administrador_usuario_id={ADMIN};""")
    old_assignment = db.sql(database,f'SELECT to_jsonb(a) FROM banco.asignacion_alumno a WHERE id={_a(5,7)};')
    old_rejected = db.sql(database,f'SELECT to_jsonb(c) FROM banco.candidatura c WHERE id={_c(4,6)};')
    for code,sql in (
      ('23503',f"SELECT banco.cancelar_proyecto(-159999,{ADMIN},'No existe');"),
      ('23514',f"SELECT banco.finalizar_proyecto({_p(8)},{_s(8)},'Actor incorrecto');"),
      ('23514',f"SELECT banco.cancelar_proyecto({_p(4)},-144002,'Empresa sin permiso');"),
      ('23514',f"SELECT banco.cancelar_proyecto({_p(4)},-144003,'Admin inactivo');"),
      ('23514',f"SELECT banco.cancelar_proyecto({_p(4)},{ADMIN},E' \t\n');"),
      ('23514',f'SELECT banco.finalizar_proyecto({_p(8)},{ADMIN},NULL);'),
      ('25001',f"BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT banco.cancelar_proyecto({_p(4)},{ADMIN},'RR no soportado'); COMMIT;"),
      ('42501',f"BEGIN; SET LOCAL ROLE banco_escritura; SELECT banco.cancelar_proyecto({_p(4)},{ADMIN},'Sin privilegio técnico'); COMMIT;"),
      ('55000',f"UPDATE banco.proyecto SET estado='finalizado' WHERE id={_p(11)};"),
      ('55000',f"UPDATE banco.proyecto SET estado='cancelado' WHERE id={_p(11)};"),
    ):
        _error(db,database,code,sql)
        negatives += 1
    for n in (1,2,3,4,6,7):
        _error(db,database,'55000',f"SELECT banco.finalizar_proyecto({_p(n)},{ADMIN},'Solo debe finalizar En curso');")
        negatives += 1
    _error(db,database,'55000',f"SELECT banco.cancelar_proyecto({_p(7)},{ADMIN},'Rechazado ya está cerrado');")
    negatives += 1

    # Cancelar desde cada estado abierto; el borrador no recibe un inicio ficticio.
    for n in (1,2,3,4,5,6):
        event = db.sql(database,f"SELECT banco.cancelar_proyecto({_p(n)},{ADMIN},'Cancelación administrativa de prueba');")
        _check_closed(db,database,n,'cancelado',event)
        _assert(db,database,f"SELECT banco.cancelar_proyecto({_p(n)},{OTHER_ADMIN},'No reescribe motivo');",event,'La repetición duplicó el cierre')
        _assert(db,database,f"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='cancelar_proyecto' AND registro_afectado='{_p(n)}';",1,'Se duplicó el evento de cancelación')
    _assert(db,database,f"SELECT count(*) FROM banco.proyecto WHERE id IN({_p(1)},{_p(2)},{_p(3)},{_p(4)}) AND evento_inicio_id IS NOT NULL;",0,'Se inventó inicio en una cancelación anterior al inicio')
    _assert(db,database,f"SELECT estado_revision || ':' || (evento_cierre_id IS NOT NULL)::text FROM banco.revision_proyecto WHERE proyecto_id={_p(2)};",'cancelada:true','La revisión pendiente no se canceló con evidencia')
    _assert(db,database,f"SELECT count(*) FROM banco.decision_administrativa WHERE revision_proyecto_id IN(SELECT id FROM banco.revision_proyecto WHERE proyecto_id={_p(2)});",0,'Se inventó una decisión administrativa para la revisión cancelada')
    _assert(db,database,f"SELECT estado_revision || ':' || (evento_cierre_id IS NULL)::text FROM banco.revision_proyecto WHERE proyecto_id={_p(3)};",'en_correccion:true','La revisión ya resuelta fue reescrita')
    _assert(db,database,f'SELECT to_jsonb(a) FROM banco.asignacion_alumno a WHERE id={_a(5,7)};',old_assignment,'El cierre reescribió un retiro histórico')
    _assert(db,database,f'SELECT to_jsonb(c) FROM banco.candidatura c WHERE id={_c(4,6)};',old_rejected,'El cierre reescribió una candidatura rechazada')
    _assert(db,database,f"SELECT count(*) FROM banco.candidatura WHERE proyecto_id={_p(4)} AND estado='aprobada' AND evento_cierre_id IS NULL;",1,'El cierre canceló el origen aprobado de una asignación')
    _assert(db,database,f"SELECT count(*) FROM banco.candidatura c JOIN banco.proyecto p ON p.id=c.proyecto_id WHERE p.id={_p(4)} AND c.estado='cancelada' AND c.evento_cierre_id=p.evento_cierre_id;",4,'Las candidaturas canceladas no comparten la evidencia raíz')

    # Finalizar libera reservas y representa los períodos futuros sin fin ficticio.
    final_event = db.sql(database,f"SELECT banco.finalizar_proyecto({_p(8)},{ADMIN},'Proyecto concluido');")
    _check_closed(db,database,8,'finalizado',final_event)
    _assert(db,database,f"SELECT estado || ':' || (fin IS NOT NULL)::text || ':' || evento_cierre_id FROM banco.asignacion_alumno WHERE id={_a(8)};",'finalizada:true:'+final_event,'No se cerró el alumno con fecha real')
    _assert(db,database,f"SELECT a.fin=e.fecha FROM banco.asignacion_alumno a JOIN banco.evento_auditoria e ON e.id=a.evento_cierre_id WHERE a.id={_a(8)};",'t','El fin no coincide con la fecha real del evento raíz')
    _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_cierre_id FROM banco.asignacion_alumno WHERE id={_a(8,2)};",'finalizada:true:'+final_event,'Se inventó fin del alumno futuro')
    _assert(db,database,f"SELECT count(*) FROM banco.acompanamiento WHERE id IN({_v(8)},{_v(8,2)}) AND estado='finalizada' AND fin IS NULL AND evento_cierre_id={final_event};",2,'Los acompañamientos futuros no conservan el cierre exacto')
    _assert(db,database,f"SELECT banco.finalizar_proyecto({_p(8)},{OTHER_ADMIN},'Repetición sin cambio');",final_event,'Finalizar repetido duplicó el evento')
    # Cancelar un proyecto iniciado cuyos períodos efectivos aún no comenzaron.
    future_event = db.sql(database,f"SELECT banco.cancelar_proyecto({_p(21)},{ADMIN},'Cancelación anterior al período');")
    for table,record in (('asignacion_alumno',_a(21)),('asignacion_direccion',_d(21)),('acompanamiento',_v(21))):
        _assert(db,database,f"SELECT estado || ':' || (fin IS NULL)::text || ':' || evento_cierre_id FROM banco.{table} WHERE id={record};",'revocada:true:'+future_event,'La cancelación anticipada inventó fecha efectiva')

    # La historia no exige que un administrador histórico continúe activo.
    db.sql(database,f"UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id={ADMIN}; UPDATE banco.asignacion_alumno SET estado=estado WHERE id={_a(8)};")
    db.sql(database,f"UPDATE banco.usuario SET estado_cuenta='activa' WHERE id={ADMIN};")
    for code,sql in (
      ('55000',f"SELECT banco.cancelar_proyecto({_p(8)},{ADMIN},'Destino opuesto');"),
      ('55000',f"SELECT banco.finalizar_proyecto({_p(5)},{ADMIN},'Destino opuesto');"),
      ('55000',f"UPDATE banco.proyecto SET estado='publicado' WHERE id={_p(8)};"),
      ('55000',f"UPDATE banco.proyecto SET titulo='Reescritura' WHERE id={_p(8)};"),
      ('55000',f"UPDATE banco.candidatura SET estado='preseleccionada' WHERE id={_c(4,5)};"),
      ('23514',f"UPDATE banco.asignacion_alumno SET estado='revocada',fin=(SELECT fecha FROM banco.evento_auditoria WHERE id={final_event}),evento_cierre_id={final_event} WHERE id={_a(11)};"),
    ):
        _error(db,database,code,sql)
        negatives += 1

    # Evidencia correcta de la transacción no permite cerrar solo una fuente.
    partial_before = _snapshot(db,database,11)
    _error(db,database,'23514',_transaction(_manual_event(11) + f"""
      UPDATE banco.candidatura SET estado='cancelada',evento_cierre_id=(SELECT id FROM cierre_incompleto)
      WHERE id={_c(11,3)};"""))
    negatives += 1
    if partial_before != _snapshot(db,database,11):
        raise AssertionError('El cierre parcial confirmado dejó una candidatura liberada o evento residual.')

    # Una falla de auditoría o de un hijo revierte todo, incluida la liberación.
    before = _snapshot(db,database,10)
    for table,timing,condition in (
      ('evento_auditoria','BEFORE INSERT',f"NEW.operacion='finalizar_proyecto' AND NEW.registro_afectado='{_p(10)}'"),
      ('asignacion_alumno','AFTER UPDATE',f"NEW.id={_a(10)} AND NEW.estado='finalizada'"),
    ):
        _error(db,database,'P9999',f"""BEGIN;
          CREATE FUNCTION pg_temp.fallar_cierre() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN IF {condition} THEN RAISE EXCEPTION 'Fallo controlado de cierre' USING ERRCODE='P9999'; END IF; RETURN NEW; END $$;
          CREATE TRIGGER tr_zz_prueba_cierre {timing} ON banco.{table} FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_cierre();
          SELECT banco.finalizar_proyecto({_p(10)},{ADMIN},'Debe revertir todo'); COMMIT;""")
        negatives += 1
        if before != _snapshot(db,database,10):
            raise AssertionError('El fallo dejó cierre parcial, fuentes canceladas o auditoría residual.')

    concurrent = _concurrent()
    races = {}
    races['cierre_repetido'] = _race(db,database,concurrent,
      f"SELECT banco.finalizar_proyecto({_p(12)},{ADMIN},'Primer cierre');",
      f"SELECT banco.finalizar_proyecto({_p(12)},{OTHER_ADMIN},'Repetición concurrente');",
      event_query=f'SELECT evento_cierre_id FROM banco.proyecto WHERE id={_p(12)};')
    races['finalizar_y_cancelar'] = _race(db,database,concurrent,
      f"SELECT banco.finalizar_proyecto({_p(13)},{ADMIN},'Finalización gana');",
      f"SELECT banco.cancelar_proyecto({_p(13)},{OTHER_ADMIN},'Cancelación incompatible');",'55000')
    races['cierre_y_retiro'] = _race(db,database,concurrent,
      f"SELECT banco.cancelar_proyecto({_p(14)},{ADMIN},'Cierre gana');",
      f"SELECT banco.retirar_alumno({_a(14)},{OTHER_ADMIN},'Retiro tardío');",'55000')
    races['cierre_y_reanudacion'] = _race(db,database,concurrent,
      f"SELECT banco.cancelar_proyecto({_p(15)},{ADMIN},'Cerrar durante pausa');",
      f'SELECT banco.reanudar_proyecto({_p(15)},{OTHER_ADMIN});','55000')
    # Tras leer un alcance anterior, se rechaza antes de escribir y se reintenta.
    races['retiro_y_cierre_reintentable'] = _race(db,database,concurrent,
      f"SELECT banco.retirar_alumno({_a(16)},{ADMIN},'Retiro cambia alcance');",
      f"SELECT banco.cancelar_proyecto({_p(16)},{OTHER_ADMIN},'Cerrar tras retiro');",'40001')
    _assert(db,database,f"SELECT estado || ':' || (evento_cierre_id IS NULL)::text FROM banco.proyecto WHERE id={_p(16)};",'pausado:true','La operación reintentable dejó un cierre parcial')
    event = db.sql(database,f"SELECT banco.cancelar_proyecto({_p(16)},{OTHER_ADMIN},'Reintento de transacción completa');")
    _check_closed(db,database,16,'cancelado',event)
    races['nueva_solicitud_y_cierre_reintentable'] = _race(db,database,concurrent,
      f'SELECT banco.presentar_candidatura({_p(17)},{_s(17,4)});',
      f"SELECT banco.cancelar_proyecto({_p(17)},{ADMIN},'Alcance incorpora una solicitud');",'40001')
    event = db.sql(database,f"SELECT banco.cancelar_proyecto({_p(17)},{ADMIN},'Reintento con alcance actual');")
    _check_closed(db,database,17,'cancelado',event)
    races['autorizacion_y_cierre_reintentable'] = _race(db,database,concurrent,
      _student(18),f"SELECT banco.cancelar_proyecto({_p(18)},{ADMIN},'Asignación recién autorizada');",'40001')
    event = db.sql(database,f"SELECT banco.cancelar_proyecto({_p(18)},{ADMIN},'Reintento posterior a autorización');")
    _check_closed(db,database,18,'cancelado',event)
    races['cierre_y_nueva_candidatura'] = _race(db,database,concurrent,
      f"SELECT banco.cancelar_proyecto({_p(19)},{ADMIN},'Cerrar antes del envío');",
      f'SELECT banco.presentar_candidatura({_p(19)},{_s(19,4)});','23514')
    _assert(db,database,f'SELECT count(*) FROM banco.candidatura WHERE alumno_id={_s(19,4)} AND proyecto_id={_p(19)};',0,'El envío concurrente dejó una candidatura en el proyecto cerrado')

    # Las decisiones originales, el primer inicio y otros proyectos permanecen.
    _assert(db,database,f'SELECT jsonb_object_agg(id,evento_inicio_id) FROM banco.proyecto WHERE empresa_id={COMPANY};',starts,'El cierre alteró el primer inicio')
    _assert(db,database,f"SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) FROM banco.decision_administrativa d WHERE d.administrador_usuario_id={ADMIN} AND id<>{_a(18)};",decisions,'El cierre modificó decisiones anteriores')
    if untouched != _snapshot(db,database,23):
        raise AssertionError('Cerrar otros proyectos alteró un proyecto independiente.')
    _assert(db,database,"SELECT has_function_privilege('banco_lectura','banco.finalizar_proyecto(bigint,bigint,text)','EXECUTE') OR has_function_privilege('banco_escritura','banco.cancelar_proyecto(bigint,bigint,text)','EXECUTE');",'f','Se expusieron operaciones internas sin integración de aplicación')
    return {
      'negativos_secuenciales':negatives,
      'estados':'cancelación desde todos los estados abiertos; finalización solo En curso; cerrados no reabren ni cambian de destino',
      'actor':'administrador activo con motivo no blanco, auditoría exacta e idempotencia del mismo cierre',
      'coordinacion':'asignaciones y acompañamientos cierran; candidaturas activas y solicitudes pendientes se cancelan; cupos y cargas quedan liberados',
      'revision':'revisión pendiente cancelada con evento, sin inventar decisión; revisiones resueltas y fuentes aprobadas permanecen',
      'periodos':'fin real cuando el período había empezado; fin NULL con evidencia exacta cuando aún no empezó, incluso al finalizar',
      'historia':'primer inicio, estados anteriores, decisiones, retiros previos y otros proyectos conservados; administrador histórico puede inactivarse',
      'rollback':'fallo de auditoría o hijo revierte el cierre y sus efectos conjuntos',
      'concurrencia':races,
      'reintento':'40001 por alcance concurrente cambiado no deja cierres parciales; una transacción nueva cierra el alcance actualizado',
      'limite':'Pruebas SQL internas con fixtures técnicas de autorización, sin sesión, API ni entrega de avisos externos.'
    }

"""D-08: evaluación inmutable, preselección y decisión/asignación atómicas.

Solo usa datos ficticios y bases temporales del ejecutor. Las operaciones SQL
internas comprueban actor/rol/pertenencia; no representan autenticación web.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import time
import uuid

ADMIN=-162001
REP=-162002
OTHER_REP=-162003
INACTIVE=-162004


def _p(n): return -162300-n
def _a(n): return -162100-n
def _t(n): return -162200-n
def _c(n): return -162400-n
def _r(n): return -162500-n


def _literal(text): return "'"+text.replace("'","''")+"'"


def _rubric(score=2,comment='Comparado con los requisitos del proyecto'):
    return json.dumps({k:{'puntuacion':score,'comentario':comment} for k in ('tecnico','blando','academico')},ensure_ascii=False)


def _evaluate(candidate,representative=REP,*,score=2,recommended=True,comments='Valoración manual del perfil'):
    return f"SELECT banco.evaluar_candidatura({candidate},{representative},{_literal(_rubric(score))}::jsonb,{_literal(comments)},{str(recommended).lower()});"


def _resolve(candidate,result='aprobada',admin=ADMIN,reason='Decisión administrativa motivada'):
    return f"SELECT banco.resolver_candidatura({candidate},{admin},{_literal(result)},{_literal(reason)});"


def _direction(request,result='aprobada',admin=ADMIN):
    return f"SELECT banco.resolver_direccion({request},{admin},{_literal(result)},'Revisión administrativa de experiencia');"


def _assert(db,database,query,expected,message):
    actual=db.sql(database,query)
    if actual!=str(expected): raise AssertionError(f'{message}: esperado {expected}, obtenido {actual}')


def _error(db,database,code,statement):
    try: db.sql(database,statement)
    except RuntimeError as error:
        if code not in str(error): raise AssertionError(f'Se esperaba {code}, obtenido {error}') from error
    else: raise AssertionError(f'Se aceptó una operación que debía rechazarse con {code}')


def _transaction(statement): return 'BEGIN;\n'+statement+'\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;'


def _concurrent():
    spec=importlib.util.spec_from_file_location('concurrencia_d08',Path(__file__).with_name('concurrencia.py'))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _both(db,database,concurrent,first_sql,second_sql):
    """La repetición espera la primera operación y devuelve la misma decisión."""
    token=uuid.uuid4().hex[:10]
    first=concurrent.Transaction(db,database,'d08_a_'+token)
    second=None
    try:
        first.execute(first_sql)
        app='d08_b_'+token
        second=subprocess.Popen(db.command('psql',database)+['-X','-qAt','-v','ON_ERROR_STOP=on','-v','VERBOSITY=verbose'],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',
            env={**db.env,'PGAPPNAME':app})
        second.stdin.write(_transaction(second_sql)+'\n')
        second.stdin.close()
        second.stdin=None
        deadline=time.monotonic()+12
        observed=False
        while second.poll() is None and time.monotonic()<deadline:
            if db.sql(database,f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';")=='1':
                observed=True
                break
            time.sleep(.04)
        if not observed:
            out,error=second.communicate(timeout=3)
            raise AssertionError('La repetición no esperó un bloqueo real: '+error+out)
        first.close(commit=True)
        out,error=second.communicate(timeout=20)
        if second.returncode: raise AssertionError(error+out)
        return {'espera_de_bloqueo_observada':True,'resultado':'misma decisión sin duplicados'}
    finally:
        try: first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill()
                second.communicate()


def _setup(db,database):
    db.sql(database,"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
        (-162001,'Admin D08','d08-admin@example.invalid','!prueba','administrador','activa'),
        (-162002,'Empresa D08','d08-rep@example.invalid','!prueba','empresa','activa'),
        (-162003,'Otra empresa D08','d08-rep2@example.invalid','!prueba','empresa','activa'),
        (-162004,'Admin inactivo D08','d08-inactivo@example.invalid','!prueba','administrador','inactiva');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT id,'Alumno D08 '||id,'d08-a'||abs(id)||'@example.invalid','!prueba','alumno'
      FROM generate_series(-162145,-162101) AS alumnos(id);
      INSERT INTO banco.alumno(usuario_id,matricula)
      SELECT id,'D08-A-'||abs(id) FROM generate_series(-162145,-162101) AS alumnos(id);
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT id,'Profesor D08 '||id,'d08-p'||abs(id)||'@example.invalid','!prueba','profesor'
      FROM generate_series(-162210,-162201) AS profesores(id);
      INSERT INTO banco.profesor(usuario_id,numero_empleado)
      SELECT id,'D08-P-'||abs(id) FROM generate_series(-162210,-162201) AS profesores(id);
      INSERT INTO banco.empresa(id,razon_social) VALUES(-162010,'Empresa ficticia D08'),(-162011,'Otra empresa ficticia D08');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-162002,-162010),(-162003,-162011);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
      SELECT id,-162010,-162002,'Proyecto D08 '||id,'Descripción','Problemática','Objetivos','Justificación','Alcance',1
      FROM generate_series(-162325,-162301) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-162002),-162001,'aprobada','Cupo validado D08')
      FROM banco.proyecto WHERE empresa_id=-162010 ORDER BY id;
      COMMIT;""")
    # Un alumno distinto por candidatura salvo casos explícitos de carga.
    db.sql(database,_transaction(''.join(f"INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES({_c(n)},{_a(n)},{_p(n if n<=25 else n-20)});" for n in range(1,36))))
    db.sql(database,_transaction(''.join(f"INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,experiencia_aplicable,justificacion) VALUES({_r(n)},{_t(min(n,10))},{_p(n)},'Experiencia aplicable','Justificación de dirección');" for n in range(1,11))))


def run(db,database):
    _setup(db,database)
    negatives=0
    # Parámetros, pertenencia y etapas no pueden fabricar una preselección.
    for code,sql in [
        ('23503',_evaluate(-162999)),
        ('23514',_evaluate(_c(1),OTHER_REP)),
        ('23514',_evaluate(_c(1),ADMIN)),
        ('23514',_evaluate(_c(1),score=3)),
        ('23514',_evaluate(_c(1),score=.5)),
        ('23514',_evaluate(_c(1),comments=' \t\n')),
        ('23514',f"SELECT banco.evaluar_candidatura({_c(1)},{REP},'{{}}','Opinión',true);"),
        ('23514',f"SELECT banco.evaluar_candidatura({_c(1)},{REP},'[]','Opinión',true);"),
        ('23514',f"SELECT banco.evaluar_candidatura({_c(1)},{REP},'{{\"tecnico\":false,\"blando\":{{}},\"academico\":{{}}}}','Opinión',true);"),
        ('23514',f"SELECT banco.evaluar_candidatura({_c(1)},{REP},{_literal(_rubric(comment=' \t\n'))},'Opinión',true);"),
        ('55000',f"SELECT banco.preseleccionar_candidatura({_c(1)},{REP});"),
        ('55000',_resolve(_c(1))),
        ('23514',_resolve(_c(1),admin=REP)),
        ('23514',_resolve(_c(1),admin=INACTIVE)),
        ('23514',_resolve(_c(1),reason=' \t\n')),
        ('23514',_resolve(_c(1),result='en_correccion')),
    ]:
        _error(db,database,code,sql)
        negatives+=1
    _assert(db,database,f"SELECT count(*) FROM banco.evaluacion_candidato WHERE candidatura_id={_c(1)};",0,'La validación dejó evaluación parcial')

    first=db.sql(database,_evaluate(_c(1)))
    _assert(db,database,f"SELECT count(*) FROM banco.detalle_evaluacion WHERE evaluacion_id={first};",3,'Rúbrica incompleta')
    event=db.sql(database,f"SELECT banco.preseleccionar_candidatura({_c(1)},{REP});")
    _assert(db,database,f"SELECT banco.preseleccionar_candidatura({_c(1)},{REP});",event,'Preselección repetida duplicada')
    second=db.sql(database,_evaluate(_c(1),recommended=False))
    _assert(db,database,f"SELECT estado||':'||evaluacion_vigente_id||':'||(evento_preseleccion_id IS NULL)::text FROM banco.candidatura WHERE id={_c(1)};",f'evaluada:{second}:true','Reevaluar no invalidó preselección')
    _error(db,database,'23514',f"SELECT banco.preseleccionar_candidatura({_c(1)},{REP});")
    negatives+=1
    # Ni un propietario que restaure punteros antiguos puede reutilizar una
    # preselección anterior como si correspondiera a la última valoración.
    _error(db,database,'23514',_transaction(f"UPDATE banco.candidatura SET estado='preseleccionada',evaluacion_vigente_id={first},evento_preseleccion_id={event} WHERE id={_c(1)};"+_resolve(_c(1))))
    negatives+=1
    _assert(db,database,f"SELECT count(*) FROM banco.evaluacion_candidato WHERE candidatura_id={_c(1)};",2,'Se perdió evaluación histórica')
    for sql in [f"UPDATE banco.evaluacion_candidato SET comentarios='Nuevo' WHERE id={first};",
        f"DELETE FROM banco.detalle_evaluacion WHERE evaluacion_id={first};",
        "UPDATE banco.criterio_evaluacion SET ponderacion=2 WHERE codigo='tecnico';"]:
        _error(db,database,'55000',sql)
        negatives+=1

    # La rúbrica orienta una decisión manual: no crea una nota de corte.
    db.sql(database,_evaluate(_c(1),score=0,recommended=True))
    db.sql(database,f"SELECT banco.preseleccionar_candidatura({_c(1)},{REP});")
    decision=db.sql(database,_resolve(_c(1)))
    _assert(db,database,_resolve(_c(1)),decision,'Repetición no devuelve decisión original')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE candidatura_id={_c(1)} AND decision_id={decision} AND estado='vigente';",1,'Aprobación sin asignación exacta')
    for code,sql in [('55000',_resolve(_c(1),result='rechazada')),('55000',_evaluate(_c(1)))]:
        _error(db,database,code,sql)
        negatives+=1
    # Rechazar directamente no obliga a elaborar evaluaciones ficticias.
    rejected=db.sql(database,_resolve(_c(2),result='rechazada'))
    _assert(db,database,_resolve(_c(2),result='rechazada'),rejected,'Rechazo repetido no idempotente')
    _assert(db,database,f"SELECT count(*) FROM banco.evaluacion_candidato WHERE candidatura_id={_c(2)};",0,'Se inventó evaluación para rechazo')
    _error(db,database,'55000',_resolve(_c(2)))
    negatives+=1
    _error(db,database,'55000',f"UPDATE banco.candidatura SET estado='evaluada' WHERE id={_c(2)};")
    negatives+=1

    # Cada versión D08 exige los tres detalles incluso fuera de la función.
    _error(db,database,'23514',_transaction(f"INSERT INTO banco.evaluacion_candidato(candidatura_id,evaluador_usuario_id,comentarios,recomendacion,version_rubrica) VALUES({_c(3)},{REP},'Comentario','recomendada',1);"))
    negatives+=1
    # Fallo de auditoría: evaluación, selección y asignación deben revertir.
    db.sql(database,"""CREATE FUNCTION banco.fallo_d08_prueba() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.operacion IN ('evaluar_candidatura','preseleccionar_candidatura','resolver_candidatura','resolver_direccion')
        THEN RAISE EXCEPTION 'Fallo inducido D08' USING ERRCODE='P0001'; END IF; RETURN NEW; END $$;
      CREATE TRIGGER tr_fallo_d08_prueba BEFORE INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.fallo_d08_prueba();""")
    _error(db,database,'P0001',_evaluate(_c(3)))
    negatives+=1
    _assert(db,database,f"SELECT estado||':'||(evaluacion_vigente_id IS NULL)::text FROM banco.candidatura WHERE id={_c(3)};",'pendiente_evaluacion:true','Evaluación fallida dejó cambios')
    db.sql(database,'DROP TRIGGER tr_fallo_d08_prueba ON banco.evento_auditoria;')
    db.sql(database,_evaluate(_c(3)))
    db.sql(database,'CREATE TRIGGER tr_fallo_d08_prueba BEFORE INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.fallo_d08_prueba();')
    _error(db,database,'P0001',f"SELECT banco.preseleccionar_candidatura({_c(3)},{REP});")
    negatives+=1
    _assert(db,database,f"SELECT estado||':'||(evento_preseleccion_id IS NULL)::text FROM banco.candidatura WHERE id={_c(3)};",'evaluada:true','Preselección fallida dejó cambios')
    db.sql(database,'DROP TRIGGER tr_fallo_d08_prueba ON banco.evento_auditoria;')
    db.sql(database,f"SELECT banco.preseleccionar_candidatura({_c(3)},{REP});")
    db.sql(database,'CREATE TRIGGER tr_fallo_d08_prueba BEFORE INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.fallo_d08_prueba();')
    _error(db,database,'P0001',_resolve(_c(3)))
    _error(db,database,'P0001',_direction(_r(3)))
    negatives+=2
    _assert(db,database,f"SELECT count(*) FROM banco.decision_administrativa WHERE candidatura_id={_c(3)} OR solicitud_direccion_id={_r(3)};",0,'Auditoría fallida dejó decisión')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE candidatura_id={_c(3)};",0,'Auditoría fallida dejó reserva')
    db.sql(database,'DROP TRIGGER tr_fallo_d08_prueba ON banco.evento_auditoria; DROP FUNCTION banco.fallo_d08_prueba();')

    # Dirección no usa evaluación empresarial y exige solicitud completa.
    dir_decision=db.sql(database,_direction(_r(1)))
    _assert(db,database,_direction(_r(1)),dir_decision,'Dirección repetida duplicada')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_direccion WHERE solicitud_direccion_id={_r(1)} AND decision_id={dir_decision};",1,'Dirección sin asignación exacta')
    _error(db,database,'55000',_direction(_r(1),result='rechazada'))
    negatives+=1
    db.sql(database,f"UPDATE banco.solicitud_direccion SET experiencia_aplicable=E'\\t\\n' WHERE id={_r(2)};")
    _error(db,database,'23514',_direction(_r(2)))
    negatives+=1
    db.sql(database,_direction(_r(2),result='rechazada'))
    _error(db,database,'55000',f"UPDATE banco.solicitud_direccion SET estado='pendiente' WHERE id={_r(2)};")
    negatives+=1
    _error(db,database,'23514',_direction(_r(4),admin=REP))
    _error(db,database,'23514',_direction(_r(4),admin=INACTIVE))
    negatives+=2
    db.sql(database,_transaction(f"""INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
      VALUES(-162399,-162010,{REP},'Proyecto rechazado D08','Descripción','Problemática','Objetivos','Justificación','Alcance',1);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-162399,{REP}),{ADMIN},'rechazada','Rechazo definitivo de prueba');"""))
    _error(db,database,'55000',"UPDATE banco.proyecto SET estado='borrador' WHERE id=-162399;")
    _error(db,database,'55000',"UPDATE banco.proyecto SET titulo='Reescrito' WHERE id=-162399;")
    negatives+=2
    _assert(db,database,"SELECT has_function_privilege('banco_escritura','banco.resolver_candidatura(bigint,bigint,text,text)','EXECUTE');",'f','Se concedió ejecución directa de aplicación')

    concurrent=_concurrent()
    races={}
    # Reevaluar invalida una aprobación que esperaba la versión anterior.
    for n in (4,5,6,7,8,9,10,11,12,26,27):
        db.sql(database,_evaluate(_c(n)))
        db.sql(database,f"SELECT banco.preseleccionar_candidatura({_c(n)},{REP});")
    races['reevaluacion_autorizacion']=concurrent.race(db,database,_evaluate(_c(4)),_resolve(_c(4)),'55000')
    races['autorizacion_reevaluacion']=concurrent.race(db,database,_resolve(_c(5)),_evaluate(_c(5)),'55000')
    races['cancelacion_autorizacion']=concurrent.race(db,database,f"SELECT banco.cancelar_candidatura({_c(6)},{_a(6)});",_resolve(_c(6)),'55000')
    races['autorizacion_cancelacion']=concurrent.race(db,database,_resolve(_c(7)),f"SELECT banco.cancelar_candidatura({_c(7)},{_a(7)});",'55000')
    races['autorizacion_repetida']=_both(db,database,concurrent,_resolve(_c(8)),_resolve(_c(8)))
    _assert(db,database,f"SELECT count(*) FROM banco.decision_administrativa WHERE candidatura_id={_c(8)};",1,'La repetición concurrente duplicó decisión')
    # Candidatura26 comparte proyecto6; la cancelación previa dejó plaza libre.
    db.sql(database,f"UPDATE banco.candidatura SET proyecto_id=proyecto_id WHERE id={_c(26)};")
    # Candidatura27 comparte proyecto7 ya ocupado. El rechazo no deja decisión.
    _error(db,database,'23514',_resolve(_c(27)))
    negatives+=1
    # Proyecto9 compite por la última plaza con alumno adicional.
    db.sql(database,f"INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES(-162499,{_a(40)},{_p(9)});")
    db.sql(database,_evaluate(-162499))
    db.sql(database,f"SELECT banco.preseleccionar_candidatura(-162499,{REP});")
    races['ultima_plaza_autorizaciones']=concurrent.race(db,database,_resolve(_c(9)),_resolve(-162499),'23514')
    _assert(db,database,'SELECT count(*) FROM banco.decision_administrativa WHERE candidatura_id=-162499;',0,'Última plaza fallida dejó decisión')
    # Las pruebas de cierre solo se omiten en el ensayo aislado001-013+016.
    if db.sql(database,"SELECT to_regprocedure('banco.cancelar_proyecto(bigint,bigint,text)') IS NOT NULL;")=='t':
        races['cierre_autorizacion']=concurrent.race(db,database,f"SELECT banco.cancelar_proyecto({_p(10)},{ADMIN},'Cierre simultáneo D08');",_resolve(_c(10)),'55000')
        races['autorizacion_cierre_reintentable']=concurrent.race(db,database,_resolve(_c(11)),f"SELECT banco.cancelar_proyecto({_p(11)},{ADMIN},'Cierre después de nueva asignación');",'40001')
        db.sql(database,f"SELECT banco.cancelar_proyecto({_p(11)},{ADMIN},'Reintento coordinado D08');")
        _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id={_p(11)} AND estado='vigente';",0,'Reintento no cerró asignación ganadora')
    return {'rechazos_secuenciales':negatives,'carreras':races,
      'evaluacion_inmutable_y_reevaluacion':True,'preseleccion_version_exacta':True,
      'decision_asignacion_atomica':True,'auditoria_rollback':True,'direccion_sin_evaluacion_empresa':True}

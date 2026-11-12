"""D-06: límites simultáneos, aprobación atómica y carreras PostgreSQL reales.

Las escrituras directas pertenecen a fixtures del propietario en una base temporal.
No acreditan permisos ni procedimientos de cancelación/revocación de D-07.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path


def _expect_error(db, database, code, statement):
    try:
        db.sql(database, statement)
    except RuntimeError as error:
        if code not in str(error):
            raise AssertionError(f'Se esperaba {code}; se obtuvo: {error}') from error
    else:
        raise AssertionError(f'La operación debía rechazarse con {code}.')


def _assert(db, database, query, expected, message):
    actual = db.sql(database, query)
    if actual != str(expected):
        raise AssertionError(f'{message}: esperado {expected}, obtenido {actual}.')


def _candidate(candidate, student, project, state='pendiente_evaluacion'):
    return f"""INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado)
      VALUES ({candidate},{student},{project},'{state}');"""


def _student_assignment(candidate, assignment, student, project):
    # Cada caso reserva IDs de decisión iguales a los de asignación. Las tablas
    # tienen espacios de identidad separados; no se depende de sus secuencias.
    return f"""UPDATE banco.candidatura SET estado='aprobada' WHERE id={candidate};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
      VALUES ({assignment},-91001,{candidate},'aprobada','Fixture de reserva D-06');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
      VALUES ({assignment},{candidate},{assignment},{student},{project},'2099-01-01 00:00:00+00');"""


def _direction_request(request, teacher, project):
    return f"""INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id)
      VALUES ({request},{teacher},{project});"""


def _teacher_assignment(request, assignment, teacher, project):
    return f"""UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id={request};
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
      VALUES ({assignment},-91001,{request},'aprobada','Fixture de carga D-06');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES ({assignment},{request},{assignment},{teacher},{project},'2099-01-01 00:00:00+00');"""


def _transaction(statement):
    return 'BEGIN;\n' + statement + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;'


def run(db, database):
    """Llamar únicamente en una base temporal propia del ejecutor."""
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-91001,'Admin cupos ficticio','cupos-admin@example.invalid','!prueba','administrador'),
        (-91002,'Empresa cupos ficticia','cupos-rep@example.invalid','!prueba','empresa');
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
      SELECT id,'Alumno cupos ' || id,'cupos-a' || abs(id) || '@example.invalid','!prueba','alumno'
      FROM generate_series(-91115,-91101) AS alumnos(id);
      INSERT INTO banco.alumno(usuario_id,matricula)
      SELECT id,'CUP-A-' || abs(id) FROM generate_series(-91115,-91101) AS alumnos(id);
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-91201,'Profesor cupos uno','cupos-p1@example.invalid','!prueba','profesor'),
        (-91202,'Profesor cupos dos','cupos-p2@example.invalid','!prueba','profesor');
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES (-91201,'CUP-P-1'),(-91202,'CUP-P-2');
      INSERT INTO banco.empresa(id,razon_social) VALUES (-91010,'Empresa ficticia de pruebas de cupos');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-91002,-91010);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos,fecha_inicio_estimada,fecha_fin_estimada)
      SELECT id,-91010,-91002,'Proyecto cupos ' || id,'Descripción','Problemática',
        'Objetivos','Justificación','Alcance',CASE WHEN id=-91310 THEN 2 ELSE 1 END,
        '2020-01-01','2020-06-01'
      FROM generate_series(-91330,-91301) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-91002),-91001,'aprobada','Cupo validado de prueba')
      FROM banco.proyecto WHERE empresa_id=-91010 ORDER BY id;
      COMMIT;""")
    negatives = 0

    # Los tres estados cuentan, y el historial no determina el máximo.
    db.sql(database, _transaction(
        _candidate(-92001,-91101,-91301)
        + _candidate(-92002,-91101,-91302,'evaluada')
        + _candidate(-92003,-91101,-91303,'preseleccionada')
        + ''.join(_candidate(-92010-i,-91101,-91305,'rechazada' if i%2 else 'cancelada') for i in range(5))))
    _expect_error(db,database,'23514',_transaction(_candidate(-92004,-91101,-91304)))
    _expect_error(db,database,'23505',_transaction(_candidate(-92005,-91101,-91301)))
    negatives += 2
    db.sql(database,"UPDATE banco.candidatura SET estado='evaluada' WHERE id=-92001;")
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-91101;",8,'Se alteró el historial')

    # No se puede liberar espacio poniendo aprobada sin formalizar la asignación.
    _expect_error(db,database,'23514',_transaction("UPDATE banco.candidatura SET estado='aprobada' WHERE id=-92001;"))
    _expect_error(db,database,'23514',_transaction("""INSERT INTO banco.decision_administrativa
      (id,administrador_usuario_id,candidatura_id,resultado,justificacion)
      VALUES (-93000,-91001,-92001,'aprobada','Aprobación aislada inválida');"""))
    _expect_error(db,database,'23514',_transaction("""INSERT INTO banco.decision_administrativa
      (id,administrador_usuario_id,candidatura_id,resultado,justificacion)
      VALUES (-93000,-91001,-92001,'aprobada','Origen sin aprobar inválido');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
      VALUES (-93000,-92001,-93000,-91101,-91301,'2099-01-01 00:00:00+00');"""))
    negatives += 3
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-92001;",'evaluada','La aprobación fallida liberó una candidatura')
    _assert(db,database,"SELECT count(*) FROM banco.decision_administrativa WHERE id=-93000;",0,'Persistió una decisión parcial')
    db.sql(database,_transaction(_student_assignment(-92001,-93001,-91101,-91301)))
    db.sql(database,_transaction(_candidate(-92004,-91101,-91304)))
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-91101 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');",3,'Aprobar no liberó espacio activo')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-92003;",'preseleccionada','Aprobar canceló otra candidatura')
    _expect_error(db,database,'23505',_transaction(_student_assignment(-92002,-93002,-91101,-91302)))
    negatives += 1
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-92002;",'evaluada','La segunda asignación no revirtió su origen')
    _assert(db,database,"SELECT count(*) FROM banco.decision_administrativa WHERE id=-93002;",0,'La segunda asignación dejó decisión parcial')

    # Una fecha de inicio futura y una cuenta desactivada siguen reservando carga.
    db.sql(database,"UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-91101;")
    _expect_error(db,database,'23505',_transaction(_student_assignment(-92002,-93002,-91101,-91302)))
    negatives += 1
    _assert(db,database,"SELECT count(*) FROM banco.asignacion_alumno WHERE alumno_id=-91101 AND estado='vigente';",1,'La inactividad o las fechas liberaron carga')
    db.sql(database,_transaction("""UPDATE banco.asignacion_alumno SET estado='finalizada',fin='2100-01-01 00:00:00+00'
      WHERE id=-93001;""" + _student_assignment(-92002,-93002,-91101,-91302)))
    _assert(db,database,"SELECT estado FROM banco.asignacion_alumno WHERE id=-93001;",'finalizada','Se perdió la asignación histórica')
    _assert(db,database,"SELECT count(*) FROM banco.asignacion_alumno WHERE alumno_id=-91101 AND estado='vigente';",1,'La finalización no liberó carga')
    _expect_error(db,database,'55000',"UPDATE banco.candidatura SET estado='preseleccionada' WHERE id=-92001;")
    negatives += 1

    # Liberación técnica de una candidatura cancelada; no acredita el permiso D-07.
    db.sql(database,_transaction("UPDATE banco.candidatura SET estado='cancelada' WHERE id=-92003;"
      + _candidate(-92006,-91101,-91306)))
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-91101 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');",2,'La cancelación técnica no liberó candidatura')

    # El proyecto de dos plazas admite más candidaturas, pero solo dos reservas.
    db.sql(database,_transaction(''.join(_candidate(-92100-i,-91102-i,-91310) for i in range(3))))
    db.sql(database,_transaction(_student_assignment(-92100,-93100,-91102,-91310)
      + _student_assignment(-92101,-93101,-91103,-91310)))
    _expect_error(db,database,'23514',_transaction(_student_assignment(-92102,-93102,-91104,-91310)))
    negatives += 1
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-92102;",'pendiente_evaluacion','La falta de plazas dejó aprobación parcial')
    db.sql(database,_transaction("UPDATE banco.asignacion_alumno SET estado='revocada',fin='2100-01-01 00:00:00+00' WHERE id=-93100;"
      + _student_assignment(-92102,-93102,-91104,-91310)))
    _assert(db,database,"SELECT count(*) || ':' || count(*) FILTER (WHERE estado='vigente') FROM banco.asignacion_alumno WHERE proyecto_id=-91310;",'3:2','La revocación no liberó plaza o borró historia')
    db.sql(database,_transaction(_candidate(-92110,-91102,-91311)+_candidate(-92111,-91105,-91311)
      + _student_assignment(-92110,-93110,-91102,-91311)))
    _expect_error(db,database,'23514',_transaction(_student_assignment(-92111,-93111,-91105,-91311)))
    negatives += 1

    # La carga docente cuenta proyectos autorizados, aun antes de iniciar.
    db.sql(database,_transaction(''.join(_direction_request(-92200-i,-91201,-91312-i) for i in range(5))))
    db.sql(database,_transaction(''.join(_teacher_assignment(-92200-i,-93200-i,-91201,-91312-i) for i in range(3))))
    _expect_error(db,database,'23514',_transaction(_teacher_assignment(-92203,-93203,-91201,-91315)))
    _expect_error(db,database,'23514',_transaction("UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-92204;"))
    negatives += 2
    db.sql(database,"UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-91201;")
    _expect_error(db,database,'23514',_transaction(_teacher_assignment(-92203,-93203,-91201,-91315)))
    negatives += 1
    db.sql(database,_transaction("UPDATE banco.asignacion_direccion SET estado='revocada',fin='2100-01-01 00:00:00+00' WHERE id=-93200;"
      + _teacher_assignment(-92203,-93203,-91201,-91315)))
    db.sql(database,_transaction("UPDATE banco.asignacion_direccion SET estado='finalizada',fin='2100-01-01 00:00:00+00' WHERE id=-93201;"
      + _teacher_assignment(-92204,-93204,-91201,-91316)))
    _assert(db,database,"SELECT count(*) || ':' || count(*) FILTER (WHERE estado='vigente') FROM banco.asignacion_direccion WHERE profesor_id=-91201;",'5:3','La carga docente no preservó historia o no liberó plaza')
    _expect_error(db,database,'55000',"UPDATE banco.solicitud_direccion SET estado='pendiente' WHERE id=-92200;")
    _expect_error(db,database,'25001',"BEGIN ISOLATION LEVEL REPEATABLE READ;" + _candidate(-92999,-91115,-91330) + 'COMMIT;')
    negatives += 2

    # Conexiones distintas y espera real: tercer candidato, última plaza,
    # carga global del alumno y tercer proyecto del profesor.
    spec = importlib.util.spec_from_file_location('concurrencia_cupos',Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    db.sql(database,_transaction(_candidate(-92300,-91106,-91317)+_candidate(-92301,-91106,-91318)))
    races = {}
    races['tercera_candidatura'] = concurrent.race(db,database,
      _candidate(-92302,-91106,-91319),_candidate(-92303,-91106,-91320),'23514')
    _assert(db,database,"SELECT count(*) FROM banco.candidatura WHERE alumno_id=-91106 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');",3,'La carrera excedió tres candidaturas')

    db.sql(database,_transaction(_candidate(-92400,-91107,-91321)+_candidate(-92401,-91108,-91321)))
    races['ultima_plaza_proyecto'] = concurrent.race(db,database,
      _student_assignment(-92400,-93400,-91107,-91321),_student_assignment(-92401,-93401,-91108,-91321),'23514')
    _assert(db,database,"SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=-91321 AND estado='vigente';",1,'La carrera excedió la última plaza')
    _assert(db,database,"SELECT estado FROM banco.candidatura WHERE id=-92401;",'pendiente_evaluacion','La carrera fallida dejó origen aprobado')
    _assert(db,database,"SELECT count(*) FROM banco.decision_administrativa WHERE id=-93401;",0,'La carrera fallida dejó decisión parcial')

    db.sql(database,_transaction(_candidate(-92500,-91109,-91322)+_candidate(-92501,-91109,-91323)))
    races['carga_alumno_entre_proyectos'] = concurrent.race(db,database,
      _student_assignment(-92500,-93500,-91109,-91322),_student_assignment(-92501,-93501,-91109,-91323),'23505')
    _assert(db,database,"SELECT count(*) FROM banco.asignacion_alumno WHERE alumno_id=-91109 AND estado='vigente';",1,'La carrera excedió la carga del alumno')
    _assert(db,database,"SELECT count(*) FROM banco.decision_administrativa WHERE id=-93501;",0,'La segunda asignación concurrente dejó decisión')

    db.sql(database,_transaction(''.join(_direction_request(-92600-i,-91202,-91324-i) for i in range(4))
      + _teacher_assignment(-92600,-93600,-91202,-91324)
      + _teacher_assignment(-92601,-93601,-91202,-91325)))
    races['tercer_proyecto_profesor'] = concurrent.race(db,database,
      _teacher_assignment(-92602,-93602,-91202,-91326),_teacher_assignment(-92603,-93603,-91202,-91327),'23514')
    _assert(db,database,"SELECT count(DISTINCT proyecto_id) FROM banco.asignacion_direccion WHERE profesor_id=-91202 AND estado='vigente';",3,'La carrera excedió la carga docente')
    _assert(db,database,"SELECT estado FROM banco.solicitud_direccion WHERE id=-92603;",'pendiente','La dirección concurrente dejó origen aprobado')
    _assert(db,database,"SELECT count(*) FROM banco.decision_administrativa WHERE id=-93603;",0,'La dirección concurrente dejó decisión parcial')

    return {
      'negativos_secuenciales':negatives,
      'candidaturas':'tres estados activos, historial conservado, unicidad y aprobación con asignación atómica',
      'reservas':'alumno uno global, cupo propio por proyecto y profesor tres proyectos; cuentan desde autorización',
      'liberacion':'finalizada/revocada liberan por estado; fechas y cuentas inactivas no liberan',
      'concurrencia':races,
      'limite':'Fixtures del propietario; no acreditan etapas previas D-08 ni flujos/permisos de cierre D-07.'
    }

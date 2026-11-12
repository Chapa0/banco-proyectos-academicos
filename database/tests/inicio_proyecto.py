"""D-05: inicio sobre autorizaciones coherentes, rollback y concurrencia real."""
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
        raise AssertionError(f'Se aceptó una operación que debía fallar con {code}.')


def _concurrent_module():
    spec = importlib.util.spec_from_file_location('concurrencia_inicio', Path(__file__).with_name('concurrencia.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _same_start(db, database, concurrent):
    """Dos inicios que esperan realmente el mismo lock y devuelven un solo evento."""
    token = uuid.uuid4().hex[:10]
    first = concurrent.Transaction(db, database, 'inicio_a_' + token)
    second = None
    observed = False
    try:
        first.execute('SELECT banco.iniciar_proyecto(-8026,-8001);')
        app = 'inicio_b_' + token
        second = subprocess.Popen(db.command('psql', database) + ['-X', '-qAt', '-v', 'ON_ERROR_STOP=on',
            '-v', 'VERBOSITY=verbose'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', env={**db.env, 'PGAPPNAME': app})
        second.stdin.write('BEGIN; SELECT banco.iniciar_proyecto(-8026,-8001); SET CONSTRAINTS ALL IMMEDIATE; COMMIT;\n')
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
            raise AssertionError('El segundo inicio no esperó el bloqueo: ' + error + output)
        first.close(commit=True)
        output, error = second.communicate(timeout=20)
        if second.returncode:
            raise AssertionError('Falló el inicio idempotente después de esperar: ' + error)
        event = db.sql(database, 'SELECT evento_inicio_id FROM banco.proyecto WHERE id=-8026;')
        if event not in output.splitlines():
            raise AssertionError('La segunda conexión no devolvió el mismo evento de inicio.')
        if db.sql(database, "SELECT count(*) FROM banco.evento_auditoria WHERE operacion='iniciar_proyecto' AND registro_afectado='-8026';") != '1':
            raise AssertionError('Dos inicios concurrentes generaron eventos duplicados.')
        return {'espera_de_bloqueo_observada': True, 'resultado': 'ambos inicios devuelven el mismo evento; una transición'}
    finally:
        try:
            first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill()
                second.communicate()


def run(db, database):
    """Ejecutar únicamente sobre una base temporal propia del ejecutor."""
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
        (-8001,'Admin inicio','inicio-admin@example.invalid','!prueba','administrador','activa'),
        (-8002,'Empresa inicio','inicio-rep@example.invalid','!prueba','empresa','activa'),
        (-8003,'Admin inicio inactivo','inicio-admin-inactivo@example.invalid','!prueba','administrador','inactiva'),
        (-8004,'Alumno inicio uno','inicio-a1@example.invalid','!prueba','alumno','activa'),
        (-8005,'Alumno inicio dos','inicio-a2@example.invalid','!prueba','alumno','activa'),
        (-8006,'Alumno inicio tres','inicio-a3@example.invalid','!prueba','alumno','activa'),
        (-8007,'Alumno inicio cuatro','inicio-a4@example.invalid','!prueba','alumno','activa'),
        (-8008,'Alumno incorporación','inicio-a5@example.invalid','!prueba','alumno','activa'),
        (-8009,'Director inicio uno','inicio-p1@example.invalid','!prueba','profesor','activa'),
        (-8010,'Director inicio dos','inicio-p2@example.invalid','!prueba','profesor','activa'),
        (-8011,'Director incorporación','inicio-p3@example.invalid','!prueba','profesor','activa');
      INSERT INTO banco.alumno(usuario_id,matricula) VALUES
        (-8004,'INI-A-01'),(-8005,'INI-A-02'),(-8006,'INI-A-03'),(-8007,'INI-A-04'),(-8008,'INI-A-05');
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES
        (-8009,'INI-P-01'),(-8010,'INI-P-02'),(-8011,'INI-P-03');
      INSERT INTO banco.empresa(id,razon_social) VALUES (-8015,'Empresa ficticia inicio');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-8002,-8015);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos)
      SELECT id,-8015,-8002,'Inicio ' || id,'Descripción','Problemática','Objetivos','Justificación','Alcance',3
      FROM unnest(ARRAY[-8021::bigint,-8022,-8023,-8024,-8025,-8026]) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-8002),-8001,'aprobada','Cupo de tres validado')
        FROM banco.proyecto WHERE id IN (-8021,-8022,-8023,-8025,-8026) ORDER BY id;
      INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES
        (-8031,-8004,-8021),(-8032,-8005,-8023),(-8033,-8006,-8025),(-8034,-8007,-8026),
        (-8035,-8008,-8021),(-8036,-8004,-8022);
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES
        (-8041,-8009,-8021),(-8042,-8009,-8022),(-8043,-8009,-8025),(-8044,-8010,-8026),
        (-8045,-8011,-8021);
      COMMIT;""")

    # Las fuentes YA autorizadas se preparan juntas con sus decisiones y
    # asignaciones. Esto no prueba etapas institucionales de evaluación D-08.
    db.sql(database, """BEGIN;
      UPDATE banco.candidatura SET estado='aprobada' WHERE id IN (-8031,-8032,-8033,-8034);
      UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id IN (-8041,-8042,-8043,-8044);
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion) VALUES
        (-8051,-8001,-8031,'aprobada','Alumno uno autorizado'),(-8052,-8001,-8032,'aprobada','Alumno dos autorizado'),
        (-8053,-8001,-8033,'aprobada','Alumno tres autorizado'),(-8054,-8001,-8034,'aprobada','Alumno cuatro autorizado');
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion) VALUES
        (-8061,-8001,-8041,'aprobada','Director autorizado'),(-8062,-8001,-8042,'aprobada','Director sin alumno'),
        (-8063,-8001,-8043,'aprobada','Director rollback'),(-8064,-8001,-8044,'aprobada','Director carrera');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES
        (-8071,-8031,-8051,-8004,-8021,'2026-01-01 00:00:00+00'),
        (-8072,-8032,-8052,-8005,-8023,'2026-01-01 00:00:00+00'),
        (-8073,-8033,-8053,-8006,-8025,'2026-01-01 00:00:00+00'),
        (-8074,-8034,-8054,-8007,-8026,'2026-01-01 00:00:00+00');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES
        (-8081,-8041,-8061,-8009,-8021,'2026-01-01 00:00:00+00'),
        (-8082,-8042,-8062,-8009,-8022,'2026-01-01 00:00:00+00'),
        (-8083,-8043,-8063,-8009,-8025,'2026-01-01 00:00:00+00'),
        (-8084,-8044,-8064,-8010,-8026,'2026-01-01 00:00:00+00');
      COMMIT;""")
    if db.sql(database, "SELECT count(*) FROM banco.proyecto WHERE id IN (-8021,-8022,-8023,-8025,-8026) AND estado='publicado' AND evento_inicio_id IS NULL;") != '5':
        raise AssertionError('La última autorización inició automáticamente un proyecto.')

    _error(db, database, '23503', 'SELECT banco.iniciar_proyecto(-8999,-8001);')
    _error(db, database, '55000', 'SELECT banco.iniciar_proyecto(-8024,-8001);')
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8022,-8001);')
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8023,-8001);')
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8021,-8002);')
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8021,-8003);')
    _error(db, database, '23514', "UPDATE banco.proyecto SET estado='en_curso' WHERE id=-8021;")
    _error(db, database, '55000', "INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,estado) VALUES(-8015,-8002,'Inicio sin publicación','en_curso');")
    _error(db, database, '25001', 'BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT banco.iniciar_proyecto(-8021,-8001); COMMIT;')
    # Fabricar una referencia a un evento ajeno no suple la confirmación exacta.
    _error(db, database, '23514', """BEGIN;
      INSERT INTO banco.evento_auditoria(id,actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
      SELECT -8091,-8001,'usuario','iniciar_proyecto','proyecto','-8026','publicado -> en_curso',
        banco.comprobar_condiciones_inicio(p)::text FROM banco.proyecto p WHERE id=-8021;
      UPDATE banco.proyecto SET estado='en_curso',evento_inicio_id=-8091 WHERE id=-8021;
      COMMIT;""")
    _error(db, database, '23514', """BEGIN;
      INSERT INTO banco.evento_auditoria(id,actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
      SELECT -8092,-8002,'usuario','iniciar_proyecto','proyecto','-8021','publicado -> en_curso',
        banco.comprobar_condiciones_inicio(p)::text FROM banco.proyecto p WHERE id=-8021;
      UPDATE banco.proyecto SET estado='en_curso',evento_inicio_id=-8092 WHERE id=-8021;
      COMMIT;""")

    # Probar fallos tanto al escribir la auditoría como después de insertarla:
    # ninguna mitad de la operación puede quedar confirmada.
    for table, timing, trigger_test in (
        ('evento_auditoria', 'BEFORE INSERT', "NEW.operacion='iniciar_proyecto' AND NEW.registro_afectado='-8025'"),
        ('proyecto', 'AFTER UPDATE', "NEW.id=-8025 AND NEW.estado='en_curso'"),
    ):
        db.sql(database, f"""BEGIN;
          CREATE FUNCTION pg_temp.fallar_inicio() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF {trigger_test} THEN RAISE EXCEPTION 'Fallo controlado inicio' USING ERRCODE='P9999'; END IF;
            RETURN NEW;
          END $$;
          CREATE TRIGGER tr_zz_prueba_inicio {timing} ON banco.{table}
            FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_inicio();
          DO $$ BEGIN
            BEGIN
              PERFORM banco.iniciar_proyecto(-8025,-8001);
              RAISE EXCEPTION 'No se propagó el fallo de inicio' USING ERRCODE='P9998';
            EXCEPTION WHEN SQLSTATE 'P9999' THEN NULL;
            END;
            IF (SELECT estado FROM banco.proyecto WHERE id=-8025) <> 'publicado'
              OR (SELECT evento_inicio_id FROM banco.proyecto WHERE id=-8025) IS NOT NULL
              OR EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE operacion='iniciar_proyecto' AND registro_afectado='-8025') THEN
              RAISE EXCEPTION 'El fallo dejó auditoría o inicio parciales';
            END IF;
          END $$;
          DROP TRIGGER tr_zz_prueba_inicio ON banco.{table};
          ROLLBACK;""")

    event = db.sql(database, 'SELECT banco.iniciar_proyecto(-8021,-8001);')
    if db.sql(database, 'SELECT banco.iniciar_proyecto(-8021,-8001);') != event:
        raise AssertionError('Repetir inicio no devolvió el mismo evento.')
    if db.sql(database, """SELECT count(*) FROM banco.proyecto p JOIN banco.evento_auditoria e ON e.id=p.evento_inicio_id
      WHERE p.id=-8021 AND p.estado='en_curso' AND p.cupo_maximo_alumnos=3
        AND p.fecha_inicio_estimada IS NULL AND p.fecha_fin_estimada IS NULL
        AND e.actor_usuario_id=-8001 AND e.fecha IS NOT NULL AND e.operacion='iniciar_proyecto'
        AND e.resultado::jsonb->'cupo_validado'='3'::jsonb
        AND e.resultado::jsonb->'asignaciones_alumno'='[-8071]'::jsonb
        AND e.resultado::jsonb->'asignacion_direccion'='-8081'::jsonb;""") != '1':
        raise AssertionError('El inicio con cupo parcial no conservó actor/fecha/condiciones exactas.')
    if db.sql(database, "SELECT count(*) FROM banco.evento_auditoria WHERE operacion='iniciar_proyecto' AND registro_afectado='-8021';") != '1':
        raise AssertionError('Repetir inicio duplicó la auditoría.')
    if db.sql(database, "SELECT estado FROM banco.candidatura WHERE id=-8036;") != 'pendiente_evaluacion':
        raise AssertionError('Iniciar canceló otra candidatura del alumno.')
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8021,-8003);')
    _error(db, database, '55000', "UPDATE banco.proyecto SET evento_inicio_id=NULL WHERE id=-8021;")
    _error(db, database, '55000', "UPDATE banco.proyecto SET estado='publicado' WHERE id=-8021;")
    _error(db, database, '55000', "UPDATE banco.proyecto SET estado='finalizado' WHERE id=-8021;")
    _error(db, database, '55000', "UPDATE banco.proyecto SET estado='cancelado' WHERE id=-8021;")
    _error(db, database, '55000', 'UPDATE banco.proyecto SET cupo_maximo_alumnos=4 WHERE id=-8021;')
    _error(db, database, '55000', "UPDATE banco.asignacion_alumno SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-8071;")
    _error(db, database, '55000', "UPDATE banco.asignacion_direccion SET estado='revocada',fin='2026-02-01 00:00:00+00' WHERE id=-8081;")
    _error(db, database, '55000', """BEGIN;
      UPDATE banco.candidatura SET estado='aprobada' WHERE id=-8035;
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
        VALUES(-8055,-8001,-8035,'aprobada','No habilitar incorporación posterior');
      INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES(-8035,-8055,-8008,-8021,'2026-01-01 00:00:00+00');
      COMMIT;""")
    if db.sql(database, "SELECT estado || ':' || (SELECT count(*) FROM banco.decision_administrativa WHERE id=-8055) FROM banco.candidatura WHERE id=-8035;") != 'pendiente_evaluacion:0':
        raise AssertionError('La incorporación rechazada dejó una aprobación o decisión parcial.')
    db.sql(database, """BEGIN;
      UPDATE banco.proyecto SET titulo=titulo WHERE id=-8021;
      UPDATE banco.asignacion_alumno SET estado=estado WHERE id=-8071;
      UPDATE banco.asignacion_direccion SET estado=estado WHERE id=-8081;
      UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-8001;
      UPDATE banco.proyecto SET titulo=titulo WHERE id=-8021;
      COMMIT;""")
    _error(db, database, '23514', 'SELECT banco.iniciar_proyecto(-8021,-8001);')
    db.sql(database, "UPDATE banco.usuario SET estado_cuenta='activa' WHERE id=-8001;")
    if db.sql(database, "SELECT estado || ':' || evento_inicio_id FROM banco.proyecto WHERE id=-8021;") != 'en_curso:' + event:
        raise AssertionError('La desactivación posterior alteró el inicio histórico.')
    if db.sql(database, "SELECT has_function_privilege('banco_escritura','banco.iniciar_proyecto(bigint,bigint)','EXECUTE') OR has_function_privilege('banco_lectura','banco.iniciar_proyecto(bigint,bigint)','EXECUTE');") != 'f':
        raise AssertionError('Se habilitó ejecución de inicio a una cuenta técnica sin su integración web.')

    concurrent = _concurrent_module()
    same = _same_start(db, database, concurrent)
    close = concurrent.race(db, database,
        'SELECT banco.iniciar_proyecto(-8025,-8001);',
        "UPDATE banco.asignacion_alumno SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-8073;", '55000')
    if db.sql(database, "SELECT p.estado || ':' || a.estado FROM banco.proyecto p JOIN banco.asignacion_alumno a ON a.proyecto_id=p.id WHERE p.id=-8025;") != 'en_curso:vigente':
        raise AssertionError('El cierre concurrente hizo perder la asignación requerida al iniciar.')

    # Orden inverso, con un proyecto y participantes propios: el cierre técnico
    # del único alumno obtiene primero el lock. Al esperar y revalidar, el inicio
    # debe rechazar la falta de alumno sin registrar una transición parcial.
    # El fixture no habilita ni acredita el procedimiento institucional de D-07.
    db.sql(database, """BEGIN;
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos)
        VALUES(-8027,-8015,-8002,'Cierre anterior al inicio','Descripción','Problemática',
          'Objetivos','Justificación','Alcance',3);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-8027,-8002),-8001,'aprobada','Cupo validado de carrera inversa');
      INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado)
        VALUES(-8037,-8008,-8027,'aprobada');
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado)
        VALUES(-8047,-8011,-8027,'aprobada');
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
        VALUES(-8057,-8001,-8037,'aprobada','Alumno de carrera inversa autorizado');
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES(-8067,-8001,-8047,'aprobada','Director de carrera inversa autorizado');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES(-8077,-8037,-8057,-8008,-8027,'2026-01-01 00:00:00+00');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES(-8087,-8047,-8067,-8011,-8027,'2026-01-01 00:00:00+00');
      COMMIT;""")
    close_first = concurrent.race(db, database,
        "UPDATE banco.asignacion_alumno SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-8077;",
        'SELECT banco.iniciar_proyecto(-8027,-8001);', '23514')
    if db.sql(database, "SELECT estado || ':' || coalesce(evento_inicio_id::text,'nulo') FROM banco.proyecto WHERE id=-8027;") != 'publicado:nulo':
        raise AssertionError('El inicio posterior al cierre alteró el estado o dejó evidencia parcial.')
    if db.sql(database, "SELECT count(*) FROM banco.evento_auditoria WHERE operacion='iniciar_proyecto' AND registro_afectado='-8027';") != '0':
        raise AssertionError('El inicio posterior al cierre dejó un evento exitoso parcial.')
    if db.sql(database, "SELECT estado FROM banco.asignacion_alumno WHERE id=-8077;") != 'finalizada':
        raise AssertionError('El rechazo del inicio alteró el cierre previamente confirmado.')
    return {
        'condiciones': 'publicación y cupo validados, un alumno y un director con aprobación/origen exactos; actor activo',
        'cupo_parcial': 'un alumno para tres plazas; sin fechas estimadas obligatorias ni inicio automático',
        'rollback': 'fallo al insertar auditoría y fallo posterior a insertarla revierten toda la operación',
        'idempotencia': 'mismo evento; sin auditoría duplicada',
        'inicio_concurrente': same,
        'inicio_y_cierre': close,
        'cierre_y_inicio': close_first,
        'protecciones': 'sin inicio por CRUD sin evidencia; contenido, evidencia y asignaciones iniciadas preservadas; permisos mínimos',
        'limites': 'Opera sobre autorizaciones ya coherentes; no implementa evaluación previa D-08 ni cierres/incorporaciones D-07.'
    }

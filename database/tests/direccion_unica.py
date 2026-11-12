"""D-03: dirección única, historial y dos autorizaciones concurrentes reales."""
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
        raise AssertionError(f'Se aceptó una operación que debía fallar con {code}.')


def run(db, database):
    """Usar solo en una base temporal creada y eliminada por el ejecutor."""
    db.sql(database, """BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-7101,'Admin dirección única','direccion-admin@example.invalid','!prueba','administrador'),
        (-7102,'Empresa dirección única','direccion-rep@example.invalid','!prueba','empresa'),
        (-7103,'Director uno','direccion-p1@example.invalid','!prueba','profesor'),
        (-7104,'Director dos','direccion-p2@example.invalid','!prueba','profesor'),
        (-7105,'Director tres','direccion-p3@example.invalid','!prueba','profesor'),
        (-7106,'Director cuatro','direccion-p4@example.invalid','!prueba','profesor');
      INSERT INTO banco.empresa(id,razon_social) VALUES (-7110,'Empresa ficticia dirección única');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-7102,-7110);
      INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES
        (-7103,'DU-P-01'),(-7104,'DU-P-02'),(-7105,'DU-P-03'),(-7106,'DU-P-04');
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos)
      SELECT id,-7110,-7102,'Dirección única ' || id,'Descripción','Problemática',
        'Objetivos','Justificación','Alcance',2
      FROM unnest(ARRAY[-7121::bigint,-7122,-7123]) AS proyectos(id);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-7121,-7102),-7101,'aprobada','Proyecto de prueba');
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-7122,-7102),-7101,'aprobada','Proyecto de prueba');
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(-7123,-7102),-7101,'aprobada','Proyecto de prueba');
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado) VALUES
        (-7131,-7103,-7121,'pendiente'),(-7132,-7104,-7121,'pendiente'),
        (-7133,-7103,-7122,'pendiente'),(-7136,-7105,-7123,'pendiente'),
        (-7137,-7106,-7123,'pendiente');
      COMMIT;""")
    if db.sql(database, 'SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=-7121;') != '0':
        raise AssertionError('Un proyecto sin dirección previa recibió una asignación automática.')
    db.sql(database, """BEGIN;
      UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id IN (-7131,-7133);
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES (-7141,-7101,-7131,'aprobada','Primera dirección'),
               (-7143,-7101,-7133,'aprobada','Dirección de otro proyecto');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES (-7151,-7131,-7141,-7103,-7121,'2026-01-01 00:00:00+00'),
               (-7153,-7133,-7143,-7103,-7122,'2026-01-01 00:00:00+00');
      COMMIT;""")

    # La decisión de la segunda autorización se revierte junto con la asignación.
    _expect_error(db, database, '23505', """BEGIN;
      UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-7132;
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES (-7142,-7101,-7132,'aprobada','Segunda dirección incompatible');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES (-7152,-7132,-7142,-7104,-7121,'2026-01-01 00:00:00+00');
      COMMIT;""")
    if db.sql(database, 'SELECT count(*) FROM banco.decision_administrativa WHERE id=-7142;') != '0':
        raise AssertionError('La autorización fallida dejó una decisión parcial.')
    if db.sql(database, 'SELECT estado FROM banco.solicitud_direccion WHERE id=-7132;') != 'pendiente':
        raise AssertionError('La autorización fallida no revirtió el estado de la solicitud.')
    if db.sql(database, "SELECT count(*) FROM banco.asignacion_direccion WHERE profesor_id=-7103 AND estado='vigente';") != '2':
        raise AssertionError('D-03 impidió dirigir proyectos distintos o alteró una dirección previa.')

    # Son datos técnicos cerrados para comprobar el historial, no una operación
    # institucional de revocación/sustitución, todavía pendiente en D-07.
    db.sql(database, """BEGIN;
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado) VALUES
        (-7134,-7104,-7121,'aprobada'),(-7135,-7105,-7121,'aprobada');
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
        VALUES (-7144,-7101,-7134,'aprobada','Historia técnica finalizada'),
               (-7145,-7101,-7135,'aprobada','Historia técnica revocada');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio,fin,estado)
        VALUES (-7154,-7134,-7144,-7104,-7121,'2025-01-01 00:00:00+00','2025-02-01 00:00:00+00','finalizada'),
               (-7155,-7135,-7145,-7105,-7121,'2025-03-01 00:00:00+00','2025-04-01 00:00:00+00','revocada');
      COMMIT;""")
    _expect_error(db, database, '55000', """UPDATE banco.asignacion_direccion
      SET estado='vigente',fin=NULL WHERE id=-7154;""")
    if db.sql(database, "SELECT count(*) || ':' || count(*) FILTER (WHERE estado='vigente') FROM banco.asignacion_direccion WHERE proyecto_id=-7121;") != '3:1':
        raise AssertionError('El máximo vigente eliminó o alteró las direcciones históricas.')

    spec = importlib.util.spec_from_file_location('concurrencia_direccion', Path(__file__).with_name('concurrencia.py'))
    concurrent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(concurrent)
    first = """UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-7136;
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
      VALUES (-7146,-7101,-7136,'aprobada','Dirección concurrente A');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES (-7156,-7136,-7146,-7105,-7123,'2026-01-01 00:00:00+00');"""
    second = """UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-7137;
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
      VALUES (-7147,-7101,-7137,'aprobada','Dirección concurrente B');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES (-7157,-7137,-7147,-7106,-7123,'2026-01-01 00:00:00+00');"""
    race = concurrent.race(db, database, first, second, '23505')
    if db.sql(database, "SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=-7123 AND estado='vigente';") != '1':
        raise AssertionError('Dos autorizaciones concurrentes dejaron más de una dirección vigente.')
    if db.sql(database, 'SELECT count(*) FROM banco.decision_administrativa WHERE id=-7147;') != '0':
        raise AssertionError('La autorización concurrente rechazada dejó una decisión parcial.')
    if db.sql(database, 'SELECT estado FROM banco.solicitud_direccion WHERE id=-7137;') != 'pendiente':
        raise AssertionError('La autorización concurrente rechazada no revirtió el estado de origen.')
    return {
        'segunda_direccion_vigente': '23505; decisión y asignación revertidas',
        'proyectos_distintos': 'un profesor conserva dos direcciones de proyectos diferentes',
        'historial': 'finalizada y revocada conservadas junto con una vigente; reactivación rechazada con 55000',
        'concurrencia': race,
        'limite': 'Integridad D-03; los datos históricos de prueba no acreditan el flujo de cierres o sustituciones de D-07.'
    }

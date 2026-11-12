-- Publicación inicial: RF-08/RN-02/RN-09 y cupo D-02. Datos ficticios; no define D-07.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
-- Rojo inequívoco contra 001/002: la función de envío todavía no existe.
DO $$ BEGIN
  IF to_regprocedure('banco.enviar_proyecto(bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'Falta banco.enviar_proyecto(bigint,bigint)' USING ERRCODE='42883';
  END IF;
END $$;
CREATE FUNCTION pg_temp.proyecto_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean := false;
BEGIN
  BEGIN
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> codigo THEN
      RAISE EXCEPTION 'Esperado %, obtenido %: %; SQL: %',codigo,SQLSTATE,SQLERRM,sentencia;
    END IF;
    observado := true;
  END;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;
INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
 (-6001,'Admin publicación','pub-admin@example.invalid','ficticio','administrador'),
 (-6002,'Representante publicación','pub-empresa1@example.invalid','ficticio','empresa'),
 (-6003,'Representante ajeno','pub-empresa2@example.invalid','ficticio','empresa'),
 (-6004,'Alumno publicación','pub-alumno@example.invalid','ficticio','alumno'),
 (-6005,'Profesor publicación','pub-profesor@example.invalid','ficticio','profesor');
INSERT INTO banco.empresa(id,razon_social) VALUES (-6011,'Empresa publicación'),(-6012,'Empresa ajena');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-6002,-6011),(-6003,-6012);
INSERT INTO banco.alumno(usuario_id,matricula) VALUES (-6004,'PUB-A-01');
INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES (-6005,'PUB-P-01');
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo)
VALUES (-6021,-6011,-6002,'Borrador incompleto');
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
SELECT id,-6011,-6002,'Proyecto ' || id,'Descripción','Problemática','Objetivos','Justificación','Alcance',2
FROM unnest(ARRAY[-6022::bigint,-6023,-6024,-6025,-6026,-6027]) AS ids(id);
SELECT pg_temp.proyecto_error('23514',$s$UPDATE banco.proyecto SET estado='publicado' WHERE id=-6025$s$);
SELECT pg_temp.proyecto_error('23514',$s$UPDATE banco.proyecto SET estado='en_curso' WHERE id=-6025$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.proyecto SET estado='finalizado' WHERE id=-6025$s$);
SELECT pg_temp.proyecto_error('55000',$s$INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,estado) VALUES (-6011,-6002,'Ciclo no habilitado','en_curso')$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.enviar_proyecto(-6021,-6002)$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.enviar_proyecto(-6022,-6003)$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.enviar_proyecto(-6022,-6004)$s$);
SELECT pg_temp.proyecto_error('23503',$s$SELECT banco.enviar_proyecto(-6999,-6002)$s$);

INSERT INTO banco.habilidad(id,nombre,tipo,descripcion) VALUES (-6031,'Capacidad original','dura','Descripción original');
INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria)
VALUES (-6022,-6031,'Nivel indicado',true);
CREATE TEMP TABLE publicaciones_prueba(proyecto_id bigint PRIMARY KEY,revision_id bigint,decision_id bigint) ON COMMIT DROP;
INSERT INTO publicaciones_prueba(proyecto_id,revision_id) VALUES (-6022,banco.enviar_proyecto(-6022,-6002));
DO $$ DECLARE v_revision banco.revision_proyecto%ROWTYPE; BEGIN
  SELECT r.* INTO v_revision FROM banco.revision_proyecto r JOIN publicaciones_prueba p ON p.revision_id=r.id WHERE p.proyecto_id=-6022;
  IF v_revision.estado_revision <> 'en_revision' OR v_revision.numero <> 1
    OR v_revision.instantanea_contenido->>'version_formato' <> '2'
    OR v_revision.instantanea_contenido->'proyecto'->>'titulo' <> 'Proyecto -6022'
    OR v_revision.instantanea_contenido->'habilidades'->0->>'nombre' <> 'Capacidad original'
    OR v_revision.instantanea_contenido->'habilidades'->0->>'nivel_minimo' <> 'Nivel indicado'
    OR (SELECT estado FROM banco.proyecto WHERE id=-6022) <> 'en_revision' THEN
    RAISE EXCEPTION 'El envío no conserva contenido, habilidades, número y estados';
  END IF;
END $$;
SELECT pg_temp.proyecto_error('55000',$s$SELECT banco.enviar_proyecto(-6022,-6002)$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.proyecto SET descripcion='Edición durante revisión' WHERE id=-6022$s$);
SELECT pg_temp.proyecto_error('55000',$s$DELETE FROM banco.proyecto_habilidad WHERE proyecto_id=-6022$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6022),-6002,'aprobada','Actor incorrecto')$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6022),-6001,'aprobada',' ')$s$);
SELECT pg_temp.proyecto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6022),-6001,'ignorada','Resultado inválido')$s$);
UPDATE publicaciones_prueba SET decision_id=banco.resolver_publicacion(revision_id,-6001,'aprobada','Cumple revisión inicial') WHERE proyecto_id=-6022;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM publicaciones_prueba t
    JOIN banco.proyecto p ON p.id=t.proyecto_id AND p.revision_publicada_id=t.revision_id AND p.estado='publicado'
    JOIN banco.revision_proyecto r ON r.id=t.revision_id AND r.estado_revision='aprobada'
    JOIN banco.decision_administrativa d ON d.id=t.decision_id AND d.revision_proyecto_id=r.id
      AND d.resultado='aprobada' AND d.administrador_usuario_id=-6001 AND btrim(d.justificacion) <> '' AND d.fecha IS NOT NULL
    WHERE t.proyecto_id=-6022) THEN
    RAISE EXCEPTION 'Publicación sin aprobación exacta, administrador, fecha o motivo';
  END IF;
  IF (SELECT count(*) FROM banco.evento_auditoria WHERE entidad_afectada='proyecto' AND registro_afectado='-6022'
    AND operacion IN ('enviar_proyecto','resolver_publicacion')) <> 2 THEN
    RAISE EXCEPTION 'Envío y publicación no conservaron ambos eventos';
  END IF;
END $$;
SELECT pg_temp.proyecto_error('55000',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6022),-6001,'aprobada','Repetido')$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.proyecto SET descripcion='Cambio publicado' WHERE id=-6022$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.proyecto SET revision_publicada_id=NULL WHERE id=-6022$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.proyecto_habilidad SET nivel_minimo='Otro nivel' WHERE proyecto_id=-6022$s$);
SELECT pg_temp.proyecto_error('55000',$s$UPDATE banco.revision_proyecto SET estado_revision='rechazada' WHERE id=(SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6022)$s$);
SELECT pg_temp.proyecto_error('55000',$s$SELECT banco.enviar_proyecto(-6022,-6002)$s$);
-- El catálogo puede evolucionar; la publicación sigue interpretándose con su instantánea.
UPDATE banco.habilidad SET nombre='Nombre posterior' WHERE id=-6031;
DO $$ BEGIN
  IF (SELECT r.instantanea_contenido->'habilidades'->0->>'nombre' FROM banco.revision_proyecto r
      JOIN publicaciones_prueba p ON p.revision_id=r.id WHERE p.proyecto_id=-6022) <> 'Capacidad original' THEN
    RAISE EXCEPTION 'Cambió la interpretación histórica de las habilidades';
  END IF;
END $$;

-- Corrección y reenvío generan una segunda revisión; no reescriben la primera.
INSERT INTO publicaciones_prueba(proyecto_id,revision_id) VALUES (-6023,banco.enviar_proyecto(-6023,-6002));
UPDATE publicaciones_prueba SET decision_id=banco.resolver_publicacion(revision_id,-6001,'en_correccion','Precise el alcance') WHERE proyecto_id=-6023;
UPDATE banco.proyecto SET alcance='Alcance corregido' WHERE id=-6023;
UPDATE publicaciones_prueba SET revision_id=banco.enviar_proyecto(-6023,-6002),decision_id=NULL WHERE proyecto_id=-6023;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-6023 AND numero=1 AND estado_revision='en_correccion'
    AND instantanea_contenido->'proyecto'->>'alcance'='Alcance')
    OR NOT EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-6023 AND numero=2 AND estado_revision='en_revision'
    AND instantanea_contenido->'proyecto'->>'alcance'='Alcance corregido') THEN
    RAISE EXCEPTION 'Corrección/reenvío reescribió o perdió revisiones';
  END IF;
END $$;
UPDATE publicaciones_prueba SET decision_id=banco.resolver_publicacion(revision_id,-6001,'aprobada','Corrección suficiente') WHERE proyecto_id=-6023;
SELECT pg_temp.proyecto_error('23514',$s$UPDATE banco.proyecto SET estado='publicado',revision_publicada_id=(SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6023) WHERE id=-6025$s$);

INSERT INTO publicaciones_prueba(proyecto_id,revision_id) VALUES (-6024,banco.enviar_proyecto(-6024,-6002));
UPDATE publicaciones_prueba SET decision_id=banco.resolver_publicacion(revision_id,-6001,'rechazada','Motivo de rechazo ficticio') WHERE proyecto_id=-6024;
DO $$ BEGIN
  IF (SELECT estado FROM banco.proyecto WHERE id=-6024) <> 'rechazado'
    OR (SELECT revision_publicada_id FROM banco.proyecto WHERE id=-6024) IS NOT NULL THEN
    RAISE EXCEPTION 'Un rechazo publicó el proyecto';
  END IF;
END $$;

-- Una fila de revisión marcada aprobada sin decisión administrativa no basta.
INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,estado_revision,instantanea_contenido)
VALUES (-6027,-6002,1,'aprobada',banco.instantanea_proyecto(-6027));
SELECT pg_temp.proyecto_error('23514',$s$UPDATE banco.proyecto SET estado='publicado',revision_publicada_id=(SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-6027) WHERE id=-6027$s$);

-- Fallar al registrar auditoría debe revertir decisión, publicación y revisión.
INSERT INTO publicaciones_prueba(proyecto_id,revision_id) VALUES (-6026,banco.enviar_proyecto(-6026,-6002));
CREATE FUNCTION pg_temp.fallar_auditoria_publicacion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.operacion='resolver_publicacion' AND NEW.registro_afectado='-6026' THEN
    RAISE EXCEPTION 'Fallo controlado de auditoría' USING ERRCODE='P9999';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_fallo_auditoria BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_auditoria_publicacion();
SELECT pg_temp.proyecto_error('P9999',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM publicaciones_prueba WHERE proyecto_id=-6026),-6001,'aprobada','Se debe revertir')$s$);
DROP TRIGGER tr_prueba_fallo_auditoria ON banco.evento_auditoria;
DO $$ BEGIN
  IF (SELECT estado FROM banco.proyecto WHERE id=-6026) <> 'en_revision'
    OR (SELECT revision_publicada_id FROM banco.proyecto WHERE id=-6026) IS NOT NULL
    OR EXISTS (SELECT 1 FROM banco.decision_administrativa d JOIN publicaciones_prueba p ON p.revision_id=d.revision_proyecto_id WHERE p.proyecto_id=-6026)
    OR NOT EXISTS (SELECT 1 FROM banco.revision_proyecto r JOIN publicaciones_prueba p ON p.revision_id=r.id WHERE p.proyecto_id=-6026 AND r.estado_revision='en_revision') THEN
    RAISE EXCEPTION 'El fallo de auditoría dejó efectos parciales de publicación';
  END IF;
END $$;

INSERT INTO banco.candidatura(id,alumno_id,proyecto_id) VALUES (-6041,-6004,-6022),(-6042,-6004,-6026);
INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id) VALUES (-6051,-6005,-6022),(-6052,-6005,-6026);
SELECT pg_temp.proyecto_error('23514',$s$
 UPDATE banco.candidatura SET estado='aprobada' WHERE id=-6042;
 INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
 VALUES (-6062,-6001,-6042,'aprobada','Proyecto sin publicar');
 INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-6042,-6062,-6004,-6026,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.proyecto_error('23514',$s$
 UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-6052;
 INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
 VALUES (-6064,-6001,-6052,'aprobada','Dirección sin publicar');
 INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES (-6052,-6064,-6005,-6026,'2026-01-01 00:00:00+00')$s$);
UPDATE banco.candidatura SET estado='aprobada' WHERE id=-6041;
UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-6051;
INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,solicitud_direccion_id,resultado,justificacion) VALUES
 (-6061,-6001,-6041,NULL,'aprobada','Asignación publicada'),
 (-6063,-6001,NULL,-6051,'aprobada','Dirección publicada');
INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-6041,-6061,-6004,-6022,'2026-01-01 00:00:00+00');
INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES (-6051,-6063,-6005,-6022,'2026-01-01 00:00:00+00');
DO $$ BEGIN
  IF has_function_privilege('banco_lectura','banco.enviar_proyecto(bigint,bigint)','EXECUTE')
    OR has_function_privilege('banco_escritura','banco.resolver_publicacion(bigint,bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Las funciones internas fueron expuestas a cuentas técnicas';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'Publicación inicial, versión aprobada e integridad al asignar: correcto' AS resultado;
ROLLBACK;

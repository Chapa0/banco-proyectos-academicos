-- D-02: cupo propuesto, revisión exacta y validación al aprobar la publicación.
-- Datos ficticios, todo se revierte. No acredita todavía conteos de ocupación.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.cupo_error(codigo text,sentencia text)
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

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-7001,'Admin cupo','cupo-admin@example.invalid','ficticio','administrador','activa'),
 (-7002,'Representante cupo','cupo-empresa1@example.invalid','ficticio','empresa','activa'),
 (-7003,'Representante ajeno','cupo-empresa2@example.invalid','ficticio','empresa','activa'),
 (-7004,'Admin inactivo','cupo-admin-inactivo@example.invalid','ficticio','administrador','inactiva');
INSERT INTO banco.empresa(id,razon_social) VALUES (-7011,'Empresa cupo'),(-7012,'Empresa ajena cupo');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-7002,-7011),(-7003,-7012);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance)
SELECT id,-7011,-7002,'Proyecto cupo ' || id,'Descripción','Problemática','Objetivos','Justificación','Alcance'
FROM unnest(ARRAY[-7021::bigint,-7022,-7023,-7024,-7025,-7026,-7027,-7028]) AS ids(id);

-- Un borrador puede estar incompleto; no se inventa una plaza por defecto.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM banco.proyecto WHERE id BETWEEN -7028 AND -7021 AND cupo_maximo_alumnos IS NOT NULL) THEN
    RAISE EXCEPTION 'Se asignó un cupo por defecto no acordado';
  END IF;
END $$;
SELECT pg_temp.cupo_error('23514',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=0 WHERE id=-7021$s$);
SELECT pg_temp.cupo_error('23514',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=-1 WHERE id=-7021$s$);
SELECT pg_temp.cupo_error('22P02',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos='sin cupo' WHERE id=-7021$s$);
SELECT pg_temp.cupo_error('23514',$s$SELECT banco.enviar_proyecto(-7021,-7002)$s$);
DO $$ BEGIN
  IF (SELECT estado FROM banco.proyecto WHERE id=-7021) <> 'borrador'
    OR EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-7021)
    OR EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE entidad_afectada='proyecto' AND registro_afectado='-7021') THEN
    RAISE EXCEPTION 'Un envío sin cupo dejó revisión, auditoría o estado parcial';
  END IF;
END $$;

UPDATE banco.proyecto SET cupo_maximo_alumnos=3 WHERE id=-7022;
UPDATE banco.proyecto SET cupo_maximo_alumnos=5 WHERE id=-7023;
UPDATE banco.proyecto SET cupo_maximo_alumnos=2 WHERE id IN (-7024,-7027);
CREATE TEMP TABLE cupos_prueba(proyecto_id bigint PRIMARY KEY,revision_id bigint,decision_id bigint) ON COMMIT DROP;
INSERT INTO cupos_prueba(proyecto_id,revision_id) VALUES (-7022,banco.enviar_proyecto(-7022,-7002));
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM cupos_prueba t JOIN banco.revision_proyecto r ON r.id=t.revision_id
    WHERE t.proyecto_id=-7022 AND r.instantanea_contenido->>'version_formato'='2'
    AND r.instantanea_contenido->'proyecto'->'cupo_maximo_alumnos'='3'::jsonb
    AND r.instantanea_contenido->'habilidades'='[]'::jsonb) THEN
    RAISE EXCEPTION 'El envío no conserva cupo exacto, formato v2 y habilidades opcionales';
  END IF;
END $$;
SELECT pg_temp.cupo_error('55000',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=4 WHERE id=-7022$s$);
SELECT pg_temp.cupo_error('55000',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=NULL WHERE id=-7022$s$);
SELECT pg_temp.cupo_error('55000',$s$UPDATE banco.revision_proyecto SET instantanea_contenido=jsonb_set(instantanea_contenido,'{proyecto,cupo_maximo_alumnos}','4') WHERE id=(SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7022)$s$);
SELECT pg_temp.cupo_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7022),-7002,'aprobada','Empresa no valida')$s$);
SELECT pg_temp.cupo_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7022),-7004,'aprobada','Admin inactivo')$s$);
UPDATE cupos_prueba SET decision_id=banco.resolver_publicacion(revision_id,-7001,'aprobada','Se valida cupo propuesto de tres alumnos')
WHERE proyecto_id=-7022;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM cupos_prueba t
    JOIN banco.proyecto p ON p.id=t.proyecto_id AND p.estado='publicado' AND p.revision_publicada_id=t.revision_id AND p.cupo_maximo_alumnos=3
    JOIN banco.revision_proyecto r ON r.id=t.revision_id AND r.estado_revision='aprobada'
      AND r.instantanea_contenido->'proyecto'->'cupo_maximo_alumnos'='3'::jsonb
    JOIN banco.decision_administrativa d ON d.id=t.decision_id AND d.revision_proyecto_id=r.id
      AND d.administrador_usuario_id=-7001 AND d.resultado='aprobada' AND d.fecha IS NOT NULL
    WHERE t.proyecto_id=-7022)
    OR NOT EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE operacion='resolver_publicacion'
      AND registro_afectado='-7022' AND actor_usuario_id=-7001 AND resultado LIKE '%cupo_validado=3') THEN
    RAISE EXCEPTION 'Falta trazabilidad del cupo validado, revisión, administrador, fecha o auditoría';
  END IF;
  PERFORM banco.exigir_publicacion_valida(p) FROM banco.proyecto p WHERE p.id=-7022;
END $$;
SELECT pg_temp.cupo_error('55000',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=4 WHERE id=-7022$s$);
SELECT pg_temp.cupo_error('55000',$s$UPDATE banco.proyecto SET cupo_maximo_alumnos=NULL WHERE id=-7022$s$);

-- El administrador devuelve para modificar la propuesta; cada envío conserva
-- su cupo y motivo, sin reescribir la propuesta anterior de la empresa.
INSERT INTO cupos_prueba(proyecto_id,revision_id) VALUES (-7023,banco.enviar_proyecto(-7023,-7002));
UPDATE cupos_prueba SET decision_id=banco.resolver_publicacion(revision_id,-7001,'en_correccion','Revisar capacidad propuesta') WHERE proyecto_id=-7023;
UPDATE banco.proyecto SET cupo_maximo_alumnos=2 WHERE id=-7023;
INSERT INTO cupos_prueba(proyecto_id,revision_id) VALUES (-7024,banco.enviar_proyecto(-7024,-7002));
-- Una versión de otro proyecto no valida capacidad, aunque tenga el mismo cupo.
SELECT pg_temp.cupo_error('23514',$s$UPDATE banco.proyecto SET estado='publicado',revision_publicada_id=(SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7022) WHERE id=-7023$s$);
UPDATE cupos_prueba SET revision_id=banco.enviar_proyecto(-7023,-7002),decision_id=NULL WHERE proyecto_id=-7023;
UPDATE cupos_prueba SET decision_id=banco.resolver_publicacion(revision_id,-7001,'aprobada','Se valida propuesta corregida de dos') WHERE proyecto_id=-7023;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-7023 AND numero=1 AND estado_revision='en_correccion'
      AND instantanea_contenido->'proyecto'->'cupo_maximo_alumnos'='5'::jsonb)
    OR NOT EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-7023 AND numero=2 AND estado_revision='aprobada'
      AND instantanea_contenido->'proyecto'->'cupo_maximo_alumnos'='2'::jsonb) THEN
    RAISE EXCEPTION 'Se perdió el historial de cupos propuestos y validados';
  END IF;
END $$;

-- Una instantánea v2 con cupo diferente del proyecto no puede publicarse por
-- escrituras directas, aunque exista una decisión administrativa aprobatoria.
INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,estado_revision,instantanea_contenido)
SELECT -7027,-7002,1,'aprobada',jsonb_set(banco.instantanea_proyecto(-7027),'{proyecto,cupo_maximo_alumnos}','9');
INSERT INTO banco.decision_administrativa(administrador_usuario_id,revision_proyecto_id,resultado,justificacion)
SELECT -7001,id,'aprobada','Cupo que no coincide' FROM banco.revision_proyecto WHERE proyecto_id=-7027;
SELECT pg_temp.cupo_error('23514',$s$UPDATE banco.proyecto SET estado='publicado',revision_publicada_id=(SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-7027) WHERE id=-7027$s$);
-- Una revisión/decisión sin cupo tampoco sustituye la validación de D-02.
INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,estado_revision,instantanea_contenido)
VALUES (-7028,-7002,1,'aprobada',banco.instantanea_proyecto(-7028));
INSERT INTO banco.decision_administrativa(administrador_usuario_id,revision_proyecto_id,resultado,justificacion)
SELECT -7001,id,'aprobada','Sin cupo' FROM banco.revision_proyecto WHERE proyecto_id=-7028;
SELECT pg_temp.cupo_error('23514',$s$UPDATE banco.proyecto SET estado='publicado',revision_publicada_id=(SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-7028) WHERE id=-7028$s$);

-- Compatibilidad v1: no se inventa un cupo ni se aprueba una revisión antigua.
-- Sí se permite devolverla para una propuesta v2 o rechazarla, sin atascarla.
INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,instantanea_contenido)
SELECT p.id,-7002,1,jsonb_build_object('version_formato',1,
  'proyecto',banco.contenido_proyecto(p)-'cupo_maximo_alumnos','habilidades','[]'::jsonb)
FROM banco.proyecto p WHERE p.id IN (-7025,-7026);
UPDATE banco.proyecto SET estado='en_revision' WHERE id IN (-7025,-7026);
SELECT pg_temp.cupo_error('23514',$s$SELECT banco.resolver_publicacion((SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-7025),-7001,'aprobada','No inventar cupo histórico')$s$);
SELECT banco.resolver_publicacion((SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-7025),-7001,'en_correccion','Especificar cupo');
SELECT banco.resolver_publicacion((SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-7026),-7001,'rechazada','No procede');
UPDATE banco.proyecto SET cupo_maximo_alumnos=7 WHERE id=-7025;
INSERT INTO cupos_prueba(proyecto_id,revision_id) VALUES (-7025,banco.enviar_proyecto(-7025,-7002));
UPDATE cupos_prueba SET decision_id=banco.resolver_publicacion(revision_id,-7001,'aprobada','Se valida propuesta nueva de siete') WHERE proyecto_id=-7025;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=-7025 AND numero=1
    AND instantanea_contenido->>'version_formato'='1'
    AND NOT (instantanea_contenido->'proyecto' ? 'cupo_maximo_alumnos') AND estado_revision='en_correccion')
    OR (SELECT estado FROM banco.proyecto WHERE id=-7026) <> 'rechazado' THEN
    RAISE EXCEPTION 'El flujo de corrección/rechazo reescribió o atascó una revisión v1';
  END IF;
END $$;

-- Si la auditoría falla se revierten juntos validación, decisión y publicación.
CREATE FUNCTION pg_temp.fallar_auditoria_cupo() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.operacion='resolver_publicacion' AND NEW.registro_afectado='-7024' THEN
    RAISE EXCEPTION 'Fallo controlado de auditoría D-02' USING ERRCODE='P9999';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_fallo_auditoria_cupo BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_auditoria_cupo();
SELECT pg_temp.cupo_error('P9999',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7024),-7001,'aprobada','Revertir todo')$s$);
DROP TRIGGER tr_prueba_fallo_auditoria_cupo ON banco.evento_auditoria;
DO $$ BEGIN
  IF (SELECT estado FROM banco.proyecto WHERE id=-7024) <> 'en_revision'
    OR (SELECT revision_publicada_id FROM banco.proyecto WHERE id=-7024) IS NOT NULL
    OR EXISTS (SELECT 1 FROM banco.decision_administrativa d JOIN cupos_prueba t ON t.revision_id=d.revision_proyecto_id WHERE t.proyecto_id=-7024)
    OR (SELECT estado_revision FROM banco.revision_proyecto WHERE id=(SELECT revision_id FROM cupos_prueba WHERE proyecto_id=-7024)) <> 'en_revision' THEN
    RAISE EXCEPTION 'La validación de cupo/publicación dejó efectos parciales';
  END IF;
  IF has_function_privilege('banco_lectura','banco.exigir_cupo_proyecto(banco.proyecto)','EXECUTE')
    OR has_function_privilege('banco_escritura','banco.enviar_proyecto(bigint,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'Se ampliaron permisos técnicos sin autorizar la capa web';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'Cupo propuesto, validación de publicación, historial y rollback D-02: correcto' AS resultado;
ROLLBACK;

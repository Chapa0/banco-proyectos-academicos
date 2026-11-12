-- Envíos CU-05/RF-28 contra el contrato SQL real. Fixtures ficticios revertidos.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.participacion_error(codigo text,sentencia text)
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
 (-95001,'Admin envíos','envio-admin@example.invalid','!prueba','administrador','activa'),
 (-95002,'Empresa envíos','envio-rep@example.invalid','!prueba','empresa','activa'),
 (-95101,'Alumno envíos uno','envio-a1@example.invalid','!prueba','alumno','activa'),
 (-95102,'Alumno envíos dos','envio-a2@example.invalid','!prueba','alumno','activa'),
 (-95103,'Alumno envíos tres','envio-a3@example.invalid','!prueba','alumno','activa'),
 (-95104,'Alumno envíos inactivo','envio-a4@example.invalid','!prueba','alumno','inactiva'),
 (-95120,'Profesor envíos','envio-p1@example.invalid','!prueba','profesor','activa'),
 (-95121,'Profesor envíos inactivo','envio-p2@example.invalid','!prueba','profesor','inactiva');
INSERT INTO banco.alumno(usuario_id,matricula) VALUES
 (-95101,'ENV-A-1'),(-95102,'ENV-A-2'),(-95103,'ENV-A-3'),(-95104,'ENV-A-4');
INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES (-95120,'ENV-P-1'),(-95121,'ENV-P-2');
INSERT INTO banco.empresa(id,razon_social) VALUES (-95010,'Empresa ficticia de envíos');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-95002,-95010);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
SELECT id,-95010,-95002,'Proyecto envíos ' || id,'Descripción','Problemática','Objetivos','Justificación','Alcance',1
FROM generate_series(-95205,-95201) AS proyectos(id);
SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-95002),-95001,'aprobada','Publicación de prueba')
FROM banco.proyecto WHERE empresa_id=-95010 AND id<>-95205 ORDER BY id;

SELECT pg_temp.participacion_error('23503',$s$SELECT banco.presentar_candidatura(-95201,-95120)$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.presentar_candidatura(-95201,-95104)$s$);
SELECT pg_temp.participacion_error('23503',$s$SELECT banco.presentar_candidatura(-95999,-95101)$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.presentar_candidatura(-95205,-95101)$s$);
SELECT pg_temp.participacion_error('23503',$s$SELECT banco.solicitar_direccion(-95201,-95101,'Experiencia','Justificación')$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95201,-95121,'Experiencia','Justificación')$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95201,-95120,' ','Justificación')$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95201,-95120,'Experiencia',NULL)$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95201,-95120,E'\t\n','Justificación')$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95201,-95120,'Experiencia',E'\r\n')$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.solicitar_direccion(-95205,-95120,'Experiencia','Justificación')$s$);

CREATE TEMP TABLE envios_candidatura(proyecto_id bigint PRIMARY KEY,candidatura_id bigint) ON COMMIT DROP;
INSERT INTO envios_candidatura SELECT -95201,banco.presentar_candidatura(-95201,-95101);
INSERT INTO envios_candidatura SELECT -95202,banco.presentar_candidatura(-95202,-95101);
INSERT INTO envios_candidatura SELECT -95203,banco.presentar_candidatura(-95203,-95101);
SELECT pg_temp.participacion_error('23505',$s$SELECT banco.presentar_candidatura(-95201,-95101)$s$);
SELECT pg_temp.participacion_error('23514',$s$SELECT banco.presentar_candidatura(-95204,-95101)$s$);
DO $$ BEGIN
  IF (SELECT count(*) FROM banco.candidatura WHERE alumno_id=-95101 AND estado='pendiente_evaluacion')<>3
    OR (SELECT count(*) FROM banco.evento_auditoria WHERE actor_usuario_id=-95101 AND operacion='presentar_candidatura')<>3
    OR EXISTS (SELECT 1 FROM banco.asignacion_alumno WHERE alumno_id=-95101) THEN
    RAISE EXCEPTION 'El envío alteró estado inicial, auditoría o formalizó una asignación';
  END IF;
END $$;

-- Formalización técnica coherente para probar independencia entre carga y candidatura.
-- No acredita las etapas previas de autorización que todavía define D-08.
UPDATE banco.candidatura SET estado='aprobada'
WHERE id=(SELECT candidatura_id FROM envios_candidatura WHERE proyecto_id=-95201);
INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,resultado,justificacion)
SELECT -95601,-95001,candidatura_id,'aprobada','Fixture de proyecto con cupo completo'
FROM envios_candidatura WHERE proyecto_id=-95201;
INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
SELECT candidatura_id,-95601,-95101,-95201,clock_timestamp()
FROM envios_candidatura WHERE proyecto_id=-95201;
SELECT banco.presentar_candidatura(-95204,-95101);
SELECT banco.presentar_candidatura(-95201,-95102);
DO $$ BEGIN
  IF (SELECT count(*) FROM banco.candidatura WHERE alumno_id=-95101 AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada'))<>3
    OR (SELECT count(*) FROM banco.candidatura WHERE alumno_id=-95102 AND proyecto_id=-95201)<>1
    OR (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=-95201 AND estado='vigente')<>1 THEN
    RAISE EXCEPTION 'Se confundieron candidaturas con capacidad del proyecto o carga asignada';
  END IF;
END $$;

-- Más de tres solicitudes pendientes no equivale a más de tres direcciones.
SELECT banco.solicitar_direccion(id,-95120,'Experiencia aplicable','Justificación de prueba')
FROM banco.proyecto WHERE empresa_id=-95010 AND id<>-95205 ORDER BY id;
DO $$ BEGIN
  IF (SELECT count(*) FROM banco.solicitud_direccion WHERE profesor_id=-95120 AND estado='pendiente')<>4
    OR (SELECT count(*) FROM banco.evento_auditoria WHERE actor_usuario_id=-95120 AND operacion='solicitar_direccion')<>4
    OR EXISTS (SELECT 1 FROM banco.asignacion_direccion WHERE profesor_id=-95120) THEN
    RAISE EXCEPTION 'El envío de dirección impuso un límite de pendientes o reservó carga';
  END IF;
END $$;

-- Un fallo del registro histórico revierte también el envío.
CREATE FUNCTION pg_temp.fallar_auditoria_envio() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.operacion IN ('presentar_candidatura','solicitar_direccion') THEN
    RAISE EXCEPTION 'Fallo controlado de auditoría de envío' USING ERRCODE='P9999';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_fallo_envio BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_auditoria_envio();
SELECT pg_temp.participacion_error('P9999',$s$SELECT banco.presentar_candidatura(-95202,-95103)$s$);
SELECT pg_temp.participacion_error('P9999',$s$SELECT banco.solicitar_direccion(-95202,-95120,'Experiencia','Justificación')$s$);
DROP TRIGGER tr_prueba_fallo_envio ON banco.evento_auditoria;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM banco.candidatura WHERE alumno_id=-95103)
    OR (SELECT count(*) FROM banco.solicitud_direccion WHERE profesor_id=-95120)<>4 THEN
    RAISE EXCEPTION 'El fallo de auditoría dejó un envío parcial';
  END IF;
  IF has_function_privilege('banco_escritura','banco.presentar_candidatura(bigint,bigint)','EXECUTE')
    OR has_function_privilege('banco_lectura','banco.solicitar_direccion(bigint,bigint,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Se expusieron funciones internas sin permisos de aplicación';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'Envíos de candidatura y dirección, límites y auditoría atómica: correcto' AS resultado;
ROLLBACK;

-- RF-22/RF-23/RF-28, RN-03/RN-04/RN-11 y CU-05: envío de participaciones.
-- D-06 ya define los conteos. No autoriza participantes (D-08), cancela (D-07)
-- ni genera notificaciones cuyo canal/visibilidad siguen pendientes.
-- INVOKER, propietario únicamente; el identificador suministrado no autentica.

CREATE FUNCTION banco.presentar_candidatura(p_proyecto bigint,p_alumno bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_candidatura bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Mismo orden de reserva que 006: participante -> proyecto.
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de alumno existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_alumno,'alumno',true);
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_publicacion_valida(v_proyecto);
  -- Recibir candidaturas no ocupa plazas de alumnos. D-04 tampoco prohíbe
  -- postularse por tener una asignación; los triggers aplican D-01/RN-11.
  INSERT INTO banco.candidatura(alumno_id,proyecto_id,estado)
  VALUES(p_alumno,p_proyecto,'pendiente_evaluacion') RETURNING id INTO v_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_alumno,'usuario','presentar_candidatura','candidatura',v_candidatura::text,
    'sin candidatura -> pendiente_evaluacion',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_candidatura;
END;
$$;

CREATE FUNCTION banco.solicitar_direccion(p_proyecto bigint,p_profesor bigint,p_experiencia text,p_justificacion text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_solicitud bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de profesor existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF nullif(btrim(p_experiencia),'') IS NULL OR nullif(btrim(p_justificacion),'') IS NULL THEN
    RAISE EXCEPTION 'RF-28: indicar experiencia aplicable y justificación' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_publicacion_valida(v_proyecto);
  -- RF-29/RF-32 limitan asignaciones vigentes, no solicitudes pendientes.
  -- La solicitud no reserva la dirección del proyecto ni carga docente.
  INSERT INTO banco.solicitud_direccion(profesor_id,proyecto_id,experiencia_aplicable,justificacion,estado)
  VALUES(p_profesor,p_proyecto,p_experiencia,p_justificacion,'pendiente') RETURNING id INTO v_solicitud;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_profesor,'usuario','solicitar_direccion','solicitud_direccion',v_solicitud::text,
    'sin solicitud -> pendiente',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_solicitud;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.presentar_candidatura(bigint,bigint) IS
  'Envío interno CU-05: alumno activo, publicación válida, candidatura pendiente y auditoría atómicas; máximo tres activas y sin duplicados. No autorización ni cancelación.';
COMMENT ON FUNCTION banco.solicitar_direccion(bigint,bigint,text,text) IS
  'Envío interno RF-28: profesor activo, publicación válida, experiencia y justificación; solicitud pendiente con auditoría, sin consumir carga ni fijar máximo de pendientes.';

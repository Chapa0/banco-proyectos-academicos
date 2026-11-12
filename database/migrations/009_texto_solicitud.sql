-- RF-28: tabuladores o saltos de línea solos tampoco aportan experiencia
-- ni justificación. Evolución de 008 ya aplicada, sin modificar su checksum.

CREATE OR REPLACE FUNCTION banco.solicitar_direccion(p_proyecto bigint,p_profesor bigint,p_experiencia text,p_justificacion text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_solicitud bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de profesor existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF p_experiencia IS NULL OR p_experiencia !~ '[^[:space:]]'
    OR p_justificacion IS NULL OR p_justificacion !~ '[^[:space:]]' THEN
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

REVOKE ALL ON FUNCTION banco.solicitar_direccion(bigint,bigint,text,text) FROM PUBLIC,banco_lectura,banco_escritura;

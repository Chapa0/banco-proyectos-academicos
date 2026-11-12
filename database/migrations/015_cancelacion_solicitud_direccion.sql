-- D-07, concreción delegada el 10-11-2026: cancelación propia anterior
-- a la asignación. Migración hacia delante; no borra ni reescribe historia.
CREATE FUNCTION banco.proteger_solicitud_cancelada()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF OLD.estado='cancelada' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: la solicitud cancelada conserva su historial y no se reabre'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_000_solicitud_cancelada BEFORE UPDATE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_solicitud_cancelada();

CREATE FUNCTION banco.cancelar_solicitud_direccion(p_solicitud bigint,p_profesor bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_solicitud banco.solicitud_direccion%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_solicitud FROM banco.solicitud_direccion
    WHERE id=p_solicitud FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente' USING ERRCODE='23503'; END IF;
  IF v_solicitud.profesor_id IS DISTINCT FROM p_profesor THEN
    RAISE EXCEPTION 'D-07: el profesor solo cancela su propia solicitud'
      USING ERRCODE='23514';
  END IF;
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Perfil de profesor inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF v_solicitud.estado<>'pendiente' OR EXISTS
    (SELECT 1 FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_solicitud) THEN
    RAISE EXCEPTION 'D-07: solo se cancela la solicitud pendiente; el retiro del director corresponde al administrador'
      USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion('direccion',p_solicitud);
  UPDATE banco.solicitud_direccion SET estado='cancelada' WHERE id=p_solicitud;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,
    entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_profesor,'usuario','cancelar_solicitud_direccion','solicitud_direccion',
    p_solicitud::text,'pendiente -> cancelada',
    jsonb_build_object('proyecto_id',v_solicitud.proyecto_id,
      'sin_asignacion',true)::text) RETURNING id INTO v_evento;
  RETURN v_evento;
END;
$$;
REVOKE ALL ON FUNCTION banco.proteger_solicitud_cancelada()
  FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON FUNCTION banco.cancelar_solicitud_direccion(bigint,bigint)
  FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.cancelar_solicitud_direccion(bigint,bigint) IS
  'D-07: profesor activo cancela su solicitud pendiente propia sin asignación, con auditoría atómica; no autentica los identificadores ni concede acceso de aplicación.';

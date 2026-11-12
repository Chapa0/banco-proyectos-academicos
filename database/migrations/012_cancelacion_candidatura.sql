-- RF-25/RN-13 y acuerdo parcial D-07: el alumno cancela su candidatura
-- activa antes de la asignación; el retiro posterior corresponde al
-- administrador con motivo y efectos todavía pendientes de concretar.
-- No habilita retiro, reapertura, cancelación docente ni cierre del proyecto.

CREATE FUNCTION banco.proteger_candidatura_cancelada()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF OLD.estado='cancelada' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: la candidatura cancelada conserva su historial; no se reabre ni se reescribe'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
-- Se ejecuta antes de tr_00_candidatura_cupos para rechazar una reapertura
-- antes del conteo. UPDATE ya tiene el bloqueo de la fila de candidatura.
CREATE TRIGGER tr_000_candidatura_cancelada BEFORE UPDATE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.proteger_candidatura_cancelada();

CREATE FUNCTION banco.cancelar_candidatura(p_candidatura bigint,p_alumno bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_candidatura banco.candidatura%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Las transiciones de una fuente existente siguen fuente -> participante.
  -- La aprobación también bloquea primero la candidatura al hacer UPDATE y
  -- después su alumno en 006. Este orden evita invertir esos dos bloqueos.
  SELECT * INTO v_candidatura FROM banco.candidatura
    WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  IF v_candidatura.alumno_id IS DISTINCT FROM p_alumno THEN
    RAISE EXCEPTION 'RF-25: el alumno solo puede cancelar su propia candidatura'
      USING ERRCODE='23514';
  END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Perfil de alumno inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_alumno,'alumno',true);
  IF v_candidatura.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada')
    OR EXISTS (SELECT 1 FROM banco.asignacion_alumno WHERE candidatura_id=p_candidatura) THEN
    RAISE EXCEPTION 'D-07: solo se cancela una candidatura activa anterior a la asignación; un retiro posterior requiere al administrador'
      USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion('candidatura',p_candidatura);
  -- No se exige publicación actual: una candidatura anterior sin asignación
  -- puede cancelarse aunque otros participantes ya hayan iniciado el proyecto.
  -- El alumno no ocupa una plaza de asignación y no cambia acompañamientos.
  UPDATE banco.candidatura SET estado='cancelada' WHERE id=p_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_alumno,'usuario','cancelar_candidatura','candidatura',p_candidatura::text,
    v_candidatura.estado || ' -> cancelada',
    jsonb_build_object('proyecto_id',v_candidatura.proyecto_id,'cupo_candidatura_liberado',true)::text)
  RETURNING id INTO v_evento;
  RETURN v_evento;
END;
$$;

REVOKE ALL ON FUNCTION banco.proteger_candidatura_cancelada()
  FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON FUNCTION banco.cancelar_candidatura(bigint,bigint)
  FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.cancelar_candidatura(bigint,bigint) IS
  'RF-25/D-07 parcial: alumno activo cancela una candidatura propia activa antes de asignarse; estado e historial auditado atómicos, sin borrar ni reabrir. No retiro posterior ni autenticación del ID recibido.';

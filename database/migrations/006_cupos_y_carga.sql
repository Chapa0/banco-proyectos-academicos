-- D-01/D-02/D-04/D-06: actividad simultánea, reserva desde autorización y
-- liberación por estado, nunca por fecha estimada ni desactivación de cuenta.
-- No define las etapas desde las que se puede autorizar (D-08) ni los permisos
-- de cancelación, revocación o sustitución (D-07). Funciones internas del dueño.

CREATE UNIQUE INDEX uq_candidatura_activa
  ON banco.candidatura(alumno_id,proyecto_id)
  WHERE estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
CREATE UNIQUE INDEX uq_asignacion_alumno_carga_vigente
  ON banco.asignacion_alumno(alumno_id) WHERE estado='vigente';
CREATE UNIQUE INDEX uq_decision_candidatura_aprobada
  ON banco.decision_administrativa(candidatura_id)
  WHERE candidatura_id IS NOT NULL AND resultado='aprobada';
CREATE UNIQUE INDEX uq_decision_direccion_aprobada
  ON banco.decision_administrativa(solicitud_direccion_id)
  WHERE solicitud_direccion_id IS NOT NULL AND resultado='aprobada';

CREATE FUNCTION banco.validar_cupo_candidatura()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_activas bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- La fila estable del alumno serializa proyectos distintos. READ COMMITTED
  -- da al conteo posterior una vista actualizada después de esperar el bloqueo.
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=NEW.alumno_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Alumno inexistente' USING ERRCODE='23503'; END IF;
  IF TG_OP='UPDATE' AND OLD.estado='aprobada' AND NEW.estado<>'aprobada' THEN
    RAISE EXCEPTION 'D-06: la candidatura aprobada conserva su origen autorizado; las bajas se registran en la asignación'
      USING ERRCODE='55000';
  END IF;
  IF NEW.estado IN ('pendiente_evaluacion','evaluada','preseleccionada') THEN
    -- El índice único conserva el error de duplicado 23505 para la misma pareja.
    IF EXISTS (SELECT 1 FROM banco.candidatura WHERE alumno_id=NEW.alumno_id
      AND proyecto_id=NEW.proyecto_id AND id<>NEW.id
      AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')) THEN
      RAISE EXCEPTION 'RN-11: ya existe una candidatura activa para este alumno y proyecto'
        USING ERRCODE='23505';
    END IF;
    SELECT count(*) INTO v_activas FROM banco.candidatura WHERE alumno_id=NEW.alumno_id
      AND id<>NEW.id AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
    IF v_activas>=3 THEN
      RAISE EXCEPTION 'D-01/D-06: el alumno ya tiene tres candidaturas activas simultáneas'
        USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_00_candidatura_cupos BEFORE INSERT OR UPDATE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.validar_cupo_candidatura();

CREATE FUNCTION banco.validar_reserva_asignacion()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_total bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Orden para nuevas reservas: participante -> proyecto. El nombre del
  -- trigger lo sitúa antes de los controles de publicación de la migración003.
  IF TG_TABLE_NAME='asignacion_alumno' THEN
    PERFORM usuario_id FROM banco.alumno WHERE usuario_id=NEW.alumno_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Alumno inexistente' USING ERRCODE='23503'; END IF;
  ELSE
    PERFORM usuario_id FROM banco.profesor WHERE usuario_id=NEW.profesor_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profesor inexistente' USING ERRCODE='23503'; END IF;
  END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=NEW.proyecto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  IF NEW.estado='vigente' THEN
    IF TG_TABLE_NAME='asignacion_alumno' THEN
      IF EXISTS (SELECT 1 FROM banco.asignacion_alumno WHERE alumno_id=NEW.alumno_id
        AND id<>NEW.id AND estado='vigente') THEN
        RAISE EXCEPTION 'D-04/D-06: el alumno ya tiene un proyecto asignado vigente'
          USING ERRCODE='23505';
      END IF;
      PERFORM banco.exigir_cupo_proyecto(v_proyecto);
      SELECT count(*) INTO v_total FROM banco.asignacion_alumno
        WHERE proyecto_id=NEW.proyecto_id AND id<>NEW.id AND estado='vigente';
      IF v_total>=v_proyecto.cupo_maximo_alumnos THEN
        RAISE EXCEPTION 'D-02/D-06: el proyecto no tiene plazas de alumnos disponibles'
          USING ERRCODE='23514';
      END IF;
    ELSE
      SELECT count(DISTINCT proyecto_id) INTO v_total FROM banco.asignacion_direccion
        WHERE profesor_id=NEW.profesor_id AND id<>NEW.id AND estado='vigente';
      IF v_total>=3 THEN
        RAISE EXCEPTION 'RN-05/D-06: el profesor ya dirige tres proyectos vigentes'
          USING ERRCODE='23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_00_asignacion_alumno_cupos BEFORE INSERT OR UPDATE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.validar_reserva_asignacion();
CREATE TRIGGER tr_00_asignacion_direccion_cupos BEFORE INSERT OR UPDATE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.validar_reserva_asignacion();

CREATE FUNCTION banco.proteger_aprobacion_direccion()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=NEW.profesor_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profesor inexistente' USING ERRCODE='23503'; END IF;
  IF TG_OP='UPDATE' AND OLD.estado='aprobada' AND NEW.estado<>'aprobada' THEN
    RAISE EXCEPTION 'D-06: la solicitud aprobada conserva su origen autorizado; las bajas se registran en la asignación'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_00_solicitud_direccion_aprobacion BEFORE INSERT OR UPDATE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_aprobacion_direccion();

CREATE FUNCTION banco.comprobar_aprobacion_participacion(p_tipo text,p_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_estado text; v_asignacion bigint; v_decision bigint; v_aprobacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Consultar el estado FINAL de la transacción, no el NEW de un evento previo.
  -- Las FK, la inmutabilidad del origen/historial y los locks de participante
  -- protegen las referencias sin invertir aquí el orden de bloqueos.
  IF p_tipo='candidatura' THEN
    SELECT estado INTO v_estado FROM banco.candidatura WHERE id=p_id;
    SELECT id,decision_id INTO v_asignacion,v_decision FROM banco.asignacion_alumno WHERE candidatura_id=p_id;
    SELECT id INTO v_aprobacion FROM banco.decision_administrativa WHERE candidatura_id=p_id AND resultado='aprobada';
  ELSIF p_tipo='direccion' THEN
    SELECT estado INTO v_estado FROM banco.solicitud_direccion WHERE id=p_id;
    SELECT id,decision_id INTO v_asignacion,v_decision FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_id;
    SELECT id INTO v_aprobacion FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_id AND resultado='aprobada';
  ELSE
    RAISE EXCEPTION 'Tipo de participación desconocido' USING ERRCODE='22023';
  END IF;
  IF v_estado='aprobada' OR v_asignacion IS NOT NULL OR v_aprobacion IS NOT NULL THEN
    IF v_estado IS DISTINCT FROM 'aprobada' OR v_asignacion IS NULL OR v_aprobacion IS NULL
      OR v_decision IS DISTINCT FROM v_aprobacion THEN
      RAISE EXCEPTION 'D-06: aprobar % % requiere origen aprobado, decisión y asignación exacta en la misma transacción',p_tipo,p_id
        USING ERRCODE='23514';
    END IF;
  END IF;
END;
$$;
CREATE FUNCTION banco.validar_aprobacion_participacion_diferida()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF TG_TABLE_NAME='candidatura' THEN
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.id);
  ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
    PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.id);
  ELSIF TG_TABLE_NAME='asignacion_alumno' THEN
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.candidatura_id);
  ELSIF TG_TABLE_NAME='asignacion_direccion' THEN
    PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.solicitud_direccion_id);
  ELSIF TG_TABLE_NAME='decision_administrativa' THEN
    IF NEW.candidatura_id IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.candidatura_id);
    ELSIF NEW.solicitud_direccion_id IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.solicitud_direccion_id);
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_candidatura_aprobacion
AFTER INSERT OR UPDATE ON banco.candidatura DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();
CREATE CONSTRAINT TRIGGER ct_solicitud_direccion_aprobacion
AFTER INSERT OR UPDATE ON banco.solicitud_direccion DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();
CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_aprobacion
AFTER INSERT OR UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();
CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_aprobacion
AFTER INSERT OR UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();
CREATE CONSTRAINT TRIGGER ct_decision_participacion_aprobacion
AFTER INSERT ON banco.decision_administrativa DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();

-- Una actualización no puede legitimar datos anteriores incompatibles ni
-- inventarles cierres/cupos. El error revierte la migración completa.
DO $$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM banco.candidatura
    WHERE estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
    GROUP BY alumno_id HAVING count(*)>3) THEN
    RAISE EXCEPTION 'D-01: existen alumnos con más de tres candidaturas activas; reconciliar datos antes de migrar'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM banco.asignacion_alumno a JOIN banco.proyecto p ON p.id=a.proyecto_id
    WHERE a.estado='vigente' GROUP BY p.id,p.cupo_maximo_alumnos
    HAVING p.cupo_maximo_alumnos IS NULL OR count(*)>p.cupo_maximo_alumnos) THEN
    RAISE EXCEPTION 'D-02/D-06: asignaciones previas sin cupo válido o por encima del máximo; reconciliar datos antes de migrar'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM banco.asignacion_direccion WHERE estado='vigente'
    GROUP BY profesor_id HAVING count(DISTINCT proyecto_id)>3) THEN
    RAISE EXCEPTION 'RN-05/D-06: existen profesores con más de tres proyectos vigentes; reconciliar datos antes de migrar'
      USING ERRCODE='23514';
  END IF;
  FOR r IN SELECT id FROM banco.candidatura LOOP
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',r.id);
  END LOOP;
  FOR r IN SELECT id FROM banco.solicitud_direccion LOOP
    PERFORM banco.comprobar_aprobacion_participacion('direccion',r.id);
  END LOOP;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON INDEX banco.uq_candidatura_activa IS
  'D-01/D-06: una candidatura activa por alumno/proyecto; pendiente_evaluacion, evaluada y preseleccionada consumen el máximo de tres.';
COMMENT ON INDEX banco.uq_asignacion_alumno_carga_vigente IS
  'D-04/D-06: una asignación vigente por alumno entre todos los proyectos, reservada desde la aprobación; finalizada/revocada conservan historial sin consumir.';
COMMENT ON FUNCTION banco.comprobar_aprobacion_participacion(text,bigint) IS
  'D-06: integridad diferida del estado final origen/aprobación/asignación. No define evaluación previa D-08 ni habilita permisos o flujos de cierre D-07.';

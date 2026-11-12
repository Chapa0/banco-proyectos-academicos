-- D-05/D-06: inicio expreso del administrador, sin exigir cubrir todo el cupo.
-- Opera sobre asignaciones ya autorizadas; no decide etapas previas D-08.
-- Los cierres, sustituciones e incorporaciones después del inicio siguen D-07.

ALTER TABLE banco.proyecto ADD COLUMN evento_inicio_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.proyecto ADD CONSTRAINT uq_proyecto_evento_inicio UNIQUE(evento_inicio_id);
ALTER TABLE banco.proyecto ADD CONSTRAINT ck_proyecto_inicio_evidencia CHECK (
  (estado <> 'en_curso' OR evento_inicio_id IS NOT NULL)
  AND (evento_inicio_id IS NULL OR estado IN ('en_curso','finalizado','cancelado')));
COMMENT ON COLUMN banco.proyecto.evento_inicio_id IS
  'D-05: evento inmutable del inicio administrativo; conserva actor, fecha, versión publicada, cupo y asignaciones verificadas. No duplica los datos del evento.';

CREATE FUNCTION banco.comprobar_condiciones_inicio(p_proyecto banco.proyecto)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_alumno banco.asignacion_alumno%ROWTYPE;
  v_direccion banco.asignacion_direccion%ROWTYPE;
  v_alumnos bigint; v_directores bigint; v_ids jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_publicacion_valida(p_proyecto);
  SELECT count(*),COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
    INTO v_alumnos,v_ids FROM banco.asignacion_alumno
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  SELECT count(*) INTO v_directores FROM banco.asignacion_direccion
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  IF v_alumnos < 1 OR v_alumnos > p_proyecto.cupo_maximo_alumnos OR v_directores <> 1 THEN
    RAISE EXCEPTION 'D-05: iniciar requiere al menos un alumno dentro del cupo validado y un director vigente del mismo proyecto'
      USING ERRCODE='23514';
  END IF;
  -- La fila Proyecto ya está bloqueada por iniciar_proyecto o por el UPDATE.
  -- Los triggers de 006 serializan sobre ella toda modificación de asignación.
  -- No se toman locks de perfiles/asignaciones en orden inverso: inicio no
  -- reserva nueva carga y los límites globales se conservan también en 006.
  FOR v_alumno IN SELECT * FROM banco.asignacion_alumno
    WHERE proyecto_id=p_proyecto.id AND estado='vigente' ORDER BY id
  LOOP
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',v_alumno.candidatura_id);
    IF NOT EXISTS (SELECT 1 FROM banco.candidatura c JOIN banco.decision_administrativa d
      ON d.id=v_alumno.decision_id AND d.candidatura_id=c.id AND d.resultado='aprobada'
      WHERE c.id=v_alumno.candidatura_id AND c.alumno_id=v_alumno.alumno_id
        AND c.proyecto_id=p_proyecto.id AND c.estado='aprobada')
      OR (SELECT count(*) FROM banco.asignacion_alumno
        WHERE alumno_id=v_alumno.alumno_id AND estado='vigente') > 1 THEN
      RAISE EXCEPTION 'D-04/D-05/D-06: origen/aprobación exactos y carga máxima del alumno requeridos para iniciar'
        USING ERRCODE='23514';
    END IF;
  END LOOP;
  SELECT * INTO v_direccion FROM banco.asignacion_direccion
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  PERFORM banco.comprobar_aprobacion_participacion('direccion',v_direccion.solicitud_direccion_id);
  IF NOT EXISTS (SELECT 1 FROM banco.solicitud_direccion s JOIN banco.decision_administrativa d
    ON d.id=v_direccion.decision_id AND d.solicitud_direccion_id=s.id AND d.resultado='aprobada'
    WHERE s.id=v_direccion.solicitud_direccion_id AND s.profesor_id=v_direccion.profesor_id
      AND s.proyecto_id=p_proyecto.id AND s.estado='aprobada')
    OR (SELECT count(DISTINCT proyecto_id) FROM banco.asignacion_direccion
      WHERE profesor_id=v_direccion.profesor_id AND estado='vigente') > 3 THEN
    RAISE EXCEPTION 'RN-05/D-05/D-06: origen/aprobación exactos y carga máxima del director requeridos para iniciar'
      USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('revision_publicada_id',p_proyecto.revision_publicada_id,
    'cupo_validado',p_proyecto.cupo_maximo_alumnos,'asignaciones_alumno',v_ids,
    'asignacion_direccion',v_direccion.id);
END;
$$;

CREATE OR REPLACE FUNCTION banco.proteger_publicacion_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_evento banco.evento_auditoria%ROWTYPE;
  v_datos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF NEW.estado IN ('finalizado','cancelado') THEN
    RAISE EXCEPTION 'D-07 pendiente: el cierre/cancelación del proyecto requiere su flujo específico'
      USING ERRCODE='55000';
  END IF;
  IF TG_OP='INSERT' AND (NEW.estado='en_curso' OR NEW.evento_inicio_id IS NOT NULL) THEN
    RAISE EXCEPTION 'D-05: no se inserta un proyecto iniciado; primero se publica y autoriza a sus participantes'
      USING ERRCODE='55000';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.revision_publicada_id IS NOT NULL THEN
      IF NEW.revision_publicada_id IS DISTINCT FROM OLD.revision_publicada_id
        OR banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
        RAISE EXCEPTION 'D-07 pendiente: no se modifica contenido/cupo ni se sustituye la versión publicada'
          USING ERRCODE='55000';
      END IF;
      IF OLD.evento_inicio_id IS NOT NULL THEN
        IF NEW.evento_inicio_id IS DISTINCT FROM OLD.evento_inicio_id OR NEW.estado IS DISTINCT FROM OLD.estado THEN
          RAISE EXCEPTION 'D-07 pendiente: el inicio se conserva; no se retrocede ni se sustituye su evidencia'
            USING ERRCODE='55000';
        END IF;
        -- No invalidar el historial porque después se desactive al administrador.
        -- Asignaciones y contenido iniciado se protegen en sus propios triggers.
        RETURN NEW;
      END IF;
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado <> 'en_curso' THEN
        RAISE EXCEPTION 'D-07 pendiente: el ciclo posterior requiere su flujo específico'
          USING ERRCODE='55000';
      END IF;
    ELSIF OLD.estado NOT IN ('borrador','en_correccion')
      AND banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
      RAISE EXCEPTION 'El contenido enviado no se edita durante revisión; requiere devolución para correcciones'
        USING ERRCODE='55000';
    END IF;
  END IF;
  IF NEW.estado='en_curso' THEN
    IF TG_OP <> 'UPDATE' OR OLD.estado <> 'publicado' OR OLD.evento_inicio_id IS NOT NULL
      OR NEW.evento_inicio_id IS NULL THEN
      RAISE EXCEPTION 'D-05: iniciar requiere proyecto publicado y evidencia administrativa nueva'
        USING ERRCODE='23514';
    END IF;
    -- Conservar el contrato de publicación de 004: las altas de asignaciones
    -- siguen exigiendo publicado; este inicio no abre incorporaciones D-07.
    v_publicado := NEW;
    v_publicado.estado := 'publicado';
    v_datos := banco.comprobar_condiciones_inicio(v_publicado);
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=NEW.evento_inicio_id FOR SHARE;
    IF NOT FOUND OR v_evento.origen <> 'usuario' OR v_evento.operacion <> 'iniciar_proyecto'
      OR v_evento.entidad_afectada <> 'proyecto' OR v_evento.registro_afectado <> NEW.id::text
      OR v_evento.transicion IS DISTINCT FROM 'publicado -> en_curso'
      OR v_evento.resultado IS DISTINCT FROM v_datos::text THEN
      RAISE EXCEPTION 'D-05: la evidencia de inicio debe corresponder a este proyecto y sus condiciones exactas'
        USING ERRCODE='23514';
    END IF;
    PERFORM banco.exigir_rol(v_evento.actor_usuario_id,'administrador',true);
    RETURN NEW;
  END IF;
  IF NEW.evento_inicio_id IS NOT NULL THEN
    RAISE EXCEPTION 'D-05: la evidencia de inicio solo se registra al pasar a En curso'
      USING ERRCODE='23514';
  END IF;
  IF NEW.revision_publicada_id IS NOT NULL AND NEW.estado <> 'publicado' THEN
    RAISE EXCEPTION 'Solo un proyecto publicado puede referir a una revisión publicada antes de iniciar'
      USING ERRCODE='23514';
  END IF;
  IF NEW.estado='publicado' OR NEW.revision_publicada_id IS NOT NULL THEN
    PERFORM banco.exigir_publicacion_valida(NEW);
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION banco.proteger_asignaciones_iniciadas()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- tr_00_* de 006 ya obtuvo el lock del proyecto antes de llegar aquí.
  SELECT estado INTO v_estado FROM banco.proyecto WHERE id=NEW.proyecto_id;
  -- La columna generada todavía puede estar vacía en BEFORE UPDATE; no es
  -- entrada editable y se excluye al distinguir un cambio real de un no-op.
  IF v_estado='en_curso' AND (TG_OP='INSERT' OR
    (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision')) THEN
    RAISE EXCEPTION 'D-07 pendiente: las incorporaciones, bajas o cambios de asignaciones después del inicio requieren su flujo específico'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_01_asignacion_alumno_inicio BEFORE INSERT OR UPDATE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.proteger_asignaciones_iniciadas();
CREATE TRIGGER tr_01_asignacion_direccion_inicio BEFORE INSERT OR UPDATE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_asignaciones_iniciadas();

CREATE FUNCTION banco.iniciar_proyecto(p_proyecto bigint,p_admin bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_datos jsonb; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto % inexistente',p_proyecto USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_proyecto.estado='en_curso' AND v_proyecto.evento_inicio_id IS NOT NULL THEN
    RETURN v_proyecto.evento_inicio_id;
  END IF;
  IF v_proyecto.estado <> 'publicado' OR v_proyecto.evento_inicio_id IS NOT NULL THEN
    RAISE EXCEPTION 'D-05: solo se inicia un proyecto publicado todavía no iniciado'
      USING ERRCODE='55000';
  END IF;
  v_datos := banco.comprobar_condiciones_inicio(v_proyecto);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','iniciar_proyecto','proyecto',p_proyecto::text,
    'publicado -> en_curso',v_datos::text) RETURNING id INTO v_evento;
  UPDATE banco.proyecto SET estado='en_curso',evento_inicio_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.iniciar_proyecto(bigint,bigint) IS
  'D-05: inicio administrativo interno INVOKER, con publicación/cupo y asignaciones vigentes autorizadas exactas, evento y transición atómicos. Repetir con administrador activo devuelve el mismo evento. Sin APIs, nuevas asignaciones en curso ni cierre D-07.';

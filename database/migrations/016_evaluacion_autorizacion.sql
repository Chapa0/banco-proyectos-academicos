-- D-08, resolución delegada por el usuario: rúbrica manual sencilla y
-- preselección empresarial explícita antes de la autorización del alumno.
-- SQL interno INVOKER: los IDs recibidos no autentican. Sin grants de aplicación.
-- Migración hacia delante; no convierte evaluaciones históricas ni fabrica
-- criterios, selecciones o puntuaciones para registros anteriores.

ALTER TABLE banco.criterio_evaluacion ADD COLUMN codigo text;
CREATE UNIQUE INDEX uq_criterio_codigo ON banco.criterio_evaluacion(codigo) WHERE codigo IS NOT NULL;
ALTER TABLE banco.evaluacion_candidato ADD COLUMN version_rubrica smallint
  CONSTRAINT ck_evaluacion_rubrica_version CHECK (version_rubrica IS NULL OR version_rubrica=1);
ALTER TABLE banco.evaluacion_candidato ADD CONSTRAINT uq_evaluacion_origen UNIQUE(id,candidatura_id);
ALTER TABLE banco.candidatura ADD COLUMN evaluacion_vigente_id bigint;
ALTER TABLE banco.candidatura ADD COLUMN evento_preseleccion_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.candidatura ADD CONSTRAINT fk_candidatura_evaluacion_exacta
  FOREIGN KEY(evaluacion_vigente_id,id) REFERENCES banco.evaluacion_candidato(id,candidatura_id)
  ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE INDEX ix_candidatura_evaluacion ON banco.candidatura(evaluacion_vigente_id);
CREATE UNIQUE INDEX uq_candidatura_preseleccion ON banco.candidatura(evento_preseleccion_id)
  WHERE evento_preseleccion_id IS NOT NULL;

-- D-07: un rechazo definitivo conserva su origen, sin reapertura ni edición.
-- No se modifican los registros anteriores al aplicar la migración.
CREATE FUNCTION banco.proteger_rechazo_definitivo()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF OLD.estado='rechazada' AND NEW IS DISTINCT FROM OLD
    OR TG_TABLE_NAME='proyecto' AND OLD.estado='rechazado' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: un registro rechazado conserva su historial; no se reabre ni se reescribe' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_0001_candidatura_rechazada BEFORE UPDATE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();
CREATE TRIGGER tr_0001_direccion_rechazada BEFORE UPDATE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();
CREATE TRIGGER tr_0001_proyecto_rechazado BEFORE UPDATE ON banco.proyecto
FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();

CREATE FUNCTION banco.definicion_criterio_d08(p_codigo text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,banco AS $$
DECLARE v_nombre text; v_descripcion text;
BEGIN
  CASE p_codigo
    WHEN 'tecnico' THEN v_nombre:='Conocimientos técnicos'; v_descripcion:='Correspondencia de conocimientos y habilidades técnicas con el proyecto';
    WHEN 'blando' THEN v_nombre:='Habilidades blandas'; v_descripcion:='Correspondencia de habilidades socioemocionales con el proyecto';
    WHEN 'academico' THEN v_nombre:='Requisitos académicos'; v_descripcion:='Correspondencia del perfil académico con los requisitos indicados por el proyecto';
    ELSE RAISE EXCEPTION 'Criterio D-08 desconocido' USING ERRCODE='22023';
  END CASE;
  RETURN jsonb_build_object('version',1,'codigo',p_codigo,'nombre',v_nombre,'descripcion',v_descripcion,
    'escala','0=no cumple; 1=cumple parcialmente; 2=cumple','ponderacion',1);
END;
$$;

CREATE FUNCTION banco.proteger_criterio_d08()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_def jsonb;
BEGIN
  IF TG_OP<>'INSERT' AND OLD.codigo IS NOT NULL THEN
    IF TG_OP='DELETE' OR NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'La rúbrica D-08 conserva su definición; un cambio requiere otra versión' USING ERRCODE='55000';
    END IF;
  END IF;
  IF TG_OP<>'DELETE' AND NEW.codigo IS NOT NULL THEN
    v_def:=banco.definicion_criterio_d08(NEW.codigo);
    IF NEW.nombre IS DISTINCT FROM v_def->>'nombre' OR NEW.descripcion IS DISTINCT FROM v_def->>'descripcion'
      OR NEW.escala IS DISTINCT FROM v_def->>'escala' OR NEW.ponderacion IS DISTINCT FROM 1::numeric THEN
      RAISE EXCEPTION 'Definición de rúbrica D-08 incoherente' USING ERRCODE='23514';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_criterio_d08 BEFORE INSERT OR UPDATE OR DELETE ON banco.criterio_evaluacion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_criterio_d08();

CREATE FUNCTION banco.comprobar_evaluacion_d08(p_evaluacion bigint)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_eval banco.evaluacion_candidato%ROWTYPE; v_det record; v_total integer:=0;
BEGIN
  SELECT * INTO v_eval FROM banco.evaluacion_candidato WHERE id=p_evaluacion;
  IF NOT FOUND THEN RAISE EXCEPTION 'Evaluación inexistente' USING ERRCODE='23503'; END IF;
  IF v_eval.version_rubrica IS NULL THEN RETURN; END IF;
  IF v_eval.comentarios IS NULL OR v_eval.comentarios !~ '[^[:space:]]'
    OR v_eval.recomendacion IS NULL OR v_eval.recomendacion NOT IN ('recomendada','no_recomendada') THEN
    RAISE EXCEPTION 'D-08 requiere comentarios y recomendación explícita' USING ERRCODE='23514';
  END IF;
  FOR v_det IN SELECT d.*,c.codigo FROM banco.detalle_evaluacion d
    JOIN banco.criterio_evaluacion c ON c.id=d.criterio_id WHERE d.evaluacion_id=p_evaluacion
  LOOP
    IF v_det.codigo IS NULL OR v_det.codigo NOT IN ('tecnico','blando','academico')
      OR v_det.puntuacion NOT IN (0,1,2) OR v_det.comentario IS NULL OR v_det.comentario !~ '[^[:space:]]'
      OR v_det.definicion_aplicada IS DISTINCT FROM banco.definicion_criterio_d08(v_det.codigo) THEN
      RAISE EXCEPTION 'D-08 requiere tres criterios con escala 0..2, comentario y definición exacta' USING ERRCODE='23514';
    END IF;
    v_total:=v_total+1;
  END LOOP;
  IF v_total<>3 THEN RAISE EXCEPTION 'D-08: evaluación incompleta' USING ERRCODE='23514'; END IF;
END;
$$;
CREATE FUNCTION banco.validar_evaluacion_d08_diferida()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF TG_TABLE_NAME='evaluacion_candidato' THEN PERFORM banco.comprobar_evaluacion_d08(NEW.id);
  ELSE PERFORM banco.comprobar_evaluacion_d08(NEW.evaluacion_id); END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_evaluacion_d08 AFTER INSERT ON banco.evaluacion_candidato
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluacion_d08_diferida();
CREATE CONSTRAINT TRIGGER ct_detalle_d08 AFTER INSERT ON banco.detalle_evaluacion
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluacion_d08_diferida();

CREATE FUNCTION banco.evaluar_candidatura(p_candidatura bigint,p_representante bigint,
  p_puntuaciones jsonb,p_comentarios text,p_recomendada boolean)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE;
  v_eval bigint; v_codigo text; v_item jsonb; v_def jsonb; v_criterio bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_comentarios IS NULL OR p_comentarios !~ '[^[:space:]]' OR p_recomendada IS NULL
    OR p_puntuaciones IS NULL OR jsonb_typeof(p_puntuaciones)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_puntuaciones))<>3
    OR NOT (p_puntuaciones ?& ARRAY['tecnico','blando','academico']) THEN
    RAISE EXCEPTION 'D-08: rúbrica, comentarios y recomendación completos son obligatorios' USING ERRCODE='23514';
  END IF;
  FOREACH v_codigo IN ARRAY ARRAY['tecnico','blando','academico'] LOOP
    v_item:=p_puntuaciones->v_codigo;
    IF jsonb_typeof(v_item) IS DISTINCT FROM 'object'
      OR (SELECT count(*) FROM jsonb_object_keys(v_item))<>2 OR NOT(v_item ?& ARRAY['puntuacion','comentario'])
      OR jsonb_typeof(v_item->'puntuacion') IS DISTINCT FROM 'number'
      OR (v_item->>'puntuacion')::numeric NOT IN (0,1,2)
      OR jsonb_typeof(v_item->'comentario') IS DISTINCT FROM 'string'
      OR (v_item->>'comentario') !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'D-08: cada criterio requiere puntuación 0, 1 o 2 y comentario' USING ERRCODE='23514';
    END IF;
  END LOOP;
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_representante(p_representante,v_p.empresa_id);
  IF v_c.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada') THEN
    RAISE EXCEPTION 'Solo se evalúa una candidatura activa' USING ERRCODE='55000';
  END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
  INSERT INTO banco.evaluacion_candidato(candidatura_id,evaluador_usuario_id,fecha,comentarios,recomendacion,version_rubrica)
    VALUES(p_candidatura,p_representante,clock_timestamp(),p_comentarios,
      CASE WHEN p_recomendada THEN 'recomendada' ELSE 'no_recomendada' END,1) RETURNING id INTO v_eval;
  -- Catálogo fijo creado bajo demanda; las inserciones concurrentes convergen.
  -- No se cambia ni interpreta un criterio/evaluación anterior sin versión.
  FOREACH v_codigo IN ARRAY ARRAY['tecnico','blando','academico'] LOOP
    v_def:=banco.definicion_criterio_d08(v_codigo);
    INSERT INTO banco.criterio_evaluacion(codigo,nombre,descripcion,escala,ponderacion)
      VALUES(v_codigo,v_def->>'nombre',v_def->>'descripcion',v_def->>'escala',1)
      ON CONFLICT(codigo) WHERE codigo IS NOT NULL DO NOTHING;
    SELECT id INTO v_criterio FROM banco.criterio_evaluacion WHERE codigo=v_codigo;
    INSERT INTO banco.detalle_evaluacion(evaluacion_id,criterio_id,puntuacion,comentario,definicion_aplicada)
      VALUES(v_eval,v_criterio,(p_puntuaciones->v_codigo->>'puntuacion')::numeric,
        p_puntuaciones->v_codigo->>'comentario',v_def);
  END LOOP;
  PERFORM banco.comprobar_evaluacion_d08(v_eval);
  UPDATE banco.candidatura SET estado='evaluada',evaluacion_vigente_id=v_eval,evento_preseleccion_id=NULL
    WHERE id=p_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_representante,'usuario','evaluar_candidatura','candidatura',p_candidatura::text,v_c.estado || ' -> evaluada',
      jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_eval,'version_rubrica',1,
        'evaluacion_anterior_id',v_c.evaluacion_vigente_id,'preseleccion_anterior_id',v_c.evento_preseleccion_id)::text);
  RETURN v_eval;
END;
$$;

CREATE FUNCTION banco.preseleccionar_candidatura(p_candidatura bigint,p_representante bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_e banco.evaluacion_candidato%ROWTYPE;
  v_pre banco.evento_auditoria%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_representante(p_representante,v_p.empresa_id);
  PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
  IF v_c.estado NOT IN ('evaluada','preseleccionada') OR v_c.evaluacion_vigente_id IS NULL THEN
    RAISE EXCEPTION 'D-08: preseleccionar requiere evaluación completa previa' USING ERRCODE='55000';
  END IF;
  SELECT * INTO v_e FROM banco.evaluacion_candidato WHERE id=v_c.evaluacion_vigente_id;
  PERFORM banco.comprobar_evaluacion_d08(v_e.id);
  IF v_e.version_rubrica IS DISTINCT FROM 1 OR v_e.candidatura_id<>v_c.id OR v_e.recomendacion<>'recomendada'
    OR EXISTS(SELECT 1 FROM banco.evaluacion_candidato WHERE candidatura_id=v_c.id AND version_rubrica=1 AND id>v_e.id) THEN
    RAISE EXCEPTION 'D-08: la última evaluación debe recomendar al candidato' USING ERRCODE='23514';
  END IF;
  IF v_c.estado='preseleccionada' AND v_c.evento_preseleccion_id IS NOT NULL THEN
    SELECT * INTO v_pre FROM banco.evento_auditoria WHERE id=v_c.evento_preseleccion_id;
    IF NOT FOUND OR v_pre.operacion<>'preseleccionar_candidatura' OR v_pre.entidad_afectada<>'candidatura'
      OR v_pre.registro_afectado<>v_c.id::text OR v_pre.origen<>'usuario'
      OR v_pre.resultado::jsonb IS DISTINCT FROM jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id) THEN
      RAISE EXCEPTION 'La evidencia de preselección no corresponde a la evaluación vigente' USING ERRCODE='23514';
    END IF;
    RETURN v_c.evento_preseleccion_id;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_representante,'usuario','preseleccionar_candidatura','candidatura',p_candidatura::text,'evaluada -> preseleccionada',
      jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id)::text) RETURNING id INTO v_evento;
  UPDATE banco.candidatura SET estado='preseleccionada',evento_preseleccion_id=v_evento WHERE id=p_candidatura;
  RETURN v_evento;
END;
$$;

CREATE FUNCTION banco.resolver_candidatura(p_candidatura bigint,p_admin bigint,p_resultado text,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_e banco.evaluacion_candidato%ROWTYPE;
  v_pre banco.evento_auditoria%ROWTYPE; v_decision bigint; v_asignacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_resultado IS NULL OR p_resultado NOT IN ('aprobada','rechazada') OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Resolver requiere aprobación/rechazo y motivo no blanco' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_c.estado=p_resultado THEN
    SELECT id INTO v_decision FROM banco.decision_administrativa WHERE candidatura_id=p_candidatura AND resultado=p_resultado ORDER BY id DESC LIMIT 1;
    IF v_decision IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('candidatura',p_candidatura);
      RETURN v_decision;
    END IF;
  END IF;
  IF v_c.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada')
    OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE candidatura_id=p_candidatura)
    OR EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE candidatura_id=p_candidatura) THEN
    RAISE EXCEPTION 'La candidatura ya fue resuelta o cerrada' USING ERRCODE='55000';
  END IF;
  IF p_resultado='aprobada' THEN
    PERFORM banco.exigir_rol(v_c.alumno_id,'alumno',true);
    PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
    IF v_c.estado<>'preseleccionada' OR v_c.evaluacion_vigente_id IS NULL OR v_c.evento_preseleccion_id IS NULL THEN
      RAISE EXCEPTION 'D-08: autorizar requiere evaluación y preselección empresarial' USING ERRCODE='55000';
    END IF;
    SELECT * INTO v_e FROM banco.evaluacion_candidato WHERE id=v_c.evaluacion_vigente_id;
    PERFORM banco.comprobar_evaluacion_d08(v_e.id);
    SELECT * INTO v_pre FROM banco.evento_auditoria WHERE id=v_c.evento_preseleccion_id;
    IF v_e.version_rubrica IS DISTINCT FROM 1 OR v_e.recomendacion<>'recomendada'
      OR EXISTS(SELECT 1 FROM banco.evaluacion_candidato WHERE candidatura_id=v_c.id AND version_rubrica=1 AND id>v_e.id)
      OR v_pre.operacion<>'preseleccionar_candidatura' OR v_pre.entidad_afectada<>'candidatura'
      OR v_pre.registro_afectado<>p_candidatura::text OR v_pre.origen<>'usuario'
      OR v_pre.resultado::jsonb IS DISTINCT FROM jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id) THEN
      RAISE EXCEPTION 'La preselección no corresponde a la evaluación vigente' USING ERRCODE='23514';
    END IF;
  ELSIF v_p.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'No se resuelven nuevas decisiones en un proyecto cerrado' USING ERRCODE='55000';
  END IF;
  UPDATE banco.candidatura SET estado=p_resultado WHERE id=p_candidatura;
  INSERT INTO banco.decision_administrativa(administrador_usuario_id,candidatura_id,fecha,resultado,justificacion)
    VALUES(p_admin,p_candidatura,clock_timestamp(),p_resultado,p_motivo) RETURNING id INTO v_decision;
  IF p_resultado='aprobada' THEN
    INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
      VALUES(p_candidatura,v_decision,v_c.alumno_id,v_p.id,clock_timestamp()) RETURNING id INTO v_asignacion;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','resolver_candidatura','candidatura',p_candidatura::text,v_c.estado || ' -> ' || p_resultado,
      jsonb_build_object('proyecto_id',v_p.id,'decision_id',v_decision,'asignacion_id',v_asignacion,
        'evaluacion_id',v_c.evaluacion_vigente_id,'preseleccion_evento_id',v_c.evento_preseleccion_id,'motivo',p_motivo)::text);
  RETURN v_decision;
END;
$$;

CREATE FUNCTION banco.resolver_direccion(p_solicitud bigint,p_admin bigint,p_resultado text,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_s banco.solicitud_direccion%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_decision bigint; v_asignacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_resultado IS NULL OR p_resultado NOT IN ('aprobada','rechazada') OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Resolver requiere aprobación/rechazo y motivo no blanco' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_s FROM banco.solicitud_direccion WHERE id=p_solicitud FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud de dirección inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_s.profesor_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_s.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_s.estado=p_resultado THEN
    SELECT id INTO v_decision FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_solicitud AND resultado=p_resultado ORDER BY id DESC LIMIT 1;
    IF v_decision IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('direccion',p_solicitud);
      RETURN v_decision;
    END IF;
  END IF;
  IF v_s.estado<>'pendiente' OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_solicitud)
    OR EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_solicitud) THEN
    RAISE EXCEPTION 'La solicitud de dirección ya fue resuelta o cerrada' USING ERRCODE='55000';
  END IF;
  IF p_resultado='aprobada' THEN
    PERFORM banco.exigir_rol(v_s.profesor_id,'profesor',true);
    PERFORM banco.exigir_disponibilidad_participacion(v_p,'direccion');
    IF v_s.experiencia_aplicable IS NULL OR v_s.experiencia_aplicable !~ '[^[:space:]]'
      OR v_s.justificacion IS NULL OR v_s.justificacion !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'RF-28: dirección requiere experiencia y justificación no blancas' USING ERRCODE='23514';
    END IF;
  ELSIF v_p.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'No se resuelven nuevas decisiones en un proyecto cerrado' USING ERRCODE='55000';
  END IF;
  UPDATE banco.solicitud_direccion SET estado=p_resultado WHERE id=p_solicitud;
  INSERT INTO banco.decision_administrativa(administrador_usuario_id,solicitud_direccion_id,fecha,resultado,justificacion)
    VALUES(p_admin,p_solicitud,clock_timestamp(),p_resultado,p_motivo) RETURNING id INTO v_decision;
  IF p_resultado='aprobada' THEN
    INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES(p_solicitud,v_decision,v_s.profesor_id,v_p.id,clock_timestamp()) RETURNING id INTO v_asignacion;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','resolver_direccion','solicitud_direccion',p_solicitud::text,v_s.estado || ' -> ' || p_resultado,
      jsonb_build_object('proyecto_id',v_p.id,'decision_id',v_decision,'asignacion_id',v_asignacion,'motivo',p_motivo)::text);
  RETURN v_decision;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.evaluar_candidatura(bigint,bigint,jsonb,text,boolean) IS
  'D-08: rúbrica manual 0..2 de tres criterios, iguales pesos sin umbral automático; evaluación y detalle inmutables, nueva evaluación invalida preselección. IDs no autentican.';
COMMENT ON FUNCTION banco.resolver_candidatura(bigint,bigint,text,text) IS
  'D-08: aprobación administrativa posterior a evaluación/preselección, decisión y asignación atómicas; rechazo desde fuente activa. Inicio efectivo en autorización, límites006 y publicación013 conservados.';
COMMENT ON FUNCTION banco.resolver_direccion(bigint,bigint,text,text) IS
  'D-08: administrador aprueba/rechaza dirección pendiente con motivo; experiencia/justificación y límites se comprueban al aprobar, sin evaluación empresarial de profesor.';

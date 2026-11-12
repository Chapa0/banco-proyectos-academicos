-- D-07: retiro administrativo con motivo, pausa al perder el mínimo,
-- reposición del tipo faltante y reanudación expresa por administrador.
-- No define etapas de evaluación/autorización D-08, cierres definitivos,
-- reapertura de fuentes ni incorporaciones generales después del inicio.

ALTER TABLE banco.proyecto DROP CONSTRAINT proyecto_estado_check;
ALTER TABLE banco.proyecto ADD CONSTRAINT proyecto_estado_check CHECK (estado IN
  ('borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado'));
ALTER TABLE banco.proyecto ADD COLUMN evento_estado_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.proyecto ADD CONSTRAINT uq_proyecto_evento_estado UNIQUE(evento_estado_id);
ALTER TABLE banco.proyecto DROP CONSTRAINT ck_proyecto_inicio_evidencia;
ALTER TABLE banco.proyecto ADD CONSTRAINT ck_proyecto_inicio_evidencia CHECK (
  (estado NOT IN ('en_curso','pausado') OR evento_inicio_id IS NOT NULL)
  AND (evento_inicio_id IS NULL OR estado IN ('en_curso','pausado','finalizado','cancelado'))
  AND (estado <> 'pausado' OR evento_estado_id IS NOT NULL)
  AND (evento_estado_id IS NULL OR evento_inicio_id IS NOT NULL));

ALTER TABLE banco.asignacion_alumno ADD COLUMN evento_retiro_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.asignacion_direccion ADD COLUMN evento_retiro_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.acompanamiento ADD COLUMN evento_retiro_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE UNIQUE INDEX uq_asignacion_alumno_evento_retiro ON banco.asignacion_alumno(evento_retiro_id);
CREATE UNIQUE INDEX uq_asignacion_direccion_evento_retiro ON banco.asignacion_direccion(evento_retiro_id);
CREATE INDEX ix_acompanamiento_evento_retiro ON banco.acompanamiento(evento_retiro_id);
ALTER TABLE banco.asignacion_alumno DROP CONSTRAINT ck_asignacion_alumno_fechas;
ALTER TABLE banco.asignacion_alumno ADD CONSTRAINT ck_asignacion_alumno_fechas CHECK (
  (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL)
  OR (estado='finalizada' AND fin IS NOT NULL AND fin>inicio AND evento_retiro_id IS NULL)
  OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_retiro_id IS NOT NULL))));
ALTER TABLE banco.asignacion_direccion DROP CONSTRAINT ck_asignacion_direccion_fechas;
ALTER TABLE banco.asignacion_direccion ADD CONSTRAINT ck_asignacion_direccion_fechas CHECK (
  (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL)
  OR (estado='finalizada' AND fin IS NOT NULL AND fin>inicio AND evento_retiro_id IS NULL)
  OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_retiro_id IS NOT NULL))));
ALTER TABLE banco.acompanamiento DROP CONSTRAINT ck_acompanamiento_fechas;
ALTER TABLE banco.acompanamiento ADD CONSTRAINT ck_acompanamiento_fechas CHECK (
  (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL)
  OR (estado='finalizada' AND fin IS NOT NULL AND fin>inicio AND evento_retiro_id IS NULL)
  OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_retiro_id IS NOT NULL))));

CREATE FUNCTION banco.marcar_evento_operacion_actual()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_datos jsonb;
BEGIN
  IF NEW.operacion IN ('retirar_alumno','retirar_director','pausar_proyecto','reanudar_proyecto') THEN
    PERFORM banco.exigir_aislamiento();
    BEGIN v_datos := NEW.resultado::jsonb;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'La operación requiere datos de auditoría estructurados' USING ERRCODE='23514';
    END;
    IF jsonb_typeof(v_datos) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'La operación requiere datos de auditoría objeto' USING ERRCODE='23514';
    END IF;
    -- El sello lo produce la base, no el llamador. Funciona también dentro de
    -- subtransacciones; un evento confirmado en otra transacción no habilita
    -- posteriormente una nueva transición. No altera auditoría anterior.
    NEW.fecha := clock_timestamp();
    NEW.resultado := (v_datos || jsonb_build_object('transaccion_id',pg_current_xact_id()::text))::text;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_evento_operacion_actual BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION banco.marcar_evento_operacion_actual();

CREATE FUNCTION banco.evento_operacion(p_evento bigint,p_operacion text,p_entidad text,p_registro bigint,p_actual boolean DEFAULT true)
RETURNS banco.evento_auditoria LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_evento FOR SHARE;
  IF NOT FOUND OR v_evento.origen<>'usuario' OR v_evento.operacion IS DISTINCT FROM p_operacion
    OR v_evento.entidad_afectada IS DISTINCT FROM p_entidad OR v_evento.registro_afectado IS DISTINCT FROM p_registro::text THEN
    RAISE EXCEPTION 'La evidencia no corresponde a la operación y registro exactos' USING ERRCODE='23514';
  END IF;
  BEGIN v_datos := v_evento.resultado::jsonb;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'La evidencia requiere datos estructurados' USING ERRCODE='23514';
  END;
  IF jsonb_typeof(v_datos) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'La evidencia requiere un objeto' USING ERRCODE='23514';
  END IF;
  IF p_actual THEN
    IF v_datos->>'transaccion_id' IS DISTINCT FROM pg_current_xact_id()::text THEN
      RAISE EXCEPTION 'La evidencia de transición debe crearse en la misma transacción' USING ERRCODE='23514';
    END IF;
    PERFORM banco.exigir_rol(v_evento.actor_usuario_id,'administrador',true);
  END IF;
  RETURN v_evento;
END;
$$;

CREATE FUNCTION banco.comprobar_retiro(p_tipo text,p_asignacion bigint,p_participante bigint,p_proyecto bigint,
  p_inicio timestamptz,p_fin timestamptz,p_evento bigint,p_actual boolean DEFAULT true)
RETURNS timestamptz LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_operacion text; v_entidad text; v_fin timestamptz;
BEGIN
  IF p_tipo='alumno' THEN v_operacion:='retirar_alumno'; v_entidad:='asignacion_alumno';
  ELSIF p_tipo='direccion' THEN v_operacion:='retirar_director'; v_entidad:='asignacion_direccion';
  ELSE RAISE EXCEPTION 'Tipo de retiro no reconocido' USING ERRCODE='22023'; END IF;
  v_evento := banco.evento_operacion(p_evento,v_operacion,v_entidad,p_asignacion,p_actual);
  v_datos := v_evento.resultado::jsonb;
  IF v_evento.transicion IS DISTINCT FROM 'vigente -> revocada'
    OR v_datos->>'tipo' IS DISTINCT FROM p_tipo OR v_datos->>'asignacion_id' IS DISTINCT FROM p_asignacion::text
    OR v_datos->>'participante_id' IS DISTINCT FROM p_participante::text
    OR v_datos->>'proyecto_id' IS DISTINCT FROM p_proyecto::text
    OR jsonb_typeof(v_datos->'motivo') IS DISTINCT FROM 'string'
    OR (v_datos->>'motivo') !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El retiro requiere participante, proyecto y motivo exactos' USING ERRCODE='23514';
  END IF;
  v_fin := CASE WHEN v_evento.fecha>p_inicio THEN v_evento.fecha ELSE NULL END;
  IF p_fin IS DISTINCT FROM v_fin THEN
    RAISE EXCEPTION 'El retiro conserva el inicio; fin es la fecha real solo si el periodo había empezado'
      USING ERRCODE='23514';
  END IF;
  RETURN v_evento.fecha;
END;
$$;

CREATE FUNCTION banco.validar_retiro_asignacion()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_tipo text; v_participante bigint;
BEGIN
  IF TG_OP='UPDATE' AND OLD.evento_retiro_id IS NOT NULL AND
    (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
    RAISE EXCEPTION 'El retiro confirmado conserva su historial' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_retiro_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='INSERT' OR OLD.estado<>'vigente' OR OLD.evento_retiro_id IS NOT NULL
    OR NEW.estado<>'revocada' THEN
    IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'resultado_decision')=(to_jsonb(OLD)-'resultado_decision') THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'El retiro se registra sobre una asignación vigente existente' USING ERRCODE='55000';
  END IF;
  IF (to_jsonb(NEW)-ARRAY['estado','fin','evento_retiro_id','resultado_decision'])
    IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['estado','fin','evento_retiro_id','resultado_decision']) THEN
    RAISE EXCEPTION 'El retiro no sustituye la identidad, origen o inicio de la asignación' USING ERRCODE='55000';
  END IF;
  IF TG_TABLE_NAME='asignacion_alumno' THEN v_tipo:='alumno'; v_participante:=NEW.alumno_id;
  ELSE v_tipo:='direccion'; v_participante:=NEW.profesor_id; END IF;
  PERFORM banco.comprobar_retiro(v_tipo,NEW.id,v_participante,NEW.proyecto_id,NEW.inicio,NEW.fin,NEW.evento_retiro_id,true);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_02_asignacion_alumno_retiro BEFORE INSERT OR UPDATE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.validar_retiro_asignacion();
CREATE TRIGGER tr_02_asignacion_direccion_retiro BEFORE INSERT OR UPDATE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.validar_retiro_asignacion();

CREATE FUNCTION banco.comprobar_acompanamiento_estado(p_vinculo banco.acompanamiento)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_alumno banco.asignacion_alumno%ROWTYPE; v_direccion banco.asignacion_direccion%ROWTYPE;
  v_evento banco.evento_auditoria%ROWTYPE; v_fecha timestamptz;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_alumno FROM banco.asignacion_alumno WHERE id=p_vinculo.asignacion_alumno_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de alumno inexistente' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_direccion FROM banco.asignacion_direccion WHERE id=p_vinculo.asignacion_direccion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de dirección inexistente' USING ERRCODE='23503'; END IF;
  IF v_alumno.proyecto_id<>v_direccion.proyecto_id OR p_vinculo.inicio<v_alumno.inicio OR p_vinculo.inicio<v_direccion.inicio THEN
    RAISE EXCEPTION 'El acompañamiento requiere el mismo proyecto y comienzo contenido' USING ERRCODE='23514';
  END IF;
  IF p_vinculo.estado='vigente' AND (v_alumno.estado<>'vigente' OR v_direccion.estado<>'vigente') THEN
    RAISE EXCEPTION 'Un acompañamiento vigente requiere ambas asignaciones vigentes' USING ERRCODE='23514';
  END IF;
  IF p_vinculo.evento_retiro_id IS NOT NULL THEN
    IF p_vinculo.estado<>'revocada' THEN RAISE EXCEPTION 'La evidencia de retiro requiere acompañamiento revocado' USING ERRCODE='23514'; END IF;
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_vinculo.evento_retiro_id;
    IF v_evento.operacion='retirar_alumno' AND v_alumno.estado='revocada'
      AND v_alumno.evento_retiro_id=p_vinculo.evento_retiro_id THEN
      v_fecha := banco.comprobar_retiro('alumno',v_alumno.id,v_alumno.alumno_id,v_alumno.proyecto_id,
        v_alumno.inicio,v_alumno.fin,v_alumno.evento_retiro_id,false);
    ELSIF v_evento.operacion='retirar_director' AND v_direccion.estado='revocada'
      AND v_direccion.evento_retiro_id=p_vinculo.evento_retiro_id THEN
      v_fecha := banco.comprobar_retiro('direccion',v_direccion.id,v_direccion.profesor_id,v_direccion.proyecto_id,
        v_direccion.inicio,v_direccion.fin,v_direccion.evento_retiro_id,false);
    ELSE
      RAISE EXCEPTION 'El acompañamiento debe cerrar por el retiro exacto de uno de sus padres' USING ERRCODE='23514';
    END IF;
    IF p_vinculo.fin IS DISTINCT FROM (CASE WHEN v_fecha>p_vinculo.inicio THEN v_fecha ELSE NULL END) THEN
      RAISE EXCEPTION 'El fin del acompañamiento no puede inventarse antes de su inicio' USING ERRCODE='23514';
    END IF;
    IF p_vinculo.fin IS NULL THEN RETURN; END IF;
  ELSIF p_vinculo.estado='revocada' AND p_vinculo.fin IS NULL THEN
    RAISE EXCEPTION 'Una revocación anterior al inicio requiere su evidencia exacta' USING ERRCODE='23514';
  END IF;
  IF (v_alumno.estado='revocada' AND v_alumno.fin IS NULL)
    OR (v_direccion.estado='revocada' AND v_direccion.fin IS NULL)
    OR (v_alumno.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_alumno.fin))
    OR (v_direccion.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_direccion.fin)) THEN
    RAISE EXCEPTION 'La vigencia efectiva del acompañamiento debe quedar contenida en ambas asignaciones' USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION banco.comprobar_acompanamiento(p_alumno bigint,p_direccion bigint,p_inicio timestamptz,p_fin timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_vinculo banco.acompanamiento%ROWTYPE;
BEGIN
  v_vinculo.asignacion_alumno_id:=p_alumno; v_vinculo.asignacion_direccion_id:=p_direccion;
  v_vinculo.inicio:=p_inicio; v_vinculo.fin:=p_fin;
  v_vinculo.estado:=CASE WHEN p_fin IS NULL THEN 'vigente' ELSE 'finalizada' END;
  PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
END;
$$;

CREATE OR REPLACE FUNCTION banco.validar_acompanamiento()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id
    OR NEW.asignacion_alumno_id IS DISTINCT FROM OLD.asignacion_alumno_id
    OR NEW.asignacion_direccion_id IS DISTINCT FROM OLD.asignacion_direccion_id
    OR NEW.inicio IS DISTINCT FROM OLD.inicio OR (OLD.estado<>'vigente' AND NEW IS DISTINCT FROM OLD)) THEN
    RAISE EXCEPTION 'El acompañamiento conserva identidad, origen e inicio; el historial cerrado no se reescribe' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_retiro_id IS NOT NULL AND (TG_OP='INSERT' OR NEW.evento_retiro_id IS DISTINCT FROM OLD.evento_retiro_id) THEN
    IF TG_OP='INSERT' OR OLD.estado<>'vigente' OR NEW.estado<>'revocada' THEN
      RAISE EXCEPTION 'El retiro cierra un acompañamiento vigente existente' USING ERRCODE='55000';
    END IF;
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=NEW.evento_retiro_id;
    IF NOT FOUND OR v_evento.operacion NOT IN ('retirar_alumno','retirar_director') THEN
      RAISE EXCEPTION 'La evidencia no corresponde a un retiro autorizado' USING ERRCODE='23514';
    END IF;
    PERFORM banco.evento_operacion(v_evento.id,v_evento.operacion,v_evento.entidad_afectada,v_evento.registro_afectado::bigint,true);
  END IF;
  PERFORM banco.comprobar_acompanamiento_estado(NEW);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION banco.validar_vigencias_padre()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_vinculo banco.acompanamiento%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME='asignacion_alumno' THEN
    FOR v_vinculo IN SELECT * FROM banco.acompanamiento WHERE asignacion_alumno_id=NEW.id ORDER BY id LOOP
      PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
    END LOOP;
  ELSE
    FOR v_vinculo IN SELECT * FROM banco.acompanamiento WHERE asignacion_direccion_id=NEW.id ORDER BY id LOOP
      PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;

CREATE FUNCTION banco.exigir_disponibilidad_participacion(p_proyecto banco.proyecto,p_tipo text)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_total bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_proyecto.estado='pausado' THEN
    v_publicado:=p_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.exigir_publicacion_valida(v_publicado);
    IF p_tipo='alumno' THEN SELECT count(*) INTO v_total FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente';
    ELSIF p_tipo='direccion' THEN SELECT count(*) INTO v_total FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente';
    ELSE RAISE EXCEPTION 'Tipo de participación no reconocido' USING ERRCODE='22023'; END IF;
    IF v_total<>0 THEN RAISE EXCEPTION 'D-07: la pausa solo admite solicitudes y reposición del tipo faltante' USING ERRCODE='55000'; END IF;
  ELSE
    PERFORM banco.exigir_publicacion_valida(p_proyecto);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION banco.validar_proyecto_al_asignar()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_tipo text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=NEW.proyecto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  v_tipo:=CASE WHEN TG_TABLE_NAME='asignacion_alumno' THEN 'alumno' ELSE 'direccion' END;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,v_tipo);
  IF v_proyecto.estado='pausado' AND NEW.estado<>'vigente' THEN
    RAISE EXCEPTION 'La reposición requiere una asignación vigente autorizada' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION banco.proteger_asignaciones_iniciadas()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT estado INTO v_estado FROM banco.proyecto WHERE id=NEW.proyecto_id;
  IF v_estado IN ('en_curso','pausado') THEN
    IF TG_OP='INSERT' THEN
      IF v_estado='en_curso' THEN RAISE EXCEPTION 'D-07: no se habilitan incorporaciones generales en curso' USING ERRCODE='55000'; END IF;
    ELSIF (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
      IF OLD.estado<>'vigente' OR NEW.estado<>'revocada' OR NEW.evento_retiro_id IS NULL
        OR OLD.evento_retiro_id IS NOT NULL
        OR (to_jsonb(NEW)-ARRAY['estado','fin','evento_retiro_id','resultado_decision'])
          IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['estado','fin','evento_retiro_id','resultado_decision']) THEN
        RAISE EXCEPTION 'D-07: las asignaciones iniciadas solo cambian mediante retiro administrativo con evidencia exacta'
          USING ERRCODE='55000';
      END IF;
      -- El trigger tr_02 verifica a continuación la evidencia completa.
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION banco.participantes_vigentes(p_proyecto bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
 SELECT jsonb_build_object('alumnos',COALESCE((SELECT jsonb_agg(id ORDER BY id) FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'),'[]'::jsonb),
   'direcciones',COALESCE((SELECT jsonb_agg(id ORDER BY id) FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente'),'[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION banco.proteger_publicacion_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_evento banco.evento_auditoria%ROWTYPE;
  v_retiro banco.evento_auditoria%ROWTYPE; v_previo banco.evento_auditoria%ROWTYPE;
  v_datos jsonb; v_esperado jsonb; v_participantes jsonb; v_retiro_valido boolean;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF NEW.estado IN ('finalizado','cancelado') THEN
    RAISE EXCEPTION 'D-07: el cierre definitivo o cancelación del proyecto requiere su flujo específico' USING ERRCODE='55000';
  END IF;
  IF TG_OP='INSERT' AND (NEW.estado IN ('en_curso','pausado') OR NEW.evento_inicio_id IS NOT NULL OR NEW.evento_estado_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Primero se publica e inicia el proyecto mediante sus operaciones protegidas' USING ERRCODE='55000';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.revision_publicada_id IS NOT NULL THEN
      IF NEW.revision_publicada_id IS DISTINCT FROM OLD.revision_publicada_id
        OR banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
        RAISE EXCEPTION 'D-07: no se modifica contenido/cupo ni se sustituye la versión publicada' USING ERRCODE='55000';
      END IF;
      IF OLD.evento_inicio_id IS NOT NULL THEN
        IF NEW.evento_inicio_id IS DISTINCT FROM OLD.evento_inicio_id THEN
          RAISE EXCEPTION 'El primer inicio y su evidencia se conservan' USING ERRCODE='55000';
        END IF;
        IF NEW.estado=OLD.estado AND NEW.evento_estado_id IS NOT DISTINCT FROM OLD.evento_estado_id THEN RETURN NEW; END IF;
        IF NOT ((OLD.estado='en_curso' AND NEW.estado='pausado') OR (OLD.estado='pausado' AND NEW.estado='en_curso')) THEN
          RAISE EXCEPTION 'El proyecto iniciado solo admite pausa por retiro o reanudación administrativa protegida' USING ERRCODE='55000';
        END IF;
        IF NEW.evento_estado_id IS NULL OR NEW.evento_estado_id IS NOT DISTINCT FROM OLD.evento_estado_id THEN
          RAISE EXCEPTION 'La pausa o reanudación requiere evidencia nueva de la operación' USING ERRCODE='23514';
        END IF;
        IF OLD.estado='en_curso' AND NEW.estado='pausado' THEN
          v_evento:=banco.evento_operacion(NEW.evento_estado_id,'pausar_proyecto','proyecto',NEW.id,true);
          IF v_evento.transicion IS DISTINCT FROM 'en_curso -> pausado' THEN RAISE EXCEPTION 'Transición de pausa incoherente' USING ERRCODE='23514'; END IF;
          v_datos:=v_evento.resultado::jsonb;
          v_participantes:=banco.participantes_vigentes(NEW.id);
          IF jsonb_array_length(v_participantes->'alumnos')>0 AND jsonb_array_length(v_participantes->'direcciones')>0 THEN
            RAISE EXCEPTION 'La pausa automática requiere pérdida de un participante mínimo' USING ERRCODE='23514';
          END IF;
          SELECT * INTO v_retiro FROM banco.evento_auditoria WHERE id::text=v_datos->>'retiro_evento_id';
          IF NOT FOUND OR v_retiro.operacion NOT IN ('retirar_alumno','retirar_director') THEN
            RAISE EXCEPTION 'La pausa requiere su retiro administrativo causante' USING ERRCODE='23514';
          END IF;
          v_retiro:=banco.evento_operacion(v_retiro.id,v_retiro.operacion,v_retiro.entidad_afectada,v_retiro.registro_afectado::bigint,true);
          IF v_retiro.operacion='retirar_alumno' THEN
            SELECT EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE id::text=v_retiro.registro_afectado
              AND proyecto_id=NEW.id AND estado='revocada' AND evento_retiro_id=v_retiro.id) INTO v_retiro_valido;
          ELSE
            SELECT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE id::text=v_retiro.registro_afectado
              AND proyecto_id=NEW.id AND estado='revocada' AND evento_retiro_id=v_retiro.id) INTO v_retiro_valido;
          END IF;
          IF NOT v_retiro_valido OR v_retiro.actor_usuario_id IS DISTINCT FROM v_evento.actor_usuario_id THEN
            RAISE EXCEPTION 'La pausa conserva el administrador y proyecto del retiro exacto' USING ERRCODE='23514';
          END IF;
          v_esperado:=v_participantes || jsonb_build_object('retiro_evento_id',v_retiro.id,
            'evento_estado_anterior_id',OLD.evento_estado_id,'transaccion_id',pg_current_xact_id()::text);
        ELSIF OLD.estado='pausado' AND NEW.estado='en_curso' THEN
          v_evento:=banco.evento_operacion(NEW.evento_estado_id,'reanudar_proyecto','proyecto',NEW.id,true);
          IF v_evento.transicion IS DISTINCT FROM 'pausado -> en_curso' THEN RAISE EXCEPTION 'Transición de reanudación incoherente' USING ERRCODE='23514'; END IF;
          v_previo:=banco.evento_operacion(OLD.evento_estado_id,'pausar_proyecto','proyecto',NEW.id,false);
          v_publicado:=NEW; v_publicado.estado:='publicado';
          v_esperado:=banco.comprobar_condiciones_inicio(v_publicado) || jsonb_build_object(
            'evento_estado_anterior_id',OLD.evento_estado_id,'transaccion_id',pg_current_xact_id()::text);
        ELSE
          RAISE EXCEPTION 'El proyecto iniciado solo admite pausa por retiro o reanudación administrativa protegida' USING ERRCODE='55000';
        END IF;
        IF v_evento.resultado::jsonb IS DISTINCT FROM v_esperado THEN
          RAISE EXCEPTION 'La evidencia no coincide con participantes y condiciones de la transición' USING ERRCODE='23514';
        END IF;
        RETURN NEW;
      END IF;
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado<>'en_curso' THEN
        RAISE EXCEPTION 'D-07: el ciclo posterior requiere su flujo específico' USING ERRCODE='55000';
      END IF;
    ELSIF OLD.estado NOT IN ('borrador','en_correccion')
      AND banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
      RAISE EXCEPTION 'El contenido enviado solo se corrige después de una devolución' USING ERRCODE='55000';
    END IF;
  END IF;
  IF NEW.estado='en_curso' THEN
    IF TG_OP<>'UPDATE' OR OLD.estado<>'publicado' OR OLD.evento_inicio_id IS NOT NULL
      OR NEW.evento_inicio_id IS NULL OR NEW.evento_estado_id IS NOT NULL THEN
      RAISE EXCEPTION 'Iniciar requiere proyecto publicado y evidencia inicial exacta' USING ERRCODE='23514';
    END IF;
    v_publicado:=NEW; v_publicado.estado:='publicado';
    v_datos:=banco.comprobar_condiciones_inicio(v_publicado);
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=NEW.evento_inicio_id FOR SHARE;
    IF NOT FOUND OR v_evento.origen<>'usuario' OR v_evento.operacion<>'iniciar_proyecto'
      OR v_evento.entidad_afectada<>'proyecto' OR v_evento.registro_afectado<>NEW.id::text
      OR v_evento.transicion IS DISTINCT FROM 'publicado -> en_curso' OR v_evento.resultado IS DISTINCT FROM v_datos::text THEN
      RAISE EXCEPTION 'La evidencia de inicio requiere proyecto y condiciones exactas' USING ERRCODE='23514';
    END IF;
    PERFORM banco.exigir_rol(v_evento.actor_usuario_id,'administrador',true);
    RETURN NEW;
  END IF;
  IF NEW.evento_inicio_id IS NOT NULL OR NEW.evento_estado_id IS NOT NULL OR NEW.estado='pausado' THEN
    RAISE EXCEPTION 'La evidencia de inicio o pausa solo pertenece a sus transiciones protegidas' USING ERRCODE='23514';
  END IF;
  IF NEW.revision_publicada_id IS NOT NULL AND NEW.estado<>'publicado' THEN
    RAISE EXCEPTION 'La revisión publicada anterior al inicio requiere estado publicado' USING ERRCODE='23514';
  END IF;
  IF NEW.estado='publicado' OR NEW.revision_publicada_id IS NOT NULL THEN PERFORM banco.exigir_publicacion_valida(NEW); END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION banco.retirar_asignacion(p_tipo text,p_asignacion bigint,p_admin bigint,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_tabla text; v_perfil text; v_columna text; v_origen text; v_operacion text;
  v_lectura record; v_asignacion record; v_participante bigint; v_proyecto banco.proyecto%ROWTYPE;
  v_fecha timestamptz; v_evento bigint; v_pausa bigint; v_vinculo banco.acompanamiento%ROWTYPE; v_participantes jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo='alumno' THEN
    v_tabla:='asignacion_alumno'; v_perfil:='alumno'; v_columna:='alumno_id'; v_origen:='candidatura_id'; v_operacion:='retirar_alumno';
  ELSIF p_tipo='direccion' THEN
    v_tabla:='asignacion_direccion'; v_perfil:='profesor'; v_columna:='profesor_id'; v_origen:='solicitud_direccion_id'; v_operacion:='retirar_director';
  ELSE RAISE EXCEPTION 'Tipo de retiro no reconocido' USING ERRCODE='22023'; END IF;
  IF p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN RAISE EXCEPTION 'El retiro requiere motivo no blanco' USING ERRCODE='23514'; END IF;
  -- Los IDs de origen son inmutables. Leerlos no retiene un padre mientras
  -- espera Proyecto: dos retiros de tipos distintos no forman un ciclo al
  -- cerrar sus acompañamientos. Revalidar la asignación después del bloqueo.
  EXECUTE format('SELECT * FROM banco.%I WHERE id=$1',v_tabla) INTO v_lectura USING p_asignacion;
  IF v_lectura.id IS NULL THEN RAISE EXCEPTION 'Asignación inexistente' USING ERRCODE='23503'; END IF;
  v_participante:=(to_jsonb(v_lectura)->>v_columna)::bigint;
  EXECUTE format('SELECT usuario_id FROM banco.%I WHERE usuario_id=$1 FOR UPDATE',v_perfil) USING v_participante;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_lectura.proyecto_id FOR UPDATE;
  EXECUTE format('SELECT * FROM banco.%I WHERE id=$1 FOR UPDATE',v_tabla) INTO v_asignacion USING p_asignacion;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_asignacion.id IS NULL OR v_asignacion.proyecto_id<>v_proyecto.id
    OR (to_jsonb(v_asignacion)->>v_columna)::bigint<>v_participante THEN
    RAISE EXCEPTION 'El origen de la asignación cambió indebidamente' USING ERRCODE='23503';
  END IF;
  IF v_asignacion.estado='revocada' AND v_asignacion.evento_retiro_id IS NOT NULL THEN
    PERFORM banco.comprobar_retiro(p_tipo,v_asignacion.id,v_participante,v_proyecto.id,
      v_asignacion.inicio,v_asignacion.fin,v_asignacion.evento_retiro_id,false);
    RETURN v_asignacion.evento_retiro_id;
  END IF;
  IF v_asignacion.estado<>'vigente' OR v_proyecto.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'Solo se retira una asignación vigente de un proyecto publicado, en curso o pausado' USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion(CASE WHEN p_tipo='alumno' THEN 'candidatura' ELSE 'direccion' END,
    (to_jsonb(v_asignacion)->>v_origen)::bigint);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario',v_operacion,v_tabla,p_asignacion::text,'vigente -> revocada',
    jsonb_build_object('tipo',p_tipo,'asignacion_id',p_asignacion,'participante_id',v_participante,'proyecto_id',v_proyecto.id,'motivo',p_motivo)::text)
  RETURNING id,fecha INTO v_evento,v_fecha;
  EXECUTE format('UPDATE banco.%I SET estado=''revocada'',fin=CASE WHEN $1>inicio THEN $1 ELSE NULL END,evento_retiro_id=$2 WHERE id=$3',v_tabla)
    USING v_fecha,v_evento,p_asignacion;
  FOR v_vinculo IN SELECT * FROM banco.acompanamiento
    WHERE estado='vigente' AND ((p_tipo='alumno' AND asignacion_alumno_id=p_asignacion)
      OR (p_tipo='direccion' AND asignacion_direccion_id=p_asignacion)) ORDER BY id FOR UPDATE
  LOOP
    UPDATE banco.acompanamiento SET estado='revocada',
      fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,evento_retiro_id=v_evento WHERE id=v_vinculo.id;
  END LOOP;
  v_participantes:=banco.participantes_vigentes(v_proyecto.id);
  IF v_proyecto.estado='en_curso' AND (jsonb_array_length(v_participantes->'alumnos')=0 OR jsonb_array_length(v_participantes->'direcciones')=0) THEN
    INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','pausar_proyecto','proyecto',v_proyecto.id::text,'en_curso -> pausado',
      (v_participantes || jsonb_build_object('retiro_evento_id',v_evento,'evento_estado_anterior_id',v_proyecto.evento_estado_id))::text)
    RETURNING id INTO v_pausa;
    UPDATE banco.proyecto SET estado='pausado',evento_estado_id=v_pausa WHERE id=v_proyecto.id;
  END IF;
  RETURN v_evento;
END;
$$;

CREATE FUNCTION banco.retirar_alumno(p_asignacion bigint,p_admin bigint,p_motivo text)
RETURNS bigint LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
 SELECT banco.retirar_asignacion('alumno',p_asignacion,p_admin,p_motivo);
$$;
CREATE FUNCTION banco.retirar_director(p_asignacion bigint,p_admin bigint,p_motivo text)
RETURNS bigint LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
 SELECT banco.retirar_asignacion('direccion',p_asignacion,p_admin,p_motivo);
$$;

CREATE FUNCTION banco.reanudar_proyecto(p_proyecto bigint,p_admin bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE;
  v_evento bigint; v_datos jsonb; v_previo banco.evento_auditoria%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_proyecto.estado='en_curso' AND v_proyecto.evento_estado_id IS NOT NULL THEN
    SELECT * INTO v_previo FROM banco.evento_auditoria WHERE id=v_proyecto.evento_estado_id;
    IF v_previo.operacion='reanudar_proyecto' THEN RETURN v_previo.id; END IF;
  END IF;
  IF v_proyecto.estado<>'pausado' OR v_proyecto.evento_estado_id IS NULL THEN
    RAISE EXCEPTION 'Solo se reanuda un proyecto pausado mediante confirmación administrativa' USING ERRCODE='55000';
  END IF;
  v_previo:=banco.evento_operacion(v_proyecto.evento_estado_id,'pausar_proyecto','proyecto',v_proyecto.id,false);
  v_publicado:=v_proyecto; v_publicado.estado:='publicado';
  v_datos:=banco.comprobar_condiciones_inicio(v_publicado) || jsonb_build_object('evento_estado_anterior_id',v_proyecto.evento_estado_id);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','reanudar_proyecto','proyecto',p_proyecto::text,'pausado -> en_curso',v_datos::text)
  RETURNING id INTO v_evento;
  UPDATE banco.proyecto SET estado='en_curso',evento_estado_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;

CREATE OR REPLACE FUNCTION banco.presentar_candidatura(p_proyecto bigint,p_alumno bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_candidatura bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de alumno existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_alumno,'alumno',true);
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,'alumno');
  INSERT INTO banco.candidatura(alumno_id,proyecto_id,estado)
  VALUES(p_alumno,p_proyecto,'pendiente_evaluacion') RETURNING id INTO v_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_alumno,'usuario','presentar_candidatura','candidatura',v_candidatura::text,
    'sin candidatura -> pendiente_evaluacion',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_candidatura;
END;
$$;

CREATE OR REPLACE FUNCTION banco.solicitar_direccion(p_proyecto bigint,p_profesor bigint,p_experiencia text,p_justificacion text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_solicitud bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de profesor existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF p_experiencia IS NULL OR p_experiencia !~ '[^[:space:]]' OR p_justificacion IS NULL OR p_justificacion !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'RF-28: indicar experiencia aplicable y justificación' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,'direccion');
  INSERT INTO banco.solicitud_direccion(profesor_id,proyecto_id,experiencia_aplicable,justificacion,estado)
  VALUES(p_profesor,p_proyecto,p_experiencia,p_justificacion,'pendiente') RETURNING id INTO v_solicitud;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_profesor,'usuario','solicitar_direccion','solicitud_direccion',v_solicitud::text,
    'sin solicitud -> pendiente',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_solicitud;
END;
$$;

CREATE FUNCTION banco.validar_minimos_proyecto_diferido()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_id bigint; v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME='proyecto' THEN v_id:=NEW.id; ELSE v_id:=NEW.proyecto_id; END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_id FOR UPDATE;
  IF FOUND AND v_proyecto.estado='en_curso' THEN
    v_publicado:=v_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.comprobar_condiciones_inicio(v_publicado);
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_proyecto_minimos AFTER INSERT OR UPDATE ON banco.proyecto
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_minimos AFTER INSERT OR UPDATE ON banco.asignacion_alumno
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_minimos AFTER INSERT OR UPDATE ON banco.asignacion_direccion
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON COLUMN banco.proyecto.evento_estado_id IS
  'D-07: último evento inmutable de pausa/reanudación; enlaza el anterior en su resultado. Conserva el primer evento_inicio_id.';
COMMENT ON COLUMN banco.asignacion_alumno.evento_retiro_id IS
  'D-07: retiro administrativo exacto; fecha real en auditoría. Si ocurre antes o al inicio, estado revocada y fin NULL expresan periodo no iniciado, sin inventar final.';
COMMENT ON COLUMN banco.asignacion_direccion.evento_retiro_id IS
  'D-07: retiro del director solo por administrador con motivo. Conserva otras asignaciones y carga; puede pausar el proyecto.';
COMMENT ON COLUMN banco.acompanamiento.evento_retiro_id IS
  'Retiro exacto de uno de sus padres; el periodo futuro revocado no recibe un fin ficticio. No crea acompañamientos al reponer participantes.';
COMMENT ON FUNCTION banco.retirar_alumno(bigint,bigint,text) IS
  'Retiro interno por administrador activo y motivo, con cierre de sus acompañamientos, reserva liberada y pausa si pierde el mínimo. Idempotente para el retiro ya registrado.';
COMMENT ON FUNCTION banco.retirar_director(bigint,bigint,text) IS
  'Retiro interno por administrador activo y motivo; cierra sus acompañamientos, conserva alumnos y su carga y pausa si falta director. No retiro unilateral docente.';
COMMENT ON FUNCTION banco.reanudar_proyecto(bigint,bigint) IS
  'Confirmación administrativa interna después de reponer mínimos autorizados; revalida publicación, cupo, carga y orígenes, conserva primer inicio e historial. Sin etapas D-08, APIs ni avisos.';

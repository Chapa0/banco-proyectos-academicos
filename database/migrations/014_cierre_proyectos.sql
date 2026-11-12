-- D-07: cierre definitivo administrativo, con motivo e historia coordinada.
-- Finalizar: solo En curso. Cancelar: borrador/revisión/corrección/publicado/
-- en curso/pausado. No reabre, no califica ni crea entregables académicos.
-- Migración de avance: no modifica las fuentes 001-013 ya aplicadas.

ALTER TABLE banco.proyecto ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.proyecto ADD CONSTRAINT uq_proyecto_evento_cierre UNIQUE(evento_cierre_id);
ALTER TABLE banco.proyecto ADD CONSTRAINT ck_proyecto_cierre_evidencia CHECK
  ((estado IN ('finalizado','cancelado')) = (evento_cierre_id IS NOT NULL));
ALTER TABLE banco.asignacion_alumno ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.asignacion_direccion ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.acompanamiento ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.candidatura ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.solicitud_direccion ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE banco.revision_proyecto ADD COLUMN evento_cierre_id bigint
  REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE INDEX ix_asignacion_alumno_evento_cierre ON banco.asignacion_alumno(evento_cierre_id);
CREATE INDEX ix_asignacion_direccion_evento_cierre ON banco.asignacion_direccion(evento_cierre_id);
CREATE INDEX ix_acompanamiento_evento_cierre ON banco.acompanamiento(evento_cierre_id);
CREATE INDEX ix_candidatura_evento_cierre ON banco.candidatura(evento_cierre_id);
CREATE INDEX ix_solicitud_direccion_evento_cierre ON banco.solicitud_direccion(evento_cierre_id);
CREATE INDEX ix_revision_evento_cierre ON banco.revision_proyecto(evento_cierre_id);
ALTER TABLE banco.candidatura ADD CONSTRAINT ck_candidatura_cierre CHECK
  (evento_cierre_id IS NULL OR estado='cancelada');
ALTER TABLE banco.solicitud_direccion ADD CONSTRAINT ck_solicitud_direccion_cierre CHECK
  (evento_cierre_id IS NULL OR estado='cancelada');
ALTER TABLE banco.revision_proyecto DROP CONSTRAINT revision_proyecto_estado_revision_check;
ALTER TABLE banco.revision_proyecto ADD CONSTRAINT revision_proyecto_estado_revision_check CHECK
  (estado_revision IN ('en_revision','aprobada','en_correccion','rechazada','cancelada'));
ALTER TABLE banco.revision_proyecto ADD CONSTRAINT ck_revision_cierre CHECK
  ((estado_revision='cancelada') = (evento_cierre_id IS NOT NULL));

ALTER TABLE banco.asignacion_alumno DROP CONSTRAINT ck_asignacion_alumno_fechas;
ALTER TABLE banco.asignacion_alumno ADD CONSTRAINT ck_asignacion_alumno_fechas CHECK (
  num_nonnulls(evento_retiro_id,evento_cierre_id)<=1 AND (
    (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL AND evento_cierre_id IS NULL)
    OR (estado='finalizada' AND evento_retiro_id IS NULL
      AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_cierre_id IS NOT NULL)))
    OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio)
      OR (fin IS NULL AND num_nonnulls(evento_retiro_id,evento_cierre_id)=1)))));
ALTER TABLE banco.asignacion_direccion DROP CONSTRAINT ck_asignacion_direccion_fechas;
ALTER TABLE banco.asignacion_direccion ADD CONSTRAINT ck_asignacion_direccion_fechas CHECK (
  num_nonnulls(evento_retiro_id,evento_cierre_id)<=1 AND (
    (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL AND evento_cierre_id IS NULL)
    OR (estado='finalizada' AND evento_retiro_id IS NULL
      AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_cierre_id IS NOT NULL)))
    OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio)
      OR (fin IS NULL AND num_nonnulls(evento_retiro_id,evento_cierre_id)=1)))));
ALTER TABLE banco.acompanamiento DROP CONSTRAINT ck_acompanamiento_fechas;
ALTER TABLE banco.acompanamiento ADD CONSTRAINT ck_acompanamiento_fechas CHECK (
  num_nonnulls(evento_retiro_id,evento_cierre_id)<=1 AND (
    (estado='vigente' AND fin IS NULL AND evento_retiro_id IS NULL AND evento_cierre_id IS NULL)
    OR (estado='finalizada' AND evento_retiro_id IS NULL
      AND ((fin IS NOT NULL AND fin>inicio) OR (fin IS NULL AND evento_cierre_id IS NOT NULL)))
    OR (estado='revocada' AND ((fin IS NOT NULL AND fin>inicio)
      OR (fin IS NULL AND num_nonnulls(evento_retiro_id,evento_cierre_id)=1)))));

CREATE FUNCTION banco.alcance_cierre_proyecto(p_proyecto bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
  SELECT jsonb_build_object(
    'alumnos',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'),
    'direcciones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente'),
    'acompanamientos',(SELECT COALESCE(jsonb_agg(a.id ORDER BY a.id),'[]'::jsonb)
      FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
      WHERE x.proyecto_id=p_proyecto AND a.estado='vigente'),
    'candidaturas',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'estado',estado) ORDER BY id),'[]'::jsonb)
      FROM banco.candidatura WHERE proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')),
    'solicitudes',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'),
    'revisiones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.revision_proyecto WHERE proyecto_id=p_proyecto AND estado_revision='en_revision'));
$$;

CREATE FUNCTION banco.evento_cierre_proyecto(p_evento bigint,p_proyecto bigint,p_actual boolean DEFAULT true)
RETURNS banco.evento_auditoria LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_destino text; v_clave text;
BEGIN
  SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_evento;
  IF NOT FOUND OR v_evento.operacion NOT IN ('finalizar_proyecto','cancelar_proyecto') THEN
    RAISE EXCEPTION 'El cierre requiere su evento administrativo exacto' USING ERRCODE='23514';
  END IF;
  v_evento:=banco.evento_operacion(p_evento,v_evento.operacion,'proyecto',p_proyecto,p_actual);
  v_datos:=v_evento.resultado::jsonb;
  v_destino:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizado' ELSE 'cancelado' END;
  IF v_datos->>'motivo' IS NULL OR (v_datos->>'motivo') !~ '[^[:space:]]'
    OR v_datos->>'estado_anterior' IS NULL
    OR jsonb_typeof(v_datos->'alcance') IS DISTINCT FROM 'object'
    OR v_evento.transicion IS DISTINCT FROM (v_datos->>'estado_anterior') || ' -> ' || v_destino
    OR (v_destino='finalizado' AND v_datos->>'estado_anterior' IS DISTINCT FROM 'en_curso')
    OR (v_destino='cancelado' AND (v_datos->>'estado_anterior') NOT IN
      ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
    RAISE EXCEPTION 'Motivo, transición o alcance de cierre incoherentes' USING ERRCODE='23514';
  END IF;
  FOREACH v_clave IN ARRAY ARRAY['alumnos','direcciones','acompanamientos','candidaturas','solicitudes','revisiones'] LOOP
    IF jsonb_typeof(v_datos #> ARRAY['alcance',v_clave]) IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Cada parte del alcance requiere una lista exacta' USING ERRCODE='23514';
    END IF;
  END LOOP;
  RETURN v_evento;
END;
$$;

CREATE FUNCTION banco.comprobar_periodo_cierre(p_evento bigint,p_proyecto bigint,p_clave text,
  p_id bigint,p_estado text,p_inicio timestamptz,p_fin timestamptz,p_actual boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_estado text;
BEGIN
  v_evento:=banco.evento_cierre_proyecto(p_evento,p_proyecto,p_actual);
  v_estado:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizada' ELSE 'revocada' END;
  IF p_clave NOT IN ('alumnos','direcciones','acompanamientos')
    OR p_estado IS DISTINCT FROM v_estado
    OR NOT COALESCE((v_evento.resultado::jsonb #> ARRAY['alcance',p_clave]) @> jsonb_build_array(p_id),false)
    OR p_fin IS DISTINCT FROM (CASE WHEN v_evento.fecha>p_inicio THEN v_evento.fecha ELSE NULL END) THEN
    RAISE EXCEPTION 'El periodo y estado deben corresponder al cierre exacto, sin inventar fechas' USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE FUNCTION banco.validar_elemento_cierre()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto bigint; v_evento banco.evento_auditoria%ROWTYPE; v_clave text;
  v_cambios text[]; v_datos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_OP='UPDATE' AND OLD.evento_cierre_id IS NOT NULL AND
    (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
    RAISE EXCEPTION 'El cierre conserva su historia y no se reabre ni reescribe' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_cierre_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'resultado_decision') IS NOT DISTINCT FROM
    (to_jsonb(OLD)-'resultado_decision') THEN RETURN NEW; END IF;
  IF TG_OP<>'UPDATE' OR OLD.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'El cierre solo afecta registros existentes aún abiertos' USING ERRCODE='23514';
  END IF;
  IF TG_TABLE_NAME='acompanamiento' THEN
    SELECT proyecto_id INTO v_proyecto FROM banco.asignacion_alumno WHERE id=NEW.asignacion_alumno_id;
  ELSE v_proyecto:=NEW.proyecto_id; END IF;
  v_evento:=banco.evento_cierre_proyecto(NEW.evento_cierre_id,v_proyecto,true);
  v_datos:=v_evento.resultado::jsonb;
  IF TG_TABLE_NAME IN ('asignacion_alumno','asignacion_direccion','acompanamiento') THEN
    IF OLD.estado<>'vigente' OR NEW.evento_retiro_id IS NOT NULL THEN
      RAISE EXCEPTION 'Solo se cierran periodos vigentes; los retiros anteriores se conservan' USING ERRCODE='55000';
    END IF;
    v_clave:=CASE TG_TABLE_NAME WHEN 'asignacion_alumno' THEN 'alumnos'
      WHEN 'asignacion_direccion' THEN 'direcciones' ELSE 'acompanamientos' END;
    PERFORM banco.comprobar_periodo_cierre(NEW.evento_cierre_id,v_proyecto,v_clave,
      NEW.id,NEW.estado,NEW.inicio,NEW.fin,true);
    v_cambios:=ARRAY['estado','fin','evento_cierre_id','resultado_decision'];
  ELSE
    v_cambios:=ARRAY['estado','evento_cierre_id'];
    IF TG_TABLE_NAME='candidatura' THEN
      IF OLD.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada') OR NEW.estado<>'cancelada'
        OR NOT COALESCE((v_datos #> '{alcance,candidaturas}') @>
          jsonb_build_array(jsonb_build_object('id',OLD.id,'estado',OLD.estado)),false) THEN
        RAISE EXCEPTION 'El cierre cancela solo las candidaturas activas incluidas' USING ERRCODE='23514';
      END IF;
    ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
      IF OLD.estado<>'pendiente' OR NEW.estado<>'cancelada'
        OR NOT COALESCE((v_datos #> '{alcance,solicitudes}') @> jsonb_build_array(NEW.id),false) THEN
        RAISE EXCEPTION 'El cierre cancela solo las solicitudes pendientes incluidas' USING ERRCODE='23514';
      END IF;
    ELSE
      v_cambios:=ARRAY['estado_revision','evento_cierre_id'];
      IF TG_TABLE_NAME<>'revision_proyecto' OR OLD.estado_revision<>'en_revision' OR NEW.estado_revision<>'cancelada'
        OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=NEW.id)
        OR NOT COALESCE((v_datos #> '{alcance,revisiones}') @> jsonb_build_array(NEW.id),false) THEN
        RAISE EXCEPTION 'La revisión se cancela sin fabricar una decisión de rechazo' USING ERRCODE='23514';
      END IF;
    END IF;
  END IF;
  IF (to_jsonb(NEW)-v_cambios) IS DISTINCT FROM (to_jsonb(OLD)-v_cambios) THEN
    RAISE EXCEPTION 'El cierre conserva identidad, contenido, autoría y origen' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_03_asignacion_alumno_cierre BEFORE INSERT OR UPDATE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();
CREATE TRIGGER tr_03_asignacion_direccion_cierre BEFORE INSERT OR UPDATE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();
CREATE TRIGGER tr_03_acompanamiento_cierre BEFORE INSERT OR UPDATE ON banco.acompanamiento
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();
CREATE TRIGGER tr_03_candidatura_cierre BEFORE INSERT OR UPDATE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();
CREATE TRIGGER tr_03_solicitud_direccion_cierre BEFORE INSERT OR UPDATE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();
CREATE TRIGGER tr_03_revision_cierre BEFORE INSERT OR UPDATE ON banco.revision_proyecto
FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();

CREATE FUNCTION banco.comprobar_cierre_proyecto(p_proyecto banco.proyecto,p_actual boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_esperado jsonb;
  v_alcance jsonb; v_estado text; v_fila record; v_candidaturas jsonb;
BEGIN
  v_evento:=banco.evento_cierre_proyecto(p_proyecto.evento_cierre_id,p_proyecto.id,p_actual);
  v_datos:=v_evento.resultado::jsonb;
  v_estado:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizado' ELSE 'cancelado' END;
  IF p_proyecto.estado IS DISTINCT FROM v_estado
    OR banco.alcance_cierre_proyecto(p_proyecto.id) IS DISTINCT FROM
      jsonb_build_object('alumnos','[]'::jsonb,'direcciones','[]'::jsonb,'acompanamientos','[]'::jsonb,
        'candidaturas','[]'::jsonb,'solicitudes','[]'::jsonb,'revisiones','[]'::jsonb) THEN
    RAISE EXCEPTION 'Un proyecto cerrado no conserva reservas ni solicitudes pendientes' USING ERRCODE='23514';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'estado',e.estado) ORDER BY c.id),'[]'::jsonb)
    INTO v_candidaturas FROM banco.candidatura c
    LEFT JOIN LATERAL (SELECT valor->>'estado' estado
      FROM jsonb_array_elements(v_datos #> '{alcance,candidaturas}') x(valor)
      WHERE valor->>'id'=c.id::text LIMIT 1) e ON true
    WHERE c.proyecto_id=p_proyecto.id AND c.evento_cierre_id=v_evento.id AND c.estado='cancelada';
  v_alcance:=jsonb_build_object(
    'alumnos',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.asignacion_alumno
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id),
    'direcciones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.asignacion_direccion
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id),
    'acompanamientos',(SELECT COALESCE(jsonb_agg(a.id ORDER BY a.id),'[]'::jsonb)
      FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
      WHERE x.proyecto_id=p_proyecto.id AND a.evento_cierre_id=v_evento.id),
    'candidaturas',v_candidaturas,
    'solicitudes',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.solicitud_direccion
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id AND estado='cancelada'),
    'revisiones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.revision_proyecto
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id AND estado_revision='cancelada'));
  v_esperado:=jsonb_build_object('motivo',v_datos->>'motivo','estado_anterior',v_datos->>'estado_anterior',
    'evento_inicio_id',p_proyecto.evento_inicio_id,'evento_estado_id',p_proyecto.evento_estado_id,
    'revision_publicada_id',p_proyecto.revision_publicada_id,'alcance',v_alcance,'transaccion_id',v_datos->>'transaccion_id');
  IF v_datos IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'La evidencia de cierre no coincide con todos sus registros y antecedentes' USING ERRCODE='23514';
  END IF;
  FOR v_fila IN SELECT * FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id LOOP
    PERFORM banco.comprobar_periodo_cierre(v_evento.id,p_proyecto.id,'alumnos',v_fila.id,v_fila.estado,v_fila.inicio,v_fila.fin,p_actual);
  END LOOP;
  FOR v_fila IN SELECT * FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id LOOP
    PERFORM banco.comprobar_periodo_cierre(v_evento.id,p_proyecto.id,'direcciones',v_fila.id,v_fila.estado,v_fila.inicio,v_fila.fin,p_actual);
  END LOOP;
END;
$$;

CREATE FUNCTION banco.validar_cierre_proyecto_diferido()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_id bigint; v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME='proyecto' THEN v_id:=NEW.id;
  ELSIF TG_TABLE_NAME='acompanamiento' THEN
    SELECT proyecto_id INTO v_id FROM banco.asignacion_alumno WHERE id=NEW.asignacion_alumno_id;
  ELSE v_id:=NEW.proyecto_id; END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_id FOR UPDATE;
  IF FOUND AND v_proyecto.estado IN ('finalizado','cancelado') THEN
    PERFORM banco.comprobar_cierre_proyecto(v_proyecto,false);
  ELSIF NEW.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'El cierre de un participante o solicitud requiere el cierre coordinado del proyecto' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_proyecto_cierre AFTER INSERT OR UPDATE ON banco.proyecto
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_cierre AFTER INSERT OR UPDATE ON banco.asignacion_alumno
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_cierre AFTER INSERT OR UPDATE ON banco.asignacion_direccion
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_acompanamiento_cierre AFTER INSERT OR UPDATE ON banco.acompanamiento
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_candidatura_cierre AFTER INSERT OR UPDATE ON banco.candidatura
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_solicitud_direccion_cierre AFTER INSERT OR UPDATE ON banco.solicitud_direccion
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();
CREATE CONSTRAINT TRIGGER ct_revision_cierre AFTER INSERT OR UPDATE ON banco.revision_proyecto
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();

CREATE FUNCTION banco.cerrar_proyecto(p_proyecto bigint,p_admin bigint,p_motivo text,p_destino text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE; v_alcance jsonb; v_actual jsonb;
  v_evento bigint; v_fecha timestamptz; v_estado_asignacion text; v_fila record;
  v_perfiles jsonb; v_operacion text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_destino IS NULL OR p_destino NOT IN ('finalizado','cancelado') THEN
    RAISE EXCEPTION 'Destino de cierre no reconocido' USING ERRCODE='22023';
  END IF;
  IF p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El cierre requiere motivo no blanco' USING ERRCODE='23514';
  END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF NOT EXISTS(SELECT 1 FROM banco.proyecto WHERE id=p_proyecto) THEN
    RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503';
  END IF;
  v_alcance:=banco.alcance_cierre_proyecto(p_proyecto);
  -- Las fuentes se bloquean antes de los perfiles: una autorización y las
  -- cancelaciones propias también siguen fuente -> perfil. No invertirlo.
  PERFORM id FROM banco.candidatura WHERE proyecto_id=p_proyecto
    AND (estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      OR id IN (SELECT candidatura_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'))
    ORDER BY id FOR UPDATE;
  PERFORM id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto
    AND (estado='pendiente' OR id IN (SELECT solicitud_direccion_id FROM banco.asignacion_direccion
      WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
  -- Conjuntos de perfiles leídos sin retener Proyecto; nunca se incorpora un
  -- perfil nuevo después de tomarlo. Dos cierres usan alumno/id, profesor/id.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo',tipo,'id',id) ORDER BY tipo,id),'[]'::jsonb)
    INTO v_perfiles FROM (
      SELECT 'alumno'::text tipo,alumno_id id FROM banco.candidatura WHERE proyecto_id=p_proyecto
        AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT 'alumno',alumno_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'
      UNION SELECT 'profesor',profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'
      UNION SELECT 'profesor',profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente') q;
  FOR v_fila IN SELECT x->>'tipo' tipo,(x->>'id')::bigint id FROM jsonb_array_elements(v_perfiles) x LOOP
    IF v_fila.tipo='alumno' THEN
      PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.id FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.id FOR UPDATE; END IF;
  END LOOP;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF v_proyecto.estado IN ('finalizado','cancelado') THEN
    IF v_proyecto.estado<>p_destino THEN RAISE EXCEPTION 'El cierre definitivo no se sustituye ni reabre' USING ERRCODE='55000'; END IF;
    PERFORM banco.comprobar_cierre_proyecto(v_proyecto,false);
    RETURN v_proyecto.evento_cierre_id;
  END IF;
  IF (p_destino='finalizado' AND v_proyecto.estado<>'en_curso')
    OR (p_destino='cancelado' AND v_proyecto.estado NOT IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
    RAISE EXCEPTION 'El estado actual no admite este cierre administrativo' USING ERRCODE='55000';
  END IF;
  v_actual:=banco.alcance_cierre_proyecto(p_proyecto);
  IF v_actual IS DISTINCT FROM v_alcance THEN
    RAISE EXCEPTION 'El alcance del cierre cambió durante la espera; reintentar la transacción completa' USING ERRCODE='40001';
  END IF;
  -- Después de Proyecto solo se toman padres, hijos y revisión. Las reservas
  -- nuevas esperan Proyecto y revalidan el estado terminal al obtenerlo.
  PERFORM id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente' ORDER BY id FOR UPDATE;
  PERFORM id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente' ORDER BY id FOR UPDATE;
  PERFORM a.id FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
    WHERE x.proyecto_id=p_proyecto AND a.estado='vigente' ORDER BY a.id FOR UPDATE OF a;
  PERFORM id FROM banco.revision_proyecto WHERE proyecto_id=p_proyecto AND estado_revision='en_revision' ORDER BY id FOR UPDATE;
  -- Los acompañamientos pueden escribirse tomando solo sus padres. Si alguno
  -- terminó de incorporarse mientras adquiríamos esos padres, no queda fuera.
  IF banco.alcance_cierre_proyecto(p_proyecto) IS DISTINCT FROM v_alcance THEN
    RAISE EXCEPTION 'El alcance del cierre cambió durante la espera; reintentar la transacción completa' USING ERRCODE='40001';
  END IF;
  IF p_destino='finalizado' THEN
    -- En curso mantiene sus condiciones operativas; finalizar no acredita
    -- calificaciones o entregables y no permite saltar una pausa pendiente.
    v_publicado:=v_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.comprobar_condiciones_inicio(v_publicado);
  END IF;
  v_operacion:=CASE p_destino WHEN 'finalizado' THEN 'finalizar_proyecto' ELSE 'cancelar_proyecto' END;
  v_estado_asignacion:=CASE p_destino WHEN 'finalizado' THEN 'finalizada' ELSE 'revocada' END;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario',v_operacion,'proyecto',p_proyecto::text,v_proyecto.estado || ' -> ' || p_destino,
      jsonb_build_object('motivo',p_motivo,'estado_anterior',v_proyecto.estado,'evento_inicio_id',v_proyecto.evento_inicio_id,
        'evento_estado_id',v_proyecto.evento_estado_id,'revision_publicada_id',v_proyecto.revision_publicada_id,'alcance',v_alcance)::text)
    RETURNING id,fecha INTO v_evento,v_fecha;
  UPDATE banco.asignacion_alumno SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='vigente';
  UPDATE banco.asignacion_direccion SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='vigente';
  UPDATE banco.acompanamiento a SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>a.inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento FROM banco.asignacion_alumno x
    WHERE x.id=a.asignacion_alumno_id AND x.proyecto_id=p_proyecto AND a.estado='vigente';
  UPDATE banco.candidatura SET estado='cancelada',evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto
    AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
  UPDATE banco.solicitud_direccion SET estado='cancelada',evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='pendiente';
  UPDATE banco.revision_proyecto SET estado_revision='cancelada',evento_cierre_id=v_evento
    WHERE proyecto_id=p_proyecto AND estado_revision='en_revision';
  UPDATE banco.proyecto SET estado=p_destino,evento_cierre_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;
CREATE FUNCTION banco.finalizar_proyecto(p_proyecto bigint,p_admin bigint,p_motivo text)
RETURNS bigint LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
  SELECT banco.cerrar_proyecto(p_proyecto,p_admin,p_motivo,'finalizado');
$$;
CREATE FUNCTION banco.cancelar_proyecto(p_proyecto bigint,p_admin bigint,p_motivo text)
RETURNS bigint LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco AS $$
  SELECT banco.cerrar_proyecto(p_proyecto,p_admin,p_motivo,'cancelado');
$$;

-- Extensiones puntuales de los controles 013; conservan retiro y continuidad.

CREATE OR REPLACE FUNCTION banco.marcar_evento_operacion_actual()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_datos jsonb;
BEGIN
  IF NEW.operacion IN ('retirar_alumno','retirar_director','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto') THEN
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

CREATE OR REPLACE FUNCTION banco.proteger_asignaciones_iniciadas()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT estado INTO v_estado FROM banco.proyecto WHERE id=NEW.proyecto_id;
  IF TG_OP='UPDATE' AND NEW.evento_cierre_id IS NOT NULL THEN
    -- tr_03 valida el cierre exacto y el control diferido exige su proyecto terminal.
    RETURN NEW;
  END IF;
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

CREATE OR REPLACE FUNCTION banco.proteger_publicacion_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_evento banco.evento_auditoria%ROWTYPE;
  v_retiro banco.evento_auditoria%ROWTYPE; v_previo banco.evento_auditoria%ROWTYPE;
  v_datos jsonb; v_esperado jsonb; v_participantes jsonb; v_retiro_valido boolean;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_OP='UPDATE' AND OLD.estado IN ('finalizado','cancelado') THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'El proyecto cerrado conserva su historia; no se reabre ni modifica' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado IN ('finalizado','cancelado') THEN
    IF TG_OP<>'UPDATE' OR NEW.evento_cierre_id IS NULL THEN
      RAISE EXCEPTION 'D-07: el cierre requiere su operación administrativa específica' USING ERRCODE='55000';
    END IF;
    IF (NEW.estado='finalizado' AND OLD.estado<>'en_curso')
      OR (NEW.estado='cancelado' AND OLD.estado NOT IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
      RAISE EXCEPTION 'El estado anterior no admite este cierre administrativo' USING ERRCODE='55000';
    END IF;
    IF (to_jsonb(NEW)-ARRAY['estado','evento_cierre_id']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['estado','evento_cierre_id']) THEN
      RAISE EXCEPTION 'El cierre conserva contenido, autoría, publicación y eventos anteriores' USING ERRCODE='55000';
    END IF;
    v_evento:=banco.evento_cierre_proyecto(NEW.evento_cierre_id,NEW.id,true);
    IF v_evento.resultado::jsonb->>'estado_anterior' IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'El cierre conserva el estado anterior exacto' USING ERRCODE='23514';
    END IF;
    PERFORM banco.comprobar_cierre_proyecto(NEW,true);
    RETURN NEW;
  END IF;
  IF NEW.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'La evidencia de cierre solo pertenece a un proyecto terminal' USING ERRCODE='23514';
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

CREATE OR REPLACE FUNCTION banco.comprobar_acompanamiento_estado(p_vinculo banco.acompanamiento)
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
  IF p_vinculo.evento_cierre_id IS NOT NULL THEN
    IF p_vinculo.evento_retiro_id IS NOT NULL
      OR v_alumno.evento_cierre_id IS DISTINCT FROM p_vinculo.evento_cierre_id
      OR v_direccion.evento_cierre_id IS DISTINCT FROM p_vinculo.evento_cierre_id THEN
      RAISE EXCEPTION 'El acompañamiento cierra con ambas asignaciones en la misma operación' USING ERRCODE='23514';
    END IF;
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_alumno.proyecto_id,'alumnos',
      v_alumno.id,v_alumno.estado,v_alumno.inicio,v_alumno.fin,false);
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_direccion.proyecto_id,'direcciones',
      v_direccion.id,v_direccion.estado,v_direccion.inicio,v_direccion.fin,false);
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_alumno.proyecto_id,'acompanamientos',
      p_vinculo.id,p_vinculo.estado,p_vinculo.inicio,p_vinculo.fin,false);
    -- Un periodo que aún no empezó no tiene intervalo efectivo que contener.
    IF p_vinculo.fin IS NULL THEN RETURN; END IF;
  ELSIF p_vinculo.evento_retiro_id IS NOT NULL THEN
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
  ELSIF p_vinculo.estado IN ('revocada','finalizada') AND p_vinculo.fin IS NULL THEN
    RAISE EXCEPTION 'Una revocación anterior al inicio requiere su evidencia exacta' USING ERRCODE='23514';
  END IF;
  IF (v_alumno.estado<>'vigente' AND v_alumno.fin IS NULL)
    OR (v_direccion.estado<>'vigente' AND v_direccion.fin IS NULL)
    OR (v_alumno.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_alumno.fin))
    OR (v_direccion.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_direccion.fin)) THEN
    RAISE EXCEPTION 'La vigencia efectiva del acompañamiento debe quedar contenida en ambas asignaciones' USING ERRCODE='23514';
  END IF;
END;
$$;

-- En BEFORE UPDATE, las columnas generadas aún no contienen su nuevo valor.
-- Comparar solo las columnas almacenadas permite un no-op histórico sin
-- confundir resultado_decision NULL transitorio con una reescritura real.
CREATE OR REPLACE FUNCTION banco.impedir_reescritura_origen()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME IN ('asignacion_alumno','asignacion_direccion')
    AND OLD.estado<>'vigente'
    AND (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
    RAISE EXCEPTION 'Una asignación cerrada conserva su historial; una rectificación requiere procedimiento explícito'
      USING ERRCODE='55000';
  END IF;
  IF TG_TABLE_NAME='candidatura' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.alumno_id IS DISTINCT FROM OLD.alumno_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen de una candidatura no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.profesor_id IS DISTINCT FROM OLD.profesor_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen de una solicitud de dirección no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSIF TG_TABLE_NAME='asignacion_alumno' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.candidatura_id IS DISTINCT FROM OLD.candidatura_id
      OR NEW.decision_id IS DISTINCT FROM OLD.decision_id OR NEW.alumno_id IS DISTINCT FROM OLD.alumno_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen autorizado de la asignación de alumno no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.solicitud_direccion_id IS DISTINCT FROM OLD.solicitud_direccion_id
      OR NEW.decision_id IS DISTINCT FROM OLD.decision_id OR NEW.profesor_id IS DISTINCT FROM OLD.profesor_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen autorizado de la dirección no puede cambiar' USING ERRCODE='23503';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON COLUMN banco.proyecto.evento_cierre_id IS
  'D-07: cierre definitivo administrativo exacto; conserva primer inicio y última pausa/reanudación sin inventarlos para proyectos no iniciados.';
COMMENT ON COLUMN banco.asignacion_alumno.evento_cierre_id IS
  'Cierre coordinado del proyecto; finalizada o revocada libera reservas. Fin NULL con evento exacto expresa periodo no iniciado, no ejecución académica.';
COMMENT ON COLUMN banco.asignacion_direccion.evento_cierre_id IS
  'Cierre coordinado del proyecto, separado del retiro individual. Conserva fuente y decisión aprobadas y la fecha real del evento.';
COMMENT ON COLUMN banco.acompanamiento.evento_cierre_id IS
  'Cierre coordinado con ambos padres; conserva periodos previos y no inventa final para un periodo futuro.';
COMMENT ON COLUMN banco.candidatura.evento_cierre_id IS
  'Cancelación automática de candidatura activa al cerrar el proyecto; conserva evaluación e historial y libera el máximo de tres.';
COMMENT ON COLUMN banco.solicitud_direccion.evento_cierre_id IS
  'Cancelación de solicitud aún pendiente por cierre del proyecto; no reescribe una fuente ya aprobada.';
COMMENT ON COLUMN banco.revision_proyecto.evento_cierre_id IS
  'Revisión pendiente cancelada por cierre del proyecto; conserva instantánea sin fabricar decisión de rechazo.';
COMMENT ON FUNCTION banco.finalizar_proyecto(bigint,bigint,text) IS
  'D-07: administrador activo y motivo finalizan solo En curso; cierre atómico de reservas, acompañamientos y pendientes, historia conservada. Función interna INVOKER, no autentica IDs.';
COMMENT ON FUNCTION banco.cancelar_proyecto(bigint,bigint,text) IS
  'D-07: administrador activo y motivo cancelan un proyecto abierto; cierre coordinado e idempotente con liberación de cupos/carga y conservación histórica. Sin avisos ni reapertura.';

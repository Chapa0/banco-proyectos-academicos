-- D-11: avisos internos atómicos, sin envío externo ni copia de contenido privado.
-- Hacia delante: no se generan avisos para eventos históricos.
CREATE FUNCTION banco.notificar_evento()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_id bigint; v_proyecto bigint; v_titular bigint; v_destinos bigint[]:='{}';
  v_empresa boolean:=false; v_admin boolean:=false; v_participantes boolean:=false;
  v_mensaje text;
BEGIN
  IF NEW.operacion NOT IN ('enviar_proyecto','resolver_publicacion','presentar_candidatura',
    'cancelar_candidatura','solicitar_direccion','cancelar_solicitud_direccion',
    'evaluar_candidatura','preseleccionar_candidatura','resolver_candidatura','resolver_direccion',
    'iniciar_proyecto','retirar_alumno','retirar_director','pausar_proyecto',
    'reanudar_proyecto','finalizar_proyecto','cancelar_proyecto','crear_cuenta',
    'crear_empresa_con_representante','relevar_representante','cambiar_estado_cuenta') THEN
    RETURN NEW;
  END IF;
  IF NEW.registro_afectado !~ '^-?[0-9]+$' THEN RETURN NEW; END IF;
  BEGIN v_id:=NEW.registro_afectado::bigint;
  EXCEPTION WHEN numeric_value_out_of_range THEN RETURN NEW; END;
  CASE NEW.entidad_afectada
    WHEN 'proyecto' THEN SELECT id INTO v_proyecto FROM banco.proyecto WHERE id=v_id;
    WHEN 'candidatura' THEN
      SELECT proyecto_id,alumno_id INTO v_proyecto,v_titular FROM banco.candidatura WHERE id=v_id;
    WHEN 'solicitud_direccion' THEN
      SELECT proyecto_id,profesor_id INTO v_proyecto,v_titular FROM banco.solicitud_direccion WHERE id=v_id;
    WHEN 'evaluacion_candidato' THEN
      SELECT c.proyecto_id,c.alumno_id INTO v_proyecto,v_titular FROM banco.evaluacion_candidato e
        JOIN banco.candidatura c ON c.id=e.candidatura_id WHERE e.id=v_id;
    WHEN 'asignacion_alumno' THEN
      SELECT proyecto_id,alumno_id INTO v_proyecto,v_titular FROM banco.asignacion_alumno WHERE id=v_id;
    WHEN 'asignacion_direccion' THEN
      SELECT proyecto_id,profesor_id INTO v_proyecto,v_titular FROM banco.asignacion_direccion WHERE id=v_id;
    WHEN 'usuario' THEN v_titular:=v_id;
    WHEN 'empresa' THEN
      SELECT usuario_id INTO v_titular FROM banco.representacion_empresa WHERE empresa_id=v_id AND vigente;
    ELSE RETURN NEW;
  END CASE;
  CASE NEW.operacion
    WHEN 'enviar_proyecto','solicitar_direccion','cancelar_solicitud_direccion' THEN v_admin:=true;
    WHEN 'presentar_candidatura','cancelar_candidatura','resolver_publicacion' THEN v_empresa:=true;
    WHEN 'preseleccionar_candidatura' THEN
      v_admin:=true;v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'evaluar_candidatura' THEN v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'resolver_candidatura','resolver_direccion','retirar_alumno','retirar_director' THEN
      v_empresa:=true;v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'iniciar_proyecto','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto' THEN
      v_empresa:=true;v_participantes:=true;
    ELSE v_destinos:=array_append(v_destinos,v_titular);
  END CASE;
  IF v_empresa AND v_proyecto IS NOT NULL THEN
    v_destinos:=v_destinos || ARRAY(SELECT r.usuario_id FROM banco.proyecto p
      JOIN banco.representacion_empresa r ON r.empresa_id=p.empresa_id AND r.vigente WHERE p.id=v_proyecto);
  END IF;
  IF v_admin THEN
    v_destinos:=v_destinos || ARRAY(SELECT id FROM banco.usuario WHERE rol_principal='administrador' AND estado_cuenta='activa');
  END IF;
  IF v_participantes AND v_proyecto IS NOT NULL THEN
    -- El evento raíz se inserta antes de cerrar sus hijos. En el cierre quedan
    -- incluidos todos los titulares afectados, sin un aviso por cada hijo.
    v_destinos:=v_destinos || ARRAY(SELECT alumno_id FROM banco.asignacion_alumno
      WHERE proyecto_id=v_proyecto AND estado='vigente'
      UNION SELECT profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=v_proyecto AND estado='vigente'
      UNION SELECT alumno_id FROM banco.candidatura WHERE proyecto_id=v_proyecto
        AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=v_proyecto AND estado='pendiente');
  END IF;
  v_mensaje:=CASE NEW.operacion
    WHEN 'enviar_proyecto' THEN 'Hay un proyecto pendiente de revisión.'
    WHEN 'resolver_publicacion' THEN 'Se resolvió la revisión de tu proyecto.'
    WHEN 'presentar_candidatura' THEN 'Tu proyecto recibió una candidatura.'
    WHEN 'cancelar_candidatura' THEN 'Se canceló una candidatura de tu proyecto.'
    WHEN 'solicitar_direccion' THEN 'Hay una solicitud de dirección pendiente.'
    WHEN 'cancelar_solicitud_direccion' THEN 'Se canceló una solicitud de dirección pendiente.'
    WHEN 'evaluar_candidatura' THEN 'Tu candidatura tiene una nueva evaluación.'
    WHEN 'preseleccionar_candidatura' THEN 'Se preseleccionó una candidatura para autorización.'
    WHEN 'resolver_candidatura' THEN 'Se resolvió una candidatura relacionada contigo.'
    WHEN 'resolver_direccion' THEN 'Se resolvió una solicitud de dirección relacionada contigo.'
    WHEN 'iniciar_proyecto' THEN 'Se confirmó el inicio de un proyecto relacionado contigo.'
    WHEN 'retirar_alumno' THEN 'Se registró un retiro de alumno.'
    WHEN 'retirar_director' THEN 'Se registró un retiro de dirección.'
    WHEN 'pausar_proyecto' THEN 'Un proyecto relacionado contigo quedó pausado.'
    WHEN 'reanudar_proyecto' THEN 'Se confirmó la reanudación de un proyecto relacionado contigo.'
    WHEN 'finalizar_proyecto' THEN 'Se finalizó un proyecto relacionado contigo.'
    WHEN 'cancelar_proyecto' THEN 'Se canceló un proyecto relacionado contigo.'
    ELSE 'Se actualizó tu cuenta o representación empresarial.' END;
  INSERT INTO banco.notificacion(destinatario_usuario_id,evento_id,mensaje,fecha)
    SELECT DISTINCT u.id,NEW.id,v_mensaje,clock_timestamp() FROM banco.usuario u
    WHERE u.id=ANY(v_destinos) AND u.estado_cuenta='activa'
      AND u.id IS DISTINCT FROM NEW.actor_usuario_id
    ON CONFLICT(evento_id,destinatario_usuario_id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_notificar_evento AFTER INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION banco.notificar_evento();

CREATE FUNCTION banco.proteger_notificacion()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Los avisos se conservan' USING ERRCODE='55000'; END IF;
  IF (to_jsonb(NEW)-'fecha_lectura') IS DISTINCT FROM (to_jsonb(OLD)-'fecha_lectura')
    OR (OLD.fecha_lectura IS NOT NULL AND NEW.fecha_lectura IS DISTINCT FROM OLD.fecha_lectura) THEN
    RAISE EXCEPTION 'Solo se permite registrar la primera lectura del aviso' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_notificacion_historial BEFORE UPDATE OR DELETE ON banco.notificacion
FOR EACH ROW EXECUTE FUNCTION banco.proteger_notificacion();

CREATE FUNCTION banco.marcar_notificacion_leida(p_notificacion bigint,p_usuario bigint)
RETURNS timestamptz LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_aviso banco.notificacion%ROWTYPE;v_rol text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_aviso FROM banco.notificacion WHERE id=p_notificacion FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aviso inexistente' USING ERRCODE='23503'; END IF;
  IF v_aviso.destinatario_usuario_id IS DISTINCT FROM p_usuario THEN
    RAISE EXCEPTION 'Solo el destinatario puede leer el aviso' USING ERRCODE='23514'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_usuario;
  PERFORM banco.exigir_rol(p_usuario,v_rol,true);
  IF v_aviso.fecha_lectura IS NULL THEN
    UPDATE banco.notificacion SET fecha_lectura=greatest(clock_timestamp(),fecha)
      WHERE id=p_notificacion RETURNING fecha_lectura INTO v_aviso.fecha_lectura;
  END IF;
  RETURN v_aviso.fecha_lectura;
END;
$$;
CREATE FUNCTION banco.consultar_notificaciones(p_usuario bigint,p_limite integer DEFAULT 50,p_antes_id bigint DEFAULT NULL)
RETURNS TABLE(id bigint,evento_id bigint,mensaje text,fecha timestamptz,fecha_lectura timestamptz)
LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_rol text;
BEGIN
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 THEN
    RAISE EXCEPTION 'El límite de consulta debe estar entre 1 y 100' USING ERRCODE='23514'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE usuario.id=p_usuario;
  PERFORM banco.exigir_rol(p_usuario,v_rol,true);
  RETURN QUERY SELECT n.id,n.evento_id,n.mensaje,n.fecha,n.fecha_lectura FROM banco.notificacion n
    WHERE n.destinatario_usuario_id=p_usuario AND (p_antes_id IS NULL OR n.id<p_antes_id)
    ORDER BY n.id DESC LIMIT p_limite;
END;
$$;
REVOKE ALL ON FUNCTION banco.notificar_evento(),banco.proteger_notificacion(),
  banco.marcar_notificacion_leida(bigint,bigint),banco.consultar_notificaciones(bigint,integer,bigint)
  FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON TABLE banco.notificacion IS
  'D-10/D-11: avisos internos por evento y destinatario activo; sin envío externo ni copia de motivos/evidencias. Lectura propia y conservación; no autentica IDs recibidos.';
COMMENT ON COLUMN banco.alumno_habilidad.evidencia IS
  'D-11: texto descriptivo o enlace escrito, sin adjuntos ni descarga automática. Visibilidad según D-10; tratar como texto sin ejecutar en la futura interfaz.';

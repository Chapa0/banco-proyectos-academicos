-- WEB-06: participación, evaluación y ciclo por actor/recurso.
-- Ocho gateways mínimos; sin DML general ni cambios en 001-022.
-- Evolución hacia delante: preservar respaldo y corregir mediante otra migración.

CREATE FUNCTION banco.web_participacion_base(p_tipo text,p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_datos jsonb;
BEGIN
  IF p_tipo='candidatura' THEN
    SELECT to_jsonb(c)||jsonb_build_object('titular_id',alumno_id,'tipo',p_tipo) INTO v_datos FROM banco.candidatura c WHERE id=p_id;
  ELSIF p_tipo='direccion' THEN
    SELECT to_jsonb(s)||jsonb_build_object('titular_id',profesor_id,'tipo',p_tipo) INTO v_datos FROM banco.solicitud_direccion s WHERE id=p_id;
  ELSE RAISE EXCEPTION 'Tipo de participación inválido' USING ERRCODE='22023'; END IF;
  IF v_datos IS NULL THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='23503'; END IF;
  RETURN v_datos;
END;
$$;

CREATE FUNCTION banco.web_abrir_participacion(p_actor bigint,p_tipo text,p_id bigint,p_escritura boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_datos jsonb;v_rol text;v_titular bigint;v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo='candidatura' THEN
    IF p_escritura THEN PERFORM id FROM banco.candidatura WHERE id=p_id FOR UPDATE;
    ELSE PERFORM id FROM banco.candidatura WHERE id=p_id FOR SHARE; END IF;
  ELSIF p_tipo='direccion' THEN
    IF p_escritura THEN PERFORM id FROM banco.solicitud_direccion WHERE id=p_id FOR UPDATE;
    ELSE PERFORM id FROM banco.solicitud_direccion WHERE id=p_id FOR SHARE; END IF;
  ELSE RAISE EXCEPTION 'Tipo de participación inválido' USING ERRCODE='22023'; END IF;
  v_datos:=banco.web_participacion_base(p_tipo,p_id);v_titular:=(v_datos->>'titular_id')::bigint;
  -- El orden coincide con evaluación/autorización/cancelación: fuente, perfil, proyecto, actor.
  IF p_tipo='candidatura' THEN
    IF p_escritura THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_titular FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_titular FOR SHARE; END IF;
  ELSE
    IF p_escritura THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_titular FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_titular FOR SHARE; END IF;
  END IF;
  IF p_escritura THEN SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=(v_datos->>'proyecto_id')::bigint FOR UPDATE;
  ELSE SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=(v_datos->>'proyecto_id')::bigint FOR SHARE; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('alumno','profesor','empresa','administrador') THEN
    RAISE EXCEPTION 'Acceso no permitido' USING ERRCODE='42501'; END IF;
  IF v_rol<>'empresa' THEN PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF v_rol='administrador' OR (v_rol='alumno' AND p_tipo='candidatura' AND v_titular=p_actor)
    OR (v_rol='profesor' AND p_tipo='direccion' AND v_titular=p_actor) THEN RETURN v_datos; END IF;
  IF v_rol='empresa' AND p_tipo='candidatura' THEN
    IF NOT EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE usuario_id=p_actor AND empresa_id=v_proyecto.empresa_id AND vigente) THEN
      RAISE EXCEPTION 'La solicitud queda fuera de tu empresa' USING ERRCODE='42501'; END IF;
    PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);RETURN v_datos;
  END IF;
  RAISE EXCEPTION 'La solicitud queda fuera de tu ámbito' USING ERRCODE='42501';
END;
$$;

CREATE FUNCTION banco.web_version_ciclo(p_proyecto bigint)
RETURNS text LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
 SELECT encode(sha256(convert_to(jsonb_build_object('proyecto',banco.web_version_proyecto(p_proyecto),
  'candidaturas',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM banco.candidatura c WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'direcciones',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM banco.solicitud_direccion s WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'alumnos',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM banco.asignacion_alumno a WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'directores',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM banco.asignacion_direccion a WHERE proyecto_id=p_proyecto),'[]'::jsonb)
 )::text,'UTF8')),'hex');
$$;

CREATE FUNCTION banco.web_version_participacion(p_tipo text,p_id bigint)
RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_datos jsonb;
BEGIN
  v_datos:=banco.web_participacion_base(p_tipo,p_id);
  RETURN encode(sha256(convert_to(jsonb_build_object('solicitud',v_datos,
    'perfil',banco.web_version_perfil((v_datos->>'titular_id')::bigint),
    'ciclo',banco.web_version_ciclo((v_datos->>'proyecto_id')::bigint),
    'evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria WHERE entidad_afectada=
      CASE p_tipo WHEN 'candidatura' THEN 'candidatura' ELSE 'solicitud_direccion' END AND registro_afectado=p_id::text)
  )::text,'UTF8')),'hex');
END;
$$;

CREATE FUNCTION banco.web_admite_participacion(p_proyecto banco.proyecto,p_tipo text)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE;v_revision banco.revision_proyecto%ROWTYPE;
BEGIN
  IF p_tipo NOT IN ('candidatura','direccion') OR p_proyecto.estado NOT IN ('publicado','pausado') THEN RETURN false; END IF;
  v_publicado:=p_proyecto;v_publicado.estado:='publicado';
  SELECT * INTO v_revision FROM banco.revision_proyecto WHERE id=p_proyecto.revision_publicada_id;
  IF NOT FOUND OR NOT coalesce(banco.web_catalogo_publicacion_valida(v_publicado,v_revision),false) THEN RETURN false; END IF;
  RETURN p_proyecto.estado='publicado' OR
    (p_tipo='candidatura' AND NOT EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente')) OR
    (p_tipo='direccion' AND NOT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente'));
END;
$$;

CREATE FUNCTION banco.web_acciones_participacion(p_actor bigint,p_tipo text,p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_s jsonb;v_rol text;v_p banco.proyecto%ROWTYPE;v_activa boolean;v_resultado jsonb:='[]';
BEGIN
  v_s:=banco.web_participacion_base(p_tipo,p_id);
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=(v_s->>'proyecto_id')::bigint;
  v_activa:=CASE WHEN p_tipo='candidatura' THEN v_s->>'estado' IN ('pendiente_evaluacion','evaluada','preseleccionada') ELSE v_s->>'estado'='pendiente' END;
  IF p_actor=(v_s->>'titular_id')::bigint AND v_activa THEN v_resultado:=v_resultado||'"cancelar"'::jsonb; END IF;
  IF v_rol='empresa' AND p_tipo='candidatura' AND v_activa AND banco.web_admite_participacion(v_p,p_tipo) THEN
    v_resultado:=v_resultado||'"evaluar"'::jsonb;
    IF v_s->>'estado'='evaluada' AND EXISTS(SELECT 1 FROM banco.evaluacion_candidato
      WHERE id=(v_s->>'evaluacion_vigente_id')::bigint AND recomendacion='recomendada') THEN
      v_resultado:=v_resultado||'"preseleccionar"'::jsonb;
    END IF;
  END IF;
  IF v_rol='administrador' AND v_activa AND v_p.estado IN ('publicado','en_curso','pausado') THEN
    v_resultado:=v_resultado||'"rechazar"'::jsonb;
    IF banco.web_admite_participacion(v_p,p_tipo) AND (p_tipo='direccion' OR v_s->>'estado'='preseleccionada') THEN
      v_resultado:=v_resultado||'"aprobar"'::jsonb;
    END IF;
  END IF;
  RETURN v_resultado;
END;
$$;

CREATE FUNCTION banco.web_bandeja_participacion(p_actor bigint,p_tipo text,p_estado text,p_buscar text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;v_empresa bigint;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('candidatura','direccion')
    OR (v_rol='alumno' AND p_tipo<>'candidatura') OR (v_rol='profesor' AND p_tipo<>'direccion')
    OR (v_rol='empresa' AND p_tipo<>'candidatura') THEN RAISE EXCEPTION 'Bandeja no autorizada' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN v_empresa:=banco.web_empresa_del_actor(p_actor);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(p_buscar)>150 OR (nullif(p_estado,'') IS NOT NULL AND
      ((p_tipo='candidatura' AND p_estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada','aprobada','rechazada','cancelada'))
      OR(p_tipo='direccion' AND p_estado NOT IN ('pendiente','aprobada','rechazada','cancelada')))) THEN
    RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH fuentes AS (
    SELECT id,alumno_id AS titular_id,proyecto_id,estado,fecha_solicitud FROM banco.candidatura WHERE p_tipo='candidatura'
    UNION ALL SELECT id,profesor_id,proyecto_id,estado,fecha_solicitud FROM banco.solicitud_direccion WHERE p_tipo='direccion'
  ), filtradas AS MATERIALIZED (
    SELECT f.id,p_tipo AS tipo,f.estado,f.fecha_solicitud,f.proyecto_id,p.titulo,p.estado AS proyecto_estado,e.razon_social,u.nombre AS solicitante_nombre
      FROM fuentes f JOIN banco.proyecto p ON p.id=f.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=f.titular_id
      WHERE (v_rol='administrador' OR (v_rol IN ('alumno','profesor') AND f.titular_id=p_actor)
        OR (v_rol='empresa' AND p.empresa_id=v_empresa))
      AND (nullif(p_estado,'') IS NULL OR f.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtradas ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtradas)));
END;
$$;

CREATE FUNCTION banco.web_detalle_participacion(p_actor bigint,p_tipo text,p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_s jsonb;v_p banco.proyecto%ROWTYPE;v_asignacion jsonb;v_evaluaciones jsonb;
BEGIN
  v_s:=banco.web_abrir_participacion(p_actor,p_tipo,p_id,false);
  SELECT * INTO v_p FROM banco.proyecto WHERE id=(v_s->>'proyecto_id')::bigint;
  IF p_tipo='candidatura' THEN
    SELECT jsonb_build_object('id',id,'estado',estado,'inicio',inicio,'fin',fin) INTO v_asignacion FROM banco.asignacion_alumno WHERE candidatura_id=p_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'fecha',e.fecha,'comentarios',e.comentarios,'recomendacion',e.recomendacion,
      'detalles',(SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',d.definicion_aplicada->>'codigo','nombre',d.definicion_aplicada->>'nombre',
        'puntuacion',d.puntuacion,'comentario',d.comentario) ORDER BY d.criterio_id),'[]'::jsonb) FROM banco.detalle_evaluacion d WHERE d.evaluacion_id=e.id)) ORDER BY e.id DESC),'[]'::jsonb)
      INTO v_evaluaciones FROM banco.evaluacion_candidato e WHERE candidatura_id=p_id;
  ELSE SELECT jsonb_build_object('id',id,'estado',estado,'inicio',inicio,'fin',fin) INTO v_asignacion FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_id;
    v_evaluaciones:='[]';
  END IF;
  RETURN jsonb_build_object('solicitud',jsonb_build_object('id',p_id,'tipo',p_tipo,'estado',v_s->>'estado','fecha_solicitud',v_s->'fecha_solicitud',
      'experiencia_aplicable',v_s->'experiencia_aplicable','justificacion',v_s->'justificacion'),
    'proyecto',jsonb_build_object('id',v_p.id,'titulo',v_p.titulo,'estado',v_p.estado,'razon_social',(SELECT razon_social FROM banco.empresa WHERE id=v_p.empresa_id)),
    'perfil',banco.consultar_perfil(p_actor,(v_s->>'titular_id')::bigint),'asignacion',v_asignacion,'evaluaciones',v_evaluaciones,
    'decisiones',(SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',d.fecha,'resultado',d.resultado,'justificacion',d.justificacion,'administrador_nombre',u.nombre) ORDER BY d.id DESC),'[]'::jsonb)
      FROM banco.decision_administrativa d JOIN banco.usuario u ON u.id=d.administrador_usuario_id
      WHERE (p_tipo='candidatura' AND d.candidatura_id=p_id) OR (p_tipo='direccion' AND d.solicitud_direccion_id=p_id)),
    'historial',(SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',e.fecha,'operacion',e.operacion,'transicion',e.transicion,'actor_nombre',u.nombre) ORDER BY e.id DESC),'[]'::jsonb)
      FROM banco.evento_auditoria e LEFT JOIN banco.usuario u ON u.id=e.actor_usuario_id
      WHERE e.entidad_afectada=CASE p_tipo WHEN 'candidatura' THEN 'candidatura' ELSE 'solicitud_direccion' END AND e.registro_afectado=p_id::text),
    'version',banco.web_version_participacion(p_tipo,p_id),'acciones',banco.web_acciones_participacion(p_actor,p_tipo,p_id));
END;
$$;

CREATE FUNCTION banco.web_contexto_postulacion(p_actor bigint,p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;v_tipo text;v_p banco.proyecto%ROWTYPE;v_perfil boolean;v_activas integer;v_carga integer;v_existente jsonb;v_version text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR SHARE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR SHARE;
  ELSE RAISE EXCEPTION 'Solo alumnos y profesores pueden postularse' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  PERFORM banco.web_exigir_academico(p_actor);
  v_tipo:=CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END;
  IF NOT banco.web_admite_participacion(v_p,v_tipo) THEN RAISE EXCEPTION 'El proyecto no recibe solicitudes de este tipo' USING ERRCODE='23503'; END IF;
  IF v_rol='alumno' THEN
    v_perfil:=EXISTS(SELECT 1 FROM banco.alumno WHERE usuario_id=p_actor);
    SELECT count(*) INTO v_activas FROM banco.candidatura WHERE alumno_id=p_actor AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
    SELECT count(*) INTO v_carga FROM banco.asignacion_alumno WHERE alumno_id=p_actor AND estado='vigente';
    SELECT jsonb_build_object('id',id,'estado',estado) INTO v_existente FROM banco.candidatura
      WHERE alumno_id=p_actor AND proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada') ORDER BY id DESC LIMIT 1;
  ELSE
    v_perfil:=EXISTS(SELECT 1 FROM banco.profesor WHERE usuario_id=p_actor);
    SELECT count(*) INTO v_activas FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND estado='pendiente';
    SELECT count(*) INTO v_carga FROM banco.asignacion_direccion WHERE profesor_id=p_actor AND estado='vigente';
    SELECT jsonb_build_object('id',id,'estado',estado) INTO v_existente FROM banco.solicitud_direccion
      WHERE profesor_id=p_actor AND proyecto_id=p_proyecto AND estado='pendiente' ORDER BY id DESC LIMIT 1;
  END IF;
  v_version:=encode(sha256(convert_to(jsonb_build_object('perfil',banco.web_version_perfil(p_actor),'ciclo',banco.web_version_ciclo(p_proyecto),
    'activas',v_activas,'carga',v_carga,'existente',v_existente)::text,'UTF8')),'hex');
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_p)||jsonb_build_object('id',v_p.id,'estado',v_p.estado,
      'razon_social',(SELECT razon_social FROM banco.empresa WHERE id=v_p.empresa_id),
      'habilidades',(SELECT instantanea_contenido->'habilidades' FROM banco.revision_proyecto WHERE id=v_p.revision_publicada_id)),
    'perfil_completo',v_perfil,'version',v_version,'disponibilidad',banco.web_catalogo_disponibilidad(v_p),'activas',v_activas,'carga',v_carga,
    'existente',v_existente,'acciones',CASE WHEN v_perfil AND v_existente IS NULL AND (v_rol='profesor' OR v_activas<3) THEN '["enviar"]'::jsonb ELSE '[]'::jsonb END);
END;
$$;

CREATE FUNCTION banco.web_enviar_participacion(p_actor bigint,p_proyecto bigint,p_datos jsonb,p_version text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;v_contexto jsonb;v_clave text;v_id bigint;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR UPDATE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR UPDATE;
  ELSE RAISE EXCEPTION 'Solo alumnos y profesores pueden postularse' USING ERRCODE='42501'; END IF;
  PERFORM id FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  v_contexto:=banco.web_contexto_postulacion(p_actor,p_proyecto);
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM v_contexto->>'version' THEN
    RAISE EXCEPTION 'El contexto cambió; recarga antes de enviar' USING ERRCODE='40001'; END IF;
  IF NOT (v_contexto->'acciones' ? 'enviar') THEN RAISE EXCEPTION 'Completa el perfil y revisa solicitudes activas antes de enviar' USING ERRCODE='55000'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_rol='alumno' OR v_clave NOT IN ('experiencia_aplicable','justificacion') OR jsonb_typeof(p_datos->v_clave)<>'string' OR length(p_datos->>v_clave)>10000 THEN
      RAISE EXCEPTION 'Campos de solicitud no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF v_rol='alumno' THEN v_id:=banco.presentar_candidatura(p_proyecto,p_actor);
  ELSE v_id:=banco.solicitar_direccion(p_proyecto,p_actor,p_datos->>'experiencia_aplicable',p_datos->>'justificacion'); END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION banco.web_operar_participacion(p_actor bigint,p_tipo text,p_id bigint,p_accion text,p_datos jsonb,p_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_s jsonb;v_rol text;v_clave text;
BEGIN
  v_s:=banco.web_abrir_participacion(p_actor,p_tipo,p_id,true);
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF p_accion IS NULL OR NOT ((p_accion='cancelar' AND v_rol IN ('alumno','profesor') AND p_actor=(v_s->>'titular_id')::bigint)
    OR (p_accion IN ('evaluar','preseleccionar') AND v_rol='empresa' AND p_tipo='candidatura')
    OR (p_accion IN ('aprobar','rechazar') AND v_rol='administrador')) THEN RAISE EXCEPTION 'Operación no permitida' USING ERRCODE='42501'; END IF;
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM banco.web_version_participacion(p_tipo,p_id) THEN
    RAISE EXCEPTION 'La solicitud o su contexto cambió; recarga antes de decidir' USING ERRCODE='40001'; END IF;
  IF NOT (banco.web_acciones_participacion(p_actor,p_tipo,p_id) ? p_accion) THEN RAISE EXCEPTION 'La operación ya no corresponde al estado actual' USING ERRCODE='55000'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF (p_accion IN ('cancelar','preseleccionar')) OR (p_accion IN ('aprobar','rechazar') AND v_clave<>'motivo')
      OR (p_accion='evaluar' AND v_clave NOT IN ('puntuaciones','comentarios','recomendada')) THEN RAISE EXCEPTION 'Campos no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_accion IN ('aprobar','rechazar') AND (jsonb_typeof(p_datos->'motivo') IS DISTINCT FROM 'string' OR length(p_datos->>'motivo')>1000) THEN
    RAISE EXCEPTION 'Motivo inválido' USING ERRCODE='23514'; END IF;
  IF p_accion='cancelar' THEN
    IF p_tipo='candidatura' THEN PERFORM banco.cancelar_candidatura(p_id,p_actor); ELSE PERFORM banco.cancelar_solicitud_direccion(p_id,p_actor); END IF;
  ELSIF p_accion='evaluar' THEN
    IF jsonb_typeof(p_datos->'puntuaciones') IS DISTINCT FROM 'object' OR jsonb_typeof(p_datos->'recomendada') IS DISTINCT FROM 'boolean' OR jsonb_typeof(p_datos->'comentarios') IS DISTINCT FROM 'string'
      OR length(p_datos->>'comentarios')>10000 THEN RAISE EXCEPTION 'Evaluación inválida' USING ERRCODE='23514'; END IF;
    FOR v_clave IN SELECT jsonb_object_keys(coalesce(p_datos->'puntuaciones','{}'::jsonb)) LOOP
      IF length(p_datos->'puntuaciones'->v_clave->>'comentario')>10000 THEN RAISE EXCEPTION 'Comentario demasiado largo' USING ERRCODE='23514'; END IF;
    END LOOP;
    PERFORM banco.evaluar_candidatura(p_id,p_actor,p_datos->'puntuaciones',p_datos->>'comentarios',(p_datos->>'recomendada')::boolean);
  ELSIF p_accion='preseleccionar' THEN PERFORM banco.preseleccionar_candidatura(p_id,p_actor);
  ELSIF p_tipo='candidatura' THEN PERFORM banco.resolver_candidatura(p_id,p_actor,CASE p_accion WHEN 'aprobar' THEN 'aprobada' ELSE 'rechazada' END,p_datos->>'motivo');
  ELSE PERFORM banco.resolver_direccion(p_id,p_actor,CASE p_accion WHEN 'aprobar' THEN 'aprobada' ELSE 'rechazada' END,p_datos->>'motivo'); END IF;
END;
$$;

CREATE FUNCTION banco.web_ambito_proyecto(p_actor bigint,p_proyecto banco.proyecto)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN RETURN true;
  ELSIF v_rol='empresa' THEN RETURN EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE usuario_id=p_actor AND empresa_id=p_proyecto.empresa_id AND vigente);
  ELSIF v_rol='alumno' THEN RETURN EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto.id)
      OR (p_proyecto.estado='pausado' AND banco.web_admite_participacion(p_proyecto,'candidatura'));
  ELSIF v_rol='profesor' THEN RETURN EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto.id)
      OR (p_proyecto.estado='pausado' AND banco.web_admite_participacion(p_proyecto,'direccion'));
  END IF;
  RETURN false;
END;
$$;

CREATE FUNCTION banco.web_proyectos_participacion(p_actor bigint,p_estado text,p_buscar text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN RAISE EXCEPTION 'Acceso no permitido' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN PERFORM banco.web_empresa_del_actor(p_actor);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0 OR length(p_buscar)>150
    OR (nullif(p_estado,'') IS NOT NULL AND p_estado NOT IN ('borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado')) THEN RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.id,p.titulo,p.estado,e.razon_social,p.cupo_maximo_alumnos,
      (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p.id AND estado='vigente') AS alumnos_vigentes,
      (SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=p.id AND estado='vigente') AS directores_vigentes,
      (v_rol IN ('alumno','profesor') AND p.estado='pausado' AND banco.web_admite_participacion(p,CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END)) AS vacante
      FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_ambito_proyecto(p_actor,p)
      AND (nullif(p_estado,'') IS NULL OR p.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM visibles ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM visibles)));
END;
$$;

CREATE FUNCTION banco.web_acciones_ciclo(p_actor bigint,p_proyecto banco.proyecto)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_acciones jsonb:='[]';v_alumnos integer;v_directores integer;
BEGIN
  IF EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='alumno' AND estado_cuenta='activa') THEN
    IF banco.web_admite_participacion(p_proyecto,'candidatura') AND EXISTS(SELECT 1 FROM banco.alumno WHERE usuario_id=p_actor)
      AND (SELECT count(*) FROM banco.candidatura WHERE alumno_id=p_actor AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada'))<3
      AND NOT EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto.id AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')) THEN RETURN '["participar"]'::jsonb; END IF;
    RETURN v_acciones;
  ELSIF EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='profesor' AND estado_cuenta='activa') THEN
    IF banco.web_admite_participacion(p_proyecto,'direccion') AND EXISTS(SELECT 1 FROM banco.profesor WHERE usuario_id=p_actor)
      AND NOT EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto.id AND estado='pendiente') THEN RETURN '["participar"]'::jsonb; END IF;
    RETURN v_acciones;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='administrador' AND estado_cuenta='activa') THEN RETURN v_acciones; END IF;
  SELECT count(*) INTO v_alumnos FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  SELECT count(*) INTO v_directores FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  IF p_proyecto.estado IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado') THEN v_acciones:=v_acciones||'"cancelar"'::jsonb; END IF;
  IF p_proyecto.estado='en_curso' THEN v_acciones:=v_acciones||'"finalizar"'::jsonb; END IF;
  IF p_proyecto.estado IN ('publicado','pausado') AND v_alumnos>0 AND v_directores=1 THEN
    v_acciones:=v_acciones||to_jsonb(CASE p_proyecto.estado WHEN 'publicado' THEN 'iniciar'::text ELSE 'reanudar'::text END); END IF;
  IF p_proyecto.estado IN ('publicado','en_curso','pausado') THEN
    IF v_alumnos>0 THEN v_acciones:=v_acciones||'"retirar_alumno"'::jsonb; END IF;
    IF v_directores>0 THEN v_acciones:=v_acciones||'"retirar_director"'::jsonb; END IF;
  END IF;
  RETURN v_acciones;
END;
$$;

CREATE FUNCTION banco.web_detalle_proyecto_participacion(p_actor bigint,p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_p banco.proyecto%ROWTYPE;v_rol text;v_docente boolean;v_alumnos jsonb;v_directores jsonb;
BEGIN
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR NOT banco.web_ambito_proyecto(p_actor,v_p) THEN
    RAISE EXCEPTION 'Proyecto fuera de tu ámbito' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN PERFORM banco.exigir_representante(p_actor,v_p.empresa_id);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  v_docente:=v_rol='profesor' AND EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND profesor_id=p_actor AND estado='vigente');
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'solicitud_id',a.candidatura_id,'estado',a.estado,'inicio',a.inicio,'fin',a.fin,'nombre',u.nombre,
      'perfil',banco.consultar_perfil(p_actor,a.alumno_id)) ORDER BY a.id DESC),'[]'::jsonb) INTO v_alumnos
    FROM banco.asignacion_alumno a JOIN banco.usuario u ON u.id=a.alumno_id WHERE a.proyecto_id=p_proyecto
      AND (v_rol IN ('administrador','empresa') OR (v_docente AND a.estado='vigente') OR (v_rol='alumno' AND a.alumno_id=p_actor));
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'solicitud_id',a.solicitud_direccion_id,'estado',a.estado,'inicio',a.inicio,'fin',a.fin,'nombre',u.nombre,
      'perfil',CASE WHEN v_rol='administrador' OR a.profesor_id=p_actor THEN banco.consultar_perfil(p_actor,a.profesor_id) ELSE NULL END) ORDER BY a.id DESC),'[]'::jsonb) INTO v_directores
    FROM banco.asignacion_direccion a JOIN banco.usuario u ON u.id=a.profesor_id WHERE a.proyecto_id=p_proyecto
      AND (v_rol IN ('administrador','empresa') OR a.profesor_id=p_actor);
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_p)||jsonb_build_object('id',v_p.id,'estado',v_p.estado,
      'habilidades',coalesce((SELECT instantanea_contenido->'habilidades' FROM banco.revision_proyecto WHERE id=v_p.revision_publicada_id),'[]'::jsonb)),
    'empresa',(SELECT jsonb_build_object('razon_social',razon_social,'sector',sector,'contacto_nombre',contacto_nombre,'contacto_correo',contacto_correo,'contacto_telefono',contacto_telefono) FROM banco.empresa WHERE id=v_p.empresa_id),
    'alumnos',v_alumnos,'directores',v_directores,'version',banco.web_version_ciclo(p_proyecto),'acciones',banco.web_acciones_ciclo(p_actor,v_p),
    'disponibilidad',banco.web_catalogo_disponibilidad(v_p),'vacante',v_rol IN ('alumno','profesor') AND v_p.estado='pausado'
      AND banco.web_admite_participacion(v_p,CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END),
    'historial',CASE WHEN v_rol IN ('administrador','empresa') OR
      (v_rol='alumno' AND EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto)) OR
      (v_rol='profesor' AND EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto)) THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',e.fecha,'operacion',e.operacion,'transicion',e.transicion,'actor_nombre',u.nombre,
      'motivo',CASE WHEN e.operacion IN ('finalizar_proyecto','cancelar_proyecto') THEN e.resultado::jsonb->>'motivo' ELSE NULL END) ORDER BY e.id DESC),'[]'::jsonb)
      FROM banco.evento_auditoria e LEFT JOIN banco.usuario u ON u.id=e.actor_usuario_id WHERE e.entidad_afectada='proyecto' AND e.registro_afectado=p_proyecto::text
      AND e.operacion IN ('iniciar_proyecto','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto')) ELSE '[]'::jsonb END);
END;
$$;

CREATE FUNCTION banco.web_operar_proyecto_participacion(p_actor bigint,p_proyecto bigint,p_accion text,p_datos jsonb,p_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_p banco.proyecto%ROWTYPE;v_clave text;v_id bigint;v_fila record;
BEGIN
  -- Los cierres bloquean primero fuentes y perfiles; no retener Proyecto antes de ellos.
  IF NOT EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='administrador') THEN
    RAISE EXCEPTION 'El ciclo del proyecto requiere administración' USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_accion IS NULL OR p_accion NOT IN ('iniciar','reanudar','finalizar','cancelar','retirar_alumno','retirar_director') THEN RAISE EXCEPTION 'Acción de proyecto inválida' USING ERRCODE='22023'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF p_accion IN ('iniciar','reanudar') OR (p_accion IN ('finalizar','cancelar') AND v_clave<>'motivo')
      OR (p_accion IN ('retirar_alumno','retirar_director') AND v_clave NOT IN ('motivo','asignacion_id')) THEN RAISE EXCEPTION 'Campos no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_accion NOT IN ('iniciar','reanudar') AND (jsonb_typeof(p_datos->'motivo') IS DISTINCT FROM 'string' OR length(p_datos->>'motivo')>1000) THEN RAISE EXCEPTION 'Motivo inválido' USING ERRCODE='23514'; END IF;
  IF p_accion IN ('finalizar','cancelar') THEN
    PERFORM id FROM banco.candidatura WHERE proyecto_id=p_proyecto AND (estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      OR id IN (SELECT candidatura_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
    PERFORM id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND (estado='pendiente'
      OR id IN (SELECT solicitud_direccion_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
    FOR v_fila IN SELECT tipo,id FROM (
      SELECT 'alumno'::text tipo,alumno_id id FROM banco.candidatura WHERE proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT 'alumno',alumno_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'
      UNION SELECT 'profesor',profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'
      UNION SELECT 'profesor',profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente') q ORDER BY tipo,id LOOP
      IF v_fila.tipo='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.id FOR UPDATE;
      ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.id FOR UPDATE; END IF;
    END LOOP;
  ELSIF p_accion IN ('retirar_alumno','retirar_director') THEN
    IF jsonb_typeof(p_datos->'asignacion_id') IS DISTINCT FROM 'number' OR p_datos->>'asignacion_id' !~ '^-?[0-9]+$' THEN RAISE EXCEPTION 'Asignación inválida' USING ERRCODE='23514'; END IF;
    v_id:=(p_datos->>'asignacion_id')::bigint;
    IF p_accion='retirar_alumno' THEN
      SELECT alumno_id AS titular INTO v_fila FROM banco.asignacion_alumno WHERE id=v_id AND proyecto_id=p_proyecto;
      IF NOT FOUND THEN RAISE EXCEPTION 'Asignación ajena al proyecto' USING ERRCODE='23503'; END IF;
      PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.titular FOR UPDATE;
    ELSE
      SELECT profesor_id AS titular INTO v_fila FROM banco.asignacion_direccion WHERE id=v_id AND proyecto_id=p_proyecto;
      IF NOT FOUND THEN RAISE EXCEPTION 'Asignación ajena al proyecto' USING ERRCODE='23503'; END IF;
      PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.titular FOR UPDATE;
    END IF;
  END IF;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM banco.web_version_ciclo(p_proyecto) THEN RAISE EXCEPTION 'El proyecto o sus participantes cambiaron; recarga' USING ERRCODE='40001'; END IF;
  IF NOT(banco.web_acciones_ciclo(p_actor,v_p) ? p_accion) THEN RAISE EXCEPTION 'Acción no disponible para este estado' USING ERRCODE='55000'; END IF;
  CASE p_accion
    WHEN 'iniciar' THEN PERFORM banco.iniciar_proyecto(p_proyecto,p_actor);
    WHEN 'reanudar' THEN PERFORM banco.reanudar_proyecto(p_proyecto,p_actor);
    WHEN 'finalizar' THEN PERFORM banco.finalizar_proyecto(p_proyecto,p_actor,p_datos->>'motivo');
    WHEN 'cancelar' THEN PERFORM banco.cancelar_proyecto(p_proyecto,p_actor,p_datos->>'motivo');
    WHEN 'retirar_alumno' THEN PERFORM banco.retirar_alumno(v_id,p_actor,p_datos->>'motivo');
    WHEN 'retirar_director' THEN PERFORM banco.retirar_director(v_id,p_actor,p_datos->>'motivo');
  END CASE;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_bandeja_participacion(bigint,text,text,text,integer,integer),
  banco.web_detalle_participacion(bigint,text,bigint),banco.web_contexto_postulacion(bigint,bigint),
  banco.web_enviar_participacion(bigint,bigint,jsonb,text),banco.web_operar_participacion(bigint,text,bigint,text,jsonb,text),
  banco.web_proyectos_participacion(bigint,text,text,integer,integer),banco.web_detalle_proyecto_participacion(bigint,bigint),
  banco.web_operar_proyecto_participacion(bigint,bigint,text,jsonb,text) TO banco_web;

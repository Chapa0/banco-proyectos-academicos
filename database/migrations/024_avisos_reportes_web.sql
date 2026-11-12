-- WEB-07: bandeja individual y reportes administrativos RF-41/RF-42.
-- Ampliación aditiva: no cambia datos, tablas ni gateways anteriores.
-- Recuperación: respaldo previo y corrección hacia delante; conservar 001-023.

CREATE FUNCTION banco.web_exigir_avisos(p_actor bigint)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN
    RAISE EXCEPTION 'Acceso a avisos no permitido' USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_rol(p_actor,v_rol,true);
END;
$$;

CREATE FUNCTION banco.web_recurso_aviso(p_actor bigint,p_evento bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_e banco.evento_auditoria%ROWTYPE;v_id bigint;v_c bigint;v_d bigint;v_p bigint;v_rol text;v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  SELECT * INTO v_e FROM banco.evento_auditoria WHERE id=p_evento;
  IF NOT FOUND OR v_e.registro_afectado !~ '^-?[0-9]+$' THEN RETURN NULL; END IF;
  BEGIN v_id:=v_e.registro_afectado::bigint; EXCEPTION WHEN numeric_value_out_of_range THEN RETURN NULL; END;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  CASE v_e.entidad_afectada
    WHEN 'proyecto' THEN v_p:=v_id;
    WHEN 'candidatura' THEN v_c:=v_id;
    WHEN 'solicitud_direccion' THEN v_d:=v_id;
    WHEN 'evaluacion_candidato' THEN SELECT candidatura_id INTO v_c FROM banco.evaluacion_candidato WHERE id=v_id;
    WHEN 'asignacion_alumno' THEN SELECT candidatura_id INTO v_c FROM banco.asignacion_alumno WHERE id=v_id;
    WHEN 'asignacion_direccion' THEN SELECT solicitud_direccion_id INTO v_d FROM banco.asignacion_direccion WHERE id=v_id;
    ELSE RETURN NULL;
  END CASE;
  IF v_c IS NOT NULL THEN
    SELECT proyecto_id INTO v_p FROM banco.candidatura WHERE id=v_c;
    IF EXISTS(SELECT 1 FROM banco.candidatura c JOIN banco.proyecto p ON p.id=c.proyecto_id
      WHERE c.id=v_c AND (v_rol='administrador' OR (v_rol='alumno' AND c.alumno_id=p_actor)
        OR (v_rol='empresa' AND EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE empresa_id=p.empresa_id AND usuario_id=p_actor AND vigente)))) THEN
      RETURN jsonb_build_object('tipo','candidatura','id',v_c); END IF;
  ELSIF v_d IS NOT NULL THEN
    SELECT proyecto_id INTO v_p FROM banco.solicitud_direccion WHERE id=v_d;
    IF EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE id=v_d AND (v_rol='administrador' OR (v_rol='profesor' AND profesor_id=p_actor))) THEN
      RETURN jsonb_build_object('tipo','direccion','id',v_d); END IF;
  END IF;
  IF v_p IS NOT NULL THEN
    SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_p;
    IF FOUND AND banco.web_ambito_proyecto(p_actor,v_proyecto) THEN
      RETURN jsonb_build_object('tipo','proyecto','id',v_p,'contexto',
        CASE WHEN v_e.operacion IN ('enviar_proyecto','resolver_publicacion') THEN 'publicacion' ELSE 'seguimiento' END);
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE FUNCTION banco.web_bandeja_avisos(p_actor bigint,p_estado text,p_buscar text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.web_exigir_avisos(p_actor);
  IF p_estado IS NULL OR p_estado NOT IN ('todos','no_leidos','leidos') OR length(p_buscar)>150
    OR p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0 THEN
    RAISE EXCEPTION 'Filtros de avisos inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH propios AS MATERIALIZED (
    SELECT id,mensaje,fecha,fecha_lectura FROM banco.notificacion WHERE destinatario_usuario_id=p_actor
  ), filtrados AS MATERIALIZED (
    SELECT * FROM propios WHERE (p_estado='todos' OR (p_estado='no_leidos' AND fecha_lectura IS NULL) OR (p_estado='leidos' AND fecha_lectura IS NOT NULL))
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(mensaje),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtrados ORDER BY fecha DESC,id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY fecha DESC,id DESC) FROM pagina),'[]'::jsonb),
    'total',(SELECT count(*) FROM filtrados),'no_leidos',(SELECT count(*) FROM propios WHERE fecha_lectura IS NULL)));
END;
$$;

CREATE FUNCTION banco.web_detalle_aviso(p_actor bigint,p_aviso bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_n banco.notificacion%ROWTYPE;
BEGIN
  -- Coincide con marcar_notificacion_leida: aviso antes de usuario.
  SELECT * INTO v_n FROM banco.notificacion WHERE id=p_aviso FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aviso no disponible' USING ERRCODE='23503'; END IF;
  IF v_n.destinatario_usuario_id IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'Aviso ajeno' USING ERRCODE='42501'; END IF;
  PERFORM banco.web_exigir_avisos(p_actor);
  RETURN jsonb_build_object('aviso',jsonb_build_object('id',v_n.id,'mensaje',v_n.mensaje,'fecha',v_n.fecha,'fecha_lectura',v_n.fecha_lectura),
    'recurso',banco.web_recurso_aviso(p_actor,v_n.evento_id));
END;
$$;

CREATE FUNCTION banco.web_leer_aviso(p_actor bigint,p_aviso bigint)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN
    RAISE EXCEPTION 'Acceso a avisos no permitido' USING ERRCODE='42501'; END IF;
  -- La operación interna conserva primera fecha, propiedad y cuenta activa.
  RETURN banco.marcar_notificacion_leida(p_aviso,p_actor);
END;
$$;

CREATE FUNCTION banco.web_opciones_reporte(p_tipo text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT jsonb_build_object(
    'empresas',CASE WHEN p_tipo='carga_profesores' THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'razon_social',razon_social) ORDER BY razon_social,id) FROM banco.empresa),'[]'::jsonb) END,
    'proyectos',CASE WHEN p_tipo IN ('candidaturas','direcciones','asignaciones') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'titulo',titulo) ORDER BY titulo,id) FROM banco.proyecto),'[]'::jsonb) ELSE '[]'::jsonb END,
    'profesores',CASE WHEN p_tipo IN ('direcciones','carga_profesores') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.usuario_id,'nombre',u.nombre) ORDER BY u.nombre,p.usuario_id) FROM banco.profesor p JOIN banco.usuario u ON u.id=p.usuario_id),'[]'::jsonb) ELSE '[]'::jsonb END);
$$;

CREATE FUNCTION banco.web_reporte(p_actor bigint,p_tipo text,p_filtros jsonb,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_clave text;v_permitidos text[];v_buscar text;v_estado text;v_empresa bigint;v_proyecto bigint;v_profesor bigint;
BEGIN
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_tipo IS NULL OR p_tipo NOT IN ('proyectos','candidaturas','direcciones','carga_profesores','asignaciones')
    OR p_filtros IS NULL OR jsonb_typeof(p_filtros)<>'object' OR p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100
    OR p_desplazamiento IS NULL OR p_desplazamiento<0 THEN RAISE EXCEPTION 'Reporte o paginación inválidos' USING ERRCODE='23514'; END IF;
  v_permitidos:=CASE p_tipo
    WHEN 'proyectos' THEN ARRAY['buscar','estado','empresa_id']
    WHEN 'candidaturas' THEN ARRAY['buscar','estado','empresa_id','proyecto_id']
    WHEN 'direcciones' THEN ARRAY['buscar','estado','empresa_id','proyecto_id','profesor_id']
    WHEN 'carga_profesores' THEN ARRAY['buscar','profesor_id']
    ELSE ARRAY['buscar','estado','empresa_id','proyecto_id'] END;
  FOR v_clave IN SELECT jsonb_object_keys(p_filtros) LOOP
    IF NOT(v_clave=ANY(v_permitidos)) THEN RAISE EXCEPTION 'Filtro no aplicable al reporte' USING ERRCODE='23514'; END IF;
    IF p_filtros->v_clave='null'::jsonb THEN CONTINUE; END IF;
    IF v_clave IN ('buscar','estado') THEN
      IF jsonb_typeof(p_filtros->v_clave)<>'string' OR length(p_filtros->>v_clave)>150 THEN RAISE EXCEPTION 'Filtro textual inválido' USING ERRCODE='23514'; END IF;
    ELSIF jsonb_typeof(p_filtros->v_clave)<>'number' OR p_filtros->>v_clave !~ '^-?[0-9]+$' OR p_filtros->>v_clave='0' THEN
      RAISE EXCEPTION 'Identificador de filtro inválido' USING ERRCODE='23514';
    END IF;
  END LOOP;
  v_buscar:=nullif(btrim(p_filtros->>'buscar'),'');v_estado:=nullif(p_filtros->>'estado','');
  BEGIN
    v_empresa:=(p_filtros->>'empresa_id')::bigint;v_proyecto:=(p_filtros->>'proyecto_id')::bigint;v_profesor:=(p_filtros->>'profesor_id')::bigint;
  EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN RAISE EXCEPTION 'Identificador de filtro inválido' USING ERRCODE='23514'; END;
  IF v_estado IS NOT NULL AND NOT (v_estado=ANY(CASE p_tipo
    WHEN 'proyectos' THEN ARRAY['borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado']
    WHEN 'candidaturas' THEN ARRAY['pendiente_evaluacion','evaluada','preseleccionada','aprobada','rechazada','cancelada']
    WHEN 'direcciones' THEN ARRAY['pendiente','aprobada','rechazada','cancelada']
    ELSE ARRAY['vigente','finalizada','revocada'] END)) THEN RAISE EXCEPTION 'Estado no aplicable al reporte' USING ERRCODE='23514'; END IF;

  IF p_tipo='proyectos' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT p.id,p.titulo,p.estado,p.empresa_id,e.razon_social,p.cupo_maximo_alumnos,
        (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p.id AND estado='vigente') AS alumnos_vigentes,
        (SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=p.id AND estado='vigente') AS directores_vigentes
      FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_estado IS NULL OR p.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'alumnos_vigentes',coalesce(sum(alumnos_vigentes),0),'directores_vigentes',coalesce(sum(directores_vigentes),0)) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='candidaturas' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT c.id,c.proyecto_id,p.titulo,e.razon_social,u.nombre AS solicitante_nombre,c.estado,c.fecha_solicitud
      FROM banco.candidatura c JOIN banco.proyecto p ON p.id=c.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=c.alumno_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_estado IS NULL OR c.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'activas',count(*) FILTER(WHERE estado IN ('pendiente_evaluacion','evaluada','preseleccionada')),
        'aprobadas',count(*) FILTER(WHERE estado='aprobada'),'rechazadas',count(*) FILTER(WHERE estado='rechazada'),'canceladas',count(*) FILTER(WHERE estado='cancelada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='direcciones' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT s.id,s.proyecto_id,p.titulo,e.razon_social,u.nombre AS solicitante_nombre,s.estado,s.fecha_solicitud
      FROM banco.solicitud_direccion s JOIN banco.proyecto p ON p.id=s.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=s.profesor_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_profesor IS NULL OR s.profesor_id=v_profesor)
        AND (v_estado IS NULL OR s.estado=v_estado) AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'pendientes',count(*) FILTER(WHERE estado='pendiente'),'aprobadas',count(*) FILTER(WHERE estado='aprobada'),
        'rechazadas',count(*) FILTER(WHERE estado='rechazada'),'canceladas',count(*) FILTER(WHERE estado='cancelada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='carga_profesores' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT pr.usuario_id AS profesor_id,u.nombre,(SELECT count(*) FROM banco.asignacion_direccion WHERE profesor_id=pr.usuario_id AND estado='vigente') AS proyectos_vigentes,3 AS limite_proyectos
      FROM banco.profesor pr JOIN banco.usuario u ON u.id=pr.usuario_id
      WHERE (v_profesor IS NULL OR pr.usuario_id=v_profesor) AND (v_buscar IS NULL OR strpos(lower(u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY profesor_id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY profesor_id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'proyectos_vigentes',coalesce(sum(proyectos_vigentes),0),'profesores_con_carga',count(*) FILTER(WHERE proyectos_vigentes>0)) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSE
    RETURN (WITH origen AS MATERIALIZED (
      SELECT a.id,'alumno'::text AS tipo,a.candidatura_id AS solicitud_id,a.alumno_id AS titular_id,a.proyecto_id,a.estado,a.inicio,a.fin FROM banco.asignacion_alumno a
      UNION ALL SELECT a.id,'direccion'::text,a.solicitud_direccion_id,a.profesor_id,a.proyecto_id,a.estado,a.inicio,a.fin FROM banco.asignacion_direccion a
    ), filtrados AS MATERIALIZED (
      SELECT a.id,a.tipo,a.solicitud_id,a.proyecto_id,p.titulo,e.razon_social,u.nombre AS participante_nombre,a.estado,a.inicio,a.fin
      FROM origen a JOIN banco.proyecto p ON p.id=a.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=a.titular_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_estado IS NULL OR a.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC,tipo LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC,tipo) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'alumnos_vigentes',count(*) FILTER(WHERE tipo='alumno' AND estado='vigente'),
        'directores_vigentes',count(*) FILTER(WHERE tipo='direccion' AND estado='vigente'),'finalizadas',count(*) FILTER(WHERE estado='finalizada'),'revocadas',count(*) FILTER(WHERE estado='revocada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  END IF;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_bandeja_avisos(bigint,text,text,integer,integer),banco.web_detalle_aviso(bigint,bigint),
  banco.web_leer_aviso(bigint,bigint),banco.web_reporte(bigint,text,jsonb,integer,integer) TO banco_web;
COMMENT ON FUNCTION banco.web_leer_aviso(bigint,bigint) IS
  'WEB-07: primera lectura propia idempotente mediante018; sin borrar el aviso ni alterar su evento.';
COMMENT ON FUNCTION banco.web_reporte(bigint,text,jsonb,integer,integer) IS
  'WEB-07/RF-41: cinco consultas administrativas con filtros estrictos y totales del conjunto filtrado antes de paginar. Sin exportación ni datos de acceso, evidencias o rúbricas.';

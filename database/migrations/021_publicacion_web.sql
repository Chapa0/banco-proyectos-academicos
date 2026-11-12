-- WEB-04: datos propios de empresa y publicación inicial mediante nueve gateways.
-- La sesión Laravel autentica al actor; SQL vuelve a validar rol/pertenencia.
-- Sin columnas nuevas ni DML/SELECT general. 001-020 permanecen inmutables.
-- Evolución hacia delante; para retirar capacidades se hará otra migración.

CREATE FUNCTION banco.web_version_empresa(p_empresa bigint)
RETURNS text LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('empresa',to_jsonb(e),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='empresa' AND registro_afectado=e.id::text))::text,'UTF8')),'hex')
  FROM banco.empresa e WHERE e.id=p_empresa;
$$;
CREATE FUNCTION banco.web_version_proyecto(p_proyecto bigint)
RETURNS text LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('proyecto',to_jsonb(p),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY habilidad_id)
      FROM banco.proyecto_habilidad h WHERE h.proyecto_id=p.id),'[]'::jsonb),
    'ultima_revision',(SELECT coalesce(max(id),0) FROM banco.revision_proyecto WHERE proyecto_id=p.id),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='proyecto' AND registro_afectado=p.id::text))::text,'UTF8')),'hex')
  FROM banco.proyecto p WHERE p.id=p_proyecto;
$$;
CREATE FUNCTION banco.web_empresa_del_actor(p_actor bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT empresa_id INTO v_empresa FROM banco.representacion_empresa
    WHERE usuario_id=p_actor AND vigente;
  IF NOT FOUND THEN RAISE EXCEPTION 'No hay una representación empresarial vigente'
    USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_representante(p_actor,v_empresa);
  RETURN v_empresa;
END;
$$;
CREATE FUNCTION banco.web_datos_empresa(p_empresa bigint)
RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT jsonb_build_object('id',e.id,'razon_social',e.razon_social,'sector',e.sector,
    'identificacion',e.identificacion,'contacto_nombre',e.contacto_nombre,
    'contacto_correo',e.contacto_correo,'contacto_telefono',e.contacto_telefono,
    'version',banco.web_version_empresa(e.id)) FROM banco.empresa e WHERE e.id=p_empresa;
$$;
CREATE FUNCTION banco.web_obtener_empresa(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  RETURN banco.web_datos_empresa(banco.web_empresa_del_actor(p_actor));
END;
$$;
CREATE FUNCTION banco.web_editar_empresa(p_actor bigint,p_datos jsonb,p_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_empresa bigint;v_fila banco.empresa%ROWTYPE;v_clave text;
BEGIN
  v_empresa:=banco.web_empresa_del_actor(p_actor);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_empresa(v_empresa) THEN
    RAISE EXCEPTION 'La empresa cambió; recarga sus datos antes de guardar' USING ERRCODE='40001'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'Datos de empresa inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_clave NOT IN ('razon_social','sector','identificacion','contacto_nombre','contacto_correo','contacto_telefono')
      OR jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'Datos de empresa inválidos' USING ERRCODE='23514'; END IF;
    IF length(p_datos->>v_clave)>1000 THEN
      RAISE EXCEPTION 'Un dato de empresa excede el tamaño admitido' USING ERRCODE='23514'; END IF;
  END LOOP;
  v_fila:=jsonb_populate_record(NULL::banco.empresa,p_datos);
  IF v_fila.razon_social IS NULL OR v_fila.razon_social !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'La razón social es obligatoria' USING ERRCODE='23514'; END IF;
  UPDATE banco.empresa SET razon_social=v_fila.razon_social,sector=v_fila.sector,
    identificacion=v_fila.identificacion,contacto_nombre=v_fila.contacto_nombre,
    contacto_correo=v_fila.contacto_correo,contacto_telefono=v_fila.contacto_telefono
    WHERE id=v_empresa;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario','editar_empresa','empresa',v_empresa::text,
    jsonb_build_object('version_anterior',p_version,'campos',ARRAY['razon_social','sector','identificacion','contacto_nombre','contacto_correo','contacto_telefono'])::text);
END;
$$;

CREATE FUNCTION banco.web_abrir_proyecto(p_actor bigint,p_proyecto bigint)
RETURNS banco.proyecto LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_rol text;v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN
    PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN
    v_empresa:=banco.web_empresa_del_actor(p_actor);
    IF v_empresa IS DISTINCT FROM v_proyecto.empresa_id THEN
      RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar proyectos en este módulo' USING ERRCODE='42501';
  END IF;
  RETURN v_proyecto;
END;
$$;
CREATE FUNCTION banco.web_listar_proyectos(p_actor bigint,p_buscar text,p_estado text,
  p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;v_empresa bigint;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN v_empresa:=banco.web_empresa_del_actor(p_actor);
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar proyectos en este módulo' USING ERRCODE='42501'; END IF;
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR (nullif(p_estado,'') IS NOT NULL AND p_estado NOT IN
      ('borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado'))
    OR length(p_buscar)>150 THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH filtrados AS MATERIALIZED (
    SELECT p.id,p.titulo,p.estado,p.empresa_id,e.razon_social,p.cupo_maximo_alumnos,
      r.id AS ultima_revision_id,r.numero AS numero_revision,r.fecha_envio
    FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id
    LEFT JOIN LATERAL (SELECT id,numero,fecha_envio FROM banco.revision_proyecto
      WHERE proyecto_id=p.id ORDER BY numero DESC LIMIT 1) r ON true
    WHERE (v_rol='administrador' OR p.empresa_id=v_empresa)
      AND (nullif(p_estado,'') IS NULL OR p.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('total',(SELECT count(*) FROM filtrados),
    'datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb)));
END;
$$;
CREATE FUNCTION banco.web_obtener_proyecto(p_actor bigint,p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_proyecto)||jsonb_build_object(
    'autor_usuario_id',v_proyecto.autor_usuario_id,'estado',v_proyecto.estado,
    'revision_publicada_id',v_proyecto.revision_publicada_id,'version',banco.web_version_proyecto(p_proyecto)),
    'empresa',banco.web_datos_empresa(v_proyecto.empresa_id)-'version',
    'habilidades',coalesce((SELECT jsonb_agg(jsonb_build_object('habilidad_id',h.id,'nombre',h.nombre,
      'tipo',h.tipo,'descripcion',h.descripcion,'nivel_minimo',ph.nivel_minimo,'obligatoria',ph.obligatoria) ORDER BY h.id)
      FROM banco.proyecto_habilidad ph JOIN banco.habilidad h ON h.id=ph.habilidad_id WHERE ph.proyecto_id=p_proyecto),'[]'::jsonb),
    'revisiones',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'numero',r.numero,'fecha_envio',r.fecha_envio,
      'estado_revision',r.estado_revision,'instantanea_contenido',r.instantanea_contenido,
      'decision',CASE WHEN d.id IS NULL THEN NULL ELSE jsonb_build_object('id',d.id,'resultado',d.resultado,
        'justificacion',d.justificacion,'fecha',d.fecha,'administrador_nombre',u.nombre) END) ORDER BY r.numero DESC)
      FROM banco.revision_proyecto r LEFT JOIN banco.decision_administrativa d ON d.revision_proyecto_id=r.id
      LEFT JOIN banco.usuario u ON u.id=d.administrador_usuario_id WHERE r.proyecto_id=p_proyecto),'[]'::jsonb));
END;
$$;
CREATE FUNCTION banco.web_catalogo_habilidades(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN PERFORM banco.web_empresa_del_actor(p_actor);
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar este catálogo' USING ERRCODE='42501'; END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nombre',nombre,'tipo',tipo,'descripcion',descripcion)
    ORDER BY tipo,nombre,id),'[]'::jsonb) FROM banco.habilidad);
END;
$$;

CREATE FUNCTION banco.web_validar_datos_proyecto(p_datos jsonb)
RETURNS banco.proyecto LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_clave text;v_item jsonb;v_id bigint;v_vistos bigint[]:='{}';v_fila banco.proyecto%ROWTYPE;
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'Datos de proyecto inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_clave NOT IN ('titulo','descripcion','problematica','objetivos','justificacion','alcance','requisitos_academicos',
      'duracion_estimada','modalidad','fecha_inicio_estimada','fecha_fin_estimada','recursos','cupo_maximo_alumnos','habilidades') THEN
      RAISE EXCEPTION 'El proyecto contiene campos no permitidos' USING ERRCODE='23514'; END IF;
    IF v_clave NOT IN ('cupo_maximo_alumnos','habilidades') AND jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'Un campo de proyecto no contiene texto válido' USING ERRCODE='23514'; END IF;
    IF v_clave NOT IN ('cupo_maximo_alumnos','habilidades') AND length(p_datos->>v_clave)>20000 THEN
      RAISE EXCEPTION 'Un campo de proyecto excede el tamaño admitido' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_datos ? 'cupo_maximo_alumnos' AND jsonb_typeof(p_datos->'cupo_maximo_alumnos')<>'null'
    AND (jsonb_typeof(p_datos->'cupo_maximo_alumnos') NOT IN ('string','number')
      OR p_datos->>'cupo_maximo_alumnos' !~ '^[0-9]+$') THEN
    RAISE EXCEPTION 'El cupo requiere un entero positivo' USING ERRCODE='23514'; END IF;
  FOREACH v_clave IN ARRAY ARRAY['fecha_inicio_estimada','fecha_fin_estimada'] LOOP
    IF p_datos->>v_clave IS NOT NULL AND p_datos->>v_clave !~ '^\d{4}-\d{2}-\d{2}$' THEN
      RAISE EXCEPTION 'Las fechas requieren formato año-mes-día' USING ERRCODE='23514'; END IF;
  END LOOP;
  BEGIN v_fila:=jsonb_populate_record(NULL::banco.proyecto,p_datos-'habilidades');
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Cupo o fecha de proyecto inválidos' USING ERRCODE='23514'; END;
  IF v_fila.titulo IS NULL OR v_fila.titulo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El borrador requiere un título' USING ERRCODE='23514'; END IF;
  IF v_fila.cupo_maximo_alumnos IS NOT NULL AND v_fila.cupo_maximo_alumnos<1 THEN
    RAISE EXCEPTION 'El cupo requiere un entero positivo' USING ERRCODE='23514'; END IF;
  IF coalesce(jsonb_typeof(p_datos->'habilidades'),'array')<>'array' THEN
    RAISE EXCEPTION 'Las habilidades requieren una lista' USING ERRCODE='23514'; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) LOOP
    IF jsonb_typeof(v_item)<>'object' OR NOT v_item ? 'habilidad_id' THEN
      RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) k WHERE k NOT IN ('habilidad_id','nivel_minimo','obligatoria'))
      OR jsonb_typeof(v_item->'habilidad_id') NOT IN ('string','number')
      OR v_item->>'habilidad_id' !~ '^-?[0-9]+$'
      OR (v_item ? 'nivel_minimo' AND jsonb_typeof(v_item->'nivel_minimo') NOT IN ('string','null'))
      OR length(v_item->>'nivel_minimo')>250
      OR (v_item ? 'obligatoria' AND (jsonb_typeof(v_item->'obligatoria') NOT IN ('boolean','number','string')
        OR v_item->>'obligatoria' NOT IN ('true','false','0','1'))) THEN
      RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END IF;
    BEGIN v_id:=(v_item->>'habilidad_id')::bigint;
    EXCEPTION WHEN numeric_value_out_of_range THEN RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END;
    IF v_id=ANY(v_vistos) THEN RAISE EXCEPTION 'No se permite repetir una habilidad' USING ERRCODE='23514'; END IF;
    v_vistos:=array_append(v_vistos,v_id);
    PERFORM id FROM banco.habilidad WHERE id=v_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
  END LOOP;
  RETURN v_fila;
END;
$$;
CREATE FUNCTION banco.web_guardar_habilidades(p_proyecto bigint,p_datos jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  DELETE FROM banco.proyecto_habilidad WHERE proyecto_id=p_proyecto;
  INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria)
    SELECT p_proyecto,(v->>'habilidad_id')::bigint,v->>'nivel_minimo',
      coalesce((v->>'obligatoria')::boolean,false)
    FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) AS items(v);
END;
$$;
CREATE FUNCTION banco.web_crear_proyecto(p_actor bigint,p_datos jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_empresa bigint;v_id bigint;v_fila banco.proyecto%ROWTYPE;
BEGIN
  v_empresa:=banco.web_empresa_del_actor(p_actor);
  v_fila:=banco.web_validar_datos_proyecto(p_datos);
  INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,
    requisitos_academicos,duracion_estimada,modalidad,fecha_inicio_estimada,fecha_fin_estimada,recursos,cupo_maximo_alumnos)
  VALUES(v_empresa,p_actor,v_fila.titulo,v_fila.descripcion,v_fila.problematica,v_fila.objetivos,v_fila.justificacion,v_fila.alcance,
    v_fila.requisitos_academicos,v_fila.duracion_estimada,v_fila.modalidad,v_fila.fecha_inicio_estimada,v_fila.fecha_fin_estimada,
    v_fila.recursos,v_fila.cupo_maximo_alumnos) RETURNING id INTO v_id;
  PERFORM banco.web_guardar_habilidades(v_id,p_datos);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_actor,'usuario','crear_proyecto','proyecto',v_id::text,'sin proyecto -> borrador','Borrador empresarial creado');
  RETURN v_id;
END;
$$;
CREATE FUNCTION banco.web_editar_proyecto(p_actor bigint,p_proyecto bigint,p_datos jsonb,p_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_fila banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga sus datos antes de guardar' USING ERRCODE='40001'; END IF;
  IF v_proyecto.estado NOT IN ('borrador','en_correccion') OR v_proyecto.revision_publicada_id IS NOT NULL THEN
    RAISE EXCEPTION 'Solo se puede editar un borrador o proyecto devuelto' USING ERRCODE='55000'; END IF;
  v_fila:=banco.web_validar_datos_proyecto(p_datos);
  UPDATE banco.proyecto SET titulo=v_fila.titulo,descripcion=v_fila.descripcion,problematica=v_fila.problematica,
    objetivos=v_fila.objetivos,justificacion=v_fila.justificacion,alcance=v_fila.alcance,
    requisitos_academicos=v_fila.requisitos_academicos,duracion_estimada=v_fila.duracion_estimada,modalidad=v_fila.modalidad,
    fecha_inicio_estimada=v_fila.fecha_inicio_estimada,fecha_fin_estimada=v_fila.fecha_fin_estimada,
    recursos=v_fila.recursos,cupo_maximo_alumnos=v_fila.cupo_maximo_alumnos WHERE id=p_proyecto;
  PERFORM banco.web_guardar_habilidades(p_proyecto,p_datos);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario','editar_proyecto','proyecto',p_proyecto::text,
    jsonb_build_object('version_anterior',p_version)::text);
END;
$$;
CREATE FUNCTION banco.web_enviar_proyecto(p_actor bigint,p_proyecto bigint,p_version text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga sus datos antes de enviar' USING ERRCODE='40001'; END IF;
  RETURN banco.enviar_proyecto(p_proyecto,p_actor);
END;
$$;
CREATE FUNCTION banco.web_resolver_publicacion(p_actor bigint,p_proyecto bigint,p_revision bigint,
  p_resultado text,p_motivo text,p_cupo_validado integer,p_version text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_enviado integer;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga la revisión antes de resolver' USING ERRCODE='40001'; END IF;
  SELECT (instantanea_contenido->'proyecto'->>'cupo_maximo_alumnos')::integer INTO v_enviado
    FROM banco.revision_proyecto WHERE id=p_revision AND proyecto_id=p_proyecto;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revisión inexistente para este proyecto' USING ERRCODE='23503'; END IF;
  IF p_resultado='aprobada' AND (p_cupo_validado IS NULL OR p_cupo_validado IS DISTINCT FROM v_enviado
    OR p_cupo_validado IS DISTINCT FROM v_proyecto.cupo_maximo_alumnos) THEN
    RAISE EXCEPTION 'Confirma el cupo propuesto en esta revisión exacta para publicar' USING ERRCODE='23514'; END IF;
  IF p_resultado IS DISTINCT FROM 'aprobada' AND p_cupo_validado IS NOT NULL THEN
    RAISE EXCEPTION 'El cupo se valida únicamente al aprobar la publicación' USING ERRCODE='23514'; END IF;
  RETURN banco.resolver_publicacion(p_revision,p_actor,p_resultado,p_motivo);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_obtener_empresa(bigint),banco.web_editar_empresa(bigint,jsonb,text),
  banco.web_listar_proyectos(bigint,text,text,integer,integer),banco.web_obtener_proyecto(bigint,bigint),
  banco.web_catalogo_habilidades(bigint),banco.web_crear_proyecto(bigint,jsonb),
  banco.web_editar_proyecto(bigint,bigint,jsonb,text),banco.web_enviar_proyecto(bigint,bigint,text),
  banco.web_resolver_publicacion(bigint,bigint,bigint,text,text,integer,text) TO banco_web;
COMMENT ON FUNCTION banco.web_resolver_publicacion(bigint,bigint,bigint,text,text,integer,text) IS
  'WEB-04: aprobación/devolución/rechazo de revisión exacta; aprobar confirma cupo propuesto sin cambiarlo, audita y genera avisos internos atómicos mediante los contratos existentes.';
COMMENT ON FUNCTION banco.web_version_proyecto(bigint) IS
  'Token CAS opaco de contenido/estado/habilidades/envíos/eventos. Sin columnas nuevas; no es credencial ni autorización. Una versión distinta requiere recargar, no repetir una decisión obsoleta.';

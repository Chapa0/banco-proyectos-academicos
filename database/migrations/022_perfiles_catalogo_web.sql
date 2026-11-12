-- WEB-05: perfiles académicos propios y catálogo de publicaciones válidas.
-- Sin tablas/columnas nuevas; 001-021 permanecen inmutables.
-- Seis gateways de alcance expreso. Los auxiliares no se conceden a banco_web.
-- Reversión operativa hacia delante; conservar respaldo antes de aplicar.

CREATE FUNCTION banco.web_exigir_academico(p_actor bigint)
RETURNS text LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('alumno','profesor') THEN
    RAISE EXCEPTION 'El acceso requiere una cuenta académica' USING ERRCODE='42501';
  END IF;
  PERFORM banco.exigir_rol(p_actor,v_rol,true);
  RETURN v_rol;
END;
$$;
CREATE FUNCTION banco.web_version_perfil(p_actor bigint)
RETURNS text LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('usuario',u.id,'rol',u.rol_principal,
    'alumno',(SELECT to_jsonb(a) FROM banco.alumno a WHERE a.usuario_id=u.id),
    'profesor',(SELECT to_jsonb(p) FROM banco.profesor p WHERE p.usuario_id=u.id),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY habilidad_id)
      FROM banco.alumno_habilidad h WHERE h.alumno_id=u.id),'[]'::jsonb),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='perfil_academico' AND registro_afectado=u.id::text))::text,'UTF8')),'hex')
  FROM banco.usuario u WHERE u.id=p_actor;
$$;
CREATE FUNCTION banco.web_obtener_perfil_propio(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_resultado jsonb;
BEGIN
  -- Protege el par datos/version del guardado web concurrente, incluso sin perfil.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  PERFORM banco.web_exigir_academico(p_actor);
  v_resultado:=banco.consultar_perfil(p_actor,p_actor);
  RETURN v_resultado||jsonb_build_object('version',banco.web_version_perfil(p_actor));
END;
$$;
CREATE FUNCTION banco.web_validar_perfil(p_rol text,p_datos jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_clave text;v_item jsonb;v_id bigint;v_vistos bigint[]:='{}';
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'El perfil requiere datos válidos' USING ERRCODE='23514';
  END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF (p_rol='alumno' AND v_clave NOT IN ('matricula','carrera','semestre','datos_academicos','contacto_correo','contacto_telefono','habilidades'))
      OR (p_rol='profesor' AND v_clave NOT IN ('numero_empleado','especialidad','experiencia','contacto_correo','contacto_telefono')) THEN
      RAISE EXCEPTION 'El perfil contiene campos no permitidos' USING ERRCODE='23514';
    END IF;
    IF v_clave NOT IN ('semestre','habilidades') THEN
      IF jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') OR length(p_datos->>v_clave)>10000 THEN
        RAISE EXCEPTION 'Un campo del perfil no contiene texto válido' USING ERRCODE='23514';
      END IF;
    END IF;
  END LOOP;
  IF p_rol='alumno' THEN
    IF coalesce(p_datos->>'matricula','') !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'La matrícula es obligatoria' USING ERRCODE='23514';
    END IF;
    IF p_datos ? 'semestre' AND jsonb_typeof(p_datos->'semestre')<>'null'
      AND (jsonb_typeof(p_datos->'semestre') NOT IN ('string','number') OR p_datos->>'semestre' !~ '^[0-9]+$') THEN
      RAISE EXCEPTION 'El semestre requiere un entero positivo' USING ERRCODE='23514';
    END IF;
    BEGIN
      IF p_datos->>'semestre' IS NOT NULL AND (p_datos->>'semestre')::smallint<=0 THEN
        RAISE EXCEPTION 'El semestre debe ser positivo' USING ERRCODE='23514';
      END IF;
    EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN
      RAISE EXCEPTION 'Semestre inválido' USING ERRCODE='23514';
    END;
    IF p_datos ? 'habilidades' AND jsonb_typeof(p_datos->'habilidades')<>'array' THEN
      RAISE EXCEPTION 'Las habilidades requieren una lista' USING ERRCODE='23514';
    END IF;
    IF jsonb_array_length(coalesce(p_datos->'habilidades','[]'::jsonb))>200 THEN
      RAISE EXCEPTION 'La lista de habilidades supera el tamaño admitido' USING ERRCODE='23514';
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) LOOP
      IF jsonb_typeof(v_item)<>'object' OR NOT v_item ? 'habilidad_id' THEN
        RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514';
      END IF;
      IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) k WHERE k NOT IN ('habilidad_id','nivel_dominio','descripcion','evidencia'))
        OR jsonb_typeof(v_item->'habilidad_id') NOT IN ('string','number')
        OR v_item->>'habilidad_id' !~ '^-?[0-9]+$' THEN
        RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514';
      END IF;
      FOREACH v_clave IN ARRAY ARRAY['nivel_dominio','descripcion','evidencia'] LOOP
        IF v_item ? v_clave AND (jsonb_typeof(v_item->v_clave) NOT IN ('string','null') OR length(v_item->>v_clave)>10000) THEN
          RAISE EXCEPTION 'Los datos de habilidad deben ser texto' USING ERRCODE='23514';
        END IF;
      END LOOP;
      BEGIN v_id:=(v_item->>'habilidad_id')::bigint;
      EXCEPTION WHEN numeric_value_out_of_range THEN RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END;
      IF v_id=ANY(v_vistos) THEN RAISE EXCEPTION 'No se permite repetir una habilidad' USING ERRCODE='23514'; END IF;
      v_vistos:=array_append(v_vistos,v_id);
      PERFORM id FROM banco.habilidad WHERE id=v_id FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
    END LOOP;
  ELSIF coalesce(p_datos->>'numero_empleado','') !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El número de empleado es obligatorio' USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION banco.web_guardar_perfil_propio(p_actor bigint,p_datos jsonb,p_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;v_alumno banco.alumno%ROWTYPE;v_profesor banco.profesor%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Serializa el alta sin fila y escrituras del mismo titular. En perfiles
  -- existentes respeta participante -> Usuario, compatible con 008 y D-06.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR UPDATE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR UPDATE;
  END IF;
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_perfil(p_actor) THEN
    RAISE EXCEPTION 'El perfil cambió; recarga y revisa sus datos antes de guardar' USING ERRCODE='40001';
  END IF;
  PERFORM banco.web_validar_perfil(v_rol,p_datos);
  IF v_rol='alumno' THEN
    v_alumno:=jsonb_populate_record(NULL::banco.alumno,p_datos-'habilidades');
    INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo,contacto_telefono)
      VALUES(p_actor,v_alumno.matricula,v_alumno.carrera,v_alumno.semestre,v_alumno.datos_academicos,v_alumno.contacto_correo,v_alumno.contacto_telefono)
      ON CONFLICT(usuario_id) DO UPDATE SET matricula=EXCLUDED.matricula,carrera=EXCLUDED.carrera,
        semestre=EXCLUDED.semestre,datos_academicos=EXCLUDED.datos_academicos,contacto_correo=EXCLUDED.contacto_correo,
        contacto_telefono=EXCLUDED.contacto_telefono;
    DELETE FROM banco.alumno_habilidad WHERE alumno_id=p_actor;
    INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,descripcion,evidencia)
      SELECT p_actor,(v->>'habilidad_id')::bigint,v->>'nivel_dominio',v->>'descripcion',v->>'evidencia'
      FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) items(v);
  ELSE
    v_profesor:=jsonb_populate_record(NULL::banco.profesor,p_datos);
    INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo,contacto_telefono)
      VALUES(p_actor,v_profesor.numero_empleado,v_profesor.especialidad,v_profesor.experiencia,v_profesor.contacto_correo,v_profesor.contacto_telefono)
      ON CONFLICT(usuario_id) DO UPDATE SET numero_empleado=EXCLUDED.numero_empleado,especialidad=EXCLUDED.especialidad,
        experiencia=EXCLUDED.experiencia,contacto_correo=EXCLUDED.contacto_correo,contacto_telefono=EXCLUDED.contacto_telefono;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
    VALUES(p_actor,'usuario','guardar_perfil','perfil_academico',p_actor::text,
      jsonb_build_object('rol',v_rol,'version_anterior',p_version,'habilidades',CASE WHEN v_rol='alumno'
        THEN jsonb_array_length(coalesce(p_datos->'habilidades','[]'::jsonb)) ELSE 0 END)::text);
END;
$$;
CREATE FUNCTION banco.web_listar_habilidades_perfil(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nombre',nombre,'tipo',tipo,'descripcion',descripcion)
    ORDER BY tipo,nombre,id),'[]'::jsonb) FROM banco.habilidad);
END;
$$;

CREATE FUNCTION banco.web_catalogo_publicacion_valida(p_proyecto banco.proyecto,p_revision banco.revision_proyecto)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  RETURN p_proyecto.estado='publicado' AND p_revision.id=p_proyecto.revision_publicada_id
    AND p_revision.proyecto_id=p_proyecto.id AND p_revision.estado_revision='aprobada'
    AND p_revision.instantanea_contenido->>'version_formato'='2'
    AND p_proyecto.cupo_maximo_alumnos>0
    AND p_proyecto.titulo ~ '[^[:space:]]' AND p_proyecto.descripcion ~ '[^[:space:]]'
    AND p_proyecto.problematica ~ '[^[:space:]]' AND p_proyecto.objetivos ~ '[^[:space:]]'
    AND p_proyecto.justificacion ~ '[^[:space:]]' AND p_proyecto.alcance ~ '[^[:space:]]'
    AND EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=p_revision.id AND resultado='aprobada')
    AND banco.revision_coincide_con_proyecto(p_proyecto,p_revision.instantanea_contenido);
END;
$$;
CREATE FUNCTION banco.web_catalogo_disponibilidad(p_proyecto banco.proyecto)
RETURNS jsonb LANGUAGE sql VOLATILE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT jsonb_build_object('plazas_disponibles',greatest(0,p_proyecto.cupo_maximo_alumnos-
    (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente')),
    'direccion_disponible',NOT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente'));
$$;
CREATE FUNCTION banco.web_catalogo_proyectos(p_actor bigint,p_buscar text,p_empresa bigint,p_modalidad text,
  p_habilidad bigint,p_tipo_habilidad text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(p_buscar)>150 OR length(p_modalidad)>250
    OR (nullif(p_tipo_habilidad,'') IS NOT NULL AND p_tipo_habilidad NOT IN ('dura','blanda')) THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.*,r.instantanea_contenido,e.razon_social,banco.web_catalogo_disponibilidad(p) AS disponibilidad
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
      JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_catalogo_publicacion_valida(p,r)
  ), filtrados AS MATERIALIZED (
    SELECT v.id,v.titulo,v.descripcion,v.razon_social,v.modalidad,v.duracion_estimada,v.cupo_maximo_alumnos,
      (v.disponibilidad->>'plazas_disponibles')::integer AS plazas_disponibles,
      (v.disponibilidad->>'direccion_disponible')::boolean AS direccion_disponible
      FROM visibles v
      WHERE (p_empresa IS NULL OR v.empresa_id=p_empresa)
        AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(v.titulo||' '||coalesce(v.descripcion,'')||' '||v.razon_social),lower(btrim(p_buscar)))>0)
        AND (nullif(btrim(p_modalidad),'') IS NULL OR lower(btrim(v.modalidad))=lower(btrim(p_modalidad)))
        AND ((p_habilidad IS NULL AND nullif(p_tipo_habilidad,'') IS NULL) OR EXISTS(
          SELECT 1 FROM jsonb_array_elements(v.instantanea_contenido->'habilidades') h
          WHERE (p_habilidad IS NULL OR (h->>'habilidad_id')::bigint=p_habilidad)
            AND (nullif(p_tipo_habilidad,'') IS NULL OR h->>'tipo'=p_tipo_habilidad)))
  ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),
    'total',(SELECT count(*) FROM filtrados)));
END;
$$;
CREATE FUNCTION banco.web_obtener_proyecto_catalogo(p_actor bigint,p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_revision banco.revision_proyecto%ROWTYPE;v_empresa jsonb;
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  -- Las operaciones de participación/cierre bloquean este mismo proyecto.
  -- Tras esperar se revalida su fila vigente; no mezclar una publicación
  -- anterior al cierre con la disponibilidad posterior al cierre.
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible en el catálogo' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_revision FROM banco.revision_proyecto WHERE id=v_proyecto.revision_publicada_id AND proyecto_id=p_proyecto;
  IF NOT FOUND OR NOT coalesce(banco.web_catalogo_publicacion_valida(v_proyecto,v_revision),false) THEN
    RAISE EXCEPTION 'Proyecto no disponible en el catálogo' USING ERRCODE='23503'; END IF;
  SELECT jsonb_build_object('razon_social',razon_social,'sector',sector,'contacto_nombre',contacto_nombre,
    'contacto_correo',contacto_correo,'contacto_telefono',contacto_telefono) INTO v_empresa FROM banco.empresa WHERE id=v_proyecto.empresa_id;
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_proyecto)||jsonb_build_object('estado','publicado'),
    'empresa',v_empresa,'habilidades',v_revision.instantanea_contenido->'habilidades',
    'disponibilidad',banco.web_catalogo_disponibilidad(v_proyecto));
END;
$$;
CREATE FUNCTION banco.web_filtros_catalogo(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.*,r.instantanea_contenido,e.razon_social FROM banco.proyecto p
      JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
      JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_catalogo_publicacion_valida(p,r)
  ), habilidades AS (SELECT DISTINCT ON ((h->>'habilidad_id')::bigint) (h->>'habilidad_id')::bigint AS id,
      h->>'nombre' AS nombre,h->>'tipo' AS tipo FROM visibles v,
      LATERAL jsonb_array_elements(v.instantanea_contenido->'habilidades') h ORDER BY (h->>'habilidad_id')::bigint,v.id DESC)
  SELECT jsonb_build_object('empresas',coalesce((SELECT jsonb_agg(jsonb_build_object('id',empresa_id,'razon_social',razon_social) ORDER BY razon_social)
      FROM (SELECT DISTINCT empresa_id,razon_social FROM visibles) e),'[]'::jsonb),
    'modalidades',coalesce((SELECT jsonb_agg(modalidad ORDER BY modalidad)
      FROM (SELECT DISTINCT ON (lower(btrim(modalidad))) modalidad FROM visibles WHERE nullif(btrim(modalidad),'') IS NOT NULL
        ORDER BY lower(btrim(modalidad)),modalidad) m),'[]'::jsonb),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(habilidades) ORDER BY nombre,id) FROM habilidades),'[]'::jsonb)));
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_obtener_perfil_propio(bigint),banco.web_guardar_perfil_propio(bigint,jsonb,text),
  banco.web_listar_habilidades_perfil(bigint),banco.web_catalogo_proyectos(bigint,text,bigint,text,bigint,text,integer,integer),
  banco.web_obtener_proyecto_catalogo(bigint,bigint),banco.web_filtros_catalogo(bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_guardar_perfil_propio(bigint,jsonb,text) IS
  'WEB-05: titular académico activo crea/actualiza su perfil y habilidades de alumno, con CAS y auditoría; sin modificar identidad o acceso. La evidencia se almacena como texto, no se descarga ni ejecuta.';
COMMENT ON FUNCTION banco.web_catalogo_proyectos(bigint,text,bigint,text,bigint,text,integer,integer) IS
  'WEB-05: solo publicaciones aprobadas válidas de formato2; disponibilidad indicativa sin reservar ni autorizar candidaturas o dirección. Filtros y opciones no revelan borradores o revisiones privadas.';

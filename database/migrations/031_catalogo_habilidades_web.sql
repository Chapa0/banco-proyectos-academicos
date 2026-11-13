-- UX-10 (12 de noviembre de 2026): mantenimiento del catálogo de habilidades por la administración.
-- Atiende el pendiente de WEB-05 «cargar el catálogo institucional de habilidades». Ampliación aditiva:
-- no cambia tablas ni datos existentes. Los nombres equivalentes (sin distinguir mayúsculas, acentos
-- ni espacios repetidos) no se pueden crear de nuevo; los duplicados previos se señalan, no se fusionan,
-- porque las instantáneas publicadas guardan el identificador de cada habilidad.
-- Eliminar solo se permite si la habilidad no se usa en perfiles, proyectos, evidencias ni instantáneas.
-- Recuperación: respaldo previo y corrección hacia delante; conservar 001-030.

CREATE FUNCTION banco.normalizar_habilidad(p_nombre text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT lower(translate(btrim(regexp_replace(coalesce(p_nombre,''),'\s+',' ','g')),
    'ÁÉÍÓÚÜÑáéíóúüñ','AEIOUUNaeiouun'));
$$;

-- Usos de una habilidad en cualquier parte del sistema, incluidas instantáneas de revisiones.
CREATE FUNCTION banco.usos_habilidad(p_habilidad bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,banco,adjunto AS $$
  SELECT jsonb_build_object(
    'alumnos',(SELECT count(*) FROM banco.alumno_habilidad WHERE habilidad_id=p_habilidad),
    'proyectos',(SELECT count(*) FROM banco.proyecto_habilidad WHERE habilidad_id=p_habilidad),
    'evidencias',(SELECT count(*) FROM adjunto.documento WHERE habilidad_id=p_habilidad),
    'instantaneas',(SELECT count(*) FROM banco.revision_proyecto r
      WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r.instantanea_contenido->'habilidades','[]'::jsonb)) h
        WHERE (h->>'habilidad_id')::bigint=p_habilidad)));
$$;

CREATE FUNCTION banco.web_habilidades_admin(p_actor bigint,p_buscar text,p_tipo text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
BEGIN
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(coalesce(p_buscar,''))>100 OR (nullif(p_tipo,'') IS NOT NULL AND p_tipo NOT IN ('dura','blanda')) THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH filtrados AS MATERIALIZED (
      SELECT h.id,h.nombre,h.tipo,h.descripcion,banco.normalizar_habilidad(h.nombre) AS clave
      FROM banco.habilidad h
      WHERE (nullif(p_tipo,'') IS NULL OR h.tipo=p_tipo)
        AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(banco.normalizar_habilidad(h.nombre||' '||coalesce(h.descripcion,'')),
          banco.normalizar_habilidad(p_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY clave,id LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object(
      'datos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'nombre',p.nombre,'tipo',p.tipo,'descripcion',p.descripcion,
        'usos',banco.usos_habilidad(p.id),
        'duplicados',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'nombre',o.nombre) ORDER BY o.id),'[]'::jsonb)
          FROM banco.habilidad o WHERE o.id<>p.id AND banco.normalizar_habilidad(o.nombre)=p.clave)) ORDER BY p.clave,p.id) FROM pagina p),'[]'::jsonb),
      'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('total',count(*),'duras',count(*) FILTER (WHERE tipo='dura'),
        'blandas',count(*) FILTER (WHERE tipo='blanda')) FROM banco.habilidad)));
END;
$$;

CREATE FUNCTION banco.web_guardar_habilidad(p_actor bigint,p_id bigint,p_nombre text,p_tipo text,p_descripcion text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_nombre text;v_descripcion text;v_id bigint;v_anterior jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  v_nombre:=btrim(regexp_replace(coalesce(p_nombre,''),'\s+',' ','g'));
  v_descripcion:=nullif(btrim(coalesce(p_descripcion,'')),'');
  IF v_nombre='' OR length(v_nombre)>100 OR p_tipo IS NULL OR p_tipo NOT IN ('dura','blanda')
    OR length(coalesce(v_descripcion,''))>500 THEN
    RAISE EXCEPTION 'Datos de habilidad inválidos' USING ERRCODE='23514'; END IF;
  -- Serializa altas y cambios para que dos administradores no creen el mismo nombre a la vez.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_habilidad_catalogo',0));
  IF EXISTS(SELECT 1 FROM banco.habilidad WHERE banco.normalizar_habilidad(nombre)=banco.normalizar_habilidad(v_nombre)
      AND id IS DISTINCT FROM p_id) THEN
    RAISE EXCEPTION 'Ya existe una habilidad con ese nombre' USING ERRCODE='23505'; END IF;
  IF p_id IS NULL THEN
    INSERT INTO banco.habilidad(nombre,tipo,descripcion) VALUES(v_nombre,p_tipo,v_descripcion) RETURNING id INTO v_id;
  ELSE
    SELECT to_jsonb(h) INTO v_anterior FROM banco.habilidad h WHERE id=p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
    UPDATE banco.habilidad SET nombre=v_nombre,tipo=p_tipo,descripcion=v_descripcion WHERE id=p_id;
    v_id:=p_id;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario',CASE WHEN p_id IS NULL THEN 'crear_habilidad' ELSE 'editar_habilidad' END,'habilidad',v_id::text,
      CASE WHEN p_id IS NULL THEN 'creada' ELSE 'editada' END,
      jsonb_build_object('nombre',v_nombre,'tipo',p_tipo,'anterior',v_anterior)::text);
  RETURN v_id;
END;
$$;

CREATE FUNCTION banco.web_eliminar_habilidad(p_actor bigint,p_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_h banco.habilidad%ROWTYPE;v_usos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  PERFORM pg_advisory_xact_lock(hashtextextended('web_habilidad_catalogo',0));
  SELECT * INTO v_h FROM banco.habilidad WHERE id=p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
  v_usos:=banco.usos_habilidad(p_id);
  IF (v_usos->>'alumnos')::int+(v_usos->>'proyectos')::int+(v_usos->>'evidencias')::int+(v_usos->>'instantaneas')::int>0 THEN
    RAISE EXCEPTION 'La habilidad está en uso y se conserva' USING ERRCODE='55000'; END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','eliminar_habilidad','habilidad',p_id::text,'eliminada',to_jsonb(v_h)::text);
  DELETE FROM banco.habilidad WHERE id=p_id;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_habilidades_admin(bigint,text,text,integer,integer),
  banco.web_guardar_habilidad(bigint,bigint,text,text,text),banco.web_eliminar_habilidad(bigint,bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_guardar_habilidad(bigint,bigint,text,text,text) IS
  'UX-10: alta o edición de una habilidad por la administración; rechaza nombres equivalentes (mayúsculas, acentos, espacios). Auditado.';
COMMENT ON FUNCTION banco.web_eliminar_habilidad(bigint,bigint) IS
  'UX-10: elimina una habilidad solo si no aparece en perfiles, proyectos, evidencias ni instantáneas publicadas. Auditado.';

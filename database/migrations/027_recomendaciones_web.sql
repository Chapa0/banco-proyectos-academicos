-- UX-06: «Recomendados para ti». Proyectos del catálogo ordenados por coincidencia con las habilidades del alumno.
-- Ampliación aditiva de solo lectura: no cambia datos, tablas ni gateways anteriores.
-- Usa la misma visibilidad que web_catalogo_proyectos (publicación válida) y la misma regla de coincidencia
-- que 025 (instantánea publicada; el nivel no se compara). Excluye proyectos sin plazas y aquellos donde
-- el alumno ya tiene una candidatura (cualquier estado) o una asignación. Solo orienta: no decide candidaturas.
-- Recuperación: respaldo previo y corrección hacia delante; conservar 001-026.

CREATE FUNCTION banco.web_recomendaciones(p_actor bigint,p_limite integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'Límite de recomendaciones inválido' USING ERRCODE='23514'; END IF;
  -- El profesor no registra habilidades estructuradas; no hay con qué recomendar.
  IF v_rol<>'alumno' THEN RETURN '[]'::jsonb; END IF;
  RETURN coalesce((
    WITH propias AS MATERIALIZED (SELECT habilidad_id FROM banco.alumno_habilidad WHERE alumno_id=p_actor),
    visibles AS MATERIALIZED (
      SELECT p.id,p.titulo,p.descripcion,p.modalidad,p.cupo_maximo_alumnos,e.razon_social,r.instantanea_contenido,
        (banco.web_catalogo_disponibilidad(p)->>'plazas_disponibles')::integer AS plazas_disponibles
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
        JOIN banco.empresa e ON e.id=p.empresa_id
      WHERE banco.web_catalogo_publicacion_valida(p,r)
        AND NOT EXISTS(SELECT 1 FROM banco.candidatura c WHERE c.proyecto_id=p.id AND c.alumno_id=p_actor)
        AND NOT EXISTS(SELECT 1 FROM banco.asignacion_alumno a WHERE a.proyecto_id=p.id AND a.alumno_id=p_actor)),
    puntuados AS (
      SELECT v.id,v.titulo,v.descripcion,v.modalidad,v.razon_social,v.plazas_disponibles,v.cupo_maximo_alumnos,
        count(*) AS requeridas,
        count(*) FILTER (WHERE (h->>'habilidad_id')::bigint IN (SELECT habilidad_id FROM propias)) AS cumplidas,
        count(*) FILTER (WHERE coalesce((h->>'obligatoria')::boolean,false)
          AND (h->>'habilidad_id')::bigint NOT IN (SELECT habilidad_id FROM propias)) AS faltan_obligatorias,
        coalesce(jsonb_agg(jsonb_build_object('nombre',h->>'nombre','obligatoria',coalesce((h->>'obligatoria')::boolean,false))
          ORDER BY NOT coalesce((h->>'obligatoria')::boolean,false),h->>'nombre')
          FILTER (WHERE (h->>'habilidad_id')::bigint NOT IN (SELECT habilidad_id FROM propias)),'[]'::jsonb) AS faltantes
      FROM visibles v, LATERAL jsonb_array_elements(v.instantanea_contenido->'habilidades') h
      WHERE v.plazas_disponibles>0
      GROUP BY v.id,v.titulo,v.descripcion,v.modalidad,v.razon_social,v.plazas_disponibles,v.cupo_maximo_alumnos),
    elegidos AS (
      SELECT * FROM puntuados WHERE cumplidas>0
      ORDER BY faltan_obligatorias,cumplidas::numeric/requeridas DESC,cumplidas DESC,id DESC
      LIMIT p_limite)
    SELECT jsonb_agg(jsonb_build_object('id',id,'titulo',titulo,'descripcion',descripcion,'modalidad',modalidad,
      'razon_social',razon_social,'plazas_disponibles',plazas_disponibles,'cupo_maximo_alumnos',cupo_maximo_alumnos,
      'coincidencia',jsonb_build_object('requeridas',requeridas,'cumplidas',cumplidas,'faltantes',faltantes))
      ORDER BY faltan_obligatorias,cumplidas::numeric/requeridas DESC,cumplidas DESC,id DESC)
    FROM elegidos
  ),'[]'::jsonb);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_recomendaciones(bigint,integer) TO banco_web;
COMMENT ON FUNCTION banco.web_recomendaciones(bigint,integer) IS
  'UX-06: hasta 20 proyectos publicados con plazas, donde el alumno actor no tiene candidatura ni asignación, ordenados por obligatorias cumplidas y proporción de coincidencia. Profesor recibe arreglo vacío.';

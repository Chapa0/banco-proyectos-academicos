-- UX-02: coincidencia entre las habilidades propias del alumno y las requeridas por proyectos publicados.
-- Ampliación aditiva de solo lectura: no cambia datos, tablas ni gateways anteriores.
-- Regla: una habilidad requerida cuenta como cumplida si el alumno la tiene registrada en su perfil.
-- El nivel es texto libre (RF-20) y no se compara; la coincidencia orienta y no decide candidaturas.
-- Recuperación: respaldo previo y corrección hacia delante; conservar 001-024.

CREATE FUNCTION banco.web_coincidencia_catalogo(p_actor bigint,p_proyectos bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_rol text;
BEGIN
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_proyectos IS NULL OR cardinality(p_proyectos)>100 THEN
    RAISE EXCEPTION 'Lista de proyectos inválida' USING ERRCODE='23514'; END IF;
  -- La coincidencia describe habilidades del alumno; el profesor no tiene habilidades estructuradas.
  IF v_rol<>'alumno' THEN RETURN '{}'::jsonb; END IF;
  RETURN coalesce((
    WITH propias AS MATERIALIZED (SELECT habilidad_id FROM banco.alumno_habilidad WHERE alumno_id=p_actor),
    requeridas AS (
      SELECT p.id AS proyecto_id,(h->>'habilidad_id')::bigint AS habilidad_id,h->>'nombre' AS nombre,
        coalesce((h->>'obligatoria')::boolean,false) AS obligatoria
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id,
        LATERAL jsonb_array_elements(r.instantanea_contenido->'habilidades') h
      WHERE p.id=ANY(p_proyectos) AND banco.web_catalogo_publicacion_valida(p,r))
    SELECT jsonb_object_agg(proyecto_id::text,datos) FROM (
      SELECT proyecto_id,jsonb_build_object(
        'requeridas',count(*),
        'cumplidas',count(*) FILTER (WHERE habilidad_id IN (SELECT habilidad_id FROM propias)),
        'faltantes',coalesce(jsonb_agg(jsonb_build_object('nombre',nombre,'obligatoria',obligatoria) ORDER BY NOT obligatoria,nombre)
          FILTER (WHERE habilidad_id NOT IN (SELECT habilidad_id FROM propias)),'[]'::jsonb)) AS datos
      FROM requeridas GROUP BY proyecto_id) por_proyecto
  ),'{}'::jsonb);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_coincidencia_catalogo(bigint,bigint[]) TO banco_web;
COMMENT ON FUNCTION banco.web_coincidencia_catalogo(bigint,bigint[]) IS
  'UX-02: por proyecto publicado válido, habilidades requeridas, cumplidas por el alumno actor y faltantes. Solo datos propios y la instantánea publicada; profesor recibe objeto vacío. Hasta 100 proyectos.';

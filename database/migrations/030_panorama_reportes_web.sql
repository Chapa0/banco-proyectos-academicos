-- UX-09: panorama gráfico de Reportes (RF-41). Distribuciones globales para la administración.
-- Ampliación aditiva de solo lectura: no cambia datos, tablas ni gateways anteriores.
-- Mismos conteos que web_reporte sin filtros: proyectos, candidaturas y solicitudes de dirección por estado
-- (incluye estados en cero para que las gráficas conserven su orden) y carga docente vigente frente al
-- límite de tres proyectos (D-04). Recuperación: respaldo previo y corrección hacia delante; conservar 001-029.

CREATE FUNCTION banco.web_panorama_reportes(p_actor bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  RETURN jsonb_build_object(
    'proyectos',(SELECT jsonb_object_agg(e,(SELECT count(*) FROM banco.proyecto WHERE estado=e)) FROM unnest(ARRAY[
      'borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado']) e),
    'candidaturas',(SELECT jsonb_object_agg(e,(SELECT count(*) FROM banco.candidatura WHERE estado=e)) FROM unnest(ARRAY[
      'pendiente_evaluacion','evaluada','preseleccionada','aprobada','rechazada','cancelada']) e),
    'direcciones',(SELECT jsonb_object_agg(e,(SELECT count(*) FROM banco.solicitud_direccion WHERE estado=e)) FROM unnest(ARRAY[
      'pendiente','aprobada','rechazada','cancelada']) e),
    'carga',coalesce((SELECT jsonb_agg(jsonb_build_object('profesor_id',profesor_id,'nombre',nombre,'vigentes',vigentes,'limite',3)
      ORDER BY vigentes DESC,nombre) FROM (
        SELECT pr.usuario_id AS profesor_id,u.nombre,
          (SELECT count(*) FROM banco.asignacion_direccion d WHERE d.profesor_id=pr.usuario_id AND d.estado='vigente') AS vigentes
        FROM banco.profesor pr JOIN banco.usuario u ON u.id=pr.usuario_id) c
      WHERE vigentes>0),'[]'::jsonb),
    'profesores',(SELECT count(*) FROM banco.profesor));
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_panorama_reportes(bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_panorama_reportes(bigint) IS
  'UX-09/RF-41: conteos globales por estado de proyectos, candidaturas y direcciones, y carga docente vigente frente al límite de tres. Solo administración.';

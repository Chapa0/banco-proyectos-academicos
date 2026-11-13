-- UX-07: datos de la constancia de participación de un alumno o de un director en un proyecto concluido.
-- Ampliación aditiva de solo lectura: no cambia datos, tablas ni gateways anteriores.
-- Solo hay constancia si la asignación terminó con el cierre del proyecto (estado finalizada y sin retiro).
-- La pide el titular de la solicitud o la administración; cualquier otro actor recibe 23503, como si no existiera.
-- El documento lo genera el sistema: no lleva firma institucional, que sigue sin política acordada.
-- Recuperación: respaldo previo y corrección hacia delante; conservar 001-027.

CREATE FUNCTION banco.web_constancia(p_actor bigint,p_tipo text,p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_s jsonb;v_rol text;v_titular bigint;v_a record;v_p banco.proyecto%ROWTYPE;v_inicio timestamptz;
BEGIN
  IF p_tipo IS NULL OR p_tipo NOT IN ('candidatura','direccion') THEN
    RAISE EXCEPTION 'Tipo de participación inválido' USING ERRCODE='23514'; END IF;
  -- Misma apertura y permisos de lectura que el detalle de la solicitud.
  v_s:=banco.web_abrir_participacion(p_actor,p_tipo,p_id,false);
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  v_titular:=CASE p_tipo WHEN 'candidatura' THEN (SELECT alumno_id FROM banco.candidatura WHERE id=p_id)
    ELSE (SELECT profesor_id FROM banco.solicitud_direccion WHERE id=p_id) END;
  IF v_rol<>'administrador' AND p_actor<>v_titular THEN
    RAISE EXCEPTION 'Constancia no disponible' USING ERRCODE='23503'; END IF;

  IF p_tipo='candidatura' THEN
    SELECT id,proyecto_id,inicio,fin,estado,evento_retiro_id INTO v_a FROM banco.asignacion_alumno WHERE candidatura_id=p_id;
  ELSE
    SELECT id,proyecto_id,inicio,fin,estado,evento_retiro_id INTO v_a FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_id;
  END IF;
  IF NOT FOUND OR v_a.estado<>'finalizada' OR v_a.evento_retiro_id IS NOT NULL OR v_a.fin IS NULL THEN
    RAISE EXCEPTION 'Constancia no disponible' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_a.proyecto_id;
  IF v_p.estado<>'finalizado' THEN RAISE EXCEPTION 'Constancia no disponible' USING ERRCODE='23503'; END IF;
  SELECT fecha INTO v_inicio FROM banco.evento_auditoria WHERE id=v_p.evento_inicio_id;

  RETURN jsonb_build_object(
    'folio','BP-'||to_char(v_a.fin AT TIME ZONE 'America/Mexico_City','YYYY')||'-'||CASE p_tipo WHEN 'candidatura' THEN 'A' ELSE 'D' END||lpad(v_a.id::text,5,'0'),
    'tipo',p_tipo,
    'participante',CASE p_tipo WHEN 'candidatura' THEN
        (SELECT jsonb_build_object('nombre',u.nombre,'identificador',a.matricula,'carrera',a.carrera)
           FROM banco.usuario u JOIN banco.alumno a ON a.usuario_id=u.id WHERE u.id=v_titular)
      ELSE (SELECT jsonb_build_object('nombre',u.nombre,'identificador',p.numero_empleado,'carrera',NULL)
           FROM banco.usuario u JOIN banco.profesor p ON p.usuario_id=u.id WHERE u.id=v_titular) END,
    'proyecto',(SELECT jsonb_build_object('titulo',v_p.titulo,'empresa',e.razon_social,'modalidad',v_p.modalidad,'descripcion',v_p.descripcion)
      FROM banco.empresa e WHERE e.id=v_p.empresa_id),
    'periodo',jsonb_build_object('inicio',coalesce(v_inicio,v_a.inicio),'fin',v_a.fin),
    'directores',(SELECT coalesce(jsonb_agg(u.nombre ORDER BY u.nombre),'[]'::jsonb) FROM banco.asignacion_direccion d
      JOIN banco.usuario u ON u.id=d.profesor_id WHERE d.proyecto_id=v_p.id AND d.estado='finalizada' AND d.evento_retiro_id IS NULL),
    'alumnos',(SELECT coalesce(jsonb_agg(u.nombre ORDER BY u.nombre),'[]'::jsonb) FROM banco.asignacion_alumno x
      JOIN banco.usuario u ON u.id=x.alumno_id WHERE x.proyecto_id=v_p.id AND x.estado='finalizada' AND x.evento_retiro_id IS NULL));
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_constancia(bigint,text,bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_constancia(bigint,text,bigint) IS
  'UX-07: datos de la constancia de una participación concluida con el cierre del proyecto (sin retiro). Solo el titular o la administración; otro actor recibe 23503.';

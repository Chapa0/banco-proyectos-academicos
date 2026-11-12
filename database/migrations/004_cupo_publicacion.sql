-- D-02 confirmada: cupo propio propuesto por la empresa y validado por el
-- administrador al aprobar la revisión exacta, antes de publicar.
-- Sin capacidad universal ni valor por defecto. El conteo de plazas se añade
-- por separado con los estados de D-06; esta migración no habilita D-07.
-- Las revisiones v1 y publicaciones históricas se conservan sin inventar cupo.
-- Su reconciliación requiere un flujo explícito; no habilitan asignaciones nuevas.

ALTER TABLE banco.proyecto ADD COLUMN cupo_maximo_alumnos integer;
ALTER TABLE banco.proyecto ADD CONSTRAINT ck_proyecto_cupo_positivo
  CHECK (cupo_maximo_alumnos IS NULL OR cupo_maximo_alumnos > 0);
COMMENT ON COLUMN banco.proyecto.cupo_maximo_alumnos IS
  'D-02: capacidad propuesta por la empresa, sin default. Obligatoria y positiva al enviar; validada al aprobar la revisión v2 exacta. No se cambia después de publicar (D-07).';

CREATE FUNCTION banco.exigir_cupo_proyecto(p_proyecto banco.proyecto)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF p_proyecto.cupo_maximo_alumnos IS NULL OR p_proyecto.cupo_maximo_alumnos <= 0 THEN
    RAISE EXCEPTION 'D-02: indicar un cupo máximo de alumnos positivo antes de enviar/publicar'
      USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION banco.contenido_proyecto(p_proyecto banco.proyecto)
RETURNS jsonb LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog,banco AS $$
  SELECT jsonb_build_object(
    'id',p_proyecto.id,'empresa_id',p_proyecto.empresa_id,'titulo',p_proyecto.titulo,
    'descripcion',p_proyecto.descripcion,'problematica',p_proyecto.problematica,
    'objetivos',p_proyecto.objetivos,'justificacion',p_proyecto.justificacion,
    'alcance',p_proyecto.alcance,'requisitos_academicos',p_proyecto.requisitos_academicos,
    'duracion_estimada',p_proyecto.duracion_estimada,'modalidad',p_proyecto.modalidad,
    'fecha_inicio_estimada',p_proyecto.fecha_inicio_estimada,
    'fecha_fin_estimada',p_proyecto.fecha_fin_estimada,'recursos',p_proyecto.recursos,
    'cupo_maximo_alumnos',p_proyecto.cupo_maximo_alumnos);
$$;

CREATE OR REPLACE FUNCTION banco.instantanea_proyecto(p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE STRICT SET search_path=pg_catalog,banco AS $$
DECLARE v_instantanea jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT jsonb_build_object('version_formato',2,'proyecto',banco.contenido_proyecto(p),
    'habilidades',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'habilidad_id',h.id,'nombre',h.nombre,'tipo',h.tipo,'descripcion',h.descripcion,
      'nivel_minimo',ph.nivel_minimo,'obligatoria',ph.obligatoria) ORDER BY h.id)
      FROM banco.proyecto_habilidad ph JOIN banco.habilidad h ON h.id=ph.habilidad_id
      WHERE ph.proyecto_id=p.id),'[]'::jsonb))
  INTO v_instantanea FROM banco.proyecto p WHERE p.id=p_proyecto;
  RETURN v_instantanea;
END;
$$;

CREATE OR REPLACE FUNCTION banco.revision_coincide_con_proyecto(p_proyecto banco.proyecto,p_instantanea jsonb)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_actual jsonb; v_enviado jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_instantanea->>'version_formato' = '1' THEN
    -- Compatibilidad de lectura/corrección: una revisión histórica no se
    -- convierte en propuesta de cupo ni se reescribe al ampliar el esquema.
    IF p_proyecto.cupo_maximo_alumnos IS NOT NULL
      OR p_instantanea->'proyecto' IS DISTINCT FROM
        (banco.contenido_proyecto(p_proyecto) - 'cupo_maximo_alumnos') THEN
      RETURN false;
    END IF;
  ELSIF p_instantanea->>'version_formato' = '2' THEN
    IF p_instantanea->'proyecto' IS DISTINCT FROM banco.contenido_proyecto(p_proyecto) THEN
      RETURN false;
    END IF;
  ELSE
    RETURN false;
  END IF;
  IF jsonb_typeof(p_instantanea->'habilidades') IS DISTINCT FROM 'array' THEN
    RETURN false;
  END IF;
  -- Los nombres/tipos/descripciones del catálogo se interpretan con la copia
  -- enviada. Cambiar el catálogo no reescribe una publicación anterior.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('habilidad_id',habilidad_id,
    'nivel_minimo',nivel_minimo,'obligatoria',obligatoria) ORDER BY habilidad_id),'[]'::jsonb)
    INTO v_actual FROM banco.proyecto_habilidad WHERE proyecto_id=p_proyecto.id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('habilidad_id',h->'habilidad_id',
    'nivel_minimo',h->'nivel_minimo','obligatoria',h->'obligatoria') ORDER BY h->'habilidad_id'),'[]'::jsonb)
    INTO v_enviado FROM jsonb_array_elements(p_instantanea->'habilidades') AS elementos(h);
  RETURN v_actual=v_enviado;
END;
$$;

CREATE OR REPLACE FUNCTION banco.exigir_publicacion_valida(p_proyecto banco.proyecto)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_revision banco.revision_proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_proyecto.estado <> 'publicado' OR p_proyecto.revision_publicada_id IS NULL THEN
    RAISE EXCEPTION 'RN-02/RN-09: el proyecto requiere publicación y versión autorizada' USING ERRCODE='23514';
  END IF;
  PERFORM banco.exigir_campos_proyecto(p_proyecto);
  PERFORM banco.exigir_cupo_proyecto(p_proyecto);
  SELECT * INTO v_revision FROM banco.revision_proyecto
    WHERE id=p_proyecto.revision_publicada_id AND proyecto_id=p_proyecto.id FOR SHARE;
  IF NOT FOUND OR v_revision.estado_revision <> 'aprobada' THEN
    RAISE EXCEPTION 'RN-02: la revisión publicada debe estar aprobada y pertenecer a este proyecto' USING ERRCODE='23514';
  END IF;
  IF v_revision.instantanea_contenido->>'version_formato' IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION 'D-02: una revisión histórica sin cupo no acredita capacidad validada; conservar su historial' USING ERRCODE='23514';
  END IF;
  IF NOT banco.revision_coincide_con_proyecto(p_proyecto,v_revision.instantanea_contenido) THEN
    RAISE EXCEPTION 'RN-02: el contenido/requisitos no coinciden con la versión publicada' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM banco.decision_administrativa
    WHERE revision_proyecto_id=v_revision.id AND resultado='aprobada') THEN
    RAISE EXCEPTION 'RN-02: falta una aprobación administrativa de esta revisión exacta' USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION banco.enviar_proyecto(p_proyecto bigint,p_autor bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_numero integer; v_revision bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto % inexistente',p_proyecto USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_representante(p_autor,v_proyecto.empresa_id);
  IF v_proyecto.revision_publicada_id IS NOT NULL THEN
    RAISE EXCEPTION 'D-07 pendiente: no se habilita edición/reenvío después de publicar' USING ERRCODE='55000';
  END IF;
  IF v_proyecto.estado NOT IN ('borrador','en_correccion') THEN
    RAISE EXCEPTION 'Solo un borrador o proyecto devuelto puede enviarse a revisión' USING ERRCODE='55000';
  END IF;
  PERFORM banco.exigir_campos_proyecto(v_proyecto);
  PERFORM banco.exigir_cupo_proyecto(v_proyecto);
  -- Las relaciones se serializan sobre Proyecto; el catálogo se mantiene estable
  -- mientras se obtiene la copia interpretativa, sin exigir un mínimo de filas.
  PERFORM h.id FROM banco.proyecto_habilidad ph JOIN banco.habilidad h ON h.id=ph.habilidad_id
    WHERE ph.proyecto_id=p_proyecto ORDER BY h.id FOR SHARE OF h;
  SELECT COALESCE(max(numero),0)+1 INTO v_numero FROM banco.revision_proyecto WHERE proyecto_id=p_proyecto;
  INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,instantanea_contenido)
  VALUES(p_proyecto,p_autor,v_numero,banco.instantanea_proyecto(p_proyecto)) RETURNING id INTO v_revision;
  UPDATE banco.proyecto SET estado='en_revision' WHERE id=p_proyecto;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_autor,'usuario','enviar_proyecto','proyecto',p_proyecto::text,
    v_proyecto.estado || ' -> en_revision','revision=' || v_revision::text);
  RETURN v_revision;
END;
$$;

CREATE OR REPLACE FUNCTION banco.resolver_publicacion(p_revision bigint,p_admin bigint,p_resultado text,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_revision banco.revision_proyecto%ROWTYPE; v_proyecto banco.proyecto%ROWTYPE;
  v_proyecto_id bigint; v_decision bigint; v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_resultado IS NULL OR p_resultado NOT IN ('aprobada','en_correccion','rechazada')
    OR nullif(btrim(p_motivo),'') IS NULL THEN
    RAISE EXCEPTION 'La resolución requiere aprobada/en_correccion/rechazada y motivo no vacío' USING ERRCODE='23514';
  END IF;
  SELECT proyecto_id INTO v_proyecto_id FROM banco.revision_proyecto WHERE id=p_revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revisión % inexistente',p_revision USING ERRCODE='23503'; END IF;
  -- Proyecto es la fila estable de serialización de envíos y resoluciones.
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_proyecto_id FOR UPDATE;
  SELECT * INTO v_revision FROM banco.revision_proyecto WHERE id=p_revision FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_proyecto.revision_publicada_id IS NOT NULL THEN
    RAISE EXCEPTION 'D-07 pendiente: no se reabre ni sustituye una publicación' USING ERRCODE='55000';
  END IF;
  IF v_proyecto.estado <> 'en_revision' OR v_revision.estado_revision <> 'en_revision'
    OR EXISTS (SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=p_revision)
    OR EXISTS (SELECT 1 FROM banco.revision_proyecto WHERE proyecto_id=v_proyecto_id AND numero>v_revision.numero) THEN
    RAISE EXCEPTION 'La revisión no es el envío pendiente vigente o ya fue resuelta' USING ERRCODE='55000';
  END IF;
  PERFORM banco.exigir_campos_proyecto(v_proyecto);
  IF NOT banco.revision_coincide_con_proyecto(v_proyecto,v_revision.instantanea_contenido) THEN
    RAISE EXCEPTION 'El proyecto y sus requisitos difieren del contenido enviado' USING ERRCODE='23514';
  END IF;
  IF p_resultado='aprobada' THEN
    PERFORM banco.exigir_cupo_proyecto(v_proyecto);
    IF v_revision.instantanea_contenido->>'version_formato' IS DISTINCT FROM '2' THEN
      RAISE EXCEPTION 'D-02: aprobar requiere una propuesta de cupo en la revisión exacta' USING ERRCODE='23514';
    END IF;
  END IF;
  -- La aprobación de esta revisión incluye la validación administrativa del
  -- cupo propuesto. Cambiarlo requiere devolución y un nuevo envío empresarial.
  INSERT INTO banco.decision_administrativa(administrador_usuario_id,revision_proyecto_id,resultado,justificacion)
  VALUES(p_admin,p_revision,p_resultado,p_motivo) RETURNING id INTO v_decision;
  UPDATE banco.revision_proyecto SET estado_revision=p_resultado WHERE id=p_revision;
  v_estado := CASE p_resultado WHEN 'aprobada' THEN 'publicado' WHEN 'en_correccion' THEN 'en_correccion' ELSE 'rechazado' END;
  UPDATE banco.proyecto SET estado=v_estado,
    revision_publicada_id=CASE WHEN p_resultado='aprobada' THEN p_revision ELSE NULL END
    WHERE id=v_proyecto_id;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','resolver_publicacion','proyecto',v_proyecto_id::text,
    v_proyecto.estado || ' -> ' || v_estado,
    format('revision=%s;decision=%s;resultado=%s;cupo_validado=%s',p_revision,v_decision,p_resultado,
      CASE WHEN p_resultado='aprobada' THEN v_proyecto.cupo_maximo_alumnos::text ELSE 'no' END));
  RETURN v_decision;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.enviar_proyecto(bigint,bigint) IS
  'Función interna del propietario: exige seis campos RF-08 y cupo positivo D-02; representante activo, snapshot v2 y auditoría. No API ni autenticación del actor.';
COMMENT ON FUNCTION banco.resolver_publicacion(bigint,bigint,text,text) IS
  'Función interna del propietario: aprobar valida el cupo propuesto de la revisión v2 exacta con administrador activo, motivo y auditoría atómicos. Corrección/rechazo de revisiones v1 preserva historia; sin inicio ni cambio publicado.';

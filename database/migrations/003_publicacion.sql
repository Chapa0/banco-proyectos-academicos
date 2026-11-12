-- Publicación inicial independiente: PDF p.3 RF-08/RF-09/RF-10 y p.5 RN-02;
-- RN-09 exige autorización y disponibilidad al asignar. D-01..D-08 siguen
-- condicionando cupos, inicio y edición posterior. No se aprueban esas políticas.
-- Información inequívoca exigida al enviar: seis campos enumerados en RF-08.
-- RF-09/RF-10 no fijan mínimos ni obligatoriedad de habilidades, modalidad,
-- duración, recursos o fechas: se conservan como opcionales y sin listas CSV.
-- Funciones internas INVOKER: propietario únicamente; no son APIs/autenticación.

ALTER TABLE banco.revision_proyecto
  ADD CONSTRAINT uq_revision_proyecto_pertenencia UNIQUE(id,proyecto_id);
ALTER TABLE banco.proyecto ADD COLUMN revision_publicada_id bigint;
ALTER TABLE banco.proyecto ADD CONSTRAINT fk_proyecto_revision_publicada
  FOREIGN KEY(revision_publicada_id,id) REFERENCES banco.revision_proyecto(id,proyecto_id)
  ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE INDEX ix_proyecto_revision_publicada ON banco.proyecto(revision_publicada_id);
-- Una resolución por envío inicial; una devolución requiere un envío nuevo.
-- Una futura reapertura de la publicación requerirá resolver D-07 y migrar.
CREATE UNIQUE INDEX uq_decision_publicacion_revision
ON banco.decision_administrativa(revision_proyecto_id) WHERE revision_proyecto_id IS NOT NULL;

CREATE FUNCTION banco.contenido_proyecto(p_proyecto banco.proyecto)
RETURNS jsonb LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog,banco AS $$
  SELECT jsonb_build_object(
    'id',p_proyecto.id,'empresa_id',p_proyecto.empresa_id,'titulo',p_proyecto.titulo,
    'descripcion',p_proyecto.descripcion,'problematica',p_proyecto.problematica,
    'objetivos',p_proyecto.objetivos,'justificacion',p_proyecto.justificacion,
    'alcance',p_proyecto.alcance,'requisitos_academicos',p_proyecto.requisitos_academicos,
    'duracion_estimada',p_proyecto.duracion_estimada,'modalidad',p_proyecto.modalidad,
    'fecha_inicio_estimada',p_proyecto.fecha_inicio_estimada,
    'fecha_fin_estimada',p_proyecto.fecha_fin_estimada,'recursos',p_proyecto.recursos);
$$;
CREATE FUNCTION banco.instantanea_proyecto(p_proyecto bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE STRICT SET search_path=pg_catalog,banco AS $$
DECLARE v_instantanea jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT jsonb_build_object('version_formato',1,'proyecto',banco.contenido_proyecto(p),
    'habilidades',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'habilidad_id',h.id,'nombre',h.nombre,'tipo',h.tipo,'descripcion',h.descripcion,
      'nivel_minimo',ph.nivel_minimo,'obligatoria',ph.obligatoria) ORDER BY h.id)
      FROM banco.proyecto_habilidad ph JOIN banco.habilidad h ON h.id=ph.habilidad_id
      WHERE ph.proyecto_id=p.id),'[]'::jsonb))
  INTO v_instantanea FROM banco.proyecto p WHERE p.id=p_proyecto;
  RETURN v_instantanea;
END;
$$;
CREATE FUNCTION banco.exigir_campos_proyecto(p_proyecto banco.proyecto)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF nullif(btrim(p_proyecto.titulo),'') IS NULL
    OR nullif(btrim(p_proyecto.descripcion),'') IS NULL
    OR nullif(btrim(p_proyecto.problematica),'') IS NULL
    OR nullif(btrim(p_proyecto.objetivos),'') IS NULL
    OR nullif(btrim(p_proyecto.justificacion),'') IS NULL
    OR nullif(btrim(p_proyecto.alcance),'') IS NULL THEN
    RAISE EXCEPTION 'RF-08/RN-02: título, descripción, problemática, objetivos, justificación y alcance son necesarios para enviar/publicar'
      USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION banco.revision_coincide_con_proyecto(p_proyecto banco.proyecto,p_instantanea jsonb)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_actual jsonb; v_enviado jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_instantanea->>'version_formato' IS DISTINCT FROM '1'
    OR jsonb_typeof(p_instantanea->'habilidades') IS DISTINCT FROM 'array'
    OR p_instantanea->'proyecto' IS DISTINCT FROM banco.contenido_proyecto(p_proyecto) THEN
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
CREATE FUNCTION banco.exigir_publicacion_valida(p_proyecto banco.proyecto)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_revision banco.revision_proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_proyecto.estado <> 'publicado' OR p_proyecto.revision_publicada_id IS NULL THEN
    RAISE EXCEPTION 'RN-02/RN-09: el proyecto requiere publicación y versión autorizada' USING ERRCODE='23514';
  END IF;
  PERFORM banco.exigir_campos_proyecto(p_proyecto);
  SELECT * INTO v_revision FROM banco.revision_proyecto
    WHERE id=p_proyecto.revision_publicada_id AND proyecto_id=p_proyecto.id FOR SHARE;
  IF NOT FOUND OR v_revision.estado_revision <> 'aprobada' THEN
    RAISE EXCEPTION 'RN-02: la revisión publicada debe estar aprobada y pertenecer a este proyecto' USING ERRCODE='23514';
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

CREATE FUNCTION banco.proteger_publicacion_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF NEW.estado IN ('en_curso','finalizado','cancelado') THEN
    RAISE EXCEPTION 'D-05/D-06/D-07 pendientes: el ciclo posterior a publicación no está habilitado'
      USING ERRCODE='55000';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.revision_publicada_id IS NOT NULL THEN
      IF NEW.revision_publicada_id IS DISTINCT FROM OLD.revision_publicada_id
        OR banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
        RAISE EXCEPTION 'D-07 pendiente: no se permite modificar contenido ni sustituir la versión publicada' USING ERRCODE='55000';
      END IF;
      IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        RAISE EXCEPTION 'D-05/D-06/D-07 pendientes: el ciclo posterior a publicación requiere su flujo específico' USING ERRCODE='55000';
      END IF;
    ELSIF OLD.estado NOT IN ('borrador','en_correccion')
      AND banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
      RAISE EXCEPTION 'El contenido enviado no se edita durante revisión; requiere devolución para correcciones' USING ERRCODE='55000';
    END IF;
  END IF;
  IF NEW.revision_publicada_id IS NOT NULL AND NEW.estado <> 'publicado' THEN
    RAISE EXCEPTION 'Solo un proyecto publicado puede referir a una revisión publicada' USING ERRCODE='23514';
  END IF;
  IF NEW.estado='publicado' OR NEW.revision_publicada_id IS NOT NULL THEN
    PERFORM banco.exigir_publicacion_valida(NEW);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_proyecto_publicacion BEFORE INSERT OR UPDATE ON banco.proyecto
FOR EACH ROW EXECUTE FUNCTION banco.proteger_publicacion_proyecto();

CREATE FUNCTION banco.proteger_requisitos_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_id bigint; v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  FOR v_id IN SELECT DISTINCT id FROM unnest(ARRAY[
    CASE WHEN TG_OP <> 'INSERT' THEN OLD.proyecto_id END,
    CASE WHEN TG_OP <> 'DELETE' THEN NEW.proyecto_id END]) AS afectados(id)
    WHERE id IS NOT NULL ORDER BY id
  LOOP
    SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_id FOR UPDATE;
    IF FOUND THEN
      IF v_proyecto.revision_publicada_id IS NOT NULL OR v_proyecto.estado='publicado' THEN
        RAISE EXCEPTION 'D-07 pendiente: los requisitos publicados se conservan en su versión autorizada' USING ERRCODE='55000';
      ELSIF v_proyecto.estado NOT IN ('borrador','en_correccion') THEN
        RAISE EXCEPTION 'Los requisitos solo se editan en borrador o corrección' USING ERRCODE='55000';
      END IF;
    END IF;
  END LOOP;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_proyecto_habilidad_publicacion BEFORE INSERT OR UPDATE OR DELETE ON banco.proyecto_habilidad
FOR EACH ROW EXECUTE FUNCTION banco.proteger_requisitos_proyecto();

CREATE FUNCTION banco.proteger_revision_publicada()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF NEW.estado_revision IS DISTINCT FROM OLD.estado_revision
    AND EXISTS (SELECT 1 FROM banco.proyecto WHERE revision_publicada_id=OLD.id) THEN
    RAISE EXCEPTION 'D-07 pendiente: el resultado de la revisión publicada no puede reescribirse' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_revision_publicada BEFORE UPDATE ON banco.revision_proyecto
FOR EACH ROW EXECUTE FUNCTION banco.proteger_revision_publicada();

CREATE FUNCTION banco.enviar_proyecto(p_proyecto bigint,p_autor bigint)
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

CREATE FUNCTION banco.resolver_publicacion(p_revision bigint,p_admin bigint,p_resultado text,p_motivo text)
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
    format('revision=%s;decision=%s;resultado=%s',p_revision,v_decision,p_resultado));
  RETURN v_decision;
END;
$$;

CREATE FUNCTION banco.validar_proyecto_al_asignar()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=NEW.proyecto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_publicacion_valida(v_proyecto);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_asignacion_alumno_publicacion BEFORE INSERT ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.validar_proyecto_al_asignar();
CREATE TRIGGER tr_asignacion_direccion_publicacion BEFORE INSERT ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.validar_proyecto_al_asignar();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON COLUMN banco.proyecto.revision_publicada_id IS 'Versión inicial autorizada, FK compuesta al mismo proyecto. La aprobación y coherencia del contenido se validan antes de publicar/asignar. Edición posterior D-07 pendiente.';
COMMENT ON FUNCTION banco.enviar_proyecto(bigint,bigint) IS 'Función interna del propietario: valida seis campos RF-08 y representante activo; conserva snapshot v1 y auditoría. No API ni permiso de actor autenticado.';
COMMENT ON FUNCTION banco.resolver_publicacion(bigint,bigint,text,text) IS 'Función interna del propietario: resolución inicial atómica con administrador activo, objeto exacto, motivo y auditoría; sin notificaciones D-11 ni inicio automático D-05.';

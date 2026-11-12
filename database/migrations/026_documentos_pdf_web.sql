-- UX-04 / D-11 (12 de noviembre de 2026): PDF de evidencias por habilidad del alumno y currículum
-- de alumno y profesor. El contenido vive fuera de la base, en almacenamiento privado de la aplicación;
-- aquí se registran sus metadatos. El esquema adjunto queda aparte de las 21 entidades del modelo
-- (banco): el archivo es otra representación del atributo evidencia y del perfil académico.
-- Permisos: los mismos de banco.consultar_perfil (D-10). Ampliación aditiva; conservar 001-025.

CREATE SCHEMA adjunto;
REVOKE ALL ON SCHEMA adjunto FROM PUBLIC;
COMMENT ON SCHEMA adjunto IS
  'D-11: metadatos de archivos PDF del perfil. Sin acceso directo para la aplicación; solo mediante gateways banco.web_*.';

CREATE TABLE adjunto.documento (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  titular_usuario_id bigint NOT NULL REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  tipo text NOT NULL CHECK (tipo IN ('curriculum','evidencia')),
  habilidad_id bigint REFERENCES banco.habilidad(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  nombre_original text NOT NULL CHECK (nombre_original ~ '[^[:space:]]' AND length(nombre_original) <= 255),
  ruta text NOT NULL UNIQUE CHECK (ruta ~ '^documentos/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$'),
  tamano_bytes integer NOT NULL CHECK (tamano_bytes BETWEEN 1 AND 5242880),
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  subido timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retirado timestamptz,
  CONSTRAINT ck_documento_tipo_habilidad CHECK (
    (tipo = 'curriculum' AND habilidad_id IS NULL) OR (tipo = 'evidencia' AND habilidad_id IS NOT NULL)),
  CONSTRAINT ck_documento_retiro CHECK (retirado IS NULL OR retirado >= subido)
);
CREATE UNIQUE INDEX ux_documento_curriculum_vigente ON adjunto.documento(titular_usuario_id)
  WHERE tipo = 'curriculum' AND retirado IS NULL;
CREATE INDEX ix_documento_titular_vigente ON adjunto.documento(titular_usuario_id, tipo) WHERE retirado IS NULL;
CREATE INDEX ix_documento_habilidad ON adjunto.documento(habilidad_id);
REVOKE ALL ON adjunto.documento FROM PUBLIC;
COMMENT ON TABLE adjunto.documento IS
  'D-11: un currículum vigente por titular y hasta tres evidencias vigentes por habilidad del alumno. Retirar o reemplazar conserva la fila con fecha de retiro.';

-- Los registros se conservan: solo se permite marcar el retiro una vez.
CREATE FUNCTION adjunto.proteger_documento()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,adjunto AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Los documentos se conservan' USING ERRCODE='55000'; END IF;
  IF (to_jsonb(NEW) - 'retirado') IS DISTINCT FROM (to_jsonb(OLD) - 'retirado')
    OR OLD.retirado IS NOT NULL OR NEW.retirado IS NULL THEN
    RAISE EXCEPTION 'Solo se registra el retiro de un documento vigente' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_documento_conservado BEFORE UPDATE OR DELETE ON adjunto.documento
FOR EACH ROW EXECUTE FUNCTION adjunto.proteger_documento();

CREATE FUNCTION banco.web_documento_json(p_documento adjunto.documento)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,banco,adjunto AS $$
  SELECT jsonb_build_object('id',p_documento.id,'tipo',p_documento.tipo,'habilidad_id',p_documento.habilidad_id,
    'nombre_original',p_documento.nombre_original,'tamano_bytes',p_documento.tamano_bytes,'subido',p_documento.subido);
$$;

CREATE FUNCTION banco.web_registrar_documento(p_actor bigint,p_tipo text,p_habilidad bigint,p_nombre text,
  p_ruta text,p_tamano integer,p_sha256 text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_rol text;v_id bigint;v_anterior bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Serializa los envíos del mismo titular para respetar los máximos de vigentes.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_documento:'||p_actor::text,0));
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_tipo IS NULL OR p_tipo NOT IN ('curriculum','evidencia') THEN
    RAISE EXCEPTION 'Tipo de documento inválido' USING ERRCODE='23514'; END IF;
  IF p_tipo='curriculum' THEN
    IF p_habilidad IS NOT NULL THEN RAISE EXCEPTION 'El currículum no pertenece a una habilidad' USING ERRCODE='23514'; END IF;
    SELECT id INTO v_anterior FROM adjunto.documento
      WHERE titular_usuario_id=p_actor AND tipo='curriculum' AND retirado IS NULL FOR UPDATE;
    IF FOUND THEN UPDATE adjunto.documento SET retirado=clock_timestamp() WHERE id=v_anterior; END IF;
  ELSE
    IF v_rol<>'alumno' OR NOT EXISTS(SELECT 1 FROM banco.alumno_habilidad WHERE alumno_id=p_actor AND habilidad_id=p_habilidad) THEN
      RAISE EXCEPTION 'La evidencia requiere una habilidad registrada en tu perfil' USING ERRCODE='23514'; END IF;
    IF (SELECT count(*) FROM adjunto.documento WHERE titular_usuario_id=p_actor AND tipo='evidencia'
        AND habilidad_id=p_habilidad AND retirado IS NULL) >= 3 THEN
      RAISE EXCEPTION 'Máximo tres evidencias vigentes por habilidad' USING ERRCODE='23514'; END IF;
  END IF;
  INSERT INTO adjunto.documento(titular_usuario_id,tipo,habilidad_id,nombre_original,ruta,tamano_bytes,sha256)
    VALUES(p_actor,p_tipo,p_habilidad,btrim(p_nombre),p_ruta,p_tamano,p_sha256) RETURNING id INTO v_id;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','registrar_documento','documento',v_id::text,'vigente',
      jsonb_build_object('tipo',p_tipo,'habilidad_id',p_habilidad,'reemplaza',v_anterior,'tamano_bytes',p_tamano)::text);
  RETURN v_id;
END;
$$;

CREATE FUNCTION banco.web_retirar_documento(p_actor bigint,p_documento bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_doc adjunto.documento%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM pg_advisory_xact_lock(hashtextextended('web_documento:'||p_actor::text,0));
  PERFORM banco.web_exigir_academico(p_actor);
  SELECT * INTO v_doc FROM adjunto.documento WHERE id=p_documento FOR UPDATE;
  IF NOT FOUND OR v_doc.titular_usuario_id<>p_actor OR v_doc.retirado IS NOT NULL THEN
    RAISE EXCEPTION 'Documento no disponible' USING ERRCODE='23503'; END IF;
  UPDATE adjunto.documento SET retirado=clock_timestamp() WHERE id=p_documento;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','retirar_documento','documento',p_documento::text,'vigente->retirado',
      jsonb_build_object('tipo',v_doc.tipo,'habilidad_id',v_doc.habilidad_id)::text);
END;
$$;

-- Documentos vigentes que el actor puede ver del titular: mismo ámbito que el perfil (D-10).
-- Las evidencias de una habilidad retirada del perfil dejan de mostrarse.
CREATE FUNCTION banco.web_documentos_perfil(p_actor bigint,p_titular bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
BEGIN
  PERFORM banco.consultar_perfil(p_actor,p_titular);
  RETURN coalesce((SELECT jsonb_agg(banco.web_documento_json(d) ORDER BY d.tipo,d.habilidad_id,d.subido)
    FROM adjunto.documento d
    WHERE d.titular_usuario_id=p_titular AND d.retirado IS NULL
      AND (d.tipo='curriculum' OR EXISTS(SELECT 1 FROM banco.alumno_habilidad a
        WHERE a.alumno_id=d.titular_usuario_id AND a.habilidad_id=d.habilidad_id))),'[]'::jsonb);
END;
$$;

-- Datos para la descarga, incluida la ruta privada; solo dentro del mismo ámbito.
CREATE FUNCTION banco.web_abrir_documento(p_actor bigint,p_documento bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_doc adjunto.documento%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM adjunto.documento WHERE id=p_documento;
  IF NOT FOUND OR v_doc.retirado IS NOT NULL OR (v_doc.tipo='evidencia' AND NOT EXISTS(
      SELECT 1 FROM banco.alumno_habilidad a WHERE a.alumno_id=v_doc.titular_usuario_id AND a.habilidad_id=v_doc.habilidad_id)) THEN
    RAISE EXCEPTION 'Documento no disponible' USING ERRCODE='23503'; END IF;
  BEGIN
    PERFORM banco.consultar_perfil(p_actor,v_doc.titular_usuario_id);
  EXCEPTION WHEN check_violation THEN
    -- Sin permiso se responde igual que si no existiera: no revela identificadores válidos.
    RAISE EXCEPTION 'Documento no disponible' USING ERRCODE='23503';
  END;
  RETURN banco.web_documento_json(v_doc)||jsonb_build_object('ruta',v_doc.ruta,'sha256',v_doc.sha256);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA adjunto FROM PUBLIC;
GRANT EXECUTE ON FUNCTION banco.web_registrar_documento(bigint,text,bigint,text,text,integer,text),
  banco.web_retirar_documento(bigint,bigint),banco.web_documentos_perfil(bigint,bigint),
  banco.web_abrir_documento(bigint,bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_registrar_documento(bigint,text,bigint,text,text,integer,text) IS
  'D-11: registra un PDF propio ya almacenado. Currículum reemplaza al vigente; evidencia exige habilidad del perfil y admite tres vigentes. Auditado.';
COMMENT ON FUNCTION banco.web_abrir_documento(bigint,bigint) IS
  'D-11/D-10: metadatos y ruta privada de un documento vigente, solo para quien puede consultar el perfil del titular.';

-- UX-08 (12 de noviembre de 2026): foto de perfil de alumno y profesor, y logo de empresa.
-- Igual que 026, el archivo vive en el almacenamiento privado de la aplicación y aquí solo sus metadatos,
-- en el esquema adjunto, fuera de las 21 entidades del modelo. La aplicación vuelve a codificar cada imagen
-- (cuadrada, sin metadatos) antes de registrarla.
-- Visibilidad: el logo es dato de la empresa y lo ve cualquier cuenta activa; la foto es dato personal y
-- sigue el ámbito de banco.consultar_perfil (D-10). Ampliación aditiva; conservar 001-028.

CREATE TABLE adjunto.imagen (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo text NOT NULL CHECK (tipo IN ('foto','logo')),
  usuario_id bigint REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  empresa_id bigint REFERENCES banco.empresa(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  subido_por bigint NOT NULL REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  ruta text NOT NULL UNIQUE CHECK (ruta ~ '^imagenes/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|png)$'),
  tamano_bytes integer NOT NULL CHECK (tamano_bytes BETWEEN 1 AND 1048576),
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  subido timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retirado timestamptz,
  CONSTRAINT ck_imagen_titular CHECK (
    (tipo = 'foto' AND usuario_id IS NOT NULL AND empresa_id IS NULL) OR (tipo = 'logo' AND empresa_id IS NOT NULL AND usuario_id IS NULL)),
  CONSTRAINT ck_imagen_retiro CHECK (retirado IS NULL OR retirado >= subido)
);
CREATE UNIQUE INDEX ux_imagen_foto_vigente ON adjunto.imagen(usuario_id) WHERE tipo = 'foto' AND retirado IS NULL;
CREATE UNIQUE INDEX ux_imagen_logo_vigente ON adjunto.imagen(empresa_id) WHERE tipo = 'logo' AND retirado IS NULL;
REVOKE ALL ON adjunto.imagen FROM PUBLIC;
COMMENT ON TABLE adjunto.imagen IS
  'UX-08: una foto vigente por alumno o profesor y un logo vigente por empresa. Reemplazar o quitar conserva la fila con fecha de retiro.';
-- Misma regla de conservación que los documentos: solo se registra una vez el retiro.
CREATE TRIGGER tr_imagen_conservada BEFORE UPDATE OR DELETE ON adjunto.imagen
FOR EACH ROW EXECUTE FUNCTION adjunto.proteger_documento();

-- Foto visible para el actor: la propia, la administración o quien puede consultar el perfil (D-10).
CREATE FUNCTION adjunto.puede_ver_foto(p_actor bigint,p_titular bigint)
RETURNS boolean LANGUAGE plpgsql SET search_path=pg_catalog,banco,adjunto AS $$
BEGIN
  IF p_actor=p_titular THEN RETURN true; END IF;
  PERFORM banco.consultar_perfil(p_actor,p_titular);
  RETURN true;
EXCEPTION WHEN check_violation OR foreign_key_violation THEN
  RETURN false;
END;
$$;

CREATE FUNCTION banco.web_registrar_imagen(p_actor bigint,p_tipo text,p_ruta text,p_tamano integer,p_sha256 text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_usuario bigint;v_empresa bigint;v_anterior bigint;v_id bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo IS NULL OR p_tipo NOT IN ('foto','logo') THEN
    RAISE EXCEPTION 'Tipo de imagen inválido' USING ERRCODE='23514'; END IF;
  IF p_tipo='foto' THEN
    PERFORM banco.web_exigir_academico(p_actor);
    v_usuario:=p_actor;
  ELSE
    v_empresa:=banco.web_empresa_del_actor(p_actor);
  END IF;
  -- Serializa los cambios de la misma foto o logo.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_imagen:'||p_tipo||':'||coalesce(v_usuario,v_empresa)::text,0));
  SELECT id INTO v_anterior FROM adjunto.imagen WHERE tipo=p_tipo AND retirado IS NULL
    AND (usuario_id=v_usuario OR empresa_id=v_empresa) FOR UPDATE;
  IF FOUND THEN UPDATE adjunto.imagen SET retirado=clock_timestamp() WHERE id=v_anterior; END IF;
  INSERT INTO adjunto.imagen(tipo,usuario_id,empresa_id,subido_por,ruta,tamano_bytes,sha256)
    VALUES(p_tipo,v_usuario,v_empresa,p_actor,p_ruta,p_tamano,p_sha256) RETURNING id INTO v_id;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','registrar_imagen','imagen',v_id::text,'vigente',
      jsonb_build_object('tipo',p_tipo,'empresa_id',v_empresa,'reemplaza',v_anterior,'tamano_bytes',p_tamano)::text);
  RETURN v_id;
END;
$$;

CREATE FUNCTION banco.web_retirar_imagen(p_actor bigint,p_tipo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_usuario bigint;v_empresa bigint;v_id bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo IS NULL OR p_tipo NOT IN ('foto','logo') THEN
    RAISE EXCEPTION 'Tipo de imagen inválido' USING ERRCODE='23514'; END IF;
  IF p_tipo='foto' THEN PERFORM banco.web_exigir_academico(p_actor); v_usuario:=p_actor;
  ELSE v_empresa:=banco.web_empresa_del_actor(p_actor); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('web_imagen:'||p_tipo||':'||coalesce(v_usuario,v_empresa)::text,0));
  SELECT id INTO v_id FROM adjunto.imagen WHERE tipo=p_tipo AND retirado IS NULL
    AND (usuario_id=v_usuario OR empresa_id=v_empresa) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imagen no disponible' USING ERRCODE='23503'; END IF;
  UPDATE adjunto.imagen SET retirado=clock_timestamp() WHERE id=v_id;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','retirar_imagen','imagen',v_id::text,'vigente->retirado',
      jsonb_build_object('tipo',p_tipo,'empresa_id',v_empresa)::text);
END;
$$;

-- Identificadores de las imágenes vigentes que el actor puede ver, para pintar listas sin consultar una por una.
CREATE FUNCTION banco.web_imagenes(p_actor bigint,p_usuarios bigint[],p_empresas bigint[],p_proyectos bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
BEGIN
  PERFORM banco.web_exigir_avisos(p_actor);
  IF cardinality(coalesce(p_usuarios,'{}'))>100 OR cardinality(coalesce(p_empresas,'{}'))>100 OR cardinality(coalesce(p_proyectos,'{}'))>100 THEN
    RAISE EXCEPTION 'Demasiadas imágenes solicitadas' USING ERRCODE='23514'; END IF;
  RETURN jsonb_build_object(
    'fotos',coalesce((SELECT jsonb_object_agg(i.usuario_id::text,i.id) FROM adjunto.imagen i
      WHERE i.tipo='foto' AND i.retirado IS NULL AND i.usuario_id=ANY(coalesce(p_usuarios,'{}'))
        AND adjunto.puede_ver_foto(p_actor,i.usuario_id)),'{}'::jsonb),
    'logos',coalesce((SELECT jsonb_object_agg(i.empresa_id::text,i.id) FROM adjunto.imagen i
      WHERE i.tipo='logo' AND i.retirado IS NULL AND i.empresa_id=ANY(coalesce(p_empresas,'{}'))),'{}'::jsonb),
    -- El logo es público dentro del sistema; por proyecto evita exponer empresa_id en el catálogo.
    'logos_proyecto',coalesce((SELECT jsonb_object_agg(p.id::text,i.id) FROM banco.proyecto p JOIN adjunto.imagen i
      ON i.empresa_id=p.empresa_id AND i.tipo='logo' AND i.retirado IS NULL WHERE p.id=ANY(coalesce(p_proyectos,'{}'))),'{}'::jsonb));
END;
$$;

-- Ruta privada para entregar la imagen; sin permiso se responde como si no existiera.
CREATE FUNCTION banco.web_abrir_imagen(p_actor bigint,p_imagen bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,adjunto,pg_temp AS $$
DECLARE v_img adjunto.imagen%ROWTYPE;
BEGIN
  PERFORM banco.web_exigir_avisos(p_actor);
  SELECT * INTO v_img FROM adjunto.imagen WHERE id=p_imagen;
  IF NOT FOUND OR v_img.retirado IS NOT NULL OR (v_img.tipo='foto' AND NOT adjunto.puede_ver_foto(p_actor,v_img.usuario_id)) THEN
    RAISE EXCEPTION 'Imagen no disponible' USING ERRCODE='23503'; END IF;
  RETURN jsonb_build_object('id',v_img.id,'tipo',v_img.tipo,'ruta',v_img.ruta,'sha256',v_img.sha256,'subido',v_img.subido);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA adjunto FROM PUBLIC;
GRANT EXECUTE ON FUNCTION banco.web_registrar_imagen(bigint,text,text,integer,text),banco.web_retirar_imagen(bigint,text),
  banco.web_imagenes(bigint,bigint[],bigint[],bigint[]),banco.web_abrir_imagen(bigint,bigint) TO banco_web;
COMMENT ON FUNCTION banco.web_registrar_imagen(bigint,text,text,integer,text) IS
  'UX-08: registra la foto propia (alumno/profesor) o el logo de la empresa representada, reemplazando la vigente. Auditado.';
COMMENT ON FUNCTION banco.web_imagenes(bigint,bigint[],bigint[],bigint[]) IS
  'UX-08: ids de fotos visibles para el actor (D-10) y de logos vigentes por empresa o por proyecto, hasta 100 de cada lista.';
COMMENT ON FUNCTION banco.web_abrir_imagen(bigint,bigint) IS
  'UX-08: ruta privada de una imagen vigente; foto solo dentro del ámbito de consultar_perfil, logo para cualquier cuenta activa.';

-- WEB-02: sesión y administración de cuentas mediante gateways concretos.
-- Los IDs de actor provienen de la sesión Laravel. La credencial de servidor
-- puede ejecutar estas funciones; SQL no autentica por sí mismo esos IDs.
-- Evolución hacia delante: no crea accesos válidos para las cuentas de demo.
ALTER TABLE banco.usuario ADD COLUMN version_acceso bigint NOT NULL DEFAULT 1
  CONSTRAINT ck_usuario_version_acceso CHECK(version_acceso>0);
ALTER TABLE banco.usuario ADD COLUMN requiere_cambio_clave boolean NOT NULL DEFAULT false;

CREATE FUNCTION banco.actualizar_version_acceso()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  IF ROW(NEW.nombre,NEW.hash_contrasena,NEW.estado_cuenta,NEW.correo_normalizado,
      NEW.rol_principal,NEW.requiere_cambio_clave) IS DISTINCT FROM
    ROW(OLD.nombre,OLD.hash_contrasena,OLD.estado_cuenta,OLD.correo_normalizado,
      OLD.rol_principal,OLD.requiere_cambio_clave) THEN
    NEW.version_acceso:=OLD.version_acceso+1;
  ELSE NEW.version_acceso:=OLD.version_acceso;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_000_usuario_version_acceso BEFORE UPDATE ON banco.usuario
FOR EACH ROW EXECUTE FUNCTION banco.actualizar_version_acceso();

CREATE FUNCTION banco.web_validar_hash(p_hash text)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  IF p_hash IS NULL OR p_hash !~ '^\$2y\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}$' THEN
    RAISE EXCEPTION 'La operación web requiere un hash bcrypt generado por el servidor'
      USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE FUNCTION banco.web_bloquear_cuenta(p_usuario bigint,p_version bigint)
RETURNS banco.usuario LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM pg_advisory_xact_lock(7162026,2017);
  SELECT empresa_id INTO v_empresa FROM banco.representacion_empresa WHERE usuario_id=p_usuario;
  IF v_empresa IS NOT NULL THEN
    PERFORM id FROM banco.empresa WHERE id=v_empresa FOR UPDATE;
  END IF;
  SELECT * INTO v_usuario FROM banco.usuario WHERE id=p_usuario FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cuenta inexistente' USING ERRCODE='23503'; END IF;
  IF v_usuario.version_acceso IS DISTINCT FROM p_version THEN
    RAISE EXCEPTION 'La cuenta cambió; vuelve a consultar sus datos' USING ERRCODE='40001';
  END IF;
  RETURN v_usuario;
END;
$$;

CREATE FUNCTION banco.web_datos_cuenta(p_usuario bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT jsonb_build_object('id',u.id,'nombre',u.nombre,
    'correo_normalizado',u.correo_normalizado,'rol_principal',u.rol_principal,
    'estado_cuenta',u.estado_cuenta,'fecha_alta',u.fecha_alta,
    'version_acceso',u.version_acceso,'requiere_cambio_clave',u.requiere_cambio_clave,
    'empresa_id',r.empresa_id,'razon_social',e.razon_social,
    'representante_vigente',coalesce(r.vigente,false))
  FROM banco.usuario u LEFT JOIN banco.representacion_empresa r ON r.usuario_id=u.id
    LEFT JOIN banco.empresa e ON e.id=r.empresa_id WHERE u.id=p_usuario;
$$;

CREATE FUNCTION banco.web_buscar_acceso_correo(p_correo text)
RETURNS TABLE(id bigint,nombre text,correo_normalizado text,hash_contrasena text,
  rol_principal text,estado_cuenta text,fecha_alta timestamptz,
  version_acceso bigint,requiere_cambio_clave boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT u.id,u.nombre,u.correo_normalizado,u.hash_contrasena,u.rol_principal,
    u.estado_cuenta,u.fecha_alta,u.version_acceso,u.requiere_cambio_clave
  FROM banco.usuario u WHERE u.correo_normalizado=lower(btrim(p_correo));
$$;
CREATE FUNCTION banco.web_buscar_acceso_id(p_usuario bigint)
RETURNS TABLE(id bigint,nombre text,correo_normalizado text,hash_contrasena text,
  rol_principal text,estado_cuenta text,fecha_alta timestamptz,
  version_acceso bigint,requiere_cambio_clave boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
  SELECT u.id,u.nombre,u.correo_normalizado,u.hash_contrasena,u.rol_principal,
    u.estado_cuenta,u.fecha_alta,u.version_acceso,u.requiere_cambio_clave
  FROM banco.usuario u WHERE u.id=p_usuario;
$$;

CREATE FUNCTION banco.web_listar_cuentas(p_admin bigint,p_busqueda text,p_rol text,
  p_estado text,p_limite integer,p_desplazamiento integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
BEGIN
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 OR p_desplazamiento IS NULL
    OR p_desplazamiento<0 OR (p_rol IS NOT NULL AND p_rol<>'' AND
      p_rol NOT IN ('alumno','profesor','administrador','empresa'))
    OR (p_estado IS NOT NULL AND p_estado<>'' AND p_estado NOT IN ('activa','inactiva')) THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514';
  END IF;
  RETURN (WITH filtradas AS MATERIALIZED (
    SELECT u.id FROM banco.usuario u
    WHERE (nullif(p_rol,'') IS NULL OR u.rol_principal=p_rol)
      AND (nullif(p_estado,'') IS NULL OR u.estado_cuenta=p_estado)
      AND (nullif(btrim(p_busqueda),'') IS NULL OR
        strpos(lower(u.nombre || ' ' || u.correo_normalizado),lower(btrim(p_busqueda)))>0)
  ), pagina AS (SELECT id FROM filtradas ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('total',(SELECT count(*) FROM filtradas),
    'datos',coalesce((SELECT jsonb_agg(banco.web_datos_cuenta(id) ORDER BY id DESC) FROM pagina),'[]'::jsonb)));
END;
$$;

CREATE FUNCTION banco.web_obtener_cuenta(p_admin bigint,p_usuario bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_datos jsonb;
BEGIN
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  v_datos:=banco.web_datos_cuenta(p_usuario);
  IF v_datos IS NULL THEN RAISE EXCEPTION 'Cuenta inexistente' USING ERRCODE='23503'; END IF;
  RETURN v_datos;
END;
$$;

CREATE FUNCTION banco.web_crear_cuenta(p_admin bigint,p_nombre text,p_correo text,
  p_hash text,p_rol text,p_razon_social text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(7162026,2017);
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  PERFORM banco.web_validar_hash(p_hash);
  IF p_rol='empresa' THEN
    SELECT usuario_id INTO v_usuario FROM banco.crear_empresa_con_representante(
      p_admin,p_nombre,p_correo,p_hash,p_razon_social);
  ELSE
    IF nullif(btrim(p_razon_social),'') IS NOT NULL THEN
      RAISE EXCEPTION 'La razón social corresponde solo al alta empresarial' USING ERRCODE='23514';
    END IF;
    v_usuario:=banco.crear_cuenta(p_admin,p_nombre,p_correo,p_hash,p_rol);
  END IF;
  UPDATE banco.usuario SET requiere_cambio_clave=true WHERE id=v_usuario;
  RETURN v_usuario;
END;
$$;

CREATE FUNCTION banco.web_auditar_cambio(p_actor bigint,p_usuario bigint,p_operacion text,p_motivo text)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_evento bigint;
BEGIN
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,
    entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario',p_operacion,'usuario',p_usuario::text,
    jsonb_build_object('motivo',p_motivo,'version_acceso',
      (SELECT version_acceso FROM banco.usuario WHERE id=p_usuario))::text)
  RETURNING id INTO v_evento;
  -- Estos eventos nuevos no pertenecen al allowlist histórico de 018.
  INSERT INTO banco.notificacion(destinatario_usuario_id,evento_id,mensaje)
  SELECT p_usuario,v_evento,'Se actualizaron los datos de acceso de tu cuenta.'
  FROM banco.usuario WHERE id=p_usuario AND estado_cuenta='activa';
END;
$$;

CREATE FUNCTION banco.web_editar_cuenta(p_admin bigint,p_usuario bigint,p_nombre text,
  p_correo text,p_motivo text,p_version bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_usuario,p_version);
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF p_nombre IS NULL OR p_nombre !~ '[^[:space:]]' OR p_correo IS NULL
    OR p_correo !~ '[^[:space:]]' OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Nombre, correo y motivo son obligatorios' USING ERRCODE='23514';
  END IF;
  UPDATE banco.usuario SET nombre=p_nombre,correo_normalizado=lower(btrim(p_correo)) WHERE id=p_usuario;
  PERFORM banco.web_auditar_cambio(p_admin,p_usuario,'editar_cuenta',p_motivo);
END;
$$;

CREATE FUNCTION banco.web_estado_cuenta(p_admin bigint,p_usuario bigint,p_estado text,
  p_motivo text,p_version bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_usuario,p_version);
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  RETURN banco.cambiar_estado_cuenta(p_admin,p_usuario,p_estado,p_motivo);
END;
$$;

CREATE FUNCTION banco.web_relevar_representante(p_admin bigint,p_empresa bigint,
  p_nombre text,p_correo text,p_hash text,p_motivo text,p_representante_esperado bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario bigint;v_anterior bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM pg_advisory_xact_lock(7162026,2017);
  PERFORM id FROM banco.empresa WHERE id=p_empresa FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empresa inexistente' USING ERRCODE='23503'; END IF;
  SELECT usuario_id INTO v_anterior FROM banco.representacion_empresa WHERE empresa_id=p_empresa AND vigente;
  IF v_anterior IS DISTINCT FROM p_representante_esperado OR p_representante_esperado IS NULL THEN
    RAISE EXCEPTION 'El representante cambió; vuelve a consultar la empresa' USING ERRCODE='40001'; END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  PERFORM banco.web_validar_hash(p_hash);
  v_usuario:=banco.relevar_representante(p_admin,p_empresa,p_nombre,p_correo,p_hash,p_motivo);
  UPDATE banco.usuario SET requiere_cambio_clave=true WHERE id=v_usuario;
  RETURN v_usuario;
END;
$$;

CREATE FUNCTION banco.web_restablecer_clave(p_admin bigint,p_usuario bigint,p_hash text,
  p_motivo text,p_version bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_usuario,p_version);
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  PERFORM banco.web_validar_hash(p_hash);
  IF p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El restablecimiento requiere motivo' USING ERRCODE='23514'; END IF;
  UPDATE banco.usuario SET hash_contrasena=p_hash,requiere_cambio_clave=true WHERE id=p_usuario;
  PERFORM banco.web_auditar_cambio(p_admin,p_usuario,'restablecer_clave',p_motivo);
END;
$$;

CREATE FUNCTION banco.web_cambiar_clave(p_actor bigint,p_hash text,p_version bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_actor,p_version);
  PERFORM banco.exigir_rol(p_actor,v_usuario.rol_principal,true);
  PERFORM banco.web_validar_hash(p_hash);
  UPDATE banco.usuario SET hash_contrasena=p_hash,requiere_cambio_clave=false WHERE id=p_actor;
  PERFORM banco.web_auditar_cambio(p_actor,p_actor,'cambiar_clave','Cambio de clave por su titular');
END;
$$;

CREATE FUNCTION banco.web_registrar_acceso(p_actor bigint,p_version bigint,p_operacion text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,banco,pg_temp AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_operacion IS NULL OR p_operacion NOT IN ('inicio_sesion','cierre_sesion') THEN
    RAISE EXCEPTION 'Operación de sesión inválida' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_usuario FROM banco.usuario WHERE id=p_actor FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cuenta inexistente' USING ERRCODE='23503'; END IF;
  IF v_usuario.version_acceso IS DISTINCT FROM p_version THEN
    RAISE EXCEPTION 'La versión de acceso cambió' USING ERRCODE='40001'; END IF;
  PERFORM banco.exigir_rol(p_actor,v_usuario.rol_principal,true);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,
    entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario',p_operacion,'usuario',p_actor::text,
    jsonb_build_object('version_acceso',p_version)::text);
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT EXECUTE ON FUNCTION banco.web_buscar_acceso_correo(text),banco.web_buscar_acceso_id(bigint),
  banco.web_listar_cuentas(bigint,text,text,text,integer,integer),banco.web_obtener_cuenta(bigint,bigint),
  banco.web_crear_cuenta(bigint,text,text,text,text,text),
  banco.web_editar_cuenta(bigint,bigint,text,text,text,bigint),
  banco.web_estado_cuenta(bigint,bigint,text,text,bigint),
  banco.web_relevar_representante(bigint,bigint,text,text,text,text,bigint),
  banco.web_restablecer_clave(bigint,bigint,text,text,bigint),
  banco.web_cambiar_clave(bigint,text,bigint),
  banco.web_registrar_acceso(bigint,bigint,text) TO banco_web;
COMMENT ON COLUMN banco.usuario.version_acceso IS
  'WEB-02: versión monotónica calculada al cambiar nombre, hash, correo, rol, estado o requerimiento de clave; protege formularios CAS e invalida sesiones anteriores en Laravel.';
COMMENT ON COLUMN banco.usuario.requiere_cambio_clave IS
  'WEB-02: las altas/restablecimientos web requieren cambio inicial por el titular; no convierte semillas sin acceso en credenciales válidas.';
COMMENT ON FUNCTION banco.web_buscar_acceso_correo(text) IS
  'Gateway de autenticación de la credencial de servidor Laravel. Devuelve el hash de una sola cuenta para verificarlo en servidor; no es una consulta pública ni autentica IDs de actor.';

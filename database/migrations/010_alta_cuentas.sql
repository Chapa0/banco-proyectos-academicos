-- RF-02/RF-03/RF-06 y D-09: alta administrativa inicial con auditoría atómica.
-- No decide relevo, desactivación o visibilidad (D-10), ni entrega de claves o
-- avisos (D-11). INVOKER del propietario; el ID recibido no autentica a nadie.
-- p_hash es un valor opaco producido fuera de SQL. Comprobar que no esté vacío
-- no acredita algoritmo, coste, contraseña válida ni autenticación RNF-01.

CREATE FUNCTION banco.crear_cuenta(p_admin bigint,p_nombre text,p_correo text,p_hash text,p_rol text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_usuario bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF p_rol IS NULL OR p_rol NOT IN ('alumno','profesor','administrador') THEN
    RAISE EXCEPTION 'RF-03/D-09: indicar alumno, profesor o administrador; el alta empresarial requiere crear su empresa y representante juntos'
      USING ERRCODE='23514';
  END IF;
  IF p_nombre IS NULL OR p_nombre !~ '[^[:space:]]'
    OR p_correo IS NULL OR p_correo !~ '[^[:space:]]'
    OR p_hash IS NULL OR p_hash !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El alta requiere nombre, correo y hash no vacíos' USING ERRCODE='23514';
  END IF;
  INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal)
  VALUES(p_nombre,lower(btrim(p_correo)),p_hash,p_rol) RETURNING id INTO v_usuario;
  -- La cuenta precede al perfil que completará su titular; no se inventan
  -- matrícula, número de empleado ni otros datos académicos obligatorios.
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','crear_cuenta','usuario',v_usuario::text,
    'sin cuenta -> activa',jsonb_build_object('rol',p_rol)::text);
  RETURN v_usuario;
END;
$$;

CREATE FUNCTION banco.crear_empresa_con_representante(p_admin bigint,p_nombre text,p_correo text,p_hash text,p_razon_social text)
RETURNS TABLE(usuario_id bigint,empresa_id bigint)
LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_usuario bigint; v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF p_nombre IS NULL OR p_nombre !~ '[^[:space:]]'
    OR p_correo IS NULL OR p_correo !~ '[^[:space:]]'
    OR p_hash IS NULL OR p_hash !~ '[^[:space:]]'
    OR p_razon_social IS NULL OR p_razon_social !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El alta empresarial requiere nombre, correo, hash y razón social no vacíos'
      USING ERRCODE='23514';
  END IF;
  INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal)
  VALUES(p_nombre,lower(btrim(p_correo)),p_hash,'empresa') RETURNING id INTO v_usuario;
  INSERT INTO banco.empresa(razon_social) VALUES(p_razon_social) RETURNING id INTO v_empresa;
  INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(v_usuario,v_empresa);
  -- Los datos de identificación/contacto siguen siendo opcionales y los
  -- completará la empresa conforme a RF-07. No se registra el hash en el evento.
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','crear_empresa_con_representante','empresa',v_empresa::text,
    'sin empresa -> representante vigente',jsonb_build_object('representante_usuario_id',v_usuario)::text);
  RETURN QUERY SELECT v_usuario,v_empresa;
END;
$$;

REVOKE ALL ON FUNCTION banco.crear_cuenta(bigint,text,text,text,text)
  FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON FUNCTION banco.crear_empresa_con_representante(bigint,text,text,text,text)
  FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.crear_cuenta(bigint,text,text,text,text) IS
  'Alta interna RF-02/D-09: administrador activo, correo normalizado, rol no empresarial y auditoría atómica. No exige perfil académico inicial ni valida la autenticación o el algoritmo del hash opaco recibido.';
COMMENT ON FUNCTION banco.crear_empresa_con_representante(bigint,text,text,text,text) IS
  'Alta inicial interna D-09: administrador activo, cuenta empresarial, empresa, representante y auditoría en una transacción. Sin relevo D-10, entrega de claves, avisos ni autenticación del ID suministrado.';

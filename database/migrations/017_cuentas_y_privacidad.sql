-- D-10, primera versión por delegación del usuario: conservación, relevo y
-- lectura de perfiles por relación real. Operaciones internas INVOKER del
-- propietario; los identificadores recibidos no autentican al solicitante.
-- Migración hacia delante: no modifica cuentas ni representaciones existentes.

CREATE FUNCTION banco.cambiar_estado_cuenta(p_admin bigint,p_usuario bigint,p_estado text,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;v_empresa bigint;v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_estado IS NULL OR p_estado NOT IN ('activa','inactiva') OR p_motivo IS NULL
    OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Indicar estado de cuenta y motivo no blanco' USING ERRCODE='23514';
  END IF;
  -- Las operaciones administrativas de cuentas se serializan entre sí antes
  -- de retener usuarios. Evita retirar simultáneamente los últimos dos admins.
  PERFORM pg_advisory_xact_lock(7162026,2017);
  SELECT empresa_id INTO v_empresa FROM banco.representacion_empresa WHERE usuario_id=p_usuario;
  -- La representación y las autorías existentes siguen empresa -> usuario.
  IF v_empresa IS NOT NULL THEN
    PERFORM id FROM banco.empresa WHERE id=v_empresa FOR UPDATE;
  END IF;
  -- No se retiene al administrador en modo exclusivo mientras se espera al
  -- titular: una autorización puede retener el titular y validar ese admin.
  -- El mutex ya excluye cambios cruzados entre estas operaciones de cuentas.
  PERFORM id FROM banco.usuario WHERE id=p_usuario FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  SELECT * INTO v_usuario FROM banco.usuario WHERE id=p_usuario;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cuenta inexistente' USING ERRCODE='23503'; END IF;
  IF v_usuario.estado_cuenta=p_estado THEN
    RAISE EXCEPTION 'La cuenta ya tiene ese estado' USING ERRCODE='55000';
  END IF;
  IF p_estado='inactiva' AND EXISTS(SELECT 1 FROM banco.representacion_empresa
    WHERE usuario_id=p_usuario AND vigente) THEN
    RAISE EXCEPTION 'El representante vigente requiere relevo atómico antes de desactivarse'
      USING ERRCODE='23514';
  END IF;
  IF p_estado='inactiva' AND v_usuario.rol_principal='administrador'
    AND (SELECT count(*) FROM banco.usuario
      WHERE rol_principal='administrador' AND estado_cuenta='activa')<=1 THEN
    RAISE EXCEPTION 'Debe conservarse al menos un administrador activo' USING ERRCODE='23514';
  END IF;
  UPDATE banco.usuario SET estado_cuenta=p_estado WHERE id=p_usuario;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','cambiar_estado_cuenta','usuario',p_usuario::text,
    v_usuario.estado_cuenta || ' -> ' || p_estado,
    jsonb_build_object('estado_anterior',v_usuario.estado_cuenta,
      'estado_nuevo',p_estado,'motivo',p_motivo,'participaciones_conservadas',true)::text)
  RETURNING id INTO v_evento;
  -- No se tocan candidaturas, asignaciones, acompañamientos ni sus cargas.
  RETURN v_evento;
END;
$$;

CREATE FUNCTION banco.relevar_representante(p_admin bigint,p_empresa bigint,p_nombre text,
  p_correo text,p_hash text,p_motivo text)
RETURNS bigint LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_anterior bigint;v_nuevo bigint;v_fecha timestamptz;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_nombre IS NULL OR p_nombre !~ '[^[:space:]]' OR p_correo IS NULL
    OR p_correo !~ '[^[:space:]]' OR p_hash IS NULL OR p_hash !~ '[^[:space:]]'
    OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El relevo requiere nombre, correo, hash y motivo no blancos' USING ERRCODE='23514';
  END IF;
  PERFORM pg_advisory_xact_lock(7162026,2017);
  PERFORM id FROM banco.empresa WHERE id=p_empresa FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empresa inexistente' USING ERRCODE='23503'; END IF;
  SELECT usuario_id INTO v_anterior FROM banco.representacion_empresa WHERE empresa_id=p_empresa AND vigente;
  IF NOT FOUND THEN RAISE EXCEPTION 'La empresa no tiene representante vigente' USING ERRCODE='23514'; END IF;
  PERFORM id FROM banco.usuario WHERE id=v_anterior FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  PERFORM banco.exigir_rol(v_anterior,'empresa',true);
  INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal)
    VALUES(p_nombre,lower(btrim(p_correo)),p_hash,'empresa') RETURNING id INTO v_nuevo;
  v_fecha:=clock_timestamp();
  UPDATE banco.representacion_empresa SET vigente=false,fecha_fin=v_fecha WHERE usuario_id=v_anterior;
  UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=v_anterior;
  INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,fecha_vinculacion)
    VALUES(v_nuevo,p_empresa,v_fecha);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','relevar_representante','empresa',p_empresa::text,
    'representante anterior -> nuevo representante',
    jsonb_build_object('representante_anterior_id',v_anterior,
      'representante_nuevo_id',v_nuevo,'motivo',p_motivo)::text);
  -- La cuenta anterior mantiene su empresa original y la autoría histórica.
  -- El hash opaco y el correo de acceso no se copian al evento.
  RETURN v_nuevo;
END;
$$;

CREATE FUNCTION banco.consultar_perfil(p_actor bigint,p_titular bigint)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
DECLARE v_actor banco.usuario%ROWTYPE;v_titular banco.usuario%ROWTYPE;
  v_privado boolean;v_permitido boolean;v_perfil jsonb;v_habilidades jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_actor FROM banco.usuario WHERE id=p_actor;
  IF NOT FOUND THEN RAISE EXCEPTION 'Actor inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_actor,v_actor.rol_principal,true);
  SELECT * INTO v_titular FROM banco.usuario WHERE id=p_titular;
  IF NOT FOUND THEN RAISE EXCEPTION 'Titular inexistente' USING ERRCODE='23503'; END IF;
  v_privado:=p_actor=p_titular OR v_actor.rol_principal='administrador';
  v_permitido:=v_privado;
  IF NOT v_privado AND v_titular.rol_principal='alumno' THEN
    IF v_actor.rol_principal='empresa' THEN
      SELECT EXISTS(SELECT 1 FROM banco.representacion_empresa r
        JOIN banco.proyecto p ON p.empresa_id=r.empresa_id
        JOIN banco.candidatura c ON c.proyecto_id=p.id
        WHERE r.usuario_id=p_actor AND r.vigente AND c.alumno_id=p_titular) INTO v_permitido;
    ELSIF v_actor.rol_principal='profesor' THEN
      SELECT EXISTS(SELECT 1 FROM banco.asignacion_direccion d
        JOIN banco.asignacion_alumno a ON a.proyecto_id=d.proyecto_id
        WHERE d.profesor_id=p_actor AND d.estado='vigente'
          AND a.alumno_id=p_titular AND a.estado='vigente') INTO v_permitido;
    END IF;
  END IF;
  IF NOT v_permitido THEN
    RAISE EXCEPTION 'D-10: el perfil queda fuera del ámbito autorizado' USING ERRCODE='23514';
  END IF;
  IF v_titular.rol_principal='alumno' THEN
    SELECT jsonb_build_object('carrera',a.carrera,'semestre',a.semestre,
      'datos_academicos',a.datos_academicos,'contacto_correo',a.contacto_correo,
      'contacto_telefono',a.contacto_telefono)
      || CASE WHEN v_privado THEN jsonb_build_object('matricula',a.matricula) ELSE '{}'::jsonb END
      INTO v_perfil FROM banco.alumno a WHERE a.usuario_id=p_titular;
    SELECT coalesce(jsonb_agg(jsonb_build_object('habilidad_id',h.id,'nombre',h.nombre,
      'tipo',h.tipo,'nivel_dominio',a.nivel_dominio,'descripcion',a.descripcion,
      'evidencia',a.evidencia) ORDER BY h.id),'[]'::jsonb) INTO v_habilidades
      FROM banco.alumno_habilidad a JOIN banco.habilidad h ON h.id=a.habilidad_id WHERE a.alumno_id=p_titular;
  ELSIF v_titular.rol_principal='profesor' THEN
    SELECT jsonb_build_object('especialidad',p.especialidad,'experiencia',p.experiencia,
      'contacto_correo',p.contacto_correo,'contacto_telefono',p.contacto_telefono,
      'numero_empleado',p.numero_empleado) INTO v_perfil FROM banco.profesor p WHERE p.usuario_id=p_titular;
  END IF;
  -- Lista explícita: ningún campo futuro de Usuario queda expuesto por defecto.
  RETURN jsonb_build_object('usuario_id',p_titular,'nombre',v_titular.nombre,
    'rol',v_titular.rol_principal,'perfil',v_perfil,'habilidades',coalesce(v_habilidades,'[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION banco.cambiar_estado_cuenta(bigint,bigint,text,text),
  banco.relevar_representante(bigint,bigint,text,text,text,text),
  banco.consultar_perfil(bigint,bigint) FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.cambiar_estado_cuenta(bigint,bigint,text,text) IS
  'D-10: cambio administrativo auditado sin liberar cargas. Conserva un administrador activo y exige relevo del representante vigente; controles del servicio interno, no autenticación ni grants de aplicación.';
COMMENT ON FUNCTION banco.relevar_representante(bigint,bigint,text,text,text,text) IS
  'D-09/D-10: nueva cuenta empresarial y relevo atómico con historia, cuenta anterior inactiva y vínculo permanente conservado. Hash recibido opaco; sin entrega de claves ni autenticación.';
COMMENT ON FUNCTION banco.consultar_perfil(bigint,bigint) IS
  'D-10: perfil propio/admin o perfil académico de postulante de empresa vigente y alumno de dirección vigente. Whitelist sin hash/correo de acceso; matrícula y empleado solo titular/admin. No autentica los IDs.';

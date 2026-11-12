-- BD-01. Invariantes independientes de políticas pendientes; sin workflows/APIs.
-- Las validaciones de actor acreditan coherencia histórica de los datos, no la
-- autenticación de una persona. Solo el propietario migra/prepara datos ahora.

-- Contrato técnico del protocolo de bloqueos ya descrito en arquitectura.
-- Un snapshot de REPEATABLE READ puede ocultar un hijo insertado antes de
-- adquirir el bloqueo del padre. No se permiten esas escrituras: las lecturas
-- independientes pueden usar otros aislamientos.
CREATE FUNCTION banco.exigir_aislamiento()
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Las escrituras con integridad cruzada requieren aislamiento READ COMMITTED'
      USING ERRCODE='25001';
  END IF;
END;
$$;

CREATE FUNCTION banco.exigir_rol(p_usuario bigint, p_rol text, p_activo boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_rol text; v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- FOR SHARE serializa validaciones con cambios concurrentes de rol/estado.
  SELECT rol_principal,estado_cuenta INTO v_rol,v_estado
  FROM banco.usuario WHERE id=p_usuario FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario % inexistente', p_usuario USING ERRCODE='23503';
  END IF;
  IF v_rol <> p_rol OR (p_activo AND v_estado <> 'activa') THEN
    RAISE EXCEPTION 'El usuario % requiere rol % y cuenta activa=%', p_usuario,p_rol,p_activo
      USING ERRCODE='23514';
  END IF;
END;
$$;

CREATE FUNCTION banco.validar_perfil_rol()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  PERFORM banco.exigir_rol(NEW.usuario_id,TG_ARGV[0]);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_alumno_rol BEFORE INSERT OR UPDATE ON banco.alumno
FOR EACH ROW EXECUTE FUNCTION banco.validar_perfil_rol('alumno');
CREATE TRIGGER tr_profesor_rol BEFORE INSERT OR UPDATE ON banco.profesor
FOR EACH ROW EXECUTE FUNCTION banco.validar_perfil_rol('profesor');

CREATE FUNCTION banco.validar_usuario_dependencias()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF (NEW.rol_principal <> 'alumno' AND EXISTS (SELECT 1 FROM banco.alumno WHERE usuario_id=OLD.id))
    OR (NEW.rol_principal <> 'profesor' AND EXISTS (SELECT 1 FROM banco.profesor WHERE usuario_id=OLD.id))
    OR (NEW.rol_principal <> 'empresa' AND EXISTS (SELECT 1 FROM banco.representacion_empresa WHERE usuario_id=OLD.id)) THEN
    RAISE EXCEPTION 'El rol del usuario % contradice su perfil o representación', OLD.id USING ERRCODE='23514';
  END IF;
  -- La cuenta puede quedar inactiva solo si el estado final respeta D-09.
  -- Autorías y decisiones antiguas no exigen que el actor siga activo.
  PERFORM e.id FROM banco.empresa e
    JOIN banco.representacion_empresa r ON r.empresa_id=e.id
    WHERE r.usuario_id=OLD.id ORDER BY e.id FOR UPDATE OF e;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_usuario_dependencias BEFORE UPDATE ON banco.usuario
FOR EACH ROW EXECUTE FUNCTION banco.validar_usuario_dependencias();

CREATE FUNCTION banco.validar_representacion()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  IF TG_OP='UPDATE' AND
    (NEW.usuario_id IS DISTINCT FROM OLD.usuario_id OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id) THEN
    RAISE EXCEPTION 'El vínculo de cuenta y empresa es permanente; no se traslada' USING ERRCODE='23514';
  END IF;
  PERFORM id FROM banco.empresa WHERE id=NEW.empresa_id FOR UPDATE;
  PERFORM banco.exigir_rol(NEW.usuario_id,'empresa',NEW.vigente);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_representacion_validar BEFORE INSERT OR UPDATE ON banco.representacion_empresa
FOR EACH ROW EXECUTE FUNCTION banco.validar_representacion();

CREATE FUNCTION banco.comprobar_representante_empresa(p_empresa bigint)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_total bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- La lectura de conteo es una sentencia posterior al bloqueo. Bajo READ
  -- COMMITTED ve los cambios confirmados por el anterior tenedor del bloqueo.
  PERFORM id FROM banco.empresa WHERE id=p_empresa FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT count(*) INTO v_total
  FROM banco.representacion_empresa r JOIN banco.usuario u ON u.id=r.usuario_id
  WHERE r.empresa_id=p_empresa AND r.vigente AND u.estado_cuenta='activa' AND u.rol_principal='empresa';
  IF v_total <> 1 THEN
    RAISE EXCEPTION 'D-09: empresa % requiere exactamente un representante vigente con cuenta activa; tiene %',p_empresa,v_total
      USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION banco.comprobar_representacion_diferida()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_empresa bigint;
BEGIN
  IF TG_TABLE_NAME='empresa' THEN
    IF TG_OP <> 'DELETE' THEN PERFORM banco.comprobar_representante_empresa(NEW.id); END IF;
  ELSIF TG_TABLE_NAME='representacion_empresa' THEN
    IF TG_OP <> 'INSERT' THEN PERFORM banco.comprobar_representante_empresa(OLD.empresa_id); END IF;
    IF TG_OP <> 'DELETE' THEN PERFORM banco.comprobar_representante_empresa(NEW.empresa_id); END IF;
  ELSE
    FOR v_empresa IN SELECT empresa_id FROM banco.representacion_empresa
      WHERE usuario_id=OLD.id ORDER BY empresa_id
    LOOP PERFORM banco.comprobar_representante_empresa(v_empresa); END LOOP;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_empresa_representante
AFTER INSERT OR UPDATE ON banco.empresa DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();
CREATE CONSTRAINT TRIGGER ct_representacion_exacta
AFTER INSERT OR UPDATE OR DELETE ON banco.representacion_empresa DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();
CREATE CONSTRAINT TRIGGER ct_usuario_representacion
AFTER UPDATE OR DELETE ON banco.usuario DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();

CREATE FUNCTION banco.exigir_representante(p_usuario bigint,p_empresa bigint)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  PERFORM id FROM banco.empresa WHERE id=p_empresa FOR UPDATE;
  PERFORM banco.exigir_rol(p_usuario,'empresa',true);
  IF NOT EXISTS (SELECT 1 FROM banco.representacion_empresa
    WHERE empresa_id=p_empresa AND usuario_id=p_usuario AND vigente) THEN
    RAISE EXCEPTION 'El usuario % no representa actualmente a la empresa %',p_usuario,p_empresa USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION banco.validar_autoria_proyecto()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    PERFORM banco.exigir_representante(NEW.autor_usuario_id,NEW.empresa_id);
  ELSIF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id OR NEW.autor_usuario_id IS DISTINCT FROM OLD.autor_usuario_id THEN
    RAISE EXCEPTION 'La propiedad y autoría históricas del proyecto son inmutables' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_proyecto_autoria BEFORE INSERT OR UPDATE ON banco.proyecto
FOR EACH ROW EXECUTE FUNCTION banco.validar_autoria_proyecto();
CREATE FUNCTION banco.validar_revision()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_empresa bigint;
BEGIN
  IF TG_OP='INSERT' THEN
    SELECT empresa_id INTO v_empresa FROM banco.proyecto WHERE id=NEW.proyecto_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
    PERFORM banco.exigir_representante(NEW.autor_usuario_id,v_empresa);
  ELSIF NEW.id IS DISTINCT FROM OLD.id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id
    OR NEW.autor_usuario_id IS DISTINCT FROM OLD.autor_usuario_id OR NEW.numero IS DISTINCT FROM OLD.numero
    OR NEW.fecha_envio IS DISTINCT FROM OLD.fecha_envio OR NEW.instantanea_contenido IS DISTINCT FROM OLD.instantanea_contenido THEN
    RAISE EXCEPTION 'La instantánea enviada y su identidad son inmutables' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_revision_validar BEFORE INSERT OR UPDATE ON banco.revision_proyecto
FOR EACH ROW EXECUTE FUNCTION banco.validar_revision();

CREATE FUNCTION banco.validar_administrador_decision()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  PERFORM banco.exigir_rol(NEW.administrador_usuario_id,'administrador',true);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_decision_administrador BEFORE INSERT ON banco.decision_administrativa
FOR EACH ROW EXECUTE FUNCTION banco.validar_administrador_decision();
CREATE FUNCTION banco.validar_evaluador()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_empresa bigint;
BEGIN
  SELECT p.empresa_id INTO v_empresa FROM banco.candidatura c
    JOIN banco.proyecto p ON p.id=c.proyecto_id WHERE c.id=NEW.candidatura_id FOR SHARE OF c,p;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_representante(NEW.evaluador_usuario_id,v_empresa);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_evaluacion_evaluador BEFORE INSERT ON banco.evaluacion_candidato
FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluador();

CREATE FUNCTION banco.impedir_reescritura_origen()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME IN ('asignacion_alumno','asignacion_direccion')
    AND OLD.estado <> 'vigente' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Una asignación cerrada conserva su historial; una rectificación requiere procedimiento explícito'
      USING ERRCODE='55000';
  END IF;
  IF TG_TABLE_NAME='candidatura' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.alumno_id IS DISTINCT FROM OLD.alumno_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen de una candidatura no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.profesor_id IS DISTINCT FROM OLD.profesor_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen de una solicitud de dirección no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSIF TG_TABLE_NAME='asignacion_alumno' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.candidatura_id IS DISTINCT FROM OLD.candidatura_id
      OR NEW.decision_id IS DISTINCT FROM OLD.decision_id OR NEW.alumno_id IS DISTINCT FROM OLD.alumno_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen autorizado de la asignación de alumno no puede cambiar' USING ERRCODE='23503';
    END IF;
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.solicitud_direccion_id IS DISTINCT FROM OLD.solicitud_direccion_id
      OR NEW.decision_id IS DISTINCT FROM OLD.decision_id OR NEW.profesor_id IS DISTINCT FROM OLD.profesor_id OR NEW.proyecto_id IS DISTINCT FROM OLD.proyecto_id THEN
      RAISE EXCEPTION 'El origen autorizado de la dirección no puede cambiar' USING ERRCODE='23503';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_candidatura_origen BEFORE UPDATE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();
CREATE TRIGGER tr_solicitud_direccion_origen BEFORE UPDATE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();
CREATE TRIGGER tr_asignacion_alumno_origen BEFORE UPDATE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();
CREATE TRIGGER tr_asignacion_direccion_origen BEFORE UPDATE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();

CREATE FUNCTION banco.comprobar_acompanamiento(p_alumno bigint,p_direccion bigint,p_inicio timestamptz,p_fin timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_alumno banco.asignacion_alumno%ROWTYPE; v_direccion banco.asignacion_direccion%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Mismo orden para insertar/editar vínculos: alumno y después dirección.
  -- Los cierres de padres se comprueban también, al final de la transacción.
  SELECT * INTO v_alumno FROM banco.asignacion_alumno WHERE id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de alumno inexistente' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_direccion FROM banco.asignacion_direccion WHERE id=p_direccion FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de dirección inexistente' USING ERRCODE='23503'; END IF;
  IF v_alumno.proyecto_id <> v_direccion.proyecto_id
    OR p_inicio < v_alumno.inicio OR p_inicio < v_direccion.inicio
    OR (v_alumno.fin IS NOT NULL AND (p_fin IS NULL OR p_fin > v_alumno.fin))
    OR (v_direccion.fin IS NOT NULL AND (p_fin IS NULL OR p_fin > v_direccion.fin)) THEN
    RAISE EXCEPTION 'El acompañamiento requiere el mismo proyecto y vigencia contenida en ambas asignaciones' USING ERRCODE='23514';
  END IF;
END;
$$;
CREATE FUNCTION banco.validar_acompanamiento()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.asignacion_alumno_id IS DISTINCT FROM OLD.asignacion_alumno_id
      OR NEW.asignacion_direccion_id IS DISTINCT FROM OLD.asignacion_direccion_id
      OR NEW.inicio IS DISTINCT FROM OLD.inicio
      OR (OLD.estado <> 'vigente' AND NEW IS DISTINCT FROM OLD) THEN
      RAISE EXCEPTION 'El acompañamiento conserva identidad, origen e inicio; el historial cerrado no se reescribe'
        USING ERRCODE='55000';
    END IF;
  END IF;
  PERFORM banco.comprobar_acompanamiento(NEW.asignacion_alumno_id,NEW.asignacion_direccion_id,NEW.inicio,NEW.fin);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tr_acompanamiento_validar BEFORE INSERT OR UPDATE ON banco.acompanamiento
FOR EACH ROW EXECUTE FUNCTION banco.validar_acompanamiento();
CREATE FUNCTION banco.validar_vigencias_padre()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
DECLARE v_acompanamiento banco.acompanamiento%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME='asignacion_alumno' THEN
    FOR v_acompanamiento IN SELECT * FROM banco.acompanamiento WHERE asignacion_alumno_id=NEW.id ORDER BY id
    LOOP
      PERFORM banco.comprobar_acompanamiento(v_acompanamiento.asignacion_alumno_id,
        v_acompanamiento.asignacion_direccion_id,v_acompanamiento.inicio,v_acompanamiento.fin);
    END LOOP;
  ELSE
    FOR v_acompanamiento IN SELECT * FROM banco.acompanamiento WHERE asignacion_direccion_id=NEW.id ORDER BY id
    LOOP
      PERFORM banco.comprobar_acompanamiento(v_acompanamiento.asignacion_alumno_id,
        v_acompanamiento.asignacion_direccion_id,v_acompanamiento.inicio,v_acompanamiento.fin);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_vigencias
AFTER UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_vigencias_padre();
CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_vigencias
AFTER UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION banco.validar_vigencias_padre();

CREATE FUNCTION banco.impedir_reescritura_historial()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, banco AS $$
BEGIN
  RAISE EXCEPTION '%: el historial no admite %; conservar el registro original',TG_TABLE_NAME,TG_OP USING ERRCODE='55000';
END;
$$;
CREATE TRIGGER tr_decision_inmutable BEFORE UPDATE OR DELETE ON banco.decision_administrativa
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_evaluacion_inmutable BEFORE UPDATE OR DELETE ON banco.evaluacion_candidato
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_detalle_inmutable BEFORE UPDATE OR DELETE ON banco.detalle_evaluacion
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_auditoria_inmutable BEFORE UPDATE OR DELETE ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_revision_no_borrado BEFORE DELETE ON banco.revision_proyecto
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_candidatura_no_borrado BEFORE DELETE ON banco.candidatura
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_solicitud_no_borrado BEFORE DELETE ON banco.solicitud_direccion
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_representacion_no_borrado BEFORE DELETE ON banco.representacion_empresa
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_asignacion_alumno_no_borrado BEFORE DELETE ON banco.asignacion_alumno
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_asignacion_direccion_no_borrado BEFORE DELETE ON banco.asignacion_direccion
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();
CREATE TRIGGER tr_acompanamiento_no_borrado BEFORE DELETE ON banco.acompanamiento
FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();

-- Roles de conexión técnicos; no representan alumnos/empresas ni autentican al
-- actor. Hasta resolver D-10 no se otorga lectura de tablas personales completas.
-- Nunca reutilizar silenciosamente un rol existente con atributos elevados.
DO $$
DECLARE v_nombre text;
BEGIN
  FOREACH v_nombre IN ARRAY ARRAY['banco_lectura','banco_escritura'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_nombre) THEN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_nombre AND
        (rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication OR rolbypassrls)) THEN
        RAISE EXCEPTION 'El rol técnico existente % tiene atributos incompatibles; no se modifica automáticamente',v_nombre;
      END IF;
    ELSE
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',v_nombre);
    END IF;
  END LOOP;
END;
$$;
CREATE VIEW banco.v_usuario_directorio AS
SELECT id,nombre,rol_principal,estado_cuenta,fecha_alta FROM banco.usuario;
COMMENT ON VIEW banco.v_usuario_directorio IS 'Consulta técnica mínima; no contiene hash, correo, evidencias ni perfiles. La autorización por actor se implementará después.';
REVOKE ALL ON ALL TABLES IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA banco FROM PUBLIC,banco_lectura,banco_escritura;
GRANT USAGE ON SCHEMA banco TO banco_lectura,banco_escritura;
GRANT SELECT ON banco.v_usuario_directorio TO banco_lectura,banco_escritura;
ALTER DEFAULT PRIVILEGES IN SCHEMA banco REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
COMMENT ON ROLE banco_lectura IS 'Grupo NOLOGIN de consulta técnica mínima; no identifica actor de negocio.';
COMMENT ON ROLE banco_escritura IS 'Grupo NOLOGIN reservado para futuros servicios; sin DML de procesos pendientes en BD-01.';

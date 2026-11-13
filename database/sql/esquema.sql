--
-- PostgreSQL database dump
--

\restrict heTkHyRDWHAhzEQZkTL4hWkGKXUkeI5OVt7aVprLZ2vccjyB1VOpzv2fcvuU2Si

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: banco; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA banco;


--
-- Name: SCHEMA banco; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA banco IS 'BD-01 PostgreSQL: integridad estructural. Políticas D-01..D-08/D-10..D-12 y APIs pendientes.';


--
-- Name: actualizar_version_acceso(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.actualizar_version_acceso() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: alcance_cierre_proyecto(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.alcance_cierre_proyecto(p_proyecto bigint) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
  SELECT jsonb_build_object(
    'alumnos',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'),
    'direcciones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente'),
    'acompanamientos',(SELECT COALESCE(jsonb_agg(a.id ORDER BY a.id),'[]'::jsonb)
      FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
      WHERE x.proyecto_id=p_proyecto AND a.estado='vigente'),
    'candidaturas',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'estado',estado) ORDER BY id),'[]'::jsonb)
      FROM banco.candidatura WHERE proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')),
    'solicitudes',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'),
    'revisiones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
      FROM banco.revision_proyecto WHERE proyecto_id=p_proyecto AND estado_revision='en_revision'));
$$;


--
-- Name: cambiar_estado_cuenta(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.cambiar_estado_cuenta(p_admin bigint, p_usuario bigint, p_estado text, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION cambiar_estado_cuenta(p_admin bigint, p_usuario bigint, p_estado text, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.cambiar_estado_cuenta(p_admin bigint, p_usuario bigint, p_estado text, p_motivo text) IS 'D-10: cambio administrativo auditado sin liberar cargas. Conserva un administrador activo y exige relevo del representante vigente; controles del servicio interno, no autenticación ni grants de aplicación.';


--
-- Name: cancelar_candidatura(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.cancelar_candidatura(p_candidatura bigint, p_alumno bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_candidatura banco.candidatura%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Las transiciones de una fuente existente siguen fuente -> participante.
  -- La aprobación también bloquea primero la candidatura al hacer UPDATE y
  -- después su alumno en 006. Este orden evita invertir esos dos bloqueos.
  SELECT * INTO v_candidatura FROM banco.candidatura
    WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  IF v_candidatura.alumno_id IS DISTINCT FROM p_alumno THEN
    RAISE EXCEPTION 'RF-25: el alumno solo puede cancelar su propia candidatura'
      USING ERRCODE='23514';
  END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Perfil de alumno inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_alumno,'alumno',true);
  IF v_candidatura.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada')
    OR EXISTS (SELECT 1 FROM banco.asignacion_alumno WHERE candidatura_id=p_candidatura) THEN
    RAISE EXCEPTION 'D-07: solo se cancela una candidatura activa anterior a la asignación; un retiro posterior requiere al administrador'
      USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion('candidatura',p_candidatura);
  -- No se exige publicación actual: una candidatura anterior sin asignación
  -- puede cancelarse aunque otros participantes ya hayan iniciado el proyecto.
  -- El alumno no ocupa una plaza de asignación y no cambia acompañamientos.
  UPDATE banco.candidatura SET estado='cancelada' WHERE id=p_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_alumno,'usuario','cancelar_candidatura','candidatura',p_candidatura::text,
    v_candidatura.estado || ' -> cancelada',
    jsonb_build_object('proyecto_id',v_candidatura.proyecto_id,'cupo_candidatura_liberado',true)::text)
  RETURNING id INTO v_evento;
  RETURN v_evento;
END;
$$;


--
-- Name: FUNCTION cancelar_candidatura(p_candidatura bigint, p_alumno bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.cancelar_candidatura(p_candidatura bigint, p_alumno bigint) IS 'RF-25/D-07 parcial: alumno activo cancela una candidatura propia activa antes de asignarse; estado e historial auditado atómicos, sin borrar ni reabrir. No retiro posterior ni autenticación del ID recibido.';


--
-- Name: cancelar_proyecto(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.cancelar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
  SELECT banco.cerrar_proyecto(p_proyecto,p_admin,p_motivo,'cancelado');
$$;


--
-- Name: FUNCTION cancelar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.cancelar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text) IS 'D-07: administrador activo y motivo cancelan un proyecto abierto; cierre coordinado e idempotente con liberación de cupos/carga y conservación histórica. Sin avisos ni reapertura.';


--
-- Name: cancelar_solicitud_direccion(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.cancelar_solicitud_direccion(p_solicitud bigint, p_profesor bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_solicitud banco.solicitud_direccion%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_solicitud FROM banco.solicitud_direccion
    WHERE id=p_solicitud FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente' USING ERRCODE='23503'; END IF;
  IF v_solicitud.profesor_id IS DISTINCT FROM p_profesor THEN
    RAISE EXCEPTION 'D-07: el profesor solo cancela su propia solicitud'
      USING ERRCODE='23514';
  END IF;
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Perfil de profesor inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF v_solicitud.estado<>'pendiente' OR EXISTS
    (SELECT 1 FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_solicitud) THEN
    RAISE EXCEPTION 'D-07: solo se cancela la solicitud pendiente; el retiro del director corresponde al administrador'
      USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion('direccion',p_solicitud);
  UPDATE banco.solicitud_direccion SET estado='cancelada' WHERE id=p_solicitud;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,
    entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_profesor,'usuario','cancelar_solicitud_direccion','solicitud_direccion',
    p_solicitud::text,'pendiente -> cancelada',
    jsonb_build_object('proyecto_id',v_solicitud.proyecto_id,
      'sin_asignacion',true)::text) RETURNING id INTO v_evento;
  RETURN v_evento;
END;
$$;


--
-- Name: FUNCTION cancelar_solicitud_direccion(p_solicitud bigint, p_profesor bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.cancelar_solicitud_direccion(p_solicitud bigint, p_profesor bigint) IS 'D-07: profesor activo cancela su solicitud pendiente propia sin asignación, con auditoría atómica; no autentica los identificadores ni concede acceso de aplicación.';


--
-- Name: cerrar_proyecto(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.cerrar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text, p_destino text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE; v_alcance jsonb; v_actual jsonb;
  v_evento bigint; v_fecha timestamptz; v_estado_asignacion text; v_fila record;
  v_perfiles jsonb; v_operacion text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_destino IS NULL OR p_destino NOT IN ('finalizado','cancelado') THEN
    RAISE EXCEPTION 'Destino de cierre no reconocido' USING ERRCODE='22023';
  END IF;
  IF p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El cierre requiere motivo no blanco' USING ERRCODE='23514';
  END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF NOT EXISTS(SELECT 1 FROM banco.proyecto WHERE id=p_proyecto) THEN
    RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503';
  END IF;
  v_alcance:=banco.alcance_cierre_proyecto(p_proyecto);
  -- Las fuentes se bloquean antes de los perfiles: una autorización y las
  -- cancelaciones propias también siguen fuente -> perfil. No invertirlo.
  PERFORM id FROM banco.candidatura WHERE proyecto_id=p_proyecto
    AND (estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      OR id IN (SELECT candidatura_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'))
    ORDER BY id FOR UPDATE;
  PERFORM id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto
    AND (estado='pendiente' OR id IN (SELECT solicitud_direccion_id FROM banco.asignacion_direccion
      WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
  -- Conjuntos de perfiles leídos sin retener Proyecto; nunca se incorpora un
  -- perfil nuevo después de tomarlo. Dos cierres usan alumno/id, profesor/id.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo',tipo,'id',id) ORDER BY tipo,id),'[]'::jsonb)
    INTO v_perfiles FROM (
      SELECT 'alumno'::text tipo,alumno_id id FROM banco.candidatura WHERE proyecto_id=p_proyecto
        AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT 'alumno',alumno_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'
      UNION SELECT 'profesor',profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'
      UNION SELECT 'profesor',profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente') q;
  FOR v_fila IN SELECT x->>'tipo' tipo,(x->>'id')::bigint id FROM jsonb_array_elements(v_perfiles) x LOOP
    IF v_fila.tipo='alumno' THEN
      PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.id FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.id FOR UPDATE; END IF;
  END LOOP;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF v_proyecto.estado IN ('finalizado','cancelado') THEN
    IF v_proyecto.estado<>p_destino THEN RAISE EXCEPTION 'El cierre definitivo no se sustituye ni reabre' USING ERRCODE='55000'; END IF;
    PERFORM banco.comprobar_cierre_proyecto(v_proyecto,false);
    RETURN v_proyecto.evento_cierre_id;
  END IF;
  IF (p_destino='finalizado' AND v_proyecto.estado<>'en_curso')
    OR (p_destino='cancelado' AND v_proyecto.estado NOT IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
    RAISE EXCEPTION 'El estado actual no admite este cierre administrativo' USING ERRCODE='55000';
  END IF;
  v_actual:=banco.alcance_cierre_proyecto(p_proyecto);
  IF v_actual IS DISTINCT FROM v_alcance THEN
    RAISE EXCEPTION 'El alcance del cierre cambió durante la espera; reintentar la transacción completa' USING ERRCODE='40001';
  END IF;
  -- Después de Proyecto solo se toman padres, hijos y revisión. Las reservas
  -- nuevas esperan Proyecto y revalidan el estado terminal al obtenerlo.
  PERFORM id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente' ORDER BY id FOR UPDATE;
  PERFORM id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente' ORDER BY id FOR UPDATE;
  PERFORM a.id FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
    WHERE x.proyecto_id=p_proyecto AND a.estado='vigente' ORDER BY a.id FOR UPDATE OF a;
  PERFORM id FROM banco.revision_proyecto WHERE proyecto_id=p_proyecto AND estado_revision='en_revision' ORDER BY id FOR UPDATE;
  -- Los acompañamientos pueden escribirse tomando solo sus padres. Si alguno
  -- terminó de incorporarse mientras adquiríamos esos padres, no queda fuera.
  IF banco.alcance_cierre_proyecto(p_proyecto) IS DISTINCT FROM v_alcance THEN
    RAISE EXCEPTION 'El alcance del cierre cambió durante la espera; reintentar la transacción completa' USING ERRCODE='40001';
  END IF;
  IF p_destino='finalizado' THEN
    -- En curso mantiene sus condiciones operativas; finalizar no acredita
    -- calificaciones o entregables y no permite saltar una pausa pendiente.
    v_publicado:=v_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.comprobar_condiciones_inicio(v_publicado);
  END IF;
  v_operacion:=CASE p_destino WHEN 'finalizado' THEN 'finalizar_proyecto' ELSE 'cancelar_proyecto' END;
  v_estado_asignacion:=CASE p_destino WHEN 'finalizado' THEN 'finalizada' ELSE 'revocada' END;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario',v_operacion,'proyecto',p_proyecto::text,v_proyecto.estado || ' -> ' || p_destino,
      jsonb_build_object('motivo',p_motivo,'estado_anterior',v_proyecto.estado,'evento_inicio_id',v_proyecto.evento_inicio_id,
        'evento_estado_id',v_proyecto.evento_estado_id,'revision_publicada_id',v_proyecto.revision_publicada_id,'alcance',v_alcance)::text)
    RETURNING id,fecha INTO v_evento,v_fecha;
  UPDATE banco.asignacion_alumno SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='vigente';
  UPDATE banco.asignacion_direccion SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='vigente';
  UPDATE banco.acompanamiento a SET estado=v_estado_asignacion,fin=CASE WHEN v_fecha>a.inicio THEN v_fecha ELSE NULL END,
    evento_cierre_id=v_evento FROM banco.asignacion_alumno x
    WHERE x.id=a.asignacion_alumno_id AND x.proyecto_id=p_proyecto AND a.estado='vigente';
  UPDATE banco.candidatura SET estado='cancelada',evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto
    AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
  UPDATE banco.solicitud_direccion SET estado='cancelada',evento_cierre_id=v_evento WHERE proyecto_id=p_proyecto AND estado='pendiente';
  UPDATE banco.revision_proyecto SET estado_revision='cancelada',evento_cierre_id=v_evento
    WHERE proyecto_id=p_proyecto AND estado_revision='en_revision';
  UPDATE banco.proyecto SET estado=p_destino,evento_cierre_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;


--
-- Name: comprobar_acompanamiento(bigint, bigint, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_acompanamiento(p_alumno bigint, p_direccion bigint, p_inicio timestamp with time zone, p_fin timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_vinculo banco.acompanamiento%ROWTYPE;
BEGIN
  v_vinculo.asignacion_alumno_id:=p_alumno; v_vinculo.asignacion_direccion_id:=p_direccion;
  v_vinculo.inicio:=p_inicio; v_vinculo.fin:=p_fin;
  v_vinculo.estado:=CASE WHEN p_fin IS NULL THEN 'vigente' ELSE 'finalizada' END;
  PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acompanamiento; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.acompanamiento (
    id bigint NOT NULL,
    asignacion_alumno_id bigint NOT NULL,
    asignacion_direccion_id bigint NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fin timestamp with time zone,
    estado text DEFAULT 'vigente'::text NOT NULL,
    evento_retiro_id bigint,
    evento_cierre_id bigint,
    CONSTRAINT acompanamiento_estado_check CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text]))),
    CONSTRAINT ck_acompanamiento_fechas CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))
);


--
-- Name: COLUMN acompanamiento.evento_retiro_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.acompanamiento.evento_retiro_id IS 'Retiro exacto de uno de sus padres; el periodo futuro revocado no recibe un fin ficticio. No crea acompañamientos al reponer participantes.';


--
-- Name: COLUMN acompanamiento.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.acompanamiento.evento_cierre_id IS 'Cierre coordinado con ambos padres; conserva periodos previos y no inventa final para un periodo futuro.';


--
-- Name: comprobar_acompanamiento_estado(banco.acompanamiento); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_acompanamiento_estado(p_vinculo banco.acompanamiento) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_alumno banco.asignacion_alumno%ROWTYPE; v_direccion banco.asignacion_direccion%ROWTYPE;
  v_evento banco.evento_auditoria%ROWTYPE; v_fecha timestamptz;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_alumno FROM banco.asignacion_alumno WHERE id=p_vinculo.asignacion_alumno_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de alumno inexistente' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_direccion FROM banco.asignacion_direccion WHERE id=p_vinculo.asignacion_direccion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asignación de dirección inexistente' USING ERRCODE='23503'; END IF;
  IF v_alumno.proyecto_id<>v_direccion.proyecto_id OR p_vinculo.inicio<v_alumno.inicio OR p_vinculo.inicio<v_direccion.inicio THEN
    RAISE EXCEPTION 'El acompañamiento requiere el mismo proyecto y comienzo contenido' USING ERRCODE='23514';
  END IF;
  IF p_vinculo.estado='vigente' AND (v_alumno.estado<>'vigente' OR v_direccion.estado<>'vigente') THEN
    RAISE EXCEPTION 'Un acompañamiento vigente requiere ambas asignaciones vigentes' USING ERRCODE='23514';
  END IF;
  IF p_vinculo.evento_cierre_id IS NOT NULL THEN
    IF p_vinculo.evento_retiro_id IS NOT NULL
      OR v_alumno.evento_cierre_id IS DISTINCT FROM p_vinculo.evento_cierre_id
      OR v_direccion.evento_cierre_id IS DISTINCT FROM p_vinculo.evento_cierre_id THEN
      RAISE EXCEPTION 'El acompañamiento cierra con ambas asignaciones en la misma operación' USING ERRCODE='23514';
    END IF;
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_alumno.proyecto_id,'alumnos',
      v_alumno.id,v_alumno.estado,v_alumno.inicio,v_alumno.fin,false);
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_direccion.proyecto_id,'direcciones',
      v_direccion.id,v_direccion.estado,v_direccion.inicio,v_direccion.fin,false);
    PERFORM banco.comprobar_periodo_cierre(p_vinculo.evento_cierre_id,v_alumno.proyecto_id,'acompanamientos',
      p_vinculo.id,p_vinculo.estado,p_vinculo.inicio,p_vinculo.fin,false);
    -- Un periodo que aún no empezó no tiene intervalo efectivo que contener.
    IF p_vinculo.fin IS NULL THEN RETURN; END IF;
  ELSIF p_vinculo.evento_retiro_id IS NOT NULL THEN
    IF p_vinculo.estado<>'revocada' THEN RAISE EXCEPTION 'La evidencia de retiro requiere acompañamiento revocado' USING ERRCODE='23514'; END IF;
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_vinculo.evento_retiro_id;
    IF v_evento.operacion='retirar_alumno' AND v_alumno.estado='revocada'
      AND v_alumno.evento_retiro_id=p_vinculo.evento_retiro_id THEN
      v_fecha := banco.comprobar_retiro('alumno',v_alumno.id,v_alumno.alumno_id,v_alumno.proyecto_id,
        v_alumno.inicio,v_alumno.fin,v_alumno.evento_retiro_id,false);
    ELSIF v_evento.operacion='retirar_director' AND v_direccion.estado='revocada'
      AND v_direccion.evento_retiro_id=p_vinculo.evento_retiro_id THEN
      v_fecha := banco.comprobar_retiro('direccion',v_direccion.id,v_direccion.profesor_id,v_direccion.proyecto_id,
        v_direccion.inicio,v_direccion.fin,v_direccion.evento_retiro_id,false);
    ELSE
      RAISE EXCEPTION 'El acompañamiento debe cerrar por el retiro exacto de uno de sus padres' USING ERRCODE='23514';
    END IF;
    IF p_vinculo.fin IS DISTINCT FROM (CASE WHEN v_fecha>p_vinculo.inicio THEN v_fecha ELSE NULL END) THEN
      RAISE EXCEPTION 'El fin del acompañamiento no puede inventarse antes de su inicio' USING ERRCODE='23514';
    END IF;
    IF p_vinculo.fin IS NULL THEN RETURN; END IF;
  ELSIF p_vinculo.estado IN ('revocada','finalizada') AND p_vinculo.fin IS NULL THEN
    RAISE EXCEPTION 'Una revocación anterior al inicio requiere su evidencia exacta' USING ERRCODE='23514';
  END IF;
  IF (v_alumno.estado<>'vigente' AND v_alumno.fin IS NULL)
    OR (v_direccion.estado<>'vigente' AND v_direccion.fin IS NULL)
    OR (v_alumno.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_alumno.fin))
    OR (v_direccion.fin IS NOT NULL AND (p_vinculo.fin IS NULL OR p_vinculo.fin>v_direccion.fin)) THEN
    RAISE EXCEPTION 'La vigencia efectiva del acompañamiento debe quedar contenida en ambas asignaciones' USING ERRCODE='23514';
  END IF;
END;
$$;


--
-- Name: comprobar_aprobacion_participacion(text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_aprobacion_participacion(p_tipo text, p_id bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_estado text; v_asignacion bigint; v_decision bigint; v_aprobacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Consultar el estado FINAL de la transacción, no el NEW de un evento previo.
  -- Las FK, la inmutabilidad del origen/historial y los locks de participante
  -- protegen las referencias sin invertir aquí el orden de bloqueos.
  IF p_tipo='candidatura' THEN
    SELECT estado INTO v_estado FROM banco.candidatura WHERE id=p_id;
    SELECT id,decision_id INTO v_asignacion,v_decision FROM banco.asignacion_alumno WHERE candidatura_id=p_id;
    SELECT id INTO v_aprobacion FROM banco.decision_administrativa WHERE candidatura_id=p_id AND resultado='aprobada';
  ELSIF p_tipo='direccion' THEN
    SELECT estado INTO v_estado FROM banco.solicitud_direccion WHERE id=p_id;
    SELECT id,decision_id INTO v_asignacion,v_decision FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_id;
    SELECT id INTO v_aprobacion FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_id AND resultado='aprobada';
  ELSE
    RAISE EXCEPTION 'Tipo de participación desconocido' USING ERRCODE='22023';
  END IF;
  IF v_estado='aprobada' OR v_asignacion IS NOT NULL OR v_aprobacion IS NOT NULL THEN
    IF v_estado IS DISTINCT FROM 'aprobada' OR v_asignacion IS NULL OR v_aprobacion IS NULL
      OR v_decision IS DISTINCT FROM v_aprobacion THEN
      RAISE EXCEPTION 'D-06: aprobar % % requiere origen aprobado, decisión y asignación exacta en la misma transacción',p_tipo,p_id
        USING ERRCODE='23514';
    END IF;
  END IF;
END;
$$;


--
-- Name: FUNCTION comprobar_aprobacion_participacion(p_tipo text, p_id bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.comprobar_aprobacion_participacion(p_tipo text, p_id bigint) IS 'D-06: integridad diferida del estado final origen/aprobación/asignación. No define evaluación previa D-08 ni habilita permisos o flujos de cierre D-07.';


--
-- Name: proyecto; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.proyecto (
    id bigint NOT NULL,
    empresa_id bigint NOT NULL,
    autor_usuario_id bigint NOT NULL,
    titulo text NOT NULL,
    descripcion text,
    problematica text,
    objetivos text,
    justificacion text,
    alcance text,
    requisitos_academicos text,
    duracion_estimada text,
    modalidad text,
    fecha_inicio_estimada date,
    fecha_fin_estimada date,
    recursos text,
    estado text DEFAULT 'borrador'::text NOT NULL,
    revision_publicada_id bigint,
    cupo_maximo_alumnos integer,
    evento_inicio_id bigint,
    evento_estado_id bigint,
    evento_cierre_id bigint,
    CONSTRAINT ck_proyecto_cierre_evidencia CHECK (((estado = ANY (ARRAY['finalizado'::text, 'cancelado'::text])) = (evento_cierre_id IS NOT NULL))),
    CONSTRAINT ck_proyecto_cupo_positivo CHECK (((cupo_maximo_alumnos IS NULL) OR (cupo_maximo_alumnos > 0))),
    CONSTRAINT ck_proyecto_fechas CHECK (((fecha_inicio_estimada IS NULL) OR (fecha_fin_estimada IS NULL) OR (fecha_fin_estimada >= fecha_inicio_estimada))),
    CONSTRAINT ck_proyecto_inicio_evidencia CHECK ((((estado <> ALL (ARRAY['en_curso'::text, 'pausado'::text])) OR (evento_inicio_id IS NOT NULL)) AND ((evento_inicio_id IS NULL) OR (estado = ANY (ARRAY['en_curso'::text, 'pausado'::text, 'finalizado'::text, 'cancelado'::text]))) AND ((estado <> 'pausado'::text) OR (evento_estado_id IS NOT NULL)) AND ((evento_estado_id IS NULL) OR (evento_inicio_id IS NOT NULL)))),
    CONSTRAINT proyecto_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'en_revision'::text, 'en_correccion'::text, 'publicado'::text, 'rechazado'::text, 'en_curso'::text, 'pausado'::text, 'finalizado'::text, 'cancelado'::text]))),
    CONSTRAINT proyecto_titulo_check CHECK ((btrim(titulo) <> ''::text))
);


--
-- Name: COLUMN proyecto.revision_publicada_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.proyecto.revision_publicada_id IS 'Versión inicial autorizada, FK compuesta al mismo proyecto. La aprobación y coherencia del contenido se validan antes de publicar/asignar. Edición posterior D-07 pendiente.';


--
-- Name: COLUMN proyecto.cupo_maximo_alumnos; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.proyecto.cupo_maximo_alumnos IS 'D-02: capacidad propuesta por la empresa, sin default. Obligatoria y positiva al enviar; validada al aprobar la revisión v2 exacta. No se cambia después de publicar (D-07).';


--
-- Name: COLUMN proyecto.evento_inicio_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.proyecto.evento_inicio_id IS 'D-05: evento inmutable del inicio administrativo; conserva actor, fecha, versión publicada, cupo y asignaciones verificadas. No duplica los datos del evento.';


--
-- Name: COLUMN proyecto.evento_estado_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.proyecto.evento_estado_id IS 'D-07: último evento inmutable de pausa/reanudación; enlaza el anterior en su resultado. Conserva el primer evento_inicio_id.';


--
-- Name: COLUMN proyecto.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.proyecto.evento_cierre_id IS 'D-07: cierre definitivo administrativo exacto; conserva primer inicio y última pausa/reanudación sin inventarlos para proyectos no iniciados.';


--
-- Name: comprobar_cierre_proyecto(banco.proyecto, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_cierre_proyecto(p_proyecto banco.proyecto, p_actual boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_esperado jsonb;
  v_alcance jsonb; v_estado text; v_fila record; v_candidaturas jsonb;
BEGIN
  v_evento:=banco.evento_cierre_proyecto(p_proyecto.evento_cierre_id,p_proyecto.id,p_actual);
  v_datos:=v_evento.resultado::jsonb;
  v_estado:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizado' ELSE 'cancelado' END;
  IF p_proyecto.estado IS DISTINCT FROM v_estado
    OR banco.alcance_cierre_proyecto(p_proyecto.id) IS DISTINCT FROM
      jsonb_build_object('alumnos','[]'::jsonb,'direcciones','[]'::jsonb,'acompanamientos','[]'::jsonb,
        'candidaturas','[]'::jsonb,'solicitudes','[]'::jsonb,'revisiones','[]'::jsonb) THEN
    RAISE EXCEPTION 'Un proyecto cerrado no conserva reservas ni solicitudes pendientes' USING ERRCODE='23514';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'estado',e.estado) ORDER BY c.id),'[]'::jsonb)
    INTO v_candidaturas FROM banco.candidatura c
    LEFT JOIN LATERAL (SELECT valor->>'estado' estado
      FROM jsonb_array_elements(v_datos #> '{alcance,candidaturas}') x(valor)
      WHERE valor->>'id'=c.id::text LIMIT 1) e ON true
    WHERE c.proyecto_id=p_proyecto.id AND c.evento_cierre_id=v_evento.id AND c.estado='cancelada';
  v_alcance:=jsonb_build_object(
    'alumnos',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.asignacion_alumno
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id),
    'direcciones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.asignacion_direccion
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id),
    'acompanamientos',(SELECT COALESCE(jsonb_agg(a.id ORDER BY a.id),'[]'::jsonb)
      FROM banco.acompanamiento a JOIN banco.asignacion_alumno x ON x.id=a.asignacion_alumno_id
      WHERE x.proyecto_id=p_proyecto.id AND a.evento_cierre_id=v_evento.id),
    'candidaturas',v_candidaturas,
    'solicitudes',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.solicitud_direccion
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id AND estado='cancelada'),
    'revisiones',(SELECT COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb) FROM banco.revision_proyecto
      WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id AND estado_revision='cancelada'));
  v_esperado:=jsonb_build_object('motivo',v_datos->>'motivo','estado_anterior',v_datos->>'estado_anterior',
    'evento_inicio_id',p_proyecto.evento_inicio_id,'evento_estado_id',p_proyecto.evento_estado_id,
    'revision_publicada_id',p_proyecto.revision_publicada_id,'alcance',v_alcance,'transaccion_id',v_datos->>'transaccion_id');
  IF v_datos IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'La evidencia de cierre no coincide con todos sus registros y antecedentes' USING ERRCODE='23514';
  END IF;
  FOR v_fila IN SELECT * FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id LOOP
    PERFORM banco.comprobar_periodo_cierre(v_evento.id,p_proyecto.id,'alumnos',v_fila.id,v_fila.estado,v_fila.inicio,v_fila.fin,p_actual);
  END LOOP;
  FOR v_fila IN SELECT * FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND evento_cierre_id=v_evento.id LOOP
    PERFORM banco.comprobar_periodo_cierre(v_evento.id,p_proyecto.id,'direcciones',v_fila.id,v_fila.estado,v_fila.inicio,v_fila.fin,p_actual);
  END LOOP;
END;
$$;


--
-- Name: comprobar_condiciones_inicio(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_condiciones_inicio(p_proyecto banco.proyecto) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_alumno banco.asignacion_alumno%ROWTYPE;
  v_direccion banco.asignacion_direccion%ROWTYPE;
  v_alumnos bigint; v_directores bigint; v_ids jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_publicacion_valida(p_proyecto);
  SELECT count(*),COALESCE(jsonb_agg(id ORDER BY id),'[]'::jsonb)
    INTO v_alumnos,v_ids FROM banco.asignacion_alumno
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  SELECT count(*) INTO v_directores FROM banco.asignacion_direccion
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  IF v_alumnos < 1 OR v_alumnos > p_proyecto.cupo_maximo_alumnos OR v_directores <> 1 THEN
    RAISE EXCEPTION 'D-05: iniciar requiere al menos un alumno dentro del cupo validado y un director vigente del mismo proyecto'
      USING ERRCODE='23514';
  END IF;
  -- La fila Proyecto ya está bloqueada por iniciar_proyecto o por el UPDATE.
  -- Los triggers de 006 serializan sobre ella toda modificación de asignación.
  -- No se toman locks de perfiles/asignaciones en orden inverso: inicio no
  -- reserva nueva carga y los límites globales se conservan también en 006.
  FOR v_alumno IN SELECT * FROM banco.asignacion_alumno
    WHERE proyecto_id=p_proyecto.id AND estado='vigente' ORDER BY id
  LOOP
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',v_alumno.candidatura_id);
    IF NOT EXISTS (SELECT 1 FROM banco.candidatura c JOIN banco.decision_administrativa d
      ON d.id=v_alumno.decision_id AND d.candidatura_id=c.id AND d.resultado='aprobada'
      WHERE c.id=v_alumno.candidatura_id AND c.alumno_id=v_alumno.alumno_id
        AND c.proyecto_id=p_proyecto.id AND c.estado='aprobada')
      OR (SELECT count(*) FROM banco.asignacion_alumno
        WHERE alumno_id=v_alumno.alumno_id AND estado='vigente') > 1 THEN
      RAISE EXCEPTION 'D-04/D-05/D-06: origen/aprobación exactos y carga máxima del alumno requeridos para iniciar'
        USING ERRCODE='23514';
    END IF;
  END LOOP;
  SELECT * INTO v_direccion FROM banco.asignacion_direccion
    WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  PERFORM banco.comprobar_aprobacion_participacion('direccion',v_direccion.solicitud_direccion_id);
  IF NOT EXISTS (SELECT 1 FROM banco.solicitud_direccion s JOIN banco.decision_administrativa d
    ON d.id=v_direccion.decision_id AND d.solicitud_direccion_id=s.id AND d.resultado='aprobada'
    WHERE s.id=v_direccion.solicitud_direccion_id AND s.profesor_id=v_direccion.profesor_id
      AND s.proyecto_id=p_proyecto.id AND s.estado='aprobada')
    OR (SELECT count(DISTINCT proyecto_id) FROM banco.asignacion_direccion
      WHERE profesor_id=v_direccion.profesor_id AND estado='vigente') > 3 THEN
    RAISE EXCEPTION 'RN-05/D-05/D-06: origen/aprobación exactos y carga máxima del director requeridos para iniciar'
      USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('revision_publicada_id',p_proyecto.revision_publicada_id,
    'cupo_validado',p_proyecto.cupo_maximo_alumnos,'asignaciones_alumno',v_ids,
    'asignacion_direccion',v_direccion.id);
END;
$$;


--
-- Name: comprobar_evaluacion_d08(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_evaluacion_d08(p_evaluacion bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_eval banco.evaluacion_candidato%ROWTYPE; v_det record; v_total integer:=0;
BEGIN
  SELECT * INTO v_eval FROM banco.evaluacion_candidato WHERE id=p_evaluacion;
  IF NOT FOUND THEN RAISE EXCEPTION 'Evaluación inexistente' USING ERRCODE='23503'; END IF;
  IF v_eval.version_rubrica IS NULL THEN RETURN; END IF;
  IF v_eval.comentarios IS NULL OR v_eval.comentarios !~ '[^[:space:]]'
    OR v_eval.recomendacion IS NULL OR v_eval.recomendacion NOT IN ('recomendada','no_recomendada') THEN
    RAISE EXCEPTION 'D-08 requiere comentarios y recomendación explícita' USING ERRCODE='23514';
  END IF;
  FOR v_det IN SELECT d.*,c.codigo FROM banco.detalle_evaluacion d
    JOIN banco.criterio_evaluacion c ON c.id=d.criterio_id WHERE d.evaluacion_id=p_evaluacion
  LOOP
    IF v_det.codigo IS NULL OR v_det.codigo NOT IN ('tecnico','blando','academico')
      OR v_det.puntuacion NOT IN (0,1,2) OR v_det.comentario IS NULL OR v_det.comentario !~ '[^[:space:]]'
      OR v_det.definicion_aplicada IS DISTINCT FROM banco.definicion_criterio_d08(v_det.codigo) THEN
      RAISE EXCEPTION 'D-08 requiere tres criterios con escala 0..2, comentario y definición exacta' USING ERRCODE='23514';
    END IF;
    v_total:=v_total+1;
  END LOOP;
  IF v_total<>3 THEN RAISE EXCEPTION 'D-08: evaluación incompleta' USING ERRCODE='23514'; END IF;
END;
$$;


--
-- Name: comprobar_periodo_cierre(bigint, bigint, text, bigint, text, timestamp with time zone, timestamp with time zone, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_periodo_cierre(p_evento bigint, p_proyecto bigint, p_clave text, p_id bigint, p_estado text, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_actual boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_estado text;
BEGIN
  v_evento:=banco.evento_cierre_proyecto(p_evento,p_proyecto,p_actual);
  v_estado:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizada' ELSE 'revocada' END;
  IF p_clave NOT IN ('alumnos','direcciones','acompanamientos')
    OR p_estado IS DISTINCT FROM v_estado
    OR NOT COALESCE((v_evento.resultado::jsonb #> ARRAY['alcance',p_clave]) @> jsonb_build_array(p_id),false)
    OR p_fin IS DISTINCT FROM (CASE WHEN v_evento.fecha>p_inicio THEN v_evento.fecha ELSE NULL END) THEN
    RAISE EXCEPTION 'El periodo y estado deben corresponder al cierre exacto, sin inventar fechas' USING ERRCODE='23514';
  END IF;
END;
$$;


--
-- Name: comprobar_representacion_diferida(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_representacion_diferida() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: comprobar_representante_empresa(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_representante_empresa(p_empresa bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: comprobar_retiro(text, bigint, bigint, bigint, timestamp with time zone, timestamp with time zone, bigint, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.comprobar_retiro(p_tipo text, p_asignacion bigint, p_participante bigint, p_proyecto bigint, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_evento bigint, p_actual boolean DEFAULT true) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_operacion text; v_entidad text; v_fin timestamptz;
BEGIN
  IF p_tipo='alumno' THEN v_operacion:='retirar_alumno'; v_entidad:='asignacion_alumno';
  ELSIF p_tipo='direccion' THEN v_operacion:='retirar_director'; v_entidad:='asignacion_direccion';
  ELSE RAISE EXCEPTION 'Tipo de retiro no reconocido' USING ERRCODE='22023'; END IF;
  v_evento := banco.evento_operacion(p_evento,v_operacion,v_entidad,p_asignacion,p_actual);
  v_datos := v_evento.resultado::jsonb;
  IF v_evento.transicion IS DISTINCT FROM 'vigente -> revocada'
    OR v_datos->>'tipo' IS DISTINCT FROM p_tipo OR v_datos->>'asignacion_id' IS DISTINCT FROM p_asignacion::text
    OR v_datos->>'participante_id' IS DISTINCT FROM p_participante::text
    OR v_datos->>'proyecto_id' IS DISTINCT FROM p_proyecto::text
    OR jsonb_typeof(v_datos->'motivo') IS DISTINCT FROM 'string'
    OR (v_datos->>'motivo') !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El retiro requiere participante, proyecto y motivo exactos' USING ERRCODE='23514';
  END IF;
  v_fin := CASE WHEN v_evento.fecha>p_inicio THEN v_evento.fecha ELSE NULL END;
  IF p_fin IS DISTINCT FROM v_fin THEN
    RAISE EXCEPTION 'El retiro conserva el inicio; fin es la fecha real solo si el periodo había empezado'
      USING ERRCODE='23514';
  END IF;
  RETURN v_evento.fecha;
END;
$$;


--
-- Name: consultar_notificaciones(bigint, integer, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.consultar_notificaciones(p_usuario bigint, p_limite integer DEFAULT 50, p_antes_id bigint DEFAULT NULL::bigint) RETURNS TABLE(id bigint, evento_id bigint, mensaje text, fecha timestamp with time zone, fecha_lectura timestamp with time zone)
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_rol text;
BEGIN
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 THEN
    RAISE EXCEPTION 'El límite de consulta debe estar entre 1 y 100' USING ERRCODE='23514'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE usuario.id=p_usuario;
  PERFORM banco.exigir_rol(p_usuario,v_rol,true);
  RETURN QUERY SELECT n.id,n.evento_id,n.mensaje,n.fecha,n.fecha_lectura FROM banco.notificacion n
    WHERE n.destinatario_usuario_id=p_usuario AND (p_antes_id IS NULL OR n.id<p_antes_id)
    ORDER BY n.id DESC LIMIT p_limite;
END;
$$;


--
-- Name: consultar_perfil(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.consultar_perfil(p_actor bigint, p_titular bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION consultar_perfil(p_actor bigint, p_titular bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.consultar_perfil(p_actor bigint, p_titular bigint) IS 'D-10: perfil propio/admin o perfil académico de postulante de empresa vigente y alumno de dirección vigente. Whitelist sin hash/correo de acceso; matrícula y empleado solo titular/admin. No autentica los IDs.';


--
-- Name: contenido_proyecto(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.contenido_proyecto(p_proyecto banco.proyecto) RETURNS jsonb
    LANGUAGE sql IMMUTABLE STRICT
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: crear_cuenta(bigint, text, text, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.crear_cuenta(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_rol text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION crear_cuenta(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_rol text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.crear_cuenta(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_rol text) IS 'Alta interna RF-02/D-09: administrador activo, correo normalizado, rol no empresarial y auditoría atómica. No exige perfil académico inicial ni valida la autenticación o el algoritmo del hash opaco recibido.';


--
-- Name: crear_empresa_con_representante(bigint, text, text, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.crear_empresa_con_representante(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_razon_social text) RETURNS TABLE(usuario_id bigint, empresa_id bigint)
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION crear_empresa_con_representante(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_razon_social text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.crear_empresa_con_representante(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_razon_social text) IS 'Alta inicial interna D-09: administrador activo, cuenta empresarial, empresa, representante y auditoría en una transacción. Sin relevo D-10, entrega de claves, avisos ni autenticación del ID suministrado.';


--
-- Name: definicion_criterio_d08(text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.definicion_criterio_d08(p_codigo text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_nombre text; v_descripcion text;
BEGIN
  CASE p_codigo
    WHEN 'tecnico' THEN v_nombre:='Conocimientos técnicos'; v_descripcion:='Correspondencia de conocimientos y habilidades técnicas con el proyecto';
    WHEN 'blando' THEN v_nombre:='Habilidades blandas'; v_descripcion:='Correspondencia de habilidades socioemocionales con el proyecto';
    WHEN 'academico' THEN v_nombre:='Requisitos académicos'; v_descripcion:='Correspondencia del perfil académico con los requisitos indicados por el proyecto';
    ELSE RAISE EXCEPTION 'Criterio D-08 desconocido' USING ERRCODE='22023';
  END CASE;
  RETURN jsonb_build_object('version',1,'codigo',p_codigo,'nombre',v_nombre,'descripcion',v_descripcion,
    'escala','0=no cumple; 1=cumple parcialmente; 2=cumple','ponderacion',1);
END;
$$;


--
-- Name: enviar_proyecto(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.enviar_proyecto(p_proyecto bigint, p_autor bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION enviar_proyecto(p_proyecto bigint, p_autor bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.enviar_proyecto(p_proyecto bigint, p_autor bigint) IS 'Función interna del propietario: exige seis campos RF-08 y cupo positivo D-02; representante activo, snapshot v2 y auditoría. No API ni autenticación del actor.';


--
-- Name: evaluar_candidatura(bigint, bigint, jsonb, text, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.evaluar_candidatura(p_candidatura bigint, p_representante bigint, p_puntuaciones jsonb, p_comentarios text, p_recomendada boolean) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE;
  v_eval bigint; v_codigo text; v_item jsonb; v_def jsonb; v_criterio bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_comentarios IS NULL OR p_comentarios !~ '[^[:space:]]' OR p_recomendada IS NULL
    OR p_puntuaciones IS NULL OR jsonb_typeof(p_puntuaciones)<>'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_puntuaciones))<>3
    OR NOT (p_puntuaciones ?& ARRAY['tecnico','blando','academico']) THEN
    RAISE EXCEPTION 'D-08: rúbrica, comentarios y recomendación completos son obligatorios' USING ERRCODE='23514';
  END IF;
  FOREACH v_codigo IN ARRAY ARRAY['tecnico','blando','academico'] LOOP
    v_item:=p_puntuaciones->v_codigo;
    IF jsonb_typeof(v_item) IS DISTINCT FROM 'object'
      OR (SELECT count(*) FROM jsonb_object_keys(v_item))<>2 OR NOT(v_item ?& ARRAY['puntuacion','comentario'])
      OR jsonb_typeof(v_item->'puntuacion') IS DISTINCT FROM 'number'
      OR (v_item->>'puntuacion')::numeric NOT IN (0,1,2)
      OR jsonb_typeof(v_item->'comentario') IS DISTINCT FROM 'string'
      OR (v_item->>'comentario') !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'D-08: cada criterio requiere puntuación 0, 1 o 2 y comentario' USING ERRCODE='23514';
    END IF;
  END LOOP;
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_representante(p_representante,v_p.empresa_id);
  IF v_c.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada') THEN
    RAISE EXCEPTION 'Solo se evalúa una candidatura activa' USING ERRCODE='55000';
  END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
  INSERT INTO banco.evaluacion_candidato(candidatura_id,evaluador_usuario_id,fecha,comentarios,recomendacion,version_rubrica)
    VALUES(p_candidatura,p_representante,clock_timestamp(),p_comentarios,
      CASE WHEN p_recomendada THEN 'recomendada' ELSE 'no_recomendada' END,1) RETURNING id INTO v_eval;
  -- Catálogo fijo creado bajo demanda; las inserciones concurrentes convergen.
  -- No se cambia ni interpreta un criterio/evaluación anterior sin versión.
  FOREACH v_codigo IN ARRAY ARRAY['tecnico','blando','academico'] LOOP
    v_def:=banco.definicion_criterio_d08(v_codigo);
    INSERT INTO banco.criterio_evaluacion(codigo,nombre,descripcion,escala,ponderacion)
      VALUES(v_codigo,v_def->>'nombre',v_def->>'descripcion',v_def->>'escala',1)
      ON CONFLICT(codigo) WHERE codigo IS NOT NULL DO NOTHING;
    SELECT id INTO v_criterio FROM banco.criterio_evaluacion WHERE codigo=v_codigo;
    INSERT INTO banco.detalle_evaluacion(evaluacion_id,criterio_id,puntuacion,comentario,definicion_aplicada)
      VALUES(v_eval,v_criterio,(p_puntuaciones->v_codigo->>'puntuacion')::numeric,
        p_puntuaciones->v_codigo->>'comentario',v_def);
  END LOOP;
  PERFORM banco.comprobar_evaluacion_d08(v_eval);
  UPDATE banco.candidatura SET estado='evaluada',evaluacion_vigente_id=v_eval,evento_preseleccion_id=NULL
    WHERE id=p_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_representante,'usuario','evaluar_candidatura','candidatura',p_candidatura::text,v_c.estado || ' -> evaluada',
      jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_eval,'version_rubrica',1,
        'evaluacion_anterior_id',v_c.evaluacion_vigente_id,'preseleccion_anterior_id',v_c.evento_preseleccion_id)::text);
  RETURN v_eval;
END;
$$;


--
-- Name: FUNCTION evaluar_candidatura(p_candidatura bigint, p_representante bigint, p_puntuaciones jsonb, p_comentarios text, p_recomendada boolean); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.evaluar_candidatura(p_candidatura bigint, p_representante bigint, p_puntuaciones jsonb, p_comentarios text, p_recomendada boolean) IS 'D-08: rúbrica manual 0..2 de tres criterios, iguales pesos sin umbral automático; evaluación y detalle inmutables, nueva evaluación invalida preselección. IDs no autentican.';


--
-- Name: evento_auditoria; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.evento_auditoria (
    id bigint NOT NULL,
    actor_usuario_id bigint,
    origen text NOT NULL,
    operacion text NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    entidad_afectada text NOT NULL,
    registro_afectado text NOT NULL,
    transicion text,
    resultado text NOT NULL,
    CONSTRAINT ck_auditoria_actor CHECK ((((origen = 'usuario'::text) AND (actor_usuario_id IS NOT NULL)) OR ((origen = 'sistema'::text) AND (actor_usuario_id IS NULL)))),
    CONSTRAINT evento_auditoria_entidad_afectada_check CHECK ((btrim(entidad_afectada) <> ''::text)),
    CONSTRAINT evento_auditoria_operacion_check CHECK ((btrim(operacion) <> ''::text)),
    CONSTRAINT evento_auditoria_origen_check CHECK ((origen = ANY (ARRAY['usuario'::text, 'sistema'::text]))),
    CONSTRAINT evento_auditoria_registro_afectado_check CHECK ((btrim(registro_afectado) <> ''::text)),
    CONSTRAINT evento_auditoria_resultado_check CHECK ((btrim(resultado) <> ''::text))
);


--
-- Name: evento_cierre_proyecto(bigint, bigint, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.evento_cierre_proyecto(p_evento bigint, p_proyecto bigint, p_actual boolean DEFAULT true) RETURNS banco.evento_auditoria
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb; v_destino text; v_clave text;
BEGIN
  SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_evento;
  IF NOT FOUND OR v_evento.operacion NOT IN ('finalizar_proyecto','cancelar_proyecto') THEN
    RAISE EXCEPTION 'El cierre requiere su evento administrativo exacto' USING ERRCODE='23514';
  END IF;
  v_evento:=banco.evento_operacion(p_evento,v_evento.operacion,'proyecto',p_proyecto,p_actual);
  v_datos:=v_evento.resultado::jsonb;
  v_destino:=CASE v_evento.operacion WHEN 'finalizar_proyecto' THEN 'finalizado' ELSE 'cancelado' END;
  IF v_datos->>'motivo' IS NULL OR (v_datos->>'motivo') !~ '[^[:space:]]'
    OR v_datos->>'estado_anterior' IS NULL
    OR jsonb_typeof(v_datos->'alcance') IS DISTINCT FROM 'object'
    OR v_evento.transicion IS DISTINCT FROM (v_datos->>'estado_anterior') || ' -> ' || v_destino
    OR (v_destino='finalizado' AND v_datos->>'estado_anterior' IS DISTINCT FROM 'en_curso')
    OR (v_destino='cancelado' AND (v_datos->>'estado_anterior') NOT IN
      ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
    RAISE EXCEPTION 'Motivo, transición o alcance de cierre incoherentes' USING ERRCODE='23514';
  END IF;
  FOREACH v_clave IN ARRAY ARRAY['alumnos','direcciones','acompanamientos','candidaturas','solicitudes','revisiones'] LOOP
    IF jsonb_typeof(v_datos #> ARRAY['alcance',v_clave]) IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Cada parte del alcance requiere una lista exacta' USING ERRCODE='23514';
    END IF;
  END LOOP;
  RETURN v_evento;
END;
$$;


--
-- Name: evento_operacion(bigint, text, text, bigint, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.evento_operacion(p_evento bigint, p_operacion text, p_entidad text, p_registro bigint, p_actual boolean DEFAULT true) RETURNS banco.evento_auditoria
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE; v_datos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=p_evento FOR SHARE;
  IF NOT FOUND OR v_evento.origen<>'usuario' OR v_evento.operacion IS DISTINCT FROM p_operacion
    OR v_evento.entidad_afectada IS DISTINCT FROM p_entidad OR v_evento.registro_afectado IS DISTINCT FROM p_registro::text THEN
    RAISE EXCEPTION 'La evidencia no corresponde a la operación y registro exactos' USING ERRCODE='23514';
  END IF;
  BEGIN v_datos := v_evento.resultado::jsonb;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'La evidencia requiere datos estructurados' USING ERRCODE='23514';
  END;
  IF jsonb_typeof(v_datos) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'La evidencia requiere un objeto' USING ERRCODE='23514';
  END IF;
  IF p_actual THEN
    IF v_datos->>'transaccion_id' IS DISTINCT FROM pg_current_xact_id()::text THEN
      RAISE EXCEPTION 'La evidencia de transición debe crearse en la misma transacción' USING ERRCODE='23514';
    END IF;
    PERFORM banco.exigir_rol(v_evento.actor_usuario_id,'administrador',true);
  END IF;
  RETURN v_evento;
END;
$$;


--
-- Name: exigir_aislamiento(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_aislamiento() RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'Las escrituras con integridad cruzada requieren aislamiento READ COMMITTED'
      USING ERRCODE='25001';
  END IF;
END;
$$;


--
-- Name: exigir_campos_proyecto(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_campos_proyecto(p_proyecto banco.proyecto) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF p_proyecto.titulo IS NULL OR p_proyecto.titulo !~ '[^[:space:]]'
    OR p_proyecto.descripcion IS NULL OR p_proyecto.descripcion !~ '[^[:space:]]'
    OR p_proyecto.problematica IS NULL OR p_proyecto.problematica !~ '[^[:space:]]'
    OR p_proyecto.objetivos IS NULL OR p_proyecto.objetivos !~ '[^[:space:]]'
    OR p_proyecto.justificacion IS NULL OR p_proyecto.justificacion !~ '[^[:space:]]'
    OR p_proyecto.alcance IS NULL OR p_proyecto.alcance !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'RF-08/RN-02: título, descripción, problemática, objetivos, justificación y alcance requieren texto no blanco para enviar/publicar'
      USING ERRCODE='23514';
  END IF;
END;
$$;


--
-- Name: FUNCTION exigir_campos_proyecto(p_proyecto banco.proyecto); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.exigir_campos_proyecto(p_proyecto banco.proyecto) IS 'RF-08/RN-02: exige contenido no blanco en los seis campos originales, incluidos tabuladores y saltos de línea solos. No impone longitud ni hace obligatorios otros campos; no reescribe contenido o revisiones.';


--
-- Name: exigir_cupo_proyecto(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_cupo_proyecto(p_proyecto banco.proyecto) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF p_proyecto.cupo_maximo_alumnos IS NULL OR p_proyecto.cupo_maximo_alumnos <= 0 THEN
    RAISE EXCEPTION 'D-02: indicar un cupo máximo de alumnos positivo antes de enviar/publicar'
      USING ERRCODE='23514';
  END IF;
END;
$$;


--
-- Name: exigir_disponibilidad_participacion(banco.proyecto, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_disponibilidad_participacion(p_proyecto banco.proyecto, p_tipo text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_total bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_proyecto.estado='pausado' THEN
    v_publicado:=p_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.exigir_publicacion_valida(v_publicado);
    IF p_tipo='alumno' THEN SELECT count(*) INTO v_total FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente';
    ELSIF p_tipo='direccion' THEN SELECT count(*) INTO v_total FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente';
    ELSE RAISE EXCEPTION 'Tipo de participación no reconocido' USING ERRCODE='22023'; END IF;
    IF v_total<>0 THEN RAISE EXCEPTION 'D-07: la pausa solo admite solicitudes y reposición del tipo faltante' USING ERRCODE='55000'; END IF;
  ELSE
    PERFORM banco.exigir_publicacion_valida(p_proyecto);
  END IF;
END;
$$;


--
-- Name: exigir_publicacion_valida(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_publicacion_valida(p_proyecto banco.proyecto) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: exigir_representante(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_representante(p_usuario bigint, p_empresa bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM id FROM banco.empresa WHERE id=p_empresa FOR UPDATE;
  PERFORM banco.exigir_rol(p_usuario,'empresa',true);
  IF NOT EXISTS (SELECT 1 FROM banco.representacion_empresa
    WHERE empresa_id=p_empresa AND usuario_id=p_usuario AND vigente) THEN
    RAISE EXCEPTION 'El usuario % no representa actualmente a la empresa %',p_usuario,p_empresa USING ERRCODE='23514';
  END IF;
END;
$$;


--
-- Name: exigir_rol(bigint, text, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.exigir_rol(p_usuario bigint, p_rol text, p_activo boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: finalizar_proyecto(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.finalizar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
  SELECT banco.cerrar_proyecto(p_proyecto,p_admin,p_motivo,'finalizado');
$$;


--
-- Name: FUNCTION finalizar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.finalizar_proyecto(p_proyecto bigint, p_admin bigint, p_motivo text) IS 'D-07: administrador activo y motivo finalizan solo En curso; cierre atómico de reservas, acompañamientos y pendientes, historia conservada. Función interna INVOKER, no autentica IDs.';


--
-- Name: impedir_reescritura_historial(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.impedir_reescritura_historial() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  RAISE EXCEPTION '%: el historial no admite %; conservar el registro original',TG_TABLE_NAME,TG_OP USING ERRCODE='55000';
END;
$$;


--
-- Name: impedir_reescritura_origen(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.impedir_reescritura_origen() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME IN ('asignacion_alumno','asignacion_direccion')
    AND OLD.estado<>'vigente'
    AND (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
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


--
-- Name: iniciar_proyecto(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.iniciar_proyecto(p_proyecto bigint, p_admin bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_datos jsonb; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto % inexistente',p_proyecto USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_proyecto.estado='en_curso' AND v_proyecto.evento_inicio_id IS NOT NULL THEN
    RETURN v_proyecto.evento_inicio_id;
  END IF;
  IF v_proyecto.estado <> 'publicado' OR v_proyecto.evento_inicio_id IS NOT NULL THEN
    RAISE EXCEPTION 'D-05: solo se inicia un proyecto publicado todavía no iniciado'
      USING ERRCODE='55000';
  END IF;
  v_datos := banco.comprobar_condiciones_inicio(v_proyecto);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,
    registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','iniciar_proyecto','proyecto',p_proyecto::text,
    'publicado -> en_curso',v_datos::text) RETURNING id INTO v_evento;
  UPDATE banco.proyecto SET estado='en_curso',evento_inicio_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;


--
-- Name: FUNCTION iniciar_proyecto(p_proyecto bigint, p_admin bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.iniciar_proyecto(p_proyecto bigint, p_admin bigint) IS 'D-05: inicio administrativo interno INVOKER, con publicación/cupo y asignaciones vigentes autorizadas exactas, evento y transición atómicos. Repetir con administrador activo devuelve el mismo evento. Sin APIs, nuevas asignaciones en curso ni cierre D-07.';


--
-- Name: instantanea_proyecto(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.instantanea_proyecto(p_proyecto bigint) RETURNS jsonb
    LANGUAGE plpgsql STRICT
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: marcar_evento_operacion_actual(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.marcar_evento_operacion_actual() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_datos jsonb;
BEGIN
  IF NEW.operacion IN ('retirar_alumno','retirar_director','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto') THEN
    PERFORM banco.exigir_aislamiento();
    BEGIN v_datos := NEW.resultado::jsonb;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'La operación requiere datos de auditoría estructurados' USING ERRCODE='23514';
    END;
    IF jsonb_typeof(v_datos) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'La operación requiere datos de auditoría objeto' USING ERRCODE='23514';
    END IF;
    -- El sello lo produce la base, no el llamador. Funciona también dentro de
    -- subtransacciones; un evento confirmado en otra transacción no habilita
    -- posteriormente una nueva transición. No altera auditoría anterior.
    NEW.fecha := clock_timestamp();
    NEW.resultado := (v_datos || jsonb_build_object('transaccion_id',pg_current_xact_id()::text))::text;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: marcar_notificacion_leida(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.marcar_notificacion_leida(p_notificacion bigint, p_usuario bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_aviso banco.notificacion%ROWTYPE;v_rol text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_aviso FROM banco.notificacion WHERE id=p_notificacion FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aviso inexistente' USING ERRCODE='23503'; END IF;
  IF v_aviso.destinatario_usuario_id IS DISTINCT FROM p_usuario THEN
    RAISE EXCEPTION 'Solo el destinatario puede leer el aviso' USING ERRCODE='23514'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_usuario;
  PERFORM banco.exigir_rol(p_usuario,v_rol,true);
  IF v_aviso.fecha_lectura IS NULL THEN
    UPDATE banco.notificacion SET fecha_lectura=greatest(clock_timestamp(),fecha)
      WHERE id=p_notificacion RETURNING fecha_lectura INTO v_aviso.fecha_lectura;
  END IF;
  RETURN v_aviso.fecha_lectura;
END;
$$;


--
-- Name: normalizar_habilidad(text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.normalizar_habilidad(p_nombre text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT lower(translate(btrim(regexp_replace(coalesce(p_nombre,''),'\s+',' ','g')),
    'ÁÉÍÓÚÜÑáéíóúüñ','AEIOUUNaeiouun'));
$$;


--
-- Name: notificar_evento(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.notificar_evento() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $_$
DECLARE v_id bigint; v_proyecto bigint; v_titular bigint; v_destinos bigint[]:='{}';
  v_empresa boolean:=false; v_admin boolean:=false; v_participantes boolean:=false;
  v_mensaje text;
BEGIN
  IF NEW.operacion NOT IN ('enviar_proyecto','resolver_publicacion','presentar_candidatura',
    'cancelar_candidatura','solicitar_direccion','cancelar_solicitud_direccion',
    'evaluar_candidatura','preseleccionar_candidatura','resolver_candidatura','resolver_direccion',
    'iniciar_proyecto','retirar_alumno','retirar_director','pausar_proyecto',
    'reanudar_proyecto','finalizar_proyecto','cancelar_proyecto','crear_cuenta',
    'crear_empresa_con_representante','relevar_representante','cambiar_estado_cuenta') THEN
    RETURN NEW;
  END IF;
  IF NEW.registro_afectado !~ '^-?[0-9]+$' THEN RETURN NEW; END IF;
  BEGIN v_id:=NEW.registro_afectado::bigint;
  EXCEPTION WHEN numeric_value_out_of_range THEN RETURN NEW; END;
  CASE NEW.entidad_afectada
    WHEN 'proyecto' THEN SELECT id INTO v_proyecto FROM banco.proyecto WHERE id=v_id;
    WHEN 'candidatura' THEN
      SELECT proyecto_id,alumno_id INTO v_proyecto,v_titular FROM banco.candidatura WHERE id=v_id;
    WHEN 'solicitud_direccion' THEN
      SELECT proyecto_id,profesor_id INTO v_proyecto,v_titular FROM banco.solicitud_direccion WHERE id=v_id;
    WHEN 'evaluacion_candidato' THEN
      SELECT c.proyecto_id,c.alumno_id INTO v_proyecto,v_titular FROM banco.evaluacion_candidato e
        JOIN banco.candidatura c ON c.id=e.candidatura_id WHERE e.id=v_id;
    WHEN 'asignacion_alumno' THEN
      SELECT proyecto_id,alumno_id INTO v_proyecto,v_titular FROM banco.asignacion_alumno WHERE id=v_id;
    WHEN 'asignacion_direccion' THEN
      SELECT proyecto_id,profesor_id INTO v_proyecto,v_titular FROM banco.asignacion_direccion WHERE id=v_id;
    WHEN 'usuario' THEN v_titular:=v_id;
    WHEN 'empresa' THEN
      SELECT usuario_id INTO v_titular FROM banco.representacion_empresa WHERE empresa_id=v_id AND vigente;
    ELSE RETURN NEW;
  END CASE;
  CASE NEW.operacion
    WHEN 'enviar_proyecto','solicitar_direccion','cancelar_solicitud_direccion' THEN v_admin:=true;
    WHEN 'presentar_candidatura','cancelar_candidatura','resolver_publicacion' THEN v_empresa:=true;
    WHEN 'preseleccionar_candidatura' THEN
      v_admin:=true;v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'evaluar_candidatura' THEN v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'resolver_candidatura','resolver_direccion','retirar_alumno','retirar_director' THEN
      v_empresa:=true;v_destinos:=array_append(v_destinos,v_titular);
    WHEN 'iniciar_proyecto','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto' THEN
      v_empresa:=true;v_participantes:=true;
    ELSE v_destinos:=array_append(v_destinos,v_titular);
  END CASE;
  IF v_empresa AND v_proyecto IS NOT NULL THEN
    v_destinos:=v_destinos || ARRAY(SELECT r.usuario_id FROM banco.proyecto p
      JOIN banco.representacion_empresa r ON r.empresa_id=p.empresa_id AND r.vigente WHERE p.id=v_proyecto);
  END IF;
  IF v_admin THEN
    v_destinos:=v_destinos || ARRAY(SELECT id FROM banco.usuario WHERE rol_principal='administrador' AND estado_cuenta='activa');
  END IF;
  IF v_participantes AND v_proyecto IS NOT NULL THEN
    -- El evento raíz se inserta antes de cerrar sus hijos. En el cierre quedan
    -- incluidos todos los titulares afectados, sin un aviso por cada hijo.
    v_destinos:=v_destinos || ARRAY(SELECT alumno_id FROM banco.asignacion_alumno
      WHERE proyecto_id=v_proyecto AND estado='vigente'
      UNION SELECT profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=v_proyecto AND estado='vigente'
      UNION SELECT alumno_id FROM banco.candidatura WHERE proyecto_id=v_proyecto
        AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=v_proyecto AND estado='pendiente');
  END IF;
  v_mensaje:=CASE NEW.operacion
    WHEN 'enviar_proyecto' THEN 'Hay un proyecto pendiente de revisión.'
    WHEN 'resolver_publicacion' THEN 'Se resolvió la revisión de tu proyecto.'
    WHEN 'presentar_candidatura' THEN 'Tu proyecto recibió una candidatura.'
    WHEN 'cancelar_candidatura' THEN 'Se canceló una candidatura de tu proyecto.'
    WHEN 'solicitar_direccion' THEN 'Hay una solicitud de dirección pendiente.'
    WHEN 'cancelar_solicitud_direccion' THEN 'Se canceló una solicitud de dirección pendiente.'
    WHEN 'evaluar_candidatura' THEN 'Tu candidatura tiene una nueva evaluación.'
    WHEN 'preseleccionar_candidatura' THEN 'Se preseleccionó una candidatura para autorización.'
    WHEN 'resolver_candidatura' THEN 'Se resolvió una candidatura relacionada contigo.'
    WHEN 'resolver_direccion' THEN 'Se resolvió una solicitud de dirección relacionada contigo.'
    WHEN 'iniciar_proyecto' THEN 'Se confirmó el inicio de un proyecto relacionado contigo.'
    WHEN 'retirar_alumno' THEN 'Se registró un retiro de alumno.'
    WHEN 'retirar_director' THEN 'Se registró un retiro de dirección.'
    WHEN 'pausar_proyecto' THEN 'Un proyecto relacionado contigo quedó pausado.'
    WHEN 'reanudar_proyecto' THEN 'Se confirmó la reanudación de un proyecto relacionado contigo.'
    WHEN 'finalizar_proyecto' THEN 'Se finalizó un proyecto relacionado contigo.'
    WHEN 'cancelar_proyecto' THEN 'Se canceló un proyecto relacionado contigo.'
    ELSE 'Se actualizó tu cuenta o representación empresarial.' END;
  INSERT INTO banco.notificacion(destinatario_usuario_id,evento_id,mensaje,fecha)
    SELECT DISTINCT u.id,NEW.id,v_mensaje,clock_timestamp() FROM banco.usuario u
    WHERE u.id=ANY(v_destinos) AND u.estado_cuenta='activa'
      AND u.id IS DISTINCT FROM NEW.actor_usuario_id
    ON CONFLICT(evento_id,destinatario_usuario_id) DO NOTHING;
  RETURN NEW;
END;
$_$;


--
-- Name: participantes_vigentes(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.participantes_vigentes(p_proyecto bigint) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
 SELECT jsonb_build_object('alumnos',COALESCE((SELECT jsonb_agg(id ORDER BY id) FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'),'[]'::jsonb),
   'direcciones',COALESCE((SELECT jsonb_agg(id ORDER BY id) FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente'),'[]'::jsonb));
$$;


--
-- Name: preseleccionar_candidatura(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.preseleccionar_candidatura(p_candidatura bigint, p_representante bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_e banco.evaluacion_candidato%ROWTYPE;
  v_pre banco.evento_auditoria%ROWTYPE; v_evento bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_representante(p_representante,v_p.empresa_id);
  PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
  IF v_c.estado NOT IN ('evaluada','preseleccionada') OR v_c.evaluacion_vigente_id IS NULL THEN
    RAISE EXCEPTION 'D-08: preseleccionar requiere evaluación completa previa' USING ERRCODE='55000';
  END IF;
  SELECT * INTO v_e FROM banco.evaluacion_candidato WHERE id=v_c.evaluacion_vigente_id;
  PERFORM banco.comprobar_evaluacion_d08(v_e.id);
  IF v_e.version_rubrica IS DISTINCT FROM 1 OR v_e.candidatura_id<>v_c.id OR v_e.recomendacion<>'recomendada'
    OR EXISTS(SELECT 1 FROM banco.evaluacion_candidato WHERE candidatura_id=v_c.id AND version_rubrica=1 AND id>v_e.id) THEN
    RAISE EXCEPTION 'D-08: la última evaluación debe recomendar al candidato' USING ERRCODE='23514';
  END IF;
  IF v_c.estado='preseleccionada' AND v_c.evento_preseleccion_id IS NOT NULL THEN
    SELECT * INTO v_pre FROM banco.evento_auditoria WHERE id=v_c.evento_preseleccion_id;
    IF NOT FOUND OR v_pre.operacion<>'preseleccionar_candidatura' OR v_pre.entidad_afectada<>'candidatura'
      OR v_pre.registro_afectado<>v_c.id::text OR v_pre.origen<>'usuario'
      OR v_pre.resultado::jsonb IS DISTINCT FROM jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id) THEN
      RAISE EXCEPTION 'La evidencia de preselección no corresponde a la evaluación vigente' USING ERRCODE='23514';
    END IF;
    RETURN v_c.evento_preseleccion_id;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_representante,'usuario','preseleccionar_candidatura','candidatura',p_candidatura::text,'evaluada -> preseleccionada',
      jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id)::text) RETURNING id INTO v_evento;
  UPDATE banco.candidatura SET estado='preseleccionada',evento_preseleccion_id=v_evento WHERE id=p_candidatura;
  RETURN v_evento;
END;
$$;


--
-- Name: presentar_candidatura(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.presentar_candidatura(p_proyecto bigint, p_alumno bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_candidatura bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_alumno FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de alumno existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_alumno,'alumno',true);
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,'alumno');
  INSERT INTO banco.candidatura(alumno_id,proyecto_id,estado)
  VALUES(p_alumno,p_proyecto,'pendiente_evaluacion') RETURNING id INTO v_candidatura;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_alumno,'usuario','presentar_candidatura','candidatura',v_candidatura::text,
    'sin candidatura -> pendiente_evaluacion',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_candidatura;
END;
$$;


--
-- Name: FUNCTION presentar_candidatura(p_proyecto bigint, p_alumno bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.presentar_candidatura(p_proyecto bigint, p_alumno bigint) IS 'Envío interno CU-05: alumno activo, publicación válida, candidatura pendiente y auditoría atómicas; máximo tres activas y sin duplicados. No autorización ni cancelación.';


--
-- Name: proteger_aprobacion_direccion(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_aprobacion_direccion() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=NEW.profesor_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profesor inexistente' USING ERRCODE='23503'; END IF;
  IF TG_OP='UPDATE' AND OLD.estado='aprobada' AND NEW.estado<>'aprobada' THEN
    RAISE EXCEPTION 'D-06: la solicitud aprobada conserva su origen autorizado; las bajas se registran en la asignación'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_asignaciones_iniciadas(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_asignaciones_iniciadas() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_estado text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT estado INTO v_estado FROM banco.proyecto WHERE id=NEW.proyecto_id;
  IF TG_OP='UPDATE' AND NEW.evento_cierre_id IS NOT NULL THEN
    -- tr_03 valida el cierre exacto y el control diferido exige su proyecto terminal.
    RETURN NEW;
  END IF;
  IF v_estado IN ('en_curso','pausado') THEN
    IF TG_OP='INSERT' THEN
      IF v_estado='en_curso' THEN RAISE EXCEPTION 'D-07: no se habilitan incorporaciones generales en curso' USING ERRCODE='55000'; END IF;
    ELSIF (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
      IF OLD.estado<>'vigente' OR NEW.estado<>'revocada' OR NEW.evento_retiro_id IS NULL
        OR OLD.evento_retiro_id IS NOT NULL
        OR (to_jsonb(NEW)-ARRAY['estado','fin','evento_retiro_id','resultado_decision'])
          IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['estado','fin','evento_retiro_id','resultado_decision']) THEN
        RAISE EXCEPTION 'D-07: las asignaciones iniciadas solo cambian mediante retiro administrativo con evidencia exacta'
          USING ERRCODE='55000';
      END IF;
      -- El trigger tr_02 verifica a continuación la evidencia completa.
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_candidatura_cancelada(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_candidatura_cancelada() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF OLD.estado='cancelada' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: la candidatura cancelada conserva su historial; no se reabre ni se reescribe'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_criterio_d08(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_criterio_d08() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_def jsonb;
BEGIN
  IF TG_OP<>'INSERT' AND OLD.codigo IS NOT NULL THEN
    IF TG_OP='DELETE' OR NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'La rúbrica D-08 conserva su definición; un cambio requiere otra versión' USING ERRCODE='55000';
    END IF;
  END IF;
  IF TG_OP<>'DELETE' AND NEW.codigo IS NOT NULL THEN
    v_def:=banco.definicion_criterio_d08(NEW.codigo);
    IF NEW.nombre IS DISTINCT FROM v_def->>'nombre' OR NEW.descripcion IS DISTINCT FROM v_def->>'descripcion'
      OR NEW.escala IS DISTINCT FROM v_def->>'escala' OR NEW.ponderacion IS DISTINCT FROM 1::numeric THEN
      RAISE EXCEPTION 'Definición de rúbrica D-08 incoherente' USING ERRCODE='23514';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_notificacion(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_notificacion() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Los avisos se conservan' USING ERRCODE='55000'; END IF;
  IF (to_jsonb(NEW)-'fecha_lectura') IS DISTINCT FROM (to_jsonb(OLD)-'fecha_lectura')
    OR (OLD.fecha_lectura IS NOT NULL AND NEW.fecha_lectura IS DISTINCT FROM OLD.fecha_lectura) THEN
    RAISE EXCEPTION 'Solo se permite registrar la primera lectura del aviso' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_publicacion_proyecto(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_publicacion_proyecto() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE; v_evento banco.evento_auditoria%ROWTYPE;
  v_retiro banco.evento_auditoria%ROWTYPE; v_previo banco.evento_auditoria%ROWTYPE;
  v_datos jsonb; v_esperado jsonb; v_participantes jsonb; v_retiro_valido boolean;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_OP='UPDATE' AND OLD.estado IN ('finalizado','cancelado') THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'El proyecto cerrado conserva su historia; no se reabre ni modifica' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.estado IN ('finalizado','cancelado') THEN
    IF TG_OP<>'UPDATE' OR NEW.evento_cierre_id IS NULL THEN
      RAISE EXCEPTION 'D-07: el cierre requiere su operación administrativa específica' USING ERRCODE='55000';
    END IF;
    IF (NEW.estado='finalizado' AND OLD.estado<>'en_curso')
      OR (NEW.estado='cancelado' AND OLD.estado NOT IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado')) THEN
      RAISE EXCEPTION 'El estado anterior no admite este cierre administrativo' USING ERRCODE='55000';
    END IF;
    IF (to_jsonb(NEW)-ARRAY['estado','evento_cierre_id']) IS DISTINCT FROM
      (to_jsonb(OLD)-ARRAY['estado','evento_cierre_id']) THEN
      RAISE EXCEPTION 'El cierre conserva contenido, autoría, publicación y eventos anteriores' USING ERRCODE='55000';
    END IF;
    v_evento:=banco.evento_cierre_proyecto(NEW.evento_cierre_id,NEW.id,true);
    IF v_evento.resultado::jsonb->>'estado_anterior' IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'El cierre conserva el estado anterior exacto' USING ERRCODE='23514';
    END IF;
    PERFORM banco.comprobar_cierre_proyecto(NEW,true);
    RETURN NEW;
  END IF;
  IF NEW.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'La evidencia de cierre solo pertenece a un proyecto terminal' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' AND (NEW.estado IN ('en_curso','pausado') OR NEW.evento_inicio_id IS NOT NULL OR NEW.evento_estado_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Primero se publica e inicia el proyecto mediante sus operaciones protegidas' USING ERRCODE='55000';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF OLD.revision_publicada_id IS NOT NULL THEN
      IF NEW.revision_publicada_id IS DISTINCT FROM OLD.revision_publicada_id
        OR banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
        RAISE EXCEPTION 'D-07: no se modifica contenido/cupo ni se sustituye la versión publicada' USING ERRCODE='55000';
      END IF;
      IF OLD.evento_inicio_id IS NOT NULL THEN
        IF NEW.evento_inicio_id IS DISTINCT FROM OLD.evento_inicio_id THEN
          RAISE EXCEPTION 'El primer inicio y su evidencia se conservan' USING ERRCODE='55000';
        END IF;
        IF NEW.estado=OLD.estado AND NEW.evento_estado_id IS NOT DISTINCT FROM OLD.evento_estado_id THEN RETURN NEW; END IF;
        IF NOT ((OLD.estado='en_curso' AND NEW.estado='pausado') OR (OLD.estado='pausado' AND NEW.estado='en_curso')) THEN
          RAISE EXCEPTION 'El proyecto iniciado solo admite pausa por retiro o reanudación administrativa protegida' USING ERRCODE='55000';
        END IF;
        IF NEW.evento_estado_id IS NULL OR NEW.evento_estado_id IS NOT DISTINCT FROM OLD.evento_estado_id THEN
          RAISE EXCEPTION 'La pausa o reanudación requiere evidencia nueva de la operación' USING ERRCODE='23514';
        END IF;
        IF OLD.estado='en_curso' AND NEW.estado='pausado' THEN
          v_evento:=banco.evento_operacion(NEW.evento_estado_id,'pausar_proyecto','proyecto',NEW.id,true);
          IF v_evento.transicion IS DISTINCT FROM 'en_curso -> pausado' THEN RAISE EXCEPTION 'Transición de pausa incoherente' USING ERRCODE='23514'; END IF;
          v_datos:=v_evento.resultado::jsonb;
          v_participantes:=banco.participantes_vigentes(NEW.id);
          IF jsonb_array_length(v_participantes->'alumnos')>0 AND jsonb_array_length(v_participantes->'direcciones')>0 THEN
            RAISE EXCEPTION 'La pausa automática requiere pérdida de un participante mínimo' USING ERRCODE='23514';
          END IF;
          SELECT * INTO v_retiro FROM banco.evento_auditoria WHERE id::text=v_datos->>'retiro_evento_id';
          IF NOT FOUND OR v_retiro.operacion NOT IN ('retirar_alumno','retirar_director') THEN
            RAISE EXCEPTION 'La pausa requiere su retiro administrativo causante' USING ERRCODE='23514';
          END IF;
          v_retiro:=banco.evento_operacion(v_retiro.id,v_retiro.operacion,v_retiro.entidad_afectada,v_retiro.registro_afectado::bigint,true);
          IF v_retiro.operacion='retirar_alumno' THEN
            SELECT EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE id::text=v_retiro.registro_afectado
              AND proyecto_id=NEW.id AND estado='revocada' AND evento_retiro_id=v_retiro.id) INTO v_retiro_valido;
          ELSE
            SELECT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE id::text=v_retiro.registro_afectado
              AND proyecto_id=NEW.id AND estado='revocada' AND evento_retiro_id=v_retiro.id) INTO v_retiro_valido;
          END IF;
          IF NOT v_retiro_valido OR v_retiro.actor_usuario_id IS DISTINCT FROM v_evento.actor_usuario_id THEN
            RAISE EXCEPTION 'La pausa conserva el administrador y proyecto del retiro exacto' USING ERRCODE='23514';
          END IF;
          v_esperado:=v_participantes || jsonb_build_object('retiro_evento_id',v_retiro.id,
            'evento_estado_anterior_id',OLD.evento_estado_id,'transaccion_id',pg_current_xact_id()::text);
        ELSIF OLD.estado='pausado' AND NEW.estado='en_curso' THEN
          v_evento:=banco.evento_operacion(NEW.evento_estado_id,'reanudar_proyecto','proyecto',NEW.id,true);
          IF v_evento.transicion IS DISTINCT FROM 'pausado -> en_curso' THEN RAISE EXCEPTION 'Transición de reanudación incoherente' USING ERRCODE='23514'; END IF;
          v_previo:=banco.evento_operacion(OLD.evento_estado_id,'pausar_proyecto','proyecto',NEW.id,false);
          v_publicado:=NEW; v_publicado.estado:='publicado';
          v_esperado:=banco.comprobar_condiciones_inicio(v_publicado) || jsonb_build_object(
            'evento_estado_anterior_id',OLD.evento_estado_id,'transaccion_id',pg_current_xact_id()::text);
        ELSE
          RAISE EXCEPTION 'El proyecto iniciado solo admite pausa por retiro o reanudación administrativa protegida' USING ERRCODE='55000';
        END IF;
        IF v_evento.resultado::jsonb IS DISTINCT FROM v_esperado THEN
          RAISE EXCEPTION 'La evidencia no coincide con participantes y condiciones de la transición' USING ERRCODE='23514';
        END IF;
        RETURN NEW;
      END IF;
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado<>'en_curso' THEN
        RAISE EXCEPTION 'D-07: el ciclo posterior requiere su flujo específico' USING ERRCODE='55000';
      END IF;
    ELSIF OLD.estado NOT IN ('borrador','en_correccion')
      AND banco.contenido_proyecto(NEW) IS DISTINCT FROM banco.contenido_proyecto(OLD) THEN
      RAISE EXCEPTION 'El contenido enviado solo se corrige después de una devolución' USING ERRCODE='55000';
    END IF;
  END IF;
  IF NEW.estado='en_curso' THEN
    IF TG_OP<>'UPDATE' OR OLD.estado<>'publicado' OR OLD.evento_inicio_id IS NOT NULL
      OR NEW.evento_inicio_id IS NULL OR NEW.evento_estado_id IS NOT NULL THEN
      RAISE EXCEPTION 'Iniciar requiere proyecto publicado y evidencia inicial exacta' USING ERRCODE='23514';
    END IF;
    v_publicado:=NEW; v_publicado.estado:='publicado';
    v_datos:=banco.comprobar_condiciones_inicio(v_publicado);
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=NEW.evento_inicio_id FOR SHARE;
    IF NOT FOUND OR v_evento.origen<>'usuario' OR v_evento.operacion<>'iniciar_proyecto'
      OR v_evento.entidad_afectada<>'proyecto' OR v_evento.registro_afectado<>NEW.id::text
      OR v_evento.transicion IS DISTINCT FROM 'publicado -> en_curso' OR v_evento.resultado IS DISTINCT FROM v_datos::text THEN
      RAISE EXCEPTION 'La evidencia de inicio requiere proyecto y condiciones exactas' USING ERRCODE='23514';
    END IF;
    PERFORM banco.exigir_rol(v_evento.actor_usuario_id,'administrador',true);
    RETURN NEW;
  END IF;
  IF NEW.evento_inicio_id IS NOT NULL OR NEW.evento_estado_id IS NOT NULL OR NEW.estado='pausado' THEN
    RAISE EXCEPTION 'La evidencia de inicio o pausa solo pertenece a sus transiciones protegidas' USING ERRCODE='23514';
  END IF;
  IF NEW.revision_publicada_id IS NOT NULL AND NEW.estado<>'publicado' THEN
    RAISE EXCEPTION 'La revisión publicada anterior al inicio requiere estado publicado' USING ERRCODE='23514';
  END IF;
  IF NEW.estado='publicado' OR NEW.revision_publicada_id IS NOT NULL THEN PERFORM banco.exigir_publicacion_valida(NEW); END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_rechazo_definitivo(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_rechazo_definitivo() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF OLD.estado='rechazada' AND NEW IS DISTINCT FROM OLD
    OR TG_TABLE_NAME='proyecto' AND OLD.estado='rechazado' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: un registro rechazado conserva su historial; no se reabre ni se reescribe' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_requisitos_proyecto(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_requisitos_proyecto() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: proteger_revision_publicada(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_revision_publicada() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF NEW.estado_revision IS DISTINCT FROM OLD.estado_revision
    AND EXISTS (SELECT 1 FROM banco.proyecto WHERE revision_publicada_id=OLD.id) THEN
    RAISE EXCEPTION 'D-07 pendiente: el resultado de la revisión publicada no puede reescribirse' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: proteger_solicitud_cancelada(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.proteger_solicitud_cancelada() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF OLD.estado='cancelada' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'D-07: la solicitud cancelada conserva su historial y no se reabre'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: reanudar_proyecto(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.reanudar_proyecto(p_proyecto bigint, p_admin bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE;
  v_evento bigint; v_datos jsonb; v_previo banco.evento_auditoria%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_proyecto.estado='en_curso' AND v_proyecto.evento_estado_id IS NOT NULL THEN
    SELECT * INTO v_previo FROM banco.evento_auditoria WHERE id=v_proyecto.evento_estado_id;
    IF v_previo.operacion='reanudar_proyecto' THEN RETURN v_previo.id; END IF;
  END IF;
  IF v_proyecto.estado<>'pausado' OR v_proyecto.evento_estado_id IS NULL THEN
    RAISE EXCEPTION 'Solo se reanuda un proyecto pausado mediante confirmación administrativa' USING ERRCODE='55000';
  END IF;
  v_previo:=banco.evento_operacion(v_proyecto.evento_estado_id,'pausar_proyecto','proyecto',v_proyecto.id,false);
  v_publicado:=v_proyecto; v_publicado.estado:='publicado';
  v_datos:=banco.comprobar_condiciones_inicio(v_publicado) || jsonb_build_object('evento_estado_anterior_id',v_proyecto.evento_estado_id);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario','reanudar_proyecto','proyecto',p_proyecto::text,'pausado -> en_curso',v_datos::text)
  RETURNING id INTO v_evento;
  UPDATE banco.proyecto SET estado='en_curso',evento_estado_id=v_evento WHERE id=p_proyecto;
  RETURN v_evento;
END;
$$;


--
-- Name: FUNCTION reanudar_proyecto(p_proyecto bigint, p_admin bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.reanudar_proyecto(p_proyecto bigint, p_admin bigint) IS 'Confirmación administrativa interna después de reponer mínimos autorizados; revalida publicación, cupo, carga y orígenes, conserva primer inicio e historial. Sin etapas D-08, APIs ni avisos.';


--
-- Name: relevar_representante(bigint, bigint, text, text, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.relevar_representante(p_admin bigint, p_empresa bigint, p_nombre text, p_correo text, p_hash text, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION relevar_representante(p_admin bigint, p_empresa bigint, p_nombre text, p_correo text, p_hash text, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.relevar_representante(p_admin bigint, p_empresa bigint, p_nombre text, p_correo text, p_hash text, p_motivo text) IS 'D-09/D-10: nueva cuenta empresarial y relevo atómico con historia, cuenta anterior inactiva y vínculo permanente conservado. Hash recibido opaco; sin entrega de claves ni autenticación.';


--
-- Name: resolver_candidatura(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.resolver_candidatura(p_candidatura bigint, p_admin bigint, p_resultado text, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_c banco.candidatura%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_e banco.evaluacion_candidato%ROWTYPE;
  v_pre banco.evento_auditoria%ROWTYPE; v_decision bigint; v_asignacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_resultado IS NULL OR p_resultado NOT IN ('aprobada','rechazada') OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Resolver requiere aprobación/rechazo y motivo no blanco' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_c FROM banco.candidatura WHERE id=p_candidatura FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_c.alumno_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_c.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_c.estado=p_resultado THEN
    SELECT id INTO v_decision FROM banco.decision_administrativa WHERE candidatura_id=p_candidatura AND resultado=p_resultado ORDER BY id DESC LIMIT 1;
    IF v_decision IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('candidatura',p_candidatura);
      RETURN v_decision;
    END IF;
  END IF;
  IF v_c.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada')
    OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE candidatura_id=p_candidatura)
    OR EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE candidatura_id=p_candidatura) THEN
    RAISE EXCEPTION 'La candidatura ya fue resuelta o cerrada' USING ERRCODE='55000';
  END IF;
  IF p_resultado='aprobada' THEN
    PERFORM banco.exigir_rol(v_c.alumno_id,'alumno',true);
    PERFORM banco.exigir_disponibilidad_participacion(v_p,'alumno');
    IF v_c.estado<>'preseleccionada' OR v_c.evaluacion_vigente_id IS NULL OR v_c.evento_preseleccion_id IS NULL THEN
      RAISE EXCEPTION 'D-08: autorizar requiere evaluación y preselección empresarial' USING ERRCODE='55000';
    END IF;
    SELECT * INTO v_e FROM banco.evaluacion_candidato WHERE id=v_c.evaluacion_vigente_id;
    PERFORM banco.comprobar_evaluacion_d08(v_e.id);
    SELECT * INTO v_pre FROM banco.evento_auditoria WHERE id=v_c.evento_preseleccion_id;
    IF v_e.version_rubrica IS DISTINCT FROM 1 OR v_e.recomendacion<>'recomendada'
      OR EXISTS(SELECT 1 FROM banco.evaluacion_candidato WHERE candidatura_id=v_c.id AND version_rubrica=1 AND id>v_e.id)
      OR v_pre.operacion<>'preseleccionar_candidatura' OR v_pre.entidad_afectada<>'candidatura'
      OR v_pre.registro_afectado<>p_candidatura::text OR v_pre.origen<>'usuario'
      OR v_pre.resultado::jsonb IS DISTINCT FROM jsonb_build_object('proyecto_id',v_p.id,'evaluacion_id',v_e.id) THEN
      RAISE EXCEPTION 'La preselección no corresponde a la evaluación vigente' USING ERRCODE='23514';
    END IF;
  ELSIF v_p.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'No se resuelven nuevas decisiones en un proyecto cerrado' USING ERRCODE='55000';
  END IF;
  UPDATE banco.candidatura SET estado=p_resultado WHERE id=p_candidatura;
  INSERT INTO banco.decision_administrativa(administrador_usuario_id,candidatura_id,fecha,resultado,justificacion)
    VALUES(p_admin,p_candidatura,clock_timestamp(),p_resultado,p_motivo) RETURNING id INTO v_decision;
  IF p_resultado='aprobada' THEN
    INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
      VALUES(p_candidatura,v_decision,v_c.alumno_id,v_p.id,clock_timestamp()) RETURNING id INTO v_asignacion;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','resolver_candidatura','candidatura',p_candidatura::text,v_c.estado || ' -> ' || p_resultado,
      jsonb_build_object('proyecto_id',v_p.id,'decision_id',v_decision,'asignacion_id',v_asignacion,
        'evaluacion_id',v_c.evaluacion_vigente_id,'preseleccion_evento_id',v_c.evento_preseleccion_id,'motivo',p_motivo)::text);
  RETURN v_decision;
END;
$$;


--
-- Name: FUNCTION resolver_candidatura(p_candidatura bigint, p_admin bigint, p_resultado text, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.resolver_candidatura(p_candidatura bigint, p_admin bigint, p_resultado text, p_motivo text) IS 'D-08: aprobación administrativa posterior a evaluación/preselección, decisión y asignación atómicas; rechazo desde fuente activa. Inicio efectivo en autorización, límites006 y publicación013 conservados.';


--
-- Name: resolver_direccion(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.resolver_direccion(p_solicitud bigint, p_admin bigint, p_resultado text, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_s banco.solicitud_direccion%ROWTYPE; v_p banco.proyecto%ROWTYPE; v_decision bigint; v_asignacion bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_resultado IS NULL OR p_resultado NOT IN ('aprobada','rechazada') OR p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'Resolver requiere aprobación/rechazo y motivo no blanco' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_s FROM banco.solicitud_direccion WHERE id=p_solicitud FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud de dirección inexistente' USING ERRCODE='23503'; END IF;
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_s.profesor_id FOR UPDATE;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=v_s.proyecto_id FOR UPDATE;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_s.estado=p_resultado THEN
    SELECT id INTO v_decision FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_solicitud AND resultado=p_resultado ORDER BY id DESC LIMIT 1;
    IF v_decision IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('direccion',p_solicitud);
      RETURN v_decision;
    END IF;
  END IF;
  IF v_s.estado<>'pendiente' OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE solicitud_direccion_id=p_solicitud)
    OR EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_solicitud) THEN
    RAISE EXCEPTION 'La solicitud de dirección ya fue resuelta o cerrada' USING ERRCODE='55000';
  END IF;
  IF p_resultado='aprobada' THEN
    PERFORM banco.exigir_rol(v_s.profesor_id,'profesor',true);
    PERFORM banco.exigir_disponibilidad_participacion(v_p,'direccion');
    IF v_s.experiencia_aplicable IS NULL OR v_s.experiencia_aplicable !~ '[^[:space:]]'
      OR v_s.justificacion IS NULL OR v_s.justificacion !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'RF-28: dirección requiere experiencia y justificación no blancas' USING ERRCODE='23514';
    END IF;
  ELSIF v_p.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'No se resuelven nuevas decisiones en un proyecto cerrado' USING ERRCODE='55000';
  END IF;
  UPDATE banco.solicitud_direccion SET estado=p_resultado WHERE id=p_solicitud;
  INSERT INTO banco.decision_administrativa(administrador_usuario_id,solicitud_direccion_id,fecha,resultado,justificacion)
    VALUES(p_admin,p_solicitud,clock_timestamp(),p_resultado,p_motivo) RETURNING id INTO v_decision;
  IF p_resultado='aprobada' THEN
    INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES(p_solicitud,v_decision,v_s.profesor_id,v_p.id,clock_timestamp()) RETURNING id INTO v_asignacion;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','resolver_direccion','solicitud_direccion',p_solicitud::text,v_s.estado || ' -> ' || p_resultado,
      jsonb_build_object('proyecto_id',v_p.id,'decision_id',v_decision,'asignacion_id',v_asignacion,'motivo',p_motivo)::text);
  RETURN v_decision;
END;
$$;


--
-- Name: FUNCTION resolver_direccion(p_solicitud bigint, p_admin bigint, p_resultado text, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.resolver_direccion(p_solicitud bigint, p_admin bigint, p_resultado text, p_motivo text) IS 'D-08: administrador aprueba/rechaza dirección pendiente con motivo; experiencia/justificación y límites se comprueban al aprobar, sin evaluación empresarial de profesor.';


--
-- Name: resolver_publicacion(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.resolver_publicacion(p_revision bigint, p_admin bigint, p_resultado text, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: FUNCTION resolver_publicacion(p_revision bigint, p_admin bigint, p_resultado text, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.resolver_publicacion(p_revision bigint, p_admin bigint, p_resultado text, p_motivo text) IS 'Función interna del propietario: aprobar valida el cupo propuesto de la revisión v2 exacta con administrador activo, motivo y auditoría atómicos. Corrección/rechazo de revisiones v1 preserva historia; sin inicio ni cambio publicado.';


--
-- Name: retirar_alumno(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.retirar_alumno(p_asignacion bigint, p_admin bigint, p_motivo text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
 SELECT banco.retirar_asignacion('alumno',p_asignacion,p_admin,p_motivo);
$$;


--
-- Name: FUNCTION retirar_alumno(p_asignacion bigint, p_admin bigint, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.retirar_alumno(p_asignacion bigint, p_admin bigint, p_motivo text) IS 'Retiro interno por administrador activo y motivo, con cierre de sus acompañamientos, reserva liberada y pausa si pierde el mínimo. Idempotente para el retiro ya registrado.';


--
-- Name: retirar_asignacion(text, bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.retirar_asignacion(p_tipo text, p_asignacion bigint, p_admin bigint, p_motivo text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $_$
DECLARE v_tabla text; v_perfil text; v_columna text; v_origen text; v_operacion text;
  v_lectura record; v_asignacion record; v_participante bigint; v_proyecto banco.proyecto%ROWTYPE;
  v_fecha timestamptz; v_evento bigint; v_pausa bigint; v_vinculo banco.acompanamiento%ROWTYPE; v_participantes jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo='alumno' THEN
    v_tabla:='asignacion_alumno'; v_perfil:='alumno'; v_columna:='alumno_id'; v_origen:='candidatura_id'; v_operacion:='retirar_alumno';
  ELSIF p_tipo='direccion' THEN
    v_tabla:='asignacion_direccion'; v_perfil:='profesor'; v_columna:='profesor_id'; v_origen:='solicitud_direccion_id'; v_operacion:='retirar_director';
  ELSE RAISE EXCEPTION 'Tipo de retiro no reconocido' USING ERRCODE='22023'; END IF;
  IF p_motivo IS NULL OR p_motivo !~ '[^[:space:]]' THEN RAISE EXCEPTION 'El retiro requiere motivo no blanco' USING ERRCODE='23514'; END IF;
  -- Los IDs de origen son inmutables. Leerlos no retiene un padre mientras
  -- espera Proyecto: dos retiros de tipos distintos no forman un ciclo al
  -- cerrar sus acompañamientos. Revalidar la asignación después del bloqueo.
  EXECUTE format('SELECT * FROM banco.%I WHERE id=$1',v_tabla) INTO v_lectura USING p_asignacion;
  IF v_lectura.id IS NULL THEN RAISE EXCEPTION 'Asignación inexistente' USING ERRCODE='23503'; END IF;
  v_participante:=(to_jsonb(v_lectura)->>v_columna)::bigint;
  EXECUTE format('SELECT usuario_id FROM banco.%I WHERE usuario_id=$1 FOR UPDATE',v_perfil) USING v_participante;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_lectura.proyecto_id FOR UPDATE;
  EXECUTE format('SELECT * FROM banco.%I WHERE id=$1 FOR UPDATE',v_tabla) INTO v_asignacion USING p_asignacion;
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  IF v_asignacion.id IS NULL OR v_asignacion.proyecto_id<>v_proyecto.id
    OR (to_jsonb(v_asignacion)->>v_columna)::bigint<>v_participante THEN
    RAISE EXCEPTION 'El origen de la asignación cambió indebidamente' USING ERRCODE='23503';
  END IF;
  IF v_asignacion.estado='revocada' AND v_asignacion.evento_retiro_id IS NOT NULL THEN
    PERFORM banco.comprobar_retiro(p_tipo,v_asignacion.id,v_participante,v_proyecto.id,
      v_asignacion.inicio,v_asignacion.fin,v_asignacion.evento_retiro_id,false);
    RETURN v_asignacion.evento_retiro_id;
  END IF;
  IF v_asignacion.estado<>'vigente' OR v_proyecto.estado NOT IN ('publicado','en_curso','pausado') THEN
    RAISE EXCEPTION 'Solo se retira una asignación vigente de un proyecto publicado, en curso o pausado' USING ERRCODE='55000';
  END IF;
  PERFORM banco.comprobar_aprobacion_participacion(CASE WHEN p_tipo='alumno' THEN 'candidatura' ELSE 'direccion' END,
    (to_jsonb(v_asignacion)->>v_origen)::bigint);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_admin,'usuario',v_operacion,v_tabla,p_asignacion::text,'vigente -> revocada',
    jsonb_build_object('tipo',p_tipo,'asignacion_id',p_asignacion,'participante_id',v_participante,'proyecto_id',v_proyecto.id,'motivo',p_motivo)::text)
  RETURNING id,fecha INTO v_evento,v_fecha;
  EXECUTE format('UPDATE banco.%I SET estado=''revocada'',fin=CASE WHEN $1>inicio THEN $1 ELSE NULL END,evento_retiro_id=$2 WHERE id=$3',v_tabla)
    USING v_fecha,v_evento,p_asignacion;
  FOR v_vinculo IN SELECT * FROM banco.acompanamiento
    WHERE estado='vigente' AND ((p_tipo='alumno' AND asignacion_alumno_id=p_asignacion)
      OR (p_tipo='direccion' AND asignacion_direccion_id=p_asignacion)) ORDER BY id FOR UPDATE
  LOOP
    UPDATE banco.acompanamiento SET estado='revocada',
      fin=CASE WHEN v_fecha>inicio THEN v_fecha ELSE NULL END,evento_retiro_id=v_evento WHERE id=v_vinculo.id;
  END LOOP;
  v_participantes:=banco.participantes_vigentes(v_proyecto.id);
  IF v_proyecto.estado='en_curso' AND (jsonb_array_length(v_participantes->'alumnos')=0 OR jsonb_array_length(v_participantes->'direcciones')=0) THEN
    INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_admin,'usuario','pausar_proyecto','proyecto',v_proyecto.id::text,'en_curso -> pausado',
      (v_participantes || jsonb_build_object('retiro_evento_id',v_evento,'evento_estado_anterior_id',v_proyecto.evento_estado_id))::text)
    RETURNING id INTO v_pausa;
    UPDATE banco.proyecto SET estado='pausado',evento_estado_id=v_pausa WHERE id=v_proyecto.id;
  END IF;
  RETURN v_evento;
END;
$_$;


--
-- Name: retirar_director(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.retirar_director(p_asignacion bigint, p_admin bigint, p_motivo text) RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
 SELECT banco.retirar_asignacion('direccion',p_asignacion,p_admin,p_motivo);
$$;


--
-- Name: FUNCTION retirar_director(p_asignacion bigint, p_admin bigint, p_motivo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.retirar_director(p_asignacion bigint, p_admin bigint, p_motivo text) IS 'Retiro interno por administrador activo y motivo; cierra sus acompañamientos, conserva alumnos y su carga y pausa si falta director. No retiro unilateral docente.';


--
-- Name: revision_coincide_con_proyecto(banco.proyecto, jsonb); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.revision_coincide_con_proyecto(p_proyecto banco.proyecto, p_instantanea jsonb) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: solicitar_direccion(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.solicitar_direccion(p_proyecto bigint, p_profesor bigint, p_experiencia text, p_justificacion text) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_solicitud bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_profesor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Se requiere un perfil de profesor existente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_rol(p_profesor,'profesor',true);
  IF p_experiencia IS NULL OR p_experiencia !~ '[^[:space:]]' OR p_justificacion IS NULL OR p_justificacion !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'RF-28: indicar experiencia aplicable y justificación' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,'direccion');
  INSERT INTO banco.solicitud_direccion(profesor_id,proyecto_id,experiencia_aplicable,justificacion,estado)
  VALUES(p_profesor,p_proyecto,p_experiencia,p_justificacion,'pendiente') RETURNING id INTO v_solicitud;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_profesor,'usuario','solicitar_direccion','solicitud_direccion',v_solicitud::text,
    'sin solicitud -> pendiente',jsonb_build_object('proyecto_id',p_proyecto)::text);
  RETURN v_solicitud;
END;
$$;


--
-- Name: FUNCTION solicitar_direccion(p_proyecto bigint, p_profesor bigint, p_experiencia text, p_justificacion text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.solicitar_direccion(p_proyecto bigint, p_profesor bigint, p_experiencia text, p_justificacion text) IS 'Envío interno RF-28: profesor activo, publicación válida, experiencia y justificación; solicitud pendiente con auditoría, sin consumir carga ni fijar máximo de pendientes.';


--
-- Name: usos_habilidad(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.usos_habilidad(p_habilidad bigint) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'banco', 'adjunto'
    AS $$
  SELECT jsonb_build_object(
    'alumnos',(SELECT count(*) FROM banco.alumno_habilidad WHERE habilidad_id=p_habilidad),
    'proyectos',(SELECT count(*) FROM banco.proyecto_habilidad WHERE habilidad_id=p_habilidad),
    'evidencias',(SELECT count(*) FROM adjunto.documento WHERE habilidad_id=p_habilidad),
    'instantaneas',(SELECT count(*) FROM banco.revision_proyecto r
      WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(r.instantanea_contenido->'habilidades','[]'::jsonb)) h
        WHERE (h->>'habilidad_id')::bigint=p_habilidad)));
$$;


--
-- Name: validar_acompanamiento(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_acompanamiento() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_evento banco.evento_auditoria%ROWTYPE;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id
    OR NEW.asignacion_alumno_id IS DISTINCT FROM OLD.asignacion_alumno_id
    OR NEW.asignacion_direccion_id IS DISTINCT FROM OLD.asignacion_direccion_id
    OR NEW.inicio IS DISTINCT FROM OLD.inicio OR (OLD.estado<>'vigente' AND NEW IS DISTINCT FROM OLD)) THEN
    RAISE EXCEPTION 'El acompañamiento conserva identidad, origen e inicio; el historial cerrado no se reescribe' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_retiro_id IS NOT NULL AND (TG_OP='INSERT' OR NEW.evento_retiro_id IS DISTINCT FROM OLD.evento_retiro_id) THEN
    IF TG_OP='INSERT' OR OLD.estado<>'vigente' OR NEW.estado<>'revocada' THEN
      RAISE EXCEPTION 'El retiro cierra un acompañamiento vigente existente' USING ERRCODE='55000';
    END IF;
    SELECT * INTO v_evento FROM banco.evento_auditoria WHERE id=NEW.evento_retiro_id;
    IF NOT FOUND OR v_evento.operacion NOT IN ('retirar_alumno','retirar_director') THEN
      RAISE EXCEPTION 'La evidencia no corresponde a un retiro autorizado' USING ERRCODE='23514';
    END IF;
    PERFORM banco.evento_operacion(v_evento.id,v_evento.operacion,v_evento.entidad_afectada,v_evento.registro_afectado::bigint,true);
  END IF;
  PERFORM banco.comprobar_acompanamiento_estado(NEW);
  RETURN NEW;
END;
$$;


--
-- Name: validar_administrador_decision(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_administrador_decision() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM banco.exigir_rol(NEW.administrador_usuario_id,'administrador',true);
  RETURN NEW;
END;
$$;


--
-- Name: validar_aprobacion_participacion_diferida(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_aprobacion_participacion_diferida() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF TG_TABLE_NAME='candidatura' THEN
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.id);
  ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
    PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.id);
  ELSIF TG_TABLE_NAME='asignacion_alumno' THEN
    PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.candidatura_id);
  ELSIF TG_TABLE_NAME='asignacion_direccion' THEN
    PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.solicitud_direccion_id);
  ELSIF TG_TABLE_NAME='decision_administrativa' THEN
    IF NEW.candidatura_id IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('candidatura',NEW.candidatura_id);
    ELSIF NEW.solicitud_direccion_id IS NOT NULL THEN
      PERFORM banco.comprobar_aprobacion_participacion('direccion',NEW.solicitud_direccion_id);
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: validar_autoria_proyecto(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_autoria_proyecto() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    PERFORM banco.exigir_representante(NEW.autor_usuario_id,NEW.empresa_id);
  ELSIF NEW.empresa_id IS DISTINCT FROM OLD.empresa_id OR NEW.autor_usuario_id IS DISTINCT FROM OLD.autor_usuario_id THEN
    RAISE EXCEPTION 'La propiedad y autoría históricas del proyecto son inmutables' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validar_cierre_proyecto_diferido(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_cierre_proyecto_diferido() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_id bigint; v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME='proyecto' THEN v_id:=NEW.id;
  ELSIF TG_TABLE_NAME='acompanamiento' THEN
    SELECT proyecto_id INTO v_id FROM banco.asignacion_alumno WHERE id=NEW.asignacion_alumno_id;
  ELSE v_id:=NEW.proyecto_id; END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_id FOR UPDATE;
  IF FOUND AND v_proyecto.estado IN ('finalizado','cancelado') THEN
    PERFORM banco.comprobar_cierre_proyecto(v_proyecto,false);
  ELSIF NEW.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'El cierre de un participante o solicitud requiere el cierre coordinado del proyecto' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: validar_cupo_candidatura(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_cupo_candidatura() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_activas bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- La fila estable del alumno serializa proyectos distintos. READ COMMITTED
  -- da al conteo posterior una vista actualizada después de esperar el bloqueo.
  PERFORM usuario_id FROM banco.alumno WHERE usuario_id=NEW.alumno_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Alumno inexistente' USING ERRCODE='23503'; END IF;
  IF TG_OP='UPDATE' AND OLD.estado='aprobada' AND NEW.estado<>'aprobada' THEN
    RAISE EXCEPTION 'D-06: la candidatura aprobada conserva su origen autorizado; las bajas se registran en la asignación'
      USING ERRCODE='55000';
  END IF;
  IF NEW.estado IN ('pendiente_evaluacion','evaluada','preseleccionada') THEN
    -- El índice único conserva el error de duplicado 23505 para la misma pareja.
    IF EXISTS (SELECT 1 FROM banco.candidatura WHERE alumno_id=NEW.alumno_id
      AND proyecto_id=NEW.proyecto_id AND id<>NEW.id
      AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')) THEN
      RAISE EXCEPTION 'RN-11: ya existe una candidatura activa para este alumno y proyecto'
        USING ERRCODE='23505';
    END IF;
    SELECT count(*) INTO v_activas FROM banco.candidatura WHERE alumno_id=NEW.alumno_id
      AND id<>NEW.id AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
    IF v_activas>=3 THEN
      RAISE EXCEPTION 'D-01/D-06: el alumno ya tiene tres candidaturas activas simultáneas'
        USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validar_elemento_cierre(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_elemento_cierre() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto bigint; v_evento banco.evento_auditoria%ROWTYPE; v_clave text;
  v_cambios text[]; v_datos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_OP='UPDATE' AND OLD.evento_cierre_id IS NOT NULL AND
    (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
    RAISE EXCEPTION 'El cierre conserva su historia y no se reabre ni reescribe' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_cierre_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'resultado_decision') IS NOT DISTINCT FROM
    (to_jsonb(OLD)-'resultado_decision') THEN RETURN NEW; END IF;
  IF TG_OP<>'UPDATE' OR OLD.evento_cierre_id IS NOT NULL THEN
    RAISE EXCEPTION 'El cierre solo afecta registros existentes aún abiertos' USING ERRCODE='23514';
  END IF;
  IF TG_TABLE_NAME='acompanamiento' THEN
    SELECT proyecto_id INTO v_proyecto FROM banco.asignacion_alumno WHERE id=NEW.asignacion_alumno_id;
  ELSE v_proyecto:=NEW.proyecto_id; END IF;
  v_evento:=banco.evento_cierre_proyecto(NEW.evento_cierre_id,v_proyecto,true);
  v_datos:=v_evento.resultado::jsonb;
  IF TG_TABLE_NAME IN ('asignacion_alumno','asignacion_direccion','acompanamiento') THEN
    IF OLD.estado<>'vigente' OR NEW.evento_retiro_id IS NOT NULL THEN
      RAISE EXCEPTION 'Solo se cierran periodos vigentes; los retiros anteriores se conservan' USING ERRCODE='55000';
    END IF;
    v_clave:=CASE TG_TABLE_NAME WHEN 'asignacion_alumno' THEN 'alumnos'
      WHEN 'asignacion_direccion' THEN 'direcciones' ELSE 'acompanamientos' END;
    PERFORM banco.comprobar_periodo_cierre(NEW.evento_cierre_id,v_proyecto,v_clave,
      NEW.id,NEW.estado,NEW.inicio,NEW.fin,true);
    v_cambios:=ARRAY['estado','fin','evento_cierre_id','resultado_decision'];
  ELSE
    v_cambios:=ARRAY['estado','evento_cierre_id'];
    IF TG_TABLE_NAME='candidatura' THEN
      IF OLD.estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada') OR NEW.estado<>'cancelada'
        OR NOT COALESCE((v_datos #> '{alcance,candidaturas}') @>
          jsonb_build_array(jsonb_build_object('id',OLD.id,'estado',OLD.estado)),false) THEN
        RAISE EXCEPTION 'El cierre cancela solo las candidaturas activas incluidas' USING ERRCODE='23514';
      END IF;
    ELSIF TG_TABLE_NAME='solicitud_direccion' THEN
      IF OLD.estado<>'pendiente' OR NEW.estado<>'cancelada'
        OR NOT COALESCE((v_datos #> '{alcance,solicitudes}') @> jsonb_build_array(NEW.id),false) THEN
        RAISE EXCEPTION 'El cierre cancela solo las solicitudes pendientes incluidas' USING ERRCODE='23514';
      END IF;
    ELSE
      v_cambios:=ARRAY['estado_revision','evento_cierre_id'];
      IF TG_TABLE_NAME<>'revision_proyecto' OR OLD.estado_revision<>'en_revision' OR NEW.estado_revision<>'cancelada'
        OR EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=NEW.id)
        OR NOT COALESCE((v_datos #> '{alcance,revisiones}') @> jsonb_build_array(NEW.id),false) THEN
        RAISE EXCEPTION 'La revisión se cancela sin fabricar una decisión de rechazo' USING ERRCODE='23514';
      END IF;
    END IF;
  END IF;
  IF (to_jsonb(NEW)-v_cambios) IS DISTINCT FROM (to_jsonb(OLD)-v_cambios) THEN
    RAISE EXCEPTION 'El cierre conserva identidad, contenido, autoría y origen' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validar_evaluacion_d08_diferida(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_evaluacion_d08_diferida() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  IF TG_TABLE_NAME='evaluacion_candidato' THEN PERFORM banco.comprobar_evaluacion_d08(NEW.id);
  ELSE PERFORM banco.comprobar_evaluacion_d08(NEW.evaluacion_id); END IF;
  RETURN NULL;
END;
$$;


--
-- Name: validar_evaluador(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_evaluador() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_empresa bigint;
BEGIN
  SELECT p.empresa_id INTO v_empresa FROM banco.candidatura c
    JOIN banco.proyecto p ON p.id=c.proyecto_id WHERE c.id=NEW.candidatura_id FOR SHARE OF c,p;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidatura inexistente' USING ERRCODE='23503'; END IF;
  PERFORM banco.exigir_representante(NEW.evaluador_usuario_id,v_empresa);
  RETURN NEW;
END;
$$;


--
-- Name: validar_minimos_proyecto_diferido(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_minimos_proyecto_diferido() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_id bigint; v_proyecto banco.proyecto%ROWTYPE; v_publicado banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF TG_TABLE_NAME='proyecto' THEN v_id:=NEW.id; ELSE v_id:=NEW.proyecto_id; END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_id FOR UPDATE;
  IF FOUND AND v_proyecto.estado='en_curso' THEN
    v_publicado:=v_proyecto; v_publicado.estado:='publicado';
    PERFORM banco.comprobar_condiciones_inicio(v_publicado);
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: validar_perfil_rol(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_perfil_rol() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
BEGIN
  PERFORM banco.exigir_rol(NEW.usuario_id,TG_ARGV[0]);
  RETURN NEW;
END;
$$;


--
-- Name: validar_proyecto_al_asignar(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_proyecto_al_asignar() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_tipo text;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=NEW.proyecto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  v_tipo:=CASE WHEN TG_TABLE_NAME='asignacion_alumno' THEN 'alumno' ELSE 'direccion' END;
  PERFORM banco.exigir_disponibilidad_participacion(v_proyecto,v_tipo);
  IF v_proyecto.estado='pausado' AND NEW.estado<>'vigente' THEN
    RAISE EXCEPTION 'La reposición requiere una asignación vigente autorizada' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validar_representacion(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_representacion() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: validar_reserva_asignacion(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_reserva_asignacion() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE; v_total bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Orden para nuevas reservas: participante -> proyecto. El nombre del
  -- trigger lo sitúa antes de los controles de publicación de la migración003.
  IF TG_TABLE_NAME='asignacion_alumno' THEN
    PERFORM usuario_id FROM banco.alumno WHERE usuario_id=NEW.alumno_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Alumno inexistente' USING ERRCODE='23503'; END IF;
  ELSE
    PERFORM usuario_id FROM banco.profesor WHERE usuario_id=NEW.profesor_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profesor inexistente' USING ERRCODE='23503'; END IF;
  END IF;
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=NEW.proyecto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  IF NEW.estado='vigente' THEN
    IF TG_TABLE_NAME='asignacion_alumno' THEN
      IF EXISTS (SELECT 1 FROM banco.asignacion_alumno WHERE alumno_id=NEW.alumno_id
        AND id<>NEW.id AND estado='vigente') THEN
        RAISE EXCEPTION 'D-04/D-06: el alumno ya tiene un proyecto asignado vigente'
          USING ERRCODE='23505';
      END IF;
      PERFORM banco.exigir_cupo_proyecto(v_proyecto);
      SELECT count(*) INTO v_total FROM banco.asignacion_alumno
        WHERE proyecto_id=NEW.proyecto_id AND id<>NEW.id AND estado='vigente';
      IF v_total>=v_proyecto.cupo_maximo_alumnos THEN
        RAISE EXCEPTION 'D-02/D-06: el proyecto no tiene plazas de alumnos disponibles'
          USING ERRCODE='23514';
      END IF;
    ELSE
      SELECT count(DISTINCT proyecto_id) INTO v_total FROM banco.asignacion_direccion
        WHERE profesor_id=NEW.profesor_id AND id<>NEW.id AND estado='vigente';
      IF v_total>=3 THEN
        RAISE EXCEPTION 'RN-05/D-06: el profesor ya dirige tres proyectos vigentes'
          USING ERRCODE='23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validar_retiro_asignacion(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_retiro_asignacion() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_tipo text; v_participante bigint;
BEGIN
  IF TG_OP='UPDATE' AND OLD.evento_retiro_id IS NOT NULL AND
    (to_jsonb(NEW)-'resultado_decision') IS DISTINCT FROM (to_jsonb(OLD)-'resultado_decision') THEN
    RAISE EXCEPTION 'El retiro confirmado conserva su historial' USING ERRCODE='55000';
  END IF;
  IF NEW.evento_retiro_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='INSERT' OR OLD.estado<>'vigente' OR OLD.evento_retiro_id IS NOT NULL
    OR NEW.estado<>'revocada' THEN
    IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'resultado_decision')=(to_jsonb(OLD)-'resultado_decision') THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'El retiro se registra sobre una asignación vigente existente' USING ERRCODE='55000';
  END IF;
  IF (to_jsonb(NEW)-ARRAY['estado','fin','evento_retiro_id','resultado_decision'])
    IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['estado','fin','evento_retiro_id','resultado_decision']) THEN
    RAISE EXCEPTION 'El retiro no sustituye la identidad, origen o inicio de la asignación' USING ERRCODE='55000';
  END IF;
  IF TG_TABLE_NAME='asignacion_alumno' THEN v_tipo:='alumno'; v_participante:=NEW.alumno_id;
  ELSE v_tipo:='direccion'; v_participante:=NEW.profesor_id; END IF;
  PERFORM banco.comprobar_retiro(v_tipo,NEW.id,v_participante,NEW.proyecto_id,NEW.inicio,NEW.fin,NEW.evento_retiro_id,true);
  RETURN NEW;
END;
$$;


--
-- Name: validar_revision(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_revision() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: validar_usuario_dependencias(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_usuario_dependencias() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
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


--
-- Name: validar_vigencias_padre(); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.validar_vigencias_padre() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco'
    AS $$
DECLARE v_vinculo banco.acompanamiento%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME='asignacion_alumno' THEN
    FOR v_vinculo IN SELECT * FROM banco.acompanamiento WHERE asignacion_alumno_id=NEW.id ORDER BY id LOOP
      PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
    END LOOP;
  ELSE
    FOR v_vinculo IN SELECT * FROM banco.acompanamiento WHERE asignacion_direccion_id=NEW.id ORDER BY id LOOP
      PERFORM banco.comprobar_acompanamiento_estado(v_vinculo);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: web_abrir_documento(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_abrir_documento(p_actor bigint, p_documento bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_abrir_documento(p_actor bigint, p_documento bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_abrir_documento(p_actor bigint, p_documento bigint) IS 'D-11/D-10: metadatos y ruta privada de un documento vigente, solo para quien puede consultar el perfil del titular.';


--
-- Name: web_abrir_imagen(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_abrir_imagen(p_actor bigint, p_imagen bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
DECLARE v_img adjunto.imagen%ROWTYPE;
BEGIN
  PERFORM banco.web_exigir_avisos(p_actor);
  SELECT * INTO v_img FROM adjunto.imagen WHERE id=p_imagen;
  IF NOT FOUND OR v_img.retirado IS NOT NULL OR (v_img.tipo='foto' AND NOT adjunto.puede_ver_foto(p_actor,v_img.usuario_id)) THEN
    RAISE EXCEPTION 'Imagen no disponible' USING ERRCODE='23503'; END IF;
  RETURN jsonb_build_object('id',v_img.id,'tipo',v_img.tipo,'ruta',v_img.ruta,'sha256',v_img.sha256,'subido',v_img.subido);
END;
$$;


--
-- Name: FUNCTION web_abrir_imagen(p_actor bigint, p_imagen bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_abrir_imagen(p_actor bigint, p_imagen bigint) IS 'UX-08: ruta privada de una imagen vigente; foto solo dentro del ámbito de consultar_perfil, logo para cualquier cuenta activa.';


--
-- Name: web_abrir_participacion(bigint, text, bigint, boolean); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_abrir_participacion(p_actor bigint, p_tipo text, p_id bigint, p_escritura boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_datos jsonb;v_rol text;v_titular bigint;v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  IF p_tipo='candidatura' THEN
    IF p_escritura THEN PERFORM id FROM banco.candidatura WHERE id=p_id FOR UPDATE;
    ELSE PERFORM id FROM banco.candidatura WHERE id=p_id FOR SHARE; END IF;
  ELSIF p_tipo='direccion' THEN
    IF p_escritura THEN PERFORM id FROM banco.solicitud_direccion WHERE id=p_id FOR UPDATE;
    ELSE PERFORM id FROM banco.solicitud_direccion WHERE id=p_id FOR SHARE; END IF;
  ELSE RAISE EXCEPTION 'Tipo de participación inválido' USING ERRCODE='22023'; END IF;
  v_datos:=banco.web_participacion_base(p_tipo,p_id);v_titular:=(v_datos->>'titular_id')::bigint;
  -- El orden coincide con evaluación/autorización/cancelación: fuente, perfil, proyecto, actor.
  IF p_tipo='candidatura' THEN
    IF p_escritura THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_titular FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_titular FOR SHARE; END IF;
  ELSE
    IF p_escritura THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_titular FOR UPDATE;
    ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_titular FOR SHARE; END IF;
  END IF;
  IF p_escritura THEN SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=(v_datos->>'proyecto_id')::bigint FOR UPDATE;
  ELSE SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=(v_datos->>'proyecto_id')::bigint FOR SHARE; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('alumno','profesor','empresa','administrador') THEN
    RAISE EXCEPTION 'Acceso no permitido' USING ERRCODE='42501'; END IF;
  IF v_rol<>'empresa' THEN PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF v_rol='administrador' OR (v_rol='alumno' AND p_tipo='candidatura' AND v_titular=p_actor)
    OR (v_rol='profesor' AND p_tipo='direccion' AND v_titular=p_actor) THEN RETURN v_datos; END IF;
  IF v_rol='empresa' AND p_tipo='candidatura' THEN
    IF NOT EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE usuario_id=p_actor AND empresa_id=v_proyecto.empresa_id AND vigente) THEN
      RAISE EXCEPTION 'La solicitud queda fuera de tu empresa' USING ERRCODE='42501'; END IF;
    PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);RETURN v_datos;
  END IF;
  RAISE EXCEPTION 'La solicitud queda fuera de tu ámbito' USING ERRCODE='42501';
END;
$$;


--
-- Name: web_abrir_proyecto(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_abrir_proyecto(p_actor bigint, p_proyecto bigint) RETURNS banco.proyecto
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_rol text;v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN
    PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN
    v_empresa:=banco.web_empresa_del_actor(p_actor);
    IF v_empresa IS DISTINCT FROM v_proyecto.empresa_id THEN
      RAISE EXCEPTION 'Proyecto inexistente' USING ERRCODE='23503'; END IF;
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar proyectos en este módulo' USING ERRCODE='42501';
  END IF;
  RETURN v_proyecto;
END;
$$;


--
-- Name: web_acciones_ciclo(bigint, banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_acciones_ciclo(p_actor bigint, p_proyecto banco.proyecto) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_acciones jsonb:='[]';v_alumnos integer;v_directores integer;
BEGIN
  IF EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='alumno' AND estado_cuenta='activa') THEN
    IF banco.web_admite_participacion(p_proyecto,'candidatura') AND EXISTS(SELECT 1 FROM banco.alumno WHERE usuario_id=p_actor)
      AND (SELECT count(*) FROM banco.candidatura WHERE alumno_id=p_actor AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada'))<3
      AND NOT EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto.id AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')) THEN RETURN '["participar"]'::jsonb; END IF;
    RETURN v_acciones;
  ELSIF EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='profesor' AND estado_cuenta='activa') THEN
    IF banco.web_admite_participacion(p_proyecto,'direccion') AND EXISTS(SELECT 1 FROM banco.profesor WHERE usuario_id=p_actor)
      AND NOT EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto.id AND estado='pendiente') THEN RETURN '["participar"]'::jsonb; END IF;
    RETURN v_acciones;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='administrador' AND estado_cuenta='activa') THEN RETURN v_acciones; END IF;
  SELECT count(*) INTO v_alumnos FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  SELECT count(*) INTO v_directores FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente';
  IF p_proyecto.estado IN ('borrador','en_revision','en_correccion','publicado','en_curso','pausado') THEN v_acciones:=v_acciones||'"cancelar"'::jsonb; END IF;
  IF p_proyecto.estado='en_curso' THEN v_acciones:=v_acciones||'"finalizar"'::jsonb; END IF;
  IF p_proyecto.estado IN ('publicado','pausado') AND v_alumnos>0 AND v_directores=1 THEN
    v_acciones:=v_acciones||to_jsonb(CASE p_proyecto.estado WHEN 'publicado' THEN 'iniciar'::text ELSE 'reanudar'::text END); END IF;
  IF p_proyecto.estado IN ('publicado','en_curso','pausado') THEN
    IF v_alumnos>0 THEN v_acciones:=v_acciones||'"retirar_alumno"'::jsonb; END IF;
    IF v_directores>0 THEN v_acciones:=v_acciones||'"retirar_director"'::jsonb; END IF;
  END IF;
  RETURN v_acciones;
END;
$$;


--
-- Name: web_acciones_participacion(bigint, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_acciones_participacion(p_actor bigint, p_tipo text, p_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_s jsonb;v_rol text;v_p banco.proyecto%ROWTYPE;v_activa boolean;v_resultado jsonb:='[]';
BEGIN
  v_s:=banco.web_participacion_base(p_tipo,p_id);
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=(v_s->>'proyecto_id')::bigint;
  v_activa:=CASE WHEN p_tipo='candidatura' THEN v_s->>'estado' IN ('pendiente_evaluacion','evaluada','preseleccionada') ELSE v_s->>'estado'='pendiente' END;
  IF p_actor=(v_s->>'titular_id')::bigint AND v_activa THEN v_resultado:=v_resultado||'"cancelar"'::jsonb; END IF;
  IF v_rol='empresa' AND p_tipo='candidatura' AND v_activa AND banco.web_admite_participacion(v_p,p_tipo) THEN
    v_resultado:=v_resultado||'"evaluar"'::jsonb;
    IF v_s->>'estado'='evaluada' AND EXISTS(SELECT 1 FROM banco.evaluacion_candidato
      WHERE id=(v_s->>'evaluacion_vigente_id')::bigint AND recomendacion='recomendada') THEN
      v_resultado:=v_resultado||'"preseleccionar"'::jsonb;
    END IF;
  END IF;
  IF v_rol='administrador' AND v_activa AND v_p.estado IN ('publicado','en_curso','pausado') THEN
    v_resultado:=v_resultado||'"rechazar"'::jsonb;
    IF banco.web_admite_participacion(v_p,p_tipo) AND (p_tipo='direccion' OR v_s->>'estado'='preseleccionada') THEN
      v_resultado:=v_resultado||'"aprobar"'::jsonb;
    END IF;
  END IF;
  RETURN v_resultado;
END;
$$;


--
-- Name: web_admite_participacion(banco.proyecto, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_admite_participacion(p_proyecto banco.proyecto, p_tipo text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_publicado banco.proyecto%ROWTYPE;v_revision banco.revision_proyecto%ROWTYPE;
BEGIN
  IF p_tipo NOT IN ('candidatura','direccion') OR p_proyecto.estado NOT IN ('publicado','pausado') THEN RETURN false; END IF;
  v_publicado:=p_proyecto;v_publicado.estado:='publicado';
  SELECT * INTO v_revision FROM banco.revision_proyecto WHERE id=p_proyecto.revision_publicada_id;
  IF NOT FOUND OR NOT coalesce(banco.web_catalogo_publicacion_valida(v_publicado,v_revision),false) THEN RETURN false; END IF;
  RETURN p_proyecto.estado='publicado' OR
    (p_tipo='candidatura' AND NOT EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente')) OR
    (p_tipo='direccion' AND NOT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente'));
END;
$$;


--
-- Name: web_ambito_proyecto(bigint, banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_ambito_proyecto(p_actor bigint, p_proyecto banco.proyecto) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN RETURN true;
  ELSIF v_rol='empresa' THEN RETURN EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE usuario_id=p_actor AND empresa_id=p_proyecto.empresa_id AND vigente);
  ELSIF v_rol='alumno' THEN RETURN EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto.id)
      OR (p_proyecto.estado='pausado' AND banco.web_admite_participacion(p_proyecto,'candidatura'));
  ELSIF v_rol='profesor' THEN RETURN EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto.id)
      OR (p_proyecto.estado='pausado' AND banco.web_admite_participacion(p_proyecto,'direccion'));
  END IF;
  RETURN false;
END;
$$;


--
-- Name: web_auditar_cambio(bigint, bigint, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_auditar_cambio(p_actor bigint, p_usuario bigint, p_operacion text, p_motivo text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_bandeja_avisos(bigint, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_bandeja_avisos(p_actor bigint, p_estado text, p_buscar text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.web_exigir_avisos(p_actor);
  IF p_estado IS NULL OR p_estado NOT IN ('todos','no_leidos','leidos') OR length(p_buscar)>150
    OR p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0 THEN
    RAISE EXCEPTION 'Filtros de avisos inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH propios AS MATERIALIZED (
    SELECT id,mensaje,fecha,fecha_lectura FROM banco.notificacion WHERE destinatario_usuario_id=p_actor
  ), filtrados AS MATERIALIZED (
    SELECT * FROM propios WHERE (p_estado='todos' OR (p_estado='no_leidos' AND fecha_lectura IS NULL) OR (p_estado='leidos' AND fecha_lectura IS NOT NULL))
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(mensaje),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtrados ORDER BY fecha DESC,id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY fecha DESC,id DESC) FROM pagina),'[]'::jsonb),
    'total',(SELECT count(*) FROM filtrados),'no_leidos',(SELECT count(*) FROM propios WHERE fecha_lectura IS NULL)));
END;
$$;


--
-- Name: web_bandeja_participacion(bigint, text, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_bandeja_participacion(p_actor bigint, p_tipo text, p_estado text, p_buscar text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;v_empresa bigint;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('candidatura','direccion')
    OR (v_rol='alumno' AND p_tipo<>'candidatura') OR (v_rol='profesor' AND p_tipo<>'direccion')
    OR (v_rol='empresa' AND p_tipo<>'candidatura') THEN RAISE EXCEPTION 'Bandeja no autorizada' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN v_empresa:=banco.web_empresa_del_actor(p_actor);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(p_buscar)>150 OR (nullif(p_estado,'') IS NOT NULL AND
      ((p_tipo='candidatura' AND p_estado NOT IN ('pendiente_evaluacion','evaluada','preseleccionada','aprobada','rechazada','cancelada'))
      OR(p_tipo='direccion' AND p_estado NOT IN ('pendiente','aprobada','rechazada','cancelada')))) THEN
    RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH fuentes AS (
    SELECT id,alumno_id AS titular_id,proyecto_id,estado,fecha_solicitud FROM banco.candidatura WHERE p_tipo='candidatura'
    UNION ALL SELECT id,profesor_id,proyecto_id,estado,fecha_solicitud FROM banco.solicitud_direccion WHERE p_tipo='direccion'
  ), filtradas AS MATERIALIZED (
    SELECT f.id,p_tipo AS tipo,f.estado,f.fecha_solicitud,f.proyecto_id,p.titulo,p.estado AS proyecto_estado,e.razon_social,u.nombre AS solicitante_nombre
      FROM fuentes f JOIN banco.proyecto p ON p.id=f.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=f.titular_id
      WHERE (v_rol='administrador' OR (v_rol IN ('alumno','profesor') AND f.titular_id=p_actor)
        OR (v_rol='empresa' AND p.empresa_id=v_empresa))
      AND (nullif(p_estado,'') IS NULL OR f.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtradas ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtradas)));
END;
$$;


--
-- Name: usuario; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.usuario (
    id bigint NOT NULL,
    nombre text NOT NULL,
    correo_normalizado text NOT NULL,
    hash_contrasena text NOT NULL,
    rol_principal text NOT NULL,
    estado_cuenta text DEFAULT 'activa'::text NOT NULL,
    fecha_alta timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version_acceso bigint DEFAULT 1 NOT NULL,
    requiere_cambio_clave boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_correo_normalizado CHECK (((correo_normalizado = lower(btrim(correo_normalizado))) AND (correo_normalizado <> ''::text))),
    CONSTRAINT ck_usuario_version_acceso CHECK ((version_acceso > 0)),
    CONSTRAINT usuario_estado_cuenta_check CHECK ((estado_cuenta = ANY (ARRAY['activa'::text, 'inactiva'::text]))),
    CONSTRAINT usuario_hash_contrasena_check CHECK ((btrim(hash_contrasena) <> ''::text)),
    CONSTRAINT usuario_nombre_check CHECK ((btrim(nombre) <> ''::text)),
    CONSTRAINT usuario_rol_principal_check CHECK ((rol_principal = ANY (ARRAY['empresa'::text, 'alumno'::text, 'profesor'::text, 'administrador'::text])))
);


--
-- Name: COLUMN usuario.version_acceso; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.usuario.version_acceso IS 'WEB-02: versión monotónica calculada al cambiar nombre, hash, correo, rol, estado o requerimiento de clave; protege formularios CAS e invalida sesiones anteriores en Laravel.';


--
-- Name: COLUMN usuario.requiere_cambio_clave; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.usuario.requiere_cambio_clave IS 'WEB-02: las altas/restablecimientos web requieren cambio inicial por el titular; no convierte semillas sin acceso en credenciales válidas.';


--
-- Name: web_bloquear_cuenta(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_bloquear_cuenta(p_usuario bigint, p_version bigint) RETURNS banco.usuario
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_buscar_acceso_correo(text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_buscar_acceso_correo(p_correo text) RETURNS TABLE(id bigint, nombre text, correo_normalizado text, hash_contrasena text, rol_principal text, estado_cuenta text, fecha_alta timestamp with time zone, version_acceso bigint, requiere_cambio_clave boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT u.id,u.nombre,u.correo_normalizado,u.hash_contrasena,u.rol_principal,
    u.estado_cuenta,u.fecha_alta,u.version_acceso,u.requiere_cambio_clave
  FROM banco.usuario u WHERE u.correo_normalizado=lower(btrim(p_correo));
$$;


--
-- Name: FUNCTION web_buscar_acceso_correo(p_correo text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_buscar_acceso_correo(p_correo text) IS 'Gateway de autenticación de la credencial de servidor Laravel. Devuelve el hash de una sola cuenta para verificarlo en servidor; no es una consulta pública ni autentica IDs de actor.';


--
-- Name: web_buscar_acceso_id(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_buscar_acceso_id(p_usuario bigint) RETURNS TABLE(id bigint, nombre text, correo_normalizado text, hash_contrasena text, rol_principal text, estado_cuenta text, fecha_alta timestamp with time zone, version_acceso bigint, requiere_cambio_clave boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT u.id,u.nombre,u.correo_normalizado,u.hash_contrasena,u.rol_principal,
    u.estado_cuenta,u.fecha_alta,u.version_acceso,u.requiere_cambio_clave
  FROM banco.usuario u WHERE u.id=p_usuario;
$$;


--
-- Name: web_cambiar_clave(bigint, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_cambiar_clave(p_actor bigint, p_hash text, p_version bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_actor,p_version);
  PERFORM banco.exigir_rol(p_actor,v_usuario.rol_principal,true);
  PERFORM banco.web_validar_hash(p_hash);
  UPDATE banco.usuario SET hash_contrasena=p_hash,requiere_cambio_clave=false WHERE id=p_actor;
  PERFORM banco.web_auditar_cambio(p_actor,p_actor,'cambiar_clave','Cambio de clave por su titular');
END;
$$;


--
-- Name: web_catalogo_disponibilidad(banco.proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_catalogo_disponibilidad(p_proyecto banco.proyecto) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT jsonb_build_object('plazas_disponibles',greatest(0,p_proyecto.cupo_maximo_alumnos-
    (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto.id AND estado='vigente')),
    'direccion_disponible',NOT EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto.id AND estado='vigente'));
$$;


--
-- Name: web_catalogo_habilidades(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_catalogo_habilidades(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN PERFORM banco.web_empresa_del_actor(p_actor);
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar este catálogo' USING ERRCODE='42501'; END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nombre',nombre,'tipo',tipo,'descripcion',descripcion)
    ORDER BY tipo,nombre,id),'[]'::jsonb) FROM banco.habilidad);
END;
$$;


--
-- Name: web_catalogo_proyectos(bigint, text, bigint, text, bigint, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_catalogo_proyectos(p_actor bigint, p_buscar text, p_empresa bigint, p_modalidad text, p_habilidad bigint, p_tipo_habilidad text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(p_buscar)>150 OR length(p_modalidad)>250
    OR (nullif(p_tipo_habilidad,'') IS NOT NULL AND p_tipo_habilidad NOT IN ('dura','blanda')) THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.*,r.instantanea_contenido,e.razon_social,banco.web_catalogo_disponibilidad(p) AS disponibilidad
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
      JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_catalogo_publicacion_valida(p,r)
  ), filtrados AS MATERIALIZED (
    SELECT v.id,v.titulo,v.descripcion,v.razon_social,v.modalidad,v.duracion_estimada,v.cupo_maximo_alumnos,
      (v.disponibilidad->>'plazas_disponibles')::integer AS plazas_disponibles,
      (v.disponibilidad->>'direccion_disponible')::boolean AS direccion_disponible
      FROM visibles v
      WHERE (p_empresa IS NULL OR v.empresa_id=p_empresa)
        AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(v.titulo||' '||coalesce(v.descripcion,'')||' '||v.razon_social),lower(btrim(p_buscar)))>0)
        AND (nullif(btrim(p_modalidad),'') IS NULL OR lower(btrim(v.modalidad))=lower(btrim(p_modalidad)))
        AND ((p_habilidad IS NULL AND nullif(p_tipo_habilidad,'') IS NULL) OR EXISTS(
          SELECT 1 FROM jsonb_array_elements(v.instantanea_contenido->'habilidades') h
          WHERE (p_habilidad IS NULL OR (h->>'habilidad_id')::bigint=p_habilidad)
            AND (nullif(p_tipo_habilidad,'') IS NULL OR h->>'tipo'=p_tipo_habilidad)))
  ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),
    'total',(SELECT count(*) FROM filtrados)));
END;
$$;


--
-- Name: FUNCTION web_catalogo_proyectos(p_actor bigint, p_buscar text, p_empresa bigint, p_modalidad text, p_habilidad bigint, p_tipo_habilidad text, p_limite integer, p_desplazamiento integer); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_catalogo_proyectos(p_actor bigint, p_buscar text, p_empresa bigint, p_modalidad text, p_habilidad bigint, p_tipo_habilidad text, p_limite integer, p_desplazamiento integer) IS 'WEB-05: solo publicaciones aprobadas válidas de formato2; disponibilidad indicativa sin reservar ni autorizar candidaturas o dirección. Filtros y opciones no revelan borradores o revisiones privadas.';


--
-- Name: revision_proyecto; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.revision_proyecto (
    id bigint NOT NULL,
    proyecto_id bigint NOT NULL,
    autor_usuario_id bigint NOT NULL,
    numero integer NOT NULL,
    fecha_envio timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado_revision text DEFAULT 'en_revision'::text NOT NULL,
    instantanea_contenido jsonb NOT NULL,
    evento_cierre_id bigint,
    CONSTRAINT ck_revision_cierre CHECK (((estado_revision = 'cancelada'::text) = (evento_cierre_id IS NOT NULL))),
    CONSTRAINT revision_proyecto_estado_revision_check CHECK ((estado_revision = ANY (ARRAY['en_revision'::text, 'aprobada'::text, 'en_correccion'::text, 'rechazada'::text, 'cancelada'::text]))),
    CONSTRAINT revision_proyecto_instantanea_contenido_check CHECK ((jsonb_typeof(instantanea_contenido) = 'object'::text)),
    CONSTRAINT revision_proyecto_numero_check CHECK ((numero > 0))
);


--
-- Name: COLUMN revision_proyecto.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.revision_proyecto.evento_cierre_id IS 'Revisión pendiente cancelada por cierre del proyecto; conserva instantánea sin fabricar decisión de rechazo.';


--
-- Name: web_catalogo_publicacion_valida(banco.proyecto, banco.revision_proyecto); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_catalogo_publicacion_valida(p_proyecto banco.proyecto, p_revision banco.revision_proyecto) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  RETURN p_proyecto.estado='publicado' AND p_revision.id=p_proyecto.revision_publicada_id
    AND p_revision.proyecto_id=p_proyecto.id AND p_revision.estado_revision='aprobada'
    AND p_revision.instantanea_contenido->>'version_formato'='2'
    AND p_proyecto.cupo_maximo_alumnos>0
    AND p_proyecto.titulo ~ '[^[:space:]]' AND p_proyecto.descripcion ~ '[^[:space:]]'
    AND p_proyecto.problematica ~ '[^[:space:]]' AND p_proyecto.objetivos ~ '[^[:space:]]'
    AND p_proyecto.justificacion ~ '[^[:space:]]' AND p_proyecto.alcance ~ '[^[:space:]]'
    AND EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=p_revision.id AND resultado='aprobada')
    AND banco.revision_coincide_con_proyecto(p_proyecto,p_revision.instantanea_contenido);
END;
$$;


--
-- Name: web_coincidencia_catalogo(bigint, bigint[]); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_coincidencia_catalogo(p_actor bigint, p_proyectos bigint[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_proyectos IS NULL OR cardinality(p_proyectos)>100 THEN
    RAISE EXCEPTION 'Lista de proyectos inválida' USING ERRCODE='23514'; END IF;
  -- La coincidencia describe habilidades del alumno; el profesor no tiene habilidades estructuradas.
  IF v_rol<>'alumno' THEN RETURN '{}'::jsonb; END IF;
  RETURN coalesce((
    WITH propias AS MATERIALIZED (SELECT habilidad_id FROM banco.alumno_habilidad WHERE alumno_id=p_actor),
    requeridas AS (
      SELECT p.id AS proyecto_id,(h->>'habilidad_id')::bigint AS habilidad_id,h->>'nombre' AS nombre,
        coalesce((h->>'obligatoria')::boolean,false) AS obligatoria
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id,
        LATERAL jsonb_array_elements(r.instantanea_contenido->'habilidades') h
      WHERE p.id=ANY(p_proyectos) AND banco.web_catalogo_publicacion_valida(p,r))
    SELECT jsonb_object_agg(proyecto_id::text,datos) FROM (
      SELECT proyecto_id,jsonb_build_object(
        'requeridas',count(*),
        'cumplidas',count(*) FILTER (WHERE habilidad_id IN (SELECT habilidad_id FROM propias)),
        'faltantes',coalesce(jsonb_agg(jsonb_build_object('nombre',nombre,'obligatoria',obligatoria) ORDER BY NOT obligatoria,nombre)
          FILTER (WHERE habilidad_id NOT IN (SELECT habilidad_id FROM propias)),'[]'::jsonb)) AS datos
      FROM requeridas GROUP BY proyecto_id) por_proyecto
  ),'{}'::jsonb);
END;
$$;


--
-- Name: FUNCTION web_coincidencia_catalogo(p_actor bigint, p_proyectos bigint[]); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_coincidencia_catalogo(p_actor bigint, p_proyectos bigint[]) IS 'UX-02: por proyecto publicado válido, habilidades requeridas, cumplidas por el alumno actor y faltantes. Solo datos propios y la instantánea publicada; profesor recibe objeto vacío. Hasta 100 proyectos.';


--
-- Name: web_constancia(bigint, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_constancia(p_actor bigint, p_tipo text, p_id bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_constancia(p_actor bigint, p_tipo text, p_id bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_constancia(p_actor bigint, p_tipo text, p_id bigint) IS 'UX-07: datos de la constancia de una participación concluida con el cierre del proyecto (sin retiro). Solo el titular o la administración; otro actor recibe 23503.';


--
-- Name: web_contexto_postulacion(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_contexto_postulacion(p_actor bigint, p_proyecto bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;v_tipo text;v_p banco.proyecto%ROWTYPE;v_perfil boolean;v_activas integer;v_carga integer;v_existente jsonb;v_version text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR SHARE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR SHARE;
  ELSE RAISE EXCEPTION 'Solo alumnos y profesores pueden postularse' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  PERFORM banco.web_exigir_academico(p_actor);
  v_tipo:=CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END;
  IF NOT banco.web_admite_participacion(v_p,v_tipo) THEN RAISE EXCEPTION 'El proyecto no recibe solicitudes de este tipo' USING ERRCODE='23503'; END IF;
  IF v_rol='alumno' THEN
    v_perfil:=EXISTS(SELECT 1 FROM banco.alumno WHERE usuario_id=p_actor);
    SELECT count(*) INTO v_activas FROM banco.candidatura WHERE alumno_id=p_actor AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada');
    SELECT count(*) INTO v_carga FROM banco.asignacion_alumno WHERE alumno_id=p_actor AND estado='vigente';
    SELECT jsonb_build_object('id',id,'estado',estado) INTO v_existente FROM banco.candidatura
      WHERE alumno_id=p_actor AND proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada') ORDER BY id DESC LIMIT 1;
  ELSE
    v_perfil:=EXISTS(SELECT 1 FROM banco.profesor WHERE usuario_id=p_actor);
    SELECT count(*) INTO v_activas FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND estado='pendiente';
    SELECT count(*) INTO v_carga FROM banco.asignacion_direccion WHERE profesor_id=p_actor AND estado='vigente';
    SELECT jsonb_build_object('id',id,'estado',estado) INTO v_existente FROM banco.solicitud_direccion
      WHERE profesor_id=p_actor AND proyecto_id=p_proyecto AND estado='pendiente' ORDER BY id DESC LIMIT 1;
  END IF;
  v_version:=encode(sha256(convert_to(jsonb_build_object('perfil',banco.web_version_perfil(p_actor),'ciclo',banco.web_version_ciclo(p_proyecto),
    'activas',v_activas,'carga',v_carga,'existente',v_existente)::text,'UTF8')),'hex');
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_p)||jsonb_build_object('id',v_p.id,'estado',v_p.estado,
      'razon_social',(SELECT razon_social FROM banco.empresa WHERE id=v_p.empresa_id),
      'habilidades',(SELECT instantanea_contenido->'habilidades' FROM banco.revision_proyecto WHERE id=v_p.revision_publicada_id)),
    'perfil_completo',v_perfil,'version',v_version,'disponibilidad',banco.web_catalogo_disponibilidad(v_p),'activas',v_activas,'carga',v_carga,
    'existente',v_existente,'acciones',CASE WHEN v_perfil AND v_existente IS NULL AND (v_rol='profesor' OR v_activas<3) THEN '["enviar"]'::jsonb ELSE '[]'::jsonb END);
END;
$$;


--
-- Name: web_crear_cuenta(bigint, text, text, text, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_crear_cuenta(p_admin bigint, p_nombre text, p_correo text, p_hash text, p_rol text, p_razon_social text DEFAULT NULL::text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_crear_proyecto(bigint, jsonb); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_crear_proyecto(p_actor bigint, p_datos jsonb) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_empresa bigint;v_id bigint;v_fila banco.proyecto%ROWTYPE;
BEGIN
  v_empresa:=banco.web_empresa_del_actor(p_actor);
  v_fila:=banco.web_validar_datos_proyecto(p_datos);
  INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,
    requisitos_academicos,duracion_estimada,modalidad,fecha_inicio_estimada,fecha_fin_estimada,recursos,cupo_maximo_alumnos)
  VALUES(v_empresa,p_actor,v_fila.titulo,v_fila.descripcion,v_fila.problematica,v_fila.objetivos,v_fila.justificacion,v_fila.alcance,
    v_fila.requisitos_academicos,v_fila.duracion_estimada,v_fila.modalidad,v_fila.fecha_inicio_estimada,v_fila.fecha_fin_estimada,
    v_fila.recursos,v_fila.cupo_maximo_alumnos) RETURNING id INTO v_id;
  PERFORM banco.web_guardar_habilidades(v_id,p_datos);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
  VALUES(p_actor,'usuario','crear_proyecto','proyecto',v_id::text,'sin proyecto -> borrador','Borrador empresarial creado');
  RETURN v_id;
END;
$$;


--
-- Name: web_datos_cuenta(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_datos_cuenta(p_usuario bigint) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT jsonb_build_object('id',u.id,'nombre',u.nombre,
    'correo_normalizado',u.correo_normalizado,'rol_principal',u.rol_principal,
    'estado_cuenta',u.estado_cuenta,'fecha_alta',u.fecha_alta,
    'version_acceso',u.version_acceso,'requiere_cambio_clave',u.requiere_cambio_clave,
    'empresa_id',r.empresa_id,'razon_social',e.razon_social,
    'representante_vigente',coalesce(r.vigente,false))
  FROM banco.usuario u LEFT JOIN banco.representacion_empresa r ON r.usuario_id=u.id
    LEFT JOIN banco.empresa e ON e.id=r.empresa_id WHERE u.id=p_usuario;
$$;


--
-- Name: web_datos_empresa(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_datos_empresa(p_empresa bigint) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT jsonb_build_object('id',e.id,'razon_social',e.razon_social,'sector',e.sector,
    'identificacion',e.identificacion,'contacto_nombre',e.contacto_nombre,
    'contacto_correo',e.contacto_correo,'contacto_telefono',e.contacto_telefono,
    'version',banco.web_version_empresa(e.id)) FROM banco.empresa e WHERE e.id=p_empresa;
$$;


--
-- Name: web_detalle_aviso(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_detalle_aviso(p_actor bigint, p_aviso bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_n banco.notificacion%ROWTYPE;
BEGIN
  -- Coincide con marcar_notificacion_leida: aviso antes de usuario.
  SELECT * INTO v_n FROM banco.notificacion WHERE id=p_aviso FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aviso no disponible' USING ERRCODE='23503'; END IF;
  IF v_n.destinatario_usuario_id IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'Aviso ajeno' USING ERRCODE='42501'; END IF;
  PERFORM banco.web_exigir_avisos(p_actor);
  RETURN jsonb_build_object('aviso',jsonb_build_object('id',v_n.id,'mensaje',v_n.mensaje,'fecha',v_n.fecha,'fecha_lectura',v_n.fecha_lectura),
    'recurso',banco.web_recurso_aviso(p_actor,v_n.evento_id));
END;
$$;


--
-- Name: web_detalle_participacion(bigint, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_detalle_participacion(p_actor bigint, p_tipo text, p_id bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_s jsonb;v_p banco.proyecto%ROWTYPE;v_asignacion jsonb;v_evaluaciones jsonb;
BEGIN
  v_s:=banco.web_abrir_participacion(p_actor,p_tipo,p_id,false);
  SELECT * INTO v_p FROM banco.proyecto WHERE id=(v_s->>'proyecto_id')::bigint;
  IF p_tipo='candidatura' THEN
    SELECT jsonb_build_object('id',id,'estado',estado,'inicio',inicio,'fin',fin) INTO v_asignacion FROM banco.asignacion_alumno WHERE candidatura_id=p_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'fecha',e.fecha,'comentarios',e.comentarios,'recomendacion',e.recomendacion,
      'detalles',(SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',d.definicion_aplicada->>'codigo','nombre',d.definicion_aplicada->>'nombre',
        'puntuacion',d.puntuacion,'comentario',d.comentario) ORDER BY d.criterio_id),'[]'::jsonb) FROM banco.detalle_evaluacion d WHERE d.evaluacion_id=e.id)) ORDER BY e.id DESC),'[]'::jsonb)
      INTO v_evaluaciones FROM banco.evaluacion_candidato e WHERE candidatura_id=p_id;
  ELSE SELECT jsonb_build_object('id',id,'estado',estado,'inicio',inicio,'fin',fin) INTO v_asignacion FROM banco.asignacion_direccion WHERE solicitud_direccion_id=p_id;
    v_evaluaciones:='[]';
  END IF;
  RETURN jsonb_build_object('solicitud',jsonb_build_object('id',p_id,'tipo',p_tipo,'estado',v_s->>'estado','fecha_solicitud',v_s->'fecha_solicitud',
      'experiencia_aplicable',v_s->'experiencia_aplicable','justificacion',v_s->'justificacion'),
    'proyecto',jsonb_build_object('id',v_p.id,'titulo',v_p.titulo,'estado',v_p.estado,'razon_social',(SELECT razon_social FROM banco.empresa WHERE id=v_p.empresa_id)),
    'perfil',banco.consultar_perfil(p_actor,(v_s->>'titular_id')::bigint),'asignacion',v_asignacion,'evaluaciones',v_evaluaciones,
    'decisiones',(SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',d.fecha,'resultado',d.resultado,'justificacion',d.justificacion,'administrador_nombre',u.nombre) ORDER BY d.id DESC),'[]'::jsonb)
      FROM banco.decision_administrativa d JOIN banco.usuario u ON u.id=d.administrador_usuario_id
      WHERE (p_tipo='candidatura' AND d.candidatura_id=p_id) OR (p_tipo='direccion' AND d.solicitud_direccion_id=p_id)),
    'historial',(SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',e.fecha,'operacion',e.operacion,'transicion',e.transicion,'actor_nombre',u.nombre) ORDER BY e.id DESC),'[]'::jsonb)
      FROM banco.evento_auditoria e LEFT JOIN banco.usuario u ON u.id=e.actor_usuario_id
      WHERE e.entidad_afectada=CASE p_tipo WHEN 'candidatura' THEN 'candidatura' ELSE 'solicitud_direccion' END AND e.registro_afectado=p_id::text),
    'version',banco.web_version_participacion(p_tipo,p_id),'acciones',banco.web_acciones_participacion(p_actor,p_tipo,p_id));
END;
$$;


--
-- Name: web_detalle_proyecto_participacion(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_detalle_proyecto_participacion(p_actor bigint, p_proyecto bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_p banco.proyecto%ROWTYPE;v_rol text;v_docente boolean;v_alumnos jsonb;v_directores jsonb;
BEGIN
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR NOT banco.web_ambito_proyecto(p_actor,v_p) THEN
    RAISE EXCEPTION 'Proyecto fuera de tu ámbito' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN PERFORM banco.exigir_representante(p_actor,v_p.empresa_id);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  v_docente:=v_rol='profesor' AND EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND profesor_id=p_actor AND estado='vigente');
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'solicitud_id',a.candidatura_id,'estado',a.estado,'inicio',a.inicio,'fin',a.fin,'nombre',u.nombre,
      'perfil',banco.consultar_perfil(p_actor,a.alumno_id)) ORDER BY a.id DESC),'[]'::jsonb) INTO v_alumnos
    FROM banco.asignacion_alumno a JOIN banco.usuario u ON u.id=a.alumno_id WHERE a.proyecto_id=p_proyecto
      AND (v_rol IN ('administrador','empresa') OR (v_docente AND a.estado='vigente') OR (v_rol='alumno' AND a.alumno_id=p_actor));
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'solicitud_id',a.solicitud_direccion_id,'estado',a.estado,'inicio',a.inicio,'fin',a.fin,'nombre',u.nombre,
      'perfil',CASE WHEN v_rol='administrador' OR a.profesor_id=p_actor THEN banco.consultar_perfil(p_actor,a.profesor_id) ELSE NULL END) ORDER BY a.id DESC),'[]'::jsonb) INTO v_directores
    FROM banco.asignacion_direccion a JOIN banco.usuario u ON u.id=a.profesor_id WHERE a.proyecto_id=p_proyecto
      AND (v_rol IN ('administrador','empresa') OR a.profesor_id=p_actor);
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_p)||jsonb_build_object('id',v_p.id,'estado',v_p.estado,
      'habilidades',coalesce((SELECT instantanea_contenido->'habilidades' FROM banco.revision_proyecto WHERE id=v_p.revision_publicada_id),'[]'::jsonb)),
    'empresa',(SELECT jsonb_build_object('razon_social',razon_social,'sector',sector,'contacto_nombre',contacto_nombre,'contacto_correo',contacto_correo,'contacto_telefono',contacto_telefono) FROM banco.empresa WHERE id=v_p.empresa_id),
    'alumnos',v_alumnos,'directores',v_directores,'version',banco.web_version_ciclo(p_proyecto),'acciones',banco.web_acciones_ciclo(p_actor,v_p),
    'disponibilidad',banco.web_catalogo_disponibilidad(v_p),'vacante',v_rol IN ('alumno','profesor') AND v_p.estado='pausado'
      AND banco.web_admite_participacion(v_p,CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END),
    'historial',CASE WHEN v_rol IN ('administrador','empresa') OR
      (v_rol='alumno' AND EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=p_actor AND proyecto_id=p_proyecto)) OR
      (v_rol='profesor' AND EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE profesor_id=p_actor AND proyecto_id=p_proyecto)) THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha',e.fecha,'operacion',e.operacion,'transicion',e.transicion,'actor_nombre',u.nombre,
      'motivo',CASE WHEN e.operacion IN ('finalizar_proyecto','cancelar_proyecto') THEN e.resultado::jsonb->>'motivo' ELSE NULL END) ORDER BY e.id DESC),'[]'::jsonb)
      FROM banco.evento_auditoria e LEFT JOIN banco.usuario u ON u.id=e.actor_usuario_id WHERE e.entidad_afectada='proyecto' AND e.registro_afectado=p_proyecto::text
      AND e.operacion IN ('iniciar_proyecto','pausar_proyecto','reanudar_proyecto','finalizar_proyecto','cancelar_proyecto')) ELSE '[]'::jsonb END);
END;
$$;


--
-- Name: web_documento_json(adjunto.documento); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_documento_json(p_documento adjunto.documento) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'banco', 'adjunto'
    AS $$
  SELECT jsonb_build_object('id',p_documento.id,'tipo',p_documento.tipo,'habilidad_id',p_documento.habilidad_id,
    'nombre_original',p_documento.nombre_original,'tamano_bytes',p_documento.tamano_bytes,'subido',p_documento.subido);
$$;


--
-- Name: web_documentos_perfil(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_documentos_perfil(p_actor bigint, p_titular bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.consultar_perfil(p_actor,p_titular);
  RETURN coalesce((SELECT jsonb_agg(banco.web_documento_json(d) ORDER BY d.tipo,d.habilidad_id,d.subido)
    FROM adjunto.documento d
    WHERE d.titular_usuario_id=p_titular AND d.retirado IS NULL
      AND (d.tipo='curriculum' OR EXISTS(SELECT 1 FROM banco.alumno_habilidad a
        WHERE a.alumno_id=d.titular_usuario_id AND a.habilidad_id=d.habilidad_id))),'[]'::jsonb);
END;
$$;


--
-- Name: web_editar_cuenta(bigint, bigint, text, text, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_editar_cuenta(p_admin bigint, p_usuario bigint, p_nombre text, p_correo text, p_motivo text, p_version bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_editar_empresa(bigint, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_editar_empresa(p_actor bigint, p_datos jsonb, p_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_empresa bigint;v_fila banco.empresa%ROWTYPE;v_clave text;
BEGIN
  v_empresa:=banco.web_empresa_del_actor(p_actor);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_empresa(v_empresa) THEN
    RAISE EXCEPTION 'La empresa cambió; recarga sus datos antes de guardar' USING ERRCODE='40001'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'Datos de empresa inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_clave NOT IN ('razon_social','sector','identificacion','contacto_nombre','contacto_correo','contacto_telefono')
      OR jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'Datos de empresa inválidos' USING ERRCODE='23514'; END IF;
    IF length(p_datos->>v_clave)>1000 THEN
      RAISE EXCEPTION 'Un dato de empresa excede el tamaño admitido' USING ERRCODE='23514'; END IF;
  END LOOP;
  v_fila:=jsonb_populate_record(NULL::banco.empresa,p_datos);
  IF v_fila.razon_social IS NULL OR v_fila.razon_social !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'La razón social es obligatoria' USING ERRCODE='23514'; END IF;
  UPDATE banco.empresa SET razon_social=v_fila.razon_social,sector=v_fila.sector,
    identificacion=v_fila.identificacion,contacto_nombre=v_fila.contacto_nombre,
    contacto_correo=v_fila.contacto_correo,contacto_telefono=v_fila.contacto_telefono
    WHERE id=v_empresa;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario','editar_empresa','empresa',v_empresa::text,
    jsonb_build_object('version_anterior',p_version,'campos',ARRAY['razon_social','sector','identificacion','contacto_nombre','contacto_correo','contacto_telefono'])::text);
END;
$$;


--
-- Name: web_editar_proyecto(bigint, bigint, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_editar_proyecto(p_actor bigint, p_proyecto bigint, p_datos jsonb, p_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_fila banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga sus datos antes de guardar' USING ERRCODE='40001'; END IF;
  IF v_proyecto.estado NOT IN ('borrador','en_correccion') OR v_proyecto.revision_publicada_id IS NOT NULL THEN
    RAISE EXCEPTION 'Solo se puede editar un borrador o proyecto devuelto' USING ERRCODE='55000'; END IF;
  v_fila:=banco.web_validar_datos_proyecto(p_datos);
  UPDATE banco.proyecto SET titulo=v_fila.titulo,descripcion=v_fila.descripcion,problematica=v_fila.problematica,
    objetivos=v_fila.objetivos,justificacion=v_fila.justificacion,alcance=v_fila.alcance,
    requisitos_academicos=v_fila.requisitos_academicos,duracion_estimada=v_fila.duracion_estimada,modalidad=v_fila.modalidad,
    fecha_inicio_estimada=v_fila.fecha_inicio_estimada,fecha_fin_estimada=v_fila.fecha_fin_estimada,
    recursos=v_fila.recursos,cupo_maximo_alumnos=v_fila.cupo_maximo_alumnos WHERE id=p_proyecto;
  PERFORM banco.web_guardar_habilidades(p_proyecto,p_datos);
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
  VALUES(p_actor,'usuario','editar_proyecto','proyecto',p_proyecto::text,
    jsonb_build_object('version_anterior',p_version)::text);
END;
$$;


--
-- Name: web_eliminar_habilidad(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_eliminar_habilidad(p_actor bigint, p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_h banco.habilidad%ROWTYPE;v_usos jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  PERFORM pg_advisory_xact_lock(hashtextextended('web_habilidad_catalogo',0));
  SELECT * INTO v_h FROM banco.habilidad WHERE id=p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
  v_usos:=banco.usos_habilidad(p_id);
  IF (v_usos->>'alumnos')::int+(v_usos->>'proyectos')::int+(v_usos->>'evidencias')::int+(v_usos->>'instantaneas')::int>0 THEN
    RAISE EXCEPTION 'La habilidad está en uso y se conserva' USING ERRCODE='55000'; END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario','eliminar_habilidad','habilidad',p_id::text,'eliminada',to_jsonb(v_h)::text);
  DELETE FROM banco.habilidad WHERE id=p_id;
END;
$$;


--
-- Name: FUNCTION web_eliminar_habilidad(p_actor bigint, p_id bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_eliminar_habilidad(p_actor bigint, p_id bigint) IS 'UX-10: elimina una habilidad solo si no aparece en perfiles, proyectos, evidencias ni instantáneas publicadas. Auditado.';


--
-- Name: web_empresa_del_actor(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_empresa_del_actor(p_actor bigint) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_empresa bigint;
BEGIN
  PERFORM banco.exigir_aislamiento();
  SELECT empresa_id INTO v_empresa FROM banco.representacion_empresa
    WHERE usuario_id=p_actor AND vigente;
  IF NOT FOUND THEN RAISE EXCEPTION 'No hay una representación empresarial vigente'
    USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_representante(p_actor,v_empresa);
  RETURN v_empresa;
END;
$$;


--
-- Name: web_enviar_participacion(bigint, bigint, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_enviar_participacion(p_actor bigint, p_proyecto bigint, p_datos jsonb, p_version text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_rol text;v_contexto jsonb;v_clave text;v_id bigint;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR UPDATE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR UPDATE;
  ELSE RAISE EXCEPTION 'Solo alumnos y profesores pueden postularse' USING ERRCODE='42501'; END IF;
  PERFORM id FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  v_contexto:=banco.web_contexto_postulacion(p_actor,p_proyecto);
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM v_contexto->>'version' THEN
    RAISE EXCEPTION 'El contexto cambió; recarga antes de enviar' USING ERRCODE='40001'; END IF;
  IF NOT (v_contexto->'acciones' ? 'enviar') THEN RAISE EXCEPTION 'Completa el perfil y revisa solicitudes activas antes de enviar' USING ERRCODE='55000'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_rol='alumno' OR v_clave NOT IN ('experiencia_aplicable','justificacion') OR jsonb_typeof(p_datos->v_clave)<>'string' OR length(p_datos->>v_clave)>10000 THEN
      RAISE EXCEPTION 'Campos de solicitud no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF v_rol='alumno' THEN v_id:=banco.presentar_candidatura(p_proyecto,p_actor);
  ELSE v_id:=banco.solicitar_direccion(p_proyecto,p_actor,p_datos->>'experiencia_aplicable',p_datos->>'justificacion'); END IF;
  RETURN v_id;
END;
$_$;


--
-- Name: web_enviar_proyecto(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_enviar_proyecto(p_actor bigint, p_proyecto bigint, p_version text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_representante(p_actor,v_proyecto.empresa_id);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga sus datos antes de enviar' USING ERRCODE='40001'; END IF;
  RETURN banco.enviar_proyecto(p_proyecto,p_actor);
END;
$$;


--
-- Name: web_estado_cuenta(bigint, bigint, text, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_estado_cuenta(p_admin bigint, p_usuario bigint, p_estado text, p_motivo text, p_version bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_usuario banco.usuario%ROWTYPE;
BEGIN
  v_usuario:=banco.web_bloquear_cuenta(p_usuario,p_version);
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  RETURN banco.cambiar_estado_cuenta(p_admin,p_usuario,p_estado,p_motivo);
END;
$$;


--
-- Name: web_exigir_academico(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_exigir_academico(p_actor bigint) RETURNS text
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('alumno','profesor') THEN
    RAISE EXCEPTION 'El acceso requiere una cuenta académica' USING ERRCODE='42501';
  END IF;
  PERFORM banco.exigir_rol(p_actor,v_rol,true);
  RETURN v_rol;
END;
$$;


--
-- Name: web_exigir_avisos(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_exigir_avisos(p_actor bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN
    RAISE EXCEPTION 'Acceso a avisos no permitido' USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_rol(p_actor,v_rol,true);
END;
$$;


--
-- Name: web_filtros_catalogo(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_filtros_catalogo(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.*,r.instantanea_contenido,e.razon_social FROM banco.proyecto p
      JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
      JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_catalogo_publicacion_valida(p,r)
  ), habilidades AS (SELECT DISTINCT ON ((h->>'habilidad_id')::bigint) (h->>'habilidad_id')::bigint AS id,
      h->>'nombre' AS nombre,h->>'tipo' AS tipo FROM visibles v,
      LATERAL jsonb_array_elements(v.instantanea_contenido->'habilidades') h ORDER BY (h->>'habilidad_id')::bigint,v.id DESC)
  SELECT jsonb_build_object('empresas',coalesce((SELECT jsonb_agg(jsonb_build_object('id',empresa_id,'razon_social',razon_social) ORDER BY razon_social)
      FROM (SELECT DISTINCT empresa_id,razon_social FROM visibles) e),'[]'::jsonb),
    'modalidades',coalesce((SELECT jsonb_agg(modalidad ORDER BY modalidad)
      FROM (SELECT DISTINCT ON (lower(btrim(modalidad))) modalidad FROM visibles WHERE nullif(btrim(modalidad),'') IS NOT NULL
        ORDER BY lower(btrim(modalidad)),modalidad) m),'[]'::jsonb),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(habilidades) ORDER BY nombre,id) FROM habilidades),'[]'::jsonb)));
END;
$$;


--
-- Name: web_guardar_habilidad(bigint, bigint, text, text, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_guardar_habilidad(p_actor bigint, p_id bigint, p_nombre text, p_tipo text, p_descripcion text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_nombre text;v_descripcion text;v_id bigint;v_anterior jsonb;
BEGIN
  PERFORM banco.exigir_aislamiento();
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  v_nombre:=btrim(regexp_replace(coalesce(p_nombre,''),'\s+',' ','g'));
  v_descripcion:=nullif(btrim(coalesce(p_descripcion,'')),'');
  IF v_nombre='' OR length(v_nombre)>100 OR p_tipo IS NULL OR p_tipo NOT IN ('dura','blanda')
    OR length(coalesce(v_descripcion,''))>500 THEN
    RAISE EXCEPTION 'Datos de habilidad inválidos' USING ERRCODE='23514'; END IF;
  -- Serializa altas y cambios para que dos administradores no creen el mismo nombre a la vez.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_habilidad_catalogo',0));
  IF EXISTS(SELECT 1 FROM banco.habilidad WHERE banco.normalizar_habilidad(nombre)=banco.normalizar_habilidad(v_nombre)
      AND id IS DISTINCT FROM p_id) THEN
    RAISE EXCEPTION 'Ya existe una habilidad con ese nombre' USING ERRCODE='23505'; END IF;
  IF p_id IS NULL THEN
    INSERT INTO banco.habilidad(nombre,tipo,descripcion) VALUES(v_nombre,p_tipo,v_descripcion) RETURNING id INTO v_id;
  ELSE
    SELECT to_jsonb(h) INTO v_anterior FROM banco.habilidad h WHERE id=p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
    UPDATE banco.habilidad SET nombre=v_nombre,tipo=p_tipo,descripcion=v_descripcion WHERE id=p_id;
    v_id:=p_id;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,transicion,resultado)
    VALUES(p_actor,'usuario',CASE WHEN p_id IS NULL THEN 'crear_habilidad' ELSE 'editar_habilidad' END,'habilidad',v_id::text,
      CASE WHEN p_id IS NULL THEN 'creada' ELSE 'editada' END,
      jsonb_build_object('nombre',v_nombre,'tipo',p_tipo,'anterior',v_anterior)::text);
  RETURN v_id;
END;
$$;


--
-- Name: FUNCTION web_guardar_habilidad(p_actor bigint, p_id bigint, p_nombre text, p_tipo text, p_descripcion text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_guardar_habilidad(p_actor bigint, p_id bigint, p_nombre text, p_tipo text, p_descripcion text) IS 'UX-10: alta o edición de una habilidad por la administración; rechaza nombres equivalentes (mayúsculas, acentos, espacios). Auditado.';


--
-- Name: web_guardar_habilidades(bigint, jsonb); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_guardar_habilidades(p_proyecto bigint, p_datos jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  DELETE FROM banco.proyecto_habilidad WHERE proyecto_id=p_proyecto;
  INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria)
    SELECT p_proyecto,(v->>'habilidad_id')::bigint,v->>'nivel_minimo',
      coalesce((v->>'obligatoria')::boolean,false)
    FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) AS items(v);
END;
$$;


--
-- Name: web_guardar_perfil_propio(bigint, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_guardar_perfil_propio(p_actor bigint, p_datos jsonb, p_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;v_alumno banco.alumno%ROWTYPE;v_profesor banco.profesor%ROWTYPE;
BEGIN
  PERFORM banco.exigir_aislamiento();
  -- Serializa el alta sin fila y escrituras del mismo titular. En perfiles
  -- existentes respeta participante -> Usuario, compatible con 008 y D-06.
  PERFORM pg_advisory_xact_lock(hashtextextended('web_perfil:'||p_actor::text,0));
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=p_actor FOR UPDATE;
  ELSIF v_rol='profesor' THEN PERFORM usuario_id FROM banco.profesor WHERE usuario_id=p_actor FOR UPDATE;
  END IF;
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_perfil(p_actor) THEN
    RAISE EXCEPTION 'El perfil cambió; recarga y revisa sus datos antes de guardar' USING ERRCODE='40001';
  END IF;
  PERFORM banco.web_validar_perfil(v_rol,p_datos);
  IF v_rol='alumno' THEN
    v_alumno:=jsonb_populate_record(NULL::banco.alumno,p_datos-'habilidades');
    INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo,contacto_telefono)
      VALUES(p_actor,v_alumno.matricula,v_alumno.carrera,v_alumno.semestre,v_alumno.datos_academicos,v_alumno.contacto_correo,v_alumno.contacto_telefono)
      ON CONFLICT(usuario_id) DO UPDATE SET matricula=EXCLUDED.matricula,carrera=EXCLUDED.carrera,
        semestre=EXCLUDED.semestre,datos_academicos=EXCLUDED.datos_academicos,contacto_correo=EXCLUDED.contacto_correo,
        contacto_telefono=EXCLUDED.contacto_telefono;
    DELETE FROM banco.alumno_habilidad WHERE alumno_id=p_actor;
    INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,descripcion,evidencia)
      SELECT p_actor,(v->>'habilidad_id')::bigint,v->>'nivel_dominio',v->>'descripcion',v->>'evidencia'
      FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) items(v);
  ELSE
    v_profesor:=jsonb_populate_record(NULL::banco.profesor,p_datos);
    INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo,contacto_telefono)
      VALUES(p_actor,v_profesor.numero_empleado,v_profesor.especialidad,v_profesor.experiencia,v_profesor.contacto_correo,v_profesor.contacto_telefono)
      ON CONFLICT(usuario_id) DO UPDATE SET numero_empleado=EXCLUDED.numero_empleado,especialidad=EXCLUDED.especialidad,
        experiencia=EXCLUDED.experiencia,contacto_correo=EXCLUDED.contacto_correo,contacto_telefono=EXCLUDED.contacto_telefono;
  END IF;
  INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
    VALUES(p_actor,'usuario','guardar_perfil','perfil_academico',p_actor::text,
      jsonb_build_object('rol',v_rol,'version_anterior',p_version,'habilidades',CASE WHEN v_rol='alumno'
        THEN jsonb_array_length(coalesce(p_datos->'habilidades','[]'::jsonb)) ELSE 0 END)::text);
END;
$$;


--
-- Name: FUNCTION web_guardar_perfil_propio(p_actor bigint, p_datos jsonb, p_version text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_guardar_perfil_propio(p_actor bigint, p_datos jsonb, p_version text) IS 'WEB-05: titular académico activo crea/actualiza su perfil y habilidades de alumno, con CAS y auditoría; sin modificar identidad o acceso. La evidencia se almacena como texto, no se descarga ni ejecuta.';


--
-- Name: web_habilidades_admin(bigint, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_habilidades_admin(p_actor bigint, p_buscar text, p_tipo text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR length(coalesce(p_buscar,''))>100 OR (nullif(p_tipo,'') IS NOT NULL AND p_tipo NOT IN ('dura','blanda')) THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH filtrados AS MATERIALIZED (
      SELECT h.id,h.nombre,h.tipo,h.descripcion,banco.normalizar_habilidad(h.nombre) AS clave
      FROM banco.habilidad h
      WHERE (nullif(p_tipo,'') IS NULL OR h.tipo=p_tipo)
        AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(banco.normalizar_habilidad(h.nombre||' '||coalesce(h.descripcion,'')),
          banco.normalizar_habilidad(p_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY clave,id LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object(
      'datos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'nombre',p.nombre,'tipo',p.tipo,'descripcion',p.descripcion,
        'usos',banco.usos_habilidad(p.id),
        'duplicados',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'nombre',o.nombre) ORDER BY o.id),'[]'::jsonb)
          FROM banco.habilidad o WHERE o.id<>p.id AND banco.normalizar_habilidad(o.nombre)=p.clave)) ORDER BY p.clave,p.id) FROM pagina p),'[]'::jsonb),
      'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('total',count(*),'duras',count(*) FILTER (WHERE tipo='dura'),
        'blandas',count(*) FILTER (WHERE tipo='blanda')) FROM banco.habilidad)));
END;
$$;


--
-- Name: web_imagenes(bigint, bigint[], bigint[], bigint[]); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_imagenes(p_actor bigint, p_usuarios bigint[], p_empresas bigint[], p_proyectos bigint[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_imagenes(p_actor bigint, p_usuarios bigint[], p_empresas bigint[], p_proyectos bigint[]); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_imagenes(p_actor bigint, p_usuarios bigint[], p_empresas bigint[], p_proyectos bigint[]) IS 'UX-08: ids de fotos visibles para el actor (D-10) y de logos vigentes por empresa o por proyecto, hasta 100 de cada lista.';


--
-- Name: web_leer_aviso(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_leer_aviso(p_actor bigint, p_aviso bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN
    RAISE EXCEPTION 'Acceso a avisos no permitido' USING ERRCODE='42501'; END IF;
  -- La operación interna conserva primera fecha, propiedad y cuenta activa.
  RETURN banco.marcar_notificacion_leida(p_aviso,p_actor);
END;
$$;


--
-- Name: FUNCTION web_leer_aviso(p_actor bigint, p_aviso bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_leer_aviso(p_actor bigint, p_aviso bigint) IS 'WEB-07: primera lectura propia idempotente mediante018; sin borrar el aviso ni alterar su evento.';


--
-- Name: web_listar_cuentas(bigint, text, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_listar_cuentas(p_admin bigint, p_busqueda text, p_rol text, p_estado text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_listar_habilidades_perfil(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_listar_habilidades_perfil(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'nombre',nombre,'tipo',tipo,'descripcion',descripcion)
    ORDER BY tipo,nombre,id),'[]'::jsonb) FROM banco.habilidad);
END;
$$;


--
-- Name: web_listar_proyectos(bigint, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_listar_proyectos(p_actor bigint, p_buscar text, p_estado text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;v_empresa bigint;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol='administrador' THEN PERFORM banco.exigir_rol(p_actor,'administrador',true);
  ELSIF v_rol='empresa' THEN v_empresa:=banco.web_empresa_del_actor(p_actor);
  ELSE RAISE EXCEPTION 'Esta cuenta no puede consultar proyectos en este módulo' USING ERRCODE='42501'; END IF;
  IF p_limite IS NULL OR p_limite<1 OR p_limite>100 OR p_desplazamiento IS NULL OR p_desplazamiento<0
    OR (nullif(p_estado,'') IS NOT NULL AND p_estado NOT IN
      ('borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado'))
    OR length(p_buscar)>150 THEN
    RAISE EXCEPTION 'Filtros o paginación inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH filtrados AS MATERIALIZED (
    SELECT p.id,p.titulo,p.estado,p.empresa_id,e.razon_social,p.cupo_maximo_alumnos,
      r.id AS ultima_revision_id,r.numero AS numero_revision,r.fecha_envio
    FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id
    LEFT JOIN LATERAL (SELECT id,numero,fecha_envio FROM banco.revision_proyecto
      WHERE proyecto_id=p.id ORDER BY numero DESC LIMIT 1) r ON true
    WHERE (v_rol='administrador' OR p.empresa_id=v_empresa)
      AND (nullif(p_estado,'') IS NULL OR p.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('total',(SELECT count(*) FROM filtrados),
    'datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb)));
END;
$$;


--
-- Name: web_obtener_cuenta(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_obtener_cuenta(p_admin bigint, p_usuario bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_datos jsonb;
BEGIN
  PERFORM banco.exigir_rol(p_admin,'administrador',true);
  v_datos:=banco.web_datos_cuenta(p_usuario);
  IF v_datos IS NULL THEN RAISE EXCEPTION 'Cuenta inexistente' USING ERRCODE='23503'; END IF;
  RETURN v_datos;
END;
$$;


--
-- Name: web_obtener_empresa(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_obtener_empresa(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
BEGIN
  RETURN banco.web_datos_empresa(banco.web_empresa_del_actor(p_actor));
END;
$$;


--
-- Name: web_obtener_perfil_propio(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_obtener_perfil_propio(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_resultado jsonb;
BEGIN
  -- Protege el par datos/version del guardado web concurrente, incluso sin perfil.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('web_perfil:'||p_actor::text,0));
  PERFORM banco.web_exigir_academico(p_actor);
  v_resultado:=banco.consultar_perfil(p_actor,p_actor);
  RETURN v_resultado||jsonb_build_object('version',banco.web_version_perfil(p_actor));
END;
$$;


--
-- Name: web_obtener_proyecto(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_obtener_proyecto(p_actor bigint, p_proyecto bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_proyecto)||jsonb_build_object(
    'autor_usuario_id',v_proyecto.autor_usuario_id,'estado',v_proyecto.estado,
    'revision_publicada_id',v_proyecto.revision_publicada_id,'version',banco.web_version_proyecto(p_proyecto)),
    'empresa',banco.web_datos_empresa(v_proyecto.empresa_id)-'version',
    'habilidades',coalesce((SELECT jsonb_agg(jsonb_build_object('habilidad_id',h.id,'nombre',h.nombre,
      'tipo',h.tipo,'descripcion',h.descripcion,'nivel_minimo',ph.nivel_minimo,'obligatoria',ph.obligatoria) ORDER BY h.id)
      FROM banco.proyecto_habilidad ph JOIN banco.habilidad h ON h.id=ph.habilidad_id WHERE ph.proyecto_id=p_proyecto),'[]'::jsonb),
    'revisiones',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'numero',r.numero,'fecha_envio',r.fecha_envio,
      'estado_revision',r.estado_revision,'instantanea_contenido',r.instantanea_contenido,
      'decision',CASE WHEN d.id IS NULL THEN NULL ELSE jsonb_build_object('id',d.id,'resultado',d.resultado,
        'justificacion',d.justificacion,'fecha',d.fecha,'administrador_nombre',u.nombre) END) ORDER BY r.numero DESC)
      FROM banco.revision_proyecto r LEFT JOIN banco.decision_administrativa d ON d.revision_proyecto_id=r.id
      LEFT JOIN banco.usuario u ON u.id=d.administrador_usuario_id WHERE r.proyecto_id=p_proyecto),'[]'::jsonb));
END;
$$;


--
-- Name: web_obtener_proyecto_catalogo(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_obtener_proyecto_catalogo(p_actor bigint, p_proyecto bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_revision banco.revision_proyecto%ROWTYPE;v_empresa jsonb;
BEGIN
  PERFORM banco.web_exigir_academico(p_actor);
  -- Las operaciones de participación/cierre bloquean este mismo proyecto.
  -- Tras esperar se revalida su fila vigente; no mezclar una publicación
  -- anterior al cierre con la disponibilidad posterior al cierre.
  SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=p_proyecto FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible en el catálogo' USING ERRCODE='23503'; END IF;
  SELECT * INTO v_revision FROM banco.revision_proyecto WHERE id=v_proyecto.revision_publicada_id AND proyecto_id=p_proyecto;
  IF NOT FOUND OR NOT coalesce(banco.web_catalogo_publicacion_valida(v_proyecto,v_revision),false) THEN
    RAISE EXCEPTION 'Proyecto no disponible en el catálogo' USING ERRCODE='23503'; END IF;
  SELECT jsonb_build_object('razon_social',razon_social,'sector',sector,'contacto_nombre',contacto_nombre,
    'contacto_correo',contacto_correo,'contacto_telefono',contacto_telefono) INTO v_empresa FROM banco.empresa WHERE id=v_proyecto.empresa_id;
  RETURN jsonb_build_object('proyecto',banco.contenido_proyecto(v_proyecto)||jsonb_build_object('estado','publicado'),
    'empresa',v_empresa,'habilidades',v_revision.instantanea_contenido->'habilidades',
    'disponibilidad',banco.web_catalogo_disponibilidad(v_proyecto));
END;
$$;


--
-- Name: web_opciones_reporte(text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_opciones_reporte(p_tipo text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'empresas',CASE WHEN p_tipo='carga_profesores' THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'razon_social',razon_social) ORDER BY razon_social,id) FROM banco.empresa),'[]'::jsonb) END,
    'proyectos',CASE WHEN p_tipo IN ('candidaturas','direcciones','asignaciones') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'titulo',titulo) ORDER BY titulo,id) FROM banco.proyecto),'[]'::jsonb) ELSE '[]'::jsonb END,
    'profesores',CASE WHEN p_tipo IN ('direcciones','carga_profesores') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.usuario_id,'nombre',u.nombre) ORDER BY u.nombre,p.usuario_id) FROM banco.profesor p JOIN banco.usuario u ON u.id=p.usuario_id),'[]'::jsonb) ELSE '[]'::jsonb END);
$$;


--
-- Name: web_operar_participacion(bigint, text, bigint, text, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_operar_participacion(p_actor bigint, p_tipo text, p_id bigint, p_accion text, p_datos jsonb, p_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_s jsonb;v_rol text;v_clave text;
BEGIN
  v_s:=banco.web_abrir_participacion(p_actor,p_tipo,p_id,true);
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF p_accion IS NULL OR NOT ((p_accion='cancelar' AND v_rol IN ('alumno','profesor') AND p_actor=(v_s->>'titular_id')::bigint)
    OR (p_accion IN ('evaluar','preseleccionar') AND v_rol='empresa' AND p_tipo='candidatura')
    OR (p_accion IN ('aprobar','rechazar') AND v_rol='administrador')) THEN RAISE EXCEPTION 'Operación no permitida' USING ERRCODE='42501'; END IF;
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM banco.web_version_participacion(p_tipo,p_id) THEN
    RAISE EXCEPTION 'La solicitud o su contexto cambió; recarga antes de decidir' USING ERRCODE='40001'; END IF;
  IF NOT (banco.web_acciones_participacion(p_actor,p_tipo,p_id) ? p_accion) THEN RAISE EXCEPTION 'La operación ya no corresponde al estado actual' USING ERRCODE='55000'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF (p_accion IN ('cancelar','preseleccionar')) OR (p_accion IN ('aprobar','rechazar') AND v_clave<>'motivo')
      OR (p_accion='evaluar' AND v_clave NOT IN ('puntuaciones','comentarios','recomendada')) THEN RAISE EXCEPTION 'Campos no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_accion IN ('aprobar','rechazar') AND (jsonb_typeof(p_datos->'motivo') IS DISTINCT FROM 'string' OR length(p_datos->>'motivo')>1000) THEN
    RAISE EXCEPTION 'Motivo inválido' USING ERRCODE='23514'; END IF;
  IF p_accion='cancelar' THEN
    IF p_tipo='candidatura' THEN PERFORM banco.cancelar_candidatura(p_id,p_actor); ELSE PERFORM banco.cancelar_solicitud_direccion(p_id,p_actor); END IF;
  ELSIF p_accion='evaluar' THEN
    IF jsonb_typeof(p_datos->'puntuaciones') IS DISTINCT FROM 'object' OR jsonb_typeof(p_datos->'recomendada') IS DISTINCT FROM 'boolean' OR jsonb_typeof(p_datos->'comentarios') IS DISTINCT FROM 'string'
      OR length(p_datos->>'comentarios')>10000 THEN RAISE EXCEPTION 'Evaluación inválida' USING ERRCODE='23514'; END IF;
    FOR v_clave IN SELECT jsonb_object_keys(coalesce(p_datos->'puntuaciones','{}'::jsonb)) LOOP
      IF length(p_datos->'puntuaciones'->v_clave->>'comentario')>10000 THEN RAISE EXCEPTION 'Comentario demasiado largo' USING ERRCODE='23514'; END IF;
    END LOOP;
    PERFORM banco.evaluar_candidatura(p_id,p_actor,p_datos->'puntuaciones',p_datos->>'comentarios',(p_datos->>'recomendada')::boolean);
  ELSIF p_accion='preseleccionar' THEN PERFORM banco.preseleccionar_candidatura(p_id,p_actor);
  ELSIF p_tipo='candidatura' THEN PERFORM banco.resolver_candidatura(p_id,p_actor,CASE p_accion WHEN 'aprobar' THEN 'aprobada' ELSE 'rechazada' END,p_datos->>'motivo');
  ELSE PERFORM banco.resolver_direccion(p_id,p_actor,CASE p_accion WHEN 'aprobar' THEN 'aprobada' ELSE 'rechazada' END,p_datos->>'motivo'); END IF;
END;
$_$;


--
-- Name: web_operar_proyecto_participacion(bigint, bigint, text, jsonb, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_operar_proyecto_participacion(p_actor bigint, p_proyecto bigint, p_accion text, p_datos jsonb, p_version text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_p banco.proyecto%ROWTYPE;v_clave text;v_id bigint;v_fila record;
BEGIN
  -- Los cierres bloquean primero fuentes y perfiles; no retener Proyecto antes de ellos.
  IF NOT EXISTS(SELECT 1 FROM banco.usuario WHERE id=p_actor AND rol_principal='administrador') THEN
    RAISE EXCEPTION 'El ciclo del proyecto requiere administración' USING ERRCODE='42501'; END IF;
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_accion IS NULL OR p_accion NOT IN ('iniciar','reanudar','finalizar','cancelar','retirar_alumno','retirar_director') THEN RAISE EXCEPTION 'Acción de proyecto inválida' USING ERRCODE='22023'; END IF;
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF p_accion IN ('iniciar','reanudar') OR (p_accion IN ('finalizar','cancelar') AND v_clave<>'motivo')
      OR (p_accion IN ('retirar_alumno','retirar_director') AND v_clave NOT IN ('motivo','asignacion_id')) THEN RAISE EXCEPTION 'Campos no permitidos' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_accion NOT IN ('iniciar','reanudar') AND (jsonb_typeof(p_datos->'motivo') IS DISTINCT FROM 'string' OR length(p_datos->>'motivo')>1000) THEN RAISE EXCEPTION 'Motivo inválido' USING ERRCODE='23514'; END IF;
  IF p_accion IN ('finalizar','cancelar') THEN
    PERFORM id FROM banco.candidatura WHERE proyecto_id=p_proyecto AND (estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      OR id IN (SELECT candidatura_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
    PERFORM id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND (estado='pendiente'
      OR id IN (SELECT solicitud_direccion_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente')) ORDER BY id FOR UPDATE;
    FOR v_fila IN SELECT tipo,id FROM (
      SELECT 'alumno'::text tipo,alumno_id id FROM banco.candidatura WHERE proyecto_id=p_proyecto AND estado IN ('pendiente_evaluacion','evaluada','preseleccionada')
      UNION SELECT 'alumno',alumno_id FROM banco.asignacion_alumno WHERE proyecto_id=p_proyecto AND estado='vigente'
      UNION SELECT 'profesor',profesor_id FROM banco.solicitud_direccion WHERE proyecto_id=p_proyecto AND estado='pendiente'
      UNION SELECT 'profesor',profesor_id FROM banco.asignacion_direccion WHERE proyecto_id=p_proyecto AND estado='vigente') q ORDER BY tipo,id LOOP
      IF v_fila.tipo='alumno' THEN PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.id FOR UPDATE;
      ELSE PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.id FOR UPDATE; END IF;
    END LOOP;
  ELSIF p_accion IN ('retirar_alumno','retirar_director') THEN
    IF jsonb_typeof(p_datos->'asignacion_id') IS DISTINCT FROM 'number' OR p_datos->>'asignacion_id' !~ '^-?[0-9]+$' THEN RAISE EXCEPTION 'Asignación inválida' USING ERRCODE='23514'; END IF;
    v_id:=(p_datos->>'asignacion_id')::bigint;
    IF p_accion='retirar_alumno' THEN
      SELECT alumno_id AS titular INTO v_fila FROM banco.asignacion_alumno WHERE id=v_id AND proyecto_id=p_proyecto;
      IF NOT FOUND THEN RAISE EXCEPTION 'Asignación ajena al proyecto' USING ERRCODE='23503'; END IF;
      PERFORM usuario_id FROM banco.alumno WHERE usuario_id=v_fila.titular FOR UPDATE;
    ELSE
      SELECT profesor_id AS titular INTO v_fila FROM banco.asignacion_direccion WHERE id=v_id AND proyecto_id=p_proyecto;
      IF NOT FOUND THEN RAISE EXCEPTION 'Asignación ajena al proyecto' USING ERRCODE='23503'; END IF;
      PERFORM usuario_id FROM banco.profesor WHERE usuario_id=v_fila.titular FOR UPDATE;
    END IF;
  END IF;
  SELECT * INTO v_p FROM banco.proyecto WHERE id=p_proyecto FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no disponible' USING ERRCODE='23503'; END IF;
  IF p_version IS NULL OR p_version !~ '^[0-9a-f]{64}$' OR p_version IS DISTINCT FROM banco.web_version_ciclo(p_proyecto) THEN RAISE EXCEPTION 'El proyecto o sus participantes cambiaron; recarga' USING ERRCODE='40001'; END IF;
  IF NOT(banco.web_acciones_ciclo(p_actor,v_p) ? p_accion) THEN RAISE EXCEPTION 'Acción no disponible para este estado' USING ERRCODE='55000'; END IF;
  CASE p_accion
    WHEN 'iniciar' THEN PERFORM banco.iniciar_proyecto(p_proyecto,p_actor);
    WHEN 'reanudar' THEN PERFORM banco.reanudar_proyecto(p_proyecto,p_actor);
    WHEN 'finalizar' THEN PERFORM banco.finalizar_proyecto(p_proyecto,p_actor,p_datos->>'motivo');
    WHEN 'cancelar' THEN PERFORM banco.cancelar_proyecto(p_proyecto,p_actor,p_datos->>'motivo');
    WHEN 'retirar_alumno' THEN PERFORM banco.retirar_alumno(v_id,p_actor,p_datos->>'motivo');
    WHEN 'retirar_director' THEN PERFORM banco.retirar_director(v_id,p_actor,p_datos->>'motivo');
  END CASE;
END;
$_$;


--
-- Name: web_panorama_reportes(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_panorama_reportes(p_actor bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_panorama_reportes(p_actor bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_panorama_reportes(p_actor bigint) IS 'UX-09/RF-41: conteos globales por estado de proyectos, candidaturas y direcciones, y carga docente vigente frente al límite de tres. Solo administración.';


--
-- Name: web_participacion_base(text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_participacion_base(p_tipo text, p_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_datos jsonb;
BEGIN
  IF p_tipo='candidatura' THEN
    SELECT to_jsonb(c)||jsonb_build_object('titular_id',alumno_id,'tipo',p_tipo) INTO v_datos FROM banco.candidatura c WHERE id=p_id;
  ELSIF p_tipo='direccion' THEN
    SELECT to_jsonb(s)||jsonb_build_object('titular_id',profesor_id,'tipo',p_tipo) INTO v_datos FROM banco.solicitud_direccion s WHERE id=p_id;
  ELSE RAISE EXCEPTION 'Tipo de participación inválido' USING ERRCODE='22023'; END IF;
  IF v_datos IS NULL THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='23503'; END IF;
  RETURN v_datos;
END;
$$;


--
-- Name: web_proyectos_participacion(bigint, text, text, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_proyectos_participacion(p_actor bigint, p_estado text, p_buscar text, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  IF v_rol IS NULL OR v_rol NOT IN ('administrador','empresa','alumno','profesor') THEN RAISE EXCEPTION 'Acceso no permitido' USING ERRCODE='42501'; END IF;
  IF v_rol='empresa' THEN PERFORM banco.web_empresa_del_actor(p_actor);
  ELSE PERFORM banco.exigir_rol(p_actor,v_rol,true); END IF;
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100 OR p_desplazamiento IS NULL OR p_desplazamiento<0 OR length(p_buscar)>150
    OR (nullif(p_estado,'') IS NOT NULL AND p_estado NOT IN ('borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado')) THEN RAISE EXCEPTION 'Filtros inválidos' USING ERRCODE='23514'; END IF;
  RETURN (WITH visibles AS MATERIALIZED (
    SELECT p.id,p.titulo,p.estado,e.razon_social,p.cupo_maximo_alumnos,
      (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p.id AND estado='vigente') AS alumnos_vigentes,
      (SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=p.id AND estado='vigente') AS directores_vigentes,
      (v_rol IN ('alumno','profesor') AND p.estado='pausado' AND banco.web_admite_participacion(p,CASE v_rol WHEN 'alumno' THEN 'candidatura' ELSE 'direccion' END)) AS vacante
      FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id WHERE banco.web_ambito_proyecto(p_actor,p)
      AND (nullif(p_estado,'') IS NULL OR p.estado=p_estado)
      AND (nullif(btrim(p_buscar),'') IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(btrim(p_buscar)))>0)
  ), pagina AS (SELECT * FROM visibles ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
  SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM visibles)));
END;
$$;


--
-- Name: web_recomendaciones(bigint, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_recomendaciones(p_actor bigint, p_limite integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_rol text;
BEGIN
  v_rol:=banco.web_exigir_academico(p_actor);
  IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'Límite de recomendaciones inválido' USING ERRCODE='23514'; END IF;
  -- El profesor no registra habilidades estructuradas; no hay con qué recomendar.
  IF v_rol<>'alumno' THEN RETURN '[]'::jsonb; END IF;
  RETURN coalesce((
    WITH propias AS MATERIALIZED (SELECT habilidad_id FROM banco.alumno_habilidad WHERE alumno_id=p_actor),
    visibles AS MATERIALIZED (
      SELECT p.id,p.titulo,p.descripcion,p.modalidad,p.cupo_maximo_alumnos,e.razon_social,r.instantanea_contenido,
        (banco.web_catalogo_disponibilidad(p)->>'plazas_disponibles')::integer AS plazas_disponibles
      FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id AND r.proyecto_id=p.id
        JOIN banco.empresa e ON e.id=p.empresa_id
      WHERE banco.web_catalogo_publicacion_valida(p,r)
        AND NOT EXISTS(SELECT 1 FROM banco.candidatura c WHERE c.proyecto_id=p.id AND c.alumno_id=p_actor)
        AND NOT EXISTS(SELECT 1 FROM banco.asignacion_alumno a WHERE a.proyecto_id=p.id AND a.alumno_id=p_actor)),
    puntuados AS (
      SELECT v.id,v.titulo,v.descripcion,v.modalidad,v.razon_social,v.plazas_disponibles,v.cupo_maximo_alumnos,
        count(*) AS requeridas,
        count(*) FILTER (WHERE (h->>'habilidad_id')::bigint IN (SELECT habilidad_id FROM propias)) AS cumplidas,
        count(*) FILTER (WHERE coalesce((h->>'obligatoria')::boolean,false)
          AND (h->>'habilidad_id')::bigint NOT IN (SELECT habilidad_id FROM propias)) AS faltan_obligatorias,
        coalesce(jsonb_agg(jsonb_build_object('nombre',h->>'nombre','obligatoria',coalesce((h->>'obligatoria')::boolean,false))
          ORDER BY NOT coalesce((h->>'obligatoria')::boolean,false),h->>'nombre')
          FILTER (WHERE (h->>'habilidad_id')::bigint NOT IN (SELECT habilidad_id FROM propias)),'[]'::jsonb) AS faltantes
      FROM visibles v, LATERAL jsonb_array_elements(v.instantanea_contenido->'habilidades') h
      WHERE v.plazas_disponibles>0
      GROUP BY v.id,v.titulo,v.descripcion,v.modalidad,v.razon_social,v.plazas_disponibles,v.cupo_maximo_alumnos),
    elegidos AS (
      SELECT * FROM puntuados WHERE cumplidas>0
      ORDER BY faltan_obligatorias,cumplidas::numeric/requeridas DESC,cumplidas DESC,id DESC
      LIMIT p_limite)
    SELECT jsonb_agg(jsonb_build_object('id',id,'titulo',titulo,'descripcion',descripcion,'modalidad',modalidad,
      'razon_social',razon_social,'plazas_disponibles',plazas_disponibles,'cupo_maximo_alumnos',cupo_maximo_alumnos,
      'coincidencia',jsonb_build_object('requeridas',requeridas,'cumplidas',cumplidas,'faltantes',faltantes))
      ORDER BY faltan_obligatorias,cumplidas::numeric/requeridas DESC,cumplidas DESC,id DESC)
    FROM elegidos
  ),'[]'::jsonb);
END;
$$;


--
-- Name: FUNCTION web_recomendaciones(p_actor bigint, p_limite integer); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_recomendaciones(p_actor bigint, p_limite integer) IS 'UX-06: hasta 20 proyectos publicados con plazas, donde el alumno actor no tiene candidatura ni asignación, ordenados por obligatorias cumplidas y proporción de coincidencia. Profesor recibe arreglo vacío.';


--
-- Name: web_recurso_aviso(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_recurso_aviso(p_actor bigint, p_evento bigint) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_e banco.evento_auditoria%ROWTYPE;v_id bigint;v_c bigint;v_d bigint;v_p bigint;v_rol text;v_proyecto banco.proyecto%ROWTYPE;
BEGIN
  SELECT * INTO v_e FROM banco.evento_auditoria WHERE id=p_evento;
  IF NOT FOUND OR v_e.registro_afectado !~ '^-?[0-9]+$' THEN RETURN NULL; END IF;
  BEGIN v_id:=v_e.registro_afectado::bigint; EXCEPTION WHEN numeric_value_out_of_range THEN RETURN NULL; END;
  SELECT rol_principal INTO v_rol FROM banco.usuario WHERE id=p_actor;
  CASE v_e.entidad_afectada
    WHEN 'proyecto' THEN v_p:=v_id;
    WHEN 'candidatura' THEN v_c:=v_id;
    WHEN 'solicitud_direccion' THEN v_d:=v_id;
    WHEN 'evaluacion_candidato' THEN SELECT candidatura_id INTO v_c FROM banco.evaluacion_candidato WHERE id=v_id;
    WHEN 'asignacion_alumno' THEN SELECT candidatura_id INTO v_c FROM banco.asignacion_alumno WHERE id=v_id;
    WHEN 'asignacion_direccion' THEN SELECT solicitud_direccion_id INTO v_d FROM banco.asignacion_direccion WHERE id=v_id;
    ELSE RETURN NULL;
  END CASE;
  IF v_c IS NOT NULL THEN
    SELECT proyecto_id INTO v_p FROM banco.candidatura WHERE id=v_c;
    IF EXISTS(SELECT 1 FROM banco.candidatura c JOIN banco.proyecto p ON p.id=c.proyecto_id
      WHERE c.id=v_c AND (v_rol='administrador' OR (v_rol='alumno' AND c.alumno_id=p_actor)
        OR (v_rol='empresa' AND EXISTS(SELECT 1 FROM banco.representacion_empresa WHERE empresa_id=p.empresa_id AND usuario_id=p_actor AND vigente)))) THEN
      RETURN jsonb_build_object('tipo','candidatura','id',v_c); END IF;
  ELSIF v_d IS NOT NULL THEN
    SELECT proyecto_id INTO v_p FROM banco.solicitud_direccion WHERE id=v_d;
    IF EXISTS(SELECT 1 FROM banco.solicitud_direccion WHERE id=v_d AND (v_rol='administrador' OR (v_rol='profesor' AND profesor_id=p_actor))) THEN
      RETURN jsonb_build_object('tipo','direccion','id',v_d); END IF;
  END IF;
  IF v_p IS NOT NULL THEN
    SELECT * INTO v_proyecto FROM banco.proyecto WHERE id=v_p;
    IF FOUND AND banco.web_ambito_proyecto(p_actor,v_proyecto) THEN
      RETURN jsonb_build_object('tipo','proyecto','id',v_p,'contexto',
        CASE WHEN v_e.operacion IN ('enviar_proyecto','resolver_publicacion') THEN 'publicacion' ELSE 'seguimiento' END);
    END IF;
  END IF;
  RETURN NULL;
END;
$_$;


--
-- Name: web_registrar_acceso(bigint, bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_registrar_acceso(p_actor bigint, p_version bigint, p_operacion text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_registrar_documento(bigint, text, bigint, text, text, integer, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_registrar_documento(p_actor bigint, p_tipo text, p_habilidad bigint, p_nombre text, p_ruta text, p_tamano integer, p_sha256 text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_registrar_documento(p_actor bigint, p_tipo text, p_habilidad bigint, p_nombre text, p_ruta text, p_tamano integer, p_sha256 text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_registrar_documento(p_actor bigint, p_tipo text, p_habilidad bigint, p_nombre text, p_ruta text, p_tamano integer, p_sha256 text) IS 'D-11: registra un PDF propio ya almacenado. Currículum reemplaza al vigente; evidencia exige habilidad del perfil y admite tres vigentes. Auditado.';


--
-- Name: web_registrar_imagen(bigint, text, text, integer, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_registrar_imagen(p_actor bigint, p_tipo text, p_ruta text, p_tamano integer, p_sha256 text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: FUNCTION web_registrar_imagen(p_actor bigint, p_tipo text, p_ruta text, p_tamano integer, p_sha256 text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_registrar_imagen(p_actor bigint, p_tipo text, p_ruta text, p_tamano integer, p_sha256 text) IS 'UX-08: registra la foto propia (alumno/profesor) o el logo de la empresa representada, reemplazando la vigente. Auditado.';


--
-- Name: web_relevar_representante(bigint, bigint, text, text, text, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_relevar_representante(p_admin bigint, p_empresa bigint, p_nombre text, p_correo text, p_hash text, p_motivo text, p_representante_esperado bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_reporte(bigint, text, jsonb, integer, integer); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_reporte(p_actor bigint, p_tipo text, p_filtros jsonb, p_limite integer, p_desplazamiento integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_clave text;v_permitidos text[];v_buscar text;v_estado text;v_empresa bigint;v_proyecto bigint;v_profesor bigint;
BEGIN
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_tipo IS NULL OR p_tipo NOT IN ('proyectos','candidaturas','direcciones','carga_profesores','asignaciones')
    OR p_filtros IS NULL OR jsonb_typeof(p_filtros)<>'object' OR p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 100
    OR p_desplazamiento IS NULL OR p_desplazamiento<0 THEN RAISE EXCEPTION 'Reporte o paginación inválidos' USING ERRCODE='23514'; END IF;
  v_permitidos:=CASE p_tipo
    WHEN 'proyectos' THEN ARRAY['buscar','estado','empresa_id']
    WHEN 'candidaturas' THEN ARRAY['buscar','estado','empresa_id','proyecto_id']
    WHEN 'direcciones' THEN ARRAY['buscar','estado','empresa_id','proyecto_id','profesor_id']
    WHEN 'carga_profesores' THEN ARRAY['buscar','profesor_id']
    ELSE ARRAY['buscar','estado','empresa_id','proyecto_id'] END;
  FOR v_clave IN SELECT jsonb_object_keys(p_filtros) LOOP
    IF NOT(v_clave=ANY(v_permitidos)) THEN RAISE EXCEPTION 'Filtro no aplicable al reporte' USING ERRCODE='23514'; END IF;
    IF p_filtros->v_clave='null'::jsonb THEN CONTINUE; END IF;
    IF v_clave IN ('buscar','estado') THEN
      IF jsonb_typeof(p_filtros->v_clave)<>'string' OR length(p_filtros->>v_clave)>150 THEN RAISE EXCEPTION 'Filtro textual inválido' USING ERRCODE='23514'; END IF;
    ELSIF jsonb_typeof(p_filtros->v_clave)<>'number' OR p_filtros->>v_clave !~ '^-?[0-9]+$' OR p_filtros->>v_clave='0' THEN
      RAISE EXCEPTION 'Identificador de filtro inválido' USING ERRCODE='23514';
    END IF;
  END LOOP;
  v_buscar:=nullif(btrim(p_filtros->>'buscar'),'');v_estado:=nullif(p_filtros->>'estado','');
  BEGIN
    v_empresa:=(p_filtros->>'empresa_id')::bigint;v_proyecto:=(p_filtros->>'proyecto_id')::bigint;v_profesor:=(p_filtros->>'profesor_id')::bigint;
  EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN RAISE EXCEPTION 'Identificador de filtro inválido' USING ERRCODE='23514'; END;
  IF v_estado IS NOT NULL AND NOT (v_estado=ANY(CASE p_tipo
    WHEN 'proyectos' THEN ARRAY['borrador','en_revision','en_correccion','publicado','rechazado','en_curso','pausado','finalizado','cancelado']
    WHEN 'candidaturas' THEN ARRAY['pendiente_evaluacion','evaluada','preseleccionada','aprobada','rechazada','cancelada']
    WHEN 'direcciones' THEN ARRAY['pendiente','aprobada','rechazada','cancelada']
    ELSE ARRAY['vigente','finalizada','revocada'] END)) THEN RAISE EXCEPTION 'Estado no aplicable al reporte' USING ERRCODE='23514'; END IF;

  IF p_tipo='proyectos' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT p.id,p.titulo,p.estado,p.empresa_id,e.razon_social,p.cupo_maximo_alumnos,
        (SELECT count(*) FROM banco.asignacion_alumno WHERE proyecto_id=p.id AND estado='vigente') AS alumnos_vigentes,
        (SELECT count(*) FROM banco.asignacion_direccion WHERE proyecto_id=p.id AND estado='vigente') AS directores_vigentes
      FROM banco.proyecto p JOIN banco.empresa e ON e.id=p.empresa_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_estado IS NULL OR p.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'alumnos_vigentes',coalesce(sum(alumnos_vigentes),0),'directores_vigentes',coalesce(sum(directores_vigentes),0)) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='candidaturas' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT c.id,c.proyecto_id,p.titulo,e.razon_social,u.nombre AS solicitante_nombre,c.estado,c.fecha_solicitud
      FROM banco.candidatura c JOIN banco.proyecto p ON p.id=c.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=c.alumno_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_estado IS NULL OR c.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'activas',count(*) FILTER(WHERE estado IN ('pendiente_evaluacion','evaluada','preseleccionada')),
        'aprobadas',count(*) FILTER(WHERE estado='aprobada'),'rechazadas',count(*) FILTER(WHERE estado='rechazada'),'canceladas',count(*) FILTER(WHERE estado='cancelada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='direcciones' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT s.id,s.proyecto_id,p.titulo,e.razon_social,u.nombre AS solicitante_nombre,s.estado,s.fecha_solicitud
      FROM banco.solicitud_direccion s JOIN banco.proyecto p ON p.id=s.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=s.profesor_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_profesor IS NULL OR s.profesor_id=v_profesor)
        AND (v_estado IS NULL OR s.estado=v_estado) AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'pendientes',count(*) FILTER(WHERE estado='pendiente'),'aprobadas',count(*) FILTER(WHERE estado='aprobada'),
        'rechazadas',count(*) FILTER(WHERE estado='rechazada'),'canceladas',count(*) FILTER(WHERE estado='cancelada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSIF p_tipo='carga_profesores' THEN
    RETURN (WITH filtrados AS MATERIALIZED (
      SELECT pr.usuario_id AS profesor_id,u.nombre,(SELECT count(*) FROM banco.asignacion_direccion WHERE profesor_id=pr.usuario_id AND estado='vigente') AS proyectos_vigentes,3 AS limite_proyectos
      FROM banco.profesor pr JOIN banco.usuario u ON u.id=pr.usuario_id
      WHERE (v_profesor IS NULL OR pr.usuario_id=v_profesor) AND (v_buscar IS NULL OR strpos(lower(u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY profesor_id DESC LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY profesor_id DESC) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'proyectos_vigentes',coalesce(sum(proyectos_vigentes),0),'profesores_con_carga',count(*) FILTER(WHERE proyectos_vigentes>0)) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  ELSE
    RETURN (WITH origen AS MATERIALIZED (
      SELECT a.id,'alumno'::text AS tipo,a.candidatura_id AS solicitud_id,a.alumno_id AS titular_id,a.proyecto_id,a.estado,a.inicio,a.fin FROM banco.asignacion_alumno a
      UNION ALL SELECT a.id,'direccion'::text,a.solicitud_direccion_id,a.profesor_id,a.proyecto_id,a.estado,a.inicio,a.fin FROM banco.asignacion_direccion a
    ), filtrados AS MATERIALIZED (
      SELECT a.id,a.tipo,a.solicitud_id,a.proyecto_id,p.titulo,e.razon_social,u.nombre AS participante_nombre,a.estado,a.inicio,a.fin
      FROM origen a JOIN banco.proyecto p ON p.id=a.proyecto_id JOIN banco.empresa e ON e.id=p.empresa_id JOIN banco.usuario u ON u.id=a.titular_id
      WHERE (v_empresa IS NULL OR p.empresa_id=v_empresa) AND (v_proyecto IS NULL OR p.id=v_proyecto) AND (v_estado IS NULL OR a.estado=v_estado)
        AND (v_buscar IS NULL OR strpos(lower(p.titulo||' '||e.razon_social||' '||u.nombre),lower(v_buscar))>0)
    ), pagina AS (SELECT * FROM filtrados ORDER BY id DESC,tipo LIMIT p_limite OFFSET p_desplazamiento)
    SELECT jsonb_build_object('datos',coalesce((SELECT jsonb_agg(to_jsonb(pagina) ORDER BY id DESC,tipo) FROM pagina),'[]'::jsonb),'total',(SELECT count(*) FROM filtrados),
      'resumen',(SELECT jsonb_build_object('registros',count(*),'alumnos_vigentes',count(*) FILTER(WHERE tipo='alumno' AND estado='vigente'),
        'directores_vigentes',count(*) FILTER(WHERE tipo='direccion' AND estado='vigente'),'finalizadas',count(*) FILTER(WHERE estado='finalizada'),'revocadas',count(*) FILTER(WHERE estado='revocada')) FROM filtrados),
      'opciones',banco.web_opciones_reporte(p_tipo)));
  END IF;
END;
$_$;


--
-- Name: FUNCTION web_reporte(p_actor bigint, p_tipo text, p_filtros jsonb, p_limite integer, p_desplazamiento integer); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_reporte(p_actor bigint, p_tipo text, p_filtros jsonb, p_limite integer, p_desplazamiento integer) IS 'WEB-07/RF-41: cinco consultas administrativas con filtros estrictos y totales del conjunto filtrado antes de paginar. Sin exportación ni datos de acceso, evidencias o rúbricas.';


--
-- Name: web_resolver_publicacion(bigint, bigint, bigint, text, text, integer, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_resolver_publicacion(p_actor bigint, p_proyecto bigint, p_revision bigint, p_resultado text, p_motivo text, p_cupo_validado integer, p_version text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_proyecto banco.proyecto%ROWTYPE;v_enviado integer;
BEGIN
  v_proyecto:=banco.web_abrir_proyecto(p_actor,p_proyecto);
  PERFORM banco.exigir_rol(p_actor,'administrador',true);
  IF p_version IS NULL OR p_version IS DISTINCT FROM banco.web_version_proyecto(p_proyecto) THEN
    RAISE EXCEPTION 'El proyecto cambió; recarga la revisión antes de resolver' USING ERRCODE='40001'; END IF;
  SELECT (instantanea_contenido->'proyecto'->>'cupo_maximo_alumnos')::integer INTO v_enviado
    FROM banco.revision_proyecto WHERE id=p_revision AND proyecto_id=p_proyecto;
  IF NOT FOUND THEN RAISE EXCEPTION 'Revisión inexistente para este proyecto' USING ERRCODE='23503'; END IF;
  IF p_resultado='aprobada' AND (p_cupo_validado IS NULL OR p_cupo_validado IS DISTINCT FROM v_enviado
    OR p_cupo_validado IS DISTINCT FROM v_proyecto.cupo_maximo_alumnos) THEN
    RAISE EXCEPTION 'Confirma el cupo propuesto en esta revisión exacta para publicar' USING ERRCODE='23514'; END IF;
  IF p_resultado IS DISTINCT FROM 'aprobada' AND p_cupo_validado IS NOT NULL THEN
    RAISE EXCEPTION 'El cupo se valida únicamente al aprobar la publicación' USING ERRCODE='23514'; END IF;
  RETURN banco.resolver_publicacion(p_revision,p_actor,p_resultado,p_motivo);
END;
$$;


--
-- Name: FUNCTION web_resolver_publicacion(p_actor bigint, p_proyecto bigint, p_revision bigint, p_resultado text, p_motivo text, p_cupo_validado integer, p_version text); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_resolver_publicacion(p_actor bigint, p_proyecto bigint, p_revision bigint, p_resultado text, p_motivo text, p_cupo_validado integer, p_version text) IS 'WEB-04: aprobación/devolución/rechazo de revisión exacta; aprobar confirma cupo propuesto sin cambiarlo, audita y genera avisos internos atómicos mediante los contratos existentes.';


--
-- Name: web_restablecer_clave(bigint, bigint, text, text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_restablecer_clave(p_admin bigint, p_usuario bigint, p_hash text, p_motivo text, p_version bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
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


--
-- Name: web_retirar_documento(bigint, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_retirar_documento(p_actor bigint, p_documento bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: web_retirar_imagen(bigint, text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_retirar_imagen(p_actor bigint, p_tipo text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'banco', 'adjunto', 'pg_temp'
    AS $$
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


--
-- Name: web_validar_datos_proyecto(jsonb); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_validar_datos_proyecto(p_datos jsonb) RETURNS banco.proyecto
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_clave text;v_item jsonb;v_id bigint;v_vistos bigint[]:='{}';v_fila banco.proyecto%ROWTYPE;
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'Datos de proyecto inválidos' USING ERRCODE='23514'; END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF v_clave NOT IN ('titulo','descripcion','problematica','objetivos','justificacion','alcance','requisitos_academicos',
      'duracion_estimada','modalidad','fecha_inicio_estimada','fecha_fin_estimada','recursos','cupo_maximo_alumnos','habilidades') THEN
      RAISE EXCEPTION 'El proyecto contiene campos no permitidos' USING ERRCODE='23514'; END IF;
    IF v_clave NOT IN ('cupo_maximo_alumnos','habilidades') AND jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'Un campo de proyecto no contiene texto válido' USING ERRCODE='23514'; END IF;
    IF v_clave NOT IN ('cupo_maximo_alumnos','habilidades') AND length(p_datos->>v_clave)>20000 THEN
      RAISE EXCEPTION 'Un campo de proyecto excede el tamaño admitido' USING ERRCODE='23514'; END IF;
  END LOOP;
  IF p_datos ? 'cupo_maximo_alumnos' AND jsonb_typeof(p_datos->'cupo_maximo_alumnos')<>'null'
    AND (jsonb_typeof(p_datos->'cupo_maximo_alumnos') NOT IN ('string','number')
      OR p_datos->>'cupo_maximo_alumnos' !~ '^[0-9]+$') THEN
    RAISE EXCEPTION 'El cupo requiere un entero positivo' USING ERRCODE='23514'; END IF;
  FOREACH v_clave IN ARRAY ARRAY['fecha_inicio_estimada','fecha_fin_estimada'] LOOP
    IF p_datos->>v_clave IS NOT NULL AND p_datos->>v_clave !~ '^\d{4}-\d{2}-\d{2}$' THEN
      RAISE EXCEPTION 'Las fechas requieren formato año-mes-día' USING ERRCODE='23514'; END IF;
  END LOOP;
  BEGIN v_fila:=jsonb_populate_record(NULL::banco.proyecto,p_datos-'habilidades');
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Cupo o fecha de proyecto inválidos' USING ERRCODE='23514'; END;
  IF v_fila.titulo IS NULL OR v_fila.titulo !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El borrador requiere un título' USING ERRCODE='23514'; END IF;
  IF v_fila.cupo_maximo_alumnos IS NOT NULL AND v_fila.cupo_maximo_alumnos<1 THEN
    RAISE EXCEPTION 'El cupo requiere un entero positivo' USING ERRCODE='23514'; END IF;
  IF coalesce(jsonb_typeof(p_datos->'habilidades'),'array')<>'array' THEN
    RAISE EXCEPTION 'Las habilidades requieren una lista' USING ERRCODE='23514'; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) LOOP
    IF jsonb_typeof(v_item)<>'object' OR NOT v_item ? 'habilidad_id' THEN
      RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) k WHERE k NOT IN ('habilidad_id','nivel_minimo','obligatoria'))
      OR jsonb_typeof(v_item->'habilidad_id') NOT IN ('string','number')
      OR v_item->>'habilidad_id' !~ '^-?[0-9]+$'
      OR (v_item ? 'nivel_minimo' AND jsonb_typeof(v_item->'nivel_minimo') NOT IN ('string','null'))
      OR length(v_item->>'nivel_minimo')>250
      OR (v_item ? 'obligatoria' AND (jsonb_typeof(v_item->'obligatoria') NOT IN ('boolean','number','string')
        OR v_item->>'obligatoria' NOT IN ('true','false','0','1'))) THEN
      RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END IF;
    BEGIN v_id:=(v_item->>'habilidad_id')::bigint;
    EXCEPTION WHEN numeric_value_out_of_range THEN RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END;
    IF v_id=ANY(v_vistos) THEN RAISE EXCEPTION 'No se permite repetir una habilidad' USING ERRCODE='23514'; END IF;
    v_vistos:=array_append(v_vistos,v_id);
    PERFORM id FROM banco.habilidad WHERE id=v_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
  END LOOP;
  RETURN v_fila;
END;
$_$;


--
-- Name: web_validar_hash(text); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_validar_hash(p_hash text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
BEGIN
  IF p_hash IS NULL OR p_hash !~ '^\$2y\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}$' THEN
    RAISE EXCEPTION 'La operación web requiere un hash bcrypt generado por el servidor'
      USING ERRCODE='23514';
  END IF;
END;
$_$;


--
-- Name: web_validar_perfil(text, jsonb); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_validar_perfil(p_rol text, p_datos jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $_$
DECLARE v_clave text;v_item jsonb;v_id bigint;v_vistos bigint[]:='{}';
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos)<>'object' THEN
    RAISE EXCEPTION 'El perfil requiere datos válidos' USING ERRCODE='23514';
  END IF;
  FOR v_clave IN SELECT jsonb_object_keys(p_datos) LOOP
    IF (p_rol='alumno' AND v_clave NOT IN ('matricula','carrera','semestre','datos_academicos','contacto_correo','contacto_telefono','habilidades'))
      OR (p_rol='profesor' AND v_clave NOT IN ('numero_empleado','especialidad','experiencia','contacto_correo','contacto_telefono')) THEN
      RAISE EXCEPTION 'El perfil contiene campos no permitidos' USING ERRCODE='23514';
    END IF;
    IF v_clave NOT IN ('semestre','habilidades') THEN
      IF jsonb_typeof(p_datos->v_clave) NOT IN ('string','null') OR length(p_datos->>v_clave)>10000 THEN
        RAISE EXCEPTION 'Un campo del perfil no contiene texto válido' USING ERRCODE='23514';
      END IF;
    END IF;
  END LOOP;
  IF p_rol='alumno' THEN
    IF coalesce(p_datos->>'matricula','') !~ '[^[:space:]]' THEN
      RAISE EXCEPTION 'La matrícula es obligatoria' USING ERRCODE='23514';
    END IF;
    IF p_datos ? 'semestre' AND jsonb_typeof(p_datos->'semestre')<>'null'
      AND (jsonb_typeof(p_datos->'semestre') NOT IN ('string','number') OR p_datos->>'semestre' !~ '^[0-9]+$') THEN
      RAISE EXCEPTION 'El semestre requiere un entero positivo' USING ERRCODE='23514';
    END IF;
    BEGIN
      IF p_datos->>'semestre' IS NOT NULL AND (p_datos->>'semestre')::smallint<=0 THEN
        RAISE EXCEPTION 'El semestre debe ser positivo' USING ERRCODE='23514';
      END IF;
    EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN
      RAISE EXCEPTION 'Semestre inválido' USING ERRCODE='23514';
    END;
    IF p_datos ? 'habilidades' AND jsonb_typeof(p_datos->'habilidades')<>'array' THEN
      RAISE EXCEPTION 'Las habilidades requieren una lista' USING ERRCODE='23514';
    END IF;
    IF jsonb_array_length(coalesce(p_datos->'habilidades','[]'::jsonb))>200 THEN
      RAISE EXCEPTION 'La lista de habilidades supera el tamaño admitido' USING ERRCODE='23514';
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(p_datos->'habilidades','[]'::jsonb)) LOOP
      IF jsonb_typeof(v_item)<>'object' OR NOT v_item ? 'habilidad_id' THEN
        RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514';
      END IF;
      IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_item) k WHERE k NOT IN ('habilidad_id','nivel_dominio','descripcion','evidencia'))
        OR jsonb_typeof(v_item->'habilidad_id') NOT IN ('string','number')
        OR v_item->>'habilidad_id' !~ '^-?[0-9]+$' THEN
        RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514';
      END IF;
      FOREACH v_clave IN ARRAY ARRAY['nivel_dominio','descripcion','evidencia'] LOOP
        IF v_item ? v_clave AND (jsonb_typeof(v_item->v_clave) NOT IN ('string','null') OR length(v_item->>v_clave)>10000) THEN
          RAISE EXCEPTION 'Los datos de habilidad deben ser texto' USING ERRCODE='23514';
        END IF;
      END LOOP;
      BEGIN v_id:=(v_item->>'habilidad_id')::bigint;
      EXCEPTION WHEN numeric_value_out_of_range THEN RAISE EXCEPTION 'Habilidad inválida' USING ERRCODE='23514'; END;
      IF v_id=ANY(v_vistos) THEN RAISE EXCEPTION 'No se permite repetir una habilidad' USING ERRCODE='23514'; END IF;
      v_vistos:=array_append(v_vistos,v_id);
      PERFORM id FROM banco.habilidad WHERE id=v_id FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Habilidad inexistente' USING ERRCODE='23503'; END IF;
    END LOOP;
  ELSIF coalesce(p_datos->>'numero_empleado','') !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'El número de empleado es obligatorio' USING ERRCODE='23514';
  END IF;
END;
$_$;


--
-- Name: web_version_ciclo(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_version_ciclo(p_proyecto bigint) RETURNS text
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
 SELECT encode(sha256(convert_to(jsonb_build_object('proyecto',banco.web_version_proyecto(p_proyecto),
  'candidaturas',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM banco.candidatura c WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'direcciones',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM banco.solicitud_direccion s WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'alumnos',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM banco.asignacion_alumno a WHERE proyecto_id=p_proyecto),'[]'::jsonb),
  'directores',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM banco.asignacion_direccion a WHERE proyecto_id=p_proyecto),'[]'::jsonb)
 )::text,'UTF8')),'hex');
$$;


--
-- Name: web_version_empresa(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_version_empresa(p_empresa bigint) RETURNS text
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('empresa',to_jsonb(e),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='empresa' AND registro_afectado=e.id::text))::text,'UTF8')),'hex')
  FROM banco.empresa e WHERE e.id=p_empresa;
$$;


--
-- Name: web_version_participacion(text, bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_version_participacion(p_tipo text, p_id bigint) RETURNS text
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
DECLARE v_datos jsonb;
BEGIN
  v_datos:=banco.web_participacion_base(p_tipo,p_id);
  RETURN encode(sha256(convert_to(jsonb_build_object('solicitud',v_datos,
    'perfil',banco.web_version_perfil((v_datos->>'titular_id')::bigint),
    'ciclo',banco.web_version_ciclo((v_datos->>'proyecto_id')::bigint),
    'evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria WHERE entidad_afectada=
      CASE p_tipo WHEN 'candidatura' THEN 'candidatura' ELSE 'solicitud_direccion' END AND registro_afectado=p_id::text)
  )::text,'UTF8')),'hex');
END;
$$;


--
-- Name: web_version_perfil(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_version_perfil(p_actor bigint) RETURNS text
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('usuario',u.id,'rol',u.rol_principal,
    'alumno',(SELECT to_jsonb(a) FROM banco.alumno a WHERE a.usuario_id=u.id),
    'profesor',(SELECT to_jsonb(p) FROM banco.profesor p WHERE p.usuario_id=u.id),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY habilidad_id)
      FROM banco.alumno_habilidad h WHERE h.alumno_id=u.id),'[]'::jsonb),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='perfil_academico' AND registro_afectado=u.id::text))::text,'UTF8')),'hex')
  FROM banco.usuario u WHERE u.id=p_actor;
$$;


--
-- Name: web_version_proyecto(bigint); Type: FUNCTION; Schema: banco; Owner: -
--

CREATE FUNCTION banco.web_version_proyecto(p_proyecto bigint) RETURNS text
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'banco', 'pg_temp'
    AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object('proyecto',to_jsonb(p),
    'habilidades',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY habilidad_id)
      FROM banco.proyecto_habilidad h WHERE h.proyecto_id=p.id),'[]'::jsonb),
    'ultima_revision',(SELECT coalesce(max(id),0) FROM banco.revision_proyecto WHERE proyecto_id=p.id),
    'ultimo_evento',(SELECT coalesce(max(id),0) FROM banco.evento_auditoria
      WHERE entidad_afectada='proyecto' AND registro_afectado=p.id::text))::text,'UTF8')),'hex')
  FROM banco.proyecto p WHERE p.id=p_proyecto;
$$;


--
-- Name: FUNCTION web_version_proyecto(p_proyecto bigint); Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON FUNCTION banco.web_version_proyecto(p_proyecto bigint) IS 'Token CAS opaco de contenido/estado/habilidades/envíos/eventos. Sin columnas nuevas; no es credencial ni autorización. Una versión distinta requiere recargar, no repetir una decisión obsoleta.';


--
-- Name: acompanamiento_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.acompanamiento ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.acompanamiento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: alumno; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.alumno (
    usuario_id bigint NOT NULL,
    matricula text NOT NULL,
    carrera text,
    semestre smallint,
    datos_academicos text,
    contacto_correo text,
    contacto_telefono text,
    CONSTRAINT alumno_matricula_check CHECK ((btrim(matricula) <> ''::text)),
    CONSTRAINT alumno_semestre_check CHECK ((semestre > 0))
);


--
-- Name: alumno_habilidad; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.alumno_habilidad (
    alumno_id bigint NOT NULL,
    habilidad_id bigint NOT NULL,
    nivel_dominio text,
    descripcion text,
    evidencia text
);


--
-- Name: COLUMN alumno_habilidad.evidencia; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.alumno_habilidad.evidencia IS 'D-11: texto descriptivo o enlace escrito, sin adjuntos ni descarga automática. Visibilidad según D-10; tratar como texto sin ejecutar en la futura interfaz.';


--
-- Name: asignacion_alumno; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.asignacion_alumno (
    id bigint NOT NULL,
    candidatura_id bigint NOT NULL,
    decision_id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    proyecto_id bigint NOT NULL,
    resultado_decision text GENERATED ALWAYS AS ('aprobada'::text) STORED NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fin timestamp with time zone,
    estado text DEFAULT 'vigente'::text NOT NULL,
    evento_retiro_id bigint,
    evento_cierre_id bigint,
    CONSTRAINT asignacion_alumno_estado_check CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text]))),
    CONSTRAINT ck_asignacion_alumno_fechas CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))
);


--
-- Name: COLUMN asignacion_alumno.resultado_decision; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_alumno.resultado_decision IS 'Constante generada que exige decisión aprobatoria del mismo objeto mediante FK compuesta.';


--
-- Name: COLUMN asignacion_alumno.evento_retiro_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_alumno.evento_retiro_id IS 'D-07: retiro administrativo exacto; fecha real en auditoría. Si ocurre antes o al inicio, estado revocada y fin NULL expresan periodo no iniciado, sin inventar final.';


--
-- Name: COLUMN asignacion_alumno.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_alumno.evento_cierre_id IS 'Cierre coordinado del proyecto; finalizada o revocada libera reservas. Fin NULL con evento exacto expresa periodo no iniciado, no ejecución académica.';


--
-- Name: asignacion_alumno_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.asignacion_alumno ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.asignacion_alumno_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asignacion_direccion; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.asignacion_direccion (
    id bigint NOT NULL,
    solicitud_direccion_id bigint NOT NULL,
    decision_id bigint NOT NULL,
    profesor_id bigint NOT NULL,
    proyecto_id bigint NOT NULL,
    resultado_decision text GENERATED ALWAYS AS ('aprobada'::text) STORED NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fin timestamp with time zone,
    estado text DEFAULT 'vigente'::text NOT NULL,
    evento_retiro_id bigint,
    evento_cierre_id bigint,
    CONSTRAINT asignacion_direccion_estado_check CHECK ((estado = ANY (ARRAY['vigente'::text, 'finalizada'::text, 'revocada'::text]))),
    CONSTRAINT ck_asignacion_direccion_fechas CHECK (((num_nonnulls(evento_retiro_id, evento_cierre_id) <= 1) AND (((estado = 'vigente'::text) AND (fin IS NULL) AND (evento_retiro_id IS NULL) AND (evento_cierre_id IS NULL)) OR ((estado = 'finalizada'::text) AND (evento_retiro_id IS NULL) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (evento_cierre_id IS NOT NULL)))) OR ((estado = 'revocada'::text) AND (((fin IS NOT NULL) AND (fin > inicio)) OR ((fin IS NULL) AND (num_nonnulls(evento_retiro_id, evento_cierre_id) = 1)))))))
);


--
-- Name: COLUMN asignacion_direccion.resultado_decision; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_direccion.resultado_decision IS 'Constante generada que exige decisión aprobatoria del mismo objeto mediante FK compuesta.';


--
-- Name: COLUMN asignacion_direccion.evento_retiro_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_direccion.evento_retiro_id IS 'D-07: retiro del director solo por administrador con motivo. Conserva otras asignaciones y carga; puede pausar el proyecto.';


--
-- Name: COLUMN asignacion_direccion.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.asignacion_direccion.evento_cierre_id IS 'Cierre coordinado del proyecto, separado del retiro individual. Conserva fuente y decisión aprobadas y la fecha real del evento.';


--
-- Name: asignacion_direccion_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.asignacion_direccion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.asignacion_direccion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: candidatura; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.candidatura (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    proyecto_id bigint NOT NULL,
    fecha_solicitud timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado text DEFAULT 'pendiente_evaluacion'::text NOT NULL,
    observaciones text,
    evento_cierre_id bigint,
    evaluacion_vigente_id bigint,
    evento_preseleccion_id bigint,
    CONSTRAINT candidatura_estado_check CHECK ((estado = ANY (ARRAY['pendiente_evaluacion'::text, 'evaluada'::text, 'preseleccionada'::text, 'aprobada'::text, 'rechazada'::text, 'cancelada'::text]))),
    CONSTRAINT ck_candidatura_cierre CHECK (((evento_cierre_id IS NULL) OR (estado = 'cancelada'::text)))
);


--
-- Name: COLUMN candidatura.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.candidatura.evento_cierre_id IS 'Cancelación automática de candidatura activa al cerrar el proyecto; conserva evaluación e historial y libera el máximo de tres.';


--
-- Name: candidatura_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.candidatura ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.candidatura_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: criterio_evaluacion; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.criterio_evaluacion (
    id bigint NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    escala text,
    ponderacion numeric,
    codigo text,
    CONSTRAINT ck_ponderacion_finita CHECK (((ponderacion IS NULL) OR (ponderacion <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric])))),
    CONSTRAINT criterio_evaluacion_nombre_check CHECK ((btrim(nombre) <> ''::text))
);


--
-- Name: criterio_evaluacion_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.criterio_evaluacion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.criterio_evaluacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: decision_administrativa; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.decision_administrativa (
    id bigint NOT NULL,
    administrador_usuario_id bigint NOT NULL,
    revision_proyecto_id bigint,
    candidatura_id bigint,
    solicitud_direccion_id bigint,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resultado text NOT NULL,
    justificacion text NOT NULL,
    CONSTRAINT ck_correccion_solo_revision CHECK (((resultado <> 'en_correccion'::text) OR (revision_proyecto_id IS NOT NULL))),
    CONSTRAINT ck_decision_justificacion_texto CHECK ((justificacion ~ '[^[:space:]]'::text)),
    CONSTRAINT ck_decision_objeto_unico CHECK ((num_nonnulls(revision_proyecto_id, candidatura_id, solicitud_direccion_id) = 1)),
    CONSTRAINT decision_administrativa_justificacion_check CHECK ((btrim(justificacion) <> ''::text)),
    CONSTRAINT decision_administrativa_resultado_check CHECK ((resultado = ANY (ARRAY['aprobada'::text, 'rechazada'::text, 'en_correccion'::text])))
);


--
-- Name: CONSTRAINT ck_decision_justificacion_texto ON decision_administrativa; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON CONSTRAINT ck_decision_justificacion_texto ON banco.decision_administrativa IS 'RF-40: exige al menos un carácter de contenido en el motivo administrativo. Conserva texto y saltos de línea significativos; no inventa ni corrige motivos históricos.';


--
-- Name: decision_administrativa_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.decision_administrativa ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.decision_administrativa_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: detalle_evaluacion; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.detalle_evaluacion (
    evaluacion_id bigint NOT NULL,
    criterio_id bigint NOT NULL,
    puntuacion numeric NOT NULL,
    comentario text,
    definicion_aplicada jsonb NOT NULL,
    CONSTRAINT detalle_evaluacion_definicion_aplicada_check CHECK ((jsonb_typeof(definicion_aplicada) = 'object'::text)),
    CONSTRAINT detalle_evaluacion_puntuacion_check CHECK ((puntuacion <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric])))
);


--
-- Name: empresa; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.empresa (
    id bigint NOT NULL,
    razon_social text NOT NULL,
    sector text,
    identificacion text,
    contacto_nombre text,
    contacto_correo text,
    contacto_telefono text,
    CONSTRAINT empresa_razon_social_check CHECK ((btrim(razon_social) <> ''::text))
);


--
-- Name: empresa_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.empresa ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.empresa_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: evaluacion_candidato; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.evaluacion_candidato (
    id bigint NOT NULL,
    candidatura_id bigint NOT NULL,
    evaluador_usuario_id bigint NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    comentarios text,
    recomendacion text,
    version_rubrica smallint,
    CONSTRAINT ck_evaluacion_rubrica_version CHECK (((version_rubrica IS NULL) OR (version_rubrica = 1)))
);


--
-- Name: evaluacion_candidato_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.evaluacion_candidato ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.evaluacion_candidato_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: evento_auditoria_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.evento_auditoria ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.evento_auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: habilidad; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.habilidad (
    id bigint NOT NULL,
    nombre text NOT NULL,
    tipo text NOT NULL,
    descripcion text,
    CONSTRAINT habilidad_nombre_check CHECK ((btrim(nombre) <> ''::text)),
    CONSTRAINT habilidad_tipo_check CHECK ((tipo = ANY (ARRAY['dura'::text, 'blanda'::text])))
);


--
-- Name: habilidad_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.habilidad ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.habilidad_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notificacion; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.notificacion (
    id bigint NOT NULL,
    destinatario_usuario_id bigint NOT NULL,
    evento_id bigint NOT NULL,
    mensaje text NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_lectura timestamp with time zone,
    CONSTRAINT ck_notificacion_lectura CHECK (((fecha_lectura IS NULL) OR (fecha_lectura >= fecha))),
    CONSTRAINT notificacion_mensaje_check CHECK ((btrim(mensaje) <> ''::text))
);


--
-- Name: TABLE notificacion; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON TABLE banco.notificacion IS 'D-10/D-11: avisos internos por evento y destinatario activo; sin envío externo ni copia de motivos/evidencias. Lectura propia y conservación; no autentica IDs recibidos.';


--
-- Name: notificacion_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.notificacion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.notificacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profesor; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.profesor (
    usuario_id bigint NOT NULL,
    numero_empleado text NOT NULL,
    especialidad text,
    experiencia text,
    contacto_correo text,
    contacto_telefono text,
    CONSTRAINT profesor_numero_empleado_check CHECK ((btrim(numero_empleado) <> ''::text))
);


--
-- Name: proyecto_habilidad; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.proyecto_habilidad (
    proyecto_id bigint NOT NULL,
    habilidad_id bigint NOT NULL,
    nivel_minimo text,
    obligatoria boolean DEFAULT false NOT NULL
);


--
-- Name: proyecto_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.proyecto ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.proyecto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: representacion_empresa; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.representacion_empresa (
    usuario_id bigint NOT NULL,
    empresa_id bigint NOT NULL,
    vigente boolean DEFAULT true NOT NULL,
    fecha_vinculacion timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_fin timestamp with time zone,
    CONSTRAINT ck_representacion_fechas CHECK (((vigente AND (fecha_fin IS NULL)) OR ((NOT vigente) AND (fecha_fin IS NOT NULL) AND (fecha_fin >= fecha_vinculacion))))
);


--
-- Name: revision_proyecto_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.revision_proyecto ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.revision_proyecto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: solicitud_direccion; Type: TABLE; Schema: banco; Owner: -
--

CREATE TABLE banco.solicitud_direccion (
    id bigint NOT NULL,
    profesor_id bigint NOT NULL,
    proyecto_id bigint NOT NULL,
    fecha_solicitud timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    experiencia_aplicable text,
    justificacion text,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    evento_cierre_id bigint,
    CONSTRAINT ck_solicitud_direccion_cierre CHECK (((evento_cierre_id IS NULL) OR (estado = 'cancelada'::text))),
    CONSTRAINT solicitud_direccion_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text, 'cancelada'::text])))
);


--
-- Name: COLUMN solicitud_direccion.evento_cierre_id; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON COLUMN banco.solicitud_direccion.evento_cierre_id IS 'Cancelación de solicitud aún pendiente por cierre del proyecto; no reescribe una fuente ya aprobada.';


--
-- Name: solicitud_direccion_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.solicitud_direccion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.solicitud_direccion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuario_id_seq; Type: SEQUENCE; Schema: banco; Owner: -
--

ALTER TABLE banco.usuario ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME banco.usuario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_usuario_directorio; Type: VIEW; Schema: banco; Owner: -
--

CREATE VIEW banco.v_usuario_directorio AS
 SELECT id,
    nombre,
    rol_principal,
    estado_cuenta,
    fecha_alta
   FROM banco.usuario;


--
-- Name: VIEW v_usuario_directorio; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON VIEW banco.v_usuario_directorio IS 'Consulta técnica mínima; no contiene hash, correo, evidencias ni perfiles. La autorización por actor se implementará después.';


--
-- Name: acompanamiento acompanamiento_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.acompanamiento
    ADD CONSTRAINT acompanamiento_pkey PRIMARY KEY (id);


--
-- Name: alumno_habilidad alumno_habilidad_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno_habilidad
    ADD CONSTRAINT alumno_habilidad_pkey PRIMARY KEY (alumno_id, habilidad_id);


--
-- Name: alumno alumno_matricula_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno
    ADD CONSTRAINT alumno_matricula_key UNIQUE (matricula);


--
-- Name: alumno alumno_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno
    ADD CONSTRAINT alumno_pkey PRIMARY KEY (usuario_id);


--
-- Name: asignacion_alumno asignacion_alumno_candidatura_id_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_candidatura_id_key UNIQUE (candidatura_id);


--
-- Name: asignacion_alumno asignacion_alumno_decision_id_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_decision_id_key UNIQUE (decision_id);


--
-- Name: asignacion_alumno asignacion_alumno_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_pkey PRIMARY KEY (id);


--
-- Name: asignacion_direccion asignacion_direccion_decision_id_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_decision_id_key UNIQUE (decision_id);


--
-- Name: asignacion_direccion asignacion_direccion_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_pkey PRIMARY KEY (id);


--
-- Name: asignacion_direccion asignacion_direccion_solicitud_direccion_id_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_solicitud_direccion_id_key UNIQUE (solicitud_direccion_id);


--
-- Name: candidatura candidatura_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT candidatura_pkey PRIMARY KEY (id);


--
-- Name: criterio_evaluacion criterio_evaluacion_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.criterio_evaluacion
    ADD CONSTRAINT criterio_evaluacion_pkey PRIMARY KEY (id);


--
-- Name: decision_administrativa decision_administrativa_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT decision_administrativa_pkey PRIMARY KEY (id);


--
-- Name: detalle_evaluacion detalle_evaluacion_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.detalle_evaluacion
    ADD CONSTRAINT detalle_evaluacion_pkey PRIMARY KEY (evaluacion_id, criterio_id);


--
-- Name: empresa empresa_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.empresa
    ADD CONSTRAINT empresa_pkey PRIMARY KEY (id);


--
-- Name: evaluacion_candidato evaluacion_candidato_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evaluacion_candidato
    ADD CONSTRAINT evaluacion_candidato_pkey PRIMARY KEY (id);


--
-- Name: evento_auditoria evento_auditoria_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evento_auditoria
    ADD CONSTRAINT evento_auditoria_pkey PRIMARY KEY (id);


--
-- Name: habilidad habilidad_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.habilidad
    ADD CONSTRAINT habilidad_pkey PRIMARY KEY (id);


--
-- Name: notificacion notificacion_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.notificacion
    ADD CONSTRAINT notificacion_pkey PRIMARY KEY (id);


--
-- Name: profesor profesor_numero_empleado_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.profesor
    ADD CONSTRAINT profesor_numero_empleado_key UNIQUE (numero_empleado);


--
-- Name: profesor profesor_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.profesor
    ADD CONSTRAINT profesor_pkey PRIMARY KEY (usuario_id);


--
-- Name: proyecto_habilidad proyecto_habilidad_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto_habilidad
    ADD CONSTRAINT proyecto_habilidad_pkey PRIMARY KEY (proyecto_id, habilidad_id);


--
-- Name: proyecto proyecto_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_pkey PRIMARY KEY (id);


--
-- Name: representacion_empresa representacion_empresa_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.representacion_empresa
    ADD CONSTRAINT representacion_empresa_pkey PRIMARY KEY (usuario_id);


--
-- Name: revision_proyecto revision_proyecto_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT revision_proyecto_pkey PRIMARY KEY (id);


--
-- Name: solicitud_direccion solicitud_direccion_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.solicitud_direccion
    ADD CONSTRAINT solicitud_direccion_pkey PRIMARY KEY (id);


--
-- Name: candidatura uq_candidatura_origen; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT uq_candidatura_origen UNIQUE (id, alumno_id, proyecto_id);


--
-- Name: decision_administrativa uq_decision_candidatura; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT uq_decision_candidatura UNIQUE (id, candidatura_id, resultado);


--
-- Name: decision_administrativa uq_decision_direccion; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT uq_decision_direccion UNIQUE (id, solicitud_direccion_id, resultado);


--
-- Name: evaluacion_candidato uq_evaluacion_origen; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evaluacion_candidato
    ADD CONSTRAINT uq_evaluacion_origen UNIQUE (id, candidatura_id);


--
-- Name: notificacion uq_notificacion_evento_destinatario; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.notificacion
    ADD CONSTRAINT uq_notificacion_evento_destinatario UNIQUE (evento_id, destinatario_usuario_id);


--
-- Name: proyecto uq_proyecto_evento_cierre; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT uq_proyecto_evento_cierre UNIQUE (evento_cierre_id);


--
-- Name: proyecto uq_proyecto_evento_estado; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT uq_proyecto_evento_estado UNIQUE (evento_estado_id);


--
-- Name: proyecto uq_proyecto_evento_inicio; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT uq_proyecto_evento_inicio UNIQUE (evento_inicio_id);


--
-- Name: revision_proyecto uq_revision_numero; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT uq_revision_numero UNIQUE (proyecto_id, numero);


--
-- Name: revision_proyecto uq_revision_proyecto_pertenencia; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT uq_revision_proyecto_pertenencia UNIQUE (id, proyecto_id);


--
-- Name: solicitud_direccion uq_solicitud_direccion_origen; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.solicitud_direccion
    ADD CONSTRAINT uq_solicitud_direccion_origen UNIQUE (id, profesor_id, proyecto_id);


--
-- Name: usuario usuario_correo_normalizado_key; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.usuario
    ADD CONSTRAINT usuario_correo_normalizado_key UNIQUE (correo_normalizado);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id);


--
-- Name: ix_acompanamiento_direccion; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_acompanamiento_direccion ON banco.acompanamiento USING btree (asignacion_direccion_id);


--
-- Name: ix_acompanamiento_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_acompanamiento_evento_cierre ON banco.acompanamiento USING btree (evento_cierre_id);


--
-- Name: ix_acompanamiento_evento_retiro; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_acompanamiento_evento_retiro ON banco.acompanamiento USING btree (evento_retiro_id);


--
-- Name: ix_alumno_habilidad_catalogo; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_alumno_habilidad_catalogo ON banco.alumno_habilidad USING btree (habilidad_id);


--
-- Name: ix_asignacion_alumno_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_asignacion_alumno_evento_cierre ON banco.asignacion_alumno USING btree (evento_cierre_id);


--
-- Name: ix_asignacion_alumno_proyecto; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_asignacion_alumno_proyecto ON banco.asignacion_alumno USING btree (proyecto_id);


--
-- Name: ix_asignacion_direccion_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_asignacion_direccion_evento_cierre ON banco.asignacion_direccion USING btree (evento_cierre_id);


--
-- Name: ix_asignacion_direccion_proyecto; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_asignacion_direccion_proyecto ON banco.asignacion_direccion USING btree (proyecto_id);


--
-- Name: ix_auditoria_actor; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_auditoria_actor ON banco.evento_auditoria USING btree (actor_usuario_id);


--
-- Name: ix_auditoria_fecha; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_auditoria_fecha ON banco.evento_auditoria USING btree (fecha);


--
-- Name: ix_candidatura_alumno; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_candidatura_alumno ON banco.candidatura USING btree (alumno_id);


--
-- Name: ix_candidatura_evaluacion; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_candidatura_evaluacion ON banco.candidatura USING btree (evaluacion_vigente_id);


--
-- Name: ix_candidatura_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_candidatura_evento_cierre ON banco.candidatura USING btree (evento_cierre_id);


--
-- Name: ix_candidatura_proyecto; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_candidatura_proyecto ON banco.candidatura USING btree (proyecto_id);


--
-- Name: ix_decision_administrador; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_decision_administrador ON banco.decision_administrativa USING btree (administrador_usuario_id);


--
-- Name: ix_decision_candidatura; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_decision_candidatura ON banco.decision_administrativa USING btree (candidatura_id);


--
-- Name: ix_decision_direccion; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_decision_direccion ON banco.decision_administrativa USING btree (solicitud_direccion_id);


--
-- Name: ix_decision_revision; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_decision_revision ON banco.decision_administrativa USING btree (revision_proyecto_id);


--
-- Name: ix_detalle_criterio; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_detalle_criterio ON banco.detalle_evaluacion USING btree (criterio_id);


--
-- Name: ix_evaluacion_candidatura; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_evaluacion_candidatura ON banco.evaluacion_candidato USING btree (candidatura_id);


--
-- Name: ix_evaluacion_evaluador; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_evaluacion_evaluador ON banco.evaluacion_candidato USING btree (evaluador_usuario_id);


--
-- Name: ix_notificacion_destinatario; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_notificacion_destinatario ON banco.notificacion USING btree (destinatario_usuario_id, fecha);


--
-- Name: ix_proyecto_autor; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_proyecto_autor ON banco.proyecto USING btree (autor_usuario_id);


--
-- Name: ix_proyecto_empresa; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_proyecto_empresa ON banco.proyecto USING btree (empresa_id);


--
-- Name: ix_proyecto_estado; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_proyecto_estado ON banco.proyecto USING btree (estado);


--
-- Name: ix_proyecto_habilidad_catalogo; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_proyecto_habilidad_catalogo ON banco.proyecto_habilidad USING btree (habilidad_id);


--
-- Name: ix_proyecto_revision_publicada; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_proyecto_revision_publicada ON banco.proyecto USING btree (revision_publicada_id);


--
-- Name: ix_representacion_empresa; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_representacion_empresa ON banco.representacion_empresa USING btree (empresa_id);


--
-- Name: ix_revision_autor; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_revision_autor ON banco.revision_proyecto USING btree (autor_usuario_id);


--
-- Name: ix_revision_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_revision_evento_cierre ON banco.revision_proyecto USING btree (evento_cierre_id);


--
-- Name: ix_solicitud_direccion_evento_cierre; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_solicitud_direccion_evento_cierre ON banco.solicitud_direccion USING btree (evento_cierre_id);


--
-- Name: ix_solicitud_direccion_profesor; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_solicitud_direccion_profesor ON banco.solicitud_direccion USING btree (profesor_id);


--
-- Name: ix_solicitud_direccion_proyecto; Type: INDEX; Schema: banco; Owner: -
--

CREATE INDEX ix_solicitud_direccion_proyecto ON banco.solicitud_direccion USING btree (proyecto_id);


--
-- Name: uq_acompanamiento_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_acompanamiento_vigente ON banco.acompanamiento USING btree (asignacion_alumno_id, asignacion_direccion_id) WHERE (estado = 'vigente'::text);


--
-- Name: uq_asignacion_alumno_carga_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_alumno_carga_vigente ON banco.asignacion_alumno USING btree (alumno_id) WHERE (estado = 'vigente'::text);


--
-- Name: INDEX uq_asignacion_alumno_carga_vigente; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON INDEX banco.uq_asignacion_alumno_carga_vigente IS 'D-04/D-06: una asignación vigente por alumno entre todos los proyectos, reservada desde la aprobación; finalizada/revocada conservan historial sin consumir.';


--
-- Name: uq_asignacion_alumno_evento_retiro; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_alumno_evento_retiro ON banco.asignacion_alumno USING btree (evento_retiro_id);


--
-- Name: uq_asignacion_alumno_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_alumno_vigente ON banco.asignacion_alumno USING btree (alumno_id, proyecto_id) WHERE (estado = 'vigente'::text);


--
-- Name: uq_asignacion_direccion_evento_retiro; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_direccion_evento_retiro ON banco.asignacion_direccion USING btree (evento_retiro_id);


--
-- Name: uq_asignacion_direccion_proyecto_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_direccion_proyecto_vigente ON banco.asignacion_direccion USING btree (proyecto_id) WHERE (estado = 'vigente'::text);


--
-- Name: INDEX uq_asignacion_direccion_proyecto_vigente; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON INDEX banco.uq_asignacion_direccion_proyecto_vigente IS 'D-03: máximo un director vigente por proyecto entre todos los profesores; conserva múltiples direcciones históricas finalizadas o revocadas. No autoriza sustituciones ni cierres de D-07.';


--
-- Name: uq_asignacion_direccion_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_asignacion_direccion_vigente ON banco.asignacion_direccion USING btree (profesor_id, proyecto_id) WHERE (estado = 'vigente'::text);


--
-- Name: uq_candidatura_activa; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_candidatura_activa ON banco.candidatura USING btree (alumno_id, proyecto_id) WHERE (estado = ANY (ARRAY['pendiente_evaluacion'::text, 'evaluada'::text, 'preseleccionada'::text]));


--
-- Name: INDEX uq_candidatura_activa; Type: COMMENT; Schema: banco; Owner: -
--

COMMENT ON INDEX banco.uq_candidatura_activa IS 'D-01/D-06: una candidatura activa por alumno/proyecto; pendiente_evaluacion, evaluada y preseleccionada consumen el máximo de tres.';


--
-- Name: uq_candidatura_preseleccion; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_candidatura_preseleccion ON banco.candidatura USING btree (evento_preseleccion_id) WHERE (evento_preseleccion_id IS NOT NULL);


--
-- Name: uq_criterio_codigo; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_criterio_codigo ON banco.criterio_evaluacion USING btree (codigo) WHERE (codigo IS NOT NULL);


--
-- Name: uq_decision_candidatura_aprobada; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_decision_candidatura_aprobada ON banco.decision_administrativa USING btree (candidatura_id) WHERE ((candidatura_id IS NOT NULL) AND (resultado = 'aprobada'::text));


--
-- Name: uq_decision_direccion_aprobada; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_decision_direccion_aprobada ON banco.decision_administrativa USING btree (solicitud_direccion_id) WHERE ((solicitud_direccion_id IS NOT NULL) AND (resultado = 'aprobada'::text));


--
-- Name: uq_decision_publicacion_revision; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_decision_publicacion_revision ON banco.decision_administrativa USING btree (revision_proyecto_id) WHERE (revision_proyecto_id IS NOT NULL);


--
-- Name: uq_representante_vigente; Type: INDEX; Schema: banco; Owner: -
--

CREATE UNIQUE INDEX uq_representante_vigente ON banco.representacion_empresa USING btree (empresa_id) WHERE vigente;


--
-- Name: acompanamiento ct_acompanamiento_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_acompanamiento_cierre AFTER INSERT OR UPDATE ON banco.acompanamiento DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: asignacion_alumno ct_asignacion_alumno_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_aprobacion AFTER INSERT OR UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();


--
-- Name: asignacion_alumno ct_asignacion_alumno_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_cierre AFTER INSERT OR UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: asignacion_alumno ct_asignacion_alumno_minimos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_minimos AFTER INSERT OR UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();


--
-- Name: asignacion_alumno ct_asignacion_alumno_vigencias; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_alumno_vigencias AFTER UPDATE ON banco.asignacion_alumno DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_vigencias_padre();


--
-- Name: asignacion_direccion ct_asignacion_direccion_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_aprobacion AFTER INSERT OR UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();


--
-- Name: asignacion_direccion ct_asignacion_direccion_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_cierre AFTER INSERT OR UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: asignacion_direccion ct_asignacion_direccion_minimos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_minimos AFTER INSERT OR UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();


--
-- Name: asignacion_direccion ct_asignacion_direccion_vigencias; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_asignacion_direccion_vigencias AFTER UPDATE ON banco.asignacion_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_vigencias_padre();


--
-- Name: candidatura ct_candidatura_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_candidatura_aprobacion AFTER INSERT OR UPDATE ON banco.candidatura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();


--
-- Name: candidatura ct_candidatura_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_candidatura_cierre AFTER INSERT OR UPDATE ON banco.candidatura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: decision_administrativa ct_decision_participacion_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_decision_participacion_aprobacion AFTER INSERT ON banco.decision_administrativa DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();


--
-- Name: detalle_evaluacion ct_detalle_d08; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_detalle_d08 AFTER INSERT ON banco.detalle_evaluacion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluacion_d08_diferida();


--
-- Name: empresa ct_empresa_representante; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_empresa_representante AFTER INSERT OR UPDATE ON banco.empresa DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();


--
-- Name: evaluacion_candidato ct_evaluacion_d08; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_evaluacion_d08 AFTER INSERT ON banco.evaluacion_candidato DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluacion_d08_diferida();


--
-- Name: proyecto ct_proyecto_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_proyecto_cierre AFTER INSERT OR UPDATE ON banco.proyecto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: proyecto ct_proyecto_minimos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_proyecto_minimos AFTER INSERT OR UPDATE ON banco.proyecto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_minimos_proyecto_diferido();


--
-- Name: representacion_empresa ct_representacion_exacta; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_representacion_exacta AFTER INSERT OR DELETE OR UPDATE ON banco.representacion_empresa DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();


--
-- Name: revision_proyecto ct_revision_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_revision_cierre AFTER INSERT OR UPDATE ON banco.revision_proyecto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: solicitud_direccion ct_solicitud_direccion_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_solicitud_direccion_aprobacion AFTER INSERT OR UPDATE ON banco.solicitud_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_aprobacion_participacion_diferida();


--
-- Name: solicitud_direccion ct_solicitud_direccion_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_solicitud_direccion_cierre AFTER INSERT OR UPDATE ON banco.solicitud_direccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.validar_cierre_proyecto_diferido();


--
-- Name: usuario ct_usuario_representacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE CONSTRAINT TRIGGER ct_usuario_representacion AFTER DELETE OR UPDATE ON banco.usuario DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION banco.comprobar_representacion_diferida();


--
-- Name: candidatura tr_0001_candidatura_rechazada; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_0001_candidatura_rechazada BEFORE UPDATE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();


--
-- Name: solicitud_direccion tr_0001_direccion_rechazada; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_0001_direccion_rechazada BEFORE UPDATE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();


--
-- Name: proyecto tr_0001_proyecto_rechazado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_0001_proyecto_rechazado BEFORE UPDATE ON banco.proyecto FOR EACH ROW EXECUTE FUNCTION banco.proteger_rechazo_definitivo();


--
-- Name: candidatura tr_000_candidatura_cancelada; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_000_candidatura_cancelada BEFORE UPDATE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.proteger_candidatura_cancelada();


--
-- Name: solicitud_direccion tr_000_solicitud_cancelada; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_000_solicitud_cancelada BEFORE UPDATE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.proteger_solicitud_cancelada();


--
-- Name: usuario tr_000_usuario_version_acceso; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_000_usuario_version_acceso BEFORE UPDATE ON banco.usuario FOR EACH ROW EXECUTE FUNCTION banco.actualizar_version_acceso();


--
-- Name: asignacion_alumno tr_00_asignacion_alumno_cupos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_00_asignacion_alumno_cupos BEFORE INSERT OR UPDATE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.validar_reserva_asignacion();


--
-- Name: asignacion_direccion tr_00_asignacion_direccion_cupos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_00_asignacion_direccion_cupos BEFORE INSERT OR UPDATE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.validar_reserva_asignacion();


--
-- Name: candidatura tr_00_candidatura_cupos; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_00_candidatura_cupos BEFORE INSERT OR UPDATE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.validar_cupo_candidatura();


--
-- Name: solicitud_direccion tr_00_solicitud_direccion_aprobacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_00_solicitud_direccion_aprobacion BEFORE INSERT OR UPDATE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.proteger_aprobacion_direccion();


--
-- Name: asignacion_alumno tr_01_asignacion_alumno_inicio; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_01_asignacion_alumno_inicio BEFORE INSERT OR UPDATE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.proteger_asignaciones_iniciadas();


--
-- Name: asignacion_direccion tr_01_asignacion_direccion_inicio; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_01_asignacion_direccion_inicio BEFORE INSERT OR UPDATE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.proteger_asignaciones_iniciadas();


--
-- Name: asignacion_alumno tr_02_asignacion_alumno_retiro; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_02_asignacion_alumno_retiro BEFORE INSERT OR UPDATE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.validar_retiro_asignacion();


--
-- Name: asignacion_direccion tr_02_asignacion_direccion_retiro; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_02_asignacion_direccion_retiro BEFORE INSERT OR UPDATE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.validar_retiro_asignacion();


--
-- Name: acompanamiento tr_03_acompanamiento_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_acompanamiento_cierre BEFORE INSERT OR UPDATE ON banco.acompanamiento FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: asignacion_alumno tr_03_asignacion_alumno_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_asignacion_alumno_cierre BEFORE INSERT OR UPDATE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: asignacion_direccion tr_03_asignacion_direccion_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_asignacion_direccion_cierre BEFORE INSERT OR UPDATE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: candidatura tr_03_candidatura_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_candidatura_cierre BEFORE INSERT OR UPDATE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: revision_proyecto tr_03_revision_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_revision_cierre BEFORE INSERT OR UPDATE ON banco.revision_proyecto FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: solicitud_direccion tr_03_solicitud_direccion_cierre; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_03_solicitud_direccion_cierre BEFORE INSERT OR UPDATE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.validar_elemento_cierre();


--
-- Name: acompanamiento tr_acompanamiento_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_acompanamiento_no_borrado BEFORE DELETE ON banco.acompanamiento FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: acompanamiento tr_acompanamiento_validar; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_acompanamiento_validar BEFORE INSERT OR UPDATE ON banco.acompanamiento FOR EACH ROW EXECUTE FUNCTION banco.validar_acompanamiento();


--
-- Name: alumno tr_alumno_rol; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_alumno_rol BEFORE INSERT OR UPDATE ON banco.alumno FOR EACH ROW EXECUTE FUNCTION banco.validar_perfil_rol('alumno');


--
-- Name: asignacion_alumno tr_asignacion_alumno_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_alumno_no_borrado BEFORE DELETE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: asignacion_alumno tr_asignacion_alumno_origen; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_alumno_origen BEFORE UPDATE ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();


--
-- Name: asignacion_alumno tr_asignacion_alumno_publicacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_alumno_publicacion BEFORE INSERT ON banco.asignacion_alumno FOR EACH ROW EXECUTE FUNCTION banco.validar_proyecto_al_asignar();


--
-- Name: asignacion_direccion tr_asignacion_direccion_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_direccion_no_borrado BEFORE DELETE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: asignacion_direccion tr_asignacion_direccion_origen; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_direccion_origen BEFORE UPDATE ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();


--
-- Name: asignacion_direccion tr_asignacion_direccion_publicacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_asignacion_direccion_publicacion BEFORE INSERT ON banco.asignacion_direccion FOR EACH ROW EXECUTE FUNCTION banco.validar_proyecto_al_asignar();


--
-- Name: evento_auditoria tr_auditoria_inmutable; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_auditoria_inmutable BEFORE DELETE OR UPDATE ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: candidatura tr_candidatura_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_candidatura_no_borrado BEFORE DELETE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: candidatura tr_candidatura_origen; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_candidatura_origen BEFORE UPDATE ON banco.candidatura FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();


--
-- Name: criterio_evaluacion tr_criterio_d08; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_criterio_d08 BEFORE INSERT OR DELETE OR UPDATE ON banco.criterio_evaluacion FOR EACH ROW EXECUTE FUNCTION banco.proteger_criterio_d08();


--
-- Name: decision_administrativa tr_decision_administrador; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_decision_administrador BEFORE INSERT ON banco.decision_administrativa FOR EACH ROW EXECUTE FUNCTION banco.validar_administrador_decision();


--
-- Name: decision_administrativa tr_decision_inmutable; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_decision_inmutable BEFORE DELETE OR UPDATE ON banco.decision_administrativa FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: detalle_evaluacion tr_detalle_inmutable; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_detalle_inmutable BEFORE DELETE OR UPDATE ON banco.detalle_evaluacion FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: evaluacion_candidato tr_evaluacion_evaluador; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_evaluacion_evaluador BEFORE INSERT ON banco.evaluacion_candidato FOR EACH ROW EXECUTE FUNCTION banco.validar_evaluador();


--
-- Name: evaluacion_candidato tr_evaluacion_inmutable; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_evaluacion_inmutable BEFORE DELETE OR UPDATE ON banco.evaluacion_candidato FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: evento_auditoria tr_evento_operacion_actual; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_evento_operacion_actual BEFORE INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.marcar_evento_operacion_actual();


--
-- Name: notificacion tr_notificacion_historial; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_notificacion_historial BEFORE DELETE OR UPDATE ON banco.notificacion FOR EACH ROW EXECUTE FUNCTION banco.proteger_notificacion();


--
-- Name: evento_auditoria tr_notificar_evento; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_notificar_evento AFTER INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION banco.notificar_evento();


--
-- Name: profesor tr_profesor_rol; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_profesor_rol BEFORE INSERT OR UPDATE ON banco.profesor FOR EACH ROW EXECUTE FUNCTION banco.validar_perfil_rol('profesor');


--
-- Name: proyecto tr_proyecto_autoria; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_proyecto_autoria BEFORE INSERT OR UPDATE ON banco.proyecto FOR EACH ROW EXECUTE FUNCTION banco.validar_autoria_proyecto();


--
-- Name: proyecto_habilidad tr_proyecto_habilidad_publicacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_proyecto_habilidad_publicacion BEFORE INSERT OR DELETE OR UPDATE ON banco.proyecto_habilidad FOR EACH ROW EXECUTE FUNCTION banco.proteger_requisitos_proyecto();


--
-- Name: proyecto tr_proyecto_publicacion; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_proyecto_publicacion BEFORE INSERT OR UPDATE ON banco.proyecto FOR EACH ROW EXECUTE FUNCTION banco.proteger_publicacion_proyecto();


--
-- Name: representacion_empresa tr_representacion_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_representacion_no_borrado BEFORE DELETE ON banco.representacion_empresa FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: representacion_empresa tr_representacion_validar; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_representacion_validar BEFORE INSERT OR UPDATE ON banco.representacion_empresa FOR EACH ROW EXECUTE FUNCTION banco.validar_representacion();


--
-- Name: revision_proyecto tr_revision_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_revision_no_borrado BEFORE DELETE ON banco.revision_proyecto FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: revision_proyecto tr_revision_publicada; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_revision_publicada BEFORE UPDATE ON banco.revision_proyecto FOR EACH ROW EXECUTE FUNCTION banco.proteger_revision_publicada();


--
-- Name: revision_proyecto tr_revision_validar; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_revision_validar BEFORE INSERT OR UPDATE ON banco.revision_proyecto FOR EACH ROW EXECUTE FUNCTION banco.validar_revision();


--
-- Name: solicitud_direccion tr_solicitud_direccion_origen; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_solicitud_direccion_origen BEFORE UPDATE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_origen();


--
-- Name: solicitud_direccion tr_solicitud_no_borrado; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_solicitud_no_borrado BEFORE DELETE ON banco.solicitud_direccion FOR EACH ROW EXECUTE FUNCTION banco.impedir_reescritura_historial();


--
-- Name: usuario tr_usuario_dependencias; Type: TRIGGER; Schema: banco; Owner: -
--

CREATE TRIGGER tr_usuario_dependencias BEFORE UPDATE ON banco.usuario FOR EACH ROW EXECUTE FUNCTION banco.validar_usuario_dependencias();


--
-- Name: acompanamiento acompanamiento_asignacion_alumno_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.acompanamiento
    ADD CONSTRAINT acompanamiento_asignacion_alumno_id_fkey FOREIGN KEY (asignacion_alumno_id) REFERENCES banco.asignacion_alumno(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: acompanamiento acompanamiento_asignacion_direccion_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.acompanamiento
    ADD CONSTRAINT acompanamiento_asignacion_direccion_id_fkey FOREIGN KEY (asignacion_direccion_id) REFERENCES banco.asignacion_direccion(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: acompanamiento acompanamiento_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.acompanamiento
    ADD CONSTRAINT acompanamiento_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: acompanamiento acompanamiento_evento_retiro_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.acompanamiento
    ADD CONSTRAINT acompanamiento_evento_retiro_id_fkey FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alumno_habilidad alumno_habilidad_alumno_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno_habilidad
    ADD CONSTRAINT alumno_habilidad_alumno_id_fkey FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alumno_habilidad alumno_habilidad_habilidad_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno_habilidad
    ADD CONSTRAINT alumno_habilidad_habilidad_id_fkey FOREIGN KEY (habilidad_id) REFERENCES banco.habilidad(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: alumno alumno_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.alumno
    ADD CONSTRAINT alumno_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno asignacion_alumno_alumno_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_alumno_id_fkey FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno asignacion_alumno_decision_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES banco.decision_administrativa(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno asignacion_alumno_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno asignacion_alumno_evento_retiro_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_evento_retiro_id_fkey FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno asignacion_alumno_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT asignacion_alumno_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion asignacion_direccion_decision_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES banco.decision_administrativa(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion asignacion_direccion_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion asignacion_direccion_evento_retiro_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_evento_retiro_id_fkey FOREIGN KEY (evento_retiro_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion asignacion_direccion_profesor_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_profesor_id_fkey FOREIGN KEY (profesor_id) REFERENCES banco.profesor(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion asignacion_direccion_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT asignacion_direccion_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: candidatura candidatura_alumno_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT candidatura_alumno_id_fkey FOREIGN KEY (alumno_id) REFERENCES banco.alumno(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: candidatura candidatura_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT candidatura_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: candidatura candidatura_evento_preseleccion_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT candidatura_evento_preseleccion_id_fkey FOREIGN KEY (evento_preseleccion_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: candidatura candidatura_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT candidatura_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: decision_administrativa decision_administrativa_administrador_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT decision_administrativa_administrador_usuario_id_fkey FOREIGN KEY (administrador_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: decision_administrativa decision_administrativa_candidatura_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT decision_administrativa_candidatura_id_fkey FOREIGN KEY (candidatura_id) REFERENCES banco.candidatura(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: decision_administrativa decision_administrativa_revision_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT decision_administrativa_revision_proyecto_id_fkey FOREIGN KEY (revision_proyecto_id) REFERENCES banco.revision_proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: decision_administrativa decision_administrativa_solicitud_direccion_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.decision_administrativa
    ADD CONSTRAINT decision_administrativa_solicitud_direccion_id_fkey FOREIGN KEY (solicitud_direccion_id) REFERENCES banco.solicitud_direccion(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: detalle_evaluacion detalle_evaluacion_criterio_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.detalle_evaluacion
    ADD CONSTRAINT detalle_evaluacion_criterio_id_fkey FOREIGN KEY (criterio_id) REFERENCES banco.criterio_evaluacion(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: detalle_evaluacion detalle_evaluacion_evaluacion_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.detalle_evaluacion
    ADD CONSTRAINT detalle_evaluacion_evaluacion_id_fkey FOREIGN KEY (evaluacion_id) REFERENCES banco.evaluacion_candidato(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: evaluacion_candidato evaluacion_candidato_candidatura_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evaluacion_candidato
    ADD CONSTRAINT evaluacion_candidato_candidatura_id_fkey FOREIGN KEY (candidatura_id) REFERENCES banco.candidatura(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: evaluacion_candidato evaluacion_candidato_evaluador_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evaluacion_candidato
    ADD CONSTRAINT evaluacion_candidato_evaluador_usuario_id_fkey FOREIGN KEY (evaluador_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: evento_auditoria evento_auditoria_actor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.evento_auditoria
    ADD CONSTRAINT evento_auditoria_actor_usuario_id_fkey FOREIGN KEY (actor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno fk_asignacion_alumno_aprobacion; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT fk_asignacion_alumno_aprobacion FOREIGN KEY (decision_id, candidatura_id, resultado_decision) REFERENCES banco.decision_administrativa(id, candidatura_id, resultado) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_alumno fk_asignacion_alumno_origen; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_alumno
    ADD CONSTRAINT fk_asignacion_alumno_origen FOREIGN KEY (candidatura_id, alumno_id, proyecto_id) REFERENCES banco.candidatura(id, alumno_id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion fk_asignacion_direccion_aprobacion; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT fk_asignacion_direccion_aprobacion FOREIGN KEY (decision_id, solicitud_direccion_id, resultado_decision) REFERENCES banco.decision_administrativa(id, solicitud_direccion_id, resultado) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: asignacion_direccion fk_asignacion_direccion_origen; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.asignacion_direccion
    ADD CONSTRAINT fk_asignacion_direccion_origen FOREIGN KEY (solicitud_direccion_id, profesor_id, proyecto_id) REFERENCES banco.solicitud_direccion(id, profesor_id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: candidatura fk_candidatura_evaluacion_exacta; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.candidatura
    ADD CONSTRAINT fk_candidatura_evaluacion_exacta FOREIGN KEY (evaluacion_vigente_id, id) REFERENCES banco.evaluacion_candidato(id, candidatura_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto fk_proyecto_revision_publicada; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT fk_proyecto_revision_publicada FOREIGN KEY (revision_publicada_id, id) REFERENCES banco.revision_proyecto(id, proyecto_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: notificacion notificacion_destinatario_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.notificacion
    ADD CONSTRAINT notificacion_destinatario_usuario_id_fkey FOREIGN KEY (destinatario_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: notificacion notificacion_evento_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.notificacion
    ADD CONSTRAINT notificacion_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: profesor profesor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.profesor
    ADD CONSTRAINT profesor_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto proyecto_autor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_autor_usuario_id_fkey FOREIGN KEY (autor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto proyecto_empresa_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES banco.empresa(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto proyecto_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto proyecto_evento_estado_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_evento_estado_id_fkey FOREIGN KEY (evento_estado_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto proyecto_evento_inicio_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto
    ADD CONSTRAINT proyecto_evento_inicio_id_fkey FOREIGN KEY (evento_inicio_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto_habilidad proyecto_habilidad_habilidad_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto_habilidad
    ADD CONSTRAINT proyecto_habilidad_habilidad_id_fkey FOREIGN KEY (habilidad_id) REFERENCES banco.habilidad(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: proyecto_habilidad proyecto_habilidad_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.proyecto_habilidad
    ADD CONSTRAINT proyecto_habilidad_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: representacion_empresa representacion_empresa_empresa_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.representacion_empresa
    ADD CONSTRAINT representacion_empresa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES banco.empresa(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: representacion_empresa representacion_empresa_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.representacion_empresa
    ADD CONSTRAINT representacion_empresa_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: revision_proyecto revision_proyecto_autor_usuario_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT revision_proyecto_autor_usuario_id_fkey FOREIGN KEY (autor_usuario_id) REFERENCES banco.usuario(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: revision_proyecto revision_proyecto_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT revision_proyecto_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: revision_proyecto revision_proyecto_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.revision_proyecto
    ADD CONSTRAINT revision_proyecto_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: solicitud_direccion solicitud_direccion_evento_cierre_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.solicitud_direccion
    ADD CONSTRAINT solicitud_direccion_evento_cierre_id_fkey FOREIGN KEY (evento_cierre_id) REFERENCES banco.evento_auditoria(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: solicitud_direccion solicitud_direccion_profesor_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.solicitud_direccion
    ADD CONSTRAINT solicitud_direccion_profesor_id_fkey FOREIGN KEY (profesor_id) REFERENCES banco.profesor(usuario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: solicitud_direccion solicitud_direccion_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: banco; Owner: -
--

ALTER TABLE ONLY banco.solicitud_direccion
    ADD CONSTRAINT solicitud_direccion_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES banco.proyecto(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict heTkHyRDWHAhzEQZkTL4hWkGKXUkeI5OVt7aVprLZ2vccjyB1VOpzv2fcvuU2Si


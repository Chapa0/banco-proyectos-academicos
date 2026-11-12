-- WEB-02: gateways reales con banco_web, CAS, invalidación y auditoría atómica.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.acceso_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean:=false;
BEGIN
  BEGIN
    SET LOCAL ROLE banco_web;
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>codigo THEN
      RAISE EXCEPTION 'Esperado %, obtenido %: %; SQL: %',codigo,SQLSTATE,SQLERRM,sentencia;
    END IF;
    observado:=true;
  END;
  RESET ROLE;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-200001,'Admin acceso','acceso-admin@example.invalid','!SIN-ACCESO','administrador','activa'),
 (-200002,'Admin inactivo','acceso-inactivo@example.invalid','!SIN-ACCESO','administrador','inactiva'),
 (-200003,'Alumno acceso','acceso-alumno@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-200004,'Profesor acceso','acceso-prof@example.invalid','!SIN-ACCESO','profesor','activa');
CREATE TEMP TABLE acceso_prueba(etiqueta text PRIMARY KEY,usuario_id bigint,empresa_id bigint,version bigint);
GRANT SELECT,INSERT,UPDATE ON acceso_prueba TO banco_web;

-- Los gateways de acceso entregan solo el registro solicitado. La aplicación
-- conserva la obligación de verificar hash, cuenta activa y sesión.
SET LOCAL ROLE banco_web;
DO $$ BEGIN
  IF (SELECT id FROM banco.web_buscar_acceso_correo(' ACCESO-ALUMNO@EXAMPLE.INVALID '))<>-200003
    OR (SELECT count(*) FROM banco.web_buscar_acceso_id(-200004))<>1
    OR (SELECT count(*) FROM banco.web_buscar_acceso_correo('ausente@example.invalid'))<>0 THEN
    RAISE EXCEPTION 'La consulta de autenticación alteró identidad o devolvió registros ajenos'; END IF;
END $$;
RESET ROLE;

SELECT pg_temp.acceso_error('42501',$s$SELECT hash_contrasena FROM banco.usuario LIMIT 0$s$);
SELECT pg_temp.acceso_error('42501',$s$UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE false$s$);
SELECT pg_temp.acceso_error('42501',$s$SELECT banco.crear_cuenta(-200001,'No','no@example.invalid','!HASH','alumno')$s$);
SELECT pg_temp.acceso_error('42501',$s$SELECT banco.web_datos_cuenta(-200001)$s$);
SELECT pg_temp.acceso_error('42501',$s$SELECT banco.web_bloquear_cuenta(-200001,1)$s$);
SELECT pg_temp.acceso_error('42501',$s$SELECT banco.web_validar_hash('!HASH')$s$);
SELECT pg_temp.acceso_error('42501',$s$SELECT banco.web_auditar_cambio(-200001,-200003,'falso','falso')$s$);
SELECT pg_temp.acceso_error('42501',$s$INSERT INTO banco.evento_auditoria DEFAULT VALUES$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_listar_cuentas(-200003,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_obtener_cuenta(-200002,-200003)$s$);
SELECT pg_temp.acceso_error('23503',$s$SELECT banco.web_obtener_cuenta(-200001,-209999)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_listar_cuentas(-200001,NULL,'otro',NULL,20,0)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_listar_cuentas(-200001,NULL,NULL,NULL,101,0)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_listar_cuentas(-200001,NULL,NULL,NULL,20,-1)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_crear_cuenta(-200001,'No','no@example.invalid','texto-plano','alumno',NULL)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_crear_cuenta(-200003,'No','no@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','alumno',NULL)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_crear_cuenta(-200001,'No','no@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','otro',NULL)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_crear_cuenta(-200001,'No','no@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','empresa',NULL)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_crear_cuenta(-200001,'No','no@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','alumno','Empresa improcedente')$s$);

SET LOCAL ROLE banco_web;
INSERT INTO acceso_prueba(etiqueta,usuario_id) VALUES('alumno',banco.web_crear_cuenta(-200001,'Alumno creado',' ACCESO-NUEVO@EXAMPLE.INVALID ',
 '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','alumno',NULL));
INSERT INTO acceso_prueba(etiqueta,usuario_id) VALUES('empresa',banco.web_crear_cuenta(-200001,'Representante creado','acceso-empresa@example.invalid',
 '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','empresa','Empresa WEB-02 ficticia'));
UPDATE acceso_prueba t SET empresa_id=(banco.web_obtener_cuenta(-200001,t.usuario_id)->>'empresa_id')::bigint,
 version=(banco.web_obtener_cuenta(-200001,t.usuario_id)->>'version_acceso')::bigint;
DO $$ DECLARE datos jsonb; BEGIN
  datos:=banco.web_listar_cuentas(-200001,'acceso',NULL,NULL,100,0);
  IF datos::text LIKE '%hash_contrasena%' OR datos::text LIKE '%92IXUNpkj%'
    OR (datos->>'total')::integer<6
    OR (SELECT count(*) FROM banco.web_buscar_acceso_correo('acceso-nuevo@example.invalid') WHERE requiere_cambio_clave)<>1
    OR (banco.web_obtener_cuenta(-200001,(SELECT usuario_id FROM acceso_prueba WHERE etiqueta='empresa'))->>'razon_social')<>'Empresa WEB-02 ficticia' THEN
    RAISE EXCEPTION 'Datos privados expuestos, cuenta omitida o alta empresarial/clave inicial incompleta'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.acceso_error('23505',$s$SELECT banco.web_crear_cuenta(-200001,'Duplicado','acceso-nuevo@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','alumno',NULL)$s$);
SELECT pg_temp.acceso_error('40001',$s$SELECT banco.web_editar_cuenta(-200001,-200003,'No','no@example.invalid','Motivo',0)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_editar_cuenta(-200003,-200004,'No','no@example.invalid','Motivo',1)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_editar_cuenta(-200001,-200003,'Nombre','correo@example.invalid',E'\t\n',1)$s$);

SET LOCAL ROLE banco_web;
SELECT banco.web_editar_cuenta(-200001,-200003,'Alumno actualizado',' acceso-cambiado@example.invalid ','Corrección de correo',1);
DO $$ BEGIN
  IF (SELECT version_acceso FROM banco.web_buscar_acceso_id(-200003))<>2 THEN
    RAISE EXCEPTION 'El cambio de correo no invalidó sesiones anteriores'; END IF;
END $$;
SELECT banco.web_registrar_acceso(-200003,2,'inicio_sesion');
SELECT banco.web_registrar_acceso(-200003,2,'cierre_sesion');
SELECT banco.web_estado_cuenta(-200001,-200003,'inactiva','Baja temporal',2);
DO $$ BEGIN
  IF (SELECT version_acceso FROM banco.web_buscar_acceso_id(-200003))<>3 THEN
    RAISE EXCEPTION 'La desactivación no invalidó sesiones'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.acceso_error('40001',$s$SELECT banco.web_estado_cuenta(-200001,-200003,'activa','Solicitud vieja',2)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_cambiar_clave(-200003,'$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',3)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_registrar_acceso(-200003,3,'inicio_sesion')$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_registrar_acceso(-200004,1,'operacion_falsa')$s$);
SELECT pg_temp.acceso_error('40001',$s$SELECT banco.web_registrar_acceso(-200004,0,'inicio_sesion')$s$);
SELECT pg_temp.acceso_error('23503',$s$SELECT banco.web_registrar_acceso(-209999,1,'inicio_sesion')$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_estado_cuenta(-200001,-200003,'activa','Reactivación',3);
SELECT banco.web_restablecer_clave(-200001,-200003,'$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','Entrega de clave temporal',4);
DO $$ BEGIN
 IF (SELECT version_acceso FROM banco.web_buscar_acceso_id(-200003))<>5
  OR NOT (SELECT requiere_cambio_clave FROM banco.web_buscar_acceso_id(-200003)) THEN
  RAISE EXCEPTION 'El restablecimiento no incrementó versión o dejó de exigir cambio'; END IF;
END $$;
SELECT banco.web_cambiar_clave(-200003,'$2y$12$72IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',5);
DO $$ BEGIN
 IF (SELECT version_acceso FROM banco.web_buscar_acceso_id(-200003))<>6
  OR (SELECT requiere_cambio_clave FROM banco.web_buscar_acceso_id(-200003)) THEN
  RAISE EXCEPTION 'El cambio propio no conservó versión y requisito'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.acceso_error('40001',$s$SELECT banco.web_cambiar_clave(-200003,'$2y$12$72IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',5)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_restablecer_clave(-200001,-200003,'texto-plano','Motivo',6)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_restablecer_clave(-200004,-200003,'$2y$12$72IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','Motivo',6)$s$);
SELECT pg_temp.acceso_error('23514',$s$SELECT banco.web_restablecer_clave(-200001,-200003,'$2y$12$72IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',E'\t',6)$s$);

-- Relevo exacto: un formulario de la representación anterior no retira otra.
SET LOCAL ROLE banco_web;
INSERT INTO acceso_prueba(etiqueta,usuario_id) SELECT 'relevo',banco.web_relevar_representante(
 -200001,empresa_id,'Relevo nuevo','acceso-relevo@example.invalid',
 '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','Cambio de representante',usuario_id)
 FROM acceso_prueba WHERE etiqueta='empresa';
RESET ROLE;
SELECT pg_temp.acceso_error('40001',$s$SELECT banco.web_relevar_representante(-200001,empresa_id,'Relevo viejo','acceso-obsoleto@example.invalid','$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','Formulario anterior',usuario_id) FROM acceso_prueba WHERE etiqueta='empresa'$s$);
DO $$ BEGIN
 IF (SELECT estado_cuenta FROM banco.usuario WHERE id=(SELECT usuario_id FROM acceso_prueba WHERE etiqueta='empresa'))<>'inactiva'
  OR (SELECT version_acceso FROM banco.usuario WHERE id=(SELECT usuario_id FROM acceso_prueba WHERE etiqueta='empresa'))<=
     (SELECT version FROM acceso_prueba WHERE etiqueta='empresa')
  OR (SELECT count(*) FROM banco.representacion_empresa WHERE empresa_id=(SELECT empresa_id FROM acceso_prueba WHERE etiqueta='empresa') AND vigente)<>1 THEN
  RAISE EXCEPTION 'El relevo no invalidó el acceso anterior o perdió representante único'; END IF;
 IF EXISTS(SELECT 1 FROM banco.evento_auditoria WHERE actor_usuario_id IN(-200001,-200003,-200004)
   AND (resultado LIKE '%92IXUNpkj%' OR resultado LIKE '%example.invalid%')) THEN
  RAISE EXCEPTION 'La auditoría copió un hash o correo privado'; END IF;
END $$;

-- Fallo de auditoría o aviso revierte datos y versión: no se permite un cambio
-- de acceso sin su evidencia, aunque el UPDATE haya ocurrido antes del fallo.
CREATE FUNCTION pg_temp.fallar_acceso() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.operacion IN('editar_cuenta','inicio_sesion') THEN
  RAISE EXCEPTION 'Fallo auditado inyectado' USING ERRCODE='P0001'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_acceso BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_acceso();
SELECT pg_temp.acceso_error('P0001',$s$SELECT banco.web_editar_cuenta(-200001,-200004,'No debe persistir','acceso-fallo@example.invalid','Prueba rollback',1)$s$);
SELECT pg_temp.acceso_error('P0001',$s$SELECT banco.web_registrar_acceso(-200004,1,'inicio_sesion')$s$);
DROP TRIGGER tr_prueba_acceso ON banco.evento_auditoria;
DO $$ BEGIN
 IF (SELECT version_acceso FROM banco.usuario WHERE id=-200004)<>1
  OR (SELECT correo_normalizado FROM banco.usuario WHERE id=-200004)<>'acceso-prof@example.invalid' THEN
  RAISE EXCEPTION 'Un cambio fallido dejó versión o datos parciales'; END IF;
END $$;
CREATE FUNCTION pg_temp.fallar_aviso_acceso() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Fallo de aviso inyectado' USING ERRCODE='P0001'; END $$;
CREATE TRIGGER tr_prueba_aviso_acceso BEFORE INSERT ON banco.notificacion
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_aviso_acceso();
SELECT pg_temp.acceso_error('P0001',$s$SELECT banco.web_restablecer_clave(-200001,-200004,'$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','Prueba aviso',1)$s$);
DROP TRIGGER tr_prueba_aviso_acceso ON banco.notificacion;
DO $$ BEGIN
 IF (SELECT version_acceso FROM banco.usuario WHERE id=-200004)<>1
  OR (SELECT hash_contrasena FROM banco.usuario WHERE id=-200004)<>'!SIN-ACCESO' THEN
  RAISE EXCEPTION 'Un restablecimiento fallido dejó hash o versión parciales'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'WEB-02: acceso, cuentas, versión de sesión, CAS y rollback correctos';

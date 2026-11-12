-- WEB-01: privilegios reales del grupo mínimo, sin datos de usuarios en salida.
-- Ejecutar exclusivamente en una base temporal propia del ejecutor.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.web_error(codigo text,sentencia text)
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
END;
$$;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='banco_web' AND
    (rolsuper OR rolcreatedb OR rolcreaterole OR rolcanlogin OR rolreplication
      OR rolbypassrls OR NOT rolinherit))
    OR EXISTS(SELECT 1 FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.member
      WHERE r.rolname='banco_web') THEN
    RAISE EXCEPTION 'El grupo web tiene atributos elevados o hereda otro rol';
  END IF;
  IF (SELECT array_agg(column_name::text ORDER BY ordinal_position)
      FROM information_schema.columns WHERE table_schema='banco'
        AND table_name='v_usuario_directorio') IS DISTINCT FROM
      ARRAY['id','nombre','rol_principal','estado_cuenta','fecha_alta']::text[] THEN
    RAISE EXCEPTION 'El directorio dejó de ser la proyección mínima prevista';
  END IF;
END $$;
SET LOCAL ROLE banco_web;
DO $$ BEGIN
  IF current_user<>'banco_web' THEN RAISE EXCEPTION 'La consulta no usa el grupo web'; END IF;
END $$;
SELECT id,nombre,rol_principal,estado_cuenta,fecha_alta
  FROM banco.v_usuario_directorio WHERE false;
RESET ROLE;
SELECT pg_temp.web_error('42501',$s$SELECT hash_contrasena FROM banco.usuario LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$SELECT nombre FROM banco.usuario LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$SELECT * FROM banco.proyecto LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$SELECT * FROM banco.evento_auditoria LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$SELECT * FROM banco.alumno LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$SELECT * FROM control.migracion LIMIT 0$s$);
SELECT pg_temp.web_error('42501',$s$INSERT INTO banco.usuario DEFAULT VALUES$s$);
SELECT pg_temp.web_error('42501',$s$UPDATE banco.proyecto SET titulo='No permitido' WHERE false$s$);
SELECT pg_temp.web_error('42501',$s$DELETE FROM banco.candidatura WHERE false$s$);
SELECT pg_temp.web_error('42501',$s$TRUNCATE banco.proyecto$s$);
SELECT pg_temp.web_error('42501',$s$INSERT INTO banco.v_usuario_directorio(nombre) VALUES('No permitido')$s$);
SELECT pg_temp.web_error('42501',$s$SELECT nextval('banco.usuario_id_seq')$s$);
SELECT pg_temp.web_error('42501',$s$SELECT banco.crear_cuenta(0,'No permitido','web@example.invalid','!FICTICIO','alumno')$s$);
SELECT pg_temp.web_error('42501',$s$SELECT banco.consultar_perfil(0,0)$s$);
SELECT pg_temp.web_error('42501',$s$CREATE TABLE banco.web_no_permitida(id integer)$s$);
SELECT pg_temp.web_error('42501',$s$CREATE SCHEMA web_no_permitido$s$);
SELECT pg_temp.web_error('42501',$s$ALTER TABLE banco.proyecto ADD COLUMN web_no_permitida integer$s$);
SELECT pg_temp.web_error('42501',$s$DROP VIEW banco.v_usuario_directorio$s$);
SELECT pg_temp.web_error('42501',$s$GRANT SELECT ON banco.usuario TO banco_web$s$);
DO $$ BEGIN
  IF current_user='banco_web' THEN RAISE EXCEPTION 'La prueba no restableció el propietario'; END IF;
END $$;
ROLLBACK;
SELECT 'WEB-01: directorio mínimo y 19 rechazos de acceso SQL correctos';

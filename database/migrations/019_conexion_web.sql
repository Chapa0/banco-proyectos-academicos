-- WEB-01: grupo técnico mínimo para comprobar conexión y mapeo de la web.
-- La cuenta LOGIN y su secreto se provisionan fuera del SQL versionado.
-- No habilita autenticación, lectura de perfiles ni procesos de negocio.
DO $$
DECLARE v_rol oid;
BEGIN
  SELECT oid INTO v_rol FROM pg_roles WHERE rolname='banco_web';
  IF NOT FOUND THEN
    CREATE ROLE banco_web NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
      NOREPLICATION NOBYPASSRLS INHERIT;
    SELECT oid INTO v_rol FROM pg_roles WHERE rolname='banco_web';
  END IF;
  -- No reutilizar ni rebajar silenciosamente un rol ajeno con más permisos.
  IF EXISTS(SELECT 1 FROM pg_roles WHERE oid=v_rol AND
      (rolsuper OR rolcreatedb OR rolcreaterole OR rolcanlogin OR rolreplication
        OR rolbypassrls OR NOT rolinherit))
    OR EXISTS(SELECT 1 FROM pg_auth_members WHERE member=v_rol) THEN
    RAISE EXCEPTION 'banco_web existente tiene atributos o membresías incompatibles; no se modifica automáticamente'
      USING ERRCODE='23514';
  END IF;
  IF has_database_privilege(v_rol,current_database(),'CREATE')
    OR has_schema_privilege(v_rol,'banco','CREATE')
    OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE CASE WHEN n.nspname='banco' AND c.relkind IN ('r','p','v','m','f') THEN
        (has_table_privilege(v_rol,c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
          OR (c.relname<>'v_usuario_directorio' AND
            has_any_column_privilege(v_rol,c.oid,'SELECT,INSERT,UPDATE,REFERENCES')))
        ELSE false END)
    OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE CASE WHEN n.nspname='banco' AND c.relkind='S'
        THEN has_sequence_privilege(v_rol,c.oid,'SELECT,USAGE,UPDATE') ELSE false END)
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='banco' AND has_function_privilege(v_rol,p.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'banco_web existente tiene acceso incompatible con WEB-01; conciliarlo explícitamente'
      USING ERRCODE='23514';
  END IF;
END;
$$;
GRANT USAGE ON SCHEMA banco TO banco_web;
GRANT SELECT ON banco.v_usuario_directorio TO banco_web;
COMMENT ON ROLE banco_web IS
  'WEB-01: grupo NOLOGIN para conexión de aplicación, USAGE banco y SELECT del directorio mínimo. Sin DML, DDL de negocio, secuencias, funciones o lectura de hashes; no autentica actores web.';

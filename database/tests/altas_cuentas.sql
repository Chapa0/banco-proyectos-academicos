-- RF-02/RF-03/RF-06 y D-09. Solo datos ficticios sin credenciales de acceso.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.alta_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean := false;
BEGIN
  BEGIN
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> codigo THEN
      RAISE EXCEPTION 'Esperado %, obtenido %: %; SQL: %',codigo,SQLSTATE,SQLERRM,sentencia;
    END IF;
    observado := true;
  END;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-100001,'Admin altas','alta-admin@example.invalid','!ALTA-FICTICIO','administrador','activa'),
 (-100002,'Admin inactivo altas','alta-admin-inactivo@example.invalid','!ALTA-FICTICIO','administrador','inactiva'),
 (-100003,'Alumno sin facultad administrativa','alta-actor-alumno@example.invalid','!ALTA-FICTICIO','alumno','activa');

SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100003,'Cuenta','alta-fallo1@example.invalid','!ALTA-FICTICIO','alumno')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100002,'Cuenta','alta-fallo2@example.invalid','!ALTA-FICTICIO','profesor')$s$);
SELECT pg_temp.alta_error('23503',$s$SELECT banco.crear_cuenta(-100099,'Cuenta','alta-fallo3@example.invalid','!ALTA-FICTICIO','alumno')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_empresa_con_representante(-100003,'Cuenta','alta-fallo4@example.invalid','!ALTA-FICTICIO','Empresa')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_empresa_con_representante(-100002,'Cuenta','alta-fallo5@example.invalid','!ALTA-FICTICIO','Empresa')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,'Cuenta','alta-fallo6@example.invalid','!ALTA-FICTICIO','empresa')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,'Cuenta','alta-fallo7@example.invalid','!ALTA-FICTICIO','visitante')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,'Cuenta','alta-fallo8@example.invalid','!ALTA-FICTICIO',NULL)$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,E'\t\n','alta-fallo9@example.invalid','!ALTA-FICTICIO','alumno')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,'Cuenta',' ','!ALTA-FICTICIO','alumno')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_cuenta(-100001,'Cuenta','alta-fallo10@example.invalid',NULL,'alumno')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_empresa_con_representante(-100001,'Cuenta','alta-fallo11@example.invalid',E'\t\r\n','Empresa')$s$);
SELECT pg_temp.alta_error('23514',$s$SELECT banco.crear_empresa_con_representante(-100001,'Cuenta','alta-fallo12@example.invalid','!ALTA-FICTICIO',E'\t\n')$s$);

CREATE TEMP TABLE altas_prueba(etiqueta text PRIMARY KEY,usuario_id bigint,empresa_id bigint) ON COMMIT DROP;
INSERT INTO altas_prueba SELECT 'alumno',banco.crear_cuenta(-100001,'Alumno nuevo',' NUEVO.ALUMNO@Example.invalid ','!ALTA-FICTICIO','alumno'),NULL;
INSERT INTO altas_prueba SELECT 'profesor',banco.crear_cuenta(-100001,'Profesor nuevo','nuevo.profesor@example.invalid','!ALTA-FICTICIO','profesor'),NULL;
INSERT INTO altas_prueba SELECT 'administrador',banco.crear_cuenta(-100001,'Admin nuevo','nuevo.admin@example.invalid','!ALTA-FICTICIO','administrador'),NULL;
INSERT INTO altas_prueba SELECT 'empresa',usuario_id,empresa_id FROM banco.crear_empresa_con_representante(-100001,'Representante nuevo',' NUEVA.EMPRESA@Example.invalid ','!ALTA-FICTICIO','Empresa de prueba');
INSERT INTO altas_prueba SELECT 'empresa2',usuario_id,empresa_id FROM banco.crear_empresa_con_representante(-100001,'Otro representante','otra.empresa@example.invalid','!ALTA-FICTICIO','Otra empresa de prueba');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN
  IF (SELECT count(*) FROM altas_prueba t JOIN banco.usuario u ON u.id=t.usuario_id
      WHERE u.estado_cuenta='activa' AND u.hash_contrasena='!ALTA-FICTICIO')<>5
    OR (SELECT correo_normalizado FROM banco.usuario u JOIN altas_prueba t ON t.usuario_id=u.id WHERE t.etiqueta='alumno')<>'nuevo.alumno@example.invalid'
    OR (SELECT correo_normalizado FROM banco.usuario u JOIN altas_prueba t ON t.usuario_id=u.id WHERE t.etiqueta='empresa')<>'nueva.empresa@example.invalid' THEN
    RAISE EXCEPTION 'El alta alteró la cuenta, el hash opaco o la normalización de correo';
  END IF;
  IF EXISTS (SELECT 1 FROM altas_prueba t JOIN banco.alumno a ON a.usuario_id=t.usuario_id)
    OR EXISTS (SELECT 1 FROM altas_prueba t JOIN banco.profesor p ON p.usuario_id=t.usuario_id) THEN
    RAISE EXCEPTION 'Crear la cuenta exigió o inventó un perfil académico completo';
  END IF;
  IF (SELECT count(*) FROM altas_prueba t JOIN banco.usuario u ON u.id=t.usuario_id
      WHERE (t.etiqueta IN ('alumno','profesor','administrador') AND u.rol_principal=t.etiqueta)
         OR (t.etiqueta IN ('empresa','empresa2') AND u.rol_principal='empresa'))<>5 THEN
    RAISE EXCEPTION 'El alta no conservó el rol solicitado o la cuenta empresarial';
  END IF;
  IF (SELECT count(*) FROM altas_prueba t JOIN banco.representacion_empresa r
      ON r.usuario_id=t.usuario_id AND r.empresa_id=t.empresa_id AND r.vigente
      JOIN banco.empresa e ON e.id=t.empresa_id
      WHERE t.etiqueta IN ('empresa','empresa2') AND e.identificacion IS NULL
        AND e.sector IS NULL AND e.contacto_nombre IS NULL AND e.contacto_correo IS NULL
        AND e.contacto_telefono IS NULL)<>2 THEN
    RAISE EXCEPTION 'El alta no creó ambas representaciones exactas o inventó datos empresariales';
  END IF;
  IF (SELECT count(*) FROM banco.evento_auditoria e WHERE e.actor_usuario_id=-100001
      AND e.origen='usuario' AND e.fecha IS NOT NULL
      AND ((e.operacion='crear_cuenta' AND e.entidad_afectada='usuario'
        AND e.registro_afectado IN (SELECT usuario_id::text FROM altas_prueba WHERE empresa_id IS NULL))
       OR (e.operacion='crear_empresa_con_representante' AND e.entidad_afectada='empresa'
        AND e.registro_afectado IN (SELECT empresa_id::text FROM altas_prueba WHERE empresa_id IS NOT NULL))))<>5
    OR EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE actor_usuario_id=-100001
      AND (resultado LIKE '%ALTA-FICTICIO%' OR resultado LIKE '%example.invalid%')) THEN
    RAISE EXCEPTION 'Falta auditoría exacta con administrador/fecha o se copiaron credenciales/contactos al evento';
  END IF;
END $$;

-- El titular completará el perfil después; estos INSERT son fixtures técnicos,
-- no una sesión web ni un nuevo permiso de acceso a tablas.
INSERT INTO banco.alumno(usuario_id,matricula) SELECT usuario_id,'ALTA-A-01' FROM altas_prueba WHERE etiqueta='alumno';
INSERT INTO banco.profesor(usuario_id,numero_empleado) SELECT usuario_id,'ALTA-P-01' FROM altas_prueba WHERE etiqueta='profesor';
SELECT pg_temp.alta_error('23505',$s$SELECT banco.crear_cuenta(-100001,'Duplicado',' nuevo.ALUMNO@example.invalid ','!ALTA-FICTICIO','profesor')$s$);
SELECT pg_temp.alta_error('23505',$s$SELECT banco.crear_empresa_con_representante(-100001,'Duplicado empresarial',' NUEVA.EMPRESA@example.invalid ','!ALTA-FICTICIO','No debe quedar creada')$s$);
SELECT pg_temp.alta_error('23514',$s$UPDATE banco.representacion_empresa SET empresa_id=(SELECT empresa_id FROM altas_prueba WHERE etiqueta='empresa2') WHERE usuario_id=(SELECT usuario_id FROM altas_prueba WHERE etiqueta='empresa')$s$);
SELECT pg_temp.alta_error('23505',$s$
 INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
 VALUES(-100010,'Segundo representante incompatible','alta-rep-duplicado@example.invalid','!ALTA-FICTICIO','empresa');
 INSERT INTO banco.representacion_empresa(usuario_id,empresa_id)
 SELECT -100010,empresa_id FROM altas_prueba WHERE etiqueta='empresa'
$s$);

CREATE TEMP TABLE altas_conteos AS SELECT
 (SELECT count(*) FROM banco.usuario) AS usuarios,
 (SELECT count(*) FROM banco.empresa) AS empresas,
 (SELECT count(*) FROM banco.representacion_empresa) AS representantes,
 (SELECT count(*) FROM banco.evento_auditoria) AS eventos;
CREATE FUNCTION pg_temp.fallar_auditoria_alta() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.operacion IN ('crear_cuenta','crear_empresa_con_representante') THEN
    RAISE EXCEPTION 'Fallo controlado de auditoría de alta' USING ERRCODE='P9999';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_fallo_alta BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_auditoria_alta();
SELECT pg_temp.alta_error('P9999',$s$SELECT banco.crear_cuenta(-100001,'Cuenta revertida','alta-revertida@example.invalid','!ALTA-FICTICIO','alumno')$s$);
SELECT pg_temp.alta_error('P9999',$s$SELECT banco.crear_empresa_con_representante(-100001,'Empresa revertida','alta-empresa-revertida@example.invalid','!ALTA-FICTICIO','Empresa revertida')$s$);
DROP TRIGGER tr_prueba_fallo_alta ON banco.evento_auditoria;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM altas_conteos WHERE usuarios=(SELECT count(*) FROM banco.usuario)
    AND empresas=(SELECT count(*) FROM banco.empresa)
    AND representantes=(SELECT count(*) FROM banco.representacion_empresa)
    AND eventos=(SELECT count(*) FROM banco.evento_auditoria))
    OR EXISTS (SELECT 1 FROM banco.usuario WHERE id=-100010) THEN
    RAISE EXCEPTION 'Un alta fallida dejó cuenta, empresa, representación o auditoría parcial';
  END IF;
  IF has_function_privilege('banco_lectura','banco.crear_cuenta(bigint,text,text,text,text)','EXECUTE')
    OR has_function_privilege('banco_escritura','banco.crear_cuenta(bigint,text,text,text,text)','EXECUTE')
    OR has_function_privilege('banco_lectura','banco.crear_empresa_con_representante(bigint,text,text,text,text)','EXECUTE')
    OR has_function_privilege('banco_escritura','banco.crear_empresa_con_representante(bigint,text,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Se expuso el alta sin permisos de aplicación definidos';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'Altas administrativas de cuentas y empresa/representante, historial y rollback: correcto' AS resultado;
ROLLBACK;

-- WEB-04: publicación con banco_web, versiones y avisos atómicos.
-- Todos los cambios se revierten. Solo se ejecuta en temporales propias.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.publicacion_error(codigo text,sentencia text)
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
 (-210001,'Admin publicación','pub-admin@example.invalid','!SIN-ACCESO','administrador','activa'),
 (-210002,'Rep publicación','pub-rep@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-210003,'Rep ajeno','pub-ajeno@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-210004,'Alumno publicación','pub-alumno@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-210005,'Admin inactivo','pub-inactivo@example.invalid','!SIN-ACCESO','administrador','inactiva');
INSERT INTO banco.empresa(id,razon_social) VALUES(-210011,'Empresa publicación'),(-210012,'Empresa ajena');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-210002,-210011),(-210003,-210012);
INSERT INTO banco.habilidad(id,nombre,tipo) VALUES(-210021,'SQL publicación','dura'),(-210022,'Comunicación publicación','blanda');
CREATE TEMP TABLE publicacion_prueba(clave text PRIMARY KEY,id bigint,version text,revision bigint,datos jsonb);
GRANT SELECT,INSERT,UPDATE ON publicacion_prueba TO banco_web;
INSERT INTO publicacion_prueba(clave,datos) VALUES('contenido','{"titulo":"Proyecto WEB04","descripcion":"Descripción","problematica":"Problemática","objetivos":"Objetivos","justificacion":"Justificación","alcance":"Alcance","cupo_maximo_alumnos":2,"fecha_inicio_estimada":"2027-01-02","fecha_fin_estimada":"2027-05-02","habilidades":[{"habilidad_id":-210021,"nivel_minimo":"Básico","obligatoria":true},{"habilidad_id":-210022,"obligatoria":false}]}');

SELECT pg_temp.publicacion_error('42501',$s$SELECT * FROM banco.empresa$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT * FROM banco.proyecto$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT * FROM banco.revision_proyecto$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT * FROM banco.habilidad$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT * FROM banco.evento_auditoria$s$);
SELECT pg_temp.publicacion_error('42501',$s$INSERT INTO banco.proyecto DEFAULT VALUES$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.enviar_proyecto(1,-210002)$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_version_proyecto(1)$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_datos_empresa(-210011)$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_guardar_habilidades(1,'{}')$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_crear_proyecto(-210004,'{"titulo":"No"}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_listar_proyectos(-210005,NULL,NULL,20,0)$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_listar_proyectos(-210004,NULL,NULL,20,0)$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_listar_proyectos(-210001,NULL,'inventado',20,0)$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_listar_proyectos(-210001,NULL,NULL,0,0)$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_listar_proyectos(-210001,NULL,NULL,20,-1)$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'[]')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":["No"]}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"   "}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","empresa_id":-210012}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","estado":"publicado"}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","cupo_maximo_alumnos":1.2}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","cupo_maximo_alumnos":0}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","fecha_inicio_estimada":"2027-02-30"}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","fecha_inicio_estimada":"2027-02-03","fecha_fin_estimada":"2027-01-02"}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","habilidades":null}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","habilidades":[{"habilidad_id":-210021},{"habilidad_id":-210021}]}')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","habilidades":[{"habilidad_id":-210021,"extra":1}]}')$s$);
SELECT pg_temp.publicacion_error('23503',$s$SELECT banco.web_crear_proyecto(-210002,'{"titulo":"No","habilidades":[{"habilidad_id":-219999}]}')$s$);

SET LOCAL ROLE banco_web;
INSERT INTO publicacion_prueba(clave,id,version) VALUES('empresa',-210011,banco.web_obtener_empresa(-210002)->>'version');
SELECT banco.web_editar_empresa(-210002,'{"razon_social":"Empresa editada","sector":"Tecnología","contacto_correo":"contacto@example.invalid"}',(SELECT version FROM publicacion_prueba WHERE clave='empresa'));
DO $$ BEGIN
 IF banco.web_obtener_empresa(-210002)->>'sector'<>'Tecnología' THEN RAISE EXCEPTION 'RF07 sin persistencia'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.publicacion_error('40001',$s$SELECT banco.web_editar_empresa(-210002,'{"razon_social":"Obsoleta"}',(SELECT version FROM publicacion_prueba WHERE clave='empresa'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_editar_empresa(-210002,'{"razon_social":"No","id":-210012}',banco.web_obtener_empresa(-210002)->>'version')$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_editar_empresa(-210002,'{"razon_social":"   "}',banco.web_obtener_empresa(-210002)->>'version')$s$);

SET LOCAL ROLE banco_web;
INSERT INTO publicacion_prueba(clave,id) VALUES('proyecto',banco.web_crear_proyecto(-210002,'{"titulo":"Borrador incompleto"}'));
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
DO $$ DECLARE v jsonb; BEGIN
 v:=banco.web_obtener_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'));
 IF v->'proyecto'->>'estado'<>'borrador' OR jsonb_array_length(v->'revisiones')<>0
   OR (SELECT count(*) FROM jsonb_array_elements(banco.web_listar_proyectos(-210003,NULL,NULL,100,0)->'datos') x WHERE x->>'id'=v->'proyecto'->>'id')<>0 THEN
   RAISE EXCEPTION 'El borrador cambió de estado o se compartió con otra empresa'; END IF;
 IF banco.web_obtener_proyecto(-210001,(v->'proyecto'->>'id')::bigint)->'proyecto'->>'estado'<>'borrador' THEN
   RAISE EXCEPTION 'D10: administrador no pudo consultar el borrador'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.publicacion_error('23503',$s$SELECT banco.web_obtener_proyecto(-210003,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_obtener_proyecto(-210004,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_editar_proyecto(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),'{}',(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_enviar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_editar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT datos FROM publicacion_prueba WHERE clave='contenido'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'));
RESET ROLE;
SELECT pg_temp.publicacion_error('40001',$s$SELECT banco.web_editar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),'{"titulo":"Obsoleto"}',(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('40001',$s$SELECT banco.web_enviar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);

SET LOCAL ROLE banco_web;
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
UPDATE publicacion_prueba SET revision=banco.web_enviar_proyecto(-210002,id,version) WHERE clave='proyecto';
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM banco.notificacion n JOIN banco.evento_auditoria a ON a.id=n.evento_id
   WHERE a.operacion='enviar_proyecto' AND a.registro_afectado=(SELECT id::text FROM publicacion_prueba WHERE clave='proyecto')
   AND n.destinatario_usuario_id=-210001)<>1 THEN RAISE EXCEPTION 'El administrador no recibió el aviso único de envío'; END IF;
 IF EXISTS(SELECT 1 FROM banco.notificacion n JOIN banco.evento_auditoria a ON a.id=n.evento_id
   WHERE a.registro_afectado=(SELECT id::text FROM publicacion_prueba WHERE clave='proyecto') AND n.destinatario_usuario_id=-210005) THEN
   RAISE EXCEPTION 'Un administrador inactivo recibió el aviso'; END IF;
END $$;
SELECT pg_temp.publicacion_error('55000',$s$SELECT banco.web_editar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),'{"titulo":"Durante revisión"}',(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('55000',$s$SELECT banco.web_enviar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_resolver_publicacion(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','No',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23503',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),-219999,'aprobada','No',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','No',NULL,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','No',3,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'en_correccion','No',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('23514',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','   ',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);

-- Fallo posterior al disparador de avisos: la resolución completa revierte.
CREATE FUNCTION pg_temp.fallar_resolucion() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.operacion='resolver_publicacion' THEN RAISE EXCEPTION 'Fallo deliberado posterior al aviso'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zz_publicacion_fallo AFTER INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_resolucion();
SELECT pg_temp.publicacion_error('P0001',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','Rollback completo',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
DROP TRIGGER zz_publicacion_fallo ON banco.evento_auditoria;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM banco.decision_administrativa WHERE revision_proyecto_id=(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'))
   OR EXISTS(SELECT 1 FROM banco.evento_auditoria WHERE operacion='resolver_publicacion' AND registro_afectado=(SELECT id::text FROM publicacion_prueba WHERE clave='proyecto'))
   OR (SELECT estado FROM banco.proyecto WHERE id=(SELECT id FROM publicacion_prueba WHERE clave='proyecto'))<>'en_revision' THEN
   RAISE EXCEPTION 'El fallo dejó resolución o cambios parciales'; END IF;
END $$;

SET LOCAL ROLE banco_web;
SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'en_correccion','Precisar objetivos',NULL,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'));
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
SELECT banco.web_editar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT datos||'{"objetivos":"Objetivos corregidos"}'::jsonb FROM publicacion_prueba WHERE clave='contenido'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'));
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
INSERT INTO publicacion_prueba(clave,id,revision) SELECT 'revision_anterior',id,revision FROM publicacion_prueba WHERE clave='proyecto';
UPDATE publicacion_prueba SET revision=banco.web_enviar_proyecto(-210002,id,version) WHERE clave='proyecto';
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
RESET ROLE;
SELECT pg_temp.publicacion_error('55000',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='revision_anterior'),'aprobada','Anterior',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'aprobada','Cupo y contenido comprobados',2,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'));
RESET ROLE;
SELECT pg_temp.publicacion_error('40001',$s$SELECT banco.web_resolver_publicacion(-210001,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT revision FROM publicacion_prueba WHERE clave='proyecto'),'rechazada','Duplicado',NULL,(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SET LOCAL ROLE banco_web;
UPDATE publicacion_prueba SET version=banco.web_obtener_proyecto(-210002,id)->'proyecto'->>'version' WHERE clave='proyecto';
RESET ROLE;
SELECT pg_temp.publicacion_error('55000',$s$SELECT banco.web_editar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),'{"titulo":"Reescrito"}',(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SELECT pg_temp.publicacion_error('55000',$s$SELECT banco.web_enviar_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'),(SELECT version FROM publicacion_prueba WHERE clave='proyecto'))$s$);
DO $$ DECLARE v jsonb; BEGIN
 v:=banco.web_obtener_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'));
 IF v->'proyecto'->>'estado'<>'publicado' OR v->'proyecto'->>'cupo_maximo_alumnos'<>'2'
   OR jsonb_array_length(v->'revisiones')<>2 OR v->'revisiones'->1->'instantanea_contenido'->'proyecto'->>'objetivos'<>'Objetivos'
   OR v->'revisiones'->0->'instantanea_contenido'->'proyecto'->>'objetivos'<>'Objetivos corregidos'
   OR v->'revisiones'->0->'decision'->>'administrador_nombre'<>'Admin publicación' THEN
   RAISE EXCEPTION 'Publicación, cupo, historial o identidad de la resolución incorrectos'; END IF;
 IF (SELECT count(*) FROM banco.notificacion n JOIN banco.evento_auditoria a ON a.id=n.evento_id
   WHERE a.operacion='resolver_publicacion' AND a.registro_afectado=(SELECT id::text FROM publicacion_prueba WHERE clave='proyecto') AND n.destinatario_usuario_id=-210002)<>2 THEN
   RAISE EXCEPTION 'No hubo un aviso por resolución a su representante'; END IF;
 IF EXISTS(SELECT 1 FROM banco.notificacion n JOIN banco.evento_auditoria a ON a.id=n.evento_id
   WHERE a.registro_afectado=(SELECT id::text FROM publicacion_prueba WHERE clave='proyecto') AND
   (n.mensaje LIKE '%Precisar%' OR n.mensaje LIKE '%Cupo%' OR n.destinatario_usuario_id=-210003)) THEN
   RAISE EXCEPTION 'Aviso con motivo privado o destinatario ajeno'; END IF;
END $$;

-- El relevo conserva autoría y entrega al representante nuevo los proyectos de su empresa.
INSERT INTO publicacion_prueba(clave,id) VALUES('relevo',banco.relevar_representante(-210001,-210011,'Nuevo representante','pub-nuevo@example.invalid','!SIN-ACCESO','Relevo de prueba'));
SET LOCAL ROLE banco_web;
DO $$ DECLARE v jsonb;BEGIN
 v:=banco.web_obtener_proyecto((SELECT id FROM publicacion_prueba WHERE clave='relevo'),(SELECT id FROM publicacion_prueba WHERE clave='proyecto'));
 IF v->'proyecto'->>'autor_usuario_id'<>'-210002' THEN RAISE EXCEPTION 'El relevo reescribió autoría'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.publicacion_error('42501',$s$SELECT banco.web_obtener_proyecto(-210002,(SELECT id FROM publicacion_prueba WHERE clave='proyecto'))$s$);
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'WEB-04: publicación, permisos, versiones, historial, auditoría, avisos y rollback correctos';

-- WEB-05: perfiles propios, habilidades y catálogo con banco_web.
-- Los datos ficticios y el fallo de auditoría se revierten íntegramente.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.perfil_error(codigo text,sentencia text)
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
 (-220001,'Admin perfiles','perfil-admin@example.invalid','!SIN-ACCESO','administrador','activa'),
 (-220002,'Rep perfiles','perfil-rep@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-220003,'Alumno sin perfil','perfil-alumno@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-220004,'Profesor sin perfil','perfil-profesor@example.invalid','!SIN-ACCESO','profesor','activa'),
 (-220005,'Alumno inactivo','perfil-inactivo@example.invalid','!SIN-ACCESO','alumno','inactiva'),
 (-220006,'Alumno ajeno','perfil-ajeno@example.invalid','!SIN-ACCESO','alumno','activa');
INSERT INTO banco.empresa(id,razon_social,identificacion,sector,contacto_nombre,contacto_correo,contacto_telefono)
 VALUES(-220011,'Organización visible','IDENTIFICACION-PRIVADA','Software','Contacto comercial','publico@example.invalid','5550000000');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-220002,-220011);
INSERT INTO banco.habilidad(id,nombre,tipo) VALUES
 (-220021,'SQL aprobado','dura'),(-220022,'Comunicación aprobada','blanda'),(-220023,'Habilidad de borrador','dura');
CREATE TEMP TABLE perfil_prueba(clave text PRIMARY KEY,id bigint,version text,revision bigint,datos jsonb);
GRANT SELECT,INSERT,UPDATE ON perfil_prueba TO banco_web;

SELECT pg_temp.perfil_error('42501',$s$SELECT * FROM banco.alumno$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT * FROM banco.profesor$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT * FROM banco.alumno_habilidad$s$);
SELECT pg_temp.perfil_error('42501',$s$UPDATE banco.alumno SET carrera='Otra' WHERE usuario_id=-220003$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_version_perfil(-220003)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_validar_perfil('alumno','{}')$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_exigir_academico(-220003)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_obtener_perfil_propio(-220001)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_obtener_perfil_propio(-220002)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_obtener_perfil_propio(NULL)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_obtener_perfil_propio(-220005)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_listar_habilidades_perfil(-220002)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_listar_habilidades_perfil(-220005)$s$);

SET LOCAL ROLE banco_web;
INSERT INTO perfil_prueba(clave,version,datos) VALUES
 ('alumno',banco.web_obtener_perfil_propio(-220003)->>'version','{"matricula":"WEB05-A","carrera":"Sistemas","semestre":3,"datos_academicos":"Perfil académico","contacto_correo":"personal@example.invalid","habilidades":[{"habilidad_id":-220021,"nivel_dominio":"Intermedio","descripcion":"Consultas","evidencia":"https://example.invalid/evidencia"},{"habilidad_id":-220022,"descripcion":"Trabajo colaborativo"}]}'),
 ('profesor',banco.web_obtener_perfil_propio(-220004)->>'version','{"numero_empleado":"WEB05-P","especialidad":"Bases de datos","experiencia":"Cinco años","contacto_telefono":"5551234567"}');
DO $$ DECLARE v jsonb;BEGIN
 v:=banco.web_obtener_perfil_propio(-220003);
 IF v->'perfil'<>'null'::jsonb OR v->'habilidades'<>'[]'::jsonb OR v->>'version'!~'^[0-9a-f]{64}$'
   OR v->>'rol'<>'alumno' OR v::text LIKE '%correo_normalizado%' OR v::text LIKE '%hash_contrasena%' THEN
   RAISE EXCEPTION 'Respuesta de alta o privacidad del perfil incorrecta'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.perfil_error('40001',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A"}',NULL)$s$);
SELECT pg_temp.perfil_error('40001',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A"}','obsoleta')$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'[]',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"  "}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","usuario_id":-220006}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","rol":"profesor"}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","correo_normalizado":"x@example.invalid"}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":["A"]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","semestre":0}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","semestre":1.5}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","semestre":32768}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":null}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[null]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[{"habilidad_id":-220021},{"habilidad_id":-220021}]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[{"habilidad_id":-220021,"archivo":"/tmp/x"}]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[{"habilidad_id":-220021,"evidencia":{}}]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[{"habilidad_id":99999999999999999999999}]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23503',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"A","habilidades":[{"habilidad_id":-229999}]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220004,'{"numero_empleado":"P","habilidades":[]}',(SELECT version FROM perfil_prueba WHERE clave='profesor'))$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_guardar_perfil_propio(-220004,'{}',(SELECT version FROM perfil_prueba WHERE clave='profesor'))$s$);

SET LOCAL ROLE banco_web;
SELECT banco.web_guardar_perfil_propio(-220003,(SELECT datos FROM perfil_prueba WHERE clave='alumno'),(SELECT version FROM perfil_prueba WHERE clave='alumno'));
SELECT banco.web_guardar_perfil_propio(-220004,(SELECT datos FROM perfil_prueba WHERE clave='profesor'),(SELECT version FROM perfil_prueba WHERE clave='profesor'));
DO $$ DECLARE a jsonb;p jsonb;BEGIN
 a:=banco.web_obtener_perfil_propio(-220003);p:=banco.web_obtener_perfil_propio(-220004);
 IF a->'perfil'->>'matricula'<>'WEB05-A' OR jsonb_array_length(a->'habilidades')<>2
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a->'habilidades') h WHERE h->>'evidencia'='https://example.invalid/evidencia')
   OR p->'perfil'->>'especialidad'<>'Bases de datos' OR p->'habilidades'<>'[]'::jsonb THEN
   RAISE EXCEPTION 'Alta de perfiles o habilidades incompleta'; END IF;
 IF banco.web_obtener_perfil_propio(-220006)->'perfil'<>'null'::jsonb THEN RAISE EXCEPTION 'Se modificó un perfil ajeno'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.perfil_error('40001',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"NO"}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
SELECT pg_temp.perfil_error('23505',$s$SELECT banco.web_guardar_perfil_propio(-220006,'{"matricula":"WEB05-A"}',banco.web_obtener_perfil_propio(-220006)->>'version')$s$);
SET LOCAL ROLE banco_web;
UPDATE perfil_prueba SET version=banco.web_obtener_perfil_propio(-220003)->>'version' WHERE clave='alumno';
RESET ROLE;
CREATE FUNCTION pg_temp.fallar_perfil() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.operacion='guardar_perfil' THEN RAISE EXCEPTION 'Fallo deliberado de auditoría'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zz_perfil_fallo AFTER INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_perfil();
SELECT pg_temp.perfil_error('P0001',$s$SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"NO-PARCIAL","habilidades":[]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'))$s$);
DROP TRIGGER zz_perfil_fallo ON banco.evento_auditoria;
DO $$ BEGIN
 IF (SELECT matricula FROM banco.alumno WHERE usuario_id=-220003)<>'WEB05-A'
   OR (SELECT count(*) FROM banco.alumno_habilidad WHERE alumno_id=-220003)<>2
   OR (SELECT count(*) FROM banco.evento_auditoria WHERE operacion='guardar_perfil' AND registro_afectado='-220003')<>1
   OR banco.web_obtener_perfil_propio(-220003)->>'version'<>(SELECT version FROM perfil_prueba WHERE clave='alumno') THEN
   RAISE EXCEPTION 'El fallo dejó perfil, habilidades, versión o auditoría parciales'; END IF;
END $$;
SET LOCAL ROLE banco_web;
SELECT banco.web_guardar_perfil_propio(-220003,'{"matricula":"WEB05-A","carrera":"Carrera corregida","habilidades":[]}',(SELECT version FROM perfil_prueba WHERE clave='alumno'));
DO $$ BEGIN
 IF banco.web_obtener_perfil_propio(-220003)->'habilidades'<>'[]'::jsonb OR
   banco.web_obtener_perfil_propio(-220003)->'perfil'->>'carrera'<>'Carrera corregida' THEN RAISE EXCEPTION 'La sustitución de habilidades no persistió'; END IF;
END $$;

-- Publicado legítimo y borrador ajeno; las opciones no exponen el segundo.
INSERT INTO perfil_prueba(clave,id) VALUES('publicado',banco.web_crear_proyecto(-220002,'{"titulo":"Inventario visible","descripcion":"Catálogo aprobado","problematica":"Problema","objetivos":"Objetivos","justificacion":"Justificación","alcance":"Alcance","modalidad":"Remoto","duracion_estimada":"Cuatro meses","cupo_maximo_alumnos":1,"habilidades":[{"habilidad_id":-220021,"obligatoria":true},{"habilidad_id":-220022,"obligatoria":false}]}'));
UPDATE perfil_prueba SET revision=banco.web_enviar_proyecto(-220002,id,banco.web_obtener_proyecto(-220002,id)->'proyecto'->>'version') WHERE clave='publicado';
SELECT banco.web_resolver_publicacion(-220001,(SELECT id FROM perfil_prueba WHERE clave='publicado'),(SELECT revision FROM perfil_prueba WHERE clave='publicado'),'aprobada','MOTIVO-INTERNO-PRIVADO',1,banco.web_obtener_proyecto(-220002,(SELECT id FROM perfil_prueba WHERE clave='publicado'))->'proyecto'->>'version');
INSERT INTO perfil_prueba(clave,id) VALUES('borrador',banco.web_crear_proyecto(-220002,'{"titulo":"BORRADOR-PRIVADO","modalidad":"MODALIDAD-PRIVADA","habilidades":[{"habilidad_id":-220023}]}'));
RESET ROLE;
UPDATE banco.habilidad SET nombre='SQL nombre posterior' WHERE id=-220021;
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_catalogo_proyectos(-220001,NULL,NULL,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_catalogo_proyectos(-220002,NULL,NULL,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_catalogo_proyectos(NULL,NULL,NULL,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220005,NULL,NULL,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220003,NULL,NULL,NULL,NULL,NULL,0,0)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220003,NULL,NULL,NULL,NULL,NULL,101,0)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220003,NULL,NULL,NULL,NULL,NULL,20,-1)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220003,NULL,NULL,NULL,NULL,'inexistente',20,0)$s$);
SELECT pg_temp.perfil_error('23514',$s$SELECT banco.web_catalogo_proyectos(-220003,repeat('x',151),NULL,NULL,NULL,NULL,20,0)$s$);
SELECT pg_temp.perfil_error('23503',$s$SELECT banco.web_obtener_proyecto_catalogo(-220003,(SELECT id FROM perfil_prueba WHERE clave='borrador'))$s$);
SELECT pg_temp.perfil_error('23503',$s$SELECT banco.web_obtener_proyecto_catalogo(-220004,-229999)$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_obtener_proyecto_catalogo(-220002,(SELECT id FROM perfil_prueba WHERE clave='publicado'))$s$);
SELECT pg_temp.perfil_error('42501',$s$SELECT banco.web_filtros_catalogo(-220001)$s$);
SET LOCAL ROLE banco_web;
DO $$ DECLARE v jsonb;f jsonb;d jsonb;p bigint;BEGIN
 SELECT id INTO p FROM perfil_prueba WHERE clave='publicado';
 v:=banco.web_catalogo_proyectos(-220003,' organización ',-220011,' REMOTO ',-220021,'dura',1,0);
 IF v->>'total'<>'1' OR v->'datos'->0->>'id'<>p::text OR v->'datos'->0->>'plazas_disponibles'<>'1'
   OR v->'datos'->0->>'direccion_disponible'<>'true' THEN RAISE EXCEPTION 'Filtros combinados o disponibilidad incorrectos'; END IF;
 IF banco.web_catalogo_proyectos(-220004,NULL,-220011,NULL,-220021,'blanda',20,0)->>'total'<>'0'
   OR banco.web_catalogo_proyectos(-220003,NULL,-220011,NULL,NULL,NULL,20,1)->'datos'<>'[]'::jsonb THEN
   RAISE EXCEPTION 'La conjunción habilidad/tipo o el desplazamiento es incorrecto'; END IF;
 d:=banco.web_obtener_proyecto_catalogo(-220004,p);f:=banco.web_filtros_catalogo(-220003);
 IF d::text LIKE '%MOTIVO-INTERNO%' OR d::text LIKE '%correo_normalizado%' OR d::text LIKE '%hash_contrasena%'
   OR d::text LIKE '%IDENTIFICACION-PRIVADA%' OR d::text LIKE '%autor_usuario_id%' OR d ? 'revisiones'
   OR d->'empresa'->>'contacto_correo'<>'publico@example.invalid' OR f::text LIKE '%MODALIDAD-PRIVADA%'
   OR f::text LIKE '%Habilidad de borrador%' OR f::text LIKE '%SQL nombre posterior%'
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(d->'habilidades') h WHERE h->>'nombre'='SQL aprobado') THEN
   RAISE EXCEPTION 'Detalle u opciones divulgan datos privados o pierden el nombre aprobado'; END IF;
END $$;
RESET ROLE;

-- Capacidad agotada y director vigente se muestran sin prometer participación.
DO $$ DECLARE p bigint;c bigint;s bigint;BEGIN
 SELECT id INTO p FROM perfil_prueba WHERE clave='publicado';
 c:=banco.presentar_candidatura(p,-220003);
 PERFORM banco.evaluar_candidatura(c,-220002,'{"tecnico":{"puntuacion":2,"comentario":"Cumple"},"blando":{"puntuacion":2,"comentario":"Cumple"},"academico":{"puntuacion":2,"comentario":"Cumple"}}','Evaluación ficticia',true);
 PERFORM banco.preseleccionar_candidatura(c,-220002);
 PERFORM banco.resolver_candidatura(c,-220001,'aprobada','Autorización ficticia');
 s:=banco.solicitar_direccion(p,-220004,'Experiencia','Justificación');
 PERFORM banco.resolver_direccion(s,-220001,'aprobada','Autorización ficticia');
 IF banco.web_obtener_proyecto_catalogo(-220003,p)->'disponibilidad'->>'plazas_disponibles'<>'0'
   OR banco.web_obtener_proyecto_catalogo(-220004,p)->'disponibilidad'->>'direccion_disponible'<>'false'
   OR banco.web_catalogo_proyectos(-220003,NULL,-220011,NULL,NULL,NULL,20,0)->>'total'<>'1' THEN
   RAISE EXCEPTION 'El proyecto completo se ocultó o la disponibilidad es incorrecta'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'WEB-05: perfiles propios, habilidades, CAS, rollback, catálogo, filtros, disponibilidad y privacidad correctos';

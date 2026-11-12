-- WEB-07: bandeja propia, lectura idempotente y reportes RF-41 sin doble conteo.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.com_web_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean:=false;
BEGIN
  BEGIN
    SET LOCAL ROLE banco_web;EXECUTE sentencia;SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>codigo THEN RAISE EXCEPTION 'Esperado %, obtenido %: %; SQL: %',codigo,SQLSTATE,SQLERRM,sentencia; END IF;
    observado:=true;
  END;
  RESET ROLE;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-240001,'Admin WEB07','sql-web07-admin@example.invalid','!SIN-ACCESO','administrador','activa'),
 (-240002,'Rep WEB07','sql-web07-rep@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-240003,'Alumno WEB07 uno','sql-web07-a1@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-240004,'Alumno WEB07 dos','sql-web07-a2@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-240005,'Profesor WEB07 anterior','sql-web07-p1@example.invalid','!SIN-ACCESO','profesor','activa'),
 (-240006,'Rep WEB07 ajeno','sql-web07-rep2@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-240007,'Inactivo WEB07','sql-web07-inactivo@example.invalid','!SIN-ACCESO','alumno','inactiva'),
 (-240008,'Profesor WEB07 vigente','sql-web07-p2@example.invalid','!SIN-ACCESO','profesor','activa'),
 (-240009,'Alumno WEB07 ajeno','sql-web07-a3@example.invalid','!SIN-ACCESO','alumno','activa');
INSERT INTO banco.alumno(usuario_id,matricula) VALUES(-240003,'WEB07-A1'),(-240004,'WEB07-A2'),(-240009,'WEB07-A3');
INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES(-240005,'WEB07-P1'),(-240008,'WEB07-P2');
INSERT INTO banco.empresa(id,razon_social) VALUES(-240101,'Empresa WEB07'),(-240102,'Empresa WEB07 ajena');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-240002,-240101),(-240006,-240102);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
 VALUES(-240201,-240101,-240002,'Proyecto WEB07 uno','Descripción','Problema','Objetivo','Justificación','Alcance',3),
 (-240202,-240101,-240002,'Proyecto WEB07 dos','Descripción','Problema','Objetivo','Justificación','Alcance',3),
 (-240203,-240102,-240006,'Proyecto WEB07 ajeno','Descripción','Problema','Objetivo','Justificación','Alcance',3);
SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,autor_usuario_id),-240001,'aprobada','MOTIVO_PRIVADO_WEB07') FROM banco.proyecto WHERE id IN (-240201,-240202,-240203);
SELECT banco.evaluar_candidatura(banco.presentar_candidatura(-240201,id),-240002,
 '{"tecnico":{"puntuacion":2,"comentario":"Cumple"},"blando":{"puntuacion":2,"comentario":"Cumple"},"academico":{"puntuacion":2,"comentario":"Cumple"}}',
 'EVALUACION_PRIVADA_WEB07',true) FROM banco.usuario WHERE id IN (-240003,-240004);
SELECT banco.preseleccionar_candidatura(id,-240002) FROM banco.candidatura WHERE proyecto_id=-240201;
SELECT banco.resolver_candidatura(id,-240001,'aprobada','ASIGNACION_PRIVADA_WEB07') FROM banco.candidatura WHERE proyecto_id=-240201;
SELECT banco.presentar_candidatura(-240203,-240009);
SELECT banco.resolver_direccion(banco.solicitar_direccion(-240201,-240005,'Experiencia','JUSTIFICACION_PRIVADA_WEB07'),-240001,'aprobada','DIRECTOR_PRIVADO_WEB07');
SELECT banco.retirar_director(id,-240001,'RETIRO_PRIVADO_WEB07') FROM banco.asignacion_direccion WHERE proyecto_id=-240201;
SELECT banco.resolver_direccion(banco.solicitar_direccion(-240201,-240008,'Experiencia','JUSTIFICACION_PRIVADA_WEB07'),-240001,'aprobada','DIRECTOR_PRIVADO_WEB07');
SELECT banco.cambiar_estado_cuenta(-240001,-240008,'inactiva','La desactivación no libera la carga');
CREATE TEMP TABLE cw(clave text PRIMARY KEY,id bigint,fecha timestamptz);
GRANT SELECT,INSERT,UPDATE ON cw TO banco_web;
INSERT INTO cw(clave,id) SELECT 'rep',id FROM banco.notificacion WHERE destinatario_usuario_id=-240002 ORDER BY id DESC LIMIT 1;
INSERT INTO cw(clave,id) SELECT 'alumno',id FROM banco.notificacion WHERE destinatario_usuario_id=-240003 ORDER BY id DESC LIMIT 1;
INSERT INTO cw(clave,id) SELECT 'admin',id FROM banco.notificacion WHERE destinatario_usuario_id=-240001 ORDER BY id DESC LIMIT 1;

SELECT pg_temp.com_web_error('42501',$s$SELECT * FROM banco.notificacion$s$);
SELECT pg_temp.com_web_error('42501',$s$UPDATE banco.notificacion SET fecha_lectura=clock_timestamp()$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.consultar_notificaciones(-240003)$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.marcar_notificacion_leida(1,-240003)$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.web_exigir_avisos(-240003)$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.web_recurso_aviso(-240003,1)$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.web_opciones_reporte('proyectos')$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.web_bandeja_avisos(-999999,'todos','',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240007,'todos','',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240003,'inventado','',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240003,'todos','',0,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240003,'todos','',101,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240003,'todos','',20,-1)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_bandeja_avisos(-240003,'todos',repeat('x',151),20,0)$s$);
SELECT pg_temp.com_web_error('23503',$s$SELECT banco.web_detalle_aviso(-240003,-999999)$s$);
SELECT pg_temp.com_web_error('42501',$s$SELECT banco.web_detalle_aviso(-240003,(SELECT id FROM cw WHERE clave='rep'))$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_leer_aviso(-240003,(SELECT id FROM cw WHERE clave='rep'))$s$);
SELECT pg_temp.com_web_error('23503',$s$SELECT banco.web_leer_aviso(-240003,-999999)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240002,'proyectos','{}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240003,'candidaturas','{}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240005,'carga_profesores','{}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'inventado','{}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','[]',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{}',0,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{}',101,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{}',20,-1)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"actor":-240003}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"buscar":[]}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"buscar":true}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos',jsonb_build_object('buscar',repeat('x',151)),20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"estado":"aprobada"}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'candidaturas','{"estado":"publicado"}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'direcciones','{"estado":"evaluada"}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'asignaciones','{"estado":"aprobada"}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'carga_profesores','{"estado":null}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"proyecto_id":-240201}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'candidaturas','{"profesor_id":-240005}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'asignaciones','{"profesor_id":-240005}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"empresa_id":true}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"empresa_id":1.5}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"empresa_id":0}',20,0)$s$);
SELECT pg_temp.com_web_error('23514',$s$SELECT banco.web_reporte(-240001,'proyectos','{"empresa_id":99999999999999999999999999}',20,0)$s$);

SET LOCAL ROLE banco_web;
DO $$
DECLARE d jsonb;e jsonb;t timestamptz;otra timestamptz;
BEGIN
  d:=banco.web_bandeja_avisos(-240003,'todos','',1,0);
  IF (d->>'total')::integer<1 OR jsonb_array_length(d->'datos')<>1 OR (d->>'no_leidos')::integer<1 THEN RAISE EXCEPTION 'Bandeja/paginación incorrecta'; END IF;
  IF d::text ~ 'MOTIVO_PRIVADO|EVALUACION_PRIVADA|hash_contrasena|correo_normalizado|evento_id' THEN RAISE EXCEPTION 'Bandeja expone campos privados'; END IF;
  d:=banco.web_detalle_aviso(-240003,(SELECT id FROM cw WHERE clave='alumno'));
  IF d->'aviso'->'fecha_lectura'<>'null'::jsonb THEN RAISE EXCEPTION 'GET detalle cambió lectura'; END IF;
  IF d->'recurso'->>'tipo'<>'candidatura' THEN RAISE EXCEPTION 'Aviso no enlaza candidatura propia'; END IF;
  t:=banco.web_leer_aviso(-240003,(SELECT id FROM cw WHERE clave='alumno'));
  otra:=banco.web_leer_aviso(-240003,(SELECT id FROM cw WHERE clave='alumno'));
  IF t IS DISTINCT FROM otra THEN RAISE EXCEPTION 'Lectura repetida cambió primera fecha'; END IF;
  d:=banco.web_bandeja_avisos(-240003,'leidos','',20,0);
  IF (d->>'total')::integer<>1 THEN RAISE EXCEPTION 'Filtro leído incorrecto'; END IF;
  IF banco.web_bandeja_avisos(-240003,'todos','SIN-COINCIDENCIA-WEB07',20,0)->>'total'<>'0' THEN RAISE EXCEPTION 'Búsqueda vacía incorrecta'; END IF;
  d:=banco.web_reporte(-240001,'proyectos','{"empresa_id":-240101}',1,0);
  IF d->>'total'<>'2' OR jsonb_array_length(d->'datos')<>1 OR d->'resumen'->>'alumnos_vigentes'<>'2' OR d->'resumen'->>'directores_vigentes'<>'1' THEN RAISE EXCEPTION 'Reporte proyectos multiplica filas o total limitado por página: %',d; END IF;
  e:=banco.web_reporte(-240001,'proyectos','{"buscar":null,"estado":null,"empresa_id":null}',20,0);
  IF e IS DISTINCT FROM banco.web_reporte(-240001,'proyectos','{}',20,0) THEN RAISE EXCEPTION 'Filtros HTML nulos no equivalen a ausencia'; END IF;
  d:=banco.web_reporte(-240001,'candidaturas','{"proyecto_id":-240201}',20,0);
  IF d->>'total'<>'2' OR d->'resumen'->>'aprobadas'<>'2' THEN RAISE EXCEPTION 'Reporte candidaturas incorrecto'; END IF;
  d:=banco.web_reporte(-240001,'direcciones','{"proyecto_id":-240201}',1,0);
  IF d->>'total'<>'2' OR d->'resumen'->>'aprobadas'<>'2' THEN RAISE EXCEPTION 'Reporte dirección confunde historial y vigencia'; END IF;
  d:=banco.web_reporte(-240001,'carga_profesores','{"profesor_id":-240008}',20,0);
  IF d->>'total'<>'1' OR d->'resumen'->>'proyectos_vigentes'<>'1' OR d->'datos'->0->>'proyectos_vigentes'<>'1' THEN RAISE EXCEPTION 'Desactivar liberó o escondió carga'; END IF;
  d:=banco.web_reporte(-240001,'asignaciones','{"proyecto_id":-240201}',1,0);
  IF d->>'total'<>'4' OR d->'resumen'->>'alumnos_vigentes'<>'2' OR d->'resumen'->>'directores_vigentes'<>'1' OR d->'resumen'->>'revocadas'<>'1' THEN RAISE EXCEPTION 'Reporte asignación multiplica historial: %',d; END IF;
  d:=banco.web_reporte(-240001,'asignaciones','{"proyecto_id":-240201,"estado":"vigente"}',20,0);
  IF d->>'total'<>'3' THEN RAISE EXCEPTION 'Filtro vigente incorrecto'; END IF;
  IF d::text ~ 'correo_normalizado|hash_contrasena|MOTIVO_PRIVADO|EVALUACION_PRIVADA|JUSTIFICACION_PRIVADA|numero_empleado|matricula' THEN RAISE EXCEPTION 'Reporte filtra información no necesaria'; END IF;
  d:=banco.web_reporte(-240001,'candidaturas','{"empresa_id":-240101,"buscar":"ajeno"}',20,0);
  IF d->>'total'<>'0' OR d->'resumen'->>'registros'<>'0' THEN RAISE EXCEPTION 'Filtros se ampliaron en vez de combinarse'; END IF;
END $$;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'WEB-07: avisos propios, lectura idempotente, reportes administrativos, filtros, totales y privacidad correctos';

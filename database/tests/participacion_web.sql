-- WEB-06: permisos, CAS, etapas, privacidad y rollback mediante banco_web.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.part_web_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean:=false;
BEGIN
  BEGIN
    SET LOCAL ROLE banco_web;
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>codigo THEN RAISE EXCEPTION 'Esperado %, obtenido %: %; SQL: %',codigo,SQLSTATE,SQLERRM,sentencia; END IF;
    observado:=true;
  END;
  RESET ROLE;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;
INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-230001,'Admin participación','pw-admin@example.invalid','!SIN-ACCESO','administrador','activa'),
 (-230002,'Rep participación','pw-rep@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-230003,'Alumno participación','pw-alumno@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-230004,'Profesor participación','pw-prof@example.invalid','!SIN-ACCESO','profesor','activa'),
 (-230005,'Alumno suplente','pw-alumno2@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-230006,'Profesor suplente','pw-prof2@example.invalid','!SIN-ACCESO','profesor','activa'),
 (-230007,'Rep ajeno','pw-rep-ajeno@example.invalid','!SIN-ACCESO','empresa','activa'),
 (-230008,'Alumno sin perfil','pw-sinperfil@example.invalid','!SIN-ACCESO','alumno','activa'),
 (-230009,'Alumno inactivo','pw-inactivo@example.invalid','!SIN-ACCESO','alumno','inactiva');
INSERT INTO banco.alumno(usuario_id,matricula,carrera,contacto_correo) VALUES
 (-230003,'PRIVADA-PW-A','Sistemas','contacto-pw@example.invalid'),(-230005,'PRIVADA-PW-B','Computación',NULL),(-230009,'PRIVADA-PW-I',NULL,NULL);
INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad) VALUES
 (-230004,'PRIVADO-PW-P','Bases de datos'),(-230006,'PRIVADO-PW-P2','Arquitectura');
INSERT INTO banco.empresa(id,razon_social) VALUES(-230011,'Organización participación'),(-230012,'Organización ajena');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-230002,-230011),(-230007,-230012);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
 SELECT -230100-n,-230011,-230002,'Proyecto WEB06 '||n,'Descripción','Problema','Objetivo','Justificación','Alcance',2 FROM generate_series(1,7)n;
SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-230002),-230001,'aprobada','MOTIVO_PUBLICACION_PRIVADO_PW') FROM banco.proyecto WHERE id BETWEEN -230107 AND -230101;
CREATE TEMP TABLE pw(clave text PRIMARY KEY,id bigint,token text,datos jsonb);
GRANT SELECT,INSERT,UPDATE ON pw TO banco_web;

SELECT pg_temp.part_web_error('42501',$s$SELECT * FROM banco.candidatura$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT * FROM banco.solicitud_direccion$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_participacion_base('candidatura',1)$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.presentar_candidatura(-230101,-230003)$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_bandeja_participacion(-230003,'direccion','','',20,0)$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_bandeja_participacion(-230007,'direccion','','',20,0)$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_bandeja_participacion(-230009,'candidatura','','',20,0)$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_bandeja_participacion(-230003,'candidatura','inventado','',20,0)$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_proyectos_participacion(-230003,'','',0,0)$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_contexto_postulacion(-230002,-230101)$s$);
SELECT pg_temp.part_web_error('23503',$s$SELECT banco.web_contexto_postulacion(-230003,-999999)$s$);
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_enviar_participacion(-230008,-230101,'{}',banco.web_contexto_postulacion(-230008,-230101)->>'version')$s$);
SELECT pg_temp.part_web_error('40001',$s$SELECT banco.web_enviar_participacion(-230003,-230101,'{}',repeat('a',64))$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_enviar_participacion(-230003,-230101,'{"actor":-230005}',banco.web_contexto_postulacion(-230003,-230101)->>'version')$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_enviar_participacion(-230004,-230101,'{"experiencia_aplicable":" ","justificacion":"Motivo"}',banco.web_contexto_postulacion(-230004,-230101)->>'version')$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_enviar_participacion(-230004,-230101,'{"experiencia_aplicable":[],"justificacion":"Motivo"}',banco.web_contexto_postulacion(-230004,-230101)->>'version')$s$);

SET LOCAL ROLE banco_web;
INSERT INTO pw(clave,id) VALUES('alumno',banco.web_enviar_participacion(-230003,-230101,'{}',banco.web_contexto_postulacion(-230003,-230101)->>'version'));
INSERT INTO pw(clave,id) VALUES('docente',banco.web_enviar_participacion(-230004,-230101,'{"experiencia_aplicable":"Experiencia específica","justificacion":"Acompañar desarrollo"}',banco.web_contexto_postulacion(-230004,-230101)->>'version'));
UPDATE pw SET token=banco.web_detalle_participacion(-230002,'candidatura',id)->>'version',datos=banco.web_detalle_participacion(-230002,'candidatura',id) WHERE clave='alumno';
RESET ROLE;
DO $$BEGIN
 IF (SELECT datos::text FROM pw WHERE clave='alumno') ~ 'PRIVADA-PW-A|pw-alumno@example.invalid|SIN-ACCESO|MOTIVO_PUBLICACION_PRIVADO_PW' THEN RAISE EXCEPTION 'Se filtraron campos reservados';END IF;
 IF (SELECT datos->'perfil'->'perfil'->>'contacto_correo' FROM pw WHERE clave='alumno')<>'contacto-pw@example.invalid' THEN RAISE EXCEPTION 'Se omitió contacto académico autorizado';END IF;
END$$;
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_detalle_participacion(-230007,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_detalle_participacion(-230005,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_detalle_participacion(-230002,'direccion',(SELECT id FROM pw WHERE clave='docente'))$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'aprobar','{}',(SELECT token FROM pw WHERE clave='alumno'))$s$);
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'preseleccionar','{}',(SELECT token FROM pw WHERE clave='alumno'))$s$);
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_operar_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'aprobar','{"motivo":"Aún sin evaluación"}',banco.web_detalle_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))->>'version')$s$);
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'evaluar','{"puntuaciones":{},"comentarios":"Observación","recomendada":true}',banco.web_detalle_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))->>'version')$s$);

SET LOCAL ROLE banco_web;
SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'evaluar',
 '{"puntuaciones":{"tecnico":{"puntuacion":2,"comentario":"Conoce"},"blando":{"puntuacion":1,"comentario":"Aprende"},"academico":{"puntuacion":2,"comentario":"Cumple"}},"comentarios":"COMENTARIO_EVALUACION_PRIVADO_PW","recomendada":true}',(SELECT token FROM pw WHERE clave='alumno'));
UPDATE pw SET token=banco.web_detalle_participacion(-230002,'candidatura',id)->>'version' WHERE clave='alumno';
SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'preseleccionar','{}',(SELECT token FROM pw WHERE clave='alumno'));
RESET ROLE;
SELECT pg_temp.part_web_error('40001',$s$SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'preseleccionar','{}',(SELECT token FROM pw WHERE clave='alumno'))$s$);

SET LOCAL ROLE banco_web;
SELECT banco.web_operar_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'aprobar','{"motivo":"Autorizar alumno"}',banco.web_detalle_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))->>'version');
SELECT banco.web_operar_participacion(-230001,'direccion',(SELECT id FROM pw WHERE clave='docente'),'aprobar','{"motivo":"Autorizar director"}',banco.web_detalle_participacion(-230001,'direccion',(SELECT id FROM pw WHERE clave='docente'))->>'version');
INSERT INTO pw(clave,token) VALUES('ciclo',banco.web_detalle_proyecto_participacion(-230001,-230101)->>'version');
RESET ROLE;
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_operar_participacion(-230003,'candidatura',(SELECT id FROM pw WHERE clave='alumno'),'cancelar','{}',banco.web_detalle_participacion(-230003,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))->>'version')$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_operar_proyecto_participacion(-230002,-230101,'iniciar','{}',(SELECT token FROM pw WHERE clave='ciclo'))$s$);
SELECT pg_temp.part_web_error('40001',$s$SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'iniciar','{}',repeat('a',64))$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'iniciar','{}',(SELECT token FROM pw WHERE clave='ciclo'));
UPDATE pw SET token=banco.web_detalle_proyecto_participacion(-230001,-230101)->>'version' WHERE clave='ciclo';
SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'retirar_alumno',jsonb_build_object('asignacion_id',(SELECT id FROM banco.web_detalle_proyecto_participacion(-230001,-230101),LATERAL jsonb_to_recordset(banco.web_detalle_proyecto_participacion(-230001,-230101)->'alumnos') AS x(id bigint) LIMIT 1),'motivo','Retiro administrativo'),(SELECT token FROM pw WHERE clave='ciclo'));
RESET ROLE;
DO $$BEGIN IF (SELECT estado FROM banco.proyecto WHERE id=-230101)<>'pausado' THEN RAISE EXCEPTION 'No se pausó al perder alumnos';END IF;END$$;
SELECT pg_temp.part_web_error('23503',$s$SELECT banco.web_contexto_postulacion(-230006,-230101)$s$);
SET LOCAL ROLE banco_web;
INSERT INTO pw(clave,datos) VALUES('vacante',banco.web_detalle_proyecto_participacion(-230005,-230101));
INSERT INTO pw(clave,id) VALUES('suplente',banco.web_enviar_participacion(-230005,-230101,'{}',banco.web_contexto_postulacion(-230005,-230101)->>'version'));
RESET ROLE;
DO $$BEGIN
 IF NOT(SELECT datos->>'vacante' FROM pw WHERE clave='vacante')::boolean OR (SELECT jsonb_array_length(datos->'alumnos')+jsonb_array_length(datos->'directores') FROM pw WHERE clave='vacante')<>0 THEN RAISE EXCEPTION 'Vacante no descubrible o expone participantes';END IF;
END$$;
SELECT pg_temp.part_web_error('40001',$s$SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'reanudar','{}',(SELECT token FROM pw WHERE clave='ciclo'))$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='suplente'),'evaluar',
 '{"puntuaciones":{"tecnico":{"puntuacion":2,"comentario":"Conoce"},"blando":{"puntuacion":2,"comentario":"Cumple"},"academico":{"puntuacion":2,"comentario":"Cumple"}},"comentarios":"Suplente apto","recomendada":true}',banco.web_detalle_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='suplente'))->>'version');
SELECT banco.web_operar_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='suplente'),'preseleccionar','{}',banco.web_detalle_participacion(-230002,'candidatura',(SELECT id FROM pw WHERE clave='suplente'))->>'version');
SELECT banco.web_operar_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='suplente'),'aprobar','{"motivo":"Reposición autorizada"}',banco.web_detalle_participacion(-230001,'candidatura',(SELECT id FROM pw WHERE clave='suplente'))->>'version');
SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'reanudar','{}',banco.web_detalle_proyecto_participacion(-230001,-230101)->>'version');
SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'finalizar','{"motivo":"Terminación correcta"}',banco.web_detalle_proyecto_participacion(-230001,-230101)->>'version');
SELECT banco.web_detalle_participacion(-230003,'candidatura',(SELECT id FROM pw WHERE clave='alumno'))->>'version';
RESET ROLE;
DO $$BEGIN
 IF EXISTS(SELECT 1 FROM banco.asignacion_alumno WHERE proyecto_id=-230101 AND estado='vigente') OR EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE proyecto_id=-230101 AND estado='vigente') THEN RAISE EXCEPTION 'Cierre parcial';END IF;
END$$;
SELECT pg_temp.part_web_error('23503',$s$SELECT banco.web_contexto_postulacion(-230003,-230101)$s$);
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_operar_proyecto_participacion(-230001,-230101,'iniciar','{}',banco.web_detalle_proyecto_participacion(-230001,-230101)->>'version')$s$);
SELECT pg_temp.part_web_error('42501',$s$SELECT banco.web_detalle_proyecto_participacion(-230007,-230101)$s$);

SET LOCAL ROLE banco_web;
INSERT INTO pw(clave,id) VALUES('limite1',banco.web_enviar_participacion(-230003,-230103,'{}',banco.web_contexto_postulacion(-230003,-230103)->>'version'));
INSERT INTO pw(clave,id) VALUES('limite2',banco.web_enviar_participacion(-230003,-230104,'{}',banco.web_contexto_postulacion(-230003,-230104)->>'version'));
INSERT INTO pw(clave,id) VALUES('limite3',banco.web_enviar_participacion(-230003,-230105,'{}',banco.web_contexto_postulacion(-230003,-230105)->>'version'));
RESET ROLE;
SELECT pg_temp.part_web_error('55000',$s$SELECT banco.web_enviar_participacion(-230003,-230106,'{}',banco.web_contexto_postulacion(-230003,-230106)->>'version')$s$);
SET LOCAL ROLE banco_web;
SELECT banco.web_operar_participacion(-230003,'candidatura',(SELECT id FROM pw WHERE clave='limite1'),'cancelar','{}',banco.web_detalle_participacion(-230003,'candidatura',(SELECT id FROM pw WHERE clave='limite1'))->>'version');
INSERT INTO pw(clave,id) VALUES('cuarta',banco.web_enviar_participacion(-230003,-230106,'{}',banco.web_contexto_postulacion(-230003,-230106)->>'version'));
INSERT INTO pw(clave,id) VALUES('cancel-docente',banco.web_enviar_participacion(-230006,-230102,'{"experiencia_aplicable":"Diseño","justificacion":"Participar"}',banco.web_contexto_postulacion(-230006,-230102)->>'version'));
SELECT banco.web_operar_participacion(-230006,'direccion',(SELECT id FROM pw WHERE clave='cancel-docente'),'cancelar','{}',banco.web_detalle_participacion(-230006,'direccion',(SELECT id FROM pw WHERE clave='cancel-docente'))->>'version');
SELECT banco.web_operar_proyecto_participacion(-230001,-230106,'cancelar','{"motivo":"Cierre coordinado"}',banco.web_detalle_proyecto_participacion(-230001,-230106)->>'version');
RESET ROLE;
DO $$BEGIN
 IF (SELECT estado FROM banco.candidatura WHERE id=(SELECT id FROM pw WHERE clave='cuarta'))<>'cancelada' THEN RAISE EXCEPTION 'Cierre no canceló candidatura activa';END IF;
END$$;
CREATE FUNCTION pg_temp.fallar_evento_pw() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 IF NEW.operacion='presentar_candidatura' THEN RAISE EXCEPTION 'Fallo de auditoría inducido' USING ERRCODE='23514';END IF;RETURN NEW;END$$;
CREATE TRIGGER pw_fallo_auditoria BEFORE INSERT ON banco.evento_auditoria FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_evento_pw();
SELECT pg_temp.part_web_error('23514',$s$SELECT banco.web_enviar_participacion(-230005,-230107,'{}',banco.web_contexto_postulacion(-230005,-230107)->>'version')$s$);
DO $$BEGIN IF EXISTS(SELECT 1 FROM banco.candidatura WHERE alumno_id=-230005 AND proyecto_id=-230107) THEN RAISE EXCEPTION 'Auditoría fallida dejó candidatura';END IF;END$$;
DROP TRIGGER pw_fallo_auditoria ON banco.evento_auditoria;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'WEB-06: participación, evaluación, asignación, pausa/reposición/cierre, privacidad y rollback correctos';
ROLLBACK;

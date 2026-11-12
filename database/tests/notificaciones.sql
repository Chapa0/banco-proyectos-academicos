-- D-10/D-11: destinatarios, lectura propia, privacidad y atomicidad.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.aviso_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean:=false;
BEGIN
 BEGIN EXECUTE sentencia; SET CONSTRAINTS ALL IMMEDIATE;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>codigo THEN RAISE EXCEPTION 'Esperado %, obtenido %: %',codigo,SQLSTATE,SQLERRM; END IF;
  observado:=true;
 END;
 IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
 SET CONSTRAINTS ALL DEFERRED;
END $$;
INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-180001,'Administrador avisos','avisos-admin@example.invalid','!SECRETO','administrador','activa'),
 (-180002,'Empresa avisos','avisos-rep@example.invalid','!SECRETO','empresa','activa'),
 (-180003,'Alumno avisos','avisos-alumno@example.invalid','!SECRETO','alumno','activa'),
 (-180004,'Profesor avisos','avisos-prof@example.invalid','!SECRETO','profesor','activa'),
 (-180005,'Alumno ajeno','avisos-ajeno@example.invalid','!SECRETO','alumno','activa'),
 (-180006,'Admin inactivo','avisos-inactivo@example.invalid','!SECRETO','administrador','inactiva');
INSERT INTO banco.alumno(usuario_id,matricula) VALUES(-180003,'AVISO-01'),(-180005,'AVISO-02');
INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES(-180004,'AVISO-P01');
INSERT INTO banco.empresa(id,razon_social) VALUES(-180010,'Empresa ficticia de avisos');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-180002,-180010);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
 objetivos,justificacion,alcance,cupo_maximo_alumnos)
VALUES(-180100,-180010,-180002,'Proyecto de avisos','Descripción','Problema','Objetivo','Justificación','Alcance',2);
SELECT banco.resolver_publicacion(banco.enviar_proyecto(-180100,-180002),-180001,'aprobada','!SECRETO motivo privado');
CREATE TEMP TABLE avisos_prueba(etiqueta text PRIMARY KEY,registro bigint,evento bigint,aviso bigint,lectura timestamptz) ON COMMIT DROP;
INSERT INTO avisos_prueba(etiqueta,registro) VALUES('candidatura',banco.presentar_candidatura(-180100,-180003));
INSERT INTO avisos_prueba(etiqueta,registro) VALUES('direccion',banco.solicitar_direccion(-180100,-180004,'Experiencia','Justificación'));
-- Evento real del flujo de evaluación: el aviso no copia su comentario.
INSERT INTO avisos_prueba(etiqueta,registro) SELECT 'evaluacion',banco.evaluar_candidatura(
 (SELECT registro FROM avisos_prueba WHERE etiqueta='candidatura'),-180002,
 '{"tecnico":{"puntuacion":2,"comentario":"!SECRETO técnico"},"blando":{"puntuacion":1,"comentario":"!SECRETO blando"},"academico":{"puntuacion":2,"comentario":"!SECRETO académico"}}',
 '!SECRETO comentario privado',true);
UPDATE avisos_prueba SET evento=(SELECT id FROM banco.evento_auditoria
 WHERE operacion='evaluar_candidatura' AND actor_usuario_id=-180002 ORDER BY id DESC LIMIT 1) WHERE etiqueta='evaluacion';
UPDATE avisos_prueba SET aviso=(SELECT id FROM banco.notificacion
 WHERE evento_id=avisos_prueba.evento AND destinatario_usuario_id=-180003) WHERE etiqueta='evaluacion';
DO $$ BEGIN
 IF (SELECT aviso FROM avisos_prueba WHERE etiqueta='evaluacion') IS NULL
  OR EXISTS(SELECT 1 FROM banco.notificacion WHERE destinatario_usuario_id IN(-180005,-180006))
  OR EXISTS(SELECT 1 FROM banco.notificacion WHERE mensaje LIKE '%SECRETO%' OR mensaje LIKE '%example.invalid%')
  OR NOT EXISTS(SELECT 1 FROM banco.notificacion n JOIN banco.evento_auditoria e ON e.id=n.evento_id
    WHERE e.operacion='presentar_candidatura' AND n.destinatario_usuario_id=-180002)
  OR NOT EXISTS(SELECT 1 FROM banco.notificacion n JOIN banco.evento_auditoria e ON e.id=n.evento_id
    WHERE e.operacion='solicitar_direccion' AND n.destinatario_usuario_id=-180001) THEN
  RAISE EXCEPTION 'Destinatarios incorrectos, falta aviso o copia de contenido privado';
 END IF;
 IF EXISTS(SELECT 1 FROM banco.consultar_notificaciones(-180003) WHERE id NOT IN
  (SELECT id FROM banco.notificacion WHERE destinatario_usuario_id=-180003)) THEN
  RAISE EXCEPTION 'La bandeja expuso un aviso ajeno';
 END IF;
END $$;
SELECT pg_temp.aviso_error('23514',$s$SELECT banco.marcar_notificacion_leida((SELECT aviso FROM avisos_prueba WHERE etiqueta='evaluacion'),-180005)$s$);
SELECT pg_temp.aviso_error('23503',$s$SELECT banco.marcar_notificacion_leida(-189999,-180003)$s$);
SELECT pg_temp.aviso_error('23514',$s$SELECT * FROM banco.consultar_notificaciones(-180006)$s$);
SELECT pg_temp.aviso_error('23514',$s$SELECT * FROM banco.consultar_notificaciones(-180003,0)$s$);
SELECT pg_temp.aviso_error('23514',$s$SELECT * FROM banco.consultar_notificaciones(-180003,101)$s$);
UPDATE avisos_prueba SET lectura=banco.marcar_notificacion_leida(aviso,-180003) WHERE etiqueta='evaluacion';
DO $$ BEGIN
 IF (SELECT banco.marcar_notificacion_leida(aviso,-180003) IS DISTINCT FROM lectura
   FROM avisos_prueba WHERE etiqueta='evaluacion') THEN RAISE EXCEPTION 'La segunda lectura cambió la primera'; END IF;
END $$;
SELECT pg_temp.aviso_error('55000',$s$UPDATE banco.notificacion SET mensaje='Alterado' WHERE id=(SELECT aviso FROM avisos_prueba WHERE etiqueta='evaluacion')$s$);
SELECT pg_temp.aviso_error('55000',$s$UPDATE banco.notificacion SET fecha_lectura=NULL WHERE id=(SELECT aviso FROM avisos_prueba WHERE etiqueta='evaluacion')$s$);
SELECT pg_temp.aviso_error('55000',$s$DELETE FROM banco.notificacion WHERE id=(SELECT aviso FROM avisos_prueba WHERE etiqueta='evaluacion')$s$);
SELECT banco.cancelar_proyecto(-180100,-180001,'!SECRETO cierre privado');
DO $$ BEGIN
 IF (SELECT count(*) FROM banco.notificacion n JOIN banco.evento_auditoria e ON e.id=n.evento_id
   WHERE e.operacion='cancelar_proyecto' AND e.registro_afectado='-180100'
   AND n.destinatario_usuario_id IN(-180002,-180003,-180004))<>3 THEN
  RAISE EXCEPTION 'El cierre no avisó exactamente a la empresa y las solicitudes afectadas'; END IF;
END $$;
-- Una entrega interna fallida revierte también la operación de negocio.
CREATE FUNCTION pg_temp.fallar_aviso() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Fallo de persistencia de aviso' USING ERRCODE='P0001'; END $$;
CREATE TRIGGER tr_prueba_aviso BEFORE INSERT ON banco.notificacion
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_aviso();
SELECT pg_temp.aviso_error('P0001',$s$SELECT banco.crear_cuenta(-180001,'No persistir','aviso-rollback@example.invalid','!SECRETO','alumno')$s$);
DROP TRIGGER tr_prueba_aviso ON banco.notificacion;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM banco.usuario WHERE correo_normalizado='aviso-rollback@example.invalid') THEN
  RAISE EXCEPTION 'El fallo de aviso dejó un alta parcial'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'OK:9 negativos de avisos, destinos, privacidad y rollback';

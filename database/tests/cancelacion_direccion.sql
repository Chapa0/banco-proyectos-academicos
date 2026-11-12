-- D-07: cancelación propia previa; datos ficticios y rollback total.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.cancel_dir_error(codigo text,sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean:=false;
BEGIN
  BEGIN
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE<>codigo THEN RAISE EXCEPTION 'Esperado %, obtenido %: %',codigo,SQLSTATE,SQLERRM; END IF;
    observado:=true;
  END;
  IF NOT observado THEN RAISE EXCEPTION 'Se aceptó indebidamente: %',sentencia; END IF;
  SET CONSTRAINTS ALL DEFERRED;
END $$;
INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-150001,'Administrador','cdir-admin@example.invalid','!FICTICIO','administrador','activa'),
 (-150002,'Empresa','cdir-empresa@example.invalid','!FICTICIO','empresa','activa'),
 (-150003,'Profesor','cdir-prof@example.invalid','!FICTICIO','profesor','activa'),
 (-150004,'Otro profesor','cdir-otro@example.invalid','!FICTICIO','profesor','activa'),
 (-150005,'Profesor inactivo','cdir-inactivo@example.invalid','!FICTICIO','profesor','inactiva');
INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES
 (-150003,'CDIR-01'),(-150004,'CDIR-02'),(-150005,'CDIR-03');
INSERT INTO banco.empresa(id,razon_social) VALUES(-150010,'Empresa ficticia');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-150002,-150010);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
 objetivos,justificacion,alcance,cupo_maximo_alumnos)
VALUES(-150100,-150010,-150002,'Proyecto cancelación','Descripción','Problema','Objetivo','Justificación','Alcance',2);
SELECT banco.resolver_publicacion(banco.enviar_proyecto(-150100,-150002),-150001,'aprobada','Publicación ficticia');
INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,experiencia_aplicable,justificacion,estado) VALUES
 (-150201,-150003,-150100,'Experiencia','Motivo','pendiente'),
 (-150202,-150005,-150100,'Experiencia','Motivo','pendiente'),
 (-150203,-150004,-150100,'Experiencia','Motivo','rechazada'),
 (-150204,-150003,-150100,'Experiencia','Motivo','pendiente');
SELECT pg_temp.cancel_dir_error('23503',$s$SELECT banco.cancelar_solicitud_direccion(-150999,-150003)$s$);
SELECT pg_temp.cancel_dir_error('23514',$s$SELECT banco.cancelar_solicitud_direccion(-150201,-150004)$s$);
SELECT pg_temp.cancel_dir_error('23514',$s$SELECT banco.cancelar_solicitud_direccion(-150202,-150005)$s$);
SELECT pg_temp.cancel_dir_error('55000',$s$SELECT banco.cancelar_solicitud_direccion(-150203,-150004)$s$);
SELECT banco.cancelar_solicitud_direccion(-150201,-150003);
SELECT pg_temp.cancel_dir_error('55000',$s$SELECT banco.cancelar_solicitud_direccion(-150201,-150003)$s$);
SELECT pg_temp.cancel_dir_error('55000',$s$UPDATE banco.solicitud_direccion SET estado='pendiente' WHERE id=-150201$s$);
SELECT pg_temp.cancel_dir_error('55000',$s$UPDATE banco.solicitud_direccion SET justificacion='Reescritura' WHERE id=-150201$s$);
-- Un fallo al auditar revierte también la cancelación.
CREATE FUNCTION pg_temp.fallar_cancel_dir() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.operacion='cancelar_solicitud_direccion' THEN RAISE EXCEPTION 'Fallo inyectado' USING ERRCODE='P0001'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tr_prueba_cancel_dir BEFORE INSERT ON banco.evento_auditoria
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_cancel_dir();
SELECT pg_temp.cancel_dir_error('P0001',$s$SELECT banco.cancelar_solicitud_direccion(-150204,-150003)$s$);
DROP TRIGGER tr_prueba_cancel_dir ON banco.evento_auditoria;
DO $$ BEGIN
 IF (SELECT estado FROM banco.solicitud_direccion WHERE id=-150204)<>'pendiente'
   OR (SELECT estado FROM banco.solicitud_direccion WHERE id=-150201)<>'cancelada'
   OR (SELECT count(*) FROM banco.evento_auditoria WHERE actor_usuario_id=-150003
     AND operacion='cancelar_solicitud_direccion' AND registro_afectado='-150201')<>1
   OR EXISTS(SELECT 1 FROM banco.asignacion_direccion WHERE profesor_id=-150003) THEN
   RAISE EXCEPTION 'Cancelación sin historial, con asignación o rollback incompleto';
 END IF;
END $$;
-- Fuente aprobada y asignación son un fixture técnico, no el flujo D-08.
UPDATE banco.solicitud_direccion SET estado='aprobada' WHERE id=-150204;
INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,solicitud_direccion_id,resultado,justificacion)
 VALUES(-150300,-150001,-150204,'aprobada','Aprobación ficticia');
INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
 VALUES(-150400,-150204,-150300,-150003,-150100,'2026-01-01');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.cancel_dir_error('55000',$s$SELECT banco.cancelar_solicitud_direccion(-150204,-150003)$s$);
ROLLBACK;
SELECT 'OK:9 negativos cancelación de dirección y conservación de historial';

-- BD-01: datos ficticios; no confirma D-01..D-08/D-10..D-12 ni prueba APIs.
-- Ejecutar completo con detención ante el primer error. Todo se revierte.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- La ausencia del esquema debe hacer fallar la fase roja antes de preparar datos.
SELECT count(*) FROM banco.usuario;

CREATE FUNCTION pg_temp.espera_error(codigo text, sentencia text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observado boolean := false;
BEGIN
  BEGIN
    EXECUTE sentencia;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> codigo THEN
      RAISE EXCEPTION 'Se esperaba SQLSTATE %, se obtuvo %: %; SQL: %',
        codigo, SQLSTATE, SQLERRM, sentencia;
    END IF;
    observado := true;
  END;
  IF NOT observado THEN
    RAISE EXCEPTION 'Se esperaba SQLSTATE %, pero la sentencia fue aceptada: %', codigo, sentencia;
  END IF;
  SET CONSTRAINTS ALL DEFERRED;
END;
$$;

DO $$
DECLARE faltantes integer;
BEGIN
  SELECT count(*) INTO faltantes
  FROM unnest(ARRAY['usuario','empresa','representacion_empresa','alumno','profesor',
    'proyecto','revision_proyecto','habilidad','alumno_habilidad','proyecto_habilidad',
    'candidatura','solicitud_direccion','asignacion_alumno','asignacion_direccion',
    'acompanamiento','evaluacion_candidato','criterio_evaluacion','detalle_evaluacion',
    'decision_administrativa','evento_auditoria','notificacion']) AS esperado(nombre)
  WHERE to_regclass('banco.' || nombre) IS NULL;
  IF faltantes <> 0 THEN RAISE EXCEPTION 'Faltan % tablas del modelo', faltantes; END IF;
END;
$$;

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
 (-9101,'Administración prueba','bd-admin@example.invalid','hash-ficticio','administrador','activa'),
 (-9102,'Representante uno','bd-empresa1@example.invalid','hash-ficticio','empresa','activa'),
 (-9103,'Representante dos','bd-empresa2@example.invalid','hash-ficticio','empresa','activa'),
 (-9104,'Relevo prueba','bd-relevo@example.invalid','hash-ficticio','empresa','activa'),
 (-9105,'Alumno uno','bd-alumno1@example.invalid','hash-ficticio','alumno','activa'),
 (-9106,'Alumno dos','bd-alumno2@example.invalid','hash-ficticio','alumno','activa'),
 (-9107,'Profesor uno','bd-profesor1@example.invalid','hash-ficticio','profesor','activa'),
 (-9108,'Profesor dos','bd-profesor2@example.invalid','hash-ficticio','profesor','activa'),
 (-9109,'Administración inactiva','bd-admin-inactivo@example.invalid','hash-ficticio','administrador','inactiva');
INSERT INTO banco.empresa(id,razon_social) VALUES (-9111,'Empresa ficticia uno'),(-9112,'Empresa ficticia dos');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
VALUES (-9102,-9111,true,'2026-01-01 00:00:00+00'),(-9103,-9112,true,'2026-01-01 00:00:00+00');
INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre)
VALUES (-9105,'BD-A-01','Sistemas',1),(-9106,'BD-A-02','Sistemas',2);
INSERT INTO banco.profesor(usuario_id,numero_empleado)
VALUES (-9107,'BD-P-01'),(-9108,'BD-P-02');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES ('Inválido','bd-invalido@example.invalid','x','visitante')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES ('Inválido',' MAYUSCULAS@example.invalid ','x','alumno')$s$);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES ('Duplicado','bd-alumno1@example.invalid','x','alumno')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.alumno(usuario_id,matricula) VALUES (-9107,'BD-NO-ALUMNO')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES (-9105,'BD-NO-PROFESOR')$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.usuario SET rol_principal='profesor' WHERE id=-9105$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.usuario SET rol_principal='alumno' WHERE id=-9107$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.usuario SET rol_principal='administrador' WHERE id=-9102$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-9102$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.empresa(id,razon_social) VALUES (-9113,'Sin representante')$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.representacion_empresa SET vigente=false,fecha_fin='2026-02-01 00:00:00+00' WHERE usuario_id=-9102$s$);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion) VALUES (-9104,-9111,true,'2026-02-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.representacion_empresa SET empresa_id=-9112 WHERE usuario_id=-9102$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion) VALUES (-9105,-9111,false,'2026-01-01 00:00:00+00')$s$);

INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo)
VALUES (-9121,-9111,-9102,'Proyecto ficticio uno'),(-9122,-9112,-9103,'Proyecto ficticio dos');
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo) VALUES (-9111,-9103,'Autor ajeno')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,fecha_inicio_estimada,fecha_fin_estimada) VALUES (-9111,-9102,'Fechas inválidas','2026-06-02','2026-06-01')$s$);
INSERT INTO banco.revision_proyecto(id,proyecto_id,autor_usuario_id,numero,instantanea_contenido)
VALUES (-9131,-9121,-9102,1,'{"version_formato":1,"titulo":"Contenido enviado","habilidades":[]}');
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.revision_proyecto(proyecto_id,autor_usuario_id,numero,instantanea_contenido) VALUES (-9121,-9102,1,'{}')$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.revision_proyecto SET instantanea_contenido='{"titulo":"Sobrescrito"}' WHERE id=-9131$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.revision_proyecto SET autor_usuario_id=-9103 WHERE id=-9131$s$);
SELECT pg_temp.espera_error('55000', $s$DELETE FROM banco.revision_proyecto WHERE id=-9131$s$);
INSERT INTO banco.habilidad(id,nombre,tipo) VALUES (-9141,'Habilidad ficticia','dura');
INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio) VALUES (-9105,-9141,'Descripción de nivel');
INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria) VALUES (-9121,-9141,'Descripción mínima',true);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id) VALUES (-9105,-9141)$s$);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id) VALUES (-9121,-9141)$s$);

-- Las pruebas de asignación parten de proyectos realmente publicados.
UPDATE banco.proyecto SET descripcion='Descripción ficticia',problematica='Problemática ficticia',
  objetivos='Objetivos ficticios',justificacion='Justificación ficticia',alcance='Alcance ficticio',cupo_maximo_alumnos=2
WHERE id IN (-9121,-9122);
SELECT banco.resolver_publicacion(banco.enviar_proyecto(-9121,-9102),-9101,'aprobada','Publicación inicial de prueba');
SELECT banco.resolver_publicacion(banco.enviar_proyecto(-9122,-9103),-9101,'aprobada','Publicación inicial de prueba');

INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado) VALUES
 (-9151,-9105,-9121,'aprobada'),(-9152,-9106,-9121,'aprobada'),
 (-9153,-9105,-9122,'aprobada'),(-9154,-9105,-9121,'rechazada'),(-9155,-9105,-9121,'aprobada');
-- El historial aprobado conserva su asignación exacta; no consume carga si está cerrado.
INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado) VALUES
 (-9161,-9107,-9121,'aprobada'),(-9162,-9108,-9121,'aprobada'),
 (-9163,-9107,-9122,'aprobada'),(-9164,-9107,-9121,'aprobada');
SELECT pg_temp.espera_error('55000', $s$DELETE FROM banco.candidatura WHERE id=-9154$s$);
SELECT pg_temp.espera_error('55000', $s$DELETE FROM banco.solicitud_direccion WHERE id=-9164$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,resultado,justificacion) VALUES (-9101,'aprobada','Sin objeto')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,candidatura_id,solicitud_direccion_id,resultado,justificacion) VALUES (-9101,-9151,-9161,'aprobada','Dos objetos')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,candidatura_id,resultado,justificacion) VALUES (-9105,-9151,'aprobada','Actor sin rol')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,candidatura_id,resultado,justificacion) VALUES (-9109,-9151,'aprobada','Actor inactivo')$s$);
INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,solicitud_direccion_id,revision_proyecto_id,resultado,justificacion) VALUES
 (-9171,-9101,-9151,NULL,NULL,'aprobada','Prueba alumno uno'),
 (-9172,-9101,NULL,-9161,NULL,'aprobada','Prueba dirección uno'),
 (-9173,-9101,-9154,NULL,NULL,'rechazada','Prueba rechazo'),
 (-9174,-9101,NULL,NULL,-9131,'aprobada','Prueba revisión'),
 (-9175,-9101,-9152,NULL,NULL,'aprobada','Prueba alumno dos'),
 (-9176,-9101,NULL,-9162,NULL,'aprobada','Prueba dirección dos'),
 (-9177,-9101,-9153,NULL,NULL,'aprobada','Prueba otro proyecto'),
 (-9178,-9101,NULL,-9163,NULL,'aprobada','Prueba otra dirección'),
 (-9179,-9101,-9155,NULL,NULL,'aprobada','Prueba duplicación alumno'),
 (-9180,-9101,NULL,-9164,NULL,'aprobada','Prueba duplicación dirección');
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.decision_administrativa SET resultado='rechazada' WHERE id=-9171$s$);
SELECT pg_temp.espera_error('55000', $s$DELETE FROM banco.decision_administrativa WHERE id=-9173$s$);

SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9151,-9171,-9106,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9151,-9171,-9105,-9122,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9154,-9173,-9105,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9151,-9174,-9105,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9151,-9175,-9105,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES (-9161,-9172,-9108,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23503', $s$INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES (-9161,-9171,-9107,-9121,'2026-01-01 00:00:00+00')$s$);
INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
VALUES (-9191,-9151,-9171,-9105,-9121,'2026-01-01 00:00:00+00'),(-9195,-9152,-9175,-9106,-9121,'2026-01-01 00:00:00+00');
INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
VALUES (-9192,-9161,-9172,-9107,-9121,'2026-01-01 00:00:00+00'),(-9194,-9163,-9178,-9107,-9122,'2026-01-01 00:00:00+00');
-- Fixtures históricos técnicos coherentes con D-06. No acreditan permisos de cierre D-07.
INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio,fin,estado)
VALUES (-9193,-9153,-9177,-9105,-9122,'2025-01-01 00:00:00+00','2025-02-01 00:00:00+00','finalizada'),
       (-9196,-9155,-9179,-9105,-9121,'2025-03-01 00:00:00+00','2025-04-01 00:00:00+00','revocada');
INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio,fin,estado)
VALUES (-9197,-9162,-9176,-9108,-9121,'2025-01-01 00:00:00+00','2025-02-01 00:00:00+00','finalizada'),
       (-9198,-9164,-9180,-9107,-9121,'2025-03-01 00:00:00+00','2025-04-01 00:00:00+00','revocada');
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.asignacion_alumno(candidatura_id,decision_id,alumno_id,proyecto_id,inicio) VALUES (-9155,-9179,-9105,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.asignacion_direccion(solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio) VALUES (-9164,-9180,-9107,-9121,'2026-01-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.asignacion_alumno SET estado='finalizada' WHERE id=-9195$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.asignacion_direccion SET fin='2026-02-01 00:00:00+00' WHERE id=-9192$s$);
SELECT pg_temp.espera_error('23503', $s$UPDATE banco.candidatura SET alumno_id=-9106 WHERE id=-9151$s$);
SELECT pg_temp.espera_error('23503', $s$UPDATE banco.solicitud_direccion SET proyecto_id=-9122 WHERE id=-9161$s$);

INSERT INTO banco.acompanamiento(id,asignacion_alumno_id,asignacion_direccion_id,inicio)
VALUES (-9201,-9191,-9192,'2026-01-02 00:00:00+00');
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.acompanamiento SET asignacion_alumno_id=-9195 WHERE id=-9201$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.acompanamiento SET id=-9299 WHERE id=-9201$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.acompanamiento(asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES (-9191,-9194,'2026-01-02 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.acompanamiento(asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES (-9195,-9192,'2025-12-01 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.acompanamiento(asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES (-9191,-9192,'2026-01-03 00:00:00+00')$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.asignacion_alumno SET inicio='2026-01-03 00:00:00+00' WHERE id=-9191$s$);
SELECT pg_temp.espera_error('23514', $s$UPDATE banco.asignacion_direccion SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-9192$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.acompanamiento SET asignacion_direccion_id=-9194 WHERE id=-9201$s$);
UPDATE banco.acompanamiento SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-9201;
UPDATE banco.asignacion_alumno SET estado='finalizada',fin='2026-02-02 00:00:00+00' WHERE id=-9191;
UPDATE banco.asignacion_direccion SET estado='finalizada',fin='2026-02-02 00:00:00+00' WHERE id=-9192;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.acompanamiento SET fin='2026-01-30 00:00:00+00' WHERE id=-9201$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.asignacion_direccion SET inicio='2025-01-01 00:00:00+00' WHERE id=-9192$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.asignacion_alumno SET estado='vigente',fin=NULL WHERE id=-9191$s$);

INSERT INTO banco.evaluacion_candidato(id,candidatura_id,evaluador_usuario_id,comentarios,recomendacion)
VALUES (-9211,-9151,-9102,'Valoración ficticia','preseleccionada');
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.evaluacion_candidato(candidatura_id,evaluador_usuario_id) VALUES (-9151,-9103)$s$);
INSERT INTO banco.criterio_evaluacion(id,nombre,descripcion,escala,ponderacion)
VALUES (-9221,'Criterio ficticio','Sin política institucional','Ejemplo sin aprobación',1);
INSERT INTO banco.detalle_evaluacion(evaluacion_id,criterio_id,puntuacion,definicion_aplicada)
VALUES (-9211,-9221,1,'{"nombre":"Criterio ficticio","escala":"Ejemplo sin aprobación","ponderacion":1}');
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.evaluacion_candidato SET comentarios='Reescritura' WHERE id=-9211$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.detalle_evaluacion SET definicion_aplicada='{}' WHERE evaluacion_id=-9211$s$);
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.detalle_evaluacion SET puntuacion=2 WHERE evaluacion_id=-9211$s$);
UPDATE banco.criterio_evaluacion SET nombre='Nombre posterior' WHERE id=-9221;
DO $$ BEGIN
  IF (SELECT definicion_aplicada->>'nombre' FROM banco.detalle_evaluacion WHERE evaluacion_id=-9211) <> 'Criterio ficticio' THEN
    RAISE EXCEPTION 'Se reinterpretó el criterio histórico';
  END IF;
END $$;

INSERT INTO banco.evento_auditoria(id,actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado)
VALUES (-9231,-9101,'usuario','prueba','proyecto','-9121','realizado');
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.evento_auditoria(origen,operacion,entidad_afectada,registro_afectado,resultado) VALUES ('usuario','prueba','proyecto','-9121','realizado')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.evento_auditoria(actor_usuario_id,origen,operacion,entidad_afectada,registro_afectado,resultado) VALUES (-9101,'sistema','prueba','proyecto','-9121','realizado')$s$);
INSERT INTO banco.evento_auditoria(origen,operacion,entidad_afectada,registro_afectado,resultado)
VALUES ('sistema','prueba automática','proyecto','-9121','realizado');
SELECT pg_temp.espera_error('55000', $s$UPDATE banco.evento_auditoria SET resultado='Reescritura' WHERE id=-9231$s$);
SELECT pg_temp.espera_error('55000', $s$DELETE FROM banco.evento_auditoria WHERE id=-9231$s$);
INSERT INTO banco.notificacion(id,destinatario_usuario_id,evento_id,mensaje) VALUES (-9241,-9105,-9231,'Aviso ficticio');
SELECT pg_temp.espera_error('23505', $s$INSERT INTO banco.notificacion(destinatario_usuario_id,evento_id,mensaje) VALUES (-9105,-9231,'Repetido')$s$);
SELECT pg_temp.espera_error('23001', $s$DELETE FROM banco.usuario WHERE id=-9101$s$);

-- Relevo atómico: el orden intermedio no se convierte en un estado persistente.
UPDATE banco.representacion_empresa SET vigente=false,fecha_fin='2026-03-01 00:00:00+00' WHERE usuario_id=-9102;
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
VALUES (-9104,-9111,true,'2026-03-01 00:00:00+00');
UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-9102;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN
  IF (SELECT autor_usuario_id FROM banco.proyecto WHERE id=-9121) <> -9102
    OR (SELECT evaluador_usuario_id FROM banco.evaluacion_candidato WHERE id=-9211) <> -9102 THEN
    RAISE EXCEPTION 'El relevo alteró autoría histórica';
  END IF;
END $$;
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo) VALUES (-9111,-9102,'Autor inactivo')$s$);
SELECT pg_temp.espera_error('23514', $s$INSERT INTO banco.evaluacion_candidato(candidatura_id,evaluador_usuario_id) VALUES (-9151,-9102)$s$);
INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo) VALUES (-9111,-9104,'Proyecto tras relevo');

DO $$ BEGIN
  IF has_table_privilege('banco_escritura','banco.asignacion_alumno','INSERT')
    OR has_table_privilege('banco_escritura','banco.decision_administrativa','INSERT')
    OR has_table_privilege('banco_escritura','banco.candidatura','INSERT') THEN
    RAISE EXCEPTION 'Una cuenta técnica puede ejecutar procesos condicionados';
  END IF;
  IF has_column_privilege('banco_lectura','banco.usuario','hash_contrasena','SELECT')
    OR has_column_privilege('banco_escritura','banco.usuario','hash_contrasena','SELECT') THEN
    RAISE EXCEPTION 'Una cuenta técnica puede consultar hashes';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
-- Probar la consulta real, además de las ACL individuales de tabla/columna.
-- Sin USAGE de esquema, esos permisos por sí solos no permiten usar la vista.
SET LOCAL ROLE banco_lectura;
SELECT count(*) FROM banco.v_usuario_directorio;
SET LOCAL ROLE banco_escritura;
SELECT count(*) FROM banco.v_usuario_directorio;
RESET ROLE;
SELECT 'BD-01: integridad correcta; cambios de prueba revertidos' AS resultado;
ROLLBACK;

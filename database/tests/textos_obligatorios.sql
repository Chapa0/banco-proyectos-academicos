-- RF-08/RN-02/RF-40: contenido obligatorio, preservación exacta y rollback.
-- Datos ficticios revertidos; no impone longitud, formato editorial o rúbrica.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
CREATE FUNCTION pg_temp.texto_error(codigo text,sentencia text)
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

INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
 (-110001,'Admin textos','textos-admin@example.invalid','!FICTICIO','administrador'),
 (-110002,'Representante textos','textos-rep@example.invalid','!FICTICIO','empresa');
INSERT INTO banco.empresa(id,razon_social) VALUES (-110010,'Empresa ficticia de textos');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-110002,-110010);
INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
SELECT id,-110010,-110002,'Título válido','Descripción válida','Problemática válida',
 'Objetivos válidos','Justificación válida','Alcance válido',2
FROM generate_series(-110108,-110101) AS proyectos(id);

-- Cada campo se comprueba por separado: un campo omitido del validador no
-- debe quedar oculto porque otro de los seis también sea inválido.
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET titulo=E'\t\n' WHERE id=-110101; SELECT banco.enviar_proyecto(-110101,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET descripcion=E'\r\n\t' WHERE id=-110102; SELECT banco.enviar_proyecto(-110102,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET problematica=E'\t\n' WHERE id=-110103; SELECT banco.enviar_proyecto(-110103,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET objetivos=E'\r\n' WHERE id=-110104; SELECT banco.enviar_proyecto(-110104,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET justificacion=E' \t\n ' WHERE id=-110105; SELECT banco.enviar_proyecto(-110105,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$UPDATE banco.proyecto SET alcance=E'\t\n' WHERE id=-110106; SELECT banco.enviar_proyecto(-110106,-110002)$s$);
SELECT pg_temp.texto_error('23514',$s$
 UPDATE banco.proyecto SET titulo=E'\t\n',descripcion=E'\t\n',problematica=E'\t\n',
   objetivos=E'\t\n',justificacion=E'\t\n',alcance=E'\t\n' WHERE id=-110107;
 SELECT banco.enviar_proyecto(-110107,-110002)$s$);

-- NULL se comprueba en memoria con el mismo tipo compuesto que usan las
-- operaciones; el título nulo de una fila real sigue sujeto a NOT NULL.
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('titulo',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('descripcion',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('problematica',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('objetivos',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('justificacion',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.exigir_campos_proyecto(jsonb_populate_record(p,jsonb_build_object('alcance',NULL))) FROM banco.proyecto p WHERE id=-110101$s$);
SELECT pg_temp.texto_error('23502',$s$UPDATE banco.proyecto SET titulo=NULL WHERE id=-110101$s$);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM banco.proyecto WHERE empresa_id=-110010 AND estado<>'borrador')
    OR EXISTS (SELECT 1 FROM banco.revision_proyecto r JOIN banco.proyecto p ON p.id=r.proyecto_id WHERE p.empresa_id=-110010)
    OR EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE actor_usuario_id=-110002) THEN
    RAISE EXCEPTION 'Un envío con texto blanco dejó estado, revisión o auditoría parciales';
  END IF;
END $$;

-- Los saltos de línea y espacios alrededor de contenido real siguen admitidos
-- y se conservan exactamente en el envío y la publicación.
UPDATE banco.proyecto SET titulo=E'  Proyecto claro\nDetalle  ',
 descripcion=E'\tDescripción\nSegunda línea',problematica=E'Problema\nDocumentado',
 objetivos=E'Objetivo\tprincipal',justificacion=E'  Justificación\nAcadémica ',
 alcance=E'\tAlcance delimitado\n' WHERE id=-110108;
CREATE TEMP TABLE textos_prueba(revision_id bigint,instantanea jsonb) ON COMMIT DROP;
INSERT INTO textos_prueba(revision_id) SELECT banco.enviar_proyecto(-110108,-110002);
UPDATE textos_prueba t SET instantanea=r.instantanea_contenido FROM banco.revision_proyecto r WHERE r.id=t.revision_id;

SELECT pg_temp.texto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM textos_prueba),-110001,'aprobada',E'\t\n')$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM textos_prueba),-110001,'en_correccion',E'\r\n\t')$s$);
SELECT pg_temp.texto_error('23514',$s$SELECT banco.resolver_publicacion((SELECT revision_id FROM textos_prueba),-110001,'rechazada',E' \t\n ')$s$);
-- El CHECK protege también una escritura técnica que no invoque resolver.
SELECT pg_temp.texto_error('23514',$s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,revision_proyecto_id,resultado,justificacion) SELECT -110001,revision_id,'rechazada',E'\t\n' FROM textos_prueba$s$);
SELECT pg_temp.texto_error('23502',$s$INSERT INTO banco.decision_administrativa(administrador_usuario_id,revision_proyecto_id,resultado,justificacion) SELECT -110001,revision_id,'rechazada',NULL FROM textos_prueba$s$);
DO $$ BEGIN
  IF (SELECT estado FROM banco.proyecto WHERE id=-110108)<>'en_revision'
    OR EXISTS (SELECT 1 FROM banco.decision_administrativa d JOIN textos_prueba t ON t.revision_id=d.revision_proyecto_id)
    OR EXISTS (SELECT 1 FROM banco.evento_auditoria WHERE operacion='resolver_publicacion' AND registro_afectado='-110108')
    OR NOT EXISTS (SELECT 1 FROM banco.revision_proyecto r JOIN textos_prueba t ON t.revision_id=r.id
      WHERE r.estado_revision='en_revision' AND r.instantanea_contenido=t.instantanea) THEN
    RAISE EXCEPTION 'Un motivo blanco dejó decisión, resolución o snapshot parciales';
  END IF;
END $$;

SELECT banco.resolver_publicacion((SELECT revision_id FROM textos_prueba),-110001,'aprobada',E'\tCumple RF-08\nRevisión aprobada  ');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM banco.proyecto p JOIN banco.revision_proyecto r ON r.id=p.revision_publicada_id
      JOIN textos_prueba t ON t.revision_id=r.id
      WHERE p.id=-110108 AND p.estado='publicado' AND p.titulo=E'  Proyecto claro\nDetalle  '
        AND r.instantanea_contenido=t.instantanea
        AND r.instantanea_contenido->'proyecto'->>'descripcion'=E'\tDescripción\nSegunda línea'
        AND p.modalidad IS NULL AND p.duracion_estimada IS NULL AND p.recursos IS NULL
        AND p.fecha_inicio_estimada IS NULL AND p.fecha_fin_estimada IS NULL)
    OR NOT EXISTS (SELECT 1 FROM banco.decision_administrativa d JOIN textos_prueba t ON t.revision_id=d.revision_proyecto_id
      WHERE d.justificacion=E'\tCumple RF-08\nRevisión aprobada  ')
    OR EXISTS (SELECT 1 FROM banco.proyecto_habilidad WHERE proyecto_id=-110108) THEN
    RAISE EXCEPTION 'La validación alteró texto/snapshot o exigió campos opcionales';
  END IF;
  IF has_function_privilege('banco_escritura','banco.exigir_campos_proyecto(banco.proyecto)','EXECUTE')
    OR has_function_privilege('banco_lectura','banco.exigir_campos_proyecto(banco.proyecto)','EXECUTE') THEN
    RAISE EXCEPTION 'El helper interno de validación quedó expuesto';
  END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'Textos obligatorios RF-08/RF-40, snapshot exacto y rollback: correcto' AS resultado;
ROLLBACK;

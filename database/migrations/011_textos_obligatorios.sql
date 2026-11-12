-- RF-08/RN-02 y RF-40: un texto obligatorio requiere contenido, no solo
-- espacios, tabuladores o saltos de línea. No añade campos ni longitudes.
-- Evolución de funciones y restricciones aplicadas: 001–010 quedan intactas.
-- La validación del CHECK rechaza motivos previos incompatibles sin reescribir
-- decisiones históricas ni inventar una justificación para poder migrar.

CREATE OR REPLACE FUNCTION banco.exigir_campos_proyecto(p_proyecto banco.proyecto)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,banco AS $$
BEGIN
  IF p_proyecto.titulo IS NULL OR p_proyecto.titulo !~ '[^[:space:]]'
    OR p_proyecto.descripcion IS NULL OR p_proyecto.descripcion !~ '[^[:space:]]'
    OR p_proyecto.problematica IS NULL OR p_proyecto.problematica !~ '[^[:space:]]'
    OR p_proyecto.objetivos IS NULL OR p_proyecto.objetivos !~ '[^[:space:]]'
    OR p_proyecto.justificacion IS NULL OR p_proyecto.justificacion !~ '[^[:space:]]'
    OR p_proyecto.alcance IS NULL OR p_proyecto.alcance !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'RF-08/RN-02: título, descripción, problemática, objetivos, justificación y alcance requieren texto no blanco para enviar/publicar'
      USING ERRCODE='23514';
  END IF;
END;
$$;

ALTER TABLE banco.decision_administrativa
  ADD CONSTRAINT ck_decision_justificacion_texto
  CHECK (justificacion ~ '[^[:space:]]');

REVOKE ALL ON FUNCTION banco.exigir_campos_proyecto(banco.proyecto)
  FROM PUBLIC,banco_lectura,banco_escritura;
COMMENT ON FUNCTION banco.exigir_campos_proyecto(banco.proyecto) IS
  'RF-08/RN-02: exige contenido no blanco en los seis campos originales, incluidos tabuladores y saltos de línea solos. No impone longitud ni hace obligatorios otros campos; no reescribe contenido o revisiones.';
COMMENT ON CONSTRAINT ck_decision_justificacion_texto ON banco.decision_administrativa IS
  'RF-40: exige al menos un carácter de contenido en el motivo administrativo. Conserva texto y saltos de línea significativos; no inventa ni corrige motivos históricos.';

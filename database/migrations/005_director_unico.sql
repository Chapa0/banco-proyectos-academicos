-- D-03: un único director vigente por proyecto, con historial conservado.
-- No decide cómo finalizar, revocar o sustituir una dirección (D-07).
-- CREATE UNIQUE INDEX rechaza datos previos incompatibles y serializa también
-- las inserciones concurrentes; no se modifica ninguna asignación existente.
CREATE UNIQUE INDEX uq_asignacion_direccion_proyecto_vigente
  ON banco.asignacion_direccion(proyecto_id) WHERE estado = 'vigente';

COMMENT ON INDEX banco.uq_asignacion_direccion_proyecto_vigente IS
  'D-03: máximo un director vigente por proyecto entre todos los profesores; conserva múltiples direcciones históricas finalizadas o revocadas. No autoriza sustituciones ni cierres de D-07.';

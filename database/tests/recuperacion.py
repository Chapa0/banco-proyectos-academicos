"""Detectar alteraciones de datos, estructura, secuencias e historial técnico."""


def run(db, database):
    results = {}
    for label, mutation in (
        ('contenido', "UPDATE banco.usuario SET nombre='Contenido alterado en prueba' WHERE correo_normalizado='demo-admin@example.invalid';"),
        ('indice', 'DROP INDEX banco.ix_proyecto_estado;'),
        ('permisos_esquema', 'REVOKE USAGE ON SCHEMA banco FROM banco_lectura;'),
        ('historial_ausente', 'DROP TABLE control.migracion;'),
        ('historial_checksum', "UPDATE control.migracion SET sha256=repeat('0',64) WHERE version='001_estructura.sql';"),
        ('historial_fecha', "UPDATE control.migracion SET aplicada_en=aplicada_en+interval '1 hour' WHERE version='001_estructura.sql';"),
        ('historial_estructura', 'ALTER TABLE control.migracion DROP CONSTRAINT migracion_pkey;'),
        ('secuencia_valor', "SELECT setval('banco.criterio_evaluacion_id_seq',last_value+5,is_called) FROM banco.criterio_evaluacion_id_seq;"),
        ('secuencia_llamada', "SELECT setval('banco.criterio_evaluacion_id_seq',last_value,NOT is_called) FROM banco.criterio_evaluacion_id_seq;"),
        ('secuencia_incremento', 'ALTER SEQUENCE banco.criterio_evaluacion_id_seq INCREMENT BY 2;'),
        ('secuencia_permisos', 'GRANT USAGE ON SEQUENCE banco.criterio_evaluacion_id_seq TO banco_escritura;'),
    ):
        original = db.run
        def altered(binary, target, args, text=None, timeout=90):
            value = original(binary, target, args, text, timeout)
            if binary == 'pg_restore':
                db.sql(target, mutation)
            return value
        db.run = altered
        try:
            try:
                db.restore_check(database)
            except RuntimeError as error:
                if 'difiere' not in str(error):
                    raise
                results[label] = 'alteración detectada'
            else:
                raise AssertionError(f'La restauración alterada ({label}) fue aceptada.')
        finally:
            db.run = original
    return results

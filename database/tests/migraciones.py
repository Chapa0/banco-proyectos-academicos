"""Alteraciones de historial y fallos parciales del migrador en una base temporal."""
from pathlib import Path
import tempfile


def run(db, database):
    def rejected(fragment):
        try:
            db.migrate(database)
        except RuntimeError as error:
            if fragment not in str(error):
                raise
        else:
            raise AssertionError('El migrador aceptó ' + fragment)

    db.sql(database, "INSERT INTO control.migracion(version,sha256) VALUES ('999_ausente.sql',repeat('0',64));")
    try:
        rejected('no existe')
    finally:
        db.sql(database, "DELETE FROM control.migracion WHERE version='999_ausente.sql';")
    version = db.sql(database, 'SELECT min(version) FROM control.migracion;')
    digest = db.sql(database, f"SELECT sha256 FROM control.migracion WHERE version='{version}';")
    db.sql(database, f"UPDATE control.migracion SET sha256=repeat('0',64) WHERE version='{version}';")
    try:
        rejected('cambió')
    finally:
        db.sql(database, f"UPDATE control.migracion SET sha256='{digest}' WHERE version='{version}';")
    original = db.migrations_path
    with tempfile.TemporaryDirectory(prefix='banco_migraciones_') as folder:
        temporary = Path(folder)
        for file in original.glob('*.sql'):
            (temporary / file.name).write_bytes(file.read_bytes())
        (temporary / '999_fallo.sql').write_text("CREATE TABLE banco.prueba_atomica(id int); DO $$ BEGIN RAISE EXCEPTION 'fallo deliberado'; END $$;",encoding='utf-8')
        db.migrations_path = temporary
        try:
            rejected('fallo deliberado')
            if db.sql(database,"SELECT to_regclass('banco.prueba_atomica') IS NULL;") != 't':
                raise AssertionError('Persistió una tabla de una migración fallida.')
            if db.sql(database,"SELECT count(*) FROM control.migracion WHERE version='999_fallo.sql';") != '0':
                raise AssertionError('Una migración fallida quedó registrada como aplicada.')
        finally:
            db.migrations_path = original
    return {'checksum_modificado':'rechazado','archivo_ausente':'rechazado','fallo_parcial':'rollback comprobado'}

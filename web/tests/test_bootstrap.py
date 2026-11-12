"""Comprobar el primer acceso en PostgreSQL temporal, nunca en la base de trabajo."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2]
DATABASE = PROJECT / 'database'
sys.path.insert(0, str(DATABASE))
from manage import Database, sql_literal  # noqa: E402
from crear_admin_web import BootstrapError, crear, _hash_clave  # noqa: E402


class PrimerAccesoTest(unittest.TestCase):
    def setUp(self):
        self.db = Database(DATABASE / '.local/connection.json')
        self.original = self.db.target
        self.migrations = self.db.migrations_path
        self.php = PROJECT / '.local/tools/php/php.exe'
        if not self.php.is_file():
            self.fail('Esta prueba local requiere el PHP configurado para WEB-02.')
        self.folder = tempfile.TemporaryDirectory(prefix='bootstrap_prueba_', dir=PROJECT / '.local')
        self.private = Path(self.folder.name).resolve()
        self.assertTrue(self.private.parent == (PROJECT / '.local').resolve())
        self.name = None

    def tearDown(self):
        self.db.target = self.original
        self.db.migrations_path = self.migrations
        if self.name is not None:
            self.db.drop_temporary(self.name)
        self.folder.cleanup()

    def instalar(self, *, anterior=False):
        self.name = self.db.create_temporary()
        if anterior:
            source = self.private / 'migraciones'
            source.mkdir()
            for path in self.migrations.glob('*.sql'):
                if int(path.name[:3]) < 20:
                    (source / path.name).write_bytes(path.read_bytes())
            self.db.migrations_path = source
        self.db.migrate(self.name)
        self.db.migrations_path = self.migrations
        self.db.target = self.name

    def test_creacion_y_repeticion_conservan_el_acceso_y_auditoria_de_sistema(self):
        self.instalar()
        self.db.seed(self.name)
        originales = self.db.content_fingerprints(self.name)
        demo_previo = self.db.sql(self.name, """SELECT (to_jsonb(u)-ARRAY['estado_cuenta','version_acceso'])::text
          FROM banco.usuario u WHERE correo_normalizado='demo-admin@example.invalid';""")
        # La operación establece su aislamiento aun si cambia el valor de la conexión.
        self.db.env['PGOPTIONS'] += ' -c default_transaction_isolation=serializable'
        archivo = self.private / 'primer-acceso.txt'
        self.assertTrue(crear(self.db, archivo, 'Administrador de prueba', 'PRIMERO@Example.invalid', self.php))
        contenido = archivo.read_text(encoding='utf-8')
        clave = re.search(r'^Contraseña temporal: ([A-Za-z0-9_-]{32})$', contenido, re.M)
        self.assertTrue(clave is not None, 'Falta la entrega privada de contraseña temporal.')
        row = json.loads(self.db.sql(self.name, """SELECT json_build_object('hash',hash_contrasena,
          'cambio',requiere_cambio_clave,'estado',estado_cuenta,'rol',rol_principal)
          FROM banco.usuario WHERE correo_normalizado='primero@example.invalid';"""))
        self.assertTrue(row['cambio'] and row['estado'] == 'activa' and row['rol'] == 'administrador')
        self.assertTrue(bool(re.fullmatch(r'\$2y\$12\$[./A-Za-z0-9]{53}', row['hash'])), 'Hash bcrypt incompatible.')
        verify = subprocess.run([str(self.php), '-r', "$d=json_decode(stream_get_contents(STDIN),true);echo password_verify($d['clave'],$d['hash'])?'1':'0';"],
            input=json.dumps({'clave': clave[1], 'hash': row['hash']}), capture_output=True, text=True, timeout=15)
        self.assertTrue(verify.returncode == 0 and verify.stdout == '1', 'La contraseña privada no verifica contra su hash.')
        audit = self.db.sql(self.name, """SELECT resultado FROM banco.evento_auditoria
          WHERE operacion='crear_admin_inicial' AND origen='sistema' AND actor_usuario_id IS NULL;""")
        self.assertTrue(audit and clave[1] not in audit and row['hash'] not in audit and 'example.invalid' not in audit,
            'La auditoría inicial contiene datos reservados o no identifica el sistema.')
        actuales = self.db.content_fingerprints(self.name)
        self.assertTrue(all(actuales[k] == v for k, v in originales.items() if k not in ('usuario', 'evento_auditoria')),
            'La preparación inicial cambió otra tabla de negocio.')
        self.assertEqual('inactiva|2', self.db.sql(self.name, """SELECT estado_cuenta,version_acceso FROM banco.usuario
          WHERE correo_normalizado='demo-admin@example.invalid';"""))
        self.assertEqual('1', self.db.sql(self.name, "SELECT count(*) FROM banco.usuario WHERE rol_principal='administrador' AND estado_cuenta='activa';"))
        self.assertTrue(demo_previo == self.db.sql(self.name, """SELECT (to_jsonb(u)-ARRAY['estado_cuenta','version_acceso'])::text
          FROM banco.usuario u WHERE correo_normalizado='demo-admin@example.invalid';"""))
        self.assertEqual('1', self.db.sql(self.name, """SELECT count(*) FROM banco.evento_auditoria WHERE operacion='desactivar_admin_demo'
          AND origen='sistema' AND actor_usuario_id IS NULL AND resultado NOT LIKE '%example.invalid%' AND resultado NOT LIKE '%SIN-ACCESO%';"""))
        before = self.db.content_fingerprints(self.name)
        file_hash = hashlib.sha256(archivo.read_bytes()).hexdigest()
        self.assertFalse(crear(self.db, archivo, 'Otro nombre ignorado', 'otro@example.invalid', self.php))
        self.assertTrue(before == self.db.content_fingerprints(self.name))
        self.assertTrue(file_hash == hashlib.sha256(archivo.read_bytes()).hexdigest())
        self.assertFalse(list(self.private.glob('.primer-acceso-*.tmp')))

    def test_no_recrea_un_acceso_inicial_en_otro_archivo(self):
        self.instalar()
        archivo = self.private / 'primero.txt'
        crear(self.db, archivo, 'Administrador', 'primero@example.invalid', self.php)
        before = self.db.content_fingerprints(self.name)
        with self.assertRaises(BootstrapError):
            crear(self.db, self.private / 'otro.txt', 'Otro administrador', 'otro@example.invalid', self.php)
        self.assertTrue(before == self.db.content_fingerprints(self.name))
        self.assertFalse((self.private / 'otro.txt').exists())
        self.assertFalse(list(self.private.glob('.primer-acceso-*.tmp')))

    def test_un_administrador_bcrypt_activo_previo_impide_otro_bootstrap(self):
        self.instalar()
        digest = _hash_clave(self.php, secrets.token_urlsafe(24))
        self.db.sql(self.name, f"""INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal)
          VALUES('Administrador previo','previo@example.invalid',{sql_literal(digest)},'administrador');""")
        before = self.db.content_fingerprints(self.name)
        with self.assertRaises(BootstrapError):
            crear(self.db, self.private / 'acceso.txt', 'Administrador', 'nuevo@example.invalid', self.php)
        self.assertTrue(before == self.db.content_fingerprints(self.name))
        self.assertFalse(list(self.private.glob('.primer-acceso-*.tmp')))

    def test_el_rol_global_no_sustituye_la_migracion_20_en_el_destino(self):
        self.instalar(anterior=True)
        before = self.db.content_fingerprints(self.name)
        self.assertEqual('1', self.db.sql(self.name, "SELECT count(*) FROM pg_roles WHERE rolname='banco_web';"))
        with self.assertRaises(BootstrapError):
            crear(self.db, self.private / 'acceso.txt', 'Administrador', 'nuevo@example.invalid', self.php)
        self.assertTrue(before == self.db.content_fingerprints(self.name))
        self.assertFalse(list(self.private.glob('.primer-acceso-*.tmp')))

    def test_fallo_al_publicar_conserva_el_auxiliar_del_acceso_ya_confirmado(self):
        self.instalar()
        archivo = self.private / 'acceso.txt'
        with patch('crear_admin_web.os.link', side_effect=OSError('Fallo inyectado de publicación')):
            with self.assertRaises(BootstrapError) as captured:
                crear(self.db, archivo, 'Administrador', 'nuevo@example.invalid', self.php)
        recovery = captured.exception.recuperacion
        self.assertTrue(recovery is not None and recovery.is_file() and recovery.parent == self.private)
        self.assertFalse(archivo.exists())
        self.assertEqual('1', self.db.sql(self.name, "SELECT count(*) FROM banco.evento_auditoria WHERE operacion='crear_admin_inicial';"))
        self.assertEqual('1', self.db.sql(self.name, "SELECT count(*) FROM banco.usuario WHERE rol_principal='administrador';"))
        self.assertFalse(crear(self.db, recovery, 'Ignorado', 'ignorado@example.invalid', self.php))


if __name__ == '__main__':
    unittest.main()

"""Intercalaciones reales: dos conexiones, espera de bloqueo observada y resultado."""
from __future__ import annotations
import os
import queue
import subprocess
import threading
import time
import uuid


class Transaction:
    def __init__(self, db, database, name, isolation='READ COMMITTED'):
        if isolation not in ('READ COMMITTED','REPEATABLE READ'):
            raise ValueError('Aislamiento de prueba desconocido.')
        self.process = subprocess.Popen(db.command('psql', database) + ['-X','-qAt','-v','ON_ERROR_STOP=on',
            '-v','VERBOSITY=verbose'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', env={**db.env, 'PGAPPNAME':name})
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.execute(f'BEGIN ISOLATION LEVEL {isolation};')

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.strip())
        self.lines.put(None)

    def execute(self, statement):
        marker = 'fin_' + uuid.uuid4().hex
        self.process.stdin.write(statement + f"\nSELECT '{marker}';\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            line = self.lines.get(timeout=max(.1, deadline-time.monotonic()))
            if line == marker:
                return
            if line is None:
                error = self.process.stderr.read()
                self.process.wait(timeout=5)
                raise AssertionError(error)
        raise AssertionError('La conexión no terminó la sentencia dentro del límite.')

    def close(self, commit=False):
        try:
            if self.process.poll() is None:
                self.execute('COMMIT;' if commit else 'ROLLBACK;')
                self.process.stdin.close()
                self.process.wait(timeout=20)
        except BaseException:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=5)
            raise
        finally:
            if self.process.stdin and not self.process.stdin.closed:
                try:
                    self.process.stdin.close()
                except OSError:
                    if self.process.poll() is None:
                        raise
            self.reader.join(timeout=2)
            self.process.stdout.close()
            self.process.stderr.close()


def race(db, database, first, second, expected):
    token = uuid.uuid4().hex[:10]
    a = Transaction(db, database, 'bd_a_' + token)
    b = None
    waiting = False
    try:
        a.execute(first)
        app = 'bd_b_' + token
        b = subprocess.Popen(db.command('psql', database) + ['-X','-qAt','-v','ON_ERROR_STOP=on',
            '-v','VERBOSITY=verbose'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', env={**db.env, 'PGAPPNAME':app})
        b.stdin.write('BEGIN;\n' + second + '\nSET CONSTRAINTS ALL IMMEDIATE;\nCOMMIT;\n')
        b.stdin.close()
        b.stdin = None
        deadline = time.monotonic()+12
        while b.poll() is None and time.monotonic()<deadline:
            state = db.sql(database, f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';")
            if state == '1':
                waiting = True
                break
            time.sleep(.04)
        if not waiting:
            out, error = b.communicate(timeout=3)
            raise AssertionError('La segunda conexión no esperó el bloqueo: ' + error + out)
        a.close(commit=True)
        out, error = b.communicate(timeout=20)
        if b.returncode == 0 or expected not in error:
            raise AssertionError(f'Se esperaba {expected} tras la espera; código {b.returncode}: {error}{out}')
        return {'espera_de_bloqueo_observada':True, 'segunda_operacion_rechazada':expected}
    finally:
        try:
            a.close()
        finally:
            if b is not None and b.poll() is None:
                b.kill()
                b.communicate()


def run(db, database):
    db.sql(database, """
    BEGIN;
    INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
      (-3001,'Admin concurrencia','conc-admin@example.invalid','!prueba','administrador'),
      (-3002,'Rep inicial','conc-rep0@example.invalid','!prueba','empresa'),
      (-3003,'Rep A','conc-rep1@example.invalid','!prueba','empresa'),
      (-3004,'Rep B','conc-rep2@example.invalid','!prueba','empresa'),
      (-3005,'Alumno concurrencia','conc-alumno@example.invalid','!prueba','alumno'),
      (-3006,'Profesor concurrencia','conc-profesor@example.invalid','!prueba','profesor'),
      (-3010,'Perfil pendiente','conc-perfil@example.invalid','!prueba','alumno');
    INSERT INTO banco.empresa(id,razon_social) VALUES (-3100,'Empresa concurrencia ficticia');
    INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
      VALUES (-3002,-3100,true,'2026-01-01 00:00:00+00');
    INSERT INTO banco.alumno(usuario_id,matricula) VALUES (-3005,'CONC-A-01');
    INSERT INTO banco.profesor(usuario_id,numero_empleado) VALUES (-3006,'CONC-P-01');
    INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo) VALUES (-3101,-3100,-3002,'Proyecto de concurrencia ficticio');
    UPDATE banco.proyecto SET descripcion='Descripción',problematica='Problemática',objetivos='Objetivos',
      justificacion='Justificación',alcance='Alcance',cupo_maximo_alumnos=2 WHERE id=-3101;
    SELECT banco.resolver_publicacion(banco.enviar_proyecto(-3101,-3002),-3001,'aprobada','Publicación de prueba concurrente');
    INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado) VALUES (-3200,-3005,-3101,'aprobada');
    INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado) VALUES (-3201,-3006,-3101,'aprobada');
    INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,solicitud_direccion_id,resultado,justificacion) VALUES
      (-3300,-3001,-3200,NULL,'aprobada','Prueba técnica'),(-3301,-3001,NULL,-3201,'aprobada','Prueba técnica');
    INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
      VALUES (-3400,-3200,-3300,-3005,-3101,'2026-01-01 00:00:00+00');
    INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
      VALUES (-3401,-3201,-3301,-3006,-3101,'2026-01-01 00:00:00+00');
    COMMIT;
    """)
    results = {}
    results['correo_unico'] = race(db,database,
      "INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES ('Correo A','conc-unico@example.invalid','!prueba','alumno');",
      "INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES ('Correo B','conc-unico@example.invalid','!prueba','alumno');",'23505')
    results['representante_unico'] = race(db,database,
      "UPDATE banco.representacion_empresa SET vigente=false,fecha_fin='2026-02-01 00:00:00+00' WHERE usuario_id=-3002; INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion) VALUES (-3003,-3100,true,'2026-02-01 00:00:00+00');",
      "INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion) VALUES (-3004,-3100,true,'2026-02-01 00:00:00+00');",'23505')
    assert db.sql(database,"SELECT count(*) FROM banco.representacion_empresa r JOIN banco.usuario u ON u.id=r.usuario_id WHERE r.empresa_id=-3100 AND r.vigente AND u.estado_cuenta='activa';") == '1'
    results['perfil_y_cambio_de_rol'] = race(db,database,
      "INSERT INTO banco.alumno(usuario_id,matricula) VALUES (-3010,'CONC-A-02');",
      "UPDATE banco.usuario SET rol_principal='profesor' WHERE id=-3010;",'23514')
    results['acompanamiento_y_cierre_de_padre'] = race(db,database,
      "INSERT INTO banco.acompanamiento(asignacion_alumno_id,asignacion_direccion_id,inicio) VALUES (-3400,-3401,'2026-01-02 00:00:00+00');",
      "UPDATE banco.asignacion_direccion SET estado='finalizada',fin='2026-02-01 00:00:00+00' WHERE id=-3401;",'23514')
    return results


def isolation_guard(db, database):
    db.sql(database,"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-4501,'Representante RR A','rr-a@example.invalid','!prueba','empresa'),
        (-4502,'Representante RR B','rr-b@example.invalid','!prueba','empresa');
      INSERT INTO banco.empresa(id,razon_social) VALUES (-4500,'Prueba snapshot RR');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
        VALUES (-4501,-4500,true,'2026-01-01 00:00:00+00');
      COMMIT;""")
    rr = Transaction(db,database,'prueba_snapshot_rr','REPEATABLE READ')
    try:
        rr.execute('SELECT count(*) FROM banco.representacion_empresa;')
        db.sql(database,"""BEGIN;
          UPDATE banco.representacion_empresa SET vigente=false,fecha_fin='2026-02-01 00:00:00+00' WHERE usuario_id=-4501;
          INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
            VALUES (-4502,-4500,true,'2026-02-01 00:00:00+00');
          COMMIT;""")
        try:
            rr.execute("UPDATE banco.usuario SET estado_cuenta='inactiva' WHERE id=-4502; SET CONSTRAINTS ALL IMMEDIATE;")
        except AssertionError as error:
            if '25001' not in str(error):
                raise
        else:
            rr.close(commit=True)
            raise AssertionError('REPEATABLE READ permitió una escritura con snapshot anterior.')
    finally:
        rr.close()
    if db.sql(database,"SELECT estado_cuenta FROM banco.usuario WHERE id=-4502;") != 'activa':
        raise AssertionError('El aislamiento no soportado alteró la representación.')
    return 'REPEATABLE READ rechazado con 25001; representante activo conservado'


def publication_races(db, database):
    db.sql(database,"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-6801,'Admin carrera publicación','pub-carrera-admin@example.invalid','!prueba','administrador'),
        (-6802,'Representante carrera publicación','pub-carrera-rep@example.invalid','!prueba','empresa');
      INSERT INTO banco.empresa(id,razon_social) VALUES (-6811,'Empresa carrera publicación');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES (-6802,-6811);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
        VALUES (-6821,-6811,-6802,'Proyecto carrera','Descripción','Problemática','Objetivos','Justificación','Alcance',2);
      COMMIT;""")
    send = 'SELECT banco.enviar_proyecto(-6821,-6802);'
    results = {'envio_publicacion':race(db,database,send,send,'55000')}
    if db.sql(database,'SELECT count(*) FROM banco.revision_proyecto WHERE proyecto_id=-6821;') != '1':
        raise AssertionError('Se duplicó el envío a revisión.')
    revision = int(db.sql(database,'SELECT id FROM banco.revision_proyecto WHERE proyecto_id=-6821;'))
    resolve = f"SELECT banco.resolver_publicacion({revision},-6801,'aprobada','Resolución de prueba');"
    results['resolucion_publicacion'] = race(db,database,resolve,resolve,'55000')
    if db.sql(database,f'SELECT count(*) FROM banco.decision_administrativa WHERE revision_proyecto_id={revision};') != '1':
        raise AssertionError('Se duplicó la resolución de publicación.')
    if db.sql(database,'SELECT estado FROM banco.proyecto WHERE id=-6821;') != 'publicado':
        raise AssertionError('No persistió la publicación autorizada.')
    return results

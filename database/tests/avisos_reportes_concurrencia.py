"""WEB-07: lectura idempotente, desactivación/relevo y totales coherentes tras esperar."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import subprocess
import time
import uuid


def run(db, database):
    spec=importlib.util.spec_from_file_location('web07_conc',Path(__file__).with_name('concurrencia.py'))
    concurrent=importlib.util.module_from_spec(spec);spec.loader.exec_module(concurrent)
    db.sql(database,"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
        (-241001,'Admin reportes carrera','conc-web07-admin@example.invalid','!SIN-ACCESO','administrador'),
        (-241007,'Admin operador carrera','conc-web07-operador@example.invalid','!SIN-ACCESO','administrador'),
        (-241002,'Rep avisos carrera','conc-web07-rep@example.invalid','!SIN-ACCESO','empresa'),
        (-241003,'Alumno avisos carrera','conc-web07-alumno@example.invalid','!SIN-ACCESO','alumno');
      INSERT INTO banco.alumno(usuario_id,matricula) VALUES(-241003,'CONC-WEB07-A1');
      INSERT INTO banco.empresa(id,razon_social) VALUES(-241101,'Empresa WEB07 carreras');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES(-241002,-241101);
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,cupo_maximo_alumnos)
        VALUES(-241201,-241101,-241002,'Proyecto WEB07 carreras','Descripción','Problema','Objetivos','Justificación','Alcance',3),
          (-241202,-241101,-241002,'Segundo WEB07 carreras','Descripción','Problema','Objetivos','Justificación','Alcance',3);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto(id,-241002),-241007,'aprobada','Aprobar fixture') FROM banco.proyecto WHERE id IN (-241201,-241202);
      SELECT banco.evaluar_candidatura(banco.presentar_candidatura(-241201,-241003),-241002,
        '{"tecnico":{"puntuacion":2,"comentario":"Cumple"},"blando":{"puntuacion":2,"comentario":"Cumple"},"academico":{"puntuacion":2,"comentario":"Cumple"}}','Evaluación fixture',true);
      SELECT banco.preseleccionar_candidatura(id,-241002) FROM banco.candidatura WHERE proyecto_id=-241201;
      COMMIT;""")
    def runtime(sql):return 'SET LOCAL ROLE banco_web; '+sql+';'
    def notice(actor,offset=0):
        return int(db.sql(database,f'SELECT id FROM banco.notificacion WHERE destinatario_usuario_id={actor} ORDER BY id DESC OFFSET {offset} LIMIT 1;'))

    def positive_race(first,second):
        token=uuid.uuid4().hex[:10];a=concurrent.Transaction(db,database,'web07_a_'+token);b=None
        try:
            a.execute(first)
            app='web07_b_'+token
            b=subprocess.Popen(db.command('psql',database)+['-X','-qAt','-v','ON_ERROR_STOP=on','-v','VERBOSITY=verbose'],
                stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',env={**db.env,'PGAPPNAME':app})
            b.stdin.write('BEGIN;\n'+second+'\nCOMMIT;\n');b.stdin.close();b.stdin=None
            waiting=False;deadline=time.monotonic()+12
            while b.poll() is None and time.monotonic()<deadline:
                if db.sql(database,f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';")=='1':
                    waiting=True;break
                time.sleep(.04)
            if not waiting:
                out,error=b.communicate(timeout=3);raise AssertionError('No se observó espera: '+error+out)
            a.close(commit=True);out,error=b.communicate(timeout=20)
            if b.returncode:raise AssertionError('La segunda operación debía completar: '+error+out)
            return {'espera_de_bloqueo_observada':True,'segunda_operacion':'completada con integridad'}
        finally:
            a.close()
            if b is not None and b.poll() is None:b.kill();b.communicate()

    cases={};rep_notice=notice(-241002)
    cases['doble_lectura_conserva_primera_fecha']=positive_race(
        runtime(f'SELECT banco.web_leer_aviso(-241002,{rep_notice})'),
        runtime(f'SELECT banco.web_leer_aviso(-241002,{rep_notice})'))
    first=db.sql(database,f'SELECT fecha_lectura FROM banco.notificacion WHERE id={rep_notice};')
    if not first:raise AssertionError('No se conservó una primera lectura.')
    another=notice(-241002,1)
    cases['detalle_sin_efecto_y_lectura_posterior']=positive_race(
        runtime(f'SELECT banco.web_detalle_aviso(-241002,{another})'),
        runtime(f'SELECT banco.web_leer_aviso(-241002,{another})'))
    if not db.sql(database,f'SELECT fecha_lectura FROM banco.notificacion WHERE id={another};'):
        raise AssertionError('La lectura no persistió después del detalle.')

    student_notice=notice(-241003)
    cases['desactivacion_contra_lectura']=concurrent.race(db,database,
        "SELECT banco.cambiar_estado_cuenta(-241007,-241003,'inactiva','Desactivar fixture');",
        runtime(f'SELECT banco.web_leer_aviso(-241003,{student_notice})'),'23514')
    if db.sql(database,f'SELECT fecha_lectura IS NULL FROM banco.notificacion WHERE id={student_notice};')!='t':
        raise AssertionError('La cuenta inactiva marcó un aviso.')
    db.sql(database,"SELECT banco.cambiar_estado_cuenta(-241007,-241003,'activa','Reactivar fixture');")

    request=int(db.sql(database,'SELECT id FROM banco.candidatura WHERE proyecto_id=-241201;'))
    cases['reporte_ve_autorizacion_coherente_tras_esperar']=positive_race(
        f"SELECT id FROM banco.usuario WHERE id=-241001 FOR UPDATE;SELECT banco.resolver_candidatura({request},-241001,'aprobada','Autorizar fixture');",
        runtime("DO $q$ DECLARE d jsonb;BEGIN d:=banco.web_reporte(-241001,'asignaciones','{\"proyecto_id\":-241201}',20,0);IF d->>'total'<>'1' OR d->'resumen'->>'alumnos_vigentes'<>'1' OR jsonb_array_length(d->'datos')<>1 THEN RAISE EXCEPTION 'Totales y filas no corresponden a la misma autorización';END IF;END $q$"))
    cases['desactivacion_admin_contra_reporte']=concurrent.race(db,database,
        "SELECT banco.cambiar_estado_cuenta(-241007,-241001,'inactiva','Desactivar admin fixture');",
        runtime("SELECT banco.web_reporte(-241001,'proyectos','{}',20,0)"),'23514')

    cases['relevo_contra_detalle_aviso_antiguo']=concurrent.race(db,database,
        "SELECT banco.relevar_representante(-241007,-241101,'Nuevo rep WEB07','conc-web07-relevo@example.invalid','!SIN-ACCESO','Relevo de fixture');",
        runtime(f'SELECT banco.web_detalle_aviso(-241002,{rep_notice})'),'23514')
    if db.sql(database,f'SELECT fecha_lectura FROM banco.notificacion WHERE id={rep_notice};')!=first:
        raise AssertionError('La primera fecha de lectura cambió en otra operación.')
    return cases

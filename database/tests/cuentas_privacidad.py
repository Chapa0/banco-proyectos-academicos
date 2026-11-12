"""D-10: cuentas, representación conservada, perfiles mínimos y carreras reales."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import time
import uuid

ADMIN=-170001
REP=-170002
STUDENT=-170101
TEACHER=-170201
COMPANY=-170010
PROJECT=-170301


def _assert(db,database,query,expected,message):
    actual=db.sql(database,query)
    if actual!=str(expected):
        raise AssertionError(f'{message}: esperado {expected}, obtenido {actual}')


def _error(db,database,code,sql):
    try:
        db.sql(database,sql)
    except RuntimeError as error:
        if code not in str(error):
            raise AssertionError(f'Se esperaba {code}: {error}') from error
    else:
        raise AssertionError('Se aceptó una operación que debía devolver '+code)


def _concurrent():
    spec=importlib.util.spec_from_file_location('concurrencia_cuentas',Path(__file__).with_name('concurrencia.py'))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _participant_then_admin(db,database,concurrent):
    """Una formalización puede validar admin mientras la baja espera al titular."""
    token=uuid.uuid4().hex[:10]
    first=concurrent.Transaction(db,database,'cuenta_autorizacion_'+token)
    second=None
    try:
        first.execute(f'SELECT usuario_id FROM banco.alumno WHERE usuario_id={STUDENT} FOR UPDATE;'
          f'SELECT id FROM banco.usuario WHERE id={STUDENT} FOR SHARE;')
        app='cuenta_baja_'+token
        second=subprocess.Popen(db.command('psql',database)+['-X','-qAt','-v','ON_ERROR_STOP=on',
          '-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
          text=True,encoding='utf-8',env={**db.env,'PGAPPNAME':app})
        second.stdin.write(f"BEGIN;SELECT banco.cambiar_estado_cuenta({ADMIN},{STUDENT},'inactiva','Baja concurrente');COMMIT;\n")
        second.stdin.close();second.stdin=None
        observed=False
        deadline=time.monotonic()+12
        while second.poll() is None and time.monotonic()<deadline:
            if db.sql(database,f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{app}' AND wait_event_type='Lock';")=='1':
                observed=True;break
            time.sleep(.04)
        if not observed:
            output,error=second.communicate(timeout=3)
            raise AssertionError('No se observó espera de baja sobre el titular: '+error+output)
        # Reproduce la última validación administrativa de una autorización
        # después de que la baja está esperando al participante.
        first.execute(f"SELECT banco.exigir_rol({ADMIN},'administrador',true);")
        first.close(commit=True)
        output,error=second.communicate(timeout=20)
        if second.returncode:
            raise AssertionError('La baja y validación del admin se interbloquearon: '+error+output)
        _assert(db,database,f'SELECT estado_cuenta FROM banco.usuario WHERE id={STUDENT};','inactiva','No confirmó la baja después de esperar')
        db.sql(database,f"SELECT banco.cambiar_estado_cuenta({ADMIN},{STUDENT},'activa','Restablecer fixture');")
        return {'espera_de_bloqueo_observada':True,
          'resultado':'validación administrativa compartida y baja confirman sin ciclo de bloqueos'}
    finally:
        try:
            first.close()
        finally:
            if second is not None and second.poll() is None:
                second.kill();second.communicate()


def _setup(db,database):
    db.sql(database,f"""BEGIN;
      INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal,estado_cuenta) VALUES
        ({ADMIN},'Admin cuentas','priv-admin@example.invalid','!HASH-RESERVADO','administrador','activa'),
        ({REP},'Empresa cuentas','priv-rep@example.invalid','!HASH-RESERVADO','empresa','activa'),
        (-170003,'Otra empresa','priv-rep2@example.invalid','!HASH-RESERVADO','empresa','activa'),
        (-170004,'Admin inactivo','priv-inactivo@example.invalid','!HASH-RESERVADO','administrador','inactiva'),
        ({STUDENT},'Alumno cuentas','priv-login@example.invalid','!HASH-RESERVADO','alumno','activa'),
        (-170102,'Alumno ajeno','priv-ajeno@example.invalid','!HASH-RESERVADO','alumno','activa'),
        ({TEACHER},'Profesor cuentas','priv-prof@example.invalid','!HASH-RESERVADO','profesor','activa'),
        (-170202,'Profesor ajeno','priv-prof2@example.invalid','!HASH-RESERVADO','profesor','activa');
      INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo,contacto_telefono) VALUES
        ({STUDENT},'MAT-RESERVADA','Sistemas',6,'Datos académicos','contacto@example.invalid','555-1701'),
        (-170102,'MAT-AJENA','Sistemas',4,NULL,NULL,NULL);
      INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad) VALUES
        ({TEACHER},'EMP-RESERVADO','Bases de datos'),(-170202,'EMP-AJENO','Redes');
      INSERT INTO banco.empresa(id,razon_social) VALUES({COMPANY},'Empresa privacidad'),(-170011,'Empresa ajena');
      INSERT INTO banco.representacion_empresa(usuario_id,empresa_id) VALUES({REP},{COMPANY}),(-170003,-170011);
      INSERT INTO banco.habilidad(id,nombre,tipo) VALUES(-170050,'SQL ficticio','dura');
      INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,evidencia)
        VALUES({STUDENT},-170050,'Intermedio','https://evidencia.invalid/a');
      INSERT INTO banco.proyecto(id,empresa_id,autor_usuario_id,titulo,descripcion,problematica,
        objetivos,justificacion,alcance,cupo_maximo_alumnos) VALUES
        ({PROJECT},{COMPANY},{REP},'Proyecto de privacidad','Descripción','Problema','Objetivo','Justificación','Alcance',2);
      SELECT banco.resolver_publicacion(banco.enviar_proyecto({PROJECT},{REP}),{ADMIN},'aprobada','Publicación ficticia');
      INSERT INTO banco.candidatura(id,alumno_id,proyecto_id,estado) VALUES(-170401,{STUDENT},{PROJECT},'aprobada');
      INSERT INTO banco.solicitud_direccion(id,profesor_id,proyecto_id,estado,experiencia_aplicable,justificacion)
        VALUES(-170601,{TEACHER},{PROJECT},'aprobada','Experiencia','Motivo');
      INSERT INTO banco.decision_administrativa(id,administrador_usuario_id,candidatura_id,solicitud_direccion_id,resultado,justificacion) VALUES
        (-170501,{ADMIN},-170401,NULL,'aprobada','Fixture técnico'),
        (-170502,{ADMIN},NULL,-170601,'aprobada','Fixture técnico');
      INSERT INTO banco.asignacion_alumno(id,candidatura_id,decision_id,alumno_id,proyecto_id,inicio)
        VALUES(-170701,-170401,-170501,{STUDENT},{PROJECT},'2026-01-01');
      INSERT INTO banco.asignacion_direccion(id,solicitud_direccion_id,decision_id,profesor_id,proyecto_id,inicio)
        VALUES(-170702,-170601,-170502,{TEACHER},{PROJECT},'2026-01-01');
      COMMIT;""")


def run(db,database):
    """El llamador proporciona una base temporal propia, nunca la de trabajo."""
    _setup(db,database)
    negatives=0
    cases=[
      ('23514',f"SELECT banco.cambiar_estado_cuenta({STUDENT},-170102,'inactiva','Motivo')"),
      ('23514',f"SELECT banco.cambiar_estado_cuenta(-170004,-170102,'inactiva','Motivo')"),
      ('23503',f"SELECT banco.cambiar_estado_cuenta({ADMIN},-179999,'inactiva','Motivo')"),
      ('23514',f"SELECT banco.cambiar_estado_cuenta({ADMIN},-170102,'borrada','Motivo')"),
      ('23514',f"SELECT banco.cambiar_estado_cuenta({ADMIN},-170102,'inactiva',E'\\t\\n')"),
      ('23514',f"SELECT banco.cambiar_estado_cuenta({ADMIN},{REP},'inactiva','Sin relevo')"),
      ('55000',f"SELECT banco.cambiar_estado_cuenta({ADMIN},-170102,'activa','Repetición')"),
      ('23514',f"SELECT banco.consultar_perfil(-170003,{STUDENT})"),
      ('23514',f"SELECT banco.consultar_perfil(-170202,{STUDENT})"),
      ('23514',f"SELECT banco.consultar_perfil(-170102,{STUDENT})"),
      ('23514',f"SELECT banco.consultar_perfil({REP},-170102)"),
      ('23514',f"SELECT banco.consultar_perfil(-170004,-170004)"),
      ('23514',f"SELECT banco.consultar_perfil({REP},{TEACHER})"),
      ('23503',f"SELECT banco.consultar_perfil({ADMIN},-179999)"),
      ('23514',f"SELECT banco.relevar_representante({STUDENT},{COMPANY},'Nuevo','no@example.invalid','!hash','Motivo')"),
      ('23503',f"SELECT banco.relevar_representante({ADMIN},-179999,'Nuevo','no@example.invalid','!hash','Motivo')"),
      ('23514',f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Nuevo','no@example.invalid','!hash',E'\\t\\n')"),
      ('23514',f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Nuevo','no@example.invalid',NULL,'Motivo')"),
      ('23505',f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Duplicado','priv-rep2@example.invalid','!hash','Motivo')"),
    ]
    for code,sql in cases:
        _error(db,database,code,sql);negatives+=1
    for actor in (REP,TEACHER):
        profile=json.loads(db.sql(database,f'SELECT banco.consultar_perfil({actor},{STUDENT});'))
        serialized=json.dumps(profile,ensure_ascii=False)
        for private in ('hash_contrasena','HASH-RESERVADO','correo_normalizado','priv-login','matricula','MAT-RESERVADA','estado_cuenta'):
            if private in serialized:
                raise AssertionError('Perfil compartido expuso dato reservado: '+private)
        if profile['perfil']['contacto_correo']!='contacto@example.invalid' or profile['habilidades'][0]['evidencia']!='https://evidencia.invalid/a':
            raise AssertionError('El perfil permitido perdió contacto o evidencia autorizada')
    for actor in (ADMIN,STUDENT):
        profile=json.loads(db.sql(database,f'SELECT banco.consultar_perfil({actor},{STUDENT});'))
        if profile['perfil']['matricula']!='MAT-RESERVADA' or 'hash_contrasena' in json.dumps(profile):
            raise AssertionError('Perfil privado incorrecto o hash expuesto')
    _assert(db,database,f"SELECT banco.consultar_perfil({TEACHER},{TEACHER})->'perfil'->>'numero_empleado';",'EMP-RESERVADO','Falta perfil docente propio')
    _assert(db,database,"SELECT has_function_privilege('banco_lectura','banco.consultar_perfil(bigint,bigint)','EXECUTE');",'f','Se otorgó acceso técnico amplio sin autenticación')

    before=db.sql(database,f"SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id=-170701;")
    db.sql(database,f"SELECT banco.cambiar_estado_cuenta({ADMIN},{STUDENT},'inactiva','Suspensión administrativa');")
    _assert(db,database,"SELECT to_jsonb(a)::text FROM banco.asignacion_alumno a WHERE id=-170701;",before,'Desactivar liberó o reescribió la asignación')
    _assert(db,database,f"SELECT count(*) FROM banco.asignacion_alumno WHERE alumno_id={STUDENT} AND estado='vigente';",1,'Desactivar liberó carga vigente')
    _error(db,database,'23514',f'SELECT banco.consultar_perfil({STUDENT},{STUDENT});');negatives+=1
    db.sql(database,f"SELECT banco.cambiar_estado_cuenta({ADMIN},{STUDENT},'activa','Reactivación autorizada');")

    failure="""CREATE FUNCTION pg_temp.fallar_cuenta() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.operacion IN ('cambiar_estado_cuenta','relevar_representante') THEN
        RAISE EXCEPTION 'Fallo de auditoría inyectado' USING ERRCODE='P0001'; END IF;RETURN NEW;END $$;
      CREATE TRIGGER tr_prueba_cuenta BEFORE INSERT ON banco.evento_auditoria
        FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_cuenta();"""
    _error(db,database,'P0001','BEGIN;'+failure+f"SELECT banco.cambiar_estado_cuenta({ADMIN},-170102,'inactiva','Motivo');COMMIT;");negatives+=1
    _assert(db,database,'SELECT estado_cuenta FROM banco.usuario WHERE id=-170102;','activa','Fallo de auditoría dejó cuenta inactiva')
    before_counts=db.counts(database)
    _error(db,database,'P0001','BEGIN;'+failure+f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Fallido','priv-fallo@example.invalid','!hash','Motivo');COMMIT;");negatives+=1
    if db.counts(database)!=before_counts:
        raise AssertionError('Relevo fallido dejó cuenta, representante o evento parcial')
    _assert(db,database,f'SELECT vigente FROM banco.representacion_empresa WHERE usuario_id={REP};','t','El relevo fallido cerró la representación')

    new=int(db.sql(database,f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Nuevo representante',' PRIV-NUEVO@Example.invalid ','!NUEVO-RESERVADO','Cambio autorizado');"))
    _assert(db,database,f"SELECT vigente::text || ':' || empresa_id::text FROM banco.representacion_empresa WHERE usuario_id={REP};",f'false:{COMPANY}','Se perdió vínculo histórico de empresa')
    _assert(db,database,f'SELECT estado_cuenta FROM banco.usuario WHERE id={REP};','inactiva','La cuenta anterior quedó activa')
    _assert(db,database,f'SELECT autor_usuario_id FROM banco.proyecto WHERE id={PROJECT};',REP,'El relevo cambió autoría histórica')
    _assert(db,database,f'SELECT count(*) FROM banco.representacion_empresa WHERE empresa_id={COMPANY} AND vigente;',1,'No quedó exactamente un representante')
    _assert(db,database,f"SELECT correo_normalizado FROM banco.usuario WHERE id={new};",'priv-nuevo@example.invalid','No normalizó nuevo correo')
    _assert(db,database,f"SELECT banco.consultar_perfil({new},{STUDENT})->>'usuario_id';",STUDENT,'La empresa perdió acceso al cambiar representante')
    _error(db,database,'23514',f'SELECT banco.consultar_perfil({REP},{STUDENT});');negatives+=1
    _error(db,database,'23514',f'UPDATE banco.representacion_empresa SET empresa_id=-170011 WHERE usuario_id={REP};');negatives+=1
    _assert(db,database,"SELECT count(*) FROM banco.evento_auditoria WHERE operacion='relevar_representante' AND registro_afectado='-170010' AND (resultado LIKE '%NUEVO-RESERVADO%' OR resultado LIKE '%example.invalid%');",0,'El evento expuso hash o correo')

    concurrent=_concurrent()
    races={}
    races['baja_espera_titular_sin_bloquear_validacion_admin']=_participant_then_admin(db,database,concurrent)
    races['relevos_sobre_misma_empresa']=concurrent.race(db,database,
      f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Concurrente','priv-carrera@example.invalid','!hash','Primero');",
      f"SELECT banco.relevar_representante({ADMIN},{COMPANY},'Duplicado','priv-carrera@example.invalid','!hash','Segundo');",'23505')
    _assert(db,database,f'SELECT count(*) FROM banco.representacion_empresa WHERE empresa_id={COMPANY} AND vigente;',1,'La carrera perdió representante único')
    _assert(db,database,f'SELECT count(*) FROM banco.representacion_empresa WHERE empresa_id={COMPANY};',3,'La carrera perdió historia o dejó relevo parcial')

    # Otra base propia permite demostrar el último administrador sin cambiar
    # ni desactivar los administradores usados por las demás pruebas.
    isolated=None
    try:
        isolated=db.create_temporary();db.migrate(isolated)
        db.sql(isolated,"""INSERT INTO banco.usuario(id,nombre,correo_normalizado,hash_contrasena,rol_principal)
          VALUES(-171001,'Admin A','priv-ultimo-a@example.invalid','!prueba','administrador'),
            (-171002,'Admin B','priv-ultimo-b@example.invalid','!prueba','administrador');""")
        races['ultimos_dos_administradores']=concurrent.race(db,isolated,
          "SELECT banco.cambiar_estado_cuenta(-171001,-171001,'inactiva','Primera baja');",
          "SELECT banco.cambiar_estado_cuenta(-171002,-171002,'inactiva','Segunda baja');",'23514')
        _assert(db,isolated,"SELECT count(*) FROM banco.usuario WHERE rol_principal='administrador' AND estado_cuenta='activa';",1,'La carrera dejó sin administración')
    finally:
        if isolated is not None: db.drop_temporary(isolated)
    return {'negativos_secuenciales':negatives,'concurrencia':races,
      'privacidad':'whitelist por titular/admin, postulante de empresa vigente y alumno de dirección vigente; sin hash/login/matrícula compartida',
      'conservacion':'desactivar conserva asignación y carga; relevo conserva empresa, autoría e historial',
      'rollback':'fallos de auditoría revierten estado de cuenta y todo el relevo',
      'limite':'Servicios INVOKER internos sin grants de aplicación; IDs recibidos no autentican. Sin purga ni sesión web.'}

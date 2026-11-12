-- Datos ficticios para inspección local. No incluyen claves de acceso válidas,
-- autorizaciones, participaciones ni políticas institucionales supuestas.
BEGIN;
SELECT pg_advisory_xact_lock(71620261029);
DO $$
DECLARE representante bigint; organizacion bigint; estudiante bigint; docente bigint;
        proyecto_demo bigint; habilidad_demo bigint;
BEGIN
  INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal)
  VALUES
    ('Administración de ejemplo','demo-admin@example.invalid','!SIN-ACCESO-DEMO','administrador'),
    ('Representante de ejemplo','demo-empresa@example.invalid','!SIN-ACCESO-DEMO','empresa'),
    ('Alumno de ejemplo','demo-alumno@example.invalid','!SIN-ACCESO-DEMO','alumno'),
    ('Profesor de ejemplo','demo-profesor@example.invalid','!SIN-ACCESO-DEMO','profesor')
  ON CONFLICT (correo_normalizado) DO NOTHING;

  SELECT id INTO STRICT representante FROM banco.usuario WHERE correo_normalizado='demo-empresa@example.invalid';
  SELECT id INTO STRICT estudiante FROM banco.usuario WHERE correo_normalizado='demo-alumno@example.invalid';
  SELECT id INTO STRICT docente FROM banco.usuario WHERE correo_normalizado='demo-profesor@example.invalid';
  SELECT empresa_id INTO organizacion FROM banco.representacion_empresa WHERE usuario_id=representante;
  IF organizacion IS NULL THEN
    INSERT INTO banco.empresa(razon_social,sector) VALUES ('Empresa de ejemplo','Tecnología') RETURNING id INTO organizacion;
    INSERT INTO banco.representacion_empresa(usuario_id,empresa_id,vigente,fecha_vinculacion)
      VALUES (representante,organizacion,true,CURRENT_TIMESTAMP);
  END IF;
  INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre)
    VALUES (estudiante,'DEMO-A-001','Sistemas Computacionales',1) ON CONFLICT (usuario_id) DO NOTHING;
  INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad)
    VALUES (docente,'DEMO-P-001','Desarrollo de software') ON CONFLICT (usuario_id) DO NOTHING;
  SELECT id INTO proyecto_demo FROM banco.proyecto WHERE autor_usuario_id=representante AND titulo='Ejemplo: sistema de inventario';
  IF proyecto_demo IS NULL THEN
    INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,descripcion)
      VALUES (organizacion,representante,'Ejemplo: sistema de inventario','Borrador ficticio para explorar el esquema.')
      RETURNING id INTO proyecto_demo;
  END IF;
  SELECT id INTO habilidad_demo FROM banco.habilidad WHERE nombre='SQL de ejemplo' AND tipo='dura';
  IF habilidad_demo IS NULL THEN
    INSERT INTO banco.habilidad(nombre,tipo,descripcion) VALUES ('SQL de ejemplo','dura','Dato ficticio, sin escala acordada.') RETURNING id INTO habilidad_demo;
  END IF;
  INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,descripcion)
    VALUES (estudiante,habilidad_demo,'Perfil de demostración') ON CONFLICT DO NOTHING;
  INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,obligatoria)
    SELECT proyecto_demo,habilidad_demo,true WHERE NOT EXISTS
      (SELECT 1 FROM banco.proyecto_habilidad WHERE proyecto_id=proyecto_demo AND habilidad_id=habilidad_demo)
    ON CONFLICT DO NOTHING;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

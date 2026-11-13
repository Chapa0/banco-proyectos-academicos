-- Datos de demostración (DEMO-01). Personas, empresas y proyectos FICTICIOS para presentar el sistema.
-- Se carga con `py -3.12 database/cargar_demo.py`, que sustituye __HASH_DEMO__ por el hash de la
-- contraseña común documentada en database/README.md. Todo pasa por las funciones de negocio
-- (enviar, publicar, postular, evaluar, resolver, iniciar y cerrar), así que estados, auditoría
-- y avisos quedan coherentes como si se hubieran usado las pantallas.
BEGIN;
SELECT pg_advisory_xact_lock(71620261112);

DO $existe$ BEGIN
  IF EXISTS (SELECT 1 FROM banco.usuario WHERE correo_normalizado LIKE '%@demo.test') THEN
    RAISE EXCEPTION 'La demostración ya está cargada en esta base' USING ERRCODE='23505';
  END IF;
END $existe$;

CREATE FUNCTION pg_temp.u(p_correo text) RETURNS bigint LANGUAGE sql STABLE AS
  $$ SELECT id FROM banco.usuario WHERE correo_normalizado=p_correo $$;
CREATE FUNCTION pg_temp.h(p_nombre text) RETURNS bigint LANGUAGE sql STABLE AS
  $$ SELECT id FROM banco.habilidad WHERE nombre=p_nombre $$;
CREATE FUNCTION pg_temp.p(p_titulo text) RETURNS bigint LANGUAGE sql STABLE AS
  $$ SELECT id FROM banco.proyecto WHERE titulo=p_titulo $$;
CREATE FUNCTION pg_temp.rubrica(t int, b int, a int, ct text, cb text, ca text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS
  $$ SELECT jsonb_build_object('tecnico',jsonb_build_object('puntuacion',t,'comentario',ct),
       'blando',jsonb_build_object('puntuacion',b,'comentario',cb),'academico',jsonb_build_object('puntuacion',a,'comentario',ca)) $$;

-- Cuentas ---------------------------------------------------------------------------------------
INSERT INTO banco.usuario(nombre,correo_normalizado,hash_contrasena,rol_principal) VALUES
  ('María Fernanda Ruiz','coordinacion@demo.test',__HASH_DEMO__,'administrador'),
  ('Jorge Medina Salazar','jorge.medina@demo.test',__HASH_DEMO__,'empresa'),
  ('Daniela Ortiz Campos','daniela.ortiz@demo.test',__HASH_DEMO__,'empresa'),
  ('Ricardo Salas Vega','ricardo.salas@demo.test',__HASH_DEMO__,'empresa'),
  ('Lucía Hernández Mora','lucia.hernandez@demo.test',__HASH_DEMO__,'empresa'),
  ('Alberto Cruz Domínguez','alberto.cruz@demo.test',__HASH_DEMO__,'profesor'),
  ('Patricia Lara Escobar','patricia.lara@demo.test',__HASH_DEMO__,'profesor'),
  ('Fernando Ríos Aguilar','fernando.rios@demo.test',__HASH_DEMO__,'profesor'),
  ('Sofía Mendoza Pérez','sofia.mendoza@demo.test',__HASH_DEMO__,'profesor'),
  ('Ana Torres Rivera','ana.torres@demo.test',__HASH_DEMO__,'alumno'),
  ('Luis Ramírez Castillo','luis.ramirez@demo.test',__HASH_DEMO__,'alumno'),
  ('Valeria Gómez Núñez','valeria.gomez@demo.test',__HASH_DEMO__,'alumno'),
  ('Diego Morales Ochoa','diego.morales@demo.test',__HASH_DEMO__,'alumno'),
  ('Camila Reyes Fuentes','camila.reyes@demo.test',__HASH_DEMO__,'alumno'),
  ('Emiliano Vázquez Luna','emiliano.vazquez@demo.test',__HASH_DEMO__,'alumno'),
  ('Ximena Flores Ibarra','ximena.flores@demo.test',__HASH_DEMO__,'alumno'),
  ('Sebastián Cortés Rojas','sebastian.cortes@demo.test',__HASH_DEMO__,'alumno'),
  ('Renata Aguirre Solís','renata.aguirre@demo.test',__HASH_DEMO__,'alumno'),
  ('Mateo Juárez Paredes','mateo.juarez@demo.test',__HASH_DEMO__,'alumno');

-- Empresas y representantes ---------------------------------------------------------------------
INSERT INTO banco.empresa(razon_social,sector,identificacion,contacto_nombre,contacto_correo,contacto_telefono) VALUES
  ('Panadería La Espiga','Alimentos y bebidas','ESP-180412-XA1','Jorge Medina Salazar','contacto@laespiga.demo.test','229 145 2201'),
  ('Clínica Veterinaria Huellitas','Salud animal','HUE-150903-KM4','Daniela Ortiz Campos','citas@huellitas.demo.test','229 310 7788'),
  ('Transportes del Golfo','Logística y transporte','TGO-090127-PL9','Ricardo Salas Vega','operaciones@tgolfo.demo.test','229 980 4410'),
  ('Cooperativa Café Altura','Agroindustria','CAL-200615-QR2','Lucía Hernández Mora','ventas@cafealtura.demo.test','228 812 0345');
INSERT INTO banco.representacion_empresa(usuario_id,empresa_id)
  SELECT pg_temp.u(c), e.id FROM (VALUES ('jorge.medina@demo.test','Panadería La Espiga'),
    ('daniela.ortiz@demo.test','Clínica Veterinaria Huellitas'),('ricardo.salas@demo.test','Transportes del Golfo'),
    ('lucia.hernandez@demo.test','Cooperativa Café Altura')) v(c,r) JOIN banco.empresa e ON e.razon_social=v.r;

-- Profesores ------------------------------------------------------------------------------------
INSERT INTO banco.profesor(usuario_id,numero_empleado,especialidad,experiencia,contacto_correo,contacto_telefono)
  SELECT pg_temp.u(c),n,e,x,c,t FROM (VALUES
  ('alberto.cruz@demo.test','DOC-0142','Bases de datos, análisis de datos y sistemas de información',
   '15 años como docente de Bases de datos. Ha dirigido 12 proyectos de residencia con empresas de la región.','229 101 0142'),
  ('patricia.lara@demo.test','DOC-0218','Desarrollo web, comercio electrónico y experiencia de usuario',
   '10 años en desarrollo web; antes trabajó como líder técnica en una agencia digital.','229 101 0218'),
  ('fernando.rios@demo.test','DOC-0305','Redes, Internet de las cosas y sistemas embebidos',
   'Ingeniero en telecomunicaciones; asesora proyectos de rastreo y sensores desde 2018.','229 101 0305'),
  ('sofia.mendoza@demo.test','DOC-0411','Ingeniería de software, metodologías ágiles y diseño de interfaces',
   'Maestra en Ingeniería de Software; certificada en Scrum. Coordina la academia de programación.','229 101 0411')) v(c,n,e,x,t);

-- Alumnos ---------------------------------------------------------------------------------------
INSERT INTO banco.alumno(usuario_id,matricula,carrera,semestre,datos_academicos,contacto_correo,contacto_telefono)
  SELECT pg_temp.u(c),m,car,s,d,CASE WHEN d IS NULL THEN NULL ELSE c END,t FROM (VALUES
  ('ana.torres@demo.test','20230145','Ingeniería en Sistemas Computacionales',8,
   'Promedio 9.3. Cursé Programación web, Bases de datos y Gestión de proyectos. Certificación en Python por la academia institucional.','229 455 1201'),
  ('luis.ramirez@demo.test','20230187','Ingeniería en Sistemas Computacionales',8,
   'Promedio 8.7. Desarrollé una app de asistencia con Flutter en la materia de Desarrollo móvil.','229 455 1202'),
  ('valeria.gomez@demo.test','20220093','Ingeniería Informática',9,
   'Promedio 9.0. Servicio social en el área de sistemas del ayuntamiento; experiencia con reportes en Power BI.','229 455 1203'),
  ('diego.morales@demo.test','20230211','Ingeniería en Sistemas Computacionales',7,
   'Promedio 8.4. Participé en el concurso regional de robótica con un prototipo de sensores.','229 455 1204'),
  ('camila.reyes@demo.test','20220156','Ingeniería en Tecnologías de la Información',9,
   'Promedio 9.5. Diseñé las interfaces del sistema de biblioteca escolar en Figma.','229 455 1205'),
  ('emiliano.vazquez@demo.test','20230264','Ingeniería en Sistemas Computacionales',7,
   'Promedio 8.1. Me interesa el desarrollo backend con PHP y Laravel.','229 455 1206'),
  ('ximena.flores@demo.test','20220178','Ingeniería Informática',8,
   'Promedio 9.1. Proyecto integrador de análisis de ventas con Python y pandas.','229 455 1207'),
  ('sebastian.cortes@demo.test','20230302','Ingeniería en Tecnologías de la Información',7,
   'Promedio 8.6. Administré la red del laboratorio de cómputo como becario.','229 455 1208'),
  ('renata.aguirre@demo.test','20220119','Ingeniería en Sistemas Computacionales',9,
   'Promedio 9.4. Desarrollé la tienda en línea de un negocio familiar con JavaScript.','229 455 1209'),
  ('mateo.juarez@demo.test','20230335','Ingeniería en Sistemas Computacionales',6,
   NULL,NULL)) v(c,m,car,s,d,t)
  -- Mateo tiene el perfil incompleto a propósito para mostrar el avance del perfil.
  ;

-- Habilidades -----------------------------------------------------------------------------------
INSERT INTO banco.habilidad(nombre,tipo,descripcion) VALUES
  ('Python','dura','Programación en Python para scripts, análisis o servicios.'),
  ('JavaScript','dura','Programación del lado del cliente y Node.js.'),
  ('PHP y Laravel','dura','Desarrollo de aplicaciones web con PHP y el framework Laravel.'),
  ('SQL y bases de datos','dura','Diseño de modelos relacionales y consultas SQL.'),
  ('HTML y CSS','dura','Maquetación de páginas web adaptables.'),
  ('Desarrollo móvil con Flutter','dura','Aplicaciones móviles multiplataforma.'),
  ('Análisis de datos','dura','Limpieza, análisis y visualización de datos.'),
  ('Redes e IoT','dura','Redes de computadoras, sensores y dispositivos conectados.'),
  ('Diseño UI/UX','dura','Diseño de interfaces y prototipos centrados en el usuario.'),
  ('Git y control de versiones','dura','Trabajo con ramas, revisiones y repositorios remotos.'),
  ('Trabajo en equipo','blanda','Colaboración y reparto de tareas en equipos de trabajo.'),
  ('Comunicación efectiva','blanda','Explicar avances y acuerdos de forma clara.'),
  ('Resolución de problemas','blanda','Analizar situaciones y proponer soluciones.'),
  ('Liderazgo','blanda','Coordinar personas y tomar decisiones.');

INSERT INTO banco.alumno_habilidad(alumno_id,habilidad_id,nivel_dominio,descripcion,evidencia)
  SELECT pg_temp.u(c),pg_temp.h(h),n,d,e FROM (VALUES
  ('ana.torres@demo.test','PHP y Laravel','Intermedio','Desarrollé el sistema de control escolar del proyecto integrador con Laravel.','Repositorio github.com/anatorres/control-escolar'),
  ('ana.torres@demo.test','SQL y bases de datos','Avanzado','Diseñé el modelo relacional y las consultas del proyecto integrador.','Constancia del curso de PostgreSQL'),
  ('ana.torres@demo.test','HTML y CSS','Avanzado','Maqueto vistas adaptables con Bootstrap.',NULL),
  ('ana.torres@demo.test','Git y control de versiones','Intermedio','Trabajo con ramas y revisiones en equipo.',NULL),
  ('ana.torres@demo.test','Trabajo en equipo','Avanzado','Coordiné tareas del equipo en tres proyectos de clase.','Carta de recomendación de la Mtra. Mendoza'),
  ('ana.torres@demo.test','Comunicación efectiva','Intermedio','Expuse los avances del proyecto final ante el grupo y la empresa invitada.',NULL),
  ('luis.ramirez@demo.test','Desarrollo móvil con Flutter','Intermedio','App de asistencia escolar publicada para pruebas internas.','github.com/luisrc/asistencia'),
  ('luis.ramirez@demo.test','JavaScript','Intermedio','Formularios dinámicos y consumo de APIs.',NULL),
  ('luis.ramirez@demo.test','Trabajo en equipo','Intermedio','Equipo de cuatro integrantes en Desarrollo móvil.',NULL),
  ('valeria.gomez@demo.test','Análisis de datos','Avanzado','Reportes de recaudación en el servicio social.','Tablero publicado en el sitio del ayuntamiento'),
  ('valeria.gomez@demo.test','SQL y bases de datos','Intermedio','Consultas para reportes mensuales.',NULL),
  ('valeria.gomez@demo.test','Python','Intermedio','Limpieza de datos con pandas.',NULL),
  ('valeria.gomez@demo.test','Comunicación efectiva','Avanzado','Presenté resultados a directivos del ayuntamiento.',NULL),
  ('diego.morales@demo.test','Redes e IoT','Intermedio','Prototipo con ESP32 y sensores de temperatura.','Video del concurso regional de robótica'),
  ('diego.morales@demo.test','Python','Básico','Scripts para leer datos de sensores.',NULL),
  ('diego.morales@demo.test','Resolución de problemas','Intermedio','Depuré fallas de comunicación del prototipo en competencia.',NULL),
  ('camila.reyes@demo.test','Diseño UI/UX','Avanzado','Prototipos en Figma y pruebas con usuarios.','Portafolio behance.net/camilareyes'),
  ('camila.reyes@demo.test','HTML y CSS','Avanzado','Implementé las vistas del sistema de biblioteca.',NULL),
  ('camila.reyes@demo.test','JavaScript','Intermedio','Interacciones y validaciones en el navegador.',NULL),
  ('camila.reyes@demo.test','Liderazgo','Intermedio','Jefa de equipo en el proyecto de biblioteca.',NULL),
  ('emiliano.vazquez@demo.test','PHP y Laravel','Básico','Curso en línea y una API de prueba.',NULL),
  ('emiliano.vazquez@demo.test','SQL y bases de datos','Intermedio','Modelos de datos en clase.',NULL),
  ('ximena.flores@demo.test','Python','Avanzado','Análisis de ventas con pandas y matplotlib.','Cuaderno publicado en GitHub'),
  ('ximena.flores@demo.test','Análisis de datos','Intermedio','Proyecto integrador de pronóstico de ventas.',NULL),
  ('ximena.flores@demo.test','Resolución de problemas','Avanzado','Primer lugar en el maratón interno de programación.','Constancia del maratón'),
  ('sebastian.cortes@demo.test','Redes e IoT','Avanzado','Administración de la red del laboratorio de cómputo.','Carta del jefe de laboratorio'),
  ('sebastian.cortes@demo.test','Trabajo en equipo','Intermedio','Soporte técnico en turnos compartidos.',NULL),
  ('renata.aguirre@demo.test','JavaScript','Avanzado','Tienda en línea con carrito y pagos de prueba.','tienda-familiar.demo.test'),
  ('renata.aguirre@demo.test','HTML y CSS','Avanzado','Diseño adaptable para teléfonos.',NULL),
  ('renata.aguirre@demo.test','PHP y Laravel','Intermedio','Panel de administración de la tienda.',NULL),
  ('renata.aguirre@demo.test','Comunicación efectiva','Intermedio','Atención a clientes del negocio familiar.',NULL),
  ('mateo.juarez@demo.test','Git y control de versiones','Básico',NULL,NULL)
  ) v(c,h,n,d,e);

-- Proyectos -------------------------------------------------------------------------------------
INSERT INTO banco.proyecto(empresa_id,autor_usuario_id,titulo,descripcion,problematica,objetivos,justificacion,alcance,
  requisitos_academicos,duracion_estimada,modalidad,fecha_inicio_estimada,fecha_fin_estimada,recursos,cupo_maximo_alumnos)
SELECT e.id,pg_temp.u(v.autor),v.titulo,v.descripcion,v.problematica,v.objetivos,v.justificacion,v.alcance,v.requisitos,v.duracion,v.modalidad,
  v.inicio::date,v.fin::date,v.recursos,v.cupo
FROM (VALUES
  ('Panadería La Espiga','jorge.medina@demo.test','Sistema de pedidos en línea para La Espiga',
   'Plataforma web para que los clientes hagan pedidos de pan y pasteles por adelantado y los recojan en sucursal.',
   'Los pedidos llegan por teléfono y WhatsApp; se pierden encargos y no hay control de horarios de entrega.',
   'Catálogo de productos, carrito, apartado por horario de recolección y panel para el personal de mostrador.',
   'Reducir errores en pedidos especiales y atender a más clientes en temporada alta.',
   'Versión web adaptable a teléfonos; sin pagos en línea en esta etapa.',
   'Programación web y bases de datos aprobadas.','16 semanas','Híbrida','2026-08-17','2026-12-11',
   'Equipo de cómputo en sucursal centro y acceso al catálogo de productos.',2),
  ('Panadería La Espiga','jorge.medina@demo.test','Control de inventario de insumos',
   'Sistema para registrar entradas y salidas de harina, azúcar y otros insumos con alertas de existencias mínimas.',
   'El inventario se lleva en libretas y se descubren faltantes cuando ya no hay tiempo de comprar.',
   'Registro de movimientos, alertas de mínimo, reporte semanal de consumo y proveedores.',
   'Evitar paros de producción y compras de emergencia más caras.',
   'Módulo web para el almacén de la planta; lectura de códigos de barras opcional.',
   'Bases de datos y Programación web.','14 semanas','Presencial','2027-01-25','2027-05-07',
   'Laptop asignada al almacén y lector de códigos de barras.',2),
  ('Clínica Veterinaria Huellitas','daniela.ortiz@demo.test','Expediente clínico digital de mascotas',
   'Expediente electrónico con historial de consultas, vacunas y tratamientos de cada mascota.',
   'Los expedientes en papel se traspapelan y el veterinario no ve el historial cuando atiende urgencias.',
   'Alta de propietarios y mascotas, notas de consulta, carnet de vacunación imprimible y búsqueda rápida.',
   'Mejorar la atención y cumplir con el registro de tratamientos controlados.',
   'Aplicación web interna para dos consultorios.',
   'Bases de datos; deseable experiencia en diseño de interfaces.','16 semanas','Presencial','2027-01-25','2027-05-21',
   'Computadoras de recepción y consultorio.',2),
  ('Clínica Veterinaria Huellitas','daniela.ortiz@demo.test','Recordatorios de vacunación por mensaje',
   'Servicio que avisa a los propietarios cuándo toca la siguiente vacuna o desparasitación.',
   'Muchos propietarios olvidan las fechas y las mascotas quedan sin protección.',
   'Calendario de aplicaciones y envío programado de recordatorios.',
   'Aumentar el regreso de clientes y la salud preventiva.',
   'Recordatorios por correo electrónico y mensaje de texto.',
   'Programación web.','10 semanas','Remota','2027-02-08','2027-04-16',
   'Cuenta de prueba de un servicio de mensajería.',1),
  ('Transportes del Golfo','ricardo.salas@demo.test','Rastreo de unidades con GPS',
   'Prototipo de rastreo en tiempo real de camiones con dispositivos GPS de bajo costo.',
   'La empresa no sabe dónde están sus unidades y responde tarde a clientes y emergencias.',
   'Dispositivo de rastreo, servidor de recepción y mapa web con la ubicación de cada unidad.',
   'Mejorar tiempos de respuesta y seguridad de los choferes.',
   'Prototipo instalado en tres unidades de reparto local.',
   'Redes e IoT; Programación.','12 semanas','Presencial','2026-02-09','2026-05-08',
   'Tres módulos GPS y acceso al patio de maniobras.',2),
  ('Transportes del Golfo','ricardo.salas@demo.test','Tablero de indicadores de entregas',
   'Tablero con entregas a tiempo, retrasos y kilómetros recorridos por ruta.',
   'Los reportes se arman a mano en hojas de cálculo cada fin de mes.',
   'Indicadores diarios por ruta y chofer, con exportación para la gerencia.',
   'Tomar decisiones con datos y detectar rutas problemáticas.',
   'Tablero web conectado a la base de datos de despachos.',
   'Análisis de datos y SQL.','10 semanas','Remota','2027-02-01','2027-04-09',
   'Copia anonimizada de la base de despachos.',2),
  ('Transportes del Golfo','ricardo.salas@demo.test','App de bitácora para choferes',
   'Aplicación para que los choferes registren cargas de combustible y casetas desde el teléfono.',
   'Los comprobantes se pierden y la conciliación de gastos tarda semanas.',
   'Captura de gastos con foto del comprobante y envío al área administrativa.',
   'Agilizar la comprobación de gastos de viaje.',
   'App móvil para Android.','Desarrollo móvil.','12 semanas','Remota','2027-02-01','2027-04-30',
   'Teléfonos de la empresa para pruebas.',2),
  ('Cooperativa Café Altura','lucia.hernandez@demo.test','Trazabilidad del café de la parcela a la taza',
   'Registro de cada lote de café desde la parcela, el beneficio y el tostado, con código QR para el consumidor.',
   'Los compradores de café de especialidad piden saber el origen exacto y la cooperativa no puede demostrarlo.',
   'Registro de lotes, etapas de proceso y página pública por código QR.',
   'Acceder a mercados que pagan mejor por café con origen comprobado.',
   'Aplicación web para el beneficio y página pública de consulta.',
   'Bases de datos y Programación web.','16 semanas','Híbrida','2027-01-18','2027-05-14',
   'Visitas al beneficio en Coatepec con transporte de la cooperativa.',2),
  ('Cooperativa Café Altura','lucia.hernandez@demo.test','Tienda en línea de café de especialidad',
   'Tienda en línea para vender café tostado directamente a consumidores.',
   'La cooperativa depende de intermediarios para vender su café tostado.',
   'Catálogo, carrito y seguimiento de envíos.',
   'Vender directamente y mejorar el ingreso de los socios.',
   'Tienda web con pagos de prueba.','Programación web.','12 semanas','Remota',NULL,NULL,NULL,2)
) v(empresa,autor,titulo,descripcion,problematica,objetivos,justificacion,alcance,requisitos,duracion,modalidad,inicio,fin,recursos,cupo)
JOIN banco.empresa e ON e.razon_social=v.empresa;

INSERT INTO banco.proyecto_habilidad(proyecto_id,habilidad_id,nivel_minimo,obligatoria)
  SELECT pg_temp.p(t),pg_temp.h(h),n,o FROM (VALUES
  ('Sistema de pedidos en línea para La Espiga','PHP y Laravel','Intermedio',true),
  ('Sistema de pedidos en línea para La Espiga','HTML y CSS','Intermedio',true),
  ('Sistema de pedidos en línea para La Espiga','Trabajo en equipo',NULL,false),
  ('Control de inventario de insumos','SQL y bases de datos','Intermedio',true),
  ('Control de inventario de insumos','PHP y Laravel','Básico',false),
  ('Control de inventario de insumos','Comunicación efectiva',NULL,false),
  ('Expediente clínico digital de mascotas','SQL y bases de datos','Intermedio',true),
  ('Expediente clínico digital de mascotas','Diseño UI/UX','Básico',false),
  ('Expediente clínico digital de mascotas','HTML y CSS',NULL,false),
  ('Recordatorios de vacunación por mensaje','JavaScript','Básico',true),
  ('Rastreo de unidades con GPS','Redes e IoT','Intermedio',true),
  ('Rastreo de unidades con GPS','Python','Básico',false),
  ('Tablero de indicadores de entregas','Análisis de datos','Intermedio',true),
  ('Tablero de indicadores de entregas','SQL y bases de datos','Básico',true),
  ('App de bitácora para choferes','Desarrollo móvil con Flutter','Intermedio',true),
  ('Trazabilidad del café de la parcela a la taza','SQL y bases de datos','Intermedio',true),
  ('Trazabilidad del café de la parcela a la taza','JavaScript','Básico',false),
  ('Trazabilidad del café de la parcela a la taza','Resolución de problemas',NULL,false),
  ('Tienda en línea de café de especialidad','JavaScript','Intermedio',true),
  ('Tienda en línea de café de especialidad','HTML y CSS',NULL,false)) v(t,h,n,o);

-- Flujo de publicación, participación y ciclo -----------------------------------------------------
DO $flujo$
DECLARE
  adm bigint := pg_temp.u('coordinacion@demo.test');
  espiga bigint := pg_temp.u('jorge.medina@demo.test');
  huellitas bigint := pg_temp.u('daniela.ortiz@demo.test');
  golfo bigint := pg_temp.u('ricardo.salas@demo.test');
  altura bigint := pg_temp.u('lucia.hernandez@demo.test');
  p_pedidos bigint := pg_temp.p('Sistema de pedidos en línea para La Espiga');
  p_inventario bigint := pg_temp.p('Control de inventario de insumos');
  p_expediente bigint := pg_temp.p('Expediente clínico digital de mascotas');
  p_vacunas bigint := pg_temp.p('Recordatorios de vacunación por mensaje');
  p_gps bigint := pg_temp.p('Rastreo de unidades con GPS');
  p_tablero bigint := pg_temp.p('Tablero de indicadores de entregas');
  p_bitacora bigint := pg_temp.p('App de bitácora para choferes');
  p_cafe bigint := pg_temp.p('Trazabilidad del café de la parcela a la taza');
  c bigint; s bigint;
BEGIN
  -- Publicaciones
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_pedidos,espiga),adm,'aprobada','Propuesta clara, alcance adecuado para residencia.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_inventario,espiga),adm,'aprobada','Aprobado. Buen proyecto para alumnos de bases de datos.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_expediente,huellitas),adm,'aprobada','Aprobado; cuidar la confidencialidad de los datos de propietarios.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_gps,golfo),adm,'aprobada','Aprobado como prototipo.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_cafe,altura),adm,'aprobada','Excelente vinculación con el sector productivo.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_tablero,golfo),adm,'en_correccion',
    'Indiquen qué indicadores necesita la gerencia y de dónde salen los datos de kilómetros.');
  PERFORM banco.resolver_publicacion(banco.enviar_proyecto(p_bitacora,golfo),adm,'rechazada',
    'Requiere manejo de comprobantes fiscales fuera del alcance académico. Pueden replantearlo como captura sin facturación.');
  PERFORM banco.enviar_proyecto(p_vacunas,huellitas); -- queda en revisión para la coordinación

  -- Rastreo GPS: proyecto completo y finalizado
  FOR c IN SELECT banco.presentar_candidatura(p_gps,pg_temp.u(x)) FROM unnest(ARRAY['diego.morales@demo.test','sebastian.cortes@demo.test']) x LOOP
    PERFORM banco.evaluar_candidatura(c,golfo,pg_temp.rubrica(2,2,2,'Domina sensores y redes.','Muy buena actitud en la entrevista.','Formación acorde al proyecto.'),'Recomendado para el prototipo.',true);
    PERFORM banco.preseleccionar_candidatura(c,golfo);
    PERFORM banco.resolver_candidatura(c,adm,'aprobada','Cumple el perfil y hay cupo.');
  END LOOP;
  s := banco.solicitar_direccion(p_gps,pg_temp.u('fernando.rios@demo.test'),
    'Asesoro proyectos de rastreo y sensores desde 2018.','El proyecto coincide con mi línea de Internet de las cosas.');
  PERFORM banco.resolver_direccion(s,adm,'aprobada','Especialidad adecuada.');
  PERFORM banco.iniciar_proyecto(p_gps,adm);
  PERFORM banco.finalizar_proyecto(p_gps,adm,'Prototipo entregado y probado en tres unidades.');

  -- Pedidos en línea: en curso con dos alumnos y directora
  FOR c IN SELECT banco.presentar_candidatura(p_pedidos,pg_temp.u(x)) FROM unnest(ARRAY['ana.torres@demo.test','renata.aguirre@demo.test']) x LOOP
    PERFORM banco.evaluar_candidatura(c,espiga,pg_temp.rubrica(2,2,2,'Experiencia comprobable en Laravel y maquetación.','Se expresa con claridad y propone ideas.','Avance académico suficiente.'),'Buen perfil para el sistema de pedidos.',true);
    PERFORM banco.preseleccionar_candidatura(c,espiga);
    PERFORM banco.resolver_candidatura(c,adm,'aprobada','Aprobada.');
  END LOOP;
  s := banco.solicitar_direccion(p_pedidos,pg_temp.u('patricia.lara@demo.test'),
    '10 años en desarrollo web y comercio electrónico.','Puedo guiar al equipo en arquitectura web y experiencia de usuario.');
  PERFORM banco.resolver_direccion(s,adm,'aprobada','Aprobada.');
  PERFORM banco.iniciar_proyecto(p_pedidos,adm);

  -- Inventario: candidaturas en todos los pasos y una dirección pendiente
  c := banco.presentar_candidatura(p_inventario,pg_temp.u('valeria.gomez@demo.test'));
  PERFORM banco.evaluar_candidatura(c,espiga,pg_temp.rubrica(2,2,1,'Maneja SQL y reportes.','Comunicación muy clara.','Le falta Programación web, que cursa este semestre.'),'Recomendada.',true);
  PERFORM banco.preseleccionar_candidatura(c,espiga); -- espera resolución de la coordinación
  c := banco.presentar_candidatura(p_inventario,pg_temp.u('emiliano.vazquez@demo.test'));
  PERFORM banco.evaluar_candidatura(c,espiga,pg_temp.rubrica(1,1,1,'Conocimientos básicos de Laravel.','Respuestas breves en la entrevista.','Promedio regular.'),'Podría reforzar el equipo como apoyo.',false);
  PERFORM banco.presentar_candidatura(p_inventario,pg_temp.u('ximena.flores@demo.test')); -- por evaluar
  PERFORM banco.solicitar_direccion(p_inventario,pg_temp.u('alberto.cruz@demo.test'),
    '15 años como docente de Bases de datos.','El inventario es un caso ideal de modelado relacional.');

  -- Expediente clínico: dos candidaturas por evaluar
  PERFORM banco.presentar_candidatura(p_expediente,pg_temp.u('camila.reyes@demo.test'));
  PERFORM banco.presentar_candidatura(p_expediente,pg_temp.u('ana.torres@demo.test'));

  -- Café: una alumna aprobada y director asignado, en espera de iniciar; una rechazada
  c := banco.presentar_candidatura(p_cafe,pg_temp.u('ximena.flores@demo.test'));
  PERFORM banco.evaluar_candidatura(c,altura,pg_temp.rubrica(2,1,2,'Sólida en análisis de datos.','Algo reservada, pero puntual y ordenada.','Muy buen promedio.'),'La recomendamos.',true);
  PERFORM banco.preseleccionar_candidatura(c,altura);
  PERFORM banco.resolver_candidatura(c,adm,'aprobada','Aprobada.');
  c := banco.presentar_candidatura(p_cafe,pg_temp.u('luis.ramirez@demo.test'));
  PERFORM banco.evaluar_candidatura(c,altura,pg_temp.rubrica(1,2,1,'Su fuerte es móvil; el proyecto es web y bases de datos.','Muy buena disposición.','Formación suficiente.'),'Mejor perfil para un proyecto móvil.',false);
  PERFORM banco.resolver_candidatura(c,adm,'rechazada','El perfil no coincide con las habilidades obligatorias; se le invita a postular a proyectos móviles.');
  s := banco.solicitar_direccion(p_cafe,pg_temp.u('alberto.cruz@demo.test'),
    'Dirigí proyectos de trazabilidad con productores de la región.','Combina bases de datos con impacto social.');
  PERFORM banco.resolver_direccion(s,adm,'aprobada','Aprobada.');
  s := banco.solicitar_direccion(p_expediente,pg_temp.u('sofia.mendoza@demo.test'),
    'Coordino la academia de programación.','Puedo apoyar en metodología y diseño de interfaces.');
  PERFORM banco.resolver_direccion(s,adm,'rechazada','La empresa pidió un director con experiencia en sistemas de salud; se buscará otro perfil.');
END $flujo$;

SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

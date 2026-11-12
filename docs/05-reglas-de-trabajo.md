# Reglas de trabajo del banco de proyectos académicos

Estas reglas organizan el análisis, desarrollo y validación del proyecto. Adaptan el método documental revisado de Blue Marlin a las fases F0 a F6 del banco académico, con registros pequeños y fuentes enlazadas. El usuario autorizó su adaptación el 21 de octubre de 2026.

La entrada para el agente es [AGENTS.md](../../AGENTS.md). El [README](../README.md) orienta la lectura; el [seguimiento](06-seguimiento.md) conserva el avance y el [registro de decisiones](07-registro-de-decisiones.md) conserva acuerdos y preguntas abiertas.

## Una ubicación principal por tema

| Información | Fuente principal |
| --- | --- |
| Requisitos originales | [Proyecto.pdf](../Proyecto.pdf) |
| Alcance, reglas, actores, permisos y flujos propuestos | [01 Alcance y requisitos](01-alcance-y-requisitos.md) |
| Arquitectura, integridad y contratos técnicos | [02 Arquitectura y datos](02-arquitectura-y-datos.md) |
| Entidades, relaciones, claves propuestas y cardinalidades | [08 Modelo entidad-relación](08-modelo-entidad-relacion.md) |
| Fases, dependencias de entrega, trazabilidad RF y criterios de aceptación | [03 Plan y validación](03-plan-y-validacion.md) |
| Fundamento técnico de la elección del motor | [04 Elección de PostgreSQL](04-eleccion-de-postgresql.md) |
| Método de trabajo y criterios de registro | Este documento |
| Estado actual, bloques, comprobaciones, problemas y siguiente acción | [06 Seguimiento](06-seguimiento.md) |
| Estado, resolución, motivo, fuente e impacto de cada decisión | [07 Registro de decisiones](07-registro-de-decisiones.md) |
| Dirección visual, componentes y reglas de presentación web | [Guía visual](../web/DESIGN.md) |
| Entregas académicas, PDF y fuentes por tarea | [Tareas del proyecto](../tareas/README.md) |

El README enlaza estas fuentes. El plan describe qué se hará; el seguimiento indica qué se ha hecho. Las explicaciones pueden citar un acuerdo, pero su resolución vigente se consulta en el registro de decisiones.

## Estados que no deben confundirse

| Dimensión | Estados | Dónde se registra |
| --- | --- | --- |
| Definición de una decisión | propuesta, por aclarar, confirmada, sustituida | Registro de decisiones |
| Avance de una tarea | pendiente, en curso, bloqueada, completada | Seguimiento |
| Implementación de una función | pendiente, parcial, implementada | Bloque funcional en seguimiento, con RF/RN afectados |
| Verificación | sin verificar, documental, local, QA | Resultado del bloque, con entorno y alcance |

Un requisito inequívoco del PDF es una fuente funcional; sus ambigüedades requieren aclaración. Una decisión se confirma con fecha y fuente del acuerdo. La documentación de una arquitectura no acredita implementación. Una prueba local solo acredita los casos y el entorno indicados; una publicación se registra aparte cuando ocurra.

## Inicio y ejecución de cada bloque

1. Leer AGENTS.md, README, estas reglas y el seguimiento actual; después, las fuentes afectadas.
2. Delimitar objetivo, entregable y requisitos relacionados usando los RF, RN, RNF, CU y CA existentes.
3. Revisar las decisiones y dependencias aplicables. Registrar una duda antes de convertirla en política; no solicitar otra vez información ya acordada.
4. Identificar archivos reales y trabajo previo. Preservar cambios ajenos y comprobar Git si existe, sin asumir commits ni remoto.
5. Seleccionar y leer las habilidades pertinentes antes de implementar, según la matriz siguiente. Anunciar brevemente cuáles se aplicarán y para qué.
6. Realizar el trabajo autorizado y su comprobación pertinente. Una solicitud de análisis produce conclusiones; no inicia por sí misma cambios de arquitectura o código.
7. Mantener el avance del bloque, las habilidades aplicadas y los límites de lo comprobado en el seguimiento.

Una tarea pequeña puede usar una sola fila y un resultado breve. Para un bloque sustancial, indicar objetivo, alcance, dependencias, entregable y cierre. Se amplía el registro existente antes de crear otro documento para el mismo asunto.

## Selección de habilidades antes de implementar

Por petición del usuario del 10 de noviembre de 2026, la selección de habilidades forma parte del inicio de cada bloque. Revisar el catálogo disponible y elegir según el problema real, los archivos afectados y la comprobación necesaria. La matriz reúne las habilidades técnicas ya empleadas y las de diseño incorporadas para WEB-03; también señala otras útiles para los siguientes módulos. No exige ejecutar todas en cada tarea.

| Trabajo del bloque | Habilidades que conviene considerar | Aplicación en este proyecto |
| --- | --- | --- |
| Cambio que cruza módulos, modifica acceso, datos o interfaces | `ecc:change-impact` | Identificar llamadas, dependencias, pruebas y recuperación afectadas antes de editar; contrastar el alcance al terminar |
| Consultas, esquema, índices o migraciones PostgreSQL | `ecc:postgres-patterns`, `ecc:database-migrations` | Mantener SQL versionado como fuente del esquema, migraciones aplicadas inmutables y comprobaciones con PostgreSQL real |
| Funcionalidad Laravel y sus pruebas | `ecc:laravel-patterns`, `ecc:laravel-tdd` | Repartir responsabilidades entre petición, controlador y servicio; probar comportamientos y límites relevantes |
| Autenticación, permisos, formularios o datos privados | `ecc:laravel-security` | Revisar autorización en servidor, CSRF, escape de salida, sesión y exposición de datos, aunque el cambio empiece en una vista |
| Recorrido entre pantallas o navegación de los módulos | `journey`, `organize` | Definir pasos, recuperación, nombres y ubicación de las opciones según la tarea del rol |
| Distribución de una pantalla | `wireframe` | Resolver jerarquía, campos, acciones y adaptación a móvil antes de aplicar el acabado visual |
| Apariencia y componentes web | `ecc:frontend-design-direction`, `ecc:design-system`, `ecc:make-interfaces-feel-better` | Seguir la guía visual, reutilizar variables y componentes, y cuidar tipografía, espaciado y estados de interacción |
| Interfaz nueva o modificada | `ecc:accessibility` | Comprobar semántica, etiquetas, errores, contraste, foco, teclado y tamaños de interacción |
| Revisión de facilidad de uso | `evaluate` | Recorrer tareas concretas y priorizar hallazgos por impacto; distinguir observaciones de supuestos |
| Comprobación del bloque Laravel o de su interfaz | `ecc:laravel-verification`, `ecc:browser-qa` | Elegir comprobaciones proporcionales y revisar páginas renderizadas con datos ficticios; declarar lo no ejecutado |
| APIs o consumidores independientes, cuando se aborde esa etapa | `ecc:contract-first` | Acordar una única definición verificable del intercambio antes de implementar ambos lados; no añadirla al MVC por rutina |

Leer el `SKILL.md` de cada habilidad seleccionada desde la ubicación del catálogo vigente; la lista de nombres no sustituye su lectura ni acredita su uso. Una habilidad mencionada expresamente por el usuario se revisa antes de aplicarla. Las nuevas habilidades se evalúan por su utilidad y compatibilidad, sin instalar dependencias ni ampliar el alcance por el mero hecho de que existan.

Las instrucciones del usuario, los acuerdos y la arquitectura del proyecto prevalecen sobre ejemplos genéricos: una receta que use SQLite, migraciones Laravel, React o Tailwind no cambia nuestra base PostgreSQL ni Laravel con Blade y Bootstrap. Adaptar la comprobación al esquema SQL existente, sin crear estructuras paralelas. Tampoco generar expedientes, hooks o documentos adicionales si los registros actuales bastan.

En el seguimiento del bloque registrar brevemente las habilidades aplicadas, su propósito y el enlace a la evidencia producida, junto con los límites. Las habilidades consideradas para otro momento se identifican como recomendaciones. Un chequeo automático no demuestra por sí solo accesibilidad completa, ausencia de defectos o preparación para producción; una primera captura tampoco acredita regresión visual contra una referencia anterior.

## Dependencias y decisiones

Las fases F0 a F6 indican el orden general, con dependencias por bloque. Pueden adelantarse partes independientes del diseño, prototipos o preparación técnica sin declarar cerrada una fase anterior. No se exige terminar todo el backend antes de trabajar en cualquier interfaz.

Conservar D-01 a D-12. D-13 registra la elección de PostgreSQL y D-14 la arquitectura y base técnica elegidas, con su historia y versiones concretadas. La libertad tecnológica ya concedida permite resolver detalles técnicos dentro del alcance; no crea una aprobación adicional por cada dependencia o tipo de dato.

Si una respuesta cambia un requisito del PDF, conservar el original, registrar la variante acordada y actualizar las fuentes y pruebas afectadas. Si sustituye una decisión previa, conservar su historia y señalar la nueva resolución. Cambiar un criterio reabre solo el alcance que depende de él.

## Comprobaciones según el cambio

| Cambio | Comprobación pertinente |
| --- | --- |
| Documentación | Leer el resultado, comprobar enlaces y anclas, consistencia de estados y conservación de identificadores |
| Regla de negocio | Casos válidos, límites, rechazos y transiciones relacionados con el requisito |
| Acceso y privacidad | Peticiones al servidor por rol y pertenencia del registro, incluidas negativas |
| Persistencia y asignaciones | Integración con PostgreSQL: restricciones, efectos conjuntos, rollback e idempotencia |
| Cupos y operaciones simultáneas | Conexiones independientes y esperas reales contra PostgreSQL |
| Interfaz | Recorrido del rol, errores, teclado, tamaño móvil y coherencia con la respuesta del servidor |
| Entrega | Instalación reproducible, comprobaciones integrales, respaldo y restauración en el entorno declarado |

Ejecutar solo comandos disponibles y adecuados al bloque. Registrar las comprobaciones realizadas separadas de las previstas. No escribir tests que repitan el código ni repetir suites ajenas por una edición documental. Ampliar la verificación cuando un cambio, fallo o riesgo lo justifique.

La evidencia breve incluye fecha, entregable o archivos, requisitos cubiertos, método o comando, entorno, resultado y límites. Los datos de prueba serán ficticios o controlados. Conservar resultados útiles para reproducir el caso y evitar credenciales o datos personales en bitácoras; los auxiliares temporales no son evidencia oficial.

## Problemas y revisiones

Una ambigüedad de política pertenece al registro de decisiones. Un comportamiento que contradice una regla confirmada es un problema: registrar ID local, esperado y fuente, observado, impacto, reproducción, estado, cambio y evidencia posterior. Mantener una sola ficha o entrada por problema.

Al inicio, [06 Seguimiento](06-seguimiento.md) contiene los problemas y las revisiones relevantes. Separarlos en archivos únicamente cuando el volumen lo justifique. Una revisión conserva alcance, fuentes, resultado y límites; terminarla no significa corregir todos sus hallazgos. No copiar problemas ni IDs del proyecto de referencia.

## Cierre de un bloque

- Entregable revisable enlazado y coherente con sus requisitos y decisiones.
- Comprobaciones pertinentes realizadas, con su resultado y límites registrados.
- Fallos y dependencias conservados, con efecto sobre el trabajo siguiente.
- Fuentes afectadas actualizadas, sin repetir estados o historiales en todos los índices.
- Estado y siguiente acción actualizados en el seguimiento.

Una falla crítica del alcance impide marcarlo como completado; puede cerrarse un bloque parcial bien delimitado sin declarar terminada la función o fase completa. Registrar bloques sustanciales, no cada edición menor ni porcentajes sin una base verificable.

## Versiones y crecimiento de la documentación

Las entregas académicas solicitadas por el usuario se guardan en carpetas numeradas dentro de `proyecto/tareas/`, con PDF, diagramas y fuentes editables cuando correspondan. El índice de tareas enlaza cada entrega; el modelo y las decisiones vigentes siguen en sus documentos principales. Cada PDF se revisa renderizado antes de entregarlo. Una tarea académica completada no acredita una aplicación implementada.

No crear expedientes de versiones de software por documentación preparatoria. Al existir una entrega de aplicación, registrar cambios reales, evidencia y notas de uso; distinguir construcción local, instalación y despliegue. Crear carpetas de evidencia o versiones cuando tengan contenido real.

AGENTS.md conserva instrucciones estables. El seguimiento conserva un resumen actual breve y un historial de hitos fechado. No trasladar a este proyecto el árbol Flutter, Firebase, comandos, etapas de migración o permisos del proyecto de referencia.

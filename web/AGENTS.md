# Trabajo en la aplicación web

Leer primero [la guía del proyecto](../../AGENTS.md), [el README](../README.md), [las reglas](../docs/05-reglas-de-trabajo.md) y el seguimiento vigente. Estas instrucciones complementan las de la raíz.

- Antes de implementar, seleccionar y leer las habilidades pertinentes siguiendo la matriz de las reglas. Anunciar cuáles se aplican y registrar sus resultados al cerrar el bloque. No instalar herramientas solo porque una plantilla genérica las mencione.
- Conservar Laravel, Blade y Bootstrap. La [guía visual](DESIGN.md) define composición, componentes, estados y comprobaciones para las nuevas pantallas.
- Usar `dev.ps1` para PHP, Composer y npm; detecta las herramientas locales o las del sistema. Revisar el entorno antes de instalar o sustituir dependencias. Los archivos de bloqueo fijan versiones.
- Mantener autorización y reglas de negocio en el servidor. Las vistas no consultan tablas privadas ni convierten ocultar una acción en un permiso.
- Las migraciones SQL de `../database/` son la única fuente del esquema. No ejecutar migraciones Laravel, `RefreshDatabase`, `migrate:fresh` o `db:wipe`.
- Mantener credenciales, `.env`, primer acceso y datos reales fuera de código, capturas y evidencia compartible. Usar bases temporales propias y cuentas ficticias para las pruebas.
- Verificar las pantallas modificadas en escritorio, móvil y con teclado; ejecutar las pruebas pertinentes de la [guía web](README.md). Conservar límites y siguiente acción en el seguimiento.

# Vinculación · Identidad del banco de proyectos académicos

Propuesta 1 elegida por el usuario el 13 de noviembre de 2026. El nombre vigente es **Banco de proyectos académicos**. «Vinculación» identifica el concepto del símbolo; no sustituye el nombre del sistema.

Los dos eslabones representan la relación entre la escuela y las empresas mediante proyectos. Se reconstruyeron con piezas congruentes, radios regulares y separaciones transparentes que conservan el entrelazado en una tinta. La retícula del símbolo es de 80 × 80 unidades: radio exterior 13, interior 4 y grosor principal 12. Las letras proceden de Inter, la tipografía ya usada por la aplicación, y están convertidas a trazados.

## Archivos y versiones

Los SVG finales están en [public/brand](../../public/brand/). Todos son vectores con fondo transparente y sin fuentes, imágenes incrustadas, scripts ni recursos externos. El favicon añade una placa blanca para conservar su lectura en las pestañas claras y oscuras.

| Composición | Uso |
| --- | --- |
| `logo-horizontal-*.svg` | Nombre completo en dos líneas, comunicaciones y presentaciones |
| `logo-vertical-*.svg` | Composición centrada cuando hay más altura que anchura |
| `logo-navegacion-*.svg` | Composición compacta de la interfaz, con el descriptor «académicos» de menor tamaño |
| `simbolo-*.svg` | Espacios pequeños y contextos donde ya se identifica el sistema |
| `favicon.svg`, `favicon.ico`, `apple-touch-icon.png` | Pestaña del navegador y acceso guardado en dispositivos |

Cada composición tiene cuatro variantes: `color` (azul `#2f5bd3` y marino `#172036`), `oscuro` (azul claro `#8fa8ff` y blanco), `monocromo` (marino) y `blanco` (negativo). La variante blanca debe colocarse sobre una superficie oscura uniforme; su archivo es transparente.

La aplicación carga la composición de navegación en el encabezado público y la barra lateral. Por debajo de 576 px, el encabezado y la barra superior utilizan el símbolo; el menú lateral conserva el nombre completo. El componente mantiene un único nombre accesible y un enlace con área de interacción de al menos 44 px. El tema elegido cambia la variante sin depender de una nueva descarga de fuentes.

## Reproducción

- Conservar la proporción y los huecos entre las piezas. Reservar al menos 8 unidades de la retícula alrededor del contorno visible.
- Usar preferentemente el símbolo desde 24 px; el favicon de 16 px se entrega por separado. En impresión, comprobar una prueba física antes de producir tiradas.
- Usar la composición horizontal desde 240 px, la vertical desde 180 px y la de navegación desde 190 px. Para tamaños inferiores, elegir el símbolo y conservar el nombre como alternativa accesible.
- Mantener fondos uniformes con suficiente separación visual. Evitar deformaciones, sombras, degradados, contornos añadidos o cambios independientes de proporción y color.

La lámina [presentacion.pdf](presentacion.pdf) y los PDF horizontales de color y una tinta también son vectoriales. [banco-proyectos-identidad.zip](banco-proyectos-identidad.zip) reúne los archivos para entrega.

## Fuentes editables

[reconstruir.py](reconstruir.py) conserva la geometría, las composiciones y el texto de origen. Regenera los SVG a partir de la fuente Inter fijada en `package-lock.json`; no realiza un calco del PNG. Requiere Python 3.12, FontTools 4.68.0, Brotli 1.2.1, Pillow e Inkscape 1.4 para las exportaciones. Estas herramientas son auxiliares de diseño, no dependencias de ejecución de Laravel. En este equipo están disponibles en `proyecto/.local/tools/marca-python` y en la instalación existente de Inkscape.

Desde `proyecto/web`, ejecutar `py -3.12 design/marca-final/reconstruir.py`. La [licencia de Inter](LICENCIA-Inter.txt) se conserva junto con la entrega. Los SVG pueden editarse directamente en un editor vectorial; para cambiar el nombre sin reconstruir letras manualmente, modificar el texto en el generador y volver a exportar.

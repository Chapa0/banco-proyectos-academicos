"""Reconstrucción vectorial de Vinculación (MARCA-03).

Usa la fuente Inter ya fijada por npm. No modifica la propuesta ráster.
Requiere fonttools 4.68.0, brotli 1.2.1 y Pillow para exportar el ICO.
"""
from __future__ import annotations

from html import escape
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

WEB = Path(__file__).resolve().parents[2]
PROYECTO = WEB.parent
sys.path.insert(0, str(PROYECTO / ".local/tools/marca-python"))

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

SALIDA = WEB / "public/brand"
ENTREGA = Path(__file__).resolve().parent
EVIDENCIA = WEB / "evidencia/marca03"
FUENTE = WEB / "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2"

# Dos piezas congruentes. El corte de 4 u junto a cada cruce es transparente.
# La intersección (51,44) pertenece exactamente al arco r=13, centro (39,39).
ESLABON = ("M52 24V17A13 13 0 0 0 39 4H17A13 13 0 0 0 4 17V39"
           "A13 13 0 0 0 17 52H39A13 13 0 0 0 51 44H40V36"
           "A4 4 0 0 1 36 40H20A4 4 0 0 1 16 36V20"
           "A4 4 0 0 1 20 16H36A4 4 0 0 1 40 20V24Z")

PALETAS = {
    "color": ("#2f5bd3", "#172036", "#172036"),
    "oscuro": ("#8fa8ff", "#ffffff", "#ffffff"),
    "monocromo": ("#172036", "#172036", "#172036"),
    "blanco": ("#ffffff", "#ffffff", "#ffffff"),
}

def simbolo(paleta: str) -> str:
    primero, segundo, _ = PALETAS[paleta]
    return (f'<path fill="{primero}" d="{ESLABON}"/>'
            f'<path fill="{segundo}" transform="rotate(180 40 40)" d="{ESLABON}"/>')

def fuente_estatica(peso: float):
    font = TTFont(FUENTE)
    return instantiateVariableFont(font, {"wght": peso}, inplace=True)

FUENTES = {700: fuente_estatica(700), 600: fuente_estatica(600)}

def texto_trazado(texto: str, tamano: float, x: float, base: float, peso: int = 700):
    font = FUENTES[peso]
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    escala = tamano / font["head"].unitsPerEm
    avance = 0.0
    pen = SVGPathPen(glyphs, ntos=lambda n: f"{n:.3f}".rstrip("0").rstrip("."))
    # Tracking óptico constante; la composición queda convertida a contornos.
    tracking = -0.012 * tamano
    for char in texto:
        nombre = cmap[ord(char)]
        glyphs[nombre].draw(TransformPen(pen, (escala, 0, 0, -escala, x + avance, base)))
        avance += glyphs[nombre].width * escala + tracking
    return pen.getCommands(), avance - tracking

def svg(ancho: float, alto: float, contenido: str, titulo: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{ancho:g}" height="{alto:g}" '
            f'viewBox="0 0 {ancho:g} {alto:g}" role="img" aria-labelledby="titulo">'
            f'<title id="titulo">{escape(titulo)}</title>{contenido}</svg>\n')

def guardar(nombre: str, contenido: str):
    (SALIDA / nombre).write_text(contenido, encoding="utf-8")

def crear_logos():
    SALIDA.mkdir(parents=True, exist_ok=True)
    EVIDENCIA.mkdir(parents=True, exist_ok=True)
    medidas = {}
    for paleta, (_, _, tinta) in PALETAS.items():
        guardar(f"simbolo-{paleta}.svg", svg(80, 80, simbolo(paleta), "Vinculación · símbolo"))
        # Versión principal, con nombre completo y dos líneas de igual jerarquía.
        d1, w1 = texto_trazado("Banco de proyectos", 34, 100, 34)
        d2, w2 = texto_trazado("académicos", 34, 100, 72)
        ancho = round(104 + max(w1, w2), 2)
        cuerpo = simbolo(paleta) + f'<g fill="{tinta}"><path d="{d1}"/><path d="{d2}"/></g>'
        guardar(f"logo-horizontal-{paleta}.svg", svg(ancho, 80, cuerpo, "Banco de proyectos académicos"))
        # Composición vertical.
        v1, vw1 = texto_trazado("Banco de proyectos", 26, 0, 0)
        v2, vw2 = texto_trazado("académicos", 26, 0, 0)
        ancho_v = round(max(vw1, vw2) + 24, 2)
        cuerpo_v = (f'<g transform="translate({(ancho_v - 104) / 2:g} 4) scale(1.3)">{simbolo(paleta)}</g>'
                    f'<g fill="{tinta}"><path transform="translate({(ancho_v-vw1)/2:g} 144)" d="{v1}"/>'
                    f'<path transform="translate({(ancho_v-vw2)/2:g} 175)" d="{v2}"/></g>')
        guardar(f"logo-vertical-{paleta}.svg", svg(ancho_v, 190, cuerpo_v, "Banco de proyectos académicos"))
        # Composición compacta para la navegación existente.
        n1, nw1 = texto_trazado("Banco de proyectos", 17.5, 55, 23)
        n2, nw2 = texto_trazado("académicos", 14, 55, 41, 600)
        ancho_n = round(58 + max(nw1, nw2), 2)
        cuerpo_n = (f'<g transform="scale(.6)">{simbolo(paleta)}</g>'
                    f'<g fill="{tinta}"><path d="{n1}"/><path d="{n2}"/></g>')
        guardar(f"logo-navegacion-{paleta}.svg", svg(ancho_n, 48, cuerpo_n, "Banco de proyectos académicos"))
        medidas[paleta] = {"horizontal": [ancho, 80], "vertical": [ancho_v, 190],
                            "navegacion": [ancho_n, 48]}
    # La placa clara conserva la misma apariencia en la pestaña de cualquier tema.
    guardar("favicon.svg", svg(80, 80, '<rect width="80" height="80" rx="16" fill="#ffffff"/>'
                              + '<g transform="translate(4 4) scale(.9)">' + simbolo("color") + '</g>',
                              "Banco de proyectos académicos"))
    (ENTREGA / "medidas.json").write_text(json.dumps(medidas, indent=2) + "\n", encoding="utf-8")
    shutil.copyfile(WEB / "node_modules/@fontsource-variable/inter/LICENSE", ENTREGA / "LICENCIA-Inter.txt")

def exportar():
    from PIL import Image
    inkscape = shutil.which("inkscape") or r"C:\Program Files\Inkscape\bin\inkscape.com"
    def exportar_archivo(origen: Path, destino: Path, *opciones):
        subprocess.run([inkscape, str(origen), "--export-filename=" + str(destino), *opciones],
                       check=True, capture_output=True)
    exportar_archivo(SALIDA / "favicon.svg", EVIDENCIA / "favicon-256.png", "--export-width=256")
    with Image.open(EVIDENCIA / "favicon-256.png") as imagen:
        imagen.save(WEB / "public/favicon.ico", format="ICO", sizes=[(16,16), (32,32), (48,48), (64,64)])
    exportar_archivo(SALIDA / "favicon.svg", SALIDA / "apple-touch-icon.png", "--export-width=180")
    for version in ("color", "monocromo"):
        exportar_archivo(SALIDA / f"logo-horizontal-{version}.svg",
                         ENTREGA / f"logo-horizontal-{version}.pdf")
    exportar_archivo(ENTREGA / "presentacion.svg", ENTREGA / "presentacion.png", "--export-width=1600")
    exportar_archivo(ENTREGA / "presentacion.svg", ENTREGA / "presentacion.pdf")

def presentacion():
    # Vista de entrega construida con los mismos SVG finales.
    def incrustar(nombre, x, y, ancho):
        import xml.etree.ElementTree as ET
        raiz = ET.parse(SALIDA / nombre).getroot()
        w, h = float(raiz.attrib["width"]), float(raiz.attrib["height"])
        contenido = "".join(ET.tostring(e, encoding="unicode") for e in raiz if e.tag.endswith("g") or e.tag.endswith("path"))
        return f'<g transform="translate({x} {y}) scale({ancho/w})">{contenido}</g>'
    textos = [
        (64, 66, "VINCULACIÓN", 18, "#5f6b85"),
        (64, 108, "Banco de proyectos académicos", 30, "#172036"),
        (64, 425, "COLOR / FONDO CLARO", 14, "#5f6b85"),
        (656, 425, "COLOR / FONDO OSCURO", 14, "#aebada"),
        (64, 675, "UNA TINTA", 14, "#5f6b85"),
        (656, 675, "NEGATIVO", 14, "#aebada"),
    ]
    cuerpo = ('<rect width="1200" height="850" fill="#ffffff"/>'
              '<rect x="600" y="380" width="600" height="470" fill="#0d1322"/>'
              '<path d="M0 380H1200M0 630H1200" stroke="#e1e6ef"/>'
              + incrustar("logo-horizontal-color.svg", 120, 180, 940)
              + incrustar("simbolo-color.svg", 236, 448, 132)
              + incrustar("simbolo-oscuro.svg", 835, 448, 132)
              + incrustar("simbolo-monocromo.svg", 236, 698, 112)
              + incrustar("simbolo-blanco.svg", 835, 698, 112))
    for x, base, contenido, tamano, color in textos:
        d, _ = texto_trazado(contenido, tamano, x, base, 600)
        cuerpo += f'<path fill="{color}" d="{d}"/>'
    (ENTREGA / "presentacion.svg").write_text(svg(1200, 850, cuerpo, "Identidad final · Vinculación"), encoding="utf-8")

def empaquetar():
    with zipfile.ZipFile(ENTREGA / "banco-proyectos-identidad.zip", "w", zipfile.ZIP_DEFLATED) as paquete:
        for archivo in sorted(SALIDA.iterdir()):
            paquete.write(archivo, "brand/" + archivo.name)
        paquete.write(WEB / "public/favicon.ico", "favicon.ico")
        for nombre in ("GUIA.md", "LICENCIA-Inter.txt", "presentacion.svg", "presentacion.pdf",
                       "logo-horizontal-color.pdf", "logo-horizontal-monocromo.pdf",
                       "reconstruir.py", "medidas.json"):
            if (ENTREGA / nombre).exists():
                paquete.write(ENTREGA / nombre, nombre)

if __name__ == "__main__":
    crear_logos()
    presentacion()
    exportar()
    empaquetar()
    print(json.dumps({"svg": len(list(SALIDA.glob("*.svg"))), "salida": str(SALIDA), "entrega": str(ENTREGA)}))


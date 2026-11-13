"""Recorrido HTTP de las 19 cuentas ficticias sobre el enlace público activo.

No cambia contraseñas ni decisiones: consulta pantallas y cierra cada sesión.
Uso: py -3.12 tests/pruebas_publicas.py
"""
from __future__ import annotations

from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from html import unescape
from http.cookiejar import CookieJar
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

WEB = Path(__file__).resolve().parents[1]
PROYECTO = WEB.parent
sys.path.insert(0, str(PROYECTO / "database"))
from cargar_demo import DEMO_CLAVE  # noqa: E402


def token(html: str) -> str:
    encontrado = re.search(r'name="_token"\s+value="([^"]+)"', html)
    if not encontrado:
        raise RuntimeError("No se encontró el token CSRF del formulario.")
    return unescape(encontrado.group(1))


def main() -> None:
    estado = json.loads((PROYECTO / ".local/pruebas-publicas/estado.json").read_text(encoding="utf-8-sig"))
    url = estado["url"]
    if not re.fullmatch(r"https://[a-z0-9-]+\.trycloudflare\.com", url):
        raise ValueError("Se requiere el enlace HTTPS del túnel de pruebas.")

    def cliente():
        jar = CookieJar()
        return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar)), jar

    def pedir(opener, ruta, datos=None):
        payload = urllib.parse.urlencode(datos).encode() if datos is not None else None
        req = urllib.request.Request(url + ruta, data=payload, headers={
            "User-Agent": "Banco-Demo-Verificacion/1.0", "Origin": url,
        })
        try:
            with opener.open(req, timeout=40) as respuesta:
                return respuesta.status, respuesta.url, respuesta.headers, respuesta.read()
        except urllib.error.HTTPError as error:
            return error.code, error.url, error.headers, error.read()

    invitado, _ = cliente()
    codigo, destino, _, contenido = pedir(invitado, "/panel")
    assert codigo == 200 and destino == url + "/login", "Acceso anónimo sin redirección al login."
    html = contenido.decode()
    assert "http://" + urllib.parse.urlparse(url).netloc not in html, "La página genera enlaces HTTP."
    assets = sorted(set(re.findall(r'(?:href|src)="([^"]+/build/assets/[^"]+)"', html)))
    assert len(assets) >= 2, "Faltan CSS o JavaScript compilados."
    for asset in assets:
        assert asset.startswith(url + "/build/assets/"), "Recurso fuera del origen HTTPS."
        assert pedir(invitado, asset.removeprefix(url))[0] == 200, "Recurso compilado no disponible."
    for ruta in ("/.env", "/.git/config", "/composer.json", "/database/demo.sql"):
        assert pedir(invitado, ruta)[0] == 404, "Un archivo privado es accesible."
    assert pedir(invitado, "/logout", {})[0] == 419, "El formulario sin CSRF no fue rechazado."

    cuentas_sql = (PROYECTO / "database/demo.sql").read_text(encoding="utf-8-sig").split("-- Empresas y representantes")[0]
    cuentas = re.findall(r"'([^']+@demo\.test)',__HASH_DEMO__,'(administrador|empresa|profesor|alumno)'", cuentas_sql)
    assert len(cuentas) == 19

    def comprobar(cuenta):
        correo, rol = cuenta
        navegador, jar = cliente()
        codigo, _, _, cuerpo = pedir(navegador, "/login")
        assert codigo == 200
        codigo, destino, headers, cuerpo = pedir(navegador, "/login", {
            "correo": correo, "password": DEMO_CLAVE, "_token": token(cuerpo.decode()),
        })
        assert codigo == 200 and destino == url + "/panel", f"Acceso fallido de {correo}: {codigo}"
        assert "no-store" in headers.get("Cache-Control", "")
        assert any(c.name == "banco_pruebas_publicas_session" and c.secure for c in jar)
        rutas = ["/avisos", "/seguimiento/proyectos"]
        if rol == "administrador":
            rutas += ["/admin/cuentas", "/admin/proyectos", "/admin/habilidades", "/reportes"]
        elif rol == "empresa":
            rutas += ["/empresa", "/empresa/proyectos", "/participacion/candidatura"]
        else:
            rutas += ["/perfil", "/catalogo", "/participacion/" + ("candidatura" if rol == "alumno" else "direccion")]
        for ruta in rutas:
            assert pedir(navegador, ruta)[0] == 200, f"Pantalla no disponible para {correo}: {ruta}"
        if rol != "administrador":
            assert pedir(navegador, "/admin/cuentas")[0] == 403
            assert pedir(navegador, "/reportes")[0] == 403
        codigo, destino, _, _ = pedir(navegador, "/logout", {"_token": token(cuerpo.decode())})
        assert codigo == 200 and destino == url + "/login"
        assert pedir(navegador, "/panel")[1] == url + "/login"
        return rol

    roles = Counter()
    with ThreadPoolExecutor(max_workers=3) as pool:
        for resultado in as_completed(pool.submit(comprobar, cuenta) for cuenta in cuentas):
            roles[resultado.result()] += 1
            print(f"Cuentas verificadas: {sum(roles.values())}/19", flush=True)

    recibo = {
        "fecha_utc": datetime.now(timezone.utc).isoformat(), "url": url,
        "base": "banco_pruebas_publicas", "cuentas_verificadas": sum(roles.values()), "roles": dict(roles),
        "resultado": "correcto", "recursos_https": len(assets),
        "comprobaciones": ["inicio y cierre de sesión", "panel y consultas por rol", "cookies Secure",
                           "no-store en páginas privadas", "permisos administrativos", "CSRF",
                           "archivos privados inaccesibles", "CSS y JavaScript por HTTPS"],
        "limites": "Pruebas HTTP, sin navegador ni carga concurrente acreditada. El túnel depende de este equipo.",
    }
    destino = WEB / "evidencia/pruebas-publicas.json"
    destino.write_text(json.dumps(recibo, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(recibo, ensure_ascii=False))


if __name__ == "__main__":
    main()

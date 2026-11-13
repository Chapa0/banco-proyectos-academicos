import { Tooltip } from 'bootstrap';

// Mejora progresiva: las rutas y la validación siguen funcionando sin JavaScript.
// No se cambia el destino ni se leen credenciales; solo se comunica el envío.
document.querySelectorAll('form[data-submit-label]').forEach((form) => {
    const button = form.querySelector('button[type="submit"]');
    if (!button) return;
    const original = button.textContent;
    const status = document.createElement('p');
    status.className = 'submission-status small mt-3 mb-0';
    status.setAttribute('role', 'status');
    status.hidden = true;
    form.after(status);

    form.addEventListener('submit', () => {
        form.setAttribute('aria-busy', 'true');
        button.disabled = true;
        button.textContent = form.dataset.submitLabel;
        status.hidden = false;
        status.textContent = 'Enviando. Espera la respuesta antes de continuar.';
    });

    window.addEventListener('pageshow', () => {
        form.removeAttribute('aria-busy');
        button.disabled = false;
        button.textContent = original;
        status.hidden = true;
        status.textContent = '';
    });
});

// Ayudas «i»: aparecen al pasar el cursor, al enfocar con teclado o al tocar; Escape las cierra.
const ayudas = [...document.querySelectorAll('[data-info-tip]')].map((boton) => {
    const tooltip = new Tooltip(boton, { trigger: 'hover focus', placement: 'top', customClass: 'info-tooltip' });
    boton.addEventListener('click', () => {
        ayudas.forEach((otra) => { if (otra !== tooltip) otra.hide(); });
        tooltip.show();
    });
    return tooltip;
});
if (ayudas.length) {
    document.addEventListener('keydown', (evento) => {
        if (evento.key === 'Escape') ayudas.forEach((tooltip) => tooltip.hide());
    });
    document.addEventListener('click', (evento) => {
        if (!evento.target.closest('[data-info-tip]')) ayudas.forEach((tooltip) => tooltip.hide());
    });
}

// Contraseñas: botón Mostrar/Ocultar, aviso de Bloq Mayús, longitud mínima y coincidencia.
document.querySelectorAll('input[data-password]').forEach((campo) => {
    const contenedor = document.createElement('div');
    contenedor.className = 'password-field';
    campo.before(contenedor);
    contenedor.append(campo);

    const alternar = document.createElement('button');
    alternar.type = 'button';
    alternar.className = 'password-toggle';
    alternar.textContent = 'Mostrar';
    alternar.setAttribute('aria-pressed', 'false');
    alternar.setAttribute('aria-controls', campo.id);
    alternar.setAttribute('aria-label', 'Mostrar contraseña');
    alternar.addEventListener('click', () => {
        const visible = campo.type === 'password';
        campo.type = visible ? 'text' : 'password';
        alternar.textContent = visible ? 'Ocultar' : 'Mostrar';
        alternar.setAttribute('aria-pressed', String(visible));
        alternar.setAttribute('aria-label', visible ? 'Ocultar contraseña' : 'Mostrar contraseña');
        campo.focus();
    });
    contenedor.append(alternar);
    // Al enviar se vuelve a ocultar, para que el navegador no la recuerde como texto visible.
    campo.form?.addEventListener('submit', () => { campo.type = 'password'; });

    const aviso = document.createElement('p');
    aviso.className = 'password-feedback';
    aviso.setAttribute('aria-live', 'polite');
    contenedor.after(aviso);

    const minimo = Number(campo.dataset.passwordLength || 0);
    const original = campo.dataset.match ? document.getElementById(campo.dataset.match) : null;
    let mayusculas = false;

    const actualizar = () => {
        const mensajes = [];
        let estado = '';
        if (mayusculas) mensajes.push('Bloq Mayús está activado.');
        if (minimo && campo.value.length > 0 && campo.value.length < minimo) {
            mensajes.push(`Llevas ${campo.value.length} de ${minimo} caracteres mínimos.`);
        } else if (minimo && campo.value.length >= minimo) {
            mensajes.push('Longitud suficiente.');
            estado = 'is-ok';
        }
        if (original && campo.value.length > 0) {
            const coincide = campo.value === original.value;
            mensajes.push(coincide ? 'Las contraseñas coinciden.' : 'Todavía no coincide con la anterior.');
            estado = coincide ? 'is-ok' : '';
        }
        aviso.textContent = mensajes.join(' ');
        aviso.className = `password-feedback ${estado}`;
    };
    const revisarMayusculas = (evento) => {
        if (typeof evento.getModifierState === 'function') mayusculas = evento.getModifierState('CapsLock');
        actualizar();
    };
    campo.addEventListener('keydown', revisarMayusculas);
    campo.addEventListener('keyup', revisarMayusculas);
    campo.addEventListener('input', actualizar);
    campo.addEventListener('blur', () => { mayusculas = false; actualizar(); });
    original?.addEventListener('input', () => { if (campo.value) actualizar(); });
});

// Contador de caracteres en textos largos; solo se anuncia cuando queda poco espacio.
document.querySelectorAll('textarea[maxlength]').forEach((area) => {
    const limite = Number(area.getAttribute('maxlength'));
    if (!limite) return;
    const contador = document.createElement('p');
    contador.className = 'char-counter';
    area.after(contador);
    const actualizar = () => {
        const usados = area.value.length;
        const restantes = limite - usados;
        const cerca = restantes <= Math.max(20, limite * 0.1);
        contador.textContent = cerca
            ? `${usados.toLocaleString('es-MX')} / ${limite.toLocaleString('es-MX')} caracteres · quedan ${restantes.toLocaleString('es-MX')}`
            : `${usados.toLocaleString('es-MX')} / ${limite.toLocaleString('es-MX')} caracteres`;
        contador.classList.toggle('is-near', cerca);
        if (cerca) contador.setAttribute('aria-live', 'polite'); else contador.removeAttribute('aria-live');
    };
    area.addEventListener('input', actualizar);
    actualizar();
});

const errorSummary = document.getElementById('errores-formulario');
if (errorSummary) errorSummary.focus();

// Menú de cuenta (details nativo): Escape lo cierra y devuelve el foco; un clic fuera también lo cierra.
document.querySelectorAll('[data-account-menu]').forEach((menu) => {
    const disparador = menu.querySelector('summary');
    document.addEventListener('click', (evento) => {
        if (menu.open && !menu.contains(evento.target)) menu.open = false;
    });
    menu.addEventListener('keydown', (evento) => {
        if (evento.key === 'Escape' && menu.open) {
            menu.open = false;
            disparador.focus();
        }
    });
});

// Cambios sin guardar: si un formulario POST se modificó y se intenta salir (cerrar sesión, otro
// enlace o cerrar la pestaña), el navegador pide confirmación. Enviar ese mismo formulario no avisa.
const formulariosConCambios = new Set();
document.querySelectorAll('form[method="POST" i][data-submit-label]:not([data-sin-aviso-salida])').forEach((form) => {
    const marcar = () => formulariosConCambios.add(form);
    form.addEventListener('input', marcar);
    form.addEventListener('change', marcar);
    form.addEventListener('submit', () => formulariosConCambios.delete(form));
});
window.addEventListener('beforeunload', (evento) => {
    if (formulariosConCambios.size === 0) return;
    evento.preventDefault();
    evento.returnValue = '';
});
window.addEventListener('pageshow', (evento) => {
    if (evento.persisted) formulariosConCambios.clear();
});

// Acciones que quitan algo piden confirmación explícita (data-confirm); sin JavaScript se envían directo.
document.querySelectorAll('form[data-confirm]').forEach((form) => {
    form.addEventListener('submit', (evento) => {
        if (!window.confirm(form.dataset.confirm)) evento.preventDefault();
    });
});

// RD-01: modo claro/oscuro. El tema inicial lo fija un script en <head>; aquí solo se alterna y se recuerda.
const raiz = document.documentElement;
const reflejarTema = () => {
    document.querySelectorAll('[data-theme-toggle]').forEach((boton) => {
        const oscuro = raiz.dataset.theme === 'dark';
        boton.setAttribute('aria-pressed', String(oscuro));
        boton.title = oscuro ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro';
    });
};
reflejarTema();
document.querySelectorAll('[data-theme-toggle]').forEach((boton) => {
    boton.addEventListener('click', () => {
        const tema = raiz.dataset.theme === 'dark' ? 'light' : 'dark';
        raiz.dataset.theme = tema;
        raiz.dataset.bsTheme = tema;
        try { localStorage.setItem('banco-tema', tema); } catch (error) { /* Sin almacenamiento: el cambio dura esta página. */ }
        reflejarTema();
    });
});

// RD-01: barra lateral desplegable en pantallas angostas. Escape o el fondo la cierran y devuelven el foco.
const shell = document.querySelector('[data-app-shell]');
const botonMenu = document.querySelector('[data-sidebar-toggle]');
const fondoMenu = document.querySelector('[data-sidebar-close]');
if (shell && botonMenu) {
    const cerrarMenu = (devolverFoco) => {
        shell.classList.remove('is-menu-open');
        botonMenu.setAttribute('aria-expanded', 'false');
        if (fondoMenu) fondoMenu.hidden = true;
        if (devolverFoco) botonMenu.focus();
    };
    botonMenu.addEventListener('click', () => {
        const abrir = !shell.classList.contains('is-menu-open');
        shell.classList.toggle('is-menu-open', abrir);
        botonMenu.setAttribute('aria-expanded', String(abrir));
        if (fondoMenu) fondoMenu.hidden = !abrir;
        if (abrir) shell.querySelector('.app-sidebar a, .app-sidebar button')?.focus();
    });
    fondoMenu?.addEventListener('click', () => cerrarMenu(true));
    document.addEventListener('keydown', (evento) => {
        if (evento.key === 'Escape' && shell.classList.contains('is-menu-open')) cerrarMenu(true);
    });
}

<!DOCTYPE html>
<html lang="es" data-theme="light" data-bs-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="Proyectos de empresas que vinculan a alumnos y profesores con necesidades tecnológicas reales.">
    <title>@yield('title', 'Banco de proyectos académicos')</title>
    {{-- RD-01: el tema se aplica antes de pintar para evitar un destello claro. Preferencia guardada o la del sistema. --}}
    <script>
        (function () {
            var tema = null;
            try { tema = localStorage.getItem('banco-tema'); } catch (e) {}
            if (tema !== 'dark' && tema !== 'light') { tema = window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; }
            document.documentElement.dataset.theme = tema;
            document.documentElement.dataset.bsTheme = tema;
        })();
    </script>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
@auth
@php
    $cuenta = auth()->user();
    $rolCuenta = ['administrador' => 'Administración', 'empresa' => 'Empresa', 'alumno' => 'Alumno', 'profesor' => 'Profesor'][$cuenta->rol_principal] ?? '';
    $claveTemporal = (bool) $cuenta->requiere_cambio_clave;
@endphp
<body class="workspace-page">
    <a class="skip-link" href="#contenido">Saltar al contenido</a>
    <div class="app-shell" data-app-shell>
        <aside class="app-sidebar" id="barra-lateral" aria-label="Menú de la cuenta">
            <a class="app-brand" href="{{ route($claveTemporal ? 'clave.edit' : 'panel') }}"><span class="brand-mark" aria-hidden="true"><i class="bi bi-bezier2"></i></span>Banco de proyectos</a>
            @unless($claveTemporal)
                @include('layouts._navegacion')
            @endunless
            <div class="app-sidebar-foot">
                <div class="app-account">
                    <x-avatar :imagen="$fotoCuenta ?? null" :nombre="$cuenta->nombre" tamano="md" />
                    <div class="app-account-text"><span class="app-account-name">{{ $cuenta->nombre }}</span><span class="app-account-role">{{ $rolCuenta }}</span></div>
                </div>
                @unless($claveTemporal)
                    <a class="nav-item {{ request()->routeIs('clave.*') ? 'is-current' : '' }}" href="{{ route('clave.edit') }}" @if(request()->routeIs('clave.*')) aria-current="page" @endif><i class="bi bi-key" aria-hidden="true"></i>Cambiar contraseña</a>
                @endunless
                <form method="POST" action="{{ route('logout') }}">@csrf<button class="nav-item nav-logout" type="submit"><i class="bi bi-box-arrow-right" aria-hidden="true"></i>Cerrar sesión</button></form>
            </div>
        </aside>
        <div class="app-backdrop" data-sidebar-close hidden></div>
        <div class="app-main">
            <header class="app-topbar">
                <button class="icon-button app-menu-button" type="button" aria-controls="barra-lateral" aria-expanded="false" data-sidebar-toggle><i class="bi bi-list" aria-hidden="true"></i><span class="visually-hidden">Abrir menú</span></button>
                <a class="app-topbar-brand" href="{{ route($claveTemporal ? 'clave.edit' : 'panel') }}">Banco de proyectos</a>
                <div class="app-topbar-actions">
                    @include('layouts._tema')
                    @if(! $claveTemporal && ($avisosSinLeer ?? null) !== null)
                        <a class="icon-button app-bell" href="{{ route('avisos.index', ['estado' => 'no_leidos']) }}">
                            <i class="bi bi-bell" aria-hidden="true"></i>
                            @if($avisosSinLeer > 0)<span class="app-bell-count" aria-hidden="true">{{ $avisosSinLeer > 99 ? '99+' : $avisosSinLeer }}</span>@endif
                            <span class="visually-hidden">{{ $avisosSinLeer === 1 ? '1 aviso sin leer' : $avisosSinLeer.' avisos sin leer' }}</span>
                        </a>
                    @endif
                </div>
            </header>
            <main id="contenido" tabindex="-1">
                @if(session('status'))<div class="container pt-4"><div class="alert alert-success" role="status"><i class="bi bi-check-circle-fill me-2" aria-hidden="true"></i>{{ session('status') }}</div></div>@endif
                @yield('content')
            </main>
            <footer class="site-footer">
                <div class="container py-4"><p class="mb-0">Banco de proyectos académicos</p></div>
            </footer>
        </div>
    </div>
</body>
@else
<body class="{{ request()->routeIs('inicio') ? 'public-page' : 'workspace-page' }}">
    <a class="skip-link" href="#contenido">Saltar al contenido</a>
    <header class="public-header">
        <div class="container public-header-inner">
            <a class="app-brand" href="{{ route('inicio') }}"><span class="brand-mark" aria-hidden="true"><i class="bi bi-bezier2"></i></span>Banco de proyectos</a>
            <nav class="public-nav" aria-label="Navegación pública">
                <a class="public-nav-link" href="{{ route('inicio') }}#como-funciona">Cómo funciona</a>
                @include('layouts._tema')
                @unless(request()->routeIs('login*'))
                    <a class="btn btn-primary btn-sm-touch" href="{{ route('login') }}">Iniciar sesión</a>
                @else
                    <a class="public-nav-link is-current" href="{{ route('login') }}" aria-current="page">Iniciar sesión</a>
                @endunless
            </nav>
        </div>
    </header>
    <main id="contenido" tabindex="-1">
        @if(session('status'))<div class="container pt-4"><div class="alert alert-success" role="status">{{ session('status') }}</div></div>@endif
        @yield('content')
    </main>
    <footer class="site-footer public-footer">
        <div class="container py-4 d-flex flex-wrap justify-content-between gap-2">
            <p class="mb-0">Banco de proyectos académicos · Proyecto escolar</p>
            <p class="mb-0">Ingeniería en Sistemas Computacionales</p>
        </div>
    </footer>
</body>
@endauth
</html>

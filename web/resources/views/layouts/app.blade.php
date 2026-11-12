<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="Proyectos de empresas que vinculan a alumnos y profesores con necesidades tecnológicas reales.">
    <title>@yield('title', 'Banco de proyectos académicos')</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="{{ request()->routeIs('inicio') ? 'public-page' : 'workspace-page' }}">
    <a class="skip-link" href="#contenido">Saltar al contenido</a>

    <header class="site-header">
        <div class="container site-topbar">
            <a class="site-brand" href="{{ route('inicio') }}">Banco de proyectos</a>
            @auth
                @php
                    $cuenta = auth()->user();
                    $iniciales = collect(preg_split('/\s+/u', trim($cuenta->nombre)))->filter()->take(2)->map(fn ($p) => mb_strtoupper(mb_substr($p, 0, 1)))->implode('');
                    $rolCuenta = ['administrador' => 'Administrador', 'empresa' => 'Empresa', 'alumno' => 'Alumno', 'profesor' => 'Profesor'][$cuenta->rol_principal] ?? '';
                @endphp
                {{-- Menú de cuenta separado de la navegación: salir requiere abrirlo a propósito. Funciona sin JavaScript. --}}
                <details class="account-menu" data-account-menu>
                    <summary class="account-trigger">
                        <span class="account-avatar" aria-hidden="true">{{ $iniciales }}</span>
                        <span class="account-trigger-text"><span class="account-trigger-name">{{ $cuenta->nombre }}</span><span class="account-trigger-role">{{ $rolCuenta }}</span></span>
                        <span class="visually-hidden">: menú de tu cuenta</span>
                        <span class="account-caret" aria-hidden="true"></span>
                    </summary>
                    <div class="account-panel">
                        <p class="account-panel-name">{{ $cuenta->nombre }}</p>
                        <p class="account-panel-email">{{ $rolCuenta }}</p>
                        @if(!$cuenta->requiere_cambio_clave)
                            <a class="account-panel-link" href="{{ route('panel') }}">Mi espacio</a>
                            <a class="account-panel-link" href="{{ route('clave.edit') }}">Cambiar contraseña</a>
                        @endif
                        <form method="POST" action="{{ route('logout') }}" class="account-panel-logout">@csrf<button class="btn btn-outline-danger w-100" type="submit"><span class="logout-icon" aria-hidden="true"></span>Cerrar sesión</button></form>
                    </div>
                </details>
            @else
                <div class="site-navigation-actions">
                    <a class="site-nav-link" href="{{ route('inicio') }}#como-funciona">Cómo funciona</a>
                    <a class="site-nav-link {{ request()->routeIs('login*') ? 'is-current' : '' }}" href="{{ route('login') }}" @if(request()->routeIs('login*')) aria-current="page" @endif>Iniciar sesión</a>
                </div>
            @endauth
        </div>
        @auth
            @if(!auth()->user()->requiere_cambio_clave)
        <nav class="container site-navigation" aria-label="Navegación principal">
            <div class="site-navigation-actions">
                        <a class="site-nav-link {{ request()->routeIs('panel') ? 'is-current' : '' }}" href="{{ route('panel') }}" @if(request()->routeIs('panel')) aria-current="page" @endif>Mi espacio</a>
                        @can('consultar-avisos')<a class="site-nav-link {{ request()->routeIs('avisos.*') ? 'is-current' : '' }}" href="{{ route('avisos.index') }}" @if(request()->routeIs('avisos.*')) aria-current="true" @endif>Avisos</a>@endcan
                        @can('consultar-reportes')<a class="site-nav-link {{ request()->routeIs('reportes.*') ? 'is-current' : '' }}" href="{{ route('reportes.index') }}" @if(request()->routeIs('reportes.*')) aria-current="true" @endif>Reportes</a>@endcan
                        @can('consultar-catalogo')<a class="site-nav-link {{ request()->routeIs('catalogo.*') ? 'is-current' : '' }}" href="{{ route('catalogo.index') }}" @if(request()->routeIs('catalogo.*')) aria-current="true" @endif>Catálogo de proyectos</a>@endcan
                        @can('gestionar-perfil')<a class="site-nav-link {{ request()->routeIs('perfil.*') ? 'is-current' : '' }}" href="{{ route('perfil.edit') }}" @if(request()->routeIs('perfil.*')) aria-current="page" @endif>Mi perfil</a>@endcan
                        @can('consultar-participacion')
                            @if(auth()->user()->rol_principal !== 'profesor')<a class="site-nav-link {{ request()->routeIs('participacion.*') && request()->route('tipo') === 'candidatura' ? 'is-current' : '' }}" href="{{ route('participacion.index', 'candidatura') }}" @if(request()->routeIs('participacion.*') && request()->route('tipo') === 'candidatura') aria-current="true" @endif>{{ auth()->user()->rol_principal === 'alumno' ? 'Mis candidaturas' : 'Candidaturas' }}</a>@endif
                            @if(in_array(auth()->user()->rol_principal, ['profesor','administrador']))<a class="site-nav-link {{ request()->routeIs('participacion.*') && request()->route('tipo') === 'direccion' ? 'is-current' : '' }}" href="{{ route('participacion.index', 'direccion') }}" @if(request()->routeIs('participacion.*') && request()->route('tipo') === 'direccion') aria-current="true" @endif>{{ auth()->user()->rol_principal === 'profesor' ? 'Mis solicitudes' : 'Dirección' }}</a>@endif
                            <a class="site-nav-link {{ request()->routeIs('seguimiento.*') ? 'is-current' : '' }}" href="{{ route('seguimiento.index') }}" @if(request()->routeIs('seguimiento.*')) aria-current="true" @endif>Seguimiento</a>
                        @endcan
                        @can('gestionar-proyectos')
                            <a class="site-nav-link {{ request()->routeIs('proyectos.*') ? 'is-current' : '' }}" href="{{ route('proyectos.index') }}" @if(request()->routeIs('proyectos.*')) aria-current="true" @endif>Mis proyectos</a>
                            <a class="site-nav-link {{ request()->routeIs('empresa.*') ? 'is-current' : '' }}" href="{{ route('empresa.edit') }}" @if(request()->routeIs('empresa.*')) aria-current="page" @endif>Datos de empresa</a>
                        @endcan
                        @can('revisar-proyectos')<a class="site-nav-link {{ request()->routeIs('revision.*') ? 'is-current' : '' }}" href="{{ route('revision.index') }}" @if(request()->routeIs('revision.*')) aria-current="true" @endif>Revisión de proyectos</a>@endcan
                        @can('administrar-cuentas')<a class="site-nav-link {{ request()->routeIs('cuentas.*') ? 'is-current' : '' }}" href="{{ route('cuentas.index') }}" @if(request()->routeIs('cuentas.*')) aria-current="{{ request()->routeIs('cuentas.index') ? 'page' : 'true' }}" @endif>Cuentas</a>@endcan
            </div>
        </nav>
            @endif
        @endauth
    </header>

    <main id="contenido" tabindex="-1">
        @if(session('status'))<div class="container pt-4"><div class="alert alert-success" role="status">{{ session('status') }}</div></div>@endif
        @yield('content')
    </main>

    <footer class="site-footer">
        <div class="container py-4">
            <p class="mb-0">Banco de proyectos académicos</p>
        </div>
    </footer>
</body>
</html>

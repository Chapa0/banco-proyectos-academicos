{{-- RD-01: navegación agrupada por tema. Solo se muestran las secciones autorizadas; el servidor vuelve a autorizar cada ruta. --}}
@php
    $rol = auth()->user()->rol_principal;
    $tipoRuta = request()->route('tipo');
    $enlace = function (string $ruta, string $icono, string $texto, bool $actual, array $parametros = [], ?int $cuenta = null) {
        return ['url' => route($ruta, $parametros), 'icono' => $icono, 'texto' => $texto, 'actual' => $actual, 'cuenta' => $cuenta];
    };
    $grupos = [];
    $grupos[''] = [$enlace('panel', 'bi-house', 'Mi espacio', request()->routeIs('panel'))];
    if (\Illuminate\Support\Facades\Gate::allows('consultar-avisos')) {
        $grupos[''][] = $enlace('avisos.index', 'bi-bell', 'Avisos', request()->routeIs('avisos.*'), [], $avisosSinLeer ?? null);
    }
    $proyectos = [];
    if (\Illuminate\Support\Facades\Gate::allows('consultar-catalogo')) {
        $proyectos[] = $enlace('catalogo.index', 'bi-grid', 'Catálogo de proyectos', request()->routeIs('catalogo.*', 'participacion.create'));
    }
    if (\Illuminate\Support\Facades\Gate::allows('gestionar-proyectos')) {
        $proyectos[] = $enlace('proyectos.index', 'bi-folder2-open', 'Mis proyectos', request()->routeIs('proyectos.*'));
        $proyectos[] = $enlace('empresa.edit', 'bi-buildings', 'Datos de empresa', request()->routeIs('empresa.*'));
    }
    if (\Illuminate\Support\Facades\Gate::allows('revisar-proyectos')) {
        $proyectos[] = $enlace('revision.index', 'bi-clipboard-check', 'Revisión de proyectos', request()->routeIs('revision.*'));
    }
    if ($proyectos) {
        $grupos['Proyectos'] = $proyectos;
    }
    $participacion = [];
    if (\Illuminate\Support\Facades\Gate::allows('consultar-participacion')) {
        if ($rol !== 'profesor') {
            $participacion[] = $enlace('participacion.index', 'bi-people', $rol === 'alumno' ? 'Mis candidaturas' : 'Candidaturas',
                request()->routeIs('participacion.index', 'participacion.show') && $tipoRuta === 'candidatura', ['candidatura']);
        }
        if (in_array($rol, ['profesor', 'administrador'], true)) {
            $participacion[] = $enlace('participacion.index', 'bi-person-badge', $rol === 'profesor' ? 'Mis solicitudes' : 'Dirección',
                request()->routeIs('participacion.index', 'participacion.show') && $tipoRuta === 'direccion', ['direccion']);
        }
        $participacion[] = $enlace('seguimiento.index', 'bi-diagram-3', 'Seguimiento', request()->routeIs('seguimiento.*'));
        $grupos['Participación'] = $participacion;
    }
    if (\Illuminate\Support\Facades\Gate::allows('gestionar-perfil')) {
        $grupos['Mi cuenta'] = [$enlace('perfil.edit', 'bi-person-vcard', 'Mi perfil', request()->routeIs('perfil.*'))];
    }
    if (\Illuminate\Support\Facades\Gate::allows('administrar-cuentas')) {
        $grupos['Administración'] = [
            $enlace('reportes.index', 'bi-bar-chart-line', 'Reportes', request()->routeIs('reportes.*')),
            $enlace('cuentas.index', 'bi-person-gear', 'Cuentas', request()->routeIs('cuentas.*')),
            $enlace('habilidades.index', 'bi-tags', 'Habilidades', request()->routeIs('habilidades.*')),
        ];
    }
@endphp
<nav class="app-nav" aria-label="Navegación principal">
    @foreach($grupos as $titulo => $items)
        <div class="app-nav-group">
            @if($titulo !== '')<p class="app-nav-title">{{ $titulo }}</p>@endif
            @foreach($items as $item)
                <a class="nav-item {{ $item['actual'] ? 'is-current' : '' }}" href="{{ $item['url'] }}" @if($item['actual']) aria-current="page" @endif>
                    <i class="bi {{ $item['icono'] }}" aria-hidden="true"></i>{{ $item['texto'] }}
                    @if(($item['cuenta'] ?? 0) > 0)<span class="nav-count"><span class="visually-hidden">: </span>{{ $item['cuenta'] > 99 ? '99+' : $item['cuenta'] }}<span class="visually-hidden"> sin leer</span></span>@endif
                </a>
            @endforeach
        </div>
    @endforeach
</nav>

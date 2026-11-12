@extends('layouts.app')
@section('title', 'Reportes · Banco de proyectos')
@section('content')
@php
    $etiquetasResumen = ['registros' => 'Registros', 'alumnos_vigentes' => 'Alumnos vigentes', 'directores_vigentes' => 'Directores vigentes', 'activas' => 'Activas', 'pendientes' => 'Pendientes', 'aprobadas' => 'Aprobadas', 'rechazadas' => 'Rechazadas', 'canceladas' => 'Canceladas', 'proyectos_vigentes' => 'Proyectos dirigidos vigentes', 'profesores_con_carga' => 'Profesores con carga', 'finalizadas' => 'Finalizadas', 'revocadas' => 'Revocadas'];
@endphp
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Reportes</h1><p class="page-description">Consulta proyectos, solicitudes y asignaciones con sus totales.</p></div></header>
    <nav class="report-navigation" aria-label="Tipos de reporte">@foreach($tipos as $codigo => $nombre)<a class="{{ $tipo === $codigo ? 'is-current' : '' }}" href="{{ route('reportes.index', $codigo) }}" @if($tipo === $codigo) aria-current="page" @endif>{{ $nombre }}</a>@endforeach</nav>
    <div class="report-heading-row mt-4 mb-3">
        <h2 class="section-heading mb-0">{{ $tipos[$tipo] }}</h2>
        @if($filas->total() > 0)
            <a class="btn btn-outline-secondary" href="{{ route('reportes.exportar', [$tipo] + collect($filtros)->except('page')->filter(fn ($v) => $v !== null && $v !== '')->all()) }}" download>Exportar CSV<span class="visually-hidden"> de {{ $tipos[$tipo] }} con los filtros actuales</span></a>
        @endif
    </div>
    @if($filas->total() > 0)<p class="field-hint">La exportación incluye todas las páginas con los filtros aplicados (hasta {{ number_format(\App\Services\ConsultaService::MAXIMO_EXPORTACION) }} registros) y se abre en Excel u hojas de cálculo.</p>@endif
    <x-errores />
    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('reportes.index', $tipo) }}" aria-label="Filtrar reporte">
            <div class="catalog-filter-grid">
                <div><label class="form-label" for="buscar">Buscar</label><input class="form-control" type="search" id="buscar" name="buscar" maxlength="150" placeholder="Nombre, título o empresa" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div>
                @if(in_array('estado', $campos, true))<div><label class="form-label" for="estado">Estado</label><select class="form-select" id="estado" name="estado"><option value="">Todos los estados</option>@foreach($estados as $codigo => $nombre)<option value="{{ $codigo }}" @selected(($filtros['estado'] ?? '') === $codigo)>{{ $nombre }}</option>@endforeach</select></div>@endif
                @foreach(['empresa_id' => ['Empresa', 'empresas', 'razon_social', 'Todas las empresas'], 'proyecto_id' => ['Proyecto', 'proyectos', 'titulo', 'Todos los proyectos'], 'profesor_id' => ['Profesor', 'profesores', 'nombre', 'Todos los profesores']] as $clave => [$etiqueta, $coleccion, $texto, $todos])
                    @if(in_array($clave, $campos, true))<div><label class="form-label" for="{{ $clave }}">{{ $etiqueta }}</label><select class="form-select" id="{{ $clave }}" name="{{ $clave }}"><option value="">{{ $todos }}</option>@foreach($opciones->{$coleccion} as $opcion)<option value="{{ $opcion->id }}" @selected((string) ($filtros[$clave] ?? '') === (string) $opcion->id)>{{ $opcion->{$texto} }}</option>@endforeach</select></div>@endif
                @endforeach
                <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('reportes.index', $tipo) }}">Limpiar</a></div>
            </div>
        </form>
        <section class="report-summary" aria-labelledby="resumen-titulo"><h3 class="h6 mb-3" id="resumen-titulo">Totales del conjunto filtrado</h3><dl class="report-totals">@foreach($resumen as $clave => $valor)<div><dt>{{ $etiquetasResumen[$clave] ?? ucfirst(str_replace('_', ' ', $clave)) }}</dt><dd>{{ $valor }}</dd></div>@endforeach</dl><p class="field-hint mb-0">Los totales incluyen todas las páginas. Los datos reflejan las condiciones al consultar.</p></section>
        @if($filas->count())
            <div class="d-none d-lg-block table-responsive"><table class="table report-table mb-0"><caption class="visually-hidden">{{ $tipos[$tipo] }}: página {{ $filas->currentPage() }}</caption><thead><tr>@foreach($columnas as $etiqueta)<th scope="col">{{ $etiqueta }}</th>@endforeach</tr></thead><tbody>@foreach($filas as $fila)<tr>@foreach($columnas as $campo => $etiqueta)<td>@include('reportes._valor')</td>@endforeach</tr>@endforeach</tbody></table></div>
            <div class="d-lg-none">@foreach($filas as $fila)<article class="report-mobile-row"><dl class="account-details mb-0 mt-0">@foreach($columnas as $campo => $etiqueta)<div><dt>{{ $etiqueta }}</dt><dd>@include('reportes._valor')</dd></div>@endforeach</dl></article>@endforeach</div>
        @elseif($filas->total() > 0)
            <div class="empty-state"><h3 class="h5">No hay registros en esta página.</h3><p class="text-body-secondary">Hay registros que coinciden con los filtros. Vuelve a la primera página para consultarlos.</p><a class="btn btn-outline-secondary" href="{{ $filas->url(1) }}">Primera página</a></div>
        @else
            <div class="empty-state"><h3 class="h5">No hay registros con esos filtros.</h3><p class="text-body-secondary">Cambia los filtros o vuelve a consultar el reporte completo.</p><a class="btn btn-outline-secondary" href="{{ route('reportes.index', $tipo) }}">Ver reporte completo</a></div>
        @endif
    </div>
    @if($filas->count())<x-paginacion :pagina="$filas" etiqueta="Páginas del reporte" />@endif
</section>
@endsection

@extends('layouts.app')
@section('title', 'Mis avisos · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Mis avisos</h1><p class="page-description">Consulta los cambios relacionados contigo y continúa los trámites disponibles.</p></div><p class="mb-0"><strong>{{ $noLeidos }}</strong> {{ $noLeidos === 1 ? 'aviso sin leer' : 'avisos sin leer' }}</p></header>
    <x-errores />
    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('avisos.index') }}" aria-label="Filtrar avisos">
            <div class="project-filter-grid">
                <div><label class="form-label" for="buscar">Buscar aviso</label><input class="form-control" id="buscar" name="buscar" type="search" maxlength="150" placeholder="Palabra del mensaje" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div>
                <div><label class="form-label" for="estado">Lectura</label><select class="form-select" id="estado" name="estado">@foreach($estados as $codigo => $etiqueta)<option value="{{ $codigo }}" @selected(($filtros['estado'] ?? 'todos') === $codigo)>{{ $etiqueta }}</option>@endforeach</select></div>
                <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('avisos.index') }}">Limpiar</a></div>
            </div>
        </form>
        <p class="field-hint px-4 py-3 mb-0">{{ $avisos->total() }} {{ $avisos->total() === 1 ? 'aviso encontrado' : 'avisos encontrados' }}</p>
        @forelse($avisos as $item)
            <article class="catalog-list-item"><div class="catalog-list-content"><h2 class="mb-2"><a href="{{ \App\Support\Regreso::enlace(route('avisos.show', $item->id)) }}">{{ $item->mensaje }}</a></h2><p class="field-hint mb-0"><x-fecha-local :valor="$item->fecha" /></p></div><div><span class="status-badge {{ $item->fecha_lectura ? '' : 'status-active' }}">{{ $item->fecha_lectura ? 'Leído' : 'No leído' }}</span></div></article>
        @empty
            @if($avisos->total() > 0)
            <div class="empty-state"><h2 class="h5">No hay avisos en esta página.</h2><p class="text-body-secondary">Hay avisos que coinciden con los filtros. Vuelve a la primera página para consultarlos.</p><a class="btn btn-outline-secondary" href="{{ $avisos->url(1) }}">Primera página</a></div>
            @else
            <div class="empty-state"><h2 class="h5">No hay avisos con esos filtros.</h2><p class="text-body-secondary">Los avisos se guardan cuando ocurren cambios que te afectan. Puedes limpiar la búsqueda para consultar todos.</p><a class="btn btn-outline-secondary" href="{{ route('avisos.index', ['estado' => 'todos']) }}">Ver todos los avisos</a></div>
            @endif
        @endforelse
    </div>
    @if($avisos->count())<x-paginacion :pagina="$avisos" etiqueta="Páginas de avisos" />@endif
</section>
@endsection

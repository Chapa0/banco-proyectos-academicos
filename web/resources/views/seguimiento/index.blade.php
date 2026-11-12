@extends('layouts.app')
@section('title', 'Seguimiento de proyectos · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">{{ in_array($rol, ['alumno','profesor']) ? 'Mis proyectos y vacantes' : 'Seguimiento de proyectos' }}</h1><p class="page-description">{{ in_array($rol, ['alumno','profesor']) ? 'Consulta tus asignaciones y las vacantes permitidas de proyectos pausados.' : 'Consulta los participantes, el estado y el historial de los proyectos.' }}</p></div></header>
    <x-errores />
    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('seguimiento.index') }}" aria-label="Filtrar seguimiento de proyectos"><div class="project-filter-grid"><div><label class="form-label" for="buscar">Buscar proyecto</label><input class="form-control" id="buscar" name="buscar" type="search" maxlength="150" placeholder="Título, palabra clave o empresa" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div><div><label class="form-label" for="estado">Estado</label><select class="form-select" id="estado" name="estado"><option value="">Todos los estados</option>@foreach($estados as $codigo => $etiqueta)<option value="{{ $codigo }}" @selected(($filtros['estado'] ?? '') === $codigo)>{{ $etiqueta }}</option>@endforeach</select></div><div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('seguimiento.index') }}">Limpiar</a></div></div></form>
        <p class="field-hint px-4 py-3 mb-0">{{ $proyectos->total() }} {{ $proyectos->total() === 1 ? 'proyecto encontrado' : 'proyectos encontrados' }}</p>
        @forelse($proyectos as $item)
            <article class="catalog-list-item"><div class="catalog-list-content"><h2 class="mb-2"><a href="{{ route('seguimiento.show', $item->id) }}">{{ $item->titulo }}</a></h2><p class="mb-2">{{ $item->razon_social }}</p>@if($item->vacante)<p class="field-hint mb-0">Vacante para {{ $rol === 'alumno' ? 'alumno' : 'director' }} durante la pausa.</p>@endif</div><div><x-estado-participacion :estado="$item->estado" /><p class="field-hint mt-3 mb-1">{{ $item->alumnos_vigentes }} alumnos asignados</p><p class="field-hint mb-0">{{ $item->directores_vigentes ? 'Con director' : 'Sin director' }}</p></div></article>
        @empty
            <div class="empty-state"><h2 class="h5">No hay proyectos con esos filtros.</h2><p class="text-body-secondary">Limpia la búsqueda para consultar los proyectos disponibles para tu cuenta.</p><a class="btn btn-outline-secondary" href="{{ route('seguimiento.index') }}">Ver todos los proyectos</a></div>
        @endforelse
    </div>
    <x-paginacion :pagina="$proyectos" />
</section>
@endsection

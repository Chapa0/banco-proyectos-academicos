@extends('layouts.app')
@section('title', $tipos[$tipo].' · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">{{ in_array($rol, ['alumno','profesor']) ? ($tipo === 'candidatura' ? 'Mis candidaturas' : 'Mis solicitudes de dirección') : $tipos[$tipo] }}</h1><p class="page-description">{{ $rol === 'empresa' ? 'Revisa los perfiles de los candidatos y registra tu evaluación.' : ($rol === 'administrador' ? 'Consulta las solicitudes y resuelve su asignación con motivo.' : 'Consulta el estado y el historial de tus solicitudes.') }}</p></div>@if(in_array($rol, ['alumno','profesor']))<a class="btn btn-primary" href="{{ route('catalogo.index') }}">Explorar proyectos</a>@endif</header>
    <x-errores />
    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('participacion.index', $tipo) }}" aria-label="Filtrar solicitudes">
            <div class="project-filter-grid">
                <div><label class="form-label" for="buscar">Buscar</label><input class="form-control" id="buscar" name="buscar" type="search" maxlength="150" placeholder="Título del proyecto o empresa" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div>
                <div><label class="form-label" for="estado">Estado</label><select class="form-select" id="estado" name="estado"><option value="">Todos los estados</option>@foreach($estados as $codigo => $etiqueta)<option value="{{ $codigo }}" @selected(($filtros['estado'] ?? '') === $codigo)>{{ $etiqueta }}</option>@endforeach</select></div>
                <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('participacion.index', $tipo) }}">Limpiar</a></div>
            </div>
        </form>
        <p class="field-hint px-4 py-3 mb-0">{{ $solicitudes->total() }} {{ $solicitudes->total() === 1 ? 'solicitud encontrada' : 'solicitudes encontradas' }}</p>
        @forelse($solicitudes as $item)
            <article class="catalog-list-item">
                <div class="catalog-list-content"><h2 class="mb-2"><a href="{{ route('participacion.show', ['tipo' => $tipo, 'solicitud' => $item->id]) }}">{{ $item->titulo }}</a></h2><p class="mb-2">{{ $item->razon_social }}</p>@if(!in_array($rol, ['alumno','profesor']))<p class="mb-2">{{ $item->solicitante_nombre }}</p>@endif<p class="field-hint mb-0">Enviada: <x-fecha-local :valor="$item->fecha_solicitud" /></p></div>
                <div><x-estado-participacion :estado="$item->estado" /></div>
            </article>
        @empty
            <div class="empty-state"><h2 class="h5">No hay solicitudes con esos filtros.</h2><p class="text-body-secondary">Prueba otro estado o limpia la búsqueda.</p><a class="btn btn-outline-secondary" href="{{ route('participacion.index', $tipo) }}">Ver todas las solicitudes</a></div>
        @endforelse
    </div>
    <x-paginacion :pagina="$solicitudes" etiqueta="Páginas de solicitudes" />
</section>
@endsection

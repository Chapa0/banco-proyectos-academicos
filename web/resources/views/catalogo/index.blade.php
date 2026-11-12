@extends('layouts.app')
@section('title', 'Catálogo de proyectos · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Catálogo de proyectos</h1><p class="page-description">Explora los proyectos publicados por las empresas.</p></div></header>
    <x-errores />
    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('catalogo.index') }}" aria-label="Filtrar catálogo de proyectos">
            <div class="catalog-filter-grid">
                <div><label class="form-label" for="buscar">Buscar proyecto</label><input class="form-control" id="buscar" name="buscar" type="search" maxlength="150" placeholder="Título, palabra clave o empresa" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div>
                <div><label class="form-label" for="empresa_id">Empresa</label><select class="form-select" id="empresa_id" name="empresa_id"><option value="">Todas las empresas</option>@foreach($opciones->empresas as $empresa)<option value="{{ $empresa->id }}" @selected((string) ($filtros['empresa_id'] ?? '') === (string) $empresa->id)>{{ $empresa->razon_social }}</option>@endforeach</select></div>
                <div><label class="form-label" for="modalidad">Modalidad</label><select class="form-select" id="modalidad" name="modalidad"><option value="">Todas las modalidades</option>@foreach($opciones->modalidades as $modalidad)<option value="{{ $modalidad }}" @selected(($filtros['modalidad'] ?? '') === $modalidad)>{{ $modalidad }}</option>@endforeach</select></div>
                <div><label class="form-label" for="tipo_habilidad">Tipo de habilidad</label><select class="form-select" id="tipo_habilidad" name="tipo_habilidad"><option value="">Cualquiera</option><option value="dura" @selected(($filtros['tipo_habilidad'] ?? '') === 'dura')>Dura</option><option value="blanda" @selected(($filtros['tipo_habilidad'] ?? '') === 'blanda')>Blanda</option></select></div>
                <div><label class="form-label" for="habilidad_id">Habilidad</label><select class="form-select" id="habilidad_id" name="habilidad_id"><option value="">Todas las habilidades</option>@foreach($opciones->habilidades as $habilidad)<option value="{{ $habilidad->id }}" @selected((string) ($filtros['habilidad_id'] ?? '') === (string) $habilidad->id)>{{ $habilidad->nombre }}</option>@endforeach</select></div>
                <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('catalogo.index') }}">Limpiar</a></div>
            </div>
        </form>
        <p class="field-hint px-4 py-3 mb-0">{{ $proyectos->total() }} {{ $proyectos->total() === 1 ? 'proyecto encontrado' : 'proyectos encontrados' }}</p>
        @forelse($proyectos as $item)
            <article class="catalog-list-item">
                <div class="catalog-list-content">
                    <h2 class="mb-2"><a href="{{ route('catalogo.show', $item->id) }}">{{ $item->titulo }}</a></h2>
                    <p class="mb-2">{{ $item->razon_social }}</p>
                    <p class="catalog-description text-body-secondary">{{ \Illuminate\Support\Str::limit($item->descripcion, 240) }}</p>
                    @if(isset($coincidencias[$item->id]))<x-coincidencia :datos="$coincidencias[$item->id]" compacta class="mb-2" />@endif
                    @if($item->modalidad || $item->duracion_estimada)<p class="field-hint mb-0">{{ $item->modalidad }}@if($item->modalidad && $item->duracion_estimada) · @endif{{ $item->duracion_estimada }}</p>@endif
                </div>
                <dl class="catalog-availability">
                    <div><dt>Plazas de alumnos</dt><dd>{{ $item->plazas_disponibles }} de {{ $item->cupo_maximo_alumnos }} libres</dd></div>
                    @if($rol === 'profesor')<div><dt>Dirección</dt><dd>{{ $item->direccion_disponible ? 'Disponible' : 'Ya asignada' }}</dd></div>@endif
                </dl>
            </article>
        @empty
            <div class="empty-state"><h2 class="h5">No hay proyectos con esos filtros.</h2><p class="text-body-secondary">Prueba otra empresa, modalidad o habilidad.</p><a class="btn btn-outline-secondary" href="{{ route('catalogo.index') }}">Ver todos los proyectos</a></div>
        @endforelse
    </div>
    <x-paginacion :pagina="$proyectos" />
</section>
@endsection

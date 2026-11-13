<div class="surface p-0 overflow-hidden">
    <form class="table-toolbar" method="GET" action="{{ route($administracion ? 'revision.index' : 'proyectos.index') }}" aria-label="Filtrar proyectos">
        <div class="project-filter-grid">
            <div><label class="form-label" for="buscar">{{ $administracion ? 'Título o empresa' : 'Buscar proyecto' }}</label><input class="form-control" type="search" id="buscar" name="buscar" maxlength="100" placeholder="{{ $administracion ? 'Ej. Sistema de inventario o Grupo Norte' : 'Ej. Sistema de inventario' }}" value="{{ is_string($filtros['buscar'] ?? '') ? ($filtros['buscar'] ?? '') : '' }}"></div>
            <div><label class="form-label" for="estado">Estado</label><select class="form-select" id="estado" name="estado"><option value="">Todos</option>@foreach($estados as $valor => $etiqueta)<option value="{{ $valor }}" @selected(($filtros['estado'] ?? '') === $valor)>{{ $etiqueta }}</option>@endforeach</select></div>
            <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route($administracion ? 'revision.index' : 'proyectos.index') }}">Limpiar</a></div>
        </div>
    </form>
    <p class="field-hint px-4 py-3 mb-0">{{ $proyectos->total() }} {{ $proyectos->total() === 1 ? 'proyecto encontrado' : 'proyectos encontrados' }}</p>
    @forelse($proyectos as $item)
        <article class="project-list-item">
            <div class="project-list-content">
                <h2 class="h5 mb-2"><a href="{{ \App\Support\Regreso::enlace(route($administracion ? 'revision.show' : 'proyectos.show', $item->id)) }}">{{ $item->titulo }}</a></h2>
                @if($administracion)<p class="mb-1">{{ $item->razon_social }}</p>@endif
                <p class="field-hint mb-0">Cupo propuesto: {{ $item->cupo_maximo_alumnos ?? 'Sin definir' }}
                    @if($item->numero_revision)
                        · Revisión {{ $item->numero_revision }}
                    @else
                        · Sin enviar
                    @endif
                </p>
            </div>
            <x-estado-proyecto :estado="$item->estado" />
        </article>
    @empty
        <div class="empty-state"><h2 class="h5">No hay proyectos con esos filtros.</h2><p class="text-body-secondary">{{ $administracion ? 'Puedes consultar todos los estados o esperar nuevos envíos.' : 'Prueba otros filtros o crea un proyecto.' }}</p><a class="btn btn-outline-secondary" href="{{ route($administracion ? 'revision.index' : 'proyectos.index', ['estado' => '']) }}">Ver todos los proyectos</a></div>
    @endforelse
</div>
<x-paginacion :pagina="$proyectos" />

@extends('layouts.app')
@section('title', 'Habilidades · Banco de proyectos')
@section('content')
@php
    $formulario = old('habilidad_id');
    $esAlta = $errors->any() && $formulario === null && old('nombre') !== null;
    $usoTexto = function (object $u) {
        $partes = [];
        foreach (['alumnos' => ['alumno', 'alumnos'], 'proyectos' => ['proyecto', 'proyectos'], 'evidencias' => ['evidencia', 'evidencias']] as $clave => [$uno, $varios]) {
            $n = (int) $u->{$clave};
            if ($n > 0) {
                $partes[] = $n.' '.($n === 1 ? $uno : $varios);
            }
        }

        return $partes === [] ? 'Sin uso' : 'Usada por '.implode(' · ', $partes);
    };
@endphp
<section class="container workspace-section">
    <header class="page-header">
        <div>
            <h1 class="page-title">Habilidades</h1>
            <p class="page-description">Catálogo que eligen los alumnos en su perfil y las empresas en sus proyectos. La coincidencia y las recomendaciones dependen de él.</p>
        </div>
    </header>

    <dl class="skill-summary" aria-label="Resumen del catálogo">
        <div><dt>En el catálogo</dt><dd>{{ $resumen->total }}</dd></div>
        <div><dt>Duras</dt><dd>{{ $resumen->duras }}</dd></div>
        <div><dt>Blandas</dt><dd>{{ $resumen->blandas }}</dd></div>
    </dl>

    @error('habilidad')<div class="alert alert-danger" role="alert">{{ $message }}</div>@enderror

    <details class="surface mb-4 skill-create" @if($esAlta || $habilidades->total() === 0) open @endif>
        <summary class="section-heading mb-0">Agregar habilidad</summary>
        <form class="pt-3" method="POST" action="{{ route('habilidades.store') }}" data-submit-label="Agregando…">
            @csrf
            @if($esAlta)<x-errores />@endif
            <div class="row g-3">
                <div class="col-md-6"><x-campo name="nombre" label="Nombre" :value="$esAlta ? old('nombre') : ''" :aislado="! $esAlta" required maxlength="100" placeholder="Ej. Desarrollo móvil con Flutter" info="Usa el nombre más común. No se admite otro igual aunque cambien mayúsculas, acentos o espacios." /></div>
                <div class="col-md-6">
                    <div class="mb-3">
                        <div class="label-row"><label class="form-label" for="tipo-nueva">Tipo</label><span class="required-mark" aria-hidden="true">*</span><x-info tema="Tipo" texto="Dura: conocimiento técnico (un lenguaje, una herramienta). Blanda: habilidad personal (comunicación, liderazgo)." /></div>
                        <select class="form-select" id="tipo-nueva" name="tipo" required>
                            @foreach($tipos as $codigo => $nombre)<option value="{{ $codigo }}" @selected(($esAlta ? old('tipo') : 'dura') === $codigo)>{{ $nombre }}</option>@endforeach
                        </select>
                    </div>
                </div>
            </div>
            <x-campo name="descripcion" label="Descripción" type="textarea" rows="2" :value="$esAlta ? old('descripcion') : ''" :aislado="! $esAlta" maxlength="500" placeholder="Ej. Aplicaciones móviles multiplataforma para Android e iOS." />
            <button class="btn btn-primary" type="submit">Agregar al catálogo</button>
        </form>
    </details>

    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="GET" action="{{ route('habilidades.index') }}" aria-label="Filtrar habilidades">
            <div class="catalog-filter-grid">
                <div><label class="form-label" for="buscar">Buscar</label><input class="form-control" id="buscar" name="buscar" type="search" maxlength="100" placeholder="Ej. python o liderazgo" value="{{ is_string($filtros['buscar'] ?? null) ? $filtros['buscar'] : '' }}"></div>
                <div><label class="form-label" for="tipo">Tipo</label><select class="form-select" id="tipo" name="tipo"><option value="">Todos</option>@foreach($tipos as $codigo => $nombre)<option value="{{ $codigo }}" @selected(($filtros['tipo'] ?? '') === $codigo)>{{ $nombre }}</option>@endforeach</select></div>
                <div class="d-flex flex-wrap gap-2"><button class="btn btn-outline-secondary" type="submit">Buscar</button><a class="btn btn-link" href="{{ route('habilidades.index') }}">Limpiar</a></div>
            </div>
        </form>
        <p class="field-hint px-4 py-3 mb-0">{{ $habilidades->total() }} {{ $habilidades->total() === 1 ? 'habilidad encontrada' : 'habilidades encontradas' }}</p>
        @forelse($habilidades as $h)
            @php $editando = (string) $formulario === (string) $h->id; $enUso = $usoTexto($h->usos) !== 'Sin uso' || (int) $h->usos->instantaneas > 0; @endphp
            <article class="catalog-skill-row" id="habilidad-{{ $h->id }}">
                <div class="skill-row-main">
                    <h2 class="skill-row-title">{{ $h->nombre }} <span class="skill-type">{{ $tipos[$h->tipo] ?? $h->tipo }}</span></h2>
                    @if($h->descripcion)<p class="mb-1 text-body-secondary">{{ $h->descripcion }}</p>@endif
                    <p class="field-hint mb-0">{{ $usoTexto($h->usos) }}@if((int) $h->usos->instantaneas > 0) · en {{ $h->usos->instantaneas }} {{ (int) $h->usos->instantaneas === 1 ? 'versión publicada' : 'versiones publicadas' }}@endif</p>
                    @if(count($h->duplicados))
                        <p class="skill-duplicate mb-0"><strong>Posible duplicado</strong> de {{ collect($h->duplicados)->pluck('nombre')->implode(', ') }}. Revisa cuál conservar; los perfiles y proyectos ya registrados no se mueven solos.</p>
                    @endif
                </div>
                <div class="skill-row-actions">
                    <details class="skill-edit" @if($editando) open @endif>
                        <summary class="btn btn-sm btn-outline-secondary">Editar<span class="visually-hidden"> {{ $h->nombre }}</span></summary>
                        <form class="skill-edit-form" method="POST" action="{{ route('habilidades.update', $h->id) }}" data-submit-label="Guardando…">
                            @csrf @method('PUT')
                            <input type="hidden" name="habilidad_id" value="{{ $h->id }}">
                            @if($editando)<x-errores />@endif
                            <x-campo name="nombre" :input-id="'nombre-'.$h->id" :aislado="! $editando" label="Nombre" :value="$editando ? old('nombre') : $h->nombre" required maxlength="100" />
                            <div class="mb-3"><label class="form-label" for="tipo-{{ $h->id }}">Tipo</label><select class="form-select" id="tipo-{{ $h->id }}" name="tipo">@foreach($tipos as $codigo => $nombre)<option value="{{ $codigo }}" @selected(($editando ? old('tipo') : $h->tipo) === $codigo)>{{ $nombre }}</option>@endforeach</select></div>
                            <x-campo name="descripcion" :input-id="'descripcion-'.$h->id" :aislado="! $editando" label="Descripción" type="textarea" rows="2" :value="$editando ? old('descripcion') : ($h->descripcion ?? '')" maxlength="500" />
                            @if($enUso)<p class="field-hint">Los proyectos ya publicados conservan el nombre con el que se aprobaron.</p>@endif
                            <button class="btn btn-primary btn-sm" type="submit">Guardar cambios</button>
                        </form>
                    </details>
                    @unless($enUso)
                        <form method="POST" action="{{ route('habilidades.destroy', $h->id) }}" data-confirm="¿Eliminar «{{ $h->nombre }}» del catálogo? No se usa en ningún perfil ni proyecto.">
                            @csrf @method('DELETE')
                            <button class="btn btn-sm btn-link text-danger" type="submit">Eliminar<span class="visually-hidden"> {{ $h->nombre }}</span></button>
                        </form>
                    @endunless
                </div>
            </article>
        @empty
            <div class="empty-state"><h2 class="h5">No hay habilidades con esos filtros.</h2><p class="text-body-secondary">Cambia la búsqueda o agrega la habilidad al catálogo.</p><a class="btn btn-outline-secondary" href="{{ route('habilidades.index') }}">Ver todo el catálogo</a></div>
        @endforelse
    </div>
    <x-paginacion :pagina="$habilidades" />
</section>
@endsection

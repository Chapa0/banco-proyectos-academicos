@extends('layouts.app')
@section('title', 'Editar proyecto · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('proyectos.show', $proyecto->id) }}"><i class="bi bi-arrow-left me-2" aria-hidden="true"></i>Volver al proyecto</a>
    <header class="page-header"><div><h1 class="page-title">Editar proyecto</h1><p class="page-description">{{ $proyecto->titulo }}</p></div><x-estado-proyecto :estado="$proyecto->estado" /></header>
    <div class="form-layout"><x-errores />
        @if($ultimaRevision?->decision && $ultimaRevision->estado_revision === 'en_correccion')
            <div class="review-note mb-4"><h2 class="h6">Observaciones del administrador</h2><p class="mb-0 preserve-lines">{{ $ultimaRevision->decision->justificacion }}</p></div>
        @endif
        <form class="surface" method="POST" action="{{ route('proyectos.update', $proyecto->id) }}" data-submit-label="Guardando…">
            @csrf @method('PUT')
            <input type="hidden" name="version" value="{{ is_string(old('version', $proyecto->version)) ? old('version', $proyecto->version) : '' }}">
            @include('proyectos._campos')
            <div class="form-actions"><button type="submit" class="btn btn-primary">Guardar cambios</button><a class="btn btn-outline-secondary" href="{{ route('proyectos.show', $proyecto->id) }}">Cancelar</a></div>
        </form>
    </div>
</section>
@endsection

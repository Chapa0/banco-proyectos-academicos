@extends('layouts.app')
@section('title', 'Proyecto · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <x-volver :defecto="route('proyectos.index')" etiqueta="Volver a mis proyectos" />
    <header class="page-header"><div><h1 class="page-title">{{ $proyecto->titulo }}</h1><p class="page-description">{{ $proyecto->empresa->razon_social }}</p></div><x-estado-proyecto :estado="$proyecto->estado" /></header>
    @if(isset($lineaTiempo))<x-linea-estado :pasos="$lineaTiempo" titulo="Avance del proyecto" />@endif
    <x-errores />
    @if($ultimaRevision?->decision && $ultimaRevision->estado_revision === 'en_correccion')
        <div class="review-note mb-4"><h2 class="h6">Observaciones del administrador</h2><p class="mb-0 preserve-lines">{{ $ultimaRevision->decision->justificacion }}</p></div>
    @endif
    @if($puedeEnviar)
        <div class="project-actions mb-4">
            <a href="{{ route('proyectos.edit', $proyecto->id) }}" class="btn btn-outline-secondary">Editar proyecto</a>
            <form method="POST" action="{{ route('proyectos.enviar', $proyecto->id) }}" data-submit-label="Enviando…">
                @csrf
                <input type="hidden" name="version" value="{{ is_string(old('version', $proyecto->version)) ? old('version', $proyecto->version) : '' }}">
                <button type="submit" class="btn btn-primary">Enviar a revisión</button>
            </form>
            <p class="field-hint mb-0 w-100">Al enviar se conserva esta versión. No podrás editarla mientras esté en revisión.</p>
        </div>
    @else
        <p class="field-hint mb-4">{{ $proyecto->estado === 'en_revision' ? 'El administrador está revisando este envío. La resolución aparecerá en el historial.' : 'El contenido de este proyecto ya no admite cambios.' }}</p>
    @endif
    <section class="surface" aria-labelledby="contenido-titulo"><h2 id="contenido-titulo" class="section-heading">Contenido del proyecto</h2><x-contenido-proyecto :contenido="$proyecto" :habilidades="$proyecto->habilidades" /></section>
    @include('proyectos._historial')
</section>
@endsection

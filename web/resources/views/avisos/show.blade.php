@extends('layouts.app')
@section('title', 'Aviso · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('avisos.index') }}">Volver a mis avisos</a>
    <header class="page-header"><div><h1 class="page-title">Aviso</h1><p class="page-description"><x-fecha-local :valor="$aviso->fecha" /></p></div><span class="status-badge {{ $aviso->fecha_lectura ? '' : 'status-active' }}">{{ $aviso->fecha_lectura ? 'Leído' : 'No leído' }}</span></header>
    <div class="form-layout">
        <x-errores />
        <section class="surface" aria-labelledby="mensaje-titulo"><h2 class="section-heading preserve-lines" id="mensaje-titulo">{{ $aviso->mensaje }}</h2>
            @if($aviso->fecha_lectura)<p class="field-hint">Primera lectura: <x-fecha-local :valor="$aviso->fecha_lectura" /></p>@endif
            @if($enlace)<p class="mb-4"><a class="d-inline-flex align-items-center min-touch" href="{{ $enlace['url'] }}">{{ $enlace['texto'] }}</a></p>@else<p class="text-body-secondary">No hay información adicional disponible para este aviso.</p>@endif
            @if(! $aviso->fecha_lectura)<form method="POST" action="{{ route('avisos.leer', $aviso->id) }}" data-submit-label="Registrando lectura…">@csrf<button class="btn btn-primary" type="submit">Marcar como leído</button></form>@endif
        </section>
    </div>
</section>
@endsection

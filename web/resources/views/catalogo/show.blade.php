@extends('layouts.app')
@section('title', 'Proyecto publicado · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <x-volver :defecto="route('catalogo.index')" etiqueta="Volver al catálogo" />
    <header class="page-header"><div class="page-header-with-logo"><x-avatar :imagen="$logo ?? null" :nombre="$proyecto->empresa->razon_social" tamano="lg" logo /><div><h1 class="page-title">{{ $proyecto->titulo }}</h1><p class="page-description">{{ $proyecto->empresa->razon_social }}</p></div></div><span class="status-badge status-active">Publicado</span></header>
    <div class="row g-4">
        <div class="col-lg-8"><section class="surface" aria-labelledby="contenido-titulo"><h2 class="section-heading" id="contenido-titulo">Sobre el proyecto</h2><x-contenido-proyecto :contenido="$proyecto" :habilidades="$proyecto->habilidades" cupo-label="Cupo validado de alumnos" /></section></div>
        <div class="col-lg-4">
            @if($coincidencia)<section class="surface mb-4" aria-labelledby="coincidencia-titulo"><h2 class="section-heading" id="coincidencia-titulo">Tus habilidades</h2><x-coincidencia :datos="$coincidencia" class="mb-3" /><p class="field-hint mb-0">Es una guía según las habilidades de tu perfil; la empresa evalúa cada candidatura completa. <a href="{{ \App\Support\Regreso::enlace(route('perfil.edit')) }}">Actualizar mis habilidades</a></p></section>@endif
            <section class="surface" aria-labelledby="disponibilidad-titulo">
                <h2 class="section-heading" id="disponibilidad-titulo">Disponibilidad</h2>
                <dl class="account-details mb-0"><div><dt>Plazas de alumnos</dt><dd>{{ $proyecto->disponibilidad->plazas_disponibles }} de {{ $proyecto->cupo_maximo_alumnos }} libres</dd></div>@if($rol === 'profesor')<div><dt>Dirección</dt><dd>{{ $proyecto->disponibilidad->direccion_disponible ? 'Disponible' : 'Ya asignada' }}</dd></div>@endif</dl>
                <p class="field-hint mb-0 mt-3">La disponibilidad puede cambiar mientras consultas el catálogo.</p>
                @can('participar')<a class="btn btn-primary mt-3" href="{{ \App\Support\Regreso::enlace(route('participacion.create', $proyecto->id)) }}">{{ $rol === 'alumno' ? 'Presentar candidatura' : 'Solicitar dirección' }}</a>@endcan
            </section>
            <section class="surface account-summary mt-4" aria-labelledby="empresa-titulo">
                <h2 class="section-heading" id="empresa-titulo">Empresa</h2>
                <p class="mb-2">{{ $proyecto->empresa->razon_social }}</p>
                @if($proyecto->empresa->sector)<p class="field-hint mb-3">{{ $proyecto->empresa->sector }}</p>@endif
                <dl class="account-details mb-0">
                    @foreach(['contacto_nombre' => 'Contacto', 'contacto_correo' => 'Correo de contacto', 'contacto_telefono' => 'Teléfono'] as $campo => $etiqueta)
                        @if($proyecto->empresa->{$campo})<div><dt>{{ $etiqueta }}</dt><dd>{{ $proyecto->empresa->{$campo} }}</dd></div>@endif
                    @endforeach
                </dl>
            </section>
        </div>
    </div>
</section>
@endsection

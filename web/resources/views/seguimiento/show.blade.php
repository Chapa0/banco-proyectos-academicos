@extends('layouts.app')
@section('title', 'Seguimiento del proyecto · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('seguimiento.index') }}">Volver al seguimiento</a>
    <header class="page-header"><div><h1 class="page-title">{{ $detalle->proyecto->titulo }}</h1><p class="page-description">{{ $detalle->empresa->razon_social }}</p></div><x-estado-participacion :estado="$detalle->proyecto->estado" /></header>
    <x-errores />
    <div class="row g-4">
        <div class="col-lg-8 {{ $detalle->vacante ? 'order-2 order-lg-1' : '' }}">
            <section class="surface" aria-labelledby="contenido-titulo"><h2 class="section-heading" id="contenido-titulo">Sobre el proyecto</h2><x-contenido-proyecto :contenido="$detalle->proyecto" :habilidades="$detalle->proyecto->habilidades" cupo-label="Cupo de alumnos" /></section>
            @include('seguimiento._asignaciones')
            @if(! $detalle->vacante || count($detalle->historial))<section class="surface mt-4" aria-labelledby="historial-titulo"><h2 class="section-heading" id="historial-titulo">Historial del proyecto</h2>@forelse($detalle->historial as $evento)<article class="revision-entry"><p class="fw-semibold mb-2">{{ ucfirst(str_replace('_',' ', $evento->operacion)) }}</p><p class="field-hint mb-1"><x-fecha-local :valor="$evento->fecha" /> · {{ $evento->actor_nombre }}</p>@if($evento->transicion)<p>{{ str_replace(['_', '->'], [' ', ' → '], $evento->transicion) }}</p>@endif @if($evento->motivo)<p class="preserve-lines mb-0">{{ $evento->motivo }}</p>@endif</article>@empty<p class="text-body-secondary mb-0">No hay eventos disponibles para tu consulta.</p>@endforelse</section>@endif
        </div>
        <div class="col-lg-4 {{ $detalle->vacante ? 'order-1 order-lg-2' : '' }}">
            <section class="surface" aria-labelledby="acciones-titulo"><h2 class="section-heading" id="acciones-titulo">Participación y estado</h2>
                @if(in_array('participar', $detalle->acciones, true))<p>{{ $detalle->vacante ? 'El proyecto admite solicitudes para reponer al participante faltante. La reanudación requiere confirmación administrativa.' : 'Puedes solicitar tu participación en este proyecto.' }}</p><a class="btn btn-primary" href="{{ route('participacion.create', $detalle->proyecto->id) }}">{{ $rol === 'alumno' ? 'Presentar candidatura' : 'Solicitar dirección' }}</a>@endif
                @foreach(['iniciar' => 'Confirmar inicio', 'reanudar' => 'Confirmar reanudación'] as $accion => $etiqueta)
                    @if(in_array($accion, $detalle->acciones, true))<form class="mb-3" method="POST" action="{{ route('seguimiento.operar', ['proyecto' => $detalle->proyecto->id, 'accion' => $accion]) }}" data-submit-label="Confirmando…">@csrf @include('participacion._version', ['version' => $detalle->version])<p class="field-hint">Se comprobarán de nuevo la publicación, los participantes, el cupo y las cargas.</p><button class="btn btn-primary" type="submit">{{ $etiqueta }}</button></form>@endif
                @endforeach
                @foreach(['finalizar' => 'Finalizar proyecto', 'cancelar' => 'Cancelar proyecto'] as $accion => $etiqueta)
                    @if(in_array($accion, $detalle->acciones, true))<details class="revision-entry" @if($errors->has('motivo') && old('asignacion_id') === null) open @endif><summary>{{ $etiqueta }}</summary><form class="pt-3" method="POST" action="{{ route('seguimiento.operar', ['proyecto' => $detalle->proyecto->id, 'accion' => $accion]) }}" data-submit-label="Cerrando proyecto…">@csrf @include('participacion._version', ['version' => $detalle->version])<p>Se cerrarán coordinadamente las asignaciones y solicitudes pendientes, liberando las reservas. El historial se conserva. El proyecto cerrado no se reabre.</p><x-campo name="motivo" :input-id="'motivo-'.$accion" label="Motivo del cierre" type="textarea" maxlength="1000" required placeholder="Ej. El proyecto concluyó y la empresa entregó su conformidad." info="Queda registrado en el historial del proyecto. El cierre no se puede deshacer." /><button class="btn btn-outline-danger" type="submit">{{ $etiqueta }}</button></form></details>@endif
                @endforeach
                <dl class="account-details mb-0"><div><dt>Plazas de alumnos disponibles</dt><dd>{{ $detalle->disponibilidad->plazas_disponibles }}</dd></div><div><dt>Dirección</dt><dd>{{ $detalle->disponibilidad->direccion_disponible ? 'Sin director vigente' : 'Con director vigente' }}</dd></div></dl>
            </section>
            @if(in_array($rol, ['empresa','administrador']))<section class="surface mt-4"><h2 class="section-heading">Buscar solicitudes</h2><div class="d-flex flex-wrap gap-2"><a class="btn btn-outline-secondary" href="{{ route('participacion.index', ['tipo' => 'candidatura', 'buscar' => $detalle->proyecto->titulo]) }}">Candidaturas</a>@if($rol === 'administrador')<a class="btn btn-outline-secondary" href="{{ route('participacion.index', ['tipo' => 'direccion', 'buscar' => $detalle->proyecto->titulo]) }}">Solicitudes de dirección</a>@endif</div></section>@endif
            <section class="surface account-summary mt-4" aria-labelledby="empresa-titulo"><h2 class="section-heading" id="empresa-titulo">Empresa</h2><p>{{ $detalle->empresa->razon_social }}</p><dl class="account-details mb-0">@foreach(['sector' => 'Sector', 'contacto_nombre' => 'Contacto', 'contacto_correo' => 'Correo de contacto', 'contacto_telefono' => 'Teléfono de contacto'] as $campo => $etiqueta)@if(isset($detalle->empresa->{$campo}) && $detalle->empresa->{$campo} !== '')<div><dt>{{ $etiqueta }}</dt><dd>{{ $detalle->empresa->{$campo} }}</dd></div>@endif @endforeach</dl></section>
        </div>
    </div>
</section>
@endsection

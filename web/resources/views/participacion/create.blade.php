@extends('layouts.app')
@section('title', ($tipo === 'candidatura' ? 'Presentar candidatura' : 'Solicitar dirección').' · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <x-volver :defecto="route($contexto->proyecto->estado === 'publicado' ? 'catalogo.show' : 'seguimiento.show', $contexto->proyecto->id)" etiqueta="Volver al proyecto" />
    <header class="page-header"><div><h1 class="page-title">{{ $tipo === 'candidatura' ? 'Presentar candidatura' : 'Solicitar dirección' }}</h1><p class="page-description">{{ $contexto->proyecto->titulo }} · {{ $contexto->proyecto->razon_social }}</p></div></header>
    <div class="row g-4">
        <div class="col-lg-7">
            <x-errores />
            @if(in_array('enviar', $contexto->acciones, true))
                <form class="surface" method="POST" action="{{ route('participacion.store', $contexto->proyecto->id) }}" data-submit-label="Enviando solicitud…">
                    @csrf
                    @include('participacion._version', ['version' => $contexto->version])
                    @if($tipo === 'direccion')
                        <x-campo name="experiencia_aplicable" label="Experiencia aplicable al proyecto" type="textarea" maxlength="10000" required placeholder="Ej. He impartido Bases de datos por 5 años y dirigí dos sistemas de inventario con empresas locales." help="Explica qué conocimientos y experiencia aportarías como director." />
                        <x-campo name="justificacion" label="Justificación de la solicitud" type="textarea" maxlength="10000" required placeholder="Ej. El proyecto coincide con mi especialidad y tengo disponibilidad de 4 horas semanales para asesorías." info="Por qué eres una buena opción para dirigir este proyecto. La administración lo revisa al resolver tu solicitud." />
                    @else
                        <p>La empresa podrá consultar tu perfil académico y tus habilidades para evaluar esta candidatura.</p>
                        <p class="field-hint">Puedes tener hasta tres candidaturas activas. El envío no reserva una plaza ni crea una asignación.</p>
                    @endif
                    <div class="form-actions"><button class="btn btn-primary" type="submit">{{ $tipo === 'candidatura' ? 'Enviar candidatura' : 'Enviar solicitud de dirección' }}</button><a class="btn btn-outline-secondary" href="{{ route('participacion.index', $tipo) }}">Ver mis solicitudes</a></div>
                </form>
            @else
                <section class="surface" aria-labelledby="no-disponible">
                    <h2 class="section-heading" id="no-disponible">No puedes enviar esta solicitud ahora</h2>
                    @if(! $contexto->perfil_completo)
                        <p>Completa tu perfil académico antes de participar.</p><a class="btn btn-primary" href="{{ \App\Support\Regreso::enlace(route('perfil.edit')) }}">Completar mi perfil</a>
                    @elseif($contexto->existente)
                        <p>Ya tienes una solicitud activa para este proyecto.</p><a class="btn btn-primary" href="{{ \App\Support\Regreso::enlace(route('participacion.show', ['tipo' => $tipo, 'solicitud' => $contexto->existente->id])) }}">Consultar solicitud</a>
                    @elseif($tipo === 'candidatura' && $contexto->activas >= 3)
                        <p>Ya tienes tres candidaturas activas. Revisa tus solicitudes antes de presentar otra.</p><a class="btn btn-primary" href="{{ route('participacion.index', $tipo) }}">Mis candidaturas</a>
                    @else
                        <p>El proyecto no admite nuevas solicitudes de este tipo en su estado actual.</p><a class="btn btn-outline-secondary" href="{{ route('catalogo.index') }}">Volver al catálogo</a>
                    @endif
                </section>
            @endif
        </div>
        <div class="col-lg-5"><section class="surface" aria-labelledby="antes-enviar"><h2 class="section-heading" id="antes-enviar">Antes de enviar</h2><p>Revisa tus datos académicos y de contacto. Puedes cancelar una solicitud pendiente antes de su asignación.</p><a href="{{ \App\Support\Regreso::enlace(route('perfil.edit')) }}">Revisar mi perfil</a><dl class="account-details mb-0"><div><dt>Estado del proyecto</dt><dd><x-estado-participacion :estado="$contexto->proyecto->estado" /></dd></div>@if($tipo === 'candidatura')<div><dt>Candidaturas activas</dt><dd>{{ $contexto->activas }} de 3</dd></div>@endif</dl></section></div>
    </div>
</section>
@endsection

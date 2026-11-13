@extends('layouts.app')
@section('title', 'Mi espacio · Banco de proyectos')
@section('content')
<section class="container workspace-section" aria-labelledby="panel-titulo">
    <header class="page-header">
        <div>
            <h1 id="panel-titulo" class="page-title">{{ ['administrador' => 'Administración', 'empresa' => 'Área de empresas', 'alumno' => 'Área de alumnos', 'profesor' => 'Área de profesores'][$usuario->rol_principal] }}</h1>
            <p class="page-description">Hola, {{ $usuario->nombre }}.</p>
        </div>
    </header>
    <section class="surface pending-section mb-4" aria-labelledby="pendientes-titulo">
        <h2 id="pendientes-titulo" class="section-heading">Pendientes</h2>
        @if($pendientes === [])
            <p class="pending-empty mb-0">No tienes tareas pendientes por ahora.</p>
        @else
            <ul class="pending-list">
                @foreach($pendientes as $pendiente)
                    <li class="pending-item" data-pendiente="{{ $pendiente['clave'] }}">
                        <span class="pending-count" aria-hidden="true">{{ $pendiente['cantidad'] }}</span>
                        <span class="pending-text"><span class="visually-hidden">{{ $pendiente['cantidad'] }} </span>{{ $pendiente['texto'] }}</span>
                        <a class="btn btn-sm btn-outline-secondary" href="{{ \App\Support\Regreso::enlace($pendiente['url']) }}">{{ $pendiente['accion'] }}<span class="visually-hidden">: {{ $pendiente['texto'] }}</span></a>
                    </li>
                @endforeach
            </ul>
        @endif
    </section>
    <x-recomendados :proyectos="$recomendados ?? []" :logos="$logos ?? []" class="surface mb-4" />
    <div class="row g-4">
        @can('administrar-cuentas')
            <div class="col-lg-7">
                <section class="surface panel-section" aria-labelledby="cuentas-titulo">
                    <h2 id="cuentas-titulo" class="section-heading">Gestión del sistema</h2>
                    <p>Revisa los proyectos enviados por las empresas y administra el acceso de los participantes.</p>
                    <div class="d-flex flex-wrap gap-3">
                        <a href="{{ route('revision.index') }}" class="btn btn-primary">Revisar proyectos</a>
                        <a href="{{ route('cuentas.index') }}" class="btn btn-outline-secondary">Administrar cuentas</a>
                        <a href="{{ route('habilidades.index') }}" class="btn btn-outline-secondary">Catálogo de habilidades</a>
                        <a href="{{ route('participacion.index', 'candidatura') }}" class="btn btn-outline-secondary">Candidaturas</a>
                        <a href="{{ route('participacion.index', 'direccion') }}" class="btn btn-outline-secondary">Solicitudes de dirección</a>
                        <a href="{{ route('seguimiento.index') }}" class="btn btn-outline-secondary">Seguimiento</a>
                        <a href="{{ route('reportes.index') }}" class="btn btn-outline-secondary">Reportes</a>
                    </div>
                </section>
            </div>
        @endcan
        @can('gestionar-proyectos')
            <div class="col-lg-7">
                <section class="surface panel-section" aria-labelledby="proyectos-titulo">
                    <h2 id="proyectos-titulo" class="section-heading">Proyectos de la empresa</h2>
                    <p>Prepara tus propuestas y consulta el estado de los envíos y las observaciones del administrador.</p>
                    <div class="d-flex flex-wrap gap-3">
                        <a href="{{ route('proyectos.index') }}" class="btn btn-primary">Mis proyectos</a>
                        <a href="{{ route('empresa.edit') }}" class="btn btn-outline-secondary">Datos de empresa</a>
                        <a href="{{ route('participacion.index', 'candidatura') }}" class="btn btn-outline-secondary">Evaluar candidatos</a>
                        <a href="{{ route('seguimiento.index') }}" class="btn btn-outline-secondary">Seguimiento</a>
                    </div>
                </section>
            </div>
        @endcan
        @can('gestionar-perfil')
            <div class="col-lg-7">
                <section class="surface panel-section" aria-labelledby="perfil-proyectos-titulo">
                    <h2 id="perfil-proyectos-titulo" class="section-heading">Proyectos y perfil</h2>
                    <p>Explora las propuestas publicadas y mantén tus datos académicos actualizados.</p>
                    @if($avancePerfil ?? null)<x-avance-perfil :avance="$avancePerfil" enlazar class="mb-4" />@endif
                    <div class="d-flex flex-wrap gap-3">
                        <a href="{{ route('catalogo.index') }}" class="btn btn-primary">Explorar proyectos</a>
                        <a href="{{ route('perfil.edit') }}" class="btn btn-outline-secondary">Mi perfil</a>
                        <a href="{{ route('participacion.index', $usuario->rol_principal === 'alumno' ? 'candidatura' : 'direccion') }}" class="btn btn-outline-secondary">{{ $usuario->rol_principal === 'alumno' ? 'Mis candidaturas' : 'Mis solicitudes' }}</a>
                        <a href="{{ route('seguimiento.index') }}" class="btn btn-outline-secondary">Mis proyectos y vacantes</a>
                    </div>
                </section>
            </div>
        @endcan
        <div class="col-lg-5">
            <section class="surface panel-section" aria-labelledby="mi-cuenta-titulo">
                <h2 id="mi-cuenta-titulo" class="section-heading">Tu cuenta</h2>
                <dl class="account-details">
                    <div><dt>Nombre</dt><dd>{{ $usuario->nombre }}</dd></div>
                    <div><dt>Correo</dt><dd>{{ $usuario->correo_normalizado }}</dd></div>
                    <div><dt>Rol</dt><dd>{{ ['administrador' => 'Administrador', 'empresa' => 'Empresa', 'alumno' => 'Alumno', 'profesor' => 'Profesor'][$usuario->rol_principal] }}</dd></div>
                </dl>
                <a href="{{ route('clave.edit') }}" class="btn btn-outline-secondary">Cambiar contraseña</a>
                @can('consultar-avisos')<a href="{{ route('avisos.index') }}" class="btn btn-outline-secondary mt-2">Mis avisos</a>@endcan
            </section>
        </div>
    </div>
</section>
@endsection

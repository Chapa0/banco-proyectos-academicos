@extends('layouts.app')
@section('title', 'Cuentas | Banco de proyectos')

@section('content')
@php($roles = ['administrador' => 'Administrador', 'empresa' => 'Empresa', 'alumno' => 'Alumno', 'profesor' => 'Profesor'])
<section class="container workspace-section">
    <header class="page-header">
        <div>
            <h1 class="page-title">Cuentas</h1>
            <p class="page-description">Consulta los accesos y administra las cuentas del sistema.</p>
        </div>
        <a class="btn btn-primary" href="{{ route('cuentas.create') }}">Crear cuenta</a>
    </header>

    @include('cuentas._errores')

    <div class="surface p-0 overflow-hidden">
        <form class="table-toolbar" method="get" action="{{ route('cuentas.index') }}" aria-label="Filtrar cuentas">
            <div class="filter-grid">
                <div>
                    <label class="form-label" for="buscar">Nombre o correo</label>
                    <input class="form-control" type="search" name="buscar" id="buscar" value="{{ is_string($filtros['buscar'] ?? null) ? $filtros['buscar'] : '' }}" maxlength="100" placeholder="Ej. López o maria@ejemplo.com"> 
                </div>
                <div>
                    <label class="form-label" for="rol">Rol</label>
                    <select class="form-select" name="rol" id="rol">
                        <option value="">Todos</option>
                        @foreach($roles as $value => $label)<option value="{{ $value }}" @selected(($filtros['rol'] ?? '') === $value)>{{ $label }}</option>@endforeach
                    </select>
                </div>
                <div>
                    <label class="form-label" for="estado">Estado</label>
                    <select class="form-select" name="estado" id="estado">
                        <option value="">Todos</option>
                        <option value="activa" @selected(($filtros['estado'] ?? '') === 'activa')>Activa</option>
                        <option value="inactiva" @selected(($filtros['estado'] ?? '') === 'inactiva')>Inactiva</option>
                    </select>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    <button class="btn btn-outline-secondary" type="submit">Buscar</button>
                    <a class="btn btn-link" href="{{ route('cuentas.index') }}">Limpiar</a>
                </div>
            </div>
        </form>

        <div class="px-3 px-md-4 py-3 border-top">
            <p class="small text-body-secondary mb-0">{{ $cuentas->total() }} {{ $cuentas->total() === 1 ? 'cuenta encontrada' : 'cuentas encontradas' }}</p>
        </div>
        @if($cuentas->count())
            <div class="table-responsive d-none d-md-block">
                <table class="table account-table align-middle mb-0">
                    <caption class="visually-hidden">Cuentas administradas en el banco de proyectos</caption>
                    <thead><tr><th scope="col">Nombre</th><th scope="col">Correo</th><th scope="col">Rol</th><th scope="col">Estado</th><th scope="col"><span class="visually-hidden">Acciones</span></th></tr></thead>
                    <tbody>
                        @foreach($cuentas as $cuenta)
                            <tr>
                                <th scope="row">{{ $cuenta->nombre }}@if($cuenta->razon_social)<span class="d-block small fw-normal text-body-secondary">{{ $cuenta->razon_social }}</span>@endif</th>
                                <td>{{ $cuenta->correo_normalizado }}</td>
                                <td>{{ $roles[$cuenta->rol_principal] ?? $cuenta->rol_principal }}</td>
                                <td><span class="status-badge {{ $cuenta->estado_cuenta === 'activa' ? 'status-active' : 'status-inactive' }}">{{ $cuenta->estado_cuenta === 'activa' ? 'Activa' : 'Inactiva' }}</span></td>
                                <td><a class="btn btn-outline-secondary" href="{{ \App\Support\Regreso::enlace(route('cuentas.edit', $cuenta->id)) }}" aria-label="Administrar cuenta de {{ $cuenta->nombre }}">Administrar</a></td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
            <ul class="account-mobile-list list-unstyled d-md-none mb-0">
                @foreach($cuentas as $cuenta)
                    <li class="account-mobile-item border-top p-3">
                        <h2 class="h6 mb-1 text-break">{{ $cuenta->nombre }}</h2>
                        @if($cuenta->razon_social)<p class="small text-body-secondary mb-1 text-break">{{ $cuenta->razon_social }}</p>@endif
                        <p class="small mb-3 text-break">{{ $cuenta->correo_normalizado }}</p>
                        <div class="d-flex flex-wrap align-items-center justify-content-between gap-3">
                            <div>
                                <p class="small mb-1">{{ $roles[$cuenta->rol_principal] ?? $cuenta->rol_principal }}</p>
                                <span class="status-badge {{ $cuenta->estado_cuenta === 'activa' ? 'status-active' : 'status-inactive' }}">{{ $cuenta->estado_cuenta === 'activa' ? 'Activa' : 'Inactiva' }}</span>
                            </div>
                            <a class="btn btn-outline-secondary" href="{{ \App\Support\Regreso::enlace(route('cuentas.edit', $cuenta->id)) }}" aria-label="Administrar cuenta de {{ $cuenta->nombre }}">Administrar</a>
                        </div>
                    </li>
                @endforeach
            </ul>
        @else
            <div class="empty-state text-center px-3 py-5 border-top">
                <h2 class="h5">No hay cuentas con esos filtros.</h2>
                <p class="text-body-secondary mb-3">Prueba con otro nombre, correo, rol o estado.</p>
                <a class="btn btn-outline-secondary" href="{{ route('cuentas.index') }}">Ver todas las cuentas</a>
            </div>
        @endif
    </div>

    @if($cuentas->hasPages())
        <nav class="d-flex flex-wrap align-items-center justify-content-between gap-3 mt-4" aria-label="Páginas de cuentas">
            <p class="small text-body-secondary mb-0">Página {{ $cuentas->currentPage() }} de {{ $cuentas->lastPage() }}</p>
            <ul class="pagination mb-0">
                @if($cuentas->onFirstPage())<li class="page-item disabled" aria-disabled="true"><span class="page-link">Anterior</span></li>
                @else<li class="page-item"><a class="page-link" href="{{ $cuentas->previousPageUrl() }}" rel="prev">Anterior</a></li>@endif
                @if($cuentas->hasMorePages())<li class="page-item"><a class="page-link" href="{{ $cuentas->nextPageUrl() }}" rel="next">Siguiente</a></li>
                @else<li class="page-item disabled" aria-disabled="true"><span class="page-link">Siguiente</span></li>@endif
            </ul>
        </nav>
    @endif
</section>
@endsection

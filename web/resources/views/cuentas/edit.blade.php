@extends('layouts.app')
@section('title', 'Administrar cuenta | Banco de proyectos')

@section('content')
@php
    $roles = ['administrador' => 'Administrador', 'empresa' => 'Empresa', 'alumno' => 'Alumno', 'profesor' => 'Profesor'];
    $anterior = old('version_acceso', $cuenta->version_acceso);
    $version = is_scalar($anterior) && ctype_digit((string) $anterior) ? (string) $anterior : (string) $cuenta->version_acceso;
@endphp
<section class="container workspace-section">
    <a class="back-link" href="{{ route('cuentas.index') }}">Volver a cuentas</a>
    <header class="page-header mt-3">
        <div>
            <h1 class="page-title">Administrar cuenta</h1>
            <p class="page-description text-break">{{ $cuenta->nombre }}</p>
        </div>
        <span class="status-badge {{ $cuenta->estado_cuenta === 'activa' ? 'status-active' : 'status-inactive' }}">{{ $cuenta->estado_cuenta === 'activa' ? 'Activa' : 'Inactiva' }}</span>
    </header>
    <dl class="account-summary d-flex flex-wrap gap-3 gap-md-5 mb-4">
        <div><dt>Correo de acceso</dt><dd class="text-break mb-0">{{ $cuenta->correo_normalizado }}</dd></div>
        <div><dt>Rol</dt><dd class="mb-0">{{ $roles[$cuenta->rol_principal] ?? $cuenta->rol_principal }}</dd></div>
        @if($cuenta->razon_social)<div><dt>Empresa</dt><dd class="text-break mb-0">{{ $cuenta->razon_social }}</dd></div>@endif
    </dl>
    @if($cuenta->requiere_cambio_clave)<p class="field-hint mb-4">Tiene pendiente cambiar su contraseña al entrar.</p>@endif
    @include('cuentas._errores')

    <div class="row g-4">
        <div class="col-lg-6">
            <section class="surface p-3 p-md-4" aria-labelledby="datos-titulo">
                <h2 class="section-heading" id="datos-titulo">Datos de acceso</h2>
                <p class="field-hint mb-4">El rol permanece como fue asignado al crear la cuenta. Completa todos los campos para guardar.</p>
                <form method="post" action="{{ route('cuentas.update', $cuenta->id) }}" data-submit-label="Guardando…">
                    @csrf @method('PUT')
                    <input type="hidden" name="version_acceso" value="{{ $version }}">
                    <input type="hidden" name="_formulario" value="datos">
                    @include('cuentas._campo', ['name' => 'nombre', 'id' => 'datos-nombre', 'label' => 'Nombre completo', 'valorInicial' => $cuenta->nombre, 'maxlength' => 150, 'autocomplete' => 'name', 'placeholder' => 'Ej. María Fernanda López Ruiz', 'contexto' => 'datos'])
                    @include('cuentas._campo', ['name' => 'correo', 'id' => 'datos-correo', 'label' => 'Correo de acceso', 'type' => 'email', 'valorInicial' => $cuenta->correo_normalizado, 'maxlength' => 254, 'placeholder' => 'nombre@ejemplo.com', 'info' => 'Si lo cambias, la persona deberá usar el nuevo correo para iniciar sesión. Avísale del cambio.', 'autocomplete' => 'email', 'contexto' => 'datos'])
                    @include('cuentas._campo', ['name' => 'motivo', 'id' => 'datos-motivo', 'label' => 'Motivo del cambio', 'type' => 'textarea', 'maxlength' => 1000, 'placeholder' => 'Ej. Corrección del apellido solicitada por la persona.', 'info' => 'Queda registrado en el historial de auditoría junto con tu nombre y la fecha. Sé breve y concreto.', 'contexto' => 'datos'])
                    <div class="form-actions"><button class="btn btn-primary" type="submit">Guardar datos</button></div>
                </form>
            </section>
        </div>
        <div class="col-lg-6">
            <section class="surface p-3 p-md-4" aria-labelledby="clave-titulo">
                <h2 class="section-heading" id="clave-titulo">Restablecer contraseña</h2>
                <p class="field-hint mb-4">Se cerrarán las sesiones anteriores. La persona deberá cambiar la contraseña temporal al volver a entrar. Completa todos los campos.</p>
                <form method="post" action="{{ route('cuentas.clave', $cuenta->id) }}" data-submit-label="Restableciendo…">
                    @csrf
                    <input type="hidden" name="version_acceso" value="{{ $version }}">
                    <input type="hidden" name="_formulario" value="clave">
                    @include('cuentas._clave', ['prefijo' => 'restablecer', 'contexto' => 'clave'])
                    @include('cuentas._campo', ['name' => 'motivo', 'id' => 'clave-motivo', 'label' => 'Motivo del restablecimiento', 'type' => 'textarea', 'maxlength' => 1000, 'placeholder' => 'Ej. La persona olvidó su contraseña y lo solicitó por correo institucional.', 'info' => 'Queda registrado en el historial de auditoría junto con tu nombre y la fecha.', 'contexto' => 'clave'])
                    <div class="form-actions"><button class="btn btn-outline-secondary" type="submit">Restablecer contraseña temporal</button></div>
                </form>
            </section>
        </div>
        <div class="col-lg-6">
            <section class="surface p-3 p-md-4" aria-labelledby="estado-titulo">
                <h2 class="section-heading" id="estado-titulo">Estado de la cuenta</h2>
                @if($cuenta->representante_vigente)
                    <p class="field-hint mb-0">Esta cuenta representa a su empresa. Usa el relevo de representante para sustituirla y conservar una representación activa.</p>
                @else
                    <p class="field-hint mb-4">Desactivar impide nuevas acciones, conservando participaciones, cargas e historial. El motivo es obligatorio.</p>
                    <form method="post" action="{{ route('cuentas.estado', $cuenta->id) }}" data-submit-label="Actualizando…">
                        @csrf
                        <input type="hidden" name="version_acceso" value="{{ $version }}">
                        <input type="hidden" name="_formulario" value="estado">
                        <input type="hidden" name="estado" value="{{ $cuenta->estado_cuenta === 'activa' ? 'inactiva' : 'activa' }}">
                        @include('cuentas._campo', ['name' => 'motivo', 'id' => 'estado-motivo', 'label' => 'Motivo del cambio de estado', 'type' => 'textarea', 'maxlength' => 1000, 'placeholder' => 'Ej. La persona concluyó sus estudios en la institución.', 'info' => 'Queda registrado en el historial de auditoría. Desactivar no borra la cuenta ni su historial; puede reactivarse después.', 'contexto' => 'estado'])
                        <div class="form-actions"><button class="btn {{ $cuenta->estado_cuenta === 'activa' ? 'btn-outline-danger' : 'btn-primary' }}" type="submit">{{ $cuenta->estado_cuenta === 'activa' ? 'Desactivar cuenta' : 'Activar cuenta' }}</button></div>
                    </form>
                @endif
            </section>
        </div>
        @if($cuenta->representante_vigente && $cuenta->empresa_id !== null)
            <div class="col-lg-6">
                <section class="surface p-3 p-md-4" aria-labelledby="relevo-titulo">
                    <h2 class="section-heading" id="relevo-titulo">Relevar representante</h2>
                    <p class="field-hint mb-4">Se creará una cuenta nueva para la misma empresa. La cuenta anterior quedará inactiva y conservará su autoría. Completa todos los campos.</p>
                    <form method="post" action="{{ route('cuentas.relevo', $cuenta->id) }}" data-submit-label="Creando…">
                        @csrf
                        <input type="hidden" name="_formulario" value="relevo">
                        @include('cuentas._campo', ['name' => 'nombre', 'id' => 'relevo-nombre', 'label' => 'Nombre del nuevo representante', 'maxlength' => 150, 'autocomplete' => 'name', 'placeholder' => 'Ej. Jorge Alberto Méndez Soto', 'contexto' => 'relevo'])
                        @include('cuentas._campo', ['name' => 'correo', 'id' => 'relevo-correo', 'label' => 'Correo del nuevo representante', 'type' => 'email', 'maxlength' => 254, 'autocomplete' => 'email', 'placeholder' => 'nombre@empresa.com', 'info' => 'Será el correo de acceso de la nueva cuenta. No puede pertenecer a otra cuenta existente.', 'contexto' => 'relevo'])
                        @include('cuentas._clave', ['prefijo' => 'relevo', 'contexto' => 'relevo'])
                        @include('cuentas._campo', ['name' => 'motivo', 'id' => 'relevo-motivo', 'label' => 'Motivo del relevo', 'type' => 'textarea', 'maxlength' => 1000, 'placeholder' => 'Ej. El representante anterior dejó de laborar en la empresa.', 'contexto' => 'relevo'])
                        <div class="form-actions"><button class="btn btn-outline-secondary" type="submit">Crear cuenta y relevar</button></div>
                    </form>
                </section>
            </div>
        @endif
    </div>
</section>
@endsection

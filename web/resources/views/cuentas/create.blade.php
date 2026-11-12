@extends('layouts.app')
@section('title', 'Crear cuenta | Banco de proyectos')

@section('content')
<section class="container workspace-section">
    <a class="back-link" href="{{ route('cuentas.index') }}">Volver a cuentas</a>
    <header class="page-header mt-3">
        <div>
            <h1 class="page-title">Crear cuenta</h1>
            <p class="page-description">Registra los datos de la persona y asigna su acceso.</p>
        </div>
    </header>
    <div class="row"><div class="col-lg-8 col-xl-7">
        @include('cuentas._errores')
        <form class="surface p-3 p-md-4" method="post" action="{{ route('cuentas.store') }}" data-submit-label="Creando…">
            @csrf
            <input type="hidden" name="_formulario" value="crear">
            <p class="field-hint mb-4">Los campos son obligatorios, excepto la razón social si el rol no es Empresa.</p>
            <fieldset class="form-section">
                <legend class="section-heading">Datos de la cuenta</legend>
                @include('cuentas._campo', ['name' => 'nombre', 'id' => 'crear-nombre', 'label' => 'Nombre completo', 'maxlength' => 150, 'autocomplete' => 'name', 'placeholder' => 'Ej. María Fernanda López Ruiz', 'info' => 'Nombre y apellidos tal como deben aparecer en el sistema; lo verán otros usuarios en solicitudes y avisos.'])
                @include('cuentas._campo', ['name' => 'correo', 'id' => 'crear-correo', 'label' => 'Correo de acceso', 'type' => 'email', 'maxlength' => 254, 'autocomplete' => 'email', 'placeholder' => 'nombre@ejemplo.com', 'info' => 'Es el correo con el que la persona iniciará sesión. Debe ser único: no puede estar en otra cuenta.'])
                <div class="mb-3">
                    <div class="label-row"><label class="form-label" for="crear-rol">Rol<span class="required-mark" aria-hidden="true">*</span></label><x-info tema="Rol" texto="Alumno: se postula a proyectos. Profesor: solicita dirigirlos. Empresa: publica proyectos. Administrador: revisa, autoriza y gestiona cuentas." /></div>
                    <select class="form-select @error('rol') is-invalid @enderror" name="rol" id="crear-rol" required aria-describedby="crear-rol-ayuda @error('rol') crear-rol-error @enderror" @error('rol') aria-invalid="true" @enderror>
                        <option value="">Selecciona un rol</option>
                        @foreach(['alumno' => 'Alumno', 'profesor' => 'Profesor', 'empresa' => 'Empresa', 'administrador' => 'Administrador'] as $value => $label)
                            <option value="{{ $value }}" @selected(old('rol') === $value)>{{ $label }}</option>
                        @endforeach
                    </select>
                    <p class="field-hint form-text" id="crear-rol-ayuda">El rol se asigna al crear la cuenta y no se puede modificar después.</p>
                    @error('rol')<p class="invalid-feedback" id="crear-rol-error">{{ $message }}</p>@enderror
                </div>
                @include('cuentas._campo', ['name' => 'razon_social', 'id' => 'crear-razon', 'label' => 'Razón social', 'required' => false, 'maxlength' => 250, 'placeholder' => 'Ej. Soluciones Digitales del Norte S.A. de C.V.', 'help' => 'Solo para el rol Empresa. La empresa y su representante se registran juntos.'])
            </fieldset>
            <fieldset class="form-section">
                <legend class="section-heading">Contraseña inicial</legend>
                @include('cuentas._clave', ['prefijo' => 'crear'])
                <p class="field-hint">La contraseña no se envía por correo. Entrégala a la persona por el canal acordado.</p>
            </fieldset>
            <div class="form-actions"><button class="btn btn-primary" type="submit">Crear cuenta</button><a class="btn btn-outline-secondary" href="{{ route('cuentas.index') }}">Cancelar</a></div>
        </form>
    </div></div>
</section>
@endsection


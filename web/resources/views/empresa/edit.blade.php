@extends('layouts.app')
@section('title', 'Datos de empresa · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Datos de empresa</h1><p class="page-description">Mantén actualizada la información y el contacto de tu empresa.</p></div></header>
    <div class="form-layout">
        <x-errores />
        <form class="surface" method="POST" action="{{ route('empresa.update') }}" data-submit-label="Guardando…">
            @csrf @method('PUT')
            <input type="hidden" name="version" value="{{ is_string(old('version', $empresa->version)) ? old('version', $empresa->version) : '' }}">
            <p class="field-hint mb-4">La razón social es obligatoria. Los demás datos son opcionales.</p>
            <fieldset class="form-section"><legend>Información de la empresa</legend>
                <x-campo name="razon_social" label="Razón social" :value="$empresa->razon_social" required maxlength="250" placeholder="Ej. Soluciones Digitales del Norte S.A. de C.V." info="Nombre legal registrado de la empresa. Es el que verán alumnos y profesores en el catálogo." />
                <div class="row"><div class="col-md-6"><x-campo name="sector" label="Sector" :value="$empresa->sector" maxlength="250" placeholder="Ej. Tecnologías de la información" /></div><div class="col-md-6"><x-campo name="identificacion" label="Identificación de la empresa" :value="$empresa->identificacion" maxlength="100" placeholder="Ej. RFC SDN201015AB3" info="Un dato que identifique oficialmente a la empresa, como su RFC. Es opcional." /></div></div>
            </fieldset>
            <fieldset class="form-section"><legend>Contacto</legend>
                <x-campo name="contacto_nombre" label="Nombre de contacto" :value="$empresa->contacto_nombre" maxlength="150" placeholder="Ej. Laura Martínez Gómez" autocomplete="name" />
                <x-campo name="contacto_correo" label="Correo de contacto" type="email" :value="$empresa->contacto_correo" maxlength="254" placeholder="contacto@empresa.com" help="Es el contacto de la empresa; no cambia tu correo de acceso." />
                <x-campo name="contacto_telefono" label="Teléfono de contacto" type="tel" :value="$empresa->contacto_telefono" maxlength="50" placeholder="Ej. 81 1234 5678" />
            </fieldset>
            <div class="form-actions"><button class="btn btn-primary" type="submit">Guardar datos</button><a class="btn btn-outline-secondary" href="{{ route('panel') }}">Volver a mi espacio</a></div>
        </form>
    </div>
</section>
@endsection

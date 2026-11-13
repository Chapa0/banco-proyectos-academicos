@extends('layouts.app')
@section('title', 'Mi perfil · Banco de proyectos')
@section('content')
<section class="container workspace-section">
    <header class="page-header"><div><h1 class="page-title">Mi perfil</h1><p class="page-description">{{ $rol === 'alumno' ? 'Datos académicos, contacto y habilidades para participar en proyectos.' : 'Datos académicos, contacto y experiencia para dirigir proyectos.' }}</p></div></header>
    <div class="form-layout">
        <x-errores />
        <x-avance-perfil :avance="$avance" class="surface mb-4" />
        <x-subir-imagen id="foto" class="mb-4" titulo="Foto de perfil" :imagen="$foto ?? null" :nombre="auth()->user()->nombre"
            descripcion="Ayuda a que la empresa y tu director te reconozcan. La ven quienes ya pueden consultar tu perfil."
            :accion-guardar="route('perfil.foto.store')" :accion-quitar="route('perfil.foto.destroy')" confirmar="¿Quitar tu foto de perfil? Se mostrarán tus iniciales." />
        <form class="surface" method="POST" action="{{ route('perfil.update') }}" data-submit-label="Guardando perfil…">
            @csrf @method('PUT')
            <input type="hidden" name="version" value="{{ is_string(old('version', $version)) ? old('version', $version) : '' }}">
            <p class="field-hint mb-4">{{ $rol === 'alumno' ? 'La matrícula es obligatoria. Los demás datos son opcionales.' : 'El número de empleado es obligatorio. Los demás datos son opcionales.' }}</p>
            <fieldset class="form-section">
                <legend>Datos académicos</legend>
                @if($rol === 'alumno')
                    <x-campo name="matricula" label="Matrícula" :value="$perfil?->matricula ?? ''" required maxlength="100" placeholder="Ej. 20231234" info="Tu número de matrícula escolar, tal como aparece en tu credencial. Identifica tu perfil ante empresas y administración." />
                    <div class="row"><div class="col-md-8"><x-campo name="carrera" label="Carrera" :value="$perfil?->carrera ?? ''" maxlength="250" placeholder="Ej. Ingeniería en Sistemas Computacionales" /></div><div class="col-md-4"><x-campo name="semestre" label="Semestre" type="number" :value="$perfil?->semestre ?? ''" min="1" max="32767" placeholder="Ej. 7" inputmode="numeric" /></div></div>
                    <x-campo name="datos_academicos" label="Formación y datos académicos" type="textarea" :value="$perfil?->datos_academicos ?? ''" maxlength="10000" placeholder="Ej. Promedio 9.1. Cursé Bases de datos, Programación web e Ingeniería de software. Certificación en Python básico." help="Describe tu formación o los conocimientos relevantes para los proyectos." />
                @else
                    <x-campo name="numero_empleado" label="Número de empleado" :value="$perfil?->numero_empleado ?? ''" required maxlength="100" placeholder="Ej. EMP-0457" info="El número que te asignó la institución como docente. Identifica tu perfil ante la administración." />
                    <x-campo name="especialidad" label="Áreas de especialidad" type="textarea" :value="$perfil?->especialidad ?? ''" maxlength="1000" rows="3" placeholder="Ej. Desarrollo web, bases de datos, ciberseguridad" info="Temas en los que puedes dirigir proyectos. Las empresas y la administración lo consultan al revisar tus solicitudes." />
                    <x-campo name="experiencia" label="Experiencia académica y profesional" type="textarea" :value="$perfil?->experiencia ?? ''" maxlength="10000" placeholder="Ej. 8 años como docente de Programación. Dirigí 5 proyectos de residencia con empresas locales." />
                @endif
            </fieldset>
            <fieldset class="form-section">
                <legend>Contacto</legend>
                <x-campo name="contacto_correo" label="Correo de contacto" type="email" :value="$perfil?->contacto_correo ?? ''" maxlength="254" placeholder="nombre@ejemplo.com" help="Este es el contacto de tu perfil. Guardarlo no cambia tu correo de acceso." />
                <x-campo name="contacto_telefono" label="Teléfono de contacto" type="tel" :value="$perfil?->contacto_telefono ?? ''" maxlength="50" placeholder="Ej. 81 1234 5678" />
            </fieldset>
            @if($rol === 'alumno')
                @include('perfil._habilidades')
            @endif
            <div class="form-actions"><button class="btn btn-primary" type="submit">Guardar perfil</button><x-volver boton :defecto="route('panel')" etiqueta="Volver a mi espacio" /></div>
        </form>
        @include('perfil._documentos')
    </div>
</section>
@endsection

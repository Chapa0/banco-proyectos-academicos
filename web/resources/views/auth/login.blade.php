@extends('layouts.app')
@section('title', 'Iniciar sesión · Banco de proyectos')
@section('content')
<section class="container auth-section" aria-labelledby="acceso-titulo">
    <div class="surface auth-surface">
        <h1 id="acceso-titulo" class="page-title">Iniciar sesión</h1>
        <p class="page-description">Usa la cuenta que te proporcionó el administrador.</p>
        @if(isset($mensajeLimite))<div class="alert alert-danger" role="alert">{{ $mensajeLimite }}</div>@endif
        <form method="POST" action="{{ route('login.store') }}" class="mt-4" data-submit-label="Entrando…" data-sin-aviso-salida>
            @csrf
            <div class="mb-3">
                <div class="label-row"><label for="correo" class="form-label">Correo</label><x-info tema="Correo" texto="Escribe el correo de la cuenta que te dio el administrador. Da igual si usas mayúsculas o minúsculas." /></div>
                <input id="correo" name="correo" type="email" value="{{ is_string(old('correo', $correoLogin ?? '')) ? old('correo', $correoLogin ?? '') : '' }}" autocomplete="username" placeholder="nombre@ejemplo.com" spellcheck="false" autocapitalize="none" required autofocus maxlength="254" class="form-control @error('correo') is-invalid @enderror" @error('correo') aria-invalid="true" aria-describedby="correo-error" @enderror>
                @error('correo')<div id="correo-error" class="invalid-feedback" role="alert">{{ $message }}</div>@enderror
            </div>
            <div class="mb-4">
                <div class="label-row"><label for="password" class="form-label">Contraseña</label><x-info tema="Contraseña" texto="En tu primer acceso usa la contraseña temporal que te dio el administrador; después el sistema te pedirá cambiarla." /></div>
                <input id="password" name="password" type="password" autocomplete="current-password" placeholder="Tu contraseña" data-password required class="form-control @error('password') is-invalid @enderror" @error('password') aria-invalid="true" aria-describedby="password-error" @enderror>
                @error('password')<div id="password-error" class="invalid-feedback" role="alert">{{ $message }}</div>@enderror
            </div>
            <button type="submit" class="btn btn-primary w-100">Entrar</button>
        </form>
        <p class="field-hint mt-4 mb-0">Si no recuerdas tu contraseña, solicita al administrador que la restablezca.</p>
    </div>
</section>
@endsection

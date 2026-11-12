@extends('layouts.app')
@section('title', 'Cambiar contraseña · Banco de proyectos')
@section('content')
<section class="container auth-section" aria-labelledby="clave-titulo">
    <div class="surface auth-surface">
        <h1 id="clave-titulo" class="page-title">Cambiar contraseña</h1>
        @if(auth()->user()->requiere_cambio_clave)
            <p class="page-description">Antes de continuar, cambia la contraseña que te entregó el administrador.</p>
        @else
            <p class="page-description">Al guardar se cerrarán tus otras sesiones.</p>
        @endif
        <form method="POST" action="{{ route('clave.update') }}" class="mt-4" data-submit-label="Guardando…">
            @csrf @method('PUT')
            <div class="mb-3">
                <div class="label-row"><label for="current_password" class="form-label">Contraseña actual</label><x-info tema="Contraseña actual" texto="Es la contraseña con la que entraste. Si es tu primer acceso, la temporal que te dio el administrador." /></div>
                <input id="current_password" name="current_password" type="password" autocomplete="current-password" placeholder="La contraseña con la que entraste" data-password required class="form-control @error('current_password') is-invalid @enderror" @error('current_password') aria-invalid="true" aria-describedby="actual-error" @enderror>
                @error('current_password')<div id="actual-error" class="invalid-feedback" role="alert">{{ $message }}</div>@enderror
            </div>
            <div class="mb-3">
                <div class="label-row"><label for="password" class="form-label">Nueva contraseña</label><x-info tema="Nueva contraseña" texto="Consejo: una frase de varias palabras es fácil de recordar y difícil de adivinar, por ejemplo «mi gato duerme en la azotea»." /></div>
                <input id="password" name="password" type="password" autocomplete="new-password" placeholder="Mínimo 12 caracteres" data-password data-password-length="12" required minlength="12" class="form-control @error('password') is-invalid @enderror" aria-describedby="clave-ayuda @error('password') nueva-error @enderror" @error('password') aria-invalid="true" @enderror>
                <div id="clave-ayuda" class="form-text">Usa al menos 12 caracteres y una contraseña diferente de la actual.</div>
                @error('password')<div id="nueva-error" class="invalid-feedback" role="alert">{{ $message }}</div>@enderror
            </div>
            <div class="mb-4">
                <label for="password_confirmation" class="form-label">Confirmar nueva contraseña</label>
                <input id="password_confirmation" name="password_confirmation" type="password" autocomplete="new-password" placeholder="Repite la nueva contraseña" data-password data-match="password" required minlength="12" class="form-control">
            </div>
            <div class="form-actions">
                <button class="btn btn-primary" type="submit">Guardar contraseña</button>
                @unless(auth()->user()->requiere_cambio_clave)<a class="btn btn-outline-secondary" href="{{ route('panel') }}">Cancelar</a>@endunless
            </div>
        </form>
    </div>
</section>
@endsection

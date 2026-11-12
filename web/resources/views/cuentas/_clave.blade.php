@php($mostrarError = !isset($contexto) || old('_formulario') === null || old('_formulario') === $contexto)
<div class="mb-3">
    <div class="label-row"><label class="form-label" for="{{ $prefijo }}-password">Contraseña temporal<span class="required-mark" aria-hidden="true">*</span></label><x-info tema="Contraseña temporal" texto="Solo sirve para el primer acceso: al entrar, el sistema pedirá a la persona que la cambie por una propia." /></div>
    <input class="form-control @if($mostrarError && $errors->has('password')) is-invalid @endif" type="password" name="password" id="{{ $prefijo }}-password"
        minlength="12" maxlength="72" autocomplete="new-password" placeholder="Mínimo 12 caracteres" data-password data-password-length="12" required aria-describedby="{{ $prefijo }}-ayuda @if($mostrarError && $errors->has('password')) {{ $prefijo }}-error @endif"
        @if($mostrarError && $errors->has('password')) aria-invalid="true" @endif>
    <p class="form-text field-hint" id="{{ $prefijo }}-ayuda">Al menos 12 caracteres y hasta 72 bytes. La persona deberá cambiarla al iniciar sesión.</p>
    @if($mostrarError && $errors->has('password'))<p class="invalid-feedback" id="{{ $prefijo }}-error">{{ $errors->first('password') }}</p>@endif
</div>
<div class="mb-3">
    <label class="form-label" for="{{ $prefijo }}-confirmacion">Confirmar contraseña temporal<span class="required-mark" aria-hidden="true">*</span></label>
    <input class="form-control" type="password" name="password_confirmation" id="{{ $prefijo }}-confirmacion" minlength="12" maxlength="72" autocomplete="new-password" placeholder="Repite la contraseña" data-password data-match="{{ $prefijo }}-password" required aria-describedby="{{ $prefijo }}-confirmacion-ayuda">
    <p class="form-text field-hint" id="{{ $prefijo }}-confirmacion-ayuda">Vuelve a escribir la misma contraseña.</p>
</div>

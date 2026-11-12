@php
    $usarAnterior = !isset($contexto) || old('_formulario') === null || old('_formulario') === $contexto;
    $valorCampo = $usarAnterior ? old($name, $valorInicial ?? '') : ($valorInicial ?? '');
    $valorCampo = is_scalar($valorCampo) ? (string) $valorCampo : '';
    $hayError = $usarAnterior && $errors->has($name);
    $descripcion = trim((isset($help) ? $id.'-ayuda ' : '').($hayError ? $id.'-error' : ''));
@endphp
<div class="mb-3">
    <div class="label-row">
        <label class="form-label" for="{{ $id }}">{{ $label }}@if($required ?? true)<span class="required-mark" aria-hidden="true">*</span>@endif</label>
        @isset($info)<x-info :texto="$info" :tema="$label" />@endisset
    </div>
    @if (($type ?? 'text') === 'textarea')
        <textarea class="form-control @if($hayError) is-invalid @endif" id="{{ $id }}" name="{{ $name }}" rows="3"
            @if($required ?? true) required @endif @if(isset($maxlength)) maxlength="{{ $maxlength }}" @endif @isset($placeholder) placeholder="{{ $placeholder }}" @endisset
            @if($hayError) aria-invalid="true" @endif @if($descripcion !== '') aria-describedby="{{ $descripcion }}" @endif>{{ $valorCampo }}</textarea>
    @else
        <input class="form-control @if($hayError) is-invalid @endif" type="{{ $type ?? 'text' }}" id="{{ $id }}" name="{{ $name }}" value="{{ $valorCampo }}"
            @if($required ?? true) required @endif @if(isset($maxlength)) maxlength="{{ $maxlength }}" @endif autocomplete="{{ $autocomplete ?? 'off' }}" @isset($placeholder) placeholder="{{ $placeholder }}" @endisset
            @if(($type ?? 'text') === 'email') spellcheck="false" autocapitalize="none" @endif
            @if($hayError) aria-invalid="true" @endif @if($descripcion !== '') aria-describedby="{{ $descripcion }}" @endif>
    @endif
    @isset($help)<p class="form-text field-hint" id="{{ $id }}-ayuda">{{ $help }}</p>@endisset
    @if($hayError)<p class="invalid-feedback" id="{{ $id }}-error">{{ $errors->first($name) }}</p>@endif
</div>

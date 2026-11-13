@props(['name', 'label', 'value' => '', 'type' => 'text', 'required' => false, 'maxlength' => null, 'help' => null, 'rows' => 4, 'min' => null, 'max' => null, 'inputId' => null, 'placeholder' => null, 'info' => null, 'autocomplete' => null, 'inputmode' => null, 'aislado' => false])
{{-- aislado: ignora old() y errores de otros formularios con campos del mismo nombre en la página (UX-10). --}}
@php
    $id = $inputId ?? 'campo-'.str_replace(['.', '[', ']'], '-', $name);
    $anterior = $aislado ? $value : old($name, $value);
    $conError = ! $aislado && $errors->has($name);
    $valor = is_scalar($anterior) ? (string) $anterior : '';
    $descripcion = trim(($help ? $id.'-ayuda ' : '').($conError ? $id.'-error' : ''));
    $autocompletar = $autocomplete ?? match ($type) { 'email' => 'email', 'tel' => 'tel', default => null };
@endphp
<div class="mb-4">
    <div class="label-row">
        <label for="{{ $id }}" class="form-label">{{ $label }}@if($required)<span class="required-mark" aria-hidden="true">*</span><span class="visually-hidden"> (obligatorio)</span>@endif</label>
        @if($info)<x-info :texto="$info" :tema="$label" />@endif
    </div>
    @if($type === 'textarea')
        <textarea id="{{ $id }}" name="{{ $name }}" rows="{{ $rows }}" class="form-control @if($conError) is-invalid @endif" @required($required) @if($maxlength !== null) maxlength="{{ $maxlength }}" @endif @if($placeholder) placeholder="{{ $placeholder }}" @endif @if($descripcion) aria-describedby="{{ $descripcion }}" @endif @if($conError) aria-invalid="true" @endif>{{ $valor }}</textarea>
    @else
        <input id="{{ $id }}" name="{{ $name }}" type="{{ $type }}" value="{{ $valor }}" class="form-control @if($conError) is-invalid @endif" @required($required) @if($maxlength !== null) maxlength="{{ $maxlength }}" @endif @if($min !== null) min="{{ $min }}" @endif @if($max !== null) max="{{ $max }}" @endif @if($placeholder) placeholder="{{ $placeholder }}" @endif @if($autocompletar) autocomplete="{{ $autocompletar }}" @endif @if($inputmode) inputmode="{{ $inputmode }}" @endif @if($type === 'email') spellcheck="false" autocapitalize="none" @endif @if($descripcion) aria-describedby="{{ $descripcion }}" @endif @if($conError) aria-invalid="true" @endif>
    @endif
    @if($help)<p class="form-text" id="{{ $id }}-ayuda">{{ $help }}</p>@endif
    @if($conError)<p class="invalid-feedback" id="{{ $id }}-error">{{ $errors->first($name) }}</p>@endif
</div>

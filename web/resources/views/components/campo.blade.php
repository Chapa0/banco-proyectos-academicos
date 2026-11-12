@props(['name', 'label', 'value' => '', 'type' => 'text', 'required' => false, 'maxlength' => null, 'help' => null, 'rows' => 4, 'min' => null, 'max' => null, 'inputId' => null, 'placeholder' => null, 'info' => null, 'autocomplete' => null, 'inputmode' => null])
@php
    $id = $inputId ?? 'campo-'.str_replace(['.', '[', ']'], '-', $name);
    $anterior = old($name, $value);
    $valor = is_scalar($anterior) ? (string) $anterior : '';
    $descripcion = trim(($help ? $id.'-ayuda ' : '').($errors->has($name) ? $id.'-error' : ''));
    $autocompletar = $autocomplete ?? match ($type) { 'email' => 'email', 'tel' => 'tel', default => null };
@endphp
<div class="mb-4">
    <div class="label-row">
        <label for="{{ $id }}" class="form-label">{{ $label }}@if($required)<span class="required-mark" aria-hidden="true">*</span><span class="visually-hidden"> (obligatorio)</span>@endif</label>
        @if($info)<x-info :texto="$info" :tema="$label" />@endif
    </div>
    @if($type === 'textarea')
        <textarea id="{{ $id }}" name="{{ $name }}" rows="{{ $rows }}" class="form-control @error($name) is-invalid @enderror" @required($required) @if($maxlength !== null) maxlength="{{ $maxlength }}" @endif @if($placeholder) placeholder="{{ $placeholder }}" @endif @if($descripcion) aria-describedby="{{ $descripcion }}" @endif @error($name) aria-invalid="true" @enderror>{{ $valor }}</textarea>
    @else
        <input id="{{ $id }}" name="{{ $name }}" type="{{ $type }}" value="{{ $valor }}" class="form-control @error($name) is-invalid @enderror" @required($required) @if($maxlength !== null) maxlength="{{ $maxlength }}" @endif @if($min !== null) min="{{ $min }}" @endif @if($max !== null) max="{{ $max }}" @endif @if($placeholder) placeholder="{{ $placeholder }}" @endif @if($autocompletar) autocomplete="{{ $autocompletar }}" @endif @if($inputmode) inputmode="{{ $inputmode }}" @endif @if($type === 'email') spellcheck="false" autocapitalize="none" @endif @if($descripcion) aria-describedby="{{ $descripcion }}" @endif @error($name) aria-invalid="true" @enderror>
    @endif
    @if($help)<p class="form-text" id="{{ $id }}-ayuda">{{ $help }}</p>@endif
    @error($name)<p class="invalid-feedback" id="{{ $id }}-error">{{ $message }}</p>@enderror
</div>

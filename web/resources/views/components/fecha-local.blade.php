@props(['valor'])
@php
    $fecha = $valor ? \Carbon\CarbonImmutable::parse($valor)->setTimezone('America/Mexico_City') : null;
@endphp
@if($fecha)<time datetime="{{ $fecha->toIso8601String() }}" title="Hora del centro de México">{{ $fecha->format('d/m/Y H:i') }}</time>@else<span>Sin registrar</span>@endif

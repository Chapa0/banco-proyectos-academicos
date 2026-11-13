@props(['defecto', 'etiqueta', 'boton' => false])
{{-- NAV-01: regresa a la página de origen si llegó en ?volver=; si no, a la lista de la sección. --}}
@php
    $destinoRegreso = \App\Support\Regreso::destino($defecto, $etiqueta);
@endphp
@if($boton)
<a {{ $attributes->merge(['class' => 'btn btn-outline-secondary']) }} href="{{ $destinoRegreso['url'] }}">{{ $destinoRegreso['etiqueta'] }}</a>
@else
<a {{ $attributes->merge(['class' => 'back-link']) }} href="{{ $destinoRegreso['url'] }}"><i class="bi bi-arrow-left me-2" aria-hidden="true"></i>{{ $destinoRegreso['etiqueta'] }}</a>
@endif

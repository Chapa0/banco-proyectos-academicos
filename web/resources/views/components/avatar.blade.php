@props(['imagen' => null, 'nombre' => '', 'tamano' => 'md', 'logo' => false, 'alt' => null])
{{-- UX-08: foto o logo si existe y el actor puede verlo; si no, iniciales. Sin texto alternativo por defecto
     porque el nombre siempre aparece junto a la imagen. --}}
@php
    $iniciales = collect(preg_split('/\s+/u', trim((string) $nombre)))->filter()->take(2)
        ->map(fn ($p) => mb_strtoupper(mb_substr($p, 0, 1)))->implode('');
@endphp
@if($imagen)
    <img {{ $attributes->class(['avatar', 'avatar-'.$tamano, 'is-logo' => $logo]) }} src="{{ route('imagenes.show', $imagen) }}" alt="{{ $alt ?? '' }}" width="{{ \App\Services\ImagenService::LADO }}" height="{{ \App\Services\ImagenService::LADO }}" loading="lazy" decoding="async">
@else
    <span {{ $attributes->class(['avatar', 'avatar-'.$tamano, 'avatar-initials', 'is-logo' => $logo]) }} aria-hidden="true">{{ $iniciales ?: '?' }}</span>
@endif
